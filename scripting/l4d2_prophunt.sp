#pragma semicolon 1
#pragma newdecls required

//#define DEBUG

#define PLUGIN_VERSION "1.0"

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <gamemodes/base>
#include <gamemodes/ents>

enum GameState {
	State_Unknown = 0,
	State_Hiding,
	State_Active,
	State_PropsWin,
	State_SeekerWin,
}

#define MAX_VALID_MODELS 2
static char VALID_MODELS[MAX_VALID_MODELS][] = {
	"models/props_crates/static_crate_40.mdl",
	"models/props_junk/gnome.mdl"
};

static float EMPTY_ANG[3];
#define TRANSPARENT "255 255 255 0"
#define WHITE "255 255 255 255"

enum struct PropData {
	int prop;
	bool rotationLock;
}

PropData propData[MAXPLAYERS+1];

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
	RegConsoleCmd("sm_game", Command_Test);
}

public void OnMapStart() {
	for(int i = 0; i < MAX_VALID_MODELS; i++) {
		PrecacheModel(VALID_MODELS[i]);
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
			DispatchKeyValue(i, "rendercolor", WHITE);
		}
	}
}

public void OnClientDisconnect(int client) {
	ResetPlayerData(client);
}

public Action Command_Test(int client, int args) {
	int prop = CreatePropInternal(VALID_MODELS[0]);
	if(prop <= 0) {
		ReplyToCommand(client, "Failed to spawn prop");
		return Plugin_Handled;
	}
	float pos[3];
	propData[client].prop = prop;
	DispatchKeyValue(client, "rendercolor", TRANSPARENT);
	// SetParent(prop, client);
	// SetParentAttachment(prop, "eyes", true);
	// TeleportEntity(prop, pos, EMPTY_ANG, NULL_VECTOR);
	// SetParentAttachment(prop, "eyes", true);
	SDKHook(client, SDKHook_SetTransmit, OnPlayerTransmit);
	ReplyToCommand(client, "Game!");
	return Plugin_Handled;
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
	if(propData[client].prop > 0) {
		static float pos[3], ang[3];
		GetClientAbsOrigin(client, pos);
		TeleportEntity(client, pos, NULL_VECTOR, NULL_VECTOR);
		if(propData[client].rotationLock)
			TeleportEntity(propData[client].prop, NULL_VECTOR, angles, NULL_VECTOR);
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
	/*if(attacker == currentSeeker) {
		damage = 100.0;
		ClearInventory(victim);
		if(attacker > 0 && attacker <= MaxClients && IsFakeClient(victim)) {
			PrintToChat(attacker, "That was a bot! -%.0f health", cvar_seekerFailDamageAmount.FloatValue);
			SDKHooks_TakeDamage(attacker, 0, 0, cvar_seekerFailDamageAmount.FloatValue, DMG_DIRECT);
		}
		return Plugin_Changed;
	} else if(attacker > 0 && attacker <= MaxClients) {
		damage = 0.0;
		return Plugin_Changed;
	} else {
		return Plugin_Continue;
	}*/
	return Plugin_Continue;
}
