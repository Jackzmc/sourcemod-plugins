#pragma semicolon 1
#pragma newdecls required

//#define DEBUG

#define PLUGIN_VERSION "1.0"

#include <sourcemod>
#include <sdktools>
//#include <sdkhooks>

public Plugin myinfo = 
{
	name =  "Admin Activity Log", 
	author = "jackzmc", 
	description = "", 
	version = PLUGIN_VERSION, 
	url = ""
};

enum struct Log {
	char name[32];
	char clientSteamID[32];
	char targetSteamID[32];
	char message[256];
	int timestamp;
}
// Plugin data
static ArrayList logs;
static Database g_db;
static char serverID[64];
static Handle pushTimer;
static ConVar hLogCvarChanges;
static char lastMap[64];

//Plugin related
static bool lateLoaded;
static EngineVersion g_Game;

//L4d2 Specific
static char L4D2_ZDifficulty[16];
//Generic
static char currentGamemode[32];

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("ActivityMonitor_AddLog", Native_AddLog);
	lateLoaded = late;
	return APLRes_Success;
}

public void OnPluginStart() {
	g_Game = GetEngineVersion();
	logs = new ArrayList(sizeof(Log));

	if(!SQL_CheckConfig("activitymonitor")) {
		SetFailState("No database entry for 'activitymonitor'; no database to connect to.");
	} else if(!ConnectDB()) {
		SetFailState("Failed to connect to database.");
	}

	hLogCvarChanges = CreateConVar("sm_activitymonitor_log_cvar", "0", "Should this plugin log cvar changes (when using sm_cvar from console)");
	ConVar hServerID = CreateConVar("sm_activitymonitor_id", "", "The name to use for the 'server' column", FCVAR_DONTRECORD);
	hServerID.GetString(serverID, sizeof(serverID));
	hServerID.AddChangeHook(CVAR_ServerIDChanged);

	HookEvent("player_first_spawn", Event_Connection);
	HookEvent("player_disconnect", Event_Connection);
	if(g_Game == Engine_Left4Dead2 || g_Game == Engine_Left4Dead) {
		HookEvent("player_incapacitated", Event_L4D2_Incapped);
		HookEvent("player_death", Event_L4D2_Death);
		ConVar zDifficulty = FindConVar("z_difficulty");
		zDifficulty.GetString(L4D2_ZDifficulty, sizeof(L4D2_ZDifficulty));
		CVAR_DifficultyChanged(zDifficulty, "", L4D2_ZDifficulty);
		zDifficulty.AddChangeHook(CVAR_DifficultyChanged);

		zDifficulty.GetString(L4D2_ZDifficulty, sizeof(L4D2_ZDifficulty));
		CVAR_DifficultyChanged(zDifficulty, "", L4D2_ZDifficulty);
		zDifficulty.AddChangeHook(CVAR_DifficultyChanged);
	}

	ConVar mpGamemode = FindConVar("mp_gamemode");
	if(mpGamemode != null) {
		mpGamemode.GetString(currentGamemode, sizeof(currentGamemode));
		mpGamemode.AddChangeHook(CVAR_GamemodeChanged);
	}


	if(!lateLoaded) {
		AddLog("INFO", "", "", "Server has started up");
	}

	pushTimer = CreateTimer(60.0, Timer_PushLogs, _, TIMER_REPEAT);
	// AutoExecConfig(true, "activitymonitor");
}

public void OnPluginEnd() {
	TriggerTimer(pushTimer, true);
}

public void OnMapStart() {
	static char curMap[64];
	GetCurrentMap(curMap, sizeof(curMap));
	if(!StrEqual(lastMap, curMap)) {
		strcopy(lastMap, sizeof(lastMap), curMap);
		if(g_Game == Engine_Left4Dead2 || g_Game == Engine_Left4Dead)
			Format(curMap, sizeof(curMap), "Map changed to %s (%s %s)", curMap, L4D2_ZDifficulty, currentGamemode);
		else
			Format(curMap, sizeof(curMap), "Map changed to %s (%s)", curMap, currentGamemode);
		AddLog("INFO", "", "", curMap);
	}
	TriggerTimer(pushTimer, true);
}

public void CVAR_GamemodeChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
	strcopy(currentGamemode, sizeof(currentGamemode), newValue);
}

public void CVAR_ServerIDChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
	strcopy(serverID, sizeof(serverID), newValue);
}

public void CVAR_DifficultyChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
	if(StrEqual(newValue, "Hard", false)) strcopy(L4D2_ZDifficulty, sizeof(L4D2_ZDifficulty), "Advanced");
	else if(StrEqual(newValue, "Impossible", false)) strcopy(L4D2_ZDifficulty, sizeof(L4D2_ZDifficulty), "Expert");
	else {
		strcopy(L4D2_ZDifficulty, sizeof(L4D2_ZDifficulty), newValue);
		// CVAR value could be lowercase 'normal', convert to 'Normal'
		L4D2_ZDifficulty[0] = CharToUpper(L4D2_ZDifficulty[0]);
	}
}

bool ConnectDB() {
    char error[255];
    g_db = SQL_Connect("activitymonitor", true, error, sizeof(error));
    if (g_db == null) {
		LogError("Database error %s", error);
		delete g_db;
		return false;
    } else {
		PrintToServer("[ACTM] Connected to database \"activitymonitor\"");
		SQL_LockDatabase(g_db);
		SQL_FastQuery(g_db, "SET NAMES \"UTF8mb4\"");  
		SQL_UnlockDatabase(g_db);
		g_db.SetCharset("utf8mb4");
		return true;
    }
}

public Action Timer_PushLogs(Handle h) {
	static char query[1024];
	static Log log;
	int length = logs.Length;
	Transaction transaction = new Transaction();
	if(length > 0) {
		for(int i = 0; i < length; i++) {
			logs.GetArray(i, log, sizeof(log));
			g_db.Format(query, sizeof(query), "INSERT INTO `activity_log` (`timestamp`, `server`, `type`, `client`, `target`, `message`) VALUES (%d, NULLIF('%s', ''), '%s', NULLIF('%s', ''), NULLIF('%s', ''), NULLIF('%s', ''))",
				log.timestamp,
				serverID, 
				log.name,
				log.clientSteamID,
				log.targetSteamID,
				log.message
			);
			transaction.AddQuery(query);
		}
		logs.Resize(logs.Length - length);
	}
	g_db.Execute(transaction, _, SQL_TransactionFailed, length, DBPrio_Low);
}
public void SQL_TransactionFailed(Database db, any data, int numQueries, const char[] error, int failIndex, any[] queryData) {
	PrintToServer("[ActivityMonitor] Push failure: %s at query %d/%d", error, failIndex, numQueries);
}

public void Event_Connection(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(client > 0 && !IsFakeClient(client)) {
		static char clientName[32];
		if(GetClientAuthId(client, AuthId_Steam2, clientName, sizeof(clientName))) {
			if(name[7] == 'f') {
				AddLog("JOIN", clientName, "", "");
			} else {
				AddLog("QUIT", clientName, "", "");
			}
		}
	}
}
public Action OnLogAction(Handle source, Identity identity, int client, int target, const char[] message) {
	// Ignore cvar changed msgs (from server.cfg)
	if(client == 0 && !hLogCvarChanges.BoolValue && strcmp(message[31], "changed cvar") >= 0) return Plugin_Continue;

	static char clientName[32], targetName[32];
	if(client == 0) clientName = "Server";
	else if(client > 0) GetClientAuthId(client, AuthId_Steam2, clientName, sizeof(clientName));
	else clientName[0] = '\0';

	if(target > 0 && !IsFakeClient(target)) GetClientAuthId(target, AuthId_Steam2, targetName, sizeof(targetName));
	else targetName[0] = '\0';

	AddLog("ACTION", clientName, targetName, message);
	return Plugin_Continue;
}

public void OnClientSayCommand_Post(int client, const char[] command, const char[] sArgs) {
	if(client > 0 && !IsFakeClient(client)) {
		static char clientName[32];
		GetClientAuthId(client, AuthId_Steam2, clientName, sizeof(clientName));
		AddLog("CHAT", clientName, "", sArgs);
	}
}

public void Event_L4D2_Death(Event event, const char[] name, bool dontBroadcast) {
	int victim = GetClientOfUserId(event.GetInt("userid"));
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	if(victim > 0 && GetClientTeam(victim) == 2) { //victim is a survivor
		static char victimName[32], attackerName[32];

		if(IsFakeClient(victim)) GetClientName(victim, victimName, sizeof(victimName));
		else GetClientAuthId(victim, AuthId_Steam2, victimName, sizeof(victimName));

		if(attacker > 0 && attacker != victim) { 
			if(IsFakeClient(attacker)) GetClientName(attacker, attackerName, sizeof(attackerName));
			else GetClientAuthId(attacker, AuthId_Steam2, attackerName, sizeof(attackerName));

			AddLogCustom("STATE", attackerName, victimName, "\"%L\" killed \"%L\"", attacker, victim);
		} else {
			AddLogCustom("STATE", "", victimName, "\"%L\" died", victim);
		}
	}
}
//Jackz was incapped by Jockey
//Jackz was incapped (by world/zombie)
//Jackz was incapped by Disgruntled Pea
//Ellis was incapped [by ...]
public void Event_L4D2_Incapped(Event event, const char[] name, bool dontBroadcast) {
	int victim = GetClientOfUserId(event.GetInt("userid"));
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	if(victim > 0 && GetClientTeam(victim) == 2) { 
		static char victimName[32], attackerName[32];
		if(IsFakeClient(victim)) GetClientName(victim, victimName, sizeof(victimName));
		else GetClientAuthId(victim, AuthId_Steam2, victimName, sizeof(victimName));

		if(attacker > 0 && attacker != victim) {
			if(IsFakeClient(attacker)) GetClientName(attacker, attackerName, sizeof(attackerName));
			else GetClientAuthId(attacker, AuthId_Steam2, attackerName, sizeof(attackerName));

			AddLogCustom("STATE", attackerName, victimName, "\"%L\" incapped \"%L\"", attacker, victim);
		} else {
			AddLogCustom("STATE", "", victimName, "\"%L\" was incapped", victim);
		}
	}
}

void AddLog(const char[] type, const char[] clientName, const char[] targetName, const char[] message) {
	if(StrEqual(clientName, "Bot")) return;
	Log log;
	strcopy(log.name, sizeof(log.name), type);
	strcopy(log.clientSteamID, sizeof(log.clientSteamID), clientName);
	strcopy(log.targetSteamID, sizeof(log.targetSteamID), targetName);
	strcopy(log.message, sizeof(log.message), message);
	log.timestamp = GetTime();
	logs.PushArray(log);
}

void AddLogCustom(const char[] type, const char[] clientName, const char[] targetName, const char[] format, any ...) {
	static char message[254];
	if(StrEqual(clientName, "Bot")) return;

	VFormat(message, sizeof(message), format, 5);
	AddLog(type, clientName, targetName, message);
}

public any Native_AddLog(Handle plugin, int numParams) {
	char type[32], clientName[32], targetName[32], message[256];
	if(GetNativeString(1, type, sizeof(type)) != SP_ERROR_NONE) return false;
	if(GetNativeString(2, clientName, sizeof(clientName)) != SP_ERROR_NONE) return false;
	if(GetNativeString(3, targetName, sizeof(targetName)) != SP_ERROR_NONE) return false;
	if(GetNativeString(4, message, sizeof(message)) != SP_ERROR_NONE) return false;
	AddLog(type, clientName, targetName, message);
	return true;
}