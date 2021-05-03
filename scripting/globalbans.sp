#pragma semicolon 1
#pragma newdecls required

#define DEBUG 0
#define PLUGIN_VERSION "1.0"
#define DB_NAME "globalbans"

#include <sourcemod>
#include <sdktools>
#include <geoip>

public Plugin myinfo = 
{
    name =  "Global Bans", 
    author = "jackzmc", 
    description = "Manages bans via MySQL", 
    version = PLUGIN_VERSION, 
    url = ""
};

static Database g_db;
static ConVar hKickOnDBFailure;

public void OnPluginStart() {
    if(!SQL_CheckConfig(DB_NAME)) {
        SetFailState("No database entry for " ... DB_NAME ... "; no database to connect to.");
    }
    if(!ConnectDB()) {
        SetFailState("Failed to connect to database.");
    }

    hKickOnDBFailure = CreateConVar("sm_hKickOnDBFailure", "0", "Should the plugin kick players if it cannot connect to the database?", FCVAR_NONE, true, 0.0, true, 1.0);
}

///////////////////////////////////////////////////////////////////////////////
// DB Connections
///////////////////////////////////////////////////////////////////////////////

bool ConnectDB() {
    char error[255];
    g_db = SQL_Connect(DB_NAME, true, error, sizeof(error));
    if (g_db == null) {
        LogError("Database error %s", error);
        delete g_db;
        return false;
    } else {
        PrintToServer("Connected to sm database " ... DB_NAME);
        SQL_LockDatabase(g_db);
        SQL_FastQuery(g_db, "SET NAMES \"UTF8mb4\"");  
        SQL_UnlockDatabase(g_db);
        g_db.SetCharset("utf8mb4");
        return true;
    }
}

///////////////////////////////////////////////////////////////////////////////
// EVENTS
///////////////////////////////////////////////////////////////////////////////

public void OnClientAuthorized(int client, const char[] auth) {
    if(!StrEqual(auth, "BOT", true)) {
        char query[128], ip[32];
        GetClientIP(client, ip, sizeof(ip));
        Format(query, sizeof(query), "SELECT steamid, ip, reason, timestamp, time FROM bans WHERE `steamid` = '%s' OR ip = '?'", auth, ip);
        g_db.Query(DB_OnConnectCheck, query, GetClientUserId(client), DBPrio_High);
    }
}

public Action OnBanIdentity(const char[] identity, int time, int flags, const char[] reason, const char[] command, any source) {
    if(flags == BANFLAG_AUTHID) {
        char executor[32];
        if(source > 0 && source <= MaxClients) {
            GetClientAuthId(source, AuthId_Steam2, executor, sizeof(executor));
        }else{
            executor = "CONSOLE";
        }
        char query[255];
        Format(query, sizeof(query), "INSERT INTO bans"
            ..."(steamid, reason, time, executor, ip_banned)"
            ..."VALUES ('%s', '%s', %d, '%s', 0)",
            identity,
            reason,
            time,
            executor
        );

        g_db.Query(DB_OnBanQuery, query);
    }else if(flags == BANFLAG_IP) {
        LogMessage("Cannot save IP without steamid: %s [Source: %s]", identity, source);
    }
}

public Action OnBanClient(int client, int time, int flags, const char[] reason, const char[] kick_message, const char[] command, any source) {
    char executor[32], identity[32], ip[32];
    if(source > 0 && source <= MaxClients) {
        GetClientAuthId(source, AuthId_Steam2, executor, sizeof(executor));
    }else{
        executor = "CONSOLE";
    }

    if(GetUserAdmin(client) != INVALID_ADMIN_ID) return Plugin_Stop; 

    GetClientAuthId(client, AuthId_Steam2, identity, sizeof(identity));
    GetClientIP(client, ip, sizeof(ip));

    char query[255];
    Format(query, sizeof(query), "INSERT INTO bans"
        ..."(steamid, ip, reason, time, executor, ip_banned)"
        ..."VALUES ('%s', '%s', '%s', %d, '%s', 0)",
        identity,
        ip,
        reason,
        time,
        executor
    );

    g_db.Query(DB_OnBanQuery, query);
    return Plugin_Continue;
}

public Action OnRemoveBan(const char[] identity, int flags, const char[] command, any source) {
    if(flags == BANFLAG_AUTHID) {
        char query[128];
        Format(query, sizeof(query), "DELETE FROM `bans` WHERE steamid = '%s'", identity);
        g_db.Query(DB_OnRemoveBanQuery, query, flags);
    }
}

///////////////////////////////////////////////////////////////////////////////
// DB Callbacks
///////////////////////////////////////////////////////////////////////////////

public void DB_OnConnectCheck(Database db, DBResultSet results, const char[] error, int user) {
    int client = GetClientOfUserId(user);
    if(db == INVALID_HANDLE || results == null) {
        LogError("DB_OnConnectCheck returned error: %s", error);
        if(client > 0 && hKickOnDBFailure.BoolValue) {
            KickClient(client, "Could not authenticate at this time.");
            LogMessage("Could not connect to database to authorize user '%N' (#%d)", client, user);
        }
    }else{
        //No failure, check the data.
        if(results.RowCount > 0 && client) {
            results.FetchRow();
            char reason[128];
            DBResult result;
            results.FetchString(2, reason, sizeof(reason), result);
            //TODO: Implement temp bans
            if(result == DBVal_Data)
                KickClient(client, "You have been banned: %s", reason);
            else
                KickClient(client, "You have been banned from this server.");
        }
    }
}


public void DB_OnBanQuery(Database db, DBResultSet results, const char[] error, any data) {
    if(db == INVALID_HANDLE || results == null) {
        LogError("DB_OnBanQuery returned error: %s", error);
    }
}

public void DB_OnRemoveBanQuery(Database db, DBResultSet results, const char[] error, any data) {
    if(db == INVALID_HANDLE || results == null) {
        LogError("DB_OnRemoveBanQuery returned error: %s", error);
    }
}