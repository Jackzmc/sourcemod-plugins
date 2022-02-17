#pragma semicolon 1

#define DEBUG

#define PLUGIN_VERSION "0.00"

#define DB_NAME "sprayfiltercontrol"
#define DB_TABLE "spray_results" //not used

// The minimum value for detection, number is related to value of RESULT_TEXT
#define ADULT_THRES 2
#define RACY_THRES 2

#include <sourcemod>
#include <sdktools>
#include <system2>

#pragma newdecls required

public Plugin myinfo = {
	name = "Spay Filter Control",
	author = "jackzmc",
	description = "",
	version = PLUGIN_VERSION,
	url = ""
};

static Database g_db;
static char apikey[64];
/* TODO: 
1. Plugin start, fetch API key from keyvalue
2. On client connect, check database for spray result
3. Run system2 if no result
*/ 
char RESULT_TEXT[6][] = {
    "UNKNOWN",
    "VERY UNLIKELY",
    "UNLIKELY",
    "POSSIBLE",
    "LIKELY",
    "VERY LIKELY"
};

enum Result {
    UNKNOWN = -1,
    VERY_UNLIKELY = 0,
    UNLIKELY,
    POSSIBLE,
    LIKELY,
    VERY_LIKELY
}

enum struct SprayResult {
    Result adult;
    Result racy;
}

public void OnPluginStart() {
    if(!SQL_CheckConfig(DB_NAME)) {
        SetFailState("No database entry for " ... DB_NAME ... "; no database to connect to.");
    }
    if(!ConnectDB()) {
        SetFailState("Failed to connect to database.");
    }

    KeyValues kv = new KeyValues("Config");
    kv.ImportFromFile("spraycontrol.cfg");

    if (!kv.JumpToKey("apikey")) {
        delete kv;
        SetFailState("No 'apikey' provided in spraycontrol.cfg");
    }

    kv.GetString("apikey", apikey, sizeof(apikey));

    RegAdminCmd("sm_checkspray", Command_CheckSpray, ADMFLAG_GENERIC, "Gets the spray results of a user");
}

bool ConnectDB() {
    char error[255];
    g_db = SQL_Connect(DB_NAME, true, error, sizeof(error));
    if (g_db == null) {
        LogError("[SFC] Database error %s", error);
        delete g_db;
        return false;
    } else {
        SQL_LockDatabase(g_db);
        SQL_FastQuery(g_db, "SET NAMES \"UTF8mb4\"");  
        SQL_UnlockDatabase(g_db);
        g_db.SetCharset("utf8mb4");
        return true;
    }
}

// Events

public void OnClientAuthorized(int client, const char[] auth) {
    if(!StrEqual(auth, "BOT", true)) {
        char filename[64], query[128];
        if(!GetPlayerDecalFile(client, filename, sizeof(filename))) {
            return; //They don't have a spray            
        }
        Format(query, sizeof(query), "SELECT adult,racy FROM spray_results WHERE steamid = '%s' AND sprayid = '%s'", auth, filename);
        g_db.Query(DB_OnConnectCheck, query, GetClientUserId(client));
    }
}

public void DB_OnConnectCheck(Database db, DBResultSet results, const char[] error, int user) {
    int client = GetClientOfUserId(user);
    if(db == INVALID_HANDLE || results == null) {
        LogError("DB_OnConnectCheck returned error: %s", error);
    }else{
        if(results.RowCount > 0 && client) {
            int adult = results.FetchInt(0) + 1;
            int racy = results.FetchInt(1) + 1;

            CheckUser(client, adult, racy);
        } else {
            char filename[64];
            if(!GetPlayerDecalFile(client, filename, sizeof(filename))) {
                return; //They don't have a spray            
            }
            System2_ExecuteFormattedThreaded(ExecuteCallback, GetClientUserId(client), "test-spray %s %s", filename, apikey); 
        }
    }
}

public void ExecuteCallback(bool success, const char[] command, System2ExecuteOutput output, int user) {
    int client = GetClientOfUserId(user);
    if(client <= 0) return; //Client disconnected, void result
    if (!success || output.ExitStatus != 0) {
        PrintToServer("[SFC] Could not get the spray result for %N", client);
    } else {
        char outputString[128];
        output.GetOutput(outputString, sizeof(outputString));

        char results[2][64];
        char bit[3][16];
        ExplodeString(outputString, "\n", results, 2, 64);

        int adult = -1;
        int racy = -1;

        ExplodeString(results[0], "=", bit, 3, 16);
        adult = StringToInt(bit[2]);
        ExplodeString(results[1], "=", bit, 3, 16);
        racy = StringToInt(bit[2]);

        PrintToServer("[SFC] %N Spray Results | adult=%s racy=%s", RESULT_TEXT[adult], RESULT_TEXT[racy]);

        CheckUser(client, adult, racy);
    }
}  

public Action Command_CheckSpray(int client, int args) {
    if(args < 1) 
        ReplyToCommand(client, "Usage: sm_checkspray <client>");
    else {
        char arg1[64];
        GetCmdArg(1, arg1, sizeof(arg1));
        int target = FindTarget(client, arg1, true, false);
        if(target > 0) {
            char filename[64];
            if(!GetPlayerDecalFile(client, filename, sizeof(filename))) {
                ReplyToCommand(client, "%N does not have a spray", target);
                return Plugin_Handled;
            }
            System2_ExecuteFormattedThreaded(ExecuteCallback, GetClientUserId(client), "test-spray %s %s", filename, apikey);
        } else {
            ReplyToCommand(client, "Could not find target.");
        }
    }    
    return Plugin_Handled;
}

void CheckUser(int client, int adult, int racy) {
    if(adult > 3 || (adult > ADULT_THRES && racy > RACY_THRES)) {
        PrintToAdmins("%N 's spray has a questionable spray. Adult=%s Racy=%s",
            client,
            RESULT_TEXT[adult],
            RESULT_TEXT[racy]
        );
    }
}

stock void PrintToAdmins(const char[] format, any ...) {
    char message[100];
    VFormat(message, sizeof(message), format, 2);	
    for (int x = 1; x <= MaxClients; x++){
        if (IsClientConnected(x) && IsClientInGame(x) && GetUserAdmin(x) != INVALID_ADMIN_ID) {
            PrintToChat(x, message);
        }
    }
} 