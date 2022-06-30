#pragma semicolon 1
#pragma newdecls required

//#define DEBUG

#define PLUGIN_VERSION "1.0"

#define BOT_MOVE_RANDOM_MIN_TIME 7.0 // The minimum random time for Timer_BotMove to activate (set per round)
#define BOT_MOVE_RANDOM_MAX_TIME 9.6 // The maximum random time for Timer_BotMove to activate (set per round)
#define BOT_MOVE_CHANCE 0.90 // The chance the bot will move each Timer_BotMove
#define BOT_MOVE_AVOID_FLOW_DIST 15.0 // The flow range of flow distance that triggers avoid
#define BOT_MOVE_AVOID_SEEKER_CHANCE 0.60 // The chance that if the bot gets too close to the seeker, it runs away

#define BOT_MOVE_TOO_FAR_DIST 1200.0 // TODO: DO NOT HARDCODE ME -FLOW RANGE-
#define SEED_TIME 1.0 // Time the seeker is blind, used to gather locations for bots


// #define DEBUG_SEEKER_PATH_CREATION 1


#define MAX_VALID_LOCATIONS 1000

#include <sourcemod>
#include <sdktools>
#include <left4dhooks>
#include <smlib/effects>
#include <sceneprocessor>
#include <basegamemode>
#include <multicolors>

//#include <sdkhooks>

// TODO: Hiders can switch models
char SURVIVOR_MODELS[8][] = {
	"models/survivors/survivor_gambler.mdl",
	"models/survivors/survivor_producer.mdl",
	"models/survivors/survivor_coach.mdl",
	"models/survivors/survivor_mechanic.mdl",
	"models/survivors/survivor_namvet.mdl",
	"models/survivors/survivor_teenangst.mdl",
	"models/survivors/survivor_biker.mdl",
	"models/survivors/survivor_manager.mdl"
};

enum GameState {
	State_Unknown = 0,
	State_Starting,
	State_Active,
}
int currentSeeker;
bool hasBeenSeeker[MAXPLAYERS+1];
bool ignoreSeekerBalance;
Handle spawningTimer;
UserMsg g_FadeUserMsgId;

ConVar cvar_survivorLimit;
ConVar cvar_seekerFailDamageAmount;

ArrayList validLocations;


enum struct LocationMeta {
	float pos[3];
	float ang[3];
	bool runto;
}

LocationMeta activeBotLocations[MAXPLAYERS];

static float seekerPos[3];
Handle moveTimers[MAXPLAYERS+1];
float seekerFlow = 0.0;

#include <guesswho/gwcore>

public Plugin myinfo = {
	name =  "L4D2 Guess Who", 
	author = "jackzmc", 
	description = "", 
	version = PLUGIN_VERSION, 
	url = ""
};

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

	g_FadeUserMsgId = GetUserMessageId("Fade");

	validLocations = new ArrayList(sizeof(LocationMeta));

	ConVar hGamemode = FindConVar("mp_gamemode"); 
	hGamemode.AddChangeHook(Event_GamemodeChange);
	Event_GamemodeChange(hGamemode, gamemode, gamemode);

	cvar_seekerFailDamageAmount = CreateConVar("guesswho_seeker_damage", "20.0", "The amount of damage the seeker takes when they attack a bot.", FCVAR_NONE, true, 1.0);

	RegAdminCmd("sm_guesswho", Command_GuessWho, ADMFLAG_KICK);
	RegConsoleCmd("sm_joingame", Command_Join);
}

public void OnPluginEnd() {
	Cleanup();
}

public void Event_GamemodeChange(ConVar cvar, const char[] oldValue, const char[] newValue) {
	cvar.GetString(gamemode, sizeof(gamemode));
	bool shouldEnable = StrEqual(gamemode, "guesswho", false);
	if(isEnabled == shouldEnable) return;
	if(spawningTimer != null) delete spawningTimer;
	if(shouldEnable) {
		SetCvars();
		PrintToChatAll("[GuessWho] Gamemode is starting");
		HookEvent("round_start", Event_RoundStart);
		HookEvent("player_death", Event_PlayerDeath);
		HookEvent("player_bot_replace", Event_PlayerToBot);
		// HookEvent("player_team", Event_PlayerTeam);
		/*HookEvent("round_end", Event_RoundEnd);
		;
		HookEvent("item_pickup", Event_ItemPickup);
		HookEvent("player_death", Event_PlayerDeath);*/
		// InitGamemode();
		for(int i = 1; i <= MaxClients; i++) {
			if(IsClientConnected(i) && IsClientInGame(i)) {
				//ForcePlayerSuicide(i);
			}
		}
	} else if(!lateLoaded) {
		if(cvar_survivorLimit != null)
			cvar_survivorLimit.IntValue = 4;
		UnhookEvent("round_start", Event_RoundStart);
		UnhookEvent("player_death", Event_PlayerDeath);
		UnhookEvent("player_bot_replace", Event_PlayerToBot);
		// UnhookEvent("player_team", Event_PlayerTeam);
		/*UnhookEvent("round_end", Event_RoundEnd);
		UnhookEvent("item_pickup", Event_ItemPickup);
		UnhookEvent("player_death", Event_PlayerDeath);
		UnhookEvent("player_spawn", Event_PlayerSpawn);*/
		Cleanup();
		PrintToChatAll("[GuessWho] Gamemode unloaded but cvars have not been reset.");
	}
	isEnabled = shouldEnable;
}

void Event_PlayerToBot(Event event, const char[] name, bool dontBroadcast) {
	int player = GetClientOfUserId(GetEventInt(event, "player"));
	int bot    = GetClientOfUserId(GetEventInt(event, "bot")); 

	// Do not kick bots being spawned in
	if(spawningTimer == null) {
		PrintToServer("kicking %d", bot);
		ChangeClientTeam(player, 0);
		L4D_SetHumanSpec(bot, player);
		L4D_TakeOverBot(player);
		// KickClient(bot);
	}
}

void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	if(client > 0 && GetState() == State_Active) {
		if(client == currentSeeker) {
			PrintToChatAll("%N has died, hiders win.", currentSeeker);
			SetState(State_Unknown);
			CreateTimer(5.0, Timer_ResetAll);
			for(int i = 1; i <= MaxClients; i++) {
				if(IsClientConnected(i) && IsClientInGame(i) && IsFakeClient(i)) {
					ClearInventory(i);
					PrintToServer("PlayerDeath: Seeker kill %d", i);
					KickClient(i);
				}
			}
		} else if(!IsFakeClient(client)) {
			if(attacker == currentSeeker) {
				PrintToChatAll("%N was killed", client);
			} else {
				PrintToChatAll("%N died", client);
			}
		} else {
			ClearInventory(client);
			KickClient(client);
			PrintToServer("PlayerDeath: Bot death %d", client);
		}
	}

	if(GetPlayersLeftAlive() <= 1) {
		if(GetState() == State_Active) {
			PrintToChatAll("Everyone has died. %N wins!", currentSeeker);
		}
		SetState(State_Unknown);
		// CreateTimer(5.0, Timer_ResetAll);
	}
}

Action Timer_ResetAll(Handle h) {
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2) {
			ForcePlayerSuicide(i);
		}
	}
	return Plugin_Handled;
}
bool isStarting;

void Event_RoundStart(Event event, const char[] name, bool dontBroadcast) {
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i)) {
			if(isPendingPlay[i]) {
				ChangeClientTeam(i, 2);
			} else if(IsFakeClient(i)) { 
				KickClient(i);
			}
		}
	}
	PrintToServer("RoundStart %b", isStarting);
	if(!isStarting) {
		isStarting = true;
		CreateTimer(5.0, Timer_Start);
	}
}

Action Timer_Start(Handle h) {
	if(isStarting)
		InitGamemode();
	return Plugin_Handled;
}

public void OnMapStart() {
	isStarting = false;
	if(!isEnabled) return;

	char map[128];
	GetCurrentMap(map, sizeof(map));
	if(!StrEqual(currentMap, map)) {
		strcopy(currentSet, sizeof(currentSet), "default");
		if(!StrEqual(currentMap, "")) { 
			if(!SaveMapData(currentMap)) {
				LogError("Could not save map data to disk");
			}
		}
		ReloadMapDB();
		strcopy(currentMap, sizeof(currentMap), map);
		LoadMapData(map);
	}
	g_iLaserIndex = PrecacheModel("materials/sprites/laserbeam.vmt");
	if(isEnabled) {
		SetCvars();
	}

	if(lateLoaded) {
		int seeker = GetSeeker();
		if(seeker > -1) {
			currentSeeker = seeker;
			PrintToServer("[GuessWho] Late load, found seeker %N", currentSeeker);
		}
		for(int i = 1; i <= MaxClients; i++) {
			if(IsClientConnected(i) && IsClientInGame(i)) {
				ClearInventory(i);
				if(i == currentSeeker) {
					CheatCommand(i, "give", "fireaxe");
				} else {
					CheatCommand(i, "give", "gnome");
				}
				SDKHook(i, SDKHook_WeaponDrop, OnWeaponDrop);
				SDKHook(i, SDKHook_OnTakeDamageAlive, OnTakeDamageAlive);
			}
		}
		CreateTimer(0.1, Timer_Start);
	}
	SetState(State_Unknown);
}

public void OnMapEnd() {
	for(int i = 1; i <= MaxClients; i++) {
		if(moveTimers[i] != null) {
			delete moveTimers[i];
		}
	}
}

public void OnClientPutInServer(int client) {
	if(isEnabled && !IsFakeClient(client)) {
		ChangeClientTeam(client, 1);
		isPendingPlay[client] = true;
		PrintToChatAll("%N will play next round", client);
		float pos[3];
		FindSpawnPosition(pos);
		TeleportEntity(client, pos, NULL_VECTOR, NULL_VECTOR);
	}
}

public void OnClientDisconnect(int client) {
	if(client == currentSeeker) {
		PrintToChatAll("The seeker has disconnected");
		CreateTimer(1.0, Timer_ResetAll);
	}
}



void SetCvars() {
	cvar_survivorLimit = FindConVar("survivor_limit");
	ConVar cvar_separationMinRange = FindConVar("sb_separation_danger_min_range");
	ConVar cvar_separationMaxRange = FindConVar("sb_separation_danger_max_range");
	ConVar cvar_abmAutoHard = FindConVar("abm_autohard");
	ConVar cvar_sbFixEnabled = FindConVar("sb_fix_enabled");
	ConVar cvar_sbPushScale = FindConVar("sb_pushscale");
	if(cvar_survivorLimit != null) {
		cvar_survivorLimit.SetBounds(ConVarBound_Upper, true, 64.0);
		cvar_survivorLimit.IntValue = MaxClients;
	}
	if(cvar_separationMinRange != null) {
		cvar_separationMinRange.IntValue = 1000;
		cvar_separationMaxRange.IntValue = 1200;
	} 
	if(cvar_abmAutoHard != null)
		cvar_abmAutoHard.IntValue = 0;
	if(cvar_sbFixEnabled != null)
		cvar_sbFixEnabled.IntValue = 0;
	cvar_sbPushScale.IntValue = 0;
}


void InitGamemode() {
	if(isStarting && GetState() != State_Unknown) {
		PrintToServer("[GuessWho] Warn: InitGamemode() called in an incorrect state (%d)", GetState());
		return;
	}
	SetupEntities();
	PrintToChatAll("InitGamemode(): activating");
	ArrayList validPlayerIds = new ArrayList();
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2) {
			if(IsFakeClient(i)) KickClient(i);
			else {
				if(!IsPlayerAlive(i)) {
					L4D_RespawnPlayer(i);
				}
				ChangeClientTeam(i, 2);
				if(!hasBeenSeeker[i] || ignoreSeekerBalance)
					validPlayerIds.Push(GetClientUserId(i));
			}
		}
	}
	if(validPlayerIds.Length == 0) {
		PrintToServer("[GuessWho] Warn: Ignoring InitGamemode() with no valid survivors");
		return;
	}
	ignoreSeekerBalance = false;
	int newSeeker = GetClientOfUserId(validPlayerIds.Get(GetURandomInt() % validPlayerIds.Length));
	delete validPlayerIds;
	if(newSeeker  > 0) {
		hasBeenSeeker[newSeeker] = true;
		PrintToChatAll("%N is the seeker", newSeeker);
		SetPlayerBlind(newSeeker, 255);
		SetSeeker(newSeeker);
	}
	
	TeleportAllToStart();
	spawningTimer = CreateTimer(0.2, Timer_SpawnBots, 16, TIMER_REPEAT);
}

Action Timer_SpawnBots(Handle h, int max) {
	static int count;
	if(count < max) {
		if(AddSurvivor()) {
			count++;
			return Plugin_Continue;
		} else {
			PrintToChatAll("GUESS WHO: FATAL ERROR: AddSurvivor() failed");
			LogError("Guess Who: Fatal Error: AddSurvivor() failed");
			count = 0;
			return Plugin_Stop;
		}
	}
	count = 0;
	CreateTimer(1.0, Timer_SpawnPost);
	return Plugin_Stop;
}

Action Timer_SpawnPost(Handle h) {
	PrintToChatAll("Timer_SpawnPost(): activating");
	SetState(State_Starting);

	bool isL4D1 = L4D2_GetSurvivorSetMap() == 1;
	int remainingSeekers;
	for(int i = 1; i <= MaxClients; i++) {
		if(i != currentSeeker && IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2) {
			if(!IsFakeClient(i)) {
				if(!hasBeenSeeker[i]) {
					remainingSeekers++;
				}
			}
			SDKHook(i, SDKHook_OnTakeDamageAlive, OnTakeDamageAlive);
			SDKHook(i, SDKHook_WeaponDrop, OnWeaponDrop);

			ClearInventory(i);
			int item = GivePlayerItem(i, "weapon_gnome");
			EquipPlayerWeapon(i, item);
			int survivor = GetRandomInt(isL4D1 ? 5 : 0, 7);
			SetEntityModel(i, SURVIVOR_MODELS[survivor]);
			SetEntProp(i, Prop_Send, "m_survivorCharacter", isL4D1 ? (survivor - 4) : survivor);
		}
	}

	if(remainingSeekers == 0) {
		PrintToChatAll("All players have been seekers once");
		for(int i = 0; i <= MaxClients; i++) { 
			hasBeenSeeker[i] = false;
		}
	}

	PrintToChatAll("[debug] waiting for safe area leave");
	CreateTimer(1.0, Timer_WaitForStart, _, TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT);

	return Plugin_Handled;
}

Action Timer_WaitForStart(Handle h) {
	if(L4D_HasAnySurvivorLeftSafeArea()) {
		GetClientAbsOrigin(L4D_GetHighestFlowSurvivor(), seekerPos);
		seekerFlow = L4D2Direct_GetFlowDistance(currentSeeker);
		CreateTimer(0.5, Timer_AcquireLocations, _, TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT);
		for(int i = 1; i <= MaxClients; i++) {
			if(i != currentSeeker && IsClientConnected(i) && IsClientInGame(i)) {
				TeleportEntity(i, seekerPos, NULL_VECTOR, NULL_VECTOR);
				if(IsFakeClient(i)) {
					moveTimers[i] = CreateTimer(GetRandomFloat(BOT_MOVE_RANDOM_MIN_TIME, BOT_MOVE_RANDOM_MAX_TIME), Timer_BotMove2, GetClientUserId(i), TIMER_REPEAT);
					TriggerTimer(moveTimers[i]);
				}
			}
		}

		PrintToChatAll("[GuessWho] Seeker will start in %.0f seconds", SEED_TIME);
		SetTick(0);
		SetMapTime(RoundFloat(SEED_TIME));
		CreateTimer(SEED_TIME, Timer_StartSeeker);
		return Plugin_Stop;
	}
	return Plugin_Continue;
}

Action Timer_StartSeeker(Handle h) {
	CPrintToChatAll("{blue}%N{default} :  Here I come", currentSeeker);
	TeleportToSpawn(currentSeeker);
	SetPlayerBlind(currentSeeker, 0);
	SetState(State_Active);
	SetTick(0);
	SetMapTime(1000);
	return Plugin_Continue;
}

Action OnWeaponDrop(int client, int weapon) { 
	return Plugin_Handled;
}

Action OnTakeDamageAlive(int victim, int& attacker, int& inflictor, float& damage, int& damagetype) {
	if(attacker == currentSeeker) {
		damage = 100.0;
		ClearInventory(victim);
		if(IsFakeClient(victim)) {
			PrintToChat(attacker, "That was a bot! -%.0f health", cvar_seekerFailDamageAmount.FloatValue);
			SDKHooks_TakeDamage(attacker, 0, 0, cvar_seekerFailDamageAmount.FloatValue);
		}
		return Plugin_Changed;
	} else if(attacker > 0 && attacker <= MaxClients) {
		damage = 0.0;
		return Plugin_Changed;
	} else {
		return Plugin_Continue;
	}
}

static float vecLastLocation[MAXPLAYERS+1][3]; 
static float DEBUG_BOT_MOVER_MIN[3] = { -5.0, -5.0, 0.0 }; 
static float DEBUG_BOT_MOVER_MAX[3] = { 5.0, 5.0, 2.0 }; 

Action Timer_AcquireLocations(Handle h) {
	bool ignoreSeeker = true;
	#if defined DEBUG_SEEKER_PATH_CREATION
		ignoreSeeker = false;
	#endif
	seekerFlow = L4D2Direct_GetFlowDistance(currentSeeker);
	GetClientAbsOrigin(currentSeeker, seekerPos);
	for(int i = 1; i <= MaxClients; i++) {
		if((!ignoreSeeker || i != currentSeeker) && IsClientConnected(i) && IsClientInGame(i) && !IsFakeClient(i) && GetEntityFlags(i) & FL_ONGROUND ) {
			LocationMeta meta;
			GetClientAbsOrigin(i, meta.pos);
			GetClientEyeAngles(i, meta.ang);
			if(meta.pos[0] != vecLastLocation[i][0] || meta.pos[1] != vecLastLocation[i][1] || meta.pos[2] != vecLastLocation[i][2]) {
				validLocations.PushArray(meta);
				if(validLocations.Length > MAX_VALID_LOCATIONS) {
					PrintToServer("[GuessWho] Hit MAX_VALID_LOCATIONS (%d), clearing some locations", MAX_VALID_LOCATIONS);
					validLocations.Sort(Sort_Random, Sort_Float);
					validLocations.Erase(MAX_VALID_LOCATIONS - 200);
				}
				Effect_DrawBeamBoxRotatableToAll(meta.pos, DEBUG_BOT_MOVER_MIN, DEBUG_BOT_MOVER_MAX, NULL_VECTOR, g_iLaserIndex, 0, 0, 0, 150.0, 0.1, 0.1, 0, 0.0, {255, 0, 0, 255}, 0);
				vecLastLocation[i] = meta.pos;
			}
		}
	}
	return Plugin_Continue;
}


Action Timer_BotMove2(Handle h, int userid) {
	int i = GetClientOfUserId(userid);
	if(i == 0) return Plugin_Stop;
	if(GetURandomFloat() > BOT_MOVE_CHANCE) return Plugin_Continue;

	float botFlow = L4D2Direct_GetFlowDistance(i);
	float flowDiff = FloatAbs(botFlow - seekerFlow);
	if(flowDiff > BOT_MOVE_TOO_FAR_DIST) {
		activeBotLocations[i].runto = GetURandomFloat() > 0.90;
		TE_SetupBeamLaser(i, currentSeeker, g_iLaserIndex, 0, 0, 0, 8.0, 0.5, 0.1, 0, 1.0, {255, 255, 0, 125}, 1);
		TE_SendToAll();
		L4D2_RunScript("CommandABot({cmd=1,bot=GetPlayerFromUserID(%i),pos=Vector(%f,%f,%f)})", GetClientUserId(i), seekerPos[0], seekerPos[1], seekerPos[2]);
		PrintToConsoleAll("[gw/debug] BOT %N TOO FAR (DIFF %f) -> Moving to seeker (%f %f %f)", i, flowDiff, seekerPos[0], seekerPos[1], seekerPos[2]);
	} else if(validLocations.Length > 0) {
		if(mapConfig.hasSpawnpoint && FloatAbs(botFlow - seekerFlow) < BOT_MOVE_AVOID_FLOW_DIST && GetURandomFloat() < BOT_MOVE_AVOID_SEEKER_CHANCE) {
			if(!FindPointAway(seekerPos, activeBotLocations[i].pos)) {
				PrintToConsoleAll("[gw/debug] BOT %N TOO CLOSE -> Failed to find far point, falling back to spawn", i);
				activeBotLocations[i].pos = mapConfig.spawnpoint;
			} else {
				PrintToConsoleAll("[gw/debug] BOT %N TOO CLOSE -> Moving to far point (%f %f %f)", i, activeBotLocations[i].pos[0], activeBotLocations[i].pos[1], activeBotLocations[i].pos[2]);
			}
			activeBotLocations[i].runto = GetURandomFloat() < 0.75;
			Effect_DrawBeamBoxRotatableToAll(activeBotLocations[i].pos, DEBUG_BOT_MOVER_MIN, DEBUG_BOT_MOVER_MAX, NULL_VECTOR, g_iLaserIndex, 0, 0, 0, 150.0, 0.2, 0.1, 0, 0.0, {255, 255, 255, 255}, 0);
		} else {
			activeBotLocations[i].runto = GetURandomFloat() > 0.90;
			validLocations.GetArray(GetURandomInt() % validLocations.Length, activeBotLocations[i]);
			Effect_DrawBeamBoxRotatableToAll(activeBotLocations[i].pos, DEBUG_BOT_MOVER_MIN, DEBUG_BOT_MOVER_MAX, NULL_VECTOR, g_iLaserIndex, 0, 0, 0, 150.0, 0.1, 0.1, 0, 0.0, {255, 0, 255, 255}, 0);
		}
		L4D2_RunScript("CommandABot({cmd=1,bot=GetPlayerFromUserID(%i),pos=Vector(%f,%f,%f)})", 
			GetClientUserId(i), 
			activeBotLocations[i].pos[0], activeBotLocations[i].pos[1], activeBotLocations[i].pos[2]
		);
	}
	return Plugin_Continue;
}

public Action OnPlayerRunCmd(int client, int& buttons, int& impulse, float vel[3], float angles[3], int& weapon, int& subtype, int& cmdnum, int& tickcount, int& seed, int mouse[2]) {
	if(IsFakeClient(client)) {
		float random = GetURandomFloat();
		buttons |= (activeBotLocations[client].runto ? IN_WALK : IN_SPEED);
		if(random < 0.001) {
			buttons |= IN_JUMP;
		} else if(random < 0.0015) {
			buttons |= IN_ATTACK2;
		}
		return Plugin_Changed;
	}
	return Plugin_Continue;
}


void ClearInventory(int client) {
	for(int i = 0; i <= 5; i++) {
		int item = GetPlayerWeaponSlot(client, i);
		if(item > 0) {
			RemovePlayerItem(client, item);
			AcceptEntityInput(item, "Kill");
		}
	}
}

bool AddSurvivor() {
	if (GetClientCount(false) >= MaxClients - 1) {
		return false;
	}

	int i = CreateFakeClient("GuessWhoBot");
	bool result;
	if (i > 0) {
		if (DispatchKeyValue(i, "classname", "SurvivorBot")) {
			ChangeClientTeam(i, 2);

			if (DispatchSpawn(i)) {
				result = true;
			}
		}

		CreateTimer(0.2, Timer_Kick, i);
	}
	return result;
}

Action Timer_Kick(Handle h, int i) {
	KickClient(i);
}

stock void L4D2_RunScript(const char[] sCode, any ...) {
	static int iScriptLogic = INVALID_ENT_REFERENCE;
	if(iScriptLogic == INVALID_ENT_REFERENCE || !IsValidEntity(iScriptLogic)) {
		iScriptLogic = EntIndexToEntRef(CreateEntityByName("logic_script"));
		if(iScriptLogic == INVALID_ENT_REFERENCE|| !IsValidEntity(iScriptLogic))
			SetFailState("Could not create 'logic_script'");
		
		DispatchSpawn(iScriptLogic);
	}
	
	static char sBuffer[512];
	VFormat(sBuffer, sizeof(sBuffer), sCode, 2);
	
	SetVariantString(sBuffer);
	AcceptEntityInput(iScriptLogic, "RunScriptCode");
}

public void OnSceneStageChanged(int scene, SceneStages stage) {
	if(stage == SceneStage_Started) {
		int activator = GetSceneInitiator(scene);
		if(activator == 0) {
			CancelScene(scene);
		}
	}
}

bool SaveMapData(const char[] map) {
	char buffer[256];
	BuildPath(Path_SM, buffer, sizeof(buffer), "data/guesswho");
	CreateDirectory(buffer, 1402 /* 770 */);
	BuildPath(Path_SM, buffer, sizeof(buffer), "data/guesswho/%s.txt", map);
	PrintToServer("[GuessWho] Attempting to write to %s", buffer);
	File file = OpenFile(buffer, "w+");
	if(file != null) {
		file.WriteLine("px\tpy\tpz\tax\tay\taz");
		LocationMeta meta;
		for(int i = 0; i < validLocations.Length; i++) {
			validLocations.GetArray(i, meta);
			file.WriteLine("%.1f %.1f %.1f %.1f %.1f %.1f", meta.pos[0], meta.pos[1], meta.pos[2], meta.ang[0], meta.ang[1], meta.ang[2]);
		}
		file.Flush();
		delete file;
		return true;
	}
	return false;
}

bool LoadMapData(const char[] map) {
	validLocations.Clear();

	char buffer[256];
	BuildPath(Path_SM, buffer, sizeof(buffer), "data/guesswho/%s.txt", map);
	LoadConfigForMap(map);
	File file = OpenFile(buffer, "r+");
	if(file != null) {
		char line[64];
		char pieces[16][6];
		file.ReadLine(line, sizeof(line)); // Skip header
		while(file.ReadLine(line, sizeof(line))) {
			ExplodeString(line, " ", pieces, 6, 16, false);
			LocationMeta meta;
			meta.pos[0] = StringToFloat(pieces[0]);
			meta.pos[1] = StringToFloat(pieces[1]);
			meta.pos[2] = StringToFloat(pieces[2]);
			meta.ang[0] = StringToFloat(pieces[3]);
			meta.ang[1] = StringToFloat(pieces[4]);
			meta.ang[2] = StringToFloat(pieces[5]);
			validLocations.PushArray(meta);
		}
		PrintToServer("[GuessWho] Loaded %d locations for %s", validLocations.Length, map);
		delete file;
		return true;
	}
	return false;
}