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

char gamemode[32], currentMap[64];
bool isEnabled, lateLoaded;

bool isPendingPlay[MAXPLAYERS+1];
bool isNavBlockersEnabled = true, isPropsEnabled = true, isPortalsEnabled = true;
bool isNearbyPlaying[MAXPLAYERS+1];
bool wasThirdPersonVomitted[MAXPLAYERS+1];
bool gameOver;
int currentSeeker;
int currentPlayers = 0;

float DEFAULT_SCALE[3] = { 5.0, 5.0, 5.0 };

char currentSet[16] = "default";

Handle suspenseTimer, thirdPersonTimer;

char nextRoundMap[64];
int seekerCam = INVALID_ENT_REFERENCE;
bool isViewingCam[MAXPLAYERS+1];

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
	bool canClimb;
	bool pressButtons;
}

MapConfig mapConfig;
ArrayList validMaps;
ArrayList validSets;

#include <hideandseek/hscore>

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

	RegConsoleCmd("sm_joingame", Command_Join, "Joins or joins someone else");
	RegAdminCmd("sm_hs", Command_HideAndSeek, ADMFLAG_CHEATS, "The main command. see /hs help");

}

public void OnPluginEnd() {
	Cleanup();
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

	seekerCam = INVALID_ENT_REFERENCE;
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
		if(IsGameSoloOrPlayersLoading()) {
			Handle timer = CreateTimer(10.0, Timer_KeepWaiting, _, TIMER_REPEAT);
			TriggerTimer(timer);
			PrintToServer("[H&S] Player(s) are connecting, or solo. Waiting...");
			SetState(State_Startup);
		}
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
		int seeker = GetSlasher();
		if(seeker > -1) {
			currentSeeker = seeker;
			PrintToServer("[H&S] Late load, found seeker %N", currentSeeker);
		}
		SetPeekCamTarget(currentSeeker);
		if(IsGameSoloOrPlayersLoading()) {
			Handle timer = CreateTimer(10.0, Timer_KeepWaiting, _, TIMER_REPEAT);
			TriggerTimer(timer);
			PrintToServer("[H&S] Late load, player(s) are connecting, or solo. Waiting...");
			SetState(State_Startup);
		}
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
		HookEvent("player_spawn", Event_PlayerSpawn);
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
		UnhookEvent("player_spawn", Event_PlayerSpawn);
		Cleanup();
		delete suspenseTimer;
		delete thirdPersonTimer;
	}
}

const float DEATH_CAM_MIN_DIST = 150.0;
public Action Timer_StopPeekCam(Handle h) { 
	PrintToServer("clearing cam");
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i)) {
			SetPeekCamActive(i, false);
		}
	}
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) { 
	int client = GetClientOfUserId(event.GetInt("userid"));
	int attacker = GetClientOfUserId(event.GetInt("attacker"));

	if(!gameOver && client && GetClientTeam(client) == 2) {
		SetPeekCamTarget(attacker > 0 ? attacker : client, client);

		int alive = 0;
		float pos[3], checkPos[3];
		GetClientAbsOrigin(attacker, pos);
		SetPeekCamActive(attacker, true);
		for(int i = 1; i <= MaxClients; i++) {
			if(IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i)) {
				if(attacker > 0 && attacker != client) {
					GetClientAbsOrigin(i, checkPos);
					if(GetVectorDistance(checkPos, pos) > DEATH_CAM_MIN_DIST) {
						SetPeekCamActive(i, true);
					}
					alive++;
				}
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
					SetPeekCamTarget(client);
					PrintToChatAll("Hiders win! The last survivor was %N!", client);

				}
				gameOver = true;
				return;
			} else if(alive > 2 && client != currentSeeker) {
				PrintToChatAll("%d hiders remain", alive - 1);
			}
		}
		CreateTimer(2.0, Timer_StopPeekCam);
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
				if(currentSeeker <= 0) {
					PrintToServer("[H&S] ERROR: GetSlasher() returned invalid seeker");
					currentSeeker = client;
				} else if(currentSeeker != client) {
					PrintToChatAll("[H&S] Seeker does not equal axe-receiver. Possible seeker: %N", client);
				}
				SetPeekCamTarget(currentSeeker);
				PrintToChatAll("%N is the seeker", currentSeeker);
			}
		}
	}
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(client > 0 && mapConfig.hasSpawnpoint) {
		TeleportEntity(client, mapConfig.spawnpoint, NULL_VECTOR, NULL_VECTOR);
	}
	isViewingCam[client] = false;
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
	for(int i = 1; i <= MaxClients; i++) {
		isNearbyPlaying[i] = false;
		if(IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 1) {
			SetPeekCamActive(i, false);
			if(isPendingPlay[i]) {
				ChangeClientTeam(i, 2);
				L4D_RespawnPlayer(i);
				if(mapConfig.hasSpawnpoint) {
					TeleportEntity(i, mapConfig.spawnpoint, NULL_VECTOR, NULL_VECTOR);
				}
				isPendingPlay[i] = false;
			}
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

GameState prevState;
public Action Timer_Music(Handle h) {
	static float seekerLoc[3];
	static float playerLoc[3];
	bool changedToHunting;
	if(currentSeeker > 0) {
		GetClientAbsOrigin(currentSeeker, seekerLoc);
		GameState state = GetState();
		if(state == State_Hunting) {
			if(prevState == State_Hiding) {
				changedToHunting = true;
				SetPeekCamTarget(currentSeeker);
			}
			EmitSoundToClient(currentSeeker, SOUND_SUSPENSE_1, currentSeeker, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_CHANGEPITCH, 0.2, 90, currentSeeker, seekerLoc, seekerLoc, true);
		}
		prevState = state;
	}
	int playerCount;
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && i != currentSeeker) {
			if(changedToHunting)
				SetPeekCamActive(i, true);
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
	if(changedToHunting)
		CreateTimer(2.2, Timer_StopPeekCam);
	
	return Plugin_Continue;
}
public Action Timer_RoundStart(Handle h) {
	PrintToServer("[H&S] Running round entity tweaks");
	CreateTimer(0.1, Timer_CheckWeapons);
	CreateTimer(10.0, Timer_CheckWeapons);
	int entity = INVALID_ENT_REFERENCE;
	if(mapConfig.pressButtons) {
		while ((entity = FindEntityByClassname(entity, "func_button")) != INVALID_ENT_REFERENCE) {
			AcceptEntityInput(entity, "Press");
		}
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
	if(mapConfig.canClimb) {
		while ((entity = FindEntityByClassname(entity, "func_simpleladder")) != INVALID_ENT_REFERENCE) {
			SetEntProp(entity, Prop_Send, "m_iTeamNum", 0);
		}		
	}
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

