#pragma semicolon 1
#pragma newdecls required

//#define DEBUG

#define PLUGIN_VERSION "1.0"
#define LAST_FF_TIME_THRESHOLD 100.0
#define LAST_PLAYER_JOIN_THRESHOLD 120.0

#include <sourcemod>
#include <sdktools>
#include <jutils>
#include <left4dhooks>

static Handle hRoundRespawn;

public Plugin myinfo = 
{
	name =  "L4D2 Rollback", 
	author = "jackzmc", 
	description = "", 
	version = PLUGIN_VERSION, 
	url = ""
};

/*
Allows you to rollback to state,
auto recorded at: player join, or FF event

*/
enum struct PlayerState {
	int incapState; //0 -> Not incapped, # -> # of incap
	bool isAlive;
	bool hasKit;
	char pillSlotItem[32];

	int permHealth;
	float tempHealth;

	float position[3];
	float angles[3];

	char recordType[32];
	int timeRecorded;
}

static PlayerState[MAXPLAYERS+1] playerStates;

static bool isHealing[MAXPLAYERS+1]; //Is player healing (self, or other)
static ConVar hMaxIncapCount, hDecayRate;

static float ZERO_VECTOR[3] = {0.0, 0.0, 0.0}, lastDamageTime, lastSpawnTime;

public void OnPluginStart() {
	EngineVersion g_Game = GetEngineVersion();
	if(g_Game != Engine_Left4Dead2) {
		SetFailState("This plugin is for L4D/L4D2 only.");	
	}
	Handle hGameConf = LoadGameConfigFile("left4dhooks.l4d2");
	if (hGameConf != INVALID_HANDLE) {
		StartPrepSDKCall(SDKCall_Player);
		PrepSDKCall_SetFromConf(hGameConf, SDKConf_Signature, "RoundRespawn");
		hRoundRespawn = EndPrepSDKCall();
		if (hRoundRespawn == INVALID_HANDLE) SetFailState("L4D2_Rollback: RoundRespawn Signature broken");
		
	} else {
		SetFailState("Could not find gamedata: l4d2_rollback.txt.");
	}

	hMaxIncapCount = FindConVar("survivor_max_incapacitated_count");
	hDecayRate = FindConVar("pain_pills_decay_rate");

	HookEvent("heal_begin", Event_HealBegin);
	HookEvent("heal_end", Event_HealStop);

	HookEvent("player_first_spawn", Event_PlayerFirstSpawn);
	HookEvent("player_hurt", Event_PlayerHurt);

	RegAdminCmd("sm_sstate", Command_SaveGlobalState, ADMFLAG_ROOT, "Saves all players state");
	RegAdminCmd("sm_istate", Command_ViewStateInfo, ADMFLAG_ROOT, "Views the current state info");
	RegAdminCmd("sm_rstate", Command_RestoreState, ADMFLAG_ROOT, "Restores a certain player's state");
}

// /////////////////////////////////////////////////////////////////////////////
// COMMANDS
// /////////////////////////////////////////////////////////////////////////////

public Action Command_SaveGlobalState(int client, int args) {
	RecordGlobalState("MANUAL");
}
public Action Command_ViewStateInfo(int client, int args) {
	ReplyToCommand(client, "---== Recorded Player States ==---");
	int index = 0;
	int time = GetTime();

	for(int i = 1; i <= MaxClients; i++) {
		if(playerStates[i].timeRecorded > 0) {
			int minutes = RoundToNearest((time - playerStates[i].timeRecorded) / 1000.0 / 60.0);
			ReplyToCommand(client, "%d. %16.16N - %20s - %-3d min. ago", ++index, i, playerStates[i].recordType, minutes);
		}
	}
}
public Action Command_RestoreState(int client, int args) {
	if(args < 1) {
		ReplyToCommand(client, "Usage: sm_srestore <player>");
	}else{
		char arg1[32];
		GetCmdArg(1, arg1, sizeof(arg1));

		char target_name[MAX_TARGET_LENGTH];
		int target_list[MAXPLAYERS], target_count;
		bool tn_is_ml;
		if ((target_count = ProcessTargetString(
			arg1,
			client,
			target_list,
			MAXPLAYERS,
			COMMAND_FILTER_CONNECTED,
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
			if(IsClientConnected(target) && IsClientInGame(target) && GetClientTeam(target) == 2) {
				RestoreState(target);
				//ReplyToCommand(client, "Restored %N's state", target);
			}
		}
	}
	return Plugin_Handled;
}

// /////////////////////////////////////////////////////////////////////////////
// EVENTS
// /////////////////////////////////////////////////////////////////////////////

public Action Event_PlayerFirstSpawn(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	//Ignore admins
	if(!IsFakeClient(client) && GetClientTeam(client) == 2 && GetUserAdmin(client) == INVALID_ADMIN_ID) {
		float time = GetGameTime();
		if(time - lastSpawnTime >= LAST_PLAYER_JOIN_THRESHOLD) {
			RecordGlobalState("JOIN");
			lastSpawnTime = time;
		}
	}
}

void OnClientDisconnect(int client) {
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2) {
			playerStates[i].incapState = 0;//TODO: get incap state
			playerStates[i].wasKilled = false;
			players[i].pillSlotItem[0] = '\0';
			playerStates[i].hasKit = false;
			playerStates[i].prePermHealth = 0;
			//TODO: record temp health
		}
	}
}

public Action Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast) {
	float currentTime = GetGameTime();
	if(currentTime - lastDamageTime >= LAST_FF_TIME_THRESHOLD) {
		int client = GetClientOfUserId(event.GetInt("userid"));
		int attackerID = event.GetInt("attacker");
		int damage = event.GetInt("dmg_health");
		if(client && GetClientTeam(client) == 2 && attackerID > 0 && damage > 0) {
			int attacker = GetClientOfUserId(attackerID);
			if(GetClientTeam(attacker) == 2) {
				lastDamageTime = GetGameTime();
				RecordGlobalState("FRIENDLY_FIRE");
			}
		}

	}
}

public Action Event_HealBegin(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	isHealing[client] = true;
}
public Action Event_HealStop(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	isHealing[client] = false;
}

// /////////////////////////////////////////////////////////////////////////////
// METHODS
// /////////////////////////////////////////////////////////////////////////////
void RecordGlobalState(const char[] type) {
	char item[32];
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2) {
			playerStates[i].incapState = GetEntProp(i, Prop_Send, "m_currentReviveCount");
			playerStates[i].isAlive = IsPlayerAlive(i);
			GetClientWeaponName(i, 3, item, sizeof(item));
			playerStates[i].hasKit = StrEqual(item, "weapon_first_aid_kit");
			GetClientWeaponName(i, 4, playerStates[i].pillSlotItem, 32);

			playerStates[i].permHealth = GetClientHealth(i);
			playerStates[i].tempHealth = GetClientHealthBuffer(i);

			GetClientAbsOrigin(i, playerStates[i].position);
			GetClientAbsAngles(i, playerStates[i].angles);

			strcopy(playerStates[i].recordType, 32, type);
			playerStates[i].timeRecorded = GetTime();
		}
	}
	PrintToConsoleAll("[Rollback] Recorded all player states for: %s", type);
}

void RestoreState(int client) {
	char item[32];
	bool isIncapped = GetEntProp(client, Prop_Send, "m_isIncapacitated") == 1;

	bool respawned = false;
	if(!IsPlayerAlive(client) && playerStates[client].isAlive) {
		SDKCall(hRoundRespawn, client);
		RequestFrame(Frame_Teleport, client);
		respawned = true;
	}else if(isIncapped) {
		CheatCommand(client, "give", "health", "");
		TeleportEntity(client, playerStates[client].position, playerStates[client].angles, ZERO_VECTOR);
	}
	SetEntProp(client, Prop_Send, "m_currentReviveCount", playerStates[client].incapState);
	SetEntProp(client, Prop_Send, "m_bIsOnThirdStrike", playerStates[client].incapState >= hMaxIncapCount.IntValue);
	SetEntProp(client, Prop_Send, "m_isGoingToDie", playerStates[client].incapState >= hMaxIncapCount.IntValue);

	if(!respawned) {
		GetClientWeaponName(client, 3, item, sizeof(item));
		if(playerStates[client].hasKit && !StrEqual(item, "weapon_first_aid_kit") && !isHealing[client]) {
			CheatCommand(client, "give", "first_aid_kit", "");
		}
		GetClientWeaponName(client, 4, item, sizeof(item));
		if(!StrEqual(playerStates[client].pillSlotItem, item)) {
			CheatCommand(client, "give", item, "");
		}
	}
	SetEntProp(client, Prop_Send, "m_iHealth", playerStates[client].permHealth); 
	SetEntPropFloat(client, Prop_Send, "m_healthBuffer", playerStates[client].tempHealth);
	SetEntPropFloat(client, Prop_Send, "m_healthBufferTime", GetGameTime());
}

float GetClientHealthBuffer(int client, float defaultVal=0.0) {
    // https://forums.alliedmods.net/showpost.php?p=1365630&postcount=1
    static float healthBuffer, healthBufferTime, tempHealth;
    healthBuffer = GetEntPropFloat(client, Prop_Send, "m_healthBuffer");
    healthBufferTime = GetGameTime() - GetEntPropFloat(client, Prop_Send, "m_healthBufferTime");
    tempHealth = healthBuffer - (healthBufferTime / (1.0 / hDecayRate.FloatValue));
    return tempHealth < 0.0 ? defaultVal : tempHealth;
}

public void Frame_Teleport(int client) {
	TeleportEntity(client, playerStates[client].position, playerStates[client].angles, ZERO_VECTOR);
}