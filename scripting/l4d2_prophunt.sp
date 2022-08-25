#pragma semicolon 1
#pragma newdecls required

//#define DEBUG

#define PLUGIN_VERSION "1.0"
#define BLIND_TIME 30
#define DEFAULT_GAME_TIME 600

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <left4dhooks>


enum GameState {
	State_Unknown = 0,
	State_Hiding,
	State_Active,
	State_PropsWin,
	State_SeekerWin,
}

#define MAX_VALID_MODELS 2
char VALID_MODELS[MAX_VALID_MODELS][] = {
	"models/props_crates/static_crate_40.mdl",
	"models/props_junk/gnome.mdl"
};

#define TRANSPARENT "255 255 255 0"
#define WHITE "255 255 255 255"

enum struct PropData {
	int prop;
	bool rotationLock;
}

UserMsg g_FadeUserMsgId;

PropData propData[MAXPLAYERS+1];

bool isSeeker[MAXPLAYERS+1];
bool hasBeenSeeker[MAXPLAYERS+1];
bool isStarting, firstCheckDone;

Handle timesUpTimer;
Handle waitTimer;

PropHuntGame Game;

#include <gamemodes/base>
#include <prophunt/phcore>

public Plugin myinfo = 
{
	name =  "Prophunt", 
	author = "jackzmc", 
	description = "", 
	version = PLUGIN_VERSION, 
	url = "https://github.com/Jackzmc/sourcemod-plugins"
};

public void OnPluginStart() {
	EngineVersion g_Game = GetEngineVersion();
	if(g_Game != Engine_Left4Dead2) {
		SetFailState("This plugin is for L4D2 only.");	
	}
	Game.Init("PropHunt");

	g_FadeUserMsgId = GetUserMessageId("Fade");

	RegConsoleCmd("sm_game", Command_Test);
	RegAdminCmd("sm_prophunt", Command_PropHunt, ADMFLAG_KICK);
	RegAdminCmd("sm_ph", Command_PropHunt, ADMFLAG_KICK);

	ConVar hGamemode = FindConVar("mp_gamemode"); 
	hGamemode.AddChangeHook(Event_GamemodeChange);
	Event_GamemodeChange(hGamemode, gamemode, gamemode);
}

public void OnPluginEnd() {
	OnMapEnd();
}

void Event_RoundStart(Event event, const char[] name, bool dontBroadcast) {
	waitTimer = CreateTimer(firstCheckDone ? 2.5 : 6.0, Timer_WaitForPlayers, _, TIMER_REPEAT);
}

void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast) {
	// Skip the check, everyone's loaded in
	firstCheckDone = true;
}


public void OnClientPutInServer(int client) {
	if(!isEnabled) return;
	if(IsFakeClient(client)) {
		KickClient(client, "ph: Remove Special Infected");
	} else {
		ChangeClientTeam(client, 1);
		isPendingPlay[client] = true;
		Game.Broadcast("%N will play next round", client);
		Game.TeleportToSpawn(client);
	}
}


public void OnClientDisconnect(int client) {
	if(!isEnabled) return;
	ResetPlayerData(client);
	if(Game.IsSeeker(client)) {
		if(Game.SeekersAlive == 0) {
			Game.Broadcast("All seekers have disconnected, Props win");
			Game.End(State_PropsWin);
		}
	} else if(Game.PropsAlive == 0) {
		Game.Broadcast("All hiders have disconnected, Seekers win");
		Game.End(State_SeekerWin);
	}
}

public void Event_GamemodeChange(ConVar cvar, const char[] oldValue, const char[] newValue) {
	cvar.GetString(gamemode, sizeof(gamemode));
	bool shouldEnable = StrEqual(gamemode, "prophunt", false);
	if(isEnabled == shouldEnable) return;
	firstCheckDone = false;
	if(shouldEnable) {
		Game.Broadcast("Gamemode is starting");
		HookEvent("round_start", Event_RoundStart);
		HookEvent("round_end", Event_RoundEnd);
		HookEvent("player_death", Event_PlayerDeath);
	} else if(!lateLoaded) {
		UnhookEvent("round_start", Event_RoundStart);
		UnhookEvent("round_end", Event_RoundEnd);
		UnhookEvent("player_death", Event_PlayerDeath);
		Game.Cleanup();
	}
	isEnabled = shouldEnable;
}

public void OnMapStart() {
	for(int i = 0; i < MAX_VALID_MODELS; i++) {
		PrecacheModel(VALID_MODELS[i]);
	}
	isStarting = false;
	if(!isEnabled) return;

	char map[128];
	GetCurrentMap(map, sizeof(map));
	if(!StrEqual(g_currentMap, map)) {
		firstCheckDone = false;
		strcopy(g_currentSet, sizeof(g_currentSet), "default");
		ReloadMapDB();
		strcopy(g_currentMap, sizeof(g_currentMap), map);
	}


	if(lateLoaded) {
		for(int i = 1; i <= MaxClients; i++) {
			if(IsClientConnected(i) && IsClientInGame(i)) {
				Game.SetupPlayer(i);
			}
		}
		InitGamemode();
	}
	Game.State = State_Unknown;
}

void InitGamemode() {
	if(isStarting && Game.State != State_Unknown) {
		Game.Warn("InitGamemode() called in an incorrect state (%d)", Game.State);
		return;
	}
	SetupEntities();
	Game.DebugConsole("InitGamemode(): activating");
	ArrayList validPlayerIds = new ArrayList();
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i)) {
			if(IsFakeClient(i)) {
				KickClient(i);
			} else {
				Game.SetupPlayer(i);
				if(!IsPlayerAlive(i)) {
					L4D_RespawnPlayer(i);
				}
				if(!hasBeenSeeker[i])
					validPlayerIds.Push(GetClientUserId(i));
			}
		}
	}
	if(validPlayerIds.Length == 0) {
		Game.Warn("Ignoring InitGamemode() with no valid survivors");
		return;
	}
	int numberOfSeekers = RoundToCeil(float(validPlayerIds.Length) / 3.0);
	int timeout = 0;
	while(numberOfSeekers > 0 && timeout < 2) {
		int newSeeker = GetClientOfUserId(validPlayerIds.Get(GetURandomInt() % validPlayerIds.Length));
		if(newSeeker > 0) {
			hasBeenSeeker[newSeeker] = true;
			Game.SetSeeker(newSeeker, true);
			Game.Broadcast("%N is a seeker", newSeeker);
			numberOfSeekers--;
			SetPlayerBlind(newSeeker, 255);
			SetEntPropFloat(newSeeker, Prop_Send, "m_flLaggedMovementValue", 0.0);
		} else {
			timeout++;
		}
	}
	delete validPlayerIds;
	Game.TeleportAllToStart();
	Game.MapTime = BLIND_TIME;
	Game.Tick = 0;
	Game.State = State_Hiding;
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && !Game.IsSeeker(i)) {
			PrintToChatAll("setting up non seeker %N", i);
			Game.SetupProp(i);
		}
	}
	CreateTimer(float(BLIND_TIME), Timer_StartGame);
}

void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	if(client > 0 && Game.State == State_Active) {
		if(Game.SeekersAlive == 0) {
			Game.Broadcast("All seekers have perished. Hiders win!");
			Game.End(State_PropsWin);
		} else if(Game.PropsAlive == 0) {
			Game.Broadcast("Seekers win!");
			Game.End(State_SeekerWin);
		}
	}
}

void ResetPlayerData(int client) {
	if(propData[client].prop > 0) {
		AcceptEntityInput(propData[client].prop, "Kill");
		propData[client].prop = 0;
	}
	propData[client].rotationLock = false;
}

public void OnMapEnd() {
	for(int i = 1; i <= MaxClients; i++) {
		ResetPlayerData(i);
		if(IsClientConnected(i) && IsClientInGame(i)) {
			Game.UnsetupPlayer(i);
		}
	}
}

void ClearInventory(int client) {
	for(int i = 0; i <= 5; i++) {
		int item = GetPlayerWeaponSlot(client, i);
		if(item > 0) {
			AcceptEntityInput(item, "Kill");
		}
	}
}

public Action Command_Test(int client, int args) {
	InitGamemode();
	return Plugin_Handled;
}

Action OnPropTransmit(int entity, int client) {
	return propData[client].prop == entity ? Plugin_Stop : Plugin_Continue;
}

Action OnPlayerTransmit(int entity, int client) {
	return entity == client ? Plugin_Continue : Plugin_Stop;
}

int CreatePropInternal(const char[] model) {
	int entity = CreateEntityByName("prop_dynamic");
	DispatchKeyValue(entity, "model", model);
	DispatchKeyValue(entity, "disableshadows", "1");
	DispatchKeyValue(entity, "targetname", "phprop");
	DispatchSpawn(entity);
	SetEntProp(entity, Prop_Send, "m_nSolidType", 6);
	SetEntProp(entity, Prop_Send, "m_CollisionGroup", 1);
	SetEntProp(entity, Prop_Send, "movetype", MOVETYPE_NONE);
	return entity;
}

public Action OnPlayerRunCmd(int client, int& buttons, int& impulse, float vel[3], float angles[3], int& weapon, int& subtype, int& cmdnum, int& tickcount, int& seed, int mouse[2]) {
	// if(!isEnabled) return Plugin_Continue;
	int oldButtons = GetEntProp(client, Prop_Data, "m_nOldButtons");
	if(buttons & IN_RELOAD && !(oldButtons & IN_RELOAD)) {
		propData[client].rotationLock = !propData[client].rotationLock;
		PrintHintText(client, "Rotation lock now %s", propData[client].rotationLock ? "enabled" : "disabled"); 
		return Plugin_Continue;
	}
	if(propData[client].prop > 0) {
		static float pos[3], ang[3];
		GetClientAbsOrigin(client, pos);
		TeleportEntity(client, pos, NULL_VECTOR, NULL_VECTOR);
		if(propData[client].rotationLock)
			TeleportEntity(propData[client].prop, pos, NULL_VECTOR, NULL_VECTOR);
		else {
			ang[0] = 0.0;
			ang[1] = angles[1];
			ang[2] = 0.0;
			TeleportEntity(propData[client].prop, pos, ang, NULL_VECTOR);
		}
	}
	return Plugin_Continue;
}

Action OnTakeDamageAlive(int victim, int& attacker, int& inflictor, float& damage, int& damagetype) {
	if(Game.IsSeeker(attacker)) {
		if(victim <= MaxClients && victim > 0) {
			damage = 10.0;
			return Plugin_Changed;
		} else {
			SDKHooks_TakeDamage(attacker, 0, 0, 10.0, DMG_DIRECT);
			damage = 0.0;
			return Plugin_Handled;
		}
	} else {
		damage = 0.0;
		return Plugin_Handled;
	}
}
