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
static ConVar hKickType;

public void OnPluginStart() {
    if(!SQL_CheckConfig(DB_NAME)) {
        SetFailState("No database entry for " ... DB_NAME ... "; no database to connect to.");
    }
    if(!ConnectDB()) {
        SetFailState("Failed to connect to database.");
    }

    hKickType = CreateConVar("sm_globalbans_kick_type", "1", "0 = Do not kick, just notify\n1 = Kick if banned\n 2 = Kick if cannot reach database", FCVAR_NONE, true, 0.0, true, 2.0);

}

///////////////////////////////////////////////////////////////////////////////
// DB Connections
///////////////////////////////////////////////////////////////////////////////

bool ConnectDB() {
    static char error[255];
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
        static char query[256], ip[32];
        GetClientIP(client, ip, sizeof(ip));
        Format(query, sizeof(query), "SELECT `reason`, `steamid`, `expired` FROM `bans` WHERE `steamid` LIKE 'STEAM_%:%:%s' OR ip = '?'", auth[10], ip);
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
        static char query[255];
        static char expiresDate[64];
        if(time > 0) {
            Format(expiresDate, sizeof(expiresDate), "%d", GetTime() + (time * 60000));
        }else{
            Format(expiresDate, sizeof(expiresDate), "NULL");
        }
        Format(query, sizeof(query), "INSERT INTO bans"
            ..."(steamid, reason, expires, executor, ip_banned)"
            ..."VALUES ('%s', '%s', %s, '%s', 0)",
            identity,
            reason,
            expiresDate,
            executor
        );

        g_db.Query(DB_OnBanQuery, query);
    }else if(flags == BANFLAG_IP) {
        LogMessage("Cannot save IP without steamid: %s [Source: %s]", identity, source);
    }
    return Plugin_Continue;
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

    static char query[255];
    static char expiresDate[64];
    if(time > 0) {
        Format(expiresDate, sizeof(expiresDate), "%d", GetTime() + (time * 60));
    } else {
        Format(expiresDate, sizeof(expiresDate), "NULL");
    }
    Format(query, sizeof(query), "INSERT INTO bans"
        ..."(steamid, ip, reason, expires, executor, ip_banned)"
        ..."VALUES ('%s', '%s', '%s', FROM_UNIXTIME(%s), '%s', 0)",
        identity,
        ip,
        reason,
        expiresDate,
        executor
    );

    g_db.Query(DB_OnBanQuery, query);
    return Plugin_Continue;
}

public Action OnRemoveBan(const char[] identity, int flags, const char[] command, any source) {
    if(flags == BANFLAG_AUTHID) {
        static char query[128];
        g_db.Format(query, sizeof(query), "DELETE FROM `bans` WHERE steamid = '%s'", identity);
        g_db.Query(DB_OnRemoveBanQuery, query, flags);
    }
    return Plugin_Continue;

}

///////////////////////////////////////////////////////////////////////////////
// DB Callbacks
///////////////////////////////////////////////////////////////////////////////

public void DB_OnConnectCheck(Database db, DBResultSet results, const char[] error, int user) {
    int client = GetClientOfUserId(user);
    if(db == INVALID_HANDLE || results == null) {
        LogError("DB_OnConnectCheck returned error: %s", error);
        if(client > 0 && hKickType.IntValue == 2) {
            KickClient(client, "Could not authenticate at this time.");
            LogMessage("Could not connect to database to authorize user '%N' (#%d)", client, user);
        }
    } else {
        //No failure, check the data.
        if(results.RowCount > 0 && client) {
            results.FetchRow();
            static char reason[128], steamid[64];
            DBResult reasonResult;
            results.FetchString(1, steamid, sizeof(steamid));
            bool expired = results.FetchInt(2) == 1;
            if(results.IsFieldNull(2)) {
                DeleteBan(steamid);
            } else {
                results.FetchString(0, reason, sizeof(reason), reasonResult);
                if(!expired) {
                    if(hKickType.IntValue > 0) {
                        if(reasonResult == DBVal_Data)
                            KickClient(client, "You have been banned:\n%s", reason);
                        else
                            KickClient(client, "You have been banned from this server.");
                        static char query[128];
                        g_db.Format(query, sizeof(query), "UPDATE bans SET times_tried=times_tried+1 WHERE steamid = '%s'", steamid);
                        g_db.Query(DB_OnBanQuery, query);
                    } else {
                        PrintChatToAdmins("%N was banned from this server for: \"%s\"", client, reason);
                    }
                } else {
                    PrintChatToAdmins("%N was previously banned for \"%s\"", client, reason);
                }
            }
        }
    }
}

void DeleteBan(const char[] steamid) {
    static char query[128];
    g_db.Format(query, sizeof(query), "DELETE FROM `bans` WHERE steamid = '%s'", steamid);
    g_db.Query(DB_OnRemoveBanQuery, query);
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

stock void PrintChatToAdmins(const char[] format, any ...) {
	char buffer[254];
	VFormat(buffer, sizeof(buffer), format, 2);
	for(int i = 1; i < MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i)) {
			AdminId admin = GetUserAdmin(i);
			if(admin != INVALID_ADMIN_ID) {
				PrintToChat(i, "%s", buffer);
			}
		}
	}
	PrintToServer("%s", buffer);
}
