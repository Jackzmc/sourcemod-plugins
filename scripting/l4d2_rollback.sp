#pragma semicolon 1
#pragma newdecls required

//#define DEBUG

#define PLUGIN_VERSION "1.0"
#define MAXIMUM_STAGES_STORED 3 //The maximum amount of ages to store
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
	description = "System to save and rollback to states in the game, usually pre-troll", 
	version = PLUGIN_VERSION, 
	url = ""
};

enum struct PlayerState {
	int incapState; //0 -> Not incapped, # -> # of incap
	bool isAlive;
	char kitSlotItem[32];
	char pillSlotItem[32];

	int permHealth;
	float tempHealth;

	float position[3];
	float angles[3];

	char recordType[32];
	int timeRecorded;
}

static PlayerState[MAXIMUM_STAGES_STORED][MAXPLAYERS+1] playerStatesList; //Newest -> Oldest

static bool isHealing[MAXPLAYERS+1], bMapStarted; //Is player healing (self, or other)
static ConVar hMaxIncapCount, hDecayRate;
static Handle hAutoSaveTimer;

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
	HookEvent("revive_begin", Event_ReviveBegin);

	RegAdminCmd("sm_save", Command_SaveGlobalState, ADMFLAG_ROOT, "Saves all players state");
	RegAdminCmd("sm_state", Command_ViewStateInfo, ADMFLAG_ROOT, "Views the current state info");
	RegAdminCmd("sm_restore", Command_RestoreState, ADMFLAG_ROOT, "Restores a certain player's state");

}

// /////////////////////////////////////////////////////////////////////////////
// COMMANDS
// /////////////////////////////////////////////////////////////////////////////

public Action Command_SaveGlobalState(int client, int args) {
	RecordGlobalState("MANUAL");
	ReplyToCommand(client, "Saved global state");
	return Plugin_Handled;
}
public Action Command_ViewStateInfo(int client, int args) {
	int time = GetTime(), index;
	for(int state = 0; state < MAXIMUM_STAGES_STORED; state++) {
		if(state == 0 || playerStatesList[state][0].timeRecorded > 0)
			ReplyToCommand(client, "---== Recorded Player States ==--- [Age: %d]", state);
		for(int i = 1; i <= MaxClients; i++) {
			if(playerStatesList[state][i].timeRecorded > 0) {
				int minutes = RoundToNearest((time - playerStatesList[state][i].timeRecorded) / 60.0);
				ReplyToCommand(client, "%2.d. %-16.16N | %-16.20s | %3d min. ago", ++index, i, playerStatesList[state][i].recordType, minutes);
			}
		}
		index = 0;
	}
	return Plugin_Handled;
}
public Action Command_RestoreState(int client, int args) {
	if(args < 1) {
		ReplyToCommand(client, "Usage: sm_restore <player(s)> [age=0]");
	}else{
		char arg1[32], arg2[4];
		GetCmdArg(1, arg1, sizeof(arg1));
		GetCmdArg(2, arg2, sizeof(arg2));

		int index = StringToInt(arg2);
		if(index > MAXIMUM_STAGES_STORED) {
			ReplyToCommand(client, "Age is above maximum amount of ages saved of %d.", MAXIMUM_STAGES_STORED);
			return Plugin_Handled;
		}

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
				if(playerStatesList[index][target].timeRecorded == 0) {
					ReplyToCommand(client, "%N does not have a state, using bare state.");
				}else{
					ReplyToCommand(client, "Restored %N's state to age %d", target, index);
				}
			}
		}
	}
	return Plugin_Handled;
}

// /////////////////////////////////////////////////////////////////////////////
// EVENTS
// /////////////////////////////////////////////////////////////////////////////

public void OnMapStart() {
	CreateTimer(180.0, Timer_AutoRecord, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public void OnClientPutInServer(int client) {
	if(bMapStarted) {
		RecordGlobalState("MAP_START");
		bMapStarted = false;
	}
}

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

public void OnClientDisconnect(int client) {
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2 && !IsFakeClient(i)) {
			ResetStates(i);
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

public Action Event_ReviveBegin(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	int subject = GetClientOfUserId(event.GetInt("subject"));
	if(client && subject) {
		AdminId revived = GetUserAdmin(subject);
		if(revived == INVALID_ADMIN_ID && !IsFakeClient(subject)) {
			RecordGlobalState("REVIVED_NON_ADMIN");
		}
	}
}

public void FTT_OnClientMarked(int troll, int marker) {
	RecordGlobalState("FTT_MARKED");
}
// /////////////////////////////////////////////////////////////////////////////
// TIMERS
// /////////////////////////////////////////////////////////////////////////////
public Action Timer_AutoRecord(Handle h) {
	RecordGlobalState("AUTO_TIMER", 50000);
}
// /////////////////////////////////////////////////////////////////////////////
// METHODS
// /////////////////////////////////////////////////////////////////////////////
void RecordGlobalState(const char[] type, int skipTime = 0) {
	int time = GetTime();
	for(int i = MAXIMUM_STAGES_STORED - 2; i >= 0; i--) {
		TransferArray(i, i+1);
	}

	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2) {
			//If skipTime set, do not record if last recording was <= skipTime ms ago
			if(skipTime > 0 && playerStatesList[0][i].timeRecorded > 0 && time - playerStatesList[0][i].timeRecorded <= skipTime) continue; 

			playerStatesList[0][i].incapState = GetEntProp(i, Prop_Send, "m_currentReviveCount");
			playerStatesList[0][i].isAlive = IsPlayerAlive(i);
			GetClientWeaponName(i, 3, playerStatesList[0][i].kitSlotItem, 32);
			GetClientWeaponName(i, 4, playerStatesList[0][i].pillSlotItem, 32);

			playerStatesList[0][i].permHealth = GetClientHealth(i);
			playerStatesList[0][i].tempHealth = GetClientHealthBuffer(i);

			GetClientAbsOrigin(i, playerStatesList[0][i].position);
			GetClientAbsAngles(i, playerStatesList[0][i].angles);

			strcopy(playerStatesList[0][i].recordType, 32, type);
			playerStatesList[0][i].timeRecorded = time;
		}
		playerStatesList[0][0].timeRecorded = time;
	}
	//PrintToConsoleAll("[Rollback] Recorded all player states for: %s", type);
}

void TransferArray(int oldIndex, int newIndex) {
	for(int i = 1; i <= MaxClients; i++) {
		playerStatesList[newIndex][i].incapState = playerStatesList[oldIndex][i].incapState;
		playerStatesList[newIndex][i].isAlive = playerStatesList[oldIndex][i].isAlive;
		strcopy(playerStatesList[newIndex][i].kitSlotItem, 32, playerStatesList[oldIndex][i].kitSlotItem);
		strcopy(playerStatesList[newIndex][i].pillSlotItem, 32, playerStatesList[oldIndex][i].pillSlotItem);

		playerStatesList[newIndex][i].permHealth = playerStatesList[oldIndex][i].permHealth;
		playerStatesList[newIndex][i].tempHealth = playerStatesList[oldIndex][i].tempHealth;

		playerStatesList[newIndex][i].position = playerStatesList[oldIndex][i].position;
		playerStatesList[newIndex][i].angles = playerStatesList[oldIndex][i].angles;

		strcopy(playerStatesList[newIndex][i].recordType, 32, playerStatesList[oldIndex][i].recordType);
		playerStatesList[newIndex][i].timeRecorded = playerStatesList[oldIndex][i].timeRecorded;
	}
	playerStatesList[newIndex][0].timeRecorded = playerStatesList[oldIndex][0].timeRecorded;
}

void RestoreState(int client, int index = 0) {
	char item[32];
	bool isIncapped = GetEntProp(client, Prop_Send, "m_isIncapacitated") == 1;

	bool respawned = false;
	if(!IsPlayerAlive(client) && playerStatesList[index][client].isAlive) {
		SDKCall(hRoundRespawn, client);
		DataPack pack = CreateDataPack();
		pack.WriteCell(GetClientUserId(client));
		for(int i = 0; i < 3; i++) {
			pack.WriteFloat(playerStatesList[index][client].position[i]);
		}
		for(int i = 0; i < 3; i++) {
			pack.WriteFloat(playerStatesList[index][client].angles[i]);
		}
		CreateDataTimer(0.1, Timer_Teleport, pack);
		respawned = true;
	}else if(isIncapped) {
		CheatCommand(client, "give", "health", "");
		TeleportEntity(client, playerStatesList[index][client].position, playerStatesList[index][client].angles, ZERO_VECTOR);
	}
	SetEntProp(client, Prop_Send, "m_currentReviveCount", playerStatesList[index][client].incapState);
	SetEntProp(client, Prop_Send, "m_bIsOnThirdStrike", playerStatesList[index][client].incapState >= hMaxIncapCount.IntValue);
	SetEntProp(client, Prop_Send, "m_isGoingToDie", playerStatesList[index][client].incapState >= hMaxIncapCount.IntValue);

	if(!respawned) {
		GetClientWeaponName(client, 3, item, sizeof(item));
		if(!StrEqual(playerStatesList[index][client].pillSlotItem, item) && !isHealing[client]) {
			CheatCommand(client, "give", item, "");
		}
		GetClientWeaponName(client, 4, item, sizeof(item));
		if(!StrEqual(playerStatesList[index][client].pillSlotItem, item)) {
			CheatCommand(client, "give", item, "");
		}
	}
	SetEntProp(client, Prop_Send, "m_iHealth", playerStatesList[index][client].permHealth > 0 ? playerStatesList[index][client].permHealth : 10); 
	SetEntPropFloat(client, Prop_Send, "m_healthBuffer", playerStatesList[index][client].tempHealth);
	SetEntPropFloat(client, Prop_Send, "m_healthBufferTime", GetGameTime());
}

void ResetStates(int client) {
	for(int stage = 0; stage < MAXIMUM_STAGES_STORED; stage++) {
		playerStatesList[stage][client].incapState = 0;//TODO: get incap state
		playerStatesList[stage][client].pillSlotItem[0] = '\0';
		playerStatesList[stage][client].kitSlotItem[0] = '\0';
		playerStatesList[stage][client].permHealth = 0;
		playerStatesList[stage][client].tempHealth = 0.0;
		playerStatesList[stage][client].timeRecorded = 0;
		playerStatesList[stage][client].recordType[0] = '\0';
	}
}

float GetClientHealthBuffer(int client, float defaultVal=0.0) {
    // https://forums.alliedmods.net/showpost.php?p=1365630&postcount=1
    static float healthBuffer, healthBufferTime, tempHealth;
    healthBuffer = GetEntPropFloat(client, Prop_Send, "m_healthBuffer");
    healthBufferTime = GetGameTime() - GetEntPropFloat(client, Prop_Send, "m_healthBufferTime");
    tempHealth = healthBuffer - (healthBufferTime / (1.0 / hDecayRate.FloatValue));
    return tempHealth < 0.0 ? defaultVal : tempHealth;
}

public Action Timer_Teleport(Handle handle, DataPack pack) {
	pack.Reset();
	int client = pack.ReadCell();
	float position[3], angles[3];

	for(int i = 0; i < 3; i++) {
		position[i] = pack.ReadFloat();
	}
	for(int i = 0; i < 3; i++) {
		angles[i] = pack.ReadFloat();
	}

	TeleportEntity(client, position, angles, ZERO_VECTOR);
}