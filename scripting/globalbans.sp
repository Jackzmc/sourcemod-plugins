#pragma semicolon 1
#pragma newdecls required

#define DB_NAME "globalbans"
/// How long in ms until we kick user for auth timeout to prevent spoofed banned players. 
/// May be unnecessary as server will eventually kick the user on their own with "No steam logon" but can take long time
#define AUTH_TIMEOUT 22.0  
#define LOG_FILE "addons/sourcemod/logs/globalbans.log"

#define BANFLAG_NONE 0
#define BANFLAG_IPBANNED 1
#define BANFLAG_SUSPENDED 2

#include <sourcemod>
#include <sdktools>
#include <anymap>
#define LOG_PREFIX "GlobalBans"
#define LOG_COMMAND "sm_ban"
#define LOG_FLAG ADMFLAG_BAN
#include <log>

public Plugin myinfo = 
{
    name =  "Global Bans", 
    author = "jackzmc", 
    description = "Manages bans via MySQL", 
    version = "1.1.0", 
    url = "https://github.com/Jackzmc/sourcemod-plugins"
};

static Database g_db;
static ConVar hKickType;
static AnyMap pendingInsertQueries;

static int iPendingCounter;
Handle authTimeoutTimer[MAXPLAYERS+1] = { null, ... };

ConVar cvarLogLevel;

public void OnPluginStart() {
    hKickType = CreateConVar("sm_globalbans_kick_type", "1", "0 = Do not kick, just notify\n1 = Kick if banned\n 2 = Kick if cannot reach database", FCVAR_NONE, true, 0.0, true, 2.0);
    cvarLogLevel = CreateConVar("sm_globalbans_log_level", "3", "Determines the highest log level to print. 0 = Nothing\n1 = ERROR only\n2 = WARN\n3 = INFO\n4 = DEBUG\n5 = TRACE", FCVAR_NONE, true, 0.0, true, 5.0);
    cvarLogLevel.AddChangeHook(LOG_OnCvarChange);

    if(!SQL_CheckConfig(DB_NAME)) {
        SetFailState("No database entry for " ... DB_NAME ... "; no database to connect to.");
    } else if(!ConnectDB()) {
        SetFailState("Failed to connect to database.");
    }

    pendingInsertQueries = new AnyMap();

	HookEvent("player_disconnect", Event_PlayerDisconnect);

    AutoExecConfig(true, "globalbans");
}

///////////////////////////////////////////////////////////////////////////////
// DB Connections
///////////////////////////////////////////////////////////////////////////////

bool ConnectDB() {
    static char error[255];
    g_db = SQL_Connect(DB_NAME, true, error, sizeof(error));
    if (g_db == null) {
        Log(Log_Error, Target_ServerConsole, "Database error %s", error);
        delete g_db;
        return false;
    } else {
        SQL_LockDatabase(g_db);
        SQL_FastQuery(g_db, "SET NAMES \"UTF8mb4\"");  
        SQL_UnlockDatabase(g_db);
        g_db.SetCharset("utf8mb4");
        Log(Log_Info, Target_ServerConsole, "Connected to sm database " ... DB_NAME);
        return true;
    }
}


///////////////////////////////////////////////////////////////////////////////
// EVENTS
///////////////////////////////////////////////////////////////////////////////

/**
 * BAN CHECK LOGIC:
 * - On client join, check their unvalidated steamid for speedy ban checks
 *   > Start timer to kick player after AUTH_TIMEOUT ms to prevent spoofed banned players
 * - On authorized, kill timer as they are now verified
*/

int joinTime[MAXPLAYERS+1];
public void OnClientConnected(int client) {
    if(!IsFakeClient(client)) {
        joinTime[client] = GetTime();
        // We do not validate the steamid so we can check their ban status as soon as possible
        // If they did spoof their steamid, steam will eventually kick them / fail to validate
        RequestClientCheck(client, false);
        authTimeoutTimer[client] = CreateTimer(AUTH_TIMEOUT, Timer_AuthTimeout, GetClientUserId(client));
    }
}

public void OnClientAuthorized(int client, const char[] auth) {
    if(!IsFakeClient(client)) {
        Log(Log_Debug, Target_Console, "TIMING: OnClientAuthorized took %ds for %N", GetTime() - joinTime[client], client);
        // SteamID I believe should not be able to be changed, as it's sent on initial connect, 
        // it just takes time for steam to return auth sometimes
        // Therefore, the original steamid tested (the unvalidated one) in OnClientConnected is verified now
        CancelAuthTimeout(client);
    }
}

/// Checks for any client bans
/// Returns true if check has started, false if any 
void RequestClientCheck(int client, bool validate = true) {

    static char auth[32], ip[32];
    if(!GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth), validate)) {
        // SteamID invalid / missing (if validate set, then not authed yet), ignore request
        // TODO: verify if this can be called?
        if(!validate) {
            // If NO validate, we should always get steamid. If we don't here, somethings wrong.
            Log(Log_Warn, Target_All, "Did not get steamid for %d with validate false. This should not happen.", client);
        }
        return;
    }
    GetClientIP(client, ip, sizeof(ip));

    char query[256];
    g_db.Format(query, sizeof(query), "SELECT reason, steamid, expired, public_message, flags, id FROM bans WHERE expired = 0 AND SUBSTRING(steamid, 11) = '%s' OR ip = '%s'", auth, ip);
    g_db.Query(DB_OnConnectCheck, query, GetClientUserId(client), DBPrio_High);
    Log(Log_Debug, Target_ServerConsole, "Checking client #%d (Name: %N) (ID: %s %s) (IP: %s)", client, client, auth, (validate ? "[CHECKED]" : "[UNCHECKED]"), ip);
}

Action Timer_AuthTimeout(Handle h, int userid) {
    int client = GetClientOfUserId(userid);
    if(client > 0) {
        Log(Log_Debug, Target_Console, "AUTH TIMEOUT for %N %d, would kick", client, client);
        // TODO: impl kick after verified
        KickClient(client, "Steam auth timed out.\nTry restarting your steam client");
        PrintToChatAll("%N disconnected. (Reason: Steam auth timed out)", client);
        authTimeoutTimer[client] = null;
    }
    return Plugin_Handled;
}

void CancelAuthTimeout(int client) {
    if(authTimeoutTimer[client] != null) {
        Log(Log_Debug, Target_ServerConsole, "auth timeout cancelled for client %d", client);
        delete authTimeoutTimer[client];
    }
}

public void OnClientDisconnect(int client) {
    // TODO: remove, temp debug
    if(authTimeoutTimer[client] != null) {
        Log(Log_Debug, Target_Console, "TIMING: Client %N got timed out %s sec", client, GetTime() - joinTime[client]);
    }
    CancelAuthTimeout(client);
}

public void Event_PlayerDisconnect(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(client > 0 && !IsFakeClient(client)) {
		char reason[16], playerName[32];
		event.GetString("reason", reason, sizeof(reason));
		event.GetString("name", playerName, sizeof(playerName));
		if(StrEqual(reason, "No Steam logon")) {
			if(authTimeoutTimer[client] != null) {
                Log(Log_Debug, Target_Console, "TIMING: Client %N got timed out %s sec", client, GetTime() - joinTime[client]);
            }
		}
	}
}

bool GetExecutorId(int source, char[] output, int maxlen) {
    if(source > 0 && source <= MaxClients && IsClientConnected(source)) {
        if(GetClientAuthId(source, AuthId_Steam2, output, maxlen)) {
            return true;
        } 

        Log(Log_Warn, Target_ServerConsole, "Failed to get steamid for ban source %d", source);
    }

    strcopy(output, maxlen, "CONSOLE");
    return false;
}
enum struct PendingBanData {
    int executorUserId; // ## or 0 if console
    char executorId[32]; // STEAMID or "CONSOLE"

    // SteamID of banned player
    char steamid[32];

    int expiresTimestamp;

    char ip[32];

    char reason[64];

    void GetPrecheckQuery(char[] buffer, int maxlen) {
        g_db.Format(buffer, maxlen, 
            "SELECT expired,flags FROM bans WHERE expired = 0 AND SUBSTRING(steamid, 11) = '%s' OR ip = '%s'",
            this.steamid,
            this.ip
        );
    }

    void GetInsertQuery(char[] buffer, int maxlen) {
        // Set expires to NULL if expires = 0
        // Set ip to NULL if ip = '' (empty)
        g_db.Format(buffer, maxlen, 
            "INSERT INTO bans (steamid, ip, reason, expires, executor, flags, timestamp)"
        ... "VALUES ('%s',NULLIF('%s',''),'%s','%s',NULLIF(%d,0),'%s',0,UNIX_TIMESTAMP()",
            this.steamid,
            this.ip,
            this.reason,
            this.expiresTimestamp,
            this.executorId
        );
    }
} 


void EnqueueBan(const char[] steamid, const char[] ip, int minutes, int banFlags, const char[] reason, int source) {
    if(~banFlags & BANFLAG_AUTHID) {
        Log(Log_Warn, Target_All, "Ignoring ban for %s that is not type AUTHID (flags=%d)", steamid, banFlags);
        return;
    }

    PendingBanData data;

    strcopy(data.steamid, sizeof(data.steamid), steamid);
    strcopy(data.reason, sizeof(data.reason), reason);
    strcopy(data.ip, sizeof(data.ip), ip);
    
    // The STEAM_#:## of executor or "CONSOLE" 
    data.executorUserId = source > 0 ? GetClientOfUserId(source) : 0;
    GetExecutorId(source, data.executorId, sizeof(data.executorId));

    // Setup expire timestamp (unix timestamp). Query sets NULL if timestamp = 0
    if(minutes > 0) {
        data.expiresTimestamp = GetTime() + (minutes * 60000);
    }
    
    // Get new ID to track the ban
    int queueId = ++iPendingCounter;
    pendingInsertQueries.SetArray(queueId, data, sizeof(data));

    char query[256];
    data.GetPrecheckQuery(query, sizeof(query));
    g_db.Query(DB_OnBanPreCheck, query, queueId);
}

public Action OnBanIdentity(const char[] identity, int time, int flags, const char[] reason, const char[] command, any source) {
    EnqueueBan(identity, "", time, flags, reason, source);
    return Plugin_Continue;
}

public Action OnBanClient(int client, int time, int flags, const char[] reason, const char[] kick_message, const char[] command, any source) {
    if(GetUserAdmin(client) != INVALID_ADMIN_ID) {
        Log(Log_Warn, Target_All, "Ignoring ban for an admin (%N %d)", client, client);
        return Plugin_Stop;
    } 

    char identity[32];
    // We pass validate false as we always want steamid. Unlikely spoofing causing problems here
    if(!GetClientAuthId(client, AuthId_Steam2, identity, sizeof(identity), false)) {
        Log(Log_Error, Target_All, "Could not get steamid for client %d", client);
        return Plugin_Stop;
    }

    char ip[32];
    GetClientIP(client, ip, sizeof(ip));

    EnqueueBan(identity, ip, time, flags, reason, source);
    return Plugin_Handled;
}



public Action OnRemoveBan(const char[] identity, int flags, const char[] command, any source) {
    if(flags == BANFLAG_AUTHID) {
        DeleteBan(identity);
    }
    return Plugin_Continue;

}

///////////////////////////////////////////////////////////////////////////////
// DB Callbacks
///////////////////////////////////////////////////////////////////////////////

void DB_OnConnectCheck(Database db, DBResultSet results, const char[] error, int user) {
    int client = GetClientOfUserId(user);
    if(client == 0) return;
    if(db == INVALID_HANDLE || results == null) {
        if(client > 0) {
            Log(Log_Warn, Target_AdminChat, "Failed to check ban status for client %N (%d)", client, client);
        } else {
            Log(Log_Warn, Target_AdminChat, "Failed to check ban status for userid %d", user);
        }
        Log(Log_Error, Target_AdminConsole, "DB_OnConnectCheck returned error for (userid #%d) (index %d) %s", user, client, error);
        if(hKickType.IntValue == 2) {
            KickClient(client, "Could not authenticate at this time.");
        }
        return;
    }
    
    // May return multiple rows, with some bans being suspended or not. Find any active ban
    while(results.FetchRow()) { //Is there a ban found?
        static char reason[255], steamid[64], publicMessage[255];
        DBResult colResult;

        int id = results.FetchInt(5);
        results.FetchString(0, reason, sizeof(reason), colResult);
        results.FetchString(1, steamid, sizeof(steamid));
        if(colResult == DBVal_Null) {
            reason[0] = '\0';
        } 
        
        bool isExpired = results.FetchInt(2) == 1; //Check if computed column 'expired' is true
        if(results.IsFieldNull(2)) { //If expired null, delete i guess. lol
            Log(Log_Warn, Target_AdminConsole, "Deleting ban %d for %s marked expired but with no expire date", id, steamid);
            DeleteBan(steamid);
            return;
        }

        int flags = results.FetchInt(4);
        // Ignore non active bans
        if(isExpired || flags & BANFLAG_SUSPENDED) {
            LogAction(-1, client, "\"%L\" was previously banned from server: \"%s\"", client, reason);
            Log(Log_Info, Target_AdminChat, "%N [%s] has a previously active ban of \"%s\"", client, steamid, reason);
            continue;
        }

        // Ban is valid from here on:

        LogAction(-1, client, "\"%L\" (%s), is banned from server: \"%s\"", client, steamid, reason);
        Log(Log_Info, Target_AdminChat, "Joining player \"%L\" is banned for %s", client, reason);

        // Fetch public message
        results.FetchString(3, publicMessage, sizeof(publicMessage), colResult);
        if(colResult == DBVal_Null || strlen(publicMessage) == 0) {
            // If public reason is null, show the private reason
            publicMessage = reason; 
        }
        
        bool shouldKick = hKickType.IntValue > 0; // If 0 kicks are disabled / dry run, otherwise kick
        if(shouldKick) {
            if(publicMessage[0] != '\0')
                KickClient(client, "Banned:\n%s\nAppeal at jackz.me/apl/%d", publicMessage, id);
            else
                KickClient(client, "You have been banned from this server.\nAppeal at jackz.me/apl/%d", id);
        }

        static char query[128];
        g_db.Format(query, sizeof(query), "UPDATE bans SET times_tried=times_tried+1 WHERE steamid = '%s'", steamid);
        g_db.Query(DB_GenericCallback, query);
        return;
    }

    // No active bans
}

void DB_OnBanPreCheck(Database db, DBResultSet results, const char[] error, int queueId) {
    PendingBanData data;
    char query[256];
    data.GetInsertQuery(query, sizeof(query));

    if(!pendingInsertQueries.GetArray(queueId, data, sizeof(data))) {
        Log(Log_Error, Target_AdminChat, "Ban precheck failed, ignoring ban attempt. See console for details", error, query);
        Log(Log_Error, Target_AdminConsole, "Ban precheck failed, ignoring ban attempt. Error: \"No entry for queue id #%d exists\", Query: \"%s\"", queueId, query);
    } else if(results == null || db == INVALID_HANDLE) {
        Log(Log_Error, Target_AdminChat, "Ban precheck failed, ignoring ban attempt. See console for details", error, query);
        Log(Log_Error, Target_AdminConsole, "Ban precheck failed, ignoring ban attempt. Error: \"%s\", Query: \"%s\"", error, query);
        pendingInsertQueries.Remove(queueId);
    } else {
        // Check for any active bans (not suspended or expired)
        while(results.FetchRow()) {
            bool isExpired = results.FetchInt(0) == 1;
            int flags = results.FetchInt(1);
            if(!isExpired || !(flags & BANFLAG_SUSPENDED)) {
                Log(Log_Warn, Target_AdminChat, "Found an existing active ban, ignoring ban attempt.");
                Log(Log_Error, Target_AdminConsole, "Ban precheck failed, ignoring ban attempt. Error: Existing active ban. Query: \"%s\"", query);
                return;
            }
        }

        // Setup insert query

        g_db.Query(DB_OnBanQuery, query, queueId);
    }
}

void DeleteBan(const char[] steamid) {
    static char query[128];
    g_db.Format(query, sizeof(query), "DELETE FROM `bans` WHERE steamid = '%s'", steamid);
    g_db.Query(DB_GenericCallback, query);

    Log(Log_Info, Target_AdminConsole, "Removing ban of %s", steamid);
}


void DB_OnBanQuery(Database db, DBResultSet results, const char[] error, int queueId) {
    if(db == INVALID_HANDLE || results == null) {
        PendingBanData data;
        if(!pendingInsertQueries.GetArray(queueId, data, sizeof(data))) {
            Log(Log_Error, Target_AdminChat, "Ban insert errored, ban may have failed. See console for details");
            Log(Log_Error, Target_AdminConsole, "Ban insert errored, ban may have failed. Error: \"No entry for queue id #%d exists\"", queueId);
        } else {
            pendingInsertQueries.Remove(queueId);
        }
        
        if(StrContains(error, "Duplicate entry") > 0) {
            Log(Log_Warn, Target_Console, "[Q#%d] Ban for %s ignored as an active ban currently exists", data.steamid, queueId);
            int executor = GetClientOfUserId(data.executorUserId);
            if(executor > 0) {
                PrintToChat(executor, "Unable to ban %s as there is an existing ban that is still active.", data.steamid);
            }
        } else {
            Log(Log_Error, Target_Console, "[Q#%d] Ban for %s failed: %s", data.steamid, error);
            int executor = GetClientOfUserId(data.executorUserId);
            if(executor > 0) {
                PrintToChat(executor, "Failed to ban %s due to error, see console for details.", data.steamid);
            }
        }
    }
}

public void DB_GenericCallback(Database db, DBResultSet results, const char[] error, any data) {
    if(db == INVALID_HANDLE || results == null) {
        LogError("DB_OnRemoveBanQuery returned error: %s", error);
    }
}