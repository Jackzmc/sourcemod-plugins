#pragma semicolon 1

#define DEBUG

#define PLUGIN_AUTHOR "Jackz"
#define PLUGIN_VERSION "1.00"

#define DATABASE_NAME "player-recorder"
#define RECORD_INTERVAL 60.0

#include <sourcemod>
#include <sdktools>

#pragma newdecls required

public Plugin myinfo = {
	name = "SRCDS Player Count Recorder",
	author = PLUGIN_AUTHOR,
	description = "",
	version = PLUGIN_VERSION,
	url = ""
};

static Database g_db;
static char playerID[32];

enum struct PlayerData {
	int timestamp;
	int playerCount;
}

static ArrayList g_playerData;
static int iLastCount;
static bool active;

public void OnPluginStart() {
	if(!SQL_CheckConfig(DATABASE_NAME)) {
		SetFailState("No database entry for '" ... DATABASE_NAME ... "'; no database to connect to.");
	} else if(!ConnectDB()) {
		SetFailState("Failed to connect to database.");
	}

	g_playerData = new ArrayList(sizeof(PlayerData));


	ConVar hPlayerCountID = CreateConVar("sm_playercount_id", "", "The ID to use for player count recording. Will not record if not set", FCVAR_NONE);
	hPlayerCountID.GetString(playerID, sizeof(playerID));
	hPlayerCountID.AddChangeHook(Change_ID);

	if(strlen(playerID) > 0) {
		Init();
	} 
}

void Init() {
	HookEvent("player_first_spawn", Event_Connection, EventHookMode_PostNoCopy);
	HookEvent("player_disconnect", Event_Connection, EventHookMode_PostNoCopy);

	CreateTimer(RECORD_INTERVAL, Timer_PushCounts, _, TIMER_REPEAT);
	active = true;
	PlayerData data;
	data.timestamp = GetTime();
	data.playerCount = GetPlayerCount();
	g_playerData.PushArray(data);


}

public void Change_ID(ConVar convar, const char[] oldValue, const char[] newValue) {
	convar.GetString(playerID, sizeof(playerID));
	if(!active && strlen(playerID) > 0) {
		Init();
	} 
}

bool ConnectDB() {
	char error[255];
	g_db = SQL_Connect(DATABASE_NAME, true, error, sizeof(error));
	if (g_db == null) {
		LogError("Database error %s", error);
		delete g_db;
		return false;
	} else {
		PrintToServer("[SPR] Connected to database \"" ... DATABASE_NAME ... "\"");
		SQL_LockDatabase(g_db);
		SQL_FastQuery(g_db, "SET NAMES \"UTF8mb4\"");  
		SQL_UnlockDatabase(g_db);
		g_db.SetCharset("utf8mb4");

		return true;
	}
}

public void Event_Connection(Event event, const char[] name, bool dontBroadcast) {
	int count = GetPlayerCount();
	if(count != iLastCount) {
		PlayerData data;
		data.timestamp = GetTime();
		data.playerCount = count;
		g_playerData.PushArray(data);
		iLastCount = count;
	}
}

public Action Timer_PushCounts(Handle h) {
	Transaction transact = new Transaction();
	static char query[255];
	static PlayerData data;
	int length = g_playerData.Length;
	for(int i = 0; i < length; i++) {
		g_playerData.GetArray(i, data, sizeof(data));
		g_db.Format(query, sizeof(query), "INSERT INTO player_count (server_name, timestamp, count) VALUES ('%s', %d, %d)", 
			playerID,
			data.timestamp, 
			data.playerCount
		);
		transact.AddQuery(query);
	}
	g_playerData.Resize(g_playerData.Length - length);
	g_db.Execute(transact, _, SQL_TransactionFailed, length, DBPrio_Low);
	return Plugin_Continue;
}

public void SQL_TransactionFailed(Database db, any data, int numQueries, const char[] error, int failIndex, any[] queryData) {
	PrintToServer("[PlayerRecorder] Push failure: %s at query %d/%d", error, failIndex, numQueries);
}

int GetPlayerCount() {
	int count;
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && !IsFakeClient(i)) {
			count++;            
		}
	}
	return count;
}