#pragma semicolon 1
#pragma newdecls required

//#define DEBUG

#define PLUGIN_VERSION "1.0"
// #define DEBUG_BLOCKERS 1
// #define FORCE_ENABLED 1
// #define DEBUG_LOG_MAPSTART 1

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
static bool isNavBlockersEnabled = true, isPropsEnabled = true;
static bool isNearbyPlaying[MAXPLAYERS+1];
static bool wasThirdPersonVomitted[MAXPLAYERS+1];
static bool gameOver;
static int currentSeeker;
static int currentPlayers = 0;

static const float DEFAULT_SCALE[3] = { 5.0, 5.0, 5.0 };
static float spawnpoint[3];
static bool hasSpawnpoint;

static ArrayList entities;
static ArrayList inputs;

static KeyValues kv;
static StringMap mapConfigs;
static StringMap mapInputs;
static Handle suspenseTimer, thirdPersonTimer;

// TODO: Disable weapon drop

enum struct EntityConfig {
	float origin[3];
	float rotation[3];
	char type[32];
	char model[64];
	float scale[3];
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
	lateLoaded = late;
	return APLRes_Success;
}

public void OnPluginStart() {
	EngineVersion g_Game = GetEngineVersion();
	if(g_Game != Engine_Left4Dead2) {
		SetFailState("This plugin is for L4D2 only.");	
	}

	kv = new KeyValues("EntityConfig");

	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "data/hideandseek.cfg");

	if(!FileExists(sPath) || !kv.ImportFromFile(sPath)) {
		delete kv;
		SetFailState("Could not load entity config from data/hideandseek.cfg");
	}

	mapConfigs = new StringMap();
	mapInputs = new StringMap();

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
	RegAdminCmd("sm_hs_blockers", Command_ToggleBlockers, ADMFLAG_KICK, "Toggle nav blockers");
	RegAdminCmd("sm_hs_props", Command_ToggleProps, ADMFLAG_KICK, "Toggle props");
	RegAdminCmd("sm_hs_clear", Command_Clear, ADMFLAG_KICK, "Toggle props");

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

ArrayList LoadConfigForMap(const char[] map) {
	if (kv.JumpToKey(map)) {
		ArrayList configs = new ArrayList(sizeof(EntityConfig));
		ArrayList entInputs = new ArrayList(ByteCountToCells(64));
		if(kv.JumpToKey("ents")) {
			kv.GotoFirstSubKey();
			do {
				EntityConfig config;
				kv.GetVector("origin", config.origin, NULL_VECTOR);
				kv.GetVector("rotation", config.rotation, NULL_VECTOR);
				kv.GetString("type", config.type, sizeof(config.type), "env_physics_blocker");
				kv.GetString("model", config.model, sizeof(config.model), "");
				if(config.model[0] != '\0')
					Format(config.model, sizeof(config.model), "models/%s", config.model);
				kv.GetVector("scale", config.scale, DEFAULT_SCALE);

				configs.PushArray(config);
			} while (kv.GotoNextKey());
			// Both JumpToKey and GotoFirstSubKey both traverse, i guess, go back
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
				entInputs.PushString(buffer);

				kv.GetString(NULL_STRING, buffer, sizeof(buffer));
				entInputs.PushString(buffer);
			} while (kv.GotoNextKey(false));
			kv.GoBack();
		}
		
		if(kv.GetVector("spawnpoint", spawnpoint)) {
			hasSpawnpoint = true;
		} else {
			hasSpawnpoint = false;
		}
		// Store ArrayList<EntityConfig> handle
		mapConfigs.SetValue(map, configs);
		// Discard entInputs if unused
		if(entInputs.Length > 0)
			mapInputs.SetValue(map, entInputs);
		else
			delete entInputs;
		return configs;
	} else {
		return null;
	}
}

public Action Command_Clear(int client, int args) {
	if(args > 0) {
		static char arg[16];
		GetCmdArg(1, arg, sizeof(arg));
		if(StrEqual(arg, "props")) {
			EntFire("hsprop", "kill");
			ReplyToCommand(client, "Removed all custom gamemode props");
			return Plugin_Continue;
		} else if(StrEqual(arg, "blockers")) {
			EntFire("hsblockers", "kill");
			ReplyToCommand(client, "Removed all custom gamemode blockers");
			return Plugin_Continue;

		}
	}
	ReplyToCommand(client, "Specify 'props' or 'blockers'");
	return Plugin_Continue;
}

public Action Command_ToggleBlockers(int client, int args) {
	if(isNavBlockersEnabled) {
		EntFire("hsblocker", "Disable");
		ReplyToCommand(client, "Disabled all custom gamemode blockers");
	} else {
		EntFire("hsblocker", "Enable");
		ReplyToCommand(client, "Enabled all custom gamemode blockers");
	}
	isNavBlockersEnabled = !isNavBlockersEnabled;
	return Plugin_Handled;
}

public Action Command_ToggleProps(int client, int args) {
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
	return Plugin_Handled;
}

public Action Command_Join(int client, int args) {
	static float tpLoc[3];
	if(args == 1) {
		GetClientAbsOrigin(client, tpLoc);
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
		for(int i = 1; i <= MaxClients; i++) {
			if(IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i)) {
				GetClientAbsOrigin(i, tpLoc);
				break;
			}
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
	L4D2_ExecVScriptCode("g_ModeScript.MutationState.StateTick = -40");
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

	char map[64];
	GetCurrentMap(map, sizeof(map));

	if(!StrEqual(currentMap, map)) {
		strcopy(currentMap, sizeof(currentMap), map);
		static char mapTime[16];
		L4D2_GetVScriptOutput("g_ModeScript.MutationState.MapTime", mapTime, sizeof(mapTime));
		PrintToServer("[H&S] Map %s has a time of %s seconds", map, mapTime);


		if(!mapConfigs.GetValue(map, entities)) {
			entities = LoadConfigForMap(map);
		}
		mapInputs.GetValue(map, inputs);
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
		HookEvent("round_start", Event_RoundStart);
		HookEvent("item_pickup", Event_ItemPickup);
		HookEvent("player_death", Event_PlayerDeath);
		SetupEntities();
		CreateTimer(15.0, Timer_RoundStart);
		if(suspenseTimer != null)
			delete suspenseTimer;
		suspenseTimer = CreateTimer(20.0, Timer_Music, _, TIMER_REPEAT);
		if(thirdPersonTimer != null)
			delete thirdPersonTimer;
		thirdPersonTimer = CreateTimer(1.0, Timer_CheckPlayers, _, TIMER_REPEAT);
	} else if(!lateLoaded && suspenseTimer != null) {
		UnhookEvent("round_end", Event_RoundEnd);
		UnhookEvent("round_start", Event_RoundStart);
		UnhookEvent("item_pickup", Event_ItemPickup);
		UnhookEvent("player_death", Event_PlayerDeath);
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
	if(hasSpawnpoint) {
		for(int i = 1; i <= MaxClients; i++) {
			if(IsClientConnected(i) && IsClientInGame(i)) {
				TeleportEntity(i, spawnpoint, NULL_VECTOR, NULL_VECTOR);
			}
		}
	}
	SetupEntities();
	CreateTimer(15.0, Timer_RoundStart);

}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast) {
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
		AcceptEntityInput(entity, "Kll");
	}
	PrintToServer("[H&S] Pressing buttons");
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
	DispatchKeyValue(entity, "targetname", "hsblocker");
	DispatchKeyValue(entity, "initialstate", "1");
	DispatchKeyValue(entity, "BlockType", "0");
	TeleportEntity(entity, pos, NULL_VECTOR, NULL_VECTOR);
	DispatchSpawn(entity);
	if(enabled)
		AcceptEntityInput(entity, "Enable");
	return entity;
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
	DispatchSpawn(entity);
	SetEntPropVector(entity, Prop_Send, "m_vecMaxs", scale);
	SetEntPropVector(entity, Prop_Send, "m_vecMins", mins);
	if(enabled)
		AcceptEntityInput(entity, "Enable");
	#if defined DEBUG_BLOCKERS
	Effect_DrawBeamBoxRotatableToAll(pos, mins, scale, NULL_VECTOR, g_iLaserIndex, 0, 0, 0, 150.0, 0.1, 0.1, 0, 0.0, {0, 255, 0, 255}, 0);
	#endif
	#if defined DEBUG_LOG_MAPSTART
	PrintToServer("spawn blocker scaled %.1f %.1f %.1f scale [%.0f %.0f %.0f]", pos[0], pos[1], pos[2], scale[0], scale[1], scale[2]);
	#endif
	return entity;
}

stock int CreatePropDynamic(const char[] model, const float pos[3], const float ang[3]) {
	return CreateProp("prop_dynamic", model, pos, ang);
}

stock int CreatePropPhysics(const char[] model, const float pos[3], const float ang[3]) {
	return CreateProp("prop_physics", model, pos, ang);
}

stock int CreateProp(const char[] entClass, const char[] model, const float pos[3], const float ang[3]) {
	int entity = CreateEntityByName(entClass);
	DispatchKeyValue(entity, "model", model);
	DispatchKeyValue(entity, "solid", "6");
	DispatchKeyValue(entity, "targetname", "hsprop");
	DispatchKeyValue(entity, "disableshadows", "1");
	TeleportEntity(entity, pos, ang, NULL_VECTOR);
	DispatchSpawn(entity);
	#if defined DEBUG_LOG_MAPSTART
	PrintToServer("spawn prop %.1f %.1f %.1f model %s", pos[0], pos[1], pos[2], model[7]);
	#endif
	return entity;
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
	for(int i = MAXPLAYERS + 1; i <= GetMaxEntities(); i++) {
		if(IsValidEntity(i) && IsValidEdict(i)) {
			GetEntPropString(i, Prop_Data, "m_iName", targetname, sizeof(targetname));
			if(StrEqual(targetname, name)) {
				AcceptEntityInput(i, input);
			}
		}
	}
}

void SetupEntities() {
	if(entities != null) {
		PrintToServer("[H&S] Found map entity config, deploying %d entities", entities.Length);
		for(int i = 0; i < entities.Length; i++) {
			EntityConfig config;
			entities.GetArray(i, config);

			if(config.model[0] != '\0') PrecacheModel(config.model);

			if(StrEqual(config.type, "env_physics_blocker")) {
				CreateEnvBlockerScaled(config.type, config.origin, config.scale, isNavBlockersEnabled);
			} else {
				CreateProp(config.type, config.model, config.origin, config.rotation);
			}
		}

		static char key[64];
		static char value[64];
		if(inputs != null) {
			for(int i = 0; i < inputs.Length - 1; i += 2) {
				inputs.GetString(i, key, sizeof(key));
				inputs.GetString(i + 1, value, sizeof(value));
				EntFire(key, value);
				#if defined DEBUG_LOG_MAPSTART
				PrintToServer("[H&S] EntFire: %s %s", key, value);
				#endif
			}
		}



	}
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
	L4D2_GetVScriptOutput("g_ModeScript.MutationState.CurrentSlasher ? g_ModeScript.MutationState.CurrentSlasher.GetPlayerUserId() : -1", buffer, sizeof(buffer));
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
		return value;
	}
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