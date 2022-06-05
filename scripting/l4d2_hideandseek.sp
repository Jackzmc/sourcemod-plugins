#pragma semicolon 1
#pragma newdecls required

//#define DEBUG

#define PLUGIN_VERSION "1.0"
#define DEBUG_BLOCKERS 1
// #define FORCE_ENABLED 1
#define DEBUG_LOG_MAPSTART 1

#include <sourcemod>
#include <sdktools>
#include <left4dhooks>
#include <sceneprocessor>
#if defined DEBUG_BLOCKERS
#include <smlib/effects>
int g_iLaserIndex;
#endif
//#include <sdkhooks>

public Plugin myinfo = 
{
	name =  "L4D2 Hide & Seek", 
	author = "jackzmc", 
	description = "", 
	version = PLUGIN_VERSION, 
	url = ""
};

/*
script g_ModeScript.DeepPrintTable(g_ModeScript.MutationState)
{
   MapName      = "c6m2_bedlam"
   StartActive  = true
   CurrentSlasher       = ([1] player)
   MapTime      = 480
   StateTick    = 464
   LastGiveAdren        = 10
   ModeName     = "hideandseek"
   Tick = 484
   CurrentStage = 3
   SlasherLastStumbled  = 0
}
*/

#define SOUND_SUSPENSE_1 "custom/suspense1.mp3"
#define SOUND_SUSPENSE_1_FAST "custom/suspense1fast.mp3"

enum GameState {
	State_Unknown = -1,
	State_Startup,
	State_Hiding,
	State_Restarting,
	State_Hunting
}

static char gamemode[32], currentMap[64];
static bool isEnabled, lateLoaded;

static bool isPendingPlay[MAXPLAYERS+1];
static bool isNavBlockersEnabled = true, isPropsEnabled = true, isPortalsEnabled = true;
static bool isNearbyPlaying[MAXPLAYERS+1];
static bool wasThirdPersonVomitted[MAXPLAYERS+1];
static bool gameOver;
static int currentSeeker;
static int currentPlayers = 0;

static const float DEFAULT_SCALE[3] = { 5.0, 5.0, 5.0 };

static ArrayList validMaps;
static ArrayList validSets;

static KeyValues kv;
static StringMap mapConfigs;
static char currentSet[16] = "default";

static Handle suspenseTimer, thirdPersonTimer;

static char nextRoundMap[64];
static int mapChangeMsgTicks = 5;

// TODO: Disable weapon drop

enum struct EntityConfig {
	float origin[3];
	float rotation[3];
	char type[32];
	char model[64];
	float scale[3];
	float offset[3];
}

enum struct MapConfig {
	ArrayList entities;
	ArrayList inputs;
	float spawnpoint[3];
	bool hasSpawnpoint;
	int mapTime;
}

static MapConfig mapConfig;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
	lateLoaded = late;
	return APLRes_Success;
}

public void OnPluginStart() {
	EngineVersion g_Game = GetEngineVersion();
	if(g_Game != Engine_Left4Dead2) {
		SetFailState("This plugin is for L4D2 only.");	
	}

	validMaps = new ArrayList(ByteCountToCells(64));
	validSets = new ArrayList(ByteCountToCells(16));
	mapConfigs = new StringMap();

	if(!ReloadMapDB()) {
		SetFailState("Could not load entity config from data/hideandseek.cfg");
	}

	ConVar hGamemode = FindConVar("mp_gamemode"); 
	hGamemode.GetString(gamemode, sizeof(gamemode));
	hGamemode.AddChangeHook(Event_GamemodeChange);
	Event_GamemodeChange(hGamemode, gamemode, gamemode);

	if(lateLoaded) {
		int seeker = GetSlasher();
		if(seeker > -1) {
			currentSeeker = seeker;
			PrintToServer("[H&S] Late load, found seeker %N", currentSeeker);
		}
		if(IsGameSoloOrPlayersLoading()) {
			Handle timer = CreateTimer(10.0, Timer_KeepWaiting, _, TIMER_REPEAT);
			TriggerTimer(timer);
			PrintToServer("[H&S] Late load, player(s) are connecting, or solo. Waiting...");
			SetState(State_Startup);
		}
	}

	RegConsoleCmd("sm_joingame", Command_Join, "Joins or joins someone else");
	RegAdminCmd("sm_hs", Command_HideAndSeek, ADMFLAG_CHEATS, "The main command. see /hs help");

}

bool ReloadMapDB() {
	if(kv != null) {
		delete kv;
	}
	kv = new KeyValues("hideandseek");

	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "data/hideandseek.cfg");


	if(!FileExists(sPath) || !kv.ImportFromFile(sPath)) {
		delete kv;
		return false;
	}

	validMaps.Clear();

	char map[64];
	kv.GotoFirstSubKey(true);
	do {
		kv.GetSectionName(map, sizeof(map));
		validMaps.PushString(map);
	} while(kv.GotoNextKey(true));
	kv.GoBack();
	return true;
}

public Action Command_HideAndSeek(int client, int args) {
	if(args > 0) {
		char subcmd[16];
		GetCmdArg(1, subcmd, sizeof(subcmd));
		if(StrEqual(subcmd, "r") || StrEqual(subcmd, "reload", false)) {
			GetCurrentMap(currentMap, sizeof(currentMap));
			char arg[16];
			GetCmdArg(2, arg, sizeof(arg));
			if(ReloadMapDB()) {
				if(!LoadConfigForMap(currentMap)) {
					ReplyToCommand(client, "Warn: Map has no config file");
				}
				Cleanup();
				if(arg[0] == 'f') {
					CreateTimer(0.1, Timer_RoundStart);
				}
				SetupEntities(isNavBlockersEnabled, isPropsEnabled, isPortalsEnabled);
				ReplyToCommand(client, "Reloaded map from config");
			} else {
				ReplyToCommand(client, "Error occurred while reloading map file");
			}
		} else if(StrEqual(subcmd, "set", false)) {
			if(args == 1) {
				ReplyToCommand(client, "Current Map Set: \"%s\" (Specify with /hs set <set>)", currentSet);
				if(validSets.Length == 0) ReplyToCommand(client, "Available Sets: (no map config found)");
				else { 
					ReplyToCommand(client, "Available Sets: ");
					char set[16];
					for(int i = 0; i < validSets.Length; i++) {
						validSets.GetString(i, set, sizeof(set));
						ReplyToCommand(client, "%d.  %s", i + 1, set);
					}
				}
			} else {
				GetCmdArg(2, currentSet, sizeof(currentSet));
				if(!LoadConfigForMap(currentMap)) {
					ReplyToCommand(client, "Warn: Map has no config file");
				}
				Cleanup();
				SetupEntities(isNavBlockersEnabled, isPropsEnabled, isPortalsEnabled);
				ReplyToCommand(client, "Set the current set to \"%s\"", currentSet);
			}
		} else if(StrEqual(subcmd, "toggle")) {
			char type[32];
			GetCmdArg(2, type, sizeof(type));
			bool doAll = StrEqual(type, "all");
			bool isUnknown = true;

			if(doAll || StrEqual(type, "blockers", false)) {
				if(isNavBlockersEnabled) {
					EntFire("hsblocker", "Disable");
					ReplyToCommand(client, "Disabled all custom gamemode blockers");
				} else {
					EntFire("hsblocker", "Enable");
					ReplyToCommand(client, "Enabled all custom gamemode blockers");
				}
				isNavBlockersEnabled = !isNavBlockersEnabled;
				isUnknown = false;
			} 
			if(doAll || StrEqual(type, "props", false)) {
				if(isPropsEnabled) {
					EntFire("hsprop", "Disable");
					EntFire("hsprop", "DisableCollision");
					ReplyToCommand(client, "Disabled all custom gamemode props");
				} else {
					EntFire("hsprop", "Enable");
					EntFire("hsprop", "EnableCollision");
					ReplyToCommand(client, "Enabled all custom gamemode props");
				}
				isPropsEnabled = !isPropsEnabled;
				isUnknown = false;
			}
			if(doAll || StrEqual(type, "portals", false)) {
				if(isPortalsEnabled) {
					EntFire("hsportal", "Disable");
					ReplyToCommand(client, "Disabled all custom gamemode portals");
				} else {
					EntFire("hsportal", "Enable");
					ReplyToCommand(client, "Enabled all custom gamemode portals");
				}
				isPortalsEnabled = !isPortalsEnabled;
				isUnknown = false;
			}
			if(isUnknown) ReplyToCommand(client, "Specify the type to affect: 'blockers', 'props', 'portals', or 'all'");
		} else if(StrEqual(subcmd, "clear", false)) {
			static char arg[16];
			GetCmdArg(2, arg, sizeof(arg));
			bool doAll = StrEqual(arg, "all");
			bool isUnknown = true;

			if(doAll || StrEqual(arg, "props")) {
				EntFire("hsprop", "kill");
				ReplyToCommand(client, "Removed all custom gamemode props");
				isUnknown = false;
			} 
			if(doAll || StrEqual(arg, "blockers")) {
				EntFire("hsblocker", "kill");
				ReplyToCommand(client, "Removed all custom gamemode blockers");
				isUnknown = false;
			}
			if(doAll || StrEqual(arg, "portals")) {
				EntFire("hsportal", "kill");
				ReplyToCommand(client, "Removed all custom gamemode portals");
				isUnknown = false;
			}
			if(isUnknown) ReplyToCommand(client, "Specify the type to affect: 'blockers', 'props', 'portals', or 'all'");
		} else if(StrEqual(subcmd, "settime")) {
			int prev = GetMapTime();
			static char arg[16];
			GetCmdArg(2, arg, sizeof(arg));
			int time = StringToInt(arg);
			mapConfig.mapTime = time;
			SetMapTime(time);
			ReplyToCommand(client, "Map's time is temporarily set to %d seconds (was %d)", time, prev);
		} else if(StrEqual(subcmd, "settick")) {
			static char arg[16];
			GetCmdArg(2, arg, sizeof(arg));
			int tick = -StringToInt(arg);
			SetTick(tick);
			ReplyToCommand(client, "Set tick time to %d", tick);
		} else if(StrEqual(subcmd, "map")) {
			static char arg[16];
			GetCmdArg(2, arg, sizeof(arg));
			if(StrEqual(arg, "list")) {
				ReplyToCommand(client, "See the console for available maps");
				char map[64];
				for(int i = 0; i < validMaps.Length; i++) {
					validMaps.GetString(i, map, sizeof(map));
					PrintToConsole(client, "%d. %s", i + 1, map);
				}
			} else if(StrEqual(arg, "random")) {
				bool foundMap;
				char map[64];
				do {
					int mapIndex = GetURandomInt() % validMaps.Length;
					validMaps.GetString(mapIndex, map, sizeof(map));
					if(!StrEqual(currentMap, map, false)) {
						foundMap = true;
					}
				} while(!foundMap);
				PrintToChatAll("[H&S] Switching map to %s", map);
				ChangeMap(map);
			} else if(StrEqual(arg, "next", false)) {
				if(args == 1) {
					ReplyToCommand(client, "Specify the map to change on the next round: 'next <map>'");
				} else {
					char arg2[64];
					GetCmdArg(2, arg2, sizeof(arg2));
					if(IsMapValid(arg2)) { 
						strcopy(nextRoundMap, sizeof(nextRoundMap), arg2);
						PrintToChatAll("[H&S] Switching map next round to %s", arg2);
						ForceChangeLevel(arg, "SetMapSelect");
					} else {
						ReplyToCommand(client, "Map is not valid");
					}
				}
			} else if(StrEqual(arg, "force", false)) {
				if(args == 1) {
					ReplyToCommand(client, "Specify the map to change to: 'force <map>'");
				} else {
					char arg2[64];
					GetCmdArg(2, arg2, sizeof(arg2));
					if(IsMapValid(arg2)) { 
						PrintToChatAll("[H&S] Switching map to %s", arg2);
						ChangeMap(arg2);
					} else {
						ReplyToCommand(client, "Map is not valid");
					}
				}
			} else {
				ReplyToCommand(client, "Syntax: 'map <list/random/force <mapname>/next <mapname>>");
			}
			return Plugin_Handled;
		} else if(StrEqual(subcmd, "pos", false)) {
			float pos[3];
			GetAbsOrigin(client, pos);
			ReplyToCommand(client, "\"origin\" \"%f %f %f\"", pos[0], pos[1], pos[2]);
			GetClientEyeAngles(client, pos);
			ReplyToCommand(client, "\"rotation\" \"%f %f %f\"", pos[0], pos[1], pos[2]);
		} else if(StrEqual(subcmd, "prop", false)) {
			float pos[3];
			GetAbsOrigin(client, pos);
			ReplyToCommand(client, "\"MYPROP\"");
			ReplyToCommand(client, "{");
			ReplyToCommand(client, "\t\"origin\" \"%f %f %f\"", pos[0], pos[1], pos[2]);
			GetClientAbsAngles(client, pos);
			ReplyToCommand(client, "\t\"rotation\" \"%f %f %f\"", pos[0], pos[1], pos[2]);
			ReplyToCommand(client, "\t\"type\" \"prop_dynamic\"");
			ReplyToCommand(client, "\t\"model\" \"props_junk/dumpster_2.mdl\"");
			ReplyToCommand(client, "}");
		} else if(StrEqual(subcmd, "setspawn", false)) {
			GetClientAbsOrigin(client, mapConfig.spawnpoint);
			ReplyToCommand(client, "Set map's temporarily spawnpoint to your location.");
		} else if(StrEqual(subcmd, "stuck")) {
			TeleportEntity(client, mapConfig.spawnpoint, NULL_VECTOR, NULL_VECTOR);
		} else if(StrEqual(subcmd, "bots")) {
			if(args == 2) {
				char arg[16];
				GetCmdArg(2, arg, sizeof(arg));
				if(StrEqual(arg, "toggle")) {
					bool newValue = !IsBotsEnabled();
					SetBotsEnabled(newValue);
					if(newValue) ReplyToCommand(client, "Bots are now enabled");
					else ReplyToCommand(client, "Bots are now disabled");
					return Plugin_Handled;
				} else if(StrEqual(arg, "on") || StrEqual(arg, "true")) {
					SetBotsEnabled(true);
					ReplyToCommand(client, "Bots are now enabled");
					return Plugin_Handled;
				} else if(StrEqual(arg, "off") || StrEqual(arg, "false")) {
					SetBotsEnabled(false);
					ReplyToCommand(client, "Bots are now disabled");
					return Plugin_Handled;
				}
			}
			if(IsBotsEnabled()) ReplyToCommand(client, "Bots are enabled");
			else ReplyToCommand(client, "Bots are disabled");
		}
		return Plugin_Handled;
	}
	ReplyToCommand(client, " - Hide & Seek Commands -");
	ReplyToCommand(client, "toggle <blockers/props/all>: Toggles all specified");
	ReplyToCommand(client, "set [new set]: Change the prop set or view current");
	ReplyToCommand(client, "clear <props/blockers/all>: Clear all specified");
	ReplyToCommand(client, "settime [seconds]: Sets the time override for the map");
	ReplyToCommand(client, "settick [tick]: Sets the current tick timer value");
	ReplyToCommand(client, "setspawn: Sets the temporary spawnpoint for the map");
	ReplyToCommand(client, "stuck: Teleports you to spawn to unstuck yourself");
	ReplyToCommand(client, "bots [toggle, [value]]: View if bots are enabled, or turn them on");
	return Plugin_Handled;
}


public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs) {
	if(isEnabled) {
		if(!StrEqual(command, "say")) { //Is team message
			if(currentSeeker <= 0 || currentSeeker == client) {
				return Plugin_Continue;
			}
			for(int i = 1; i <= MaxClients; i++) {
				if(IsClientConnected(i) && IsClientInGame(i) && i != currentSeeker)
					PrintToChat(i, "[Hiders] %N: %s", client, sArgs);
			}
			return Plugin_Handled;
		}
	}
	return Plugin_Continue;
}

bool LoadConfigForMap(const char[] map) {
	kv.Rewind();
	if (kv.JumpToKey(map)) {
		MapConfig config;
		config.entities = new ArrayList(sizeof(EntityConfig));
		config.inputs = new ArrayList(ByteCountToCells(64));
		validSets.Clear();
		if(kv.JumpToKey("ents")) {
			kv.GotoFirstSubKey();
			char entSet[16];
			do {
				EntityConfig entCfg;
				kv.GetVector("origin", entCfg.origin, NULL_VECTOR);
				kv.GetVector("rotation", entCfg.rotation, NULL_VECTOR);
				kv.GetString("type", entCfg.type, sizeof(entCfg.type), "env_physics_blocker");
				kv.GetString("model", entCfg.model, sizeof(entCfg.model), "");
				if(entCfg.model[0] != '\0')
					Format(entCfg.model, sizeof(entCfg.model), "models/%s", entCfg.model);
				kv.GetVector("scale", entCfg.scale, DEFAULT_SCALE);
				kv.GetVector("offset", entCfg.offset, NULL_VECTOR);
				kv.GetString("set", entSet, sizeof(entSet), "default");
				if(validSets.FindString(entSet) == -1) {
					validSets.PushString(entSet);
				}
				if(StrEqual(currentSet, entSet, false)) {
					config.entities.PushArray(entCfg);
				}
			} while (kv.GotoNextKey());
			// JumpToKey and GotoFirstSubKey both traverse, i guess, go back
			kv.GoBack();
			kv.GoBack();
		}
		if(kv.JumpToKey("inputs")) {
			// Use 'false' to propery grab
			// "key"	"value" in a section
			kv.GotoFirstSubKey(false);
			static char buffer[64];
			do {
				kv.GetSectionName(buffer, sizeof(buffer));
				config.inputs.PushString(buffer);

				kv.GetString(NULL_STRING, buffer, sizeof(buffer));
				config.inputs.PushString(buffer);
			} while (kv.GotoNextKey(false));
			kv.GoBack();
		}
		int mapTime;

		config.hasSpawnpoint = false;
		if(kv.JumpToKey("sets")) {
			char set[16];
			kv.GotoFirstSubKey(true);
			do {
				kv.GetSectionName(set, sizeof(set));
				if(validSets.FindString(set) == -1) {
					validSets.PushString(set);
				}
				if(StrEqual(currentSet, set, false)) {
					kv.GetVector("spawnpoint", config.spawnpoint);
					if(config.spawnpoint[0] != 0.0 && config.spawnpoint[1] != 0.0 && config.spawnpoint[2] != 0.0) {
						PrintToServer("[H&S] Using provided custom spawnpoint for set %s at %0.1f, %0.1f, %0.1f", currentSet, config.spawnpoint[0], config.spawnpoint[1], config.spawnpoint[2]);
						config.hasSpawnpoint = true;
					} 
					mapTime = kv.GetNum("maptime", 0);
				}
			} while(kv.GotoNextKey(true));
			kv.GoBack();
		}
		
		if(!config.hasSpawnpoint) {
			kv.GetVector("spawnpoint", config.spawnpoint);
			if(config.spawnpoint[0] != 0.0 && config.spawnpoint[1] != 0.0 && config.spawnpoint[2] != 0.0) {
				PrintToServer("[H&S] Using provided custom spawnpoint at %0.1f, %0.1f, %0.1f", config.spawnpoint[0], config.spawnpoint[1], config.spawnpoint[2]);
				config.hasSpawnpoint = true;
			} else if (GetSpawnPosition(config.spawnpoint, false)) {
				PrintToServer("[H&S] Using map spawnpoint at %0.1f, %0.1f, %0.1f", config.spawnpoint[0], config.spawnpoint[1], config.spawnpoint[2]);
				config.hasSpawnpoint = true;
			} else {
				PrintToServer("[H&S] Could not find any spawnpoints, using default spawn");
				config.hasSpawnpoint = false;
			}
		}

		// Use default maptime if exists
		if(mapTime == 0)
			mapTime = kv.GetNum("maptime", 0);
		if(mapTime > 0) {
			config.mapTime = mapTime;
			PrintToServer("[H&S] Map time overwritten to %d seconds", mapTime);
		}
		mapConfigs.SetArray(map, config, sizeof(MapConfig));
		// Discard entInputs if unused
		if(config.inputs.Length == 0) {
			delete config.inputs;
		}
		mapConfig = config;
		return true;
	} else {
		mapConfig.hasSpawnpoint = false;
		PrintToServer("[H&S] No map config exists for %s", map);
		return false;
	}
}

public Action Command_Join(int client, int args) {
	static float tpLoc[3];
	GetSpawnPosition(tpLoc);
	if(args == 1) {
		static char arg1[32];
		GetCmdArg(1, arg1, sizeof(arg1));
		char target_name[MAX_TARGET_LENGTH];
		int target_list[MAXPLAYERS], target_count;
		bool tn_is_ml;
		if ((target_count = ProcessTargetString(
				arg1,
				client,
				target_list,
				MAXPLAYERS,
				0,
				target_name,
				sizeof(target_name),
				tn_is_ml)) <= 0)
		{
			/* This function replies to the admin with a failure message */
			ReplyToTargetError(client, target_count);
			return Plugin_Handled;
		}
		for (int i = 0; i < target_count; i++) {
			int target = target_list[i];
			if(GetClientTeam(target) != 2) {
				ChangeClientTeam(target, 2);
				L4D_RespawnPlayer(target);
				TeleportEntity(target, tpLoc, NULL_VECTOR, NULL_VECTOR);
				isPendingPlay[client] = false;
				CheatCommand(target, "give", "knife");
			}
		}
		ReplyToCommand(client, "Joined %s", target_name);
	} else {
		if(currentSeeker == client) {
			ReplyToCommand(client, "You are already in-game as a seeker.");
			return Plugin_Handled;
		}
		isPendingPlay[client] = false;
		ChangeClientTeam(client, 2);
		L4D_RespawnPlayer(client);
		TeleportEntity(client, tpLoc, NULL_VECTOR, NULL_VECTOR);
		CheatCommand(client, "give", "knife");
	}
	return Plugin_Handled;
}

public void OnClientConnected(int client) {
	if(!IsFakeClient(client)) {
		currentPlayers++;
		if(isEnabled) {
			GameState state = GetState();
			if(currentPlayers == 1 && state == State_Startup) {
				CreateTimer(10.0, Timer_KeepWaiting, _, TIMER_REPEAT);
			}
		}
	}
}

public Action Timer_KeepWaiting(Handle h) {
	SetTick(-40);
	SetState(State_Startup);
	PrintHintTextToAll("Waiting for players to join...");
	return IsGameSoloOrPlayersLoading() ? Plugin_Continue : Plugin_Stop;
}

public void OnClientDisconnect(int client) {
	if(!IsFakeClient(client))
		currentPlayers--;
}

public void OnMapStart() {
	if(!isEnabled) return;

	currentSeeker = 0;

	char map[64];
	GetCurrentMap(map, sizeof(map));

	if(!StrEqual(currentMap, map)) {
		PrintToServer("[H&S] Map changed, loading fresh config");
		strcopy(currentMap, sizeof(currentMap), map);
		if(!mapConfigs.GetArray(map, mapConfig, sizeof(MapConfig))) {
			LoadConfigForMap(map);
		}
		strcopy(currentSet, sizeof(currentSet), "default");
	}

	#if defined DEBUG_BLOCKERS
	g_iLaserIndex = PrecacheModel("materials/sprites/laserbeam.vmt");
	#endif
	PrecacheSound(SOUND_SUSPENSE_1);
	PrecacheSound(SOUND_SUSPENSE_1_FAST);
	AddFileToDownloadsTable("sound/custom/suspense1.mp3");
	AddFileToDownloadsTable("sound/custom/suspense1fast.mp3");

	if(lateLoaded) {
		lateLoaded = false;
		SetupEntities();
	}
}

public Action L4D2_OnChangeFinaleStage(int &finaleType, const char[] arg) {
	if(isEnabled) {
		finaleType = 0;
		return Plugin_Changed;
	}
	return Plugin_Continue;
}


public void Event_GamemodeChange(ConVar cvar, const char[] oldValue, const char[] newValue) {
	cvar.GetString(gamemode, sizeof(gamemode));
	#if defined FORCE_ENABLED
		isEnabled = true;
		PrintToServer("[H&S] Force-enabled debug");
	#else
		isEnabled = StrEqual(gamemode, "hideandseek", false);
	#endif
	if(isEnabled) {
		HookEvent("round_end", Event_RoundEnd);
		HookEvent("round_start_post_nav", Event_RoundStart);
		HookEvent("item_pickup", Event_ItemPickup);
		HookEvent("player_death", Event_PlayerDeath);
		SetupEntities();
		CreateTimer(12.0, Timer_RoundStart);
		if(suspenseTimer != null)
			delete suspenseTimer;
		suspenseTimer = CreateTimer(20.0, Timer_Music, _, TIMER_REPEAT);
		if(thirdPersonTimer != null)
			delete thirdPersonTimer;
		thirdPersonTimer = CreateTimer(1.0, Timer_CheckPlayers, _, TIMER_REPEAT);
		if(!lateLoaded) {
			for(int i = 1; i <= MaxClients; i++) {
				if(IsClientConnected(i) && IsClientInGame(i))
					ForcePlayerSuicide(i);
			}
		}
	} else if(!lateLoaded && suspenseTimer != null) {
		UnhookEvent("round_end", Event_RoundEnd);
		UnhookEvent("round_start", Event_RoundStart);
		UnhookEvent("item_pickup", Event_ItemPickup);
		UnhookEvent("player_death", Event_PlayerDeath);
		Cleanup();
		delete suspenseTimer;
		delete thirdPersonTimer;
	}
}


public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) { 
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(!gameOver && client && GetClientTeam(client) == 2) {
		int alive = 0;
		for(int i = 1; i <= MaxClients; i++) {
			if(IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i)) {
				alive++;
			}
		}
		if(client == currentSeeker) {
			PrintToChatAll("Hiders win!");
			gameOver = true;
		} else {
			if(alive == 2) {
				PrintToChatAll("One hider remains.");
			} else if(alive == 1) {
				// Player died and not seeker, therefore seeker killed em
				if(client != currentSeeker) {
					PrintToChatAll("Seeker %N won!", currentSeeker);
				} else {
					PrintToChatAll("Hiders win! The last survivor was %N!", client);

				}
				gameOver = true;
			} else if(alive > 2 && client != currentSeeker) {
				PrintToChatAll("%d hiders remain", alive - 1);
			}
		}
	}
}

public void OnClientPutInServer(int client) {
	if(isEnabled && !IsFakeClient(client)) {
		ChangeClientTeam(client, 1);
		isPendingPlay[client] = true;
		isNearbyPlaying[client] = false;
		PrintToChatAll("%N will play next round", client);
		float pos[3];
		GetSpawnPosition(pos);
		TeleportEntity(client, pos, NULL_VECTOR, NULL_VECTOR);
	}
}

public void Event_ItemPickup(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(client && client > 0 && currentSeeker != client) {
		static char item[32];
		event.GetString("item", item, sizeof(item));
		if(StrEqual(item, "melee")) {
			int entity = GetPlayerWeaponSlot(client, 1);
			GetEntPropString(entity, Prop_Data, "m_strMapSetScriptName", item, sizeof(item));
			if(StrEqual(item, "fireaxe")) {
				gameOver = false;
				currentSeeker = GetSlasher();
				if(currentSeeker != client) {
					PrintToChatAll("[H&S] Seeker does not equal axe-receiver. Possible seeker: %N", client);
				}
				if(currentSeeker == -1) {
					PrintToServer("[H&S] ERROR: GetSlasher() returned -1");
					currentSeeker = client;
				}
				PrintToChatAll("%N is the seeker", currentSeeker);
			}
		}
	}
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast) {
	if(mapConfig.hasSpawnpoint) {
		PrintToServer("[H&S] Using provided spawnpoint: %.1f %.1f %.1f", mapConfig.spawnpoint[0], mapConfig.spawnpoint[1], mapConfig.spawnpoint[2]);
		for(int i = 1; i <= MaxClients; i++) {
			if(IsClientConnected(i) && IsClientInGame(i)) {
				TeleportEntity(i, mapConfig.spawnpoint, NULL_VECTOR, NULL_VECTOR);
			}
		}
	}
	EntFire("relay_intro_start", "Kill");
	SetupEntities();
	CreateTimer(15.0, Timer_RoundStart);

}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast) {
	if(nextRoundMap[0] != '\0') {
		ForceChangeLevel(nextRoundMap, "SetMapSelect");
		nextRoundMap[0] = '\0';
		return;
	}
	currentSeeker = 0;
	static float tpLoc[3];
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i)) {
			GetClientAbsOrigin(i, tpLoc);
			break;
		}
	}

	for(int i = 1; i <= MaxClients; i++) {
		isNearbyPlaying[i] = false;
		if(isPendingPlay[i]) {
			if(IsClientConnected(i) && IsClientInGame(i)) {
				ChangeClientTeam(i, 2);
				L4D_RespawnPlayer(i);
				TeleportEntity(i, tpLoc, NULL_VECTOR, NULL_VECTOR);
			}
			isPendingPlay[i] = false;
		}
	}
}

public Action Timer_CheckPlayers(Handle h) {
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i) && i != currentSeeker)
			QueryClientConVar(i, "cam_collision", QueryClientConVarCallback);
	}
	return Plugin_Continue;
}

public void QueryClientConVarCallback(QueryCookie cookie, int client, ConVarQueryResult result, const char[] sCvarName, const char[] bCvarValue) {
	int value = 0;
	if (result == ConVarQuery_Okay && StringToIntEx(bCvarValue, value) > 0 && value == 0) {
		wasThirdPersonVomitted[client] = true;
		PrintHintText(client, "Third person is disabled in this mode");
		// L4D_OnITExpired(client);
		// L4D_CTerrorPlayer_OnVomitedUpon(client, client);
		float random = GetRandomFloat();
		if(random < 0.3)
			PerformScene(client, "Playerareaclear");
		else if(random <= 0.6)
			PerformScene(client, "PlayerLaugh");
		else
			PerformScene(client, "PlayerDeath");
	} else if(wasThirdPersonVomitted[client]) {
		wasThirdPersonVomitted[client] = false;
		L4D_OnITExpired(client);
	}
}

public Action Timer_Music(Handle h) {
	static float seekerLoc[3];
	static float playerLoc[3];
	if(currentSeeker > 0) {
		GetClientAbsOrigin(currentSeeker, seekerLoc);
		GameState state = GetState();
		if(state == State_Hunting) {
			EmitSoundToClient(currentSeeker, SOUND_SUSPENSE_1, currentSeeker, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_CHANGEPITCH, 0.2, 90, currentSeeker, seekerLoc, seekerLoc, true);
		}
	}
	int playerCount;
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && i != currentSeeker) {
			
			playerCount++;
			GetClientAbsOrigin(i, playerLoc);
			float dist = GetVectorDistance(seekerLoc, playerLoc, true);
			if(dist <= 250000.0) {
				StopSound(i, SNDCHAN_AUTO, SOUND_SUSPENSE_1);
				EmitSoundToClient(i, SOUND_SUSPENSE_1_FAST, i, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_CHANGEPITCH, 1.0, 100, currentSeeker, seekerLoc, playerLoc, true);
				isNearbyPlaying[i] = true;
			} else if(dist <= 1000000.0) {
				EmitSoundToClient(i, SOUND_SUSPENSE_1, i, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_CHANGEPITCH, 0.2, 90, currentSeeker, seekerLoc, playerLoc, true);
				isNearbyPlaying[i] = true;
				StopSound(i, SNDCHAN_AUTO, SOUND_SUSPENSE_1_FAST);
			} else if(isNearbyPlaying[i]) {
				isNearbyPlaying[i] = false;
				StopSound(i, SNDCHAN_AUTO, SOUND_SUSPENSE_1_FAST);
				StopSound(i, SNDCHAN_AUTO, SOUND_SUSPENSE_1);
			}
		}
	}
	
	return Plugin_Continue;
}
public Action Timer_RoundStart(Handle h) {
	CreateTimer(0.1, Timer_CheckWeapons);
	CreateTimer(10.0, Timer_CheckWeapons);
	int entity = INVALID_ENT_REFERENCE;
	while ((entity = FindEntityByClassname(entity, "func_button")) != INVALID_ENT_REFERENCE) {
		AcceptEntityInput(entity, "Press");
	}
	entity = INVALID_ENT_REFERENCE;
	while ((entity = FindEntityByClassname(entity, "func_brush")) != INVALID_ENT_REFERENCE) {
		AcceptEntityInput(entity, "Kill");
	}
	entity = INVALID_ENT_REFERENCE;
	while ((entity = FindEntityByClassname(entity, "infected")) != INVALID_ENT_REFERENCE) {
		AcceptEntityInput(entity, "Kill");
	}
	entity = INVALID_ENT_REFERENCE;
	while ((entity = FindEntityByClassname(entity, "prop_door_rotating")) != INVALID_ENT_REFERENCE) {
		AcceptEntityInput(entity, "Unlock");
		if(GetURandomFloat() > 0.5)
			AcceptEntityInput(entity, "Toggle");
	}
	while ((entity = FindEntityByClassname(entity, "func_simpleladder")) != INVALID_ENT_REFERENCE) {
		SetEntProp(entity, Prop_Send, "m_iTeamNum", 0);
	}		
	PrintToServer("[H&S] Pressing buttons");
	if(mapConfig.mapTime > 0) {
		SetMapTime(mapConfig.mapTime);
	}

	PrintToServer("[H&S] Map time is %d seconds", GetMapTime());
	return Plugin_Continue;
}
public Action Timer_CheckWeapons(Handle h) {
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i)) {
			// Check if has no melee:
			if(GetPlayerWeaponSlot(i, 1) == -1) {
				CheatCommand(i, "give", "knife");
			}
			int item = GetPlayerWeaponSlot(i, 0);
			if(item != -1) AcceptEntityInput(item, "Kill");
		}
	}
	return Plugin_Continue;
}

stock int CreateEnvBlockerBox(const float pos[3], bool enabled = true) {
	int entity = CreateEntityByName("env_physics_blocker");
	if(entity == -1) return -1;
	DispatchKeyValue(entity, "targetname", "hsblocker");
	DispatchKeyValue(entity, "initialstate", "1");
	DispatchKeyValue(entity, "BlockType", "0");
	TeleportEntity(entity, pos, NULL_VECTOR, NULL_VECTOR);
	if(DispatchSpawn(entity)) {
		if(enabled)
			AcceptEntityInput(entity, "Enable");
		return entity;
	}
	return -1;
}

stock int CreateEnvBlockerScaled(const char[] entClass, const float pos[3], const float scale[3] = { 5.0, 5.0, 5.0 }, bool enabled = true) {
	int entity = CreateEntityByName(entClass);
	DispatchKeyValue(entity, "targetname", "hsblocker");
	DispatchKeyValue(entity, "initialstate", "1");
	DispatchKeyValue(entity, "BlockType", "0");
	static float mins[3];
	mins = scale;
	NegateVector(mins);
	DispatchKeyValueVector(entity, "boxmins", mins);
	DispatchKeyValueVector(entity, "boxmaxs", scale);
	DispatchKeyValueVector(entity, "mins", mins);
	DispatchKeyValueVector(entity, "maxs", scale);

	TeleportEntity(entity, pos, NULL_VECTOR, NULL_VECTOR);
	if(DispatchSpawn(entity)) {
		#if defined DEBUG_LOG_MAPSTART
		PrintToServer("spawn blocker scaled %.1f %.1f %.1f scale [%.0f %.0f %.0f]", pos[0], pos[1], pos[2], scale[0], scale[1], scale[2]);
		#endif
		SetEntPropVector(entity, Prop_Send, "m_vecMaxs", scale);
		SetEntPropVector(entity, Prop_Send, "m_vecMins", mins);
		if(enabled)
			AcceptEntityInput(entity, "Enable");
		#if defined DEBUG_BLOCKERS
		Effect_DrawBeamBoxRotatableToAll(pos, mins, scale, NULL_VECTOR, g_iLaserIndex, 0, 0, 0, 150.0, 0.1, 0.1, 0, 0.0, {255, 0, 0, 255}, 0);
		#endif
		return entity;
	}
	return -1;
}
enum PortalType {
	Portal_Relative,
	Portal_Teleport
}
PortalType  entityPortalType[2048];
float entityPortalOffsets[2048][3];
stock int CreatePortal(PortalType type, const char model[64], const float pos[3], const float offset[3] = { 40.0, 40.0, 0.0 }, const float scale[3] = { 5.0, 5.0, 5.0 }) {
	int entity = CreateEntityByName("trigger_multiple");
	if(entity == -1) return -1;
	DispatchKeyValue(entity, "spawnflags", "513");
	DispatchKeyValue(entity, "solid", "6");
	DispatchKeyValue(entity, "targetname", "hsportal");
	DispatchKeyValue(entity, "wait", "0");
	if(DispatchSpawn(entity)) {
		TeleportEntity(entity, pos, NULL_VECTOR, NULL_VECTOR);
		static float mins[3];
		mins = scale;
		NegateVector(mins);
		SetEntPropVector(entity, Prop_Send, "m_vecMaxs", scale);
		SetEntPropVector(entity, Prop_Send, "m_vecMins", mins);
		SetEntProp(entity, Prop_Send, "m_nSolidType", 2);

		HookSingleEntityOutput(entity, "OnStartTouch", OnPortalTouch, false);
		#if defined DEBUG_BLOCKERS
		Effect_DrawBeamBoxRotatableToAll(pos, mins, scale, NULL_VECTOR, g_iLaserIndex, 0, 0, 0, 150.0, 0.1, 0.1, 0, 0.0, {255, 0, 255, 255}, 0);
		#endif
		#if defined DEBUG_LOG_MAPSTART
		PrintToServer("spawn portal %d - pos %.1f %.1f %.1f - scale %.1f %.1f %.1f", entity, pos[0], pos[1], pos[2], scale[0], scale[1], scale[2]);
		#endif
		AcceptEntityInput(entity, "Enable");

		entityPortalOffsets[entity] = NULL_VECTOR;

		// Convert relative offset to one based off full scale:
		entityPortalType[entity] = type;
		if(type == Portal_Relative) {
			if(offset[0] != 0.0) entityPortalOffsets[entity][0] = (scale[0] * 2) + offset[0];
			if(offset[1] != 0.0) entityPortalOffsets[entity][1] = (scale[1] * 2) + offset[1];
			if(offset[2] != 0.0) entityPortalOffsets[entity][2] = (scale[2] * 2) + offset[2];
		} else {
			entityPortalOffsets[entity] = offset;
		}

		return entity;
	}
	return -1;
}

void OnPortalTouch(const char[] output, int caller, int activator, float delay) { 
	if(entityPortalType[caller] == Portal_Relative) {
		float pos[3];
		GetClientAbsOrigin(activator, pos);
		float ang[3];
		GetClientAbsAngles(activator, ang);
		if(ang[0] < 0) pos[0] -= entityPortalOffsets[caller][0];
		else pos[0] += entityPortalOffsets[caller][0];
		if(ang[1] < 0) pos[1] -= entityPortalOffsets[caller][1];
		else pos[1] += entityPortalOffsets[caller][1];
		if(ang[2] < 0) pos[2] -= entityPortalOffsets[caller][2];
		else pos[2] += entityPortalOffsets[caller][2];
		TeleportEntity(activator, pos, NULL_VECTOR, NULL_VECTOR);
	} else {
		TeleportEntity(activator, entityPortalOffsets[caller], NULL_VECTOR, NULL_VECTOR);
	}
}

stock int CreatePropDynamic(const char[] model, const float pos[3], const float ang[3]) {
	return CreateProp("prop_dynamic", model, pos, ang);
}

stock int CreatePropPhysics(const char[] model, const float pos[3], const float ang[3]) {
	return CreateProp("prop_physics", model, pos, ang);
}

stock int CreateProp(const char[] entClass, const char[] model, const float pos[3], const float ang[3]) {
	int entity = CreateEntityByName(entClass);
	if(entity == -1) return -1;
	DispatchKeyValue(entity, "model", model);
	DispatchKeyValue(entity, "solid", "6");
	DispatchKeyValue(entity, "targetname", "hsprop");
	DispatchKeyValue(entity, "disableshadows", "1");
	TeleportEntity(entity, pos, ang, NULL_VECTOR);
	if(DispatchSpawn(entity)) {
		#if defined DEBUG_LOG_MAPSTART
		PrintToServer("spawn prop %.1f %.1f %.1f model %s", pos[0], pos[1], pos[2], model[7]);
		#endif
		return entity;
	}
	return -1;
}

// Taken from silver's https://forums.alliedmods.net/showthread.php?p=1658873
stock int CreateDynamicLight(float vOrigin[3], float vAngles[3], int color, float brightness, int style = 0) {
	int entity = CreateEntityByName("light_dynamic");
	if( entity == -1)
		return -1;

	DispatchKeyValue(entity, "_light", "0 0 0 255");
	DispatchKeyValue(entity, "brightness", "1");
	DispatchKeyValueFloat(entity, "spotlight_radius", 32.0);
	DispatchKeyValueFloat(entity, "distance", brightness);
	DispatchKeyValue(entity, "targetname", "hslamp");
	DispatchKeyValueFloat(entity, "style", float(style));
	SetEntProp(entity, Prop_Send, "m_clrRender", color);
	if(DispatchSpawn(entity)) {
		TeleportEntity(entity, vOrigin, vAngles, NULL_VECTOR);
		AcceptEntityInput(entity, "TurnOn");
		#if defined DEBUG_LOG_MAPSTART
		PrintToServer("spawn dynamic light %.1f %.1f %.1f", vOrigin[0], vOrigin[1], vOrigin[2]);
		#endif
		return entity;
	}
	return -1;
}


stock void CheatCommand(int client, const char[] command, const char[] argument1) {
	int userFlags = GetUserFlagBits(client);
	SetUserFlagBits(client, ADMFLAG_ROOT);
	int flags = GetCommandFlags(command);
	SetCommandFlags(command, flags & ~FCVAR_CHEAT);
	FakeClientCommand(client, "%s %s", command, argument1);
	SetCommandFlags(command, flags);
	SetUserFlagBits(client, userFlags);
} 

stock void EntFire(const char[] name, const char[] input) {
	static char targetname[64];
	static char cmd[32];
	#if defined DEBUG_LOG_MAPSTART
	PrintToServer("[H&S] EntFire: %s \"%s\"", name, input);
	#endif
	int len = SplitString(input, " ", cmd, sizeof(cmd));
	if(len > -1) SetVariantString(input[len]);
	for(int i = MAXPLAYERS + 1; i <= 4096; i++) {
		if(IsValidEntity(i) && (IsValidEdict(i) || EntIndexToEntRef(i) != -1)) {
			GetEntPropString(i, Prop_Data, "m_iName", targetname, sizeof(targetname));
			if(StrEqual(targetname, name, false)) {
				if(len > -1) AcceptEntityInput(i, cmd);
				else AcceptEntityInput(i, input);
			} /*else { 
				GetEntityClassname(targetname, sizeof(targetname));
				if(StrEqual(targetname, name, false)) {
					if(len > -1) AcceptEntityInput(i, cmd);
					else AcceptEntityInput(i, input);
				}
			}*/
		}
	}
}

void SetupEntities(bool blockers = true, bool props = true, bool portals = true) {
	if(mapConfig.entities != null) {
		PrintToServer("[H&S] Deploying %d custom entities (Set: %s) (blockers:%b props:%b portals:%b)", mapConfig.entities.Length, currentSet, blockers, props, portals);
		for(int i = 0; i < mapConfig.entities.Length; i++) {
			EntityConfig config;
			mapConfig.entities.GetArray(i, config);

			if(config.model[0] != '\0') PrecacheModel(config.model);

			if(StrEqual(config.type, "env_physics_blocker")) {
				if(blockers && CreateEnvBlockerScaled(config.type, config.origin, config.scale, isNavBlockersEnabled) == -1) { 
					PrintToServer("[H&S:WARN] Failed to spawn blocker [type=%s] at (%.1f,%.1f, %.1f)", config.type, config.origin[0], config.origin[1], config.origin[2]);
				}
			} else if(StrEqual(config.type, "_relportal")) {
				if(portals && CreatePortal(Portal_Relative, config.model, config.origin, config.offset, config.scale) == -1) {
					PrintToServer("[H&S:WARN] Failed to spawn rel portal at (%.1f,%.1f, %.1f)", config.origin[0], config.origin[1], config.origin[2]);
				}
			} else if(StrEqual(config.type, "_portal")) {
				if(portals && CreatePortal(Portal_Teleport, config.model, config.origin, config.offset, config.scale) == -1) {
					PrintToServer("[H&S:WARN] Failed to spawn portal at (%.1f,%.1f, %.1f)", config.origin[0], config.origin[1], config.origin[2]);
				}
			} else if(StrEqual(config.type, "_lantern")) {
				int parent = CreateProp("prop_dynamic", config.model, config.origin, config.rotation);
				if(parent == -1) { 
					PrintToServer("[H&S:WARN] Failed to spawn prop [type=%s] [model=%s] at (%.1f,%.1f, %.1f)", config.type, config.model, config.origin[0], config.origin[1], config.origin[2]);
				} else {
					float pos[3];
					pos = config.origin;
					pos[2] += 15.0;
					int child = CreateDynamicLight(pos, config.rotation, GetColorInt(255, 255, 242), 80.0, 11);
					if(child == -1) { 
						PrintToServer("[H&S] Failed to spawn light source for _lantern");
					} else {
						SetParent(child, parent);
						TeleportEntity(parent, config.origin, NULL_VECTOR, NULL_VECTOR);
					}
				}
			} else if(props) {
				if(CreateProp(config.type, config.model, config.origin, config.rotation) == -1) { 
					PrintToServer("[H&S:WARN] Failed to spawn prop [type=%s] [model=%s] at (%.1f,%.1f, %.1f)", config.type, config.model, config.origin[0], config.origin[1], config.origin[2]);
				}
			}
		}

		static char key[64];
		static char value[64];
		if(mapConfig.inputs != null) {
			for(int i = 0; i < mapConfig.inputs.Length - 1; i += 2) {
				mapConfig.inputs.GetString(i, key, sizeof(key));
				mapConfig.inputs.GetString(i + 1, value, sizeof(value));
				EntFire(key, value);
			}
		}
	}
}

int GetColorInt(int r, int g, int b) {
	int color = r;
	color += 256 * g;
	color += 65536 * b;
	return color;
}

void Cleanup() {
	EntFire("hsprop", "kill");
	EntFire("hsblocker", "kill");
	EntFire("hsportal", "kill");
}

GameState GetState() {
	if(!isEnabled) return State_Unknown;
	static char buffer[4];
	L4D2_GetVScriptOutput("g_ModeScript.MutationState.CurrentStage", buffer, sizeof(buffer));
	int stage = -1;
	if(StringToIntEx(buffer, stage) > 0) {
		return view_as<GameState>(stage);
	} else {
		return State_Unknown;
	}
}

int GetSlasher() {
	if(!isEnabled) return -1;
	static char buffer[8];
	L4D2_GetVScriptOutput("g_ModeScript.MutationState.CurrentSlasher && \"GetPlayerUserId\" in g_ModeScript.MutationState.CurrentSlasher ? g_ModeScript.MutationState.CurrentSlasher.GetPlayerUserId() : -1", buffer, sizeof(buffer));
	int uid = StringToInt(buffer);
	if(uid > 0) {
		return GetClientOfUserId(uid);
	} else {
		return -1;
	}
}

int GetTick() {
	if(!isEnabled) return -1;
	static char buffer[4];
	L4D2_GetVScriptOutput("g_ModeScript.MutationState.StateTick", buffer, sizeof(buffer));
	int value = -1;
	if(StringToIntEx(buffer, value) > 0) {
		return value;
	} else {
		return -1;
	}
}

void SetTick(int tick) {
	static char buf[64];
	Format(buf, sizeof(buf), "g_ModeScript.MutationState.StateTick = %d", tick);
	L4D2_ExecVScriptCode(buf);
}


int GetMapTime() {
	static char mapTime[16];
	L4D2_GetVScriptOutput("g_ModeScript.MutationState.MapTime", mapTime, sizeof(mapTime));
	return StringToInt(mapTime);
}

void SetMapTime(int seconds) {
	static char buf[64];
	Format(buf, sizeof(buf), "g_ModeScript.MutationState.MapTime = %d", seconds);
	L4D2_ExecVScriptCode(buf);
}

Action Timer_ChangeMap(Handle h) {
	PrintToChatAll("Changing map to %s in %d seconds", nextRoundMap, mapChangeMsgTicks);
	if(mapChangeMsgTicks-- == 0) {
		ForceChangeLevel(nextRoundMap, "H&SMapSelect");
		nextRoundMap[0] = '\0';
		return Plugin_Stop;
	}
	return Plugin_Continue;
}

void ChangeMap(const char map[64], int time = 5) {
	strcopy(nextRoundMap, sizeof(nextRoundMap), map);
	mapChangeMsgTicks = time;
	CreateTimer(1.0, Timer_ChangeMap, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

bool GetSpawnPosition(float pos[3], bool includePlayers = true) {
	if(includePlayers) {
		for(int i = 1; i <= MaxClients; i++) {
			if(IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i)) {
				GetClientAbsOrigin(i, pos);
				return true;
			}
		}
	}
	int entity = INVALID_ENT_REFERENCE;
	while ((entity = FindEntityByClassname(entity, "info_player_start")) != INVALID_ENT_REFERENCE) {
		GetEntPropVector(entity, Prop_Send, "m_vecOrigin", pos);
		return true;
	}
	return false;
}

bool SetState(GameState state) {
	if(!isEnabled) return false;
	static char buffer[64];
	Format(buffer, sizeof(buffer), "g_ModeScript.MutationState.CurrentStage = %d", view_as<int>(state));
	return L4D2_ExecVScriptCode(buffer);
}

bool IsGameSoloOrPlayersLoading() {
	int connecting, ingame;
	for(int i = 1;  i <= MaxClients; i++) {
		if(IsClientConnected(i)) {
			if(IsClientInGame(i))
				ingame++;
			else
				connecting++;
		}
	}
	return connecting > 0 || ingame == 1;
}

//cm_NoSurvivorBots 
bool SetBotsEnabled(bool value) {
	static char buffer[64];
	if(value) 
		Format(buffer, sizeof(buffer), "g_ModeScript.MutationOptions.cm_NoSurvivorBots = true");
	else
		Format(buffer, sizeof(buffer), "g_ModeScript.MutationOptions.cm_NoSurvivorBots = false");
	return L4D2_ExecVScriptCode(buffer);
}

bool IsBotsEnabled() {
	static char result[8];
	L4D2_GetVScriptOutput("g_ModeScript.MutationState.cm_NoSurvivorBots", result, sizeof(result));
	return StrEqual(result, "true", false);
}

stock void GetHorizontalPositionFromClient(int client, float units, float finalPosition[3]) {
	float pos[3], ang[3];
	GetClientEyeAngles(client, ang);
	GetClientAbsOrigin(client, pos);

	float theta = DegToRad(ang[1]);
	pos[0] += units * Cosine(theta); 
	pos[1] += units * Sine(theta); 
	finalPosition = pos;
}

void SetParent(int child, int parent) {
	SetVariantString("!activator");
	AcceptEntityInput(child, "SetParent", parent);
}