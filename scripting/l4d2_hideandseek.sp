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
#include <multicolors>
#if defined DEBUG_BLOCKERS
#include <smlib/effects>
#endif

#define PARTICLE_ELMOS			"st_elmos_fire_cp0"
#define PARTICLE_TES1			"electrical_arc_01"

public Plugin myinfo = 
{
	name =  "L4D2 Hide & Seek", 
	author = "jackzmc", 
	description = "", 
	version = PLUGIN_VERSION, 
	url = "https://github.com/Jackzmc/sourcemod-plugins"
};

/*TODO:
2. Seeker helping
3. flare on hunted
*/

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
#define SOUND_SHAKE "doors/gate_move1.wav"

enum GameState {
	State_Unknown = -1,
	State_Startup,
	State_Hiding,
	State_Restarting,
	State_Hunting
}
char GAME_STATE_DEBUG[4][] = {
	"Startup",
	"Hiding",
	"Restarting",
	"Hunting"
};

bool isNearbyPlaying[MAXPLAYERS+1];
bool wasThirdPersonVomitted[MAXPLAYERS+1];
bool gameOver;
int currentSeeker;
int currentPlayers = 0;

Handle suspenseTimer, thirdPersonTimer, peekCamStopTimer, hiderCheckTimer;
Handle startupTimer;


int g_BeamSprite;
int g_HaloSprite;

bool hasBeenSeeker[MAXPLAYERS+1];
float lastPos[MAXPLAYERS+1][3];
float distanceTraveled[MAXPLAYERS+1];
bool ignoreSeekerBalance;

ConVar cvar_peekCam;
ConVar cvar_seekerBalance;
ConVar cvar_abm_autohard;
ConVar cvar_seekerHelpers;

BaseGame Game;
#include <gamemodes/base>
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

	Game.Init("Hide&Seek", "H&S");

	validMaps = new ArrayList(ByteCountToCells(64));
	validSets = new ArrayList(ByteCountToCells(16));
	mapConfigs = new StringMap();

	if(!ReloadMapDB()) {
		SetFailState("Could not load entity config from data/hideandseek.cfg");
	}

	cvar_peekCam = CreateConVar("hs_peekcam", "0", "Controls the peek camera on events. Set bits\n0 = OFF, 1 = On Game End, 2 = Any death", FCVAR_NONE, true, 0.0, true, 3.0);
	cvar_seekerBalance = CreateConVar("hs_seekerbalance", "1", "Enable or disable ensuring every player has played as seeker", FCVAR_NONE, true, 0.0, true, 1.0);
	cvar_seekerHelpers = CreateConVar("hs_seekerhelper", "1", "Dev. 0 = off, 1 = Glow", FCVAR_NONE, true, 0.0);

	ConVar hGamemode = FindConVar("mp_gamemode"); 
	hGamemode.AddChangeHook(Event_GamemodeChange);
	Event_GamemodeChange(hGamemode, gamemode, gamemode);

	cvar_abm_autohard = FindConVar("cvar_abm_autohard");

	RegConsoleCmd("sm_joingame", Command_Join, "Joins or joins someone else");
	RegAdminCmd("sm_hs", Command_HideAndSeek, ADMFLAG_CHEATS, "The main command. see /hs help");

}

public void OnPluginEnd() {
	Cleanup();
}

public void OnClientConnected(int client) {
	hasBeenSeeker[client] = false;
	if(!IsFakeClient(client)) {
		currentPlayers++;
		if(isEnabled) {
			// Once first player joins, wait for others to join
			if(currentPlayers == 1) {
				StartWaiting();
			}
		}
	}
}

void StartWaiting(bool fireInstantly = false) {
	if(GetState() == State_Startup && startupTimer != null) {
		startupTimer = CreateTimer(10.0, Timer_KeepWaiting, _, TIMER_REPEAT);
		if(fireInstantly) 
			TriggerTimer(startupTimer);
	}
}

public void OnClientPutInServer(int client) {
	if(isEnabled && !IsFakeClient(client)) {
		ChangeClientTeam(client, 1);
		isPendingPlay[client] = true;
		isNearbyPlaying[client] = false;
		PrintToChatAll("%N will play next round", client);
		float pos[3];
		// Try to get spawn point, if not, just let them spawn normally
		if(GetSpawnPosition(pos))
			TeleportEntity(client, pos, NULL_VECTOR, NULL_VECTOR);
	}
}

public Action Timer_KeepWaiting(Handle h) {
	SetTick(-40);
	SetState(State_Startup);
	PrintHintTextToAll("Waiting for players to join...");
	if(IsGameSoloOrPlayersLoading()) {
		return Plugin_Continue;
	} else {
		startupTimer = null;
		return Plugin_Handled;
	}
}

public void OnClientDisconnect(int client) {
	distanceTraveled[client] = 0.0;
	if(!IsFakeClient(client)) {
		currentPlayers--;
	}
}

public void OnMapStart() {
	if(!isEnabled) return;

	currentSeeker = 0;

	if(cvar_abm_autohard != null) {
		cvar_abm_autohard.IntValue = 0;
	}
	char map[64];
	GetCurrentMap(map, sizeof(map));

	if(!StrEqual(g_currentMap, map)) {
		PrintToServer("[H&S] Map changed, loading fresh config");
		strcopy(g_currentMap, sizeof(g_currentMap), map);
		if(!mapConfigs.GetArray(map, mapConfig, sizeof(MapConfig))) {
			LoadConfigForMap(map);
		}
		strcopy(g_currentSet, sizeof(g_currentSet), "default");
		if(IsGameSoloOrPlayersLoading()) {
			StartWaiting(true);
			PrintToServer("[H&S] Player(s) are connecting, or solo. Waiting...");
			SetState(State_Startup);
		}
	}

	#if defined DEBUG_BLOCKERS
	g_iLaserIndex = PrecacheModel("materials/sprites/laserbeam.vmt");
	#endif
	PrecacheSound(SOUND_SUSPENSE_1);
	PrecacheSound(SOUND_SUSPENSE_1_FAST);
	PrecacheSound(SOUND_SHAKE);
	PrecacheSound("custom/xen_teleport.mp3");
	AddFileToDownloadsTable("sound/custom/suspense1.mp3");
	AddFileToDownloadsTable("sound/custom/suspense1fast.mp3");
	AddFileToDownloadsTable("sound/custom/xen_teleport.mp3");

	PrecacheParticle(PARTICLE_ELMOS);
	PrecacheParticle(PARTICLE_TES1);

	g_BeamSprite = PrecacheModel("sprites/laser.vmt");
	g_HaloSprite = PrecacheModel("sprites/halo01.vmt");
	PrecacheSound("buttons/button17.wav", true);

	if(lateLoaded) {
		SetupEntities();
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
		lateLoaded = false;
	}
}

public Action L4D2_OnChangeFinaleStage(int &finaleType, const char[] arg) {
	if(isEnabled) {
		finaleType = 0;
		return Plugin_Changed;
	}
	return Plugin_Continue;
}

public void OnSceneStageChanged(int scene, SceneStages stage) {
	if(isEnabled && stage == SceneStage_Spawned) {
		int activator = GetSceneInitiator(scene);
		if(activator != GetActorFromScene(scene)) {
			CancelScene(scene);
		}
	}
}

bool wasEnabled;
public void Event_GamemodeChange(ConVar cvar, const char[] oldValue, const char[] newValue) {
	cvar.GetString(gamemode, sizeof(gamemode));
	#if defined FORCE_ENABLED
		isEnabled = true;
		PrintToServer("[H&S] Force-enabled debug");
	#else
		isEnabled = StrEqual(gamemode, "hideandseek", false);
	#endif
	if(isEnabled) {
		PrintToChatAll("[H&S] Hide and seek gamemode activated, starting");
		HookEvent("round_end", Event_RoundEnd);
		HookEvent("round_start", Event_RoundStart);
		HookEvent("player_spawn", Event_PlayerSpawn);
		HookEvent("item_pickup", Event_ItemPickup);
		HookEvent("player_death", Event_PlayerDeath);
		// OnMapStart(); // Don't use, need to track OnMapStart
		if(lateLoaded)
			CreateTimer(2.0, Timer_RoundStart);
		else
			CreateTimer(10.0, Timer_RoundStart);
		if(suspenseTimer != null)
			delete suspenseTimer;
		suspenseTimer = CreateTimer(20.0, Timer_Music, _, TIMER_REPEAT);
		if(hiderCheckTimer != null)
			delete hiderCheckTimer;
		hiderCheckTimer = CreateTimer(30.0, Timer_CheckHiders, _, TIMER_REPEAT);
		if(thirdPersonTimer != null)
			delete thirdPersonTimer;
		thirdPersonTimer = CreateTimer(2.0, Timer_CheckPlayers, _, TIMER_REPEAT);
		if(!lateLoaded) {
			for(int i = 1; i <= MaxClients; i++) {
				if(IsClientConnected(i) && IsClientInGame(i)) {
					ForcePlayerSuicide(i);
				}
			}
		}
		wasEnabled = true;
	} else if(wasEnabled) {
		wasEnabled = false;
		UnhookEvent("round_end", Event_RoundEnd);
		UnhookEvent("round_start", Event_RoundStart);
		UnhookEvent("item_pickup", Event_ItemPickup);
		UnhookEvent("player_death", Event_PlayerDeath);
		UnhookEvent("player_spawn", Event_PlayerSpawn);
		Cleanup();
		delete suspenseTimer;
		delete thirdPersonTimer;
		delete hiderCheckTimer;
	}
}

const float DEATH_CAM_MIN_DIST = 150.0;
public Action Timer_StopPeekCam(Handle h) { 
	for(int i = 1; i <= MaxClients; i++) {
		PeekCam.Disable(i);
	}
	PeekCam.Disable();
	RequestFrame(Frame_StopPeekCam);
	peekCamStopTimer = null;
	return Plugin_Stop;
}

void Frame_StopPeekCam() {
	PeekCam.Destroy();
}

public void OnEntityCreated(int entity, const char[] classname) {
	if(isEnabled) {
		if(StrEqual(classname, "infected"))
			AcceptEntityInput(entity, "Kill");
	}
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) { 
	if(gameOver) return;

	int client = GetClientOfUserId(event.GetInt("userid"));
	int attacker = GetClientOfUserId(event.GetInt("attacker"));

	if(!gameOver && client && GetClientTeam(client) == 2) {
		PeekCam.Create();
		PeekCam.Target = attacker > 0 ? attacker : client;
		PeekCam.Perspective = Cam_FirstPerson;

		float seekerPos[3], pos[3];
		// If player died on their own, set attacker to themselves for viewing purposes
		if(attacker <= 0) attacker = client;
		GetClientAbsOrigin(attacker, seekerPos);
		PeekCam.Enable(attacker);

		int alive = 0;
		for(int i = 1; i <= MaxClients; i++) {
			if(IsClientConnected(i) && IsClientInGame(i)) {
				// If death was by a seeker:
				if(attacker == currentSeeker && cvar_peekCam.IntValue & 2) {
					GetClientAbsOrigin(i, pos);
					if(GetVectorDistance(seekerPos, pos) > DEATH_CAM_MIN_DIST) {
						PeekCam.Enable(i);
					}
				}
				if(IsPlayerAlive(i) && GetClientTeam(i) == 2) alive++;
			}
		}

		PrintToConsoleAll("attacker: %N | victim: %N | alive: %d", client, attacker, alive);
		if(client == currentSeeker && alive == 1) {
			// If seeker died
			CPrintToChatAll("{green}Hiders win!");
			gameOver = true;
		} else {
			if(alive == 2) {
				CPrintToChatAll("{green}One hider remains.");
			} else if(alive <= 0) {
				// Player died and not seeker, therefore seeker killed em
				// If who died was not the seeker
				if(attacker == 0) {
					CPrintToChatAll("Seeker has left, game over.");
				}
				if(client == currentSeeker) {
					CPrintToChatAll("{green}Hiders win! The seeker has perished.");
				} else {
					CPrintToChatAll("{green}The seeker %N won!", currentSeeker);
				}

				if(cvar_peekCam.IntValue & 1) {
					PeekCam.Target = client;
					PeekCam.Perspective = Cam_ThirdPerson;
				}

				gameOver = true;
				return;
			} else if(alive > 2 && client != currentSeeker) {
				CPrintToChatAll("{green}%d hiders remain", alive - 1);
			}
		}
		if(peekCamStopTimer != null && IsValidHandle(peekCamStopTimer)) delete peekCamStopTimer;
		peekCamStopTimer = CreateTimer(2.0, Timer_StopPeekCam);
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
					PrintToConsoleAll("[H&S] Seeker does not equal axe-receiver. Possible seeker: %N", client);
				}
				PeekCam.Target = currentSeeker;
				if(!ignoreSeekerBalance && cvar_seekerBalance.BoolValue) {
					if(hasBeenSeeker[currentSeeker]) {
						ArrayList notPlayedSeekers = new ArrayList(1);
						for(int i = 1; i <= MaxClients; i++) {
							if(IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2 && !hasBeenSeeker[i]) {
								notPlayedSeekers.Push(i);
							}
						}
						if(notPlayedSeekers.Length > 0) {
							int newSlasher = notPlayedSeekers.Get(GetURandomInt() % notPlayedSeekers.Length);
							PrintToServer("[H&S] Switching seeker to a new random seeker: %N", newSlasher);
							SetSlasher(newSlasher);
							delete notPlayedSeekers;
							return;
						} else {
							PrintToServer("[H&S] All players have played as seeker, resetting");
							PrintToChatAll("[H&S] Everyone has played as a seeker once");
							for(int i = 1; i <= MaxClients; i++) {
								hasBeenSeeker[i] = false;
							}
							hasBeenSeeker[currentSeeker] = true;
						}
						delete notPlayedSeekers;
					} else {
						hasBeenSeeker[currentSeeker] = true;
					}
				}
				ignoreSeekerBalance = false;
				CPrintToChatAll("{green}%N{yellow} is the seeker", currentSeeker);
			}
		}
	}
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(client > 0 && mapConfig.hasSpawnpoint) {
		TeleportEntity(client, mapConfig.spawnpoint, NULL_VECTOR, NULL_VECTOR);
	}
	PeekCam.Disable(client);
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast) {
	if(mapConfig.hasSpawnpoint) {
		PrintToServer("[H&S] Using provided spawnpoint: %.1f %.1f %.1f", mapConfig.spawnpoint[0], mapConfig.spawnpoint[1], mapConfig.spawnpoint[2]);
	}
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientInGame(i)) {
			if(isPendingPlay[i]) {
				JoinGame(i);
			}
			if(mapConfig.hasSpawnpoint)
				TeleportEntity(i, mapConfig.spawnpoint, NULL_VECTOR, NULL_VECTOR);
		}
	}
	EntFire("relay_intro_start", "Kill");
	EntFire("outro", "Kill");
	CreateTimer(1.0, Timer_SetupEntities);
	CreateTimer(15.0, Timer_RoundStart);
}

public Action Timer_SetupEntities(Handle h) {
	SetupEntities();
	return Plugin_Handled;
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
			distanceTraveled[i] = 0.0;
			PeekCam.Disable(i);
			if(isPendingPlay[i]) {
				JoinGame(i);
			}
		}
	}
	PeekCam.Destroy();
}

public Action Timer_CheckPlayers(Handle h) {
	for(int i = 1; i <= MaxClients; i++) {
		if(!IsClientConnected(i) || !IsClientInGame(i)) continue;

		if(GetClientTeam(i) == 2 && IsPlayerAlive(i) && i != currentSeeker) {
			float pos[3];
			GetClientAbsOrigin(i, pos);
			distanceTraveled[i] = FloatAbs(Get2DVectorDistance(pos, lastPos[i])); 
			
			lastPos[i] = pos;
			QueryClientConVar(i, "cam_collision", QueryClientConVarCallback);
		}
		SetEntProp(i, Prop_Send, "m_audio.soundscapeIndex", -1);
		
	}
	// Rare Crashes:
	// ServerCommand("soundscape_flush");
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

int PLAYER_GLOW_COLOR[3] = { 0, 255, 0 };
public Action Timer_CheckHiders(Handle h) {
	static float seekerLoc[3];
	static float playerLoc[3];
	if(cvar_seekerHelpers.IntValue != 0) return Plugin_Continue;
	if(currentSeeker > 0) {
		GetClientAbsOrigin(currentSeeker, seekerLoc);
	}
	for(int i = 1; i <= MaxClients; i++) {
		if(i != currentSeeker && IsClientConnected(i) && IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == 2) {
			GetClientAbsOrigin(i, playerLoc);
			float dist = GetVectorDistance(seekerLoc, playerLoc, true);
			if(dist > 290000.0) {
				L4D2_SetPlayerSurvivorGlowState(i, true);
				L4D2_SetEntityGlow(i, L4D2Glow_Constant, 0, 10, PLAYER_GLOW_COLOR, true);
				CreateTimer(2.0, Timer_RemoveGlow, GetClientUserId(i));
			}
		}
	}
	return Plugin_Continue;
}

public Action Timer_RemoveGlow(Handle h, int userid) {
	int client = GetClientOfUserId(userid);
	if(client) {
		L4D2_SetPlayerSurvivorGlowState(client, false);
		L4D2_RemoveEntityGlow(client);
	}
	return Plugin_Handled;
}
GameState prevState;

// #define HEARTBEAT_NEAR_DIST 1_000_000
// #define HEARTBEAT_CLOSE_DIST 250_000

#define HEARTBEAT_NEAR_DIST 1000
#define HEARTBEAT_CLOSE_DIST 300

public Action Timer_Music(Handle h) {
	static float seekerLoc[3];
	static float playerLoc[3];
	if(currentSeeker > 0) {
		GetClientAbsOrigin(currentSeeker, seekerLoc);
		GameState state = GetState();
		if(state == State_Hunting) {
			if(prevState == State_Hiding) {
				ShowBeacon(currentSeeker);
				PeekCam.Target = currentSeeker;
				PeekCam.Create();
				PeekCam.Enable();
				CreateTimer(2.2, Timer_StopPeekCam);
			}
			EmitSoundToClient(currentSeeker, SOUND_SUSPENSE_1, currentSeeker, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_CHANGEPITCH, 0.2, 90, currentSeeker, seekerLoc, seekerLoc, true);
		}
		prevState = state;
	}
	int playerCount;

	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientInGame(i) && i != currentSeeker) {
			playerCount++;
			// GetClientAbsOrigin(i, playerLoc);
			// float dist = GetVectorDistance(seekerLoc, playerLoc, true);
			if(currentSeeker == 0) continue;
			float dist = GetFlowDistance(currentSeeker, i);
			if(dist <= HEARTBEAT_CLOSE_DIST) {
				StopSound(i, SNDCHAN_AUTO, SOUND_SUSPENSE_1);
				EmitSoundToClient(i, SOUND_SUSPENSE_1_FAST, i, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_CHANGEPITCH, 1.0, 100, currentSeeker, seekerLoc, playerLoc, true);
				isNearbyPlaying[i] = true;
			} else if(dist <= HEARTBEAT_CLOSE_DIST) {
				EmitSoundToClient(i, SOUND_SUSPENSE_1, i, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_CHANGEPITCH, 0.4, 90, currentSeeker, seekerLoc, playerLoc, true);
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


float GetFlowDistance(int survivorA, int survivorB) {
	return FloatAbs(L4D2Direct_GetFlowDistance(survivorA) - L4D2Direct_GetFlowDistance(survivorB));
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
			SDKHook(entity, SDKHook_TraceAttackPost, Hook_OnAttackPost);
			SetEntProp(entity, Prop_Send, "m_iTeamNum", 0);
		}		
	}
	entity = INVALID_ENT_REFERENCE;
	while ((entity = FindEntityByClassname(entity, "env_soundscape")) != INVALID_ENT_REFERENCE) {
		AcceptEntityInput(entity, "Disable");
		AcceptEntityInput(entity, "Kill");
	}	
	entity = INVALID_ENT_REFERENCE;
	while ((entity = FindEntityByClassname(entity, "env_soundscape_triggerable")) != INVALID_ENT_REFERENCE) {
		AcceptEntityInput(entity, "Disable");
		AcceptEntityInput(entity, "Kill");
	}	
	entity = INVALID_ENT_REFERENCE;
	while ((entity = FindEntityByClassname(entity, "env_soundscape_proxy")) != INVALID_ENT_REFERENCE) {
		AcceptEntityInput(entity, "Disable");
		AcceptEntityInput(entity, "Kill");
	}
	if(mapConfig.mapTime > 0) {
		SetMapTime(mapConfig.mapTime);
	}

	PrintToServer("[H&S] Map time is %d seconds", GetMapTime());
	return Plugin_Continue;
}

static float lastShakeTime;
public void Hook_OnAttackPost(int entity, int attacker, int inflictor, float damage, int damagetype, int ammotype, int hitbox, int hitgroup) {
	if(attacker == currentSeeker && attacker > 0 && GetGameTime() - lastShakeTime > 2.0) {
		lastShakeTime = GetGameTime();
		float min[3], max[3], origin[3], top[3];
		GetEntPropVector(entity, Prop_Send, "m_vecOrigin", origin);
		GetEntPropVector(entity, Prop_Send, "m_vecMins", min);
		GetEntPropVector(entity, Prop_Send, "m_vecMaxs", max);
		PrintHintText(attacker, "Shaking ladder");
		top = origin;
		top[2] = max[2];
		origin[2] = min[2];
		TR_EnumerateEntitiesHull(origin, top, min, max, PARTITION_SOLID_EDICTS, Ray_Enumerator, attacker);
		EmitAmbientSound(SOUND_SHAKE, top, SOUND_FROM_WORLD, SNDLEVEL_SCREAMING, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL);
	}
}
bool Ray_Enumerator(int entity, int attacker) {
	if(entity > 0 && entity <= MaxClients && entity != attacker) {
		L4D_StaggerPlayer(entity, attacker, NULL_VECTOR);
	}
	return true;
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
	if(currentSeeker) {
		int wpn = GetPlayerWeaponSlot(currentSeeker, 1);
		if(wpn > 0) {
			char buffer[32];
			GetEntityClassname(wpn, buffer, sizeof(buffer));
			if(StrEqual(buffer, "melee")) {
				GetEntPropString(wpn, Prop_Data, "m_strMapSetScriptName", buffer, sizeof(buffer));
				if(StrEqual(buffer, "fireaxe")) {
					return Plugin_Continue;
				}
			}
			AcceptEntityInput(wpn, "Kill");
		}
		CheatCommand(currentSeeker, "give", "fireaxe");
	}
	return Plugin_Continue;
}