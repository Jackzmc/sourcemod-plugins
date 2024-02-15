#pragma semicolon 1
#pragma newdecls required

#define DEBUG 0
#define PLUGIN_VERSION "1.0"
#define DB_NAME "globalbans"

#define BANFLAG_NONE 0
#define BANFLAG_IPBANNED 1
#define BANFLAG_SUSPENDED 2

#include <sourcemod>
#include <sdktools>

public Plugin myinfo = 
{
    name =  "Global Bans", 
    author = "jackzmc", 
    description = "Manages bans via MySQL", 
    version = PLUGIN_VERSION, 
    url = "https://github.com/Jackzmc/sourcemod-plugins"
};

static Database g_db;
static ConVar hKickType;
static StringMap pendingInsertQueries;

static int iPendingCounter;


public void OnPluginStart() {
    if(!SQL_CheckConfig(DB_NAME)) {
        SetFailState("No database entry for " ... DB_NAME ... "; no database to connect to.");
    }
    if(!ConnectDB()) {
        SetFailState("Failed to connect to database.");
    }

    pendingInsertQueries = new StringMap();

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
        g_db.Format(query, sizeof(query), "SELECT `reason`, `steamid`, `expired`, `public_message`, `flags`, `id` FROM `bans` WHERE `expired` = 0 AND `steamid` LIKE 'STEAM_%%:%%:%s' OR ip = '%s'", auth[10], ip);
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


        // Setup expiration date
        char expiresDate[64];
        if(time > 0) {
            Format(expiresDate, sizeof(expiresDate), "%d", GetTime() + (time * 60000));
        }else{
            Format(expiresDate, sizeof(expiresDate), "NULL");
        }

        int size = 2*strlen(reason)+1;
        char[] reasonEscaped = new char[size];
        g_db.Escape(reason, reasonEscaped, size); 
        
        int querySize = 256+size;
        char[] query = new char[querySize];

        g_db.Format(query, querySize, "INSERT INTO bans"
            ..."(steamid, reason, expires, executor, flags, timestamp)"
            ..."VALUES ('%s', '%s', %s, '%s', %d, UNIX_TIMESTAMP())",
            identity,
            reasonEscaped,
            expiresDate,
            executor,
            BANFLAG_NONE
        );

        static char strKey[8];
        int key = ++iPendingCounter;
        IntToString(key, strKey, sizeof(strKey));
        pendingInsertQueries.SetString(strKey, query);

        g_db.Format(query, querySize, "SELECT `flags` FROM `bans` WHERE `expired` = 0 AND `steamid` LIKE 'STEAM_%%:%%:%s' OR ip = '%s'", identity[10], identity);
        g_db.Query(DB_OnBanPreCheck, query, key);
        PrintToServer("Adding %s to OnBanClient queue. Key: %d", identity, key);

    }else if(flags == BANFLAG_IP) {
        LogMessage("Cannot save IP without steamid: %s [Source: %s]", identity, source);
    }
    return Plugin_Continue;
}

public Action OnBanClient(int client, int time, int flags, const char[] reason, const char[] kick_message, const char[] command, any source) {
    if(GetUserAdmin(client) != INVALID_ADMIN_ID) {
        LogMessage("Ignoring OnBanClient with admin id as target");
        return Plugin_Stop;
    } 


    char executor[32], identity[32], ip[32];
    GetClientAuthId(client, AuthId_Steam2, identity, sizeof(identity));

    LogMessage("OnBanClient client=%d flags=%d source=%d, command=%s", client, flags, source, command);

    DataPack pack;
    if(source > 0 && source <= MaxClients && IsClientConnected(source) && GetClientAuthId(source, AuthId_Steam2, executor, sizeof(executor))) {
        pack = new DataPack();
        pack.WriteString(identity);
        pack.WriteCell(source);
    }else{
        executor = "CONSOLE";
    }

    GetClientIP(client, ip, sizeof(ip));
       
    char expiresDate[64];
    if(time > 0) {
        Format(expiresDate, sizeof(expiresDate), "%d", GetTime() + (time * 60));
    } else {
        Format(expiresDate, sizeof(expiresDate), "NULL");
    }

    int size = 2*strlen(reason)+1;
    char[] reasonEscaped = new char[size];
    g_db.Escape(reason, reasonEscaped, size); 

    int querySize = 256 + size;
    char[] query = new char[querySize];

    g_db.Format(query, querySize, "INSERT INTO bans"
        ..."(steamid, ip, reason, public_message, expires, executor, flags, timestamp)"
        ..."VALUES ('%s', '%s', '%s', '%s', %s, '%s', %d, UNIX_TIMESTAMP())",
        identity,
        ip,
        reasonEscaped,
        kick_message,
        expiresDate,
        executor,
        BANFLAG_NONE
    );

    static char strKey[8];
    int key = ++iPendingCounter;
    IntToString(key, strKey, sizeof(strKey));
    pendingInsertQueries.SetString(strKey, query);

    g_db.Format(query, querySize, "SELECT `flags` FROM `bans` WHERE `expired` = 0 AND `steamid` LIKE 'STEAM_%%:%%:%s' OR ip = '%s'", identity[10], identity);
    g_db.Query(DB_OnBanPreCheck, query, key);

    PrintToServer("Adding %N to OnBanClient queue. Key: %d", client, key);

    return Plugin_Handled;
}



public Action OnRemoveBan(const char[] identity, int flags, const char[] command, any source) {
    if(flags == BANFLAG_AUTHID) {
        static char query[128];
        g_db.Format(query, sizeof(query), "DELETE FROM `bans` WHERE steamid = '%s'", identity);
        g_db.Query(DB_GenericCallback, query, flags);
    }
    return Plugin_Continue;

}

///////////////////////////////////////////////////////////////////////////////
// DB Callbacks
///////////////////////////////////////////////////////////////////////////////
//] DB_OnBanQuery returned error: You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near '' at line 1
public void DB_OnBanPreCheck(Database db, DBResultSet results, const char[] error, int key) {
    static char strKey[8];
    IntToString(key, strKey, sizeof(strKey));
    static char query[255];
    pendingInsertQueries.GetString(strKey, query, sizeof(query));

    if(results == null || db == INVALID_HANDLE) {
        LogError("Ban Pre-check: Cannot check for existing ban, ignoring ban attempt. [Query: %s]", query);
    } else {
        if(results.FetchRow()) {
            int flags = results.FetchInt(0);
            if(~flags & BANFLAG_SUSPENDED) {
                LogMessage("Ban Pre-check: Found existing non-suspended ban, ignoring ban attempt. [Query: %s]", query);
                return;
            }
        }

        g_db.Query(DB_OnBanQuery, query);
    }
}


public void DB_OnConnectCheck(Database db, DBResultSet results, const char[] error, int user) {
    int client = GetClientOfUserId(user);
    if(client == 0) return;
    if(db == INVALID_HANDLE || results == null) {
        LogError("DB_OnConnectCheck returned error: %s", error);
        if(hKickType.IntValue == 2) {
            KickClient(client, "Could not authenticate at this time.");
            LogMessage("Could not connect to database to authorize user '%N' (#%d)", client, user);
        }
    } else {
        //No failure, check the data.
        while(results.FetchRow()) { //Is there a ban found?
            static char reason[255], steamid[64], public_message[255];
            DBResult colResult;

            results.FetchString(0, reason, sizeof(reason), colResult);
            results.FetchString(1, steamid, sizeof(steamid));
            if(colResult == DBVal_Null) {
                reason[0] = '\0';
            } 
            
            bool expired = results.FetchInt(2) == 1; //Check if computed column 'expired' is true
            if(results.IsFieldNull(2)) { //If expired null, delete i guess. lol
                DeleteBan(steamid);
            } else {
                int flags = results.FetchInt(4);
                if(!expired && (~flags & BANFLAG_SUSPENDED)) {
                    LogAction(-1, client, "\"%L\" (%s), is banned from server: \"%s\"", client, steamid, reason);
                    // Fetch public message
                    results.FetchString(3, public_message, sizeof(public_message), colResult);
                    if(colResult == DBVal_Null || strlen(public_message) == 0) {
                        public_message = reason; 
                    }

                    int id = results.FetchInt(5);

                    if(hKickType.IntValue > 0) {
                        if(public_message[0] != '\0')
                            KickClient(client, "Banned:\n%s\nAppeal at jackz.me/apl/%d", public_message, id);
                        else
                            KickClient(client, "You have been banned from this server.\nAppeal at jackz.me/apl/%d", id);
                        static char query[128];
                        g_db.Format(query, sizeof(query), "UPDATE bans SET times_tried=times_tried+1 WHERE steamid = '%s'", steamid);
                        g_db.Query(DB_GenericCallback, query);
                    } else {
                        PrintChatToAdmins("\"%L\" was banned from this server for: \"%s\"", client, reason);
                    }
                    static char query[128];
                    g_db.Format(query, sizeof(query), "UPDATE bans SET times_tried=times_tried+1 WHERE steamid = '%s'", steamid);
                    g_db.Query(DB_GenericCallback, query);
                } else {
                    LogAction(-1, client, "\"%L\" was previously banned from server: \"%s\"", client, reason);
                    // User was previously banned
                    PrintChatToAdmins("%N (%s) has a previous suspended/expired ban of reason \"%s\"", client, steamid, reason);
                }
            }
        }
    }
}

void DeleteBan(const char[] steamid) {
    static char query[128];
    g_db.Format(query, sizeof(query), "DELETE FROM `bans` WHERE steamid = '%s'", steamid);
    g_db.Query(DB_GenericCallback, query);
}


public void DB_OnBanQuery(Database db, DBResultSet results, const char[] error, any data) {
    if(db == INVALID_HANDLE || results == null) {
        LogError("DB_OnBanQuery returned error: %s", error);
        DataPack pack = data;
        if(pack != null) {
            pack.Reset();
            static char id[32];
            pack.ReadString(id, sizeof(id));
            int source = pack.ReadCell();

            if(StrContains(error, "Duplicate entry") > 0) {
                PrintToChat(source, "Could not ban \"%s\", as they were previously banned. Please edit the ban manually on the website (or yell at jackz).", id);
            } else {
                PrintToChat(source, "Could not ban \"%s\" due to an error: %s", id, error);
            }
        }
    }
}

public void DB_GenericCallback(Database db, DBResultSet results, const char[] error, any data) {
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
