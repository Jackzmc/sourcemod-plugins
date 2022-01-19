#pragma semicolon 1
#pragma newdecls required

//#define DEBUG

#define PLUGIN_VERSION "1.0"
#define MAX_PLAYER_HISTORY 25

#include <sourcemod>
#include <sdktools>
//#include <sdkhooks>

public Plugin myinfo = 
{
	name =  "Noob DB", 
	author = "jackzmc", 
	description = "", 
	version = PLUGIN_VERSION, 
	url = ""
};

static Database DB;
static char query[1024];
static char reason[256];
static int WaitingForNotePlayer;
static char menuNoteTarget[32];

enum struct PlayerData {
	char id[32];
	char name[32];
}

static ArrayList lastPlayers;

public void OnPluginStart() {
	if(!SQL_CheckConfig("stats")) {
		SetFailState("No database entry for 'stats'; no database to connect to.");
	}
	if(!ConnectDB()) {
		SetFailState("Failed to connect to database.");
	}

	lastPlayers = new ArrayList(sizeof(PlayerData));

	HookEvent("player_disconnect", Event_PlayerDisconnect);
	HookEvent("player_first_spawn", Event_FirstSpawn);

	RegAdminCmd("sm_note", Command_AddNote, ADMFLAG_KICK, "Add a note to a player");
	RegAdminCmd("sm_notes", Command_ListNotes, ADMFLAG_KICK, "List notes for a player");
	RegAdminCmd("sm_notedisconnected", Command_AddNoteDisconnected, ADMFLAG_KICK, "Add a note to any disconnected players");
}

public Action Command_AddNoteDisconnected(int client, int args) {
	if(lastPlayers.Length == 0) {
		ReplyToCommand(client, "No disconnected players recorded.");
		return Plugin_Handled;
	}
	Menu menu = new Menu(Menu_Disconnected);
	menu.SetTitle("Add Note For Disconnected");
	for(int i = lastPlayers.Length - 1; i >= 0; i--) {
		PlayerData data;
		lastPlayers.GetArray(i, data, sizeof(data));
		menu.AddItem(data.id, data.name);
	}
	menu.Display(client, 0);
	return Plugin_Handled;
}

public int Menu_Disconnected(Menu menu, MenuAction action, int client, int item) {
	if (action == MenuAction_Select) {
		menu.GetItem(item, menuNoteTarget, sizeof(menuNoteTarget));
		PrintToChat(client, "Enter a note for %s:", menuNoteTarget);
		WaitingForNotePlayer = client;
	} else if (action == MenuAction_End)	
		delete menu;
}

public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs) {
	if(client > 0 && WaitingForNotePlayer == client) {
		WaitingForNotePlayer = 0;
		static char buffer[32];
		GetClientAuthId(client, AuthId_Steam2, buffer, sizeof(buffer));
		DB.Format(query, sizeof(query), "INSERT INTO `notes` (steamid, markedBy, content) VALUES ('%s', '%s', '%s')", menuNoteTarget, buffer, sArgs);
		DB.Query(DB_AddNote, query);
		LogAction(client, -1, "\"%L\" added note for \"%s\": \"%s\"", client, menuNoteTarget, sArgs);
		Format(buffer, sizeof(buffer), "%N: ", client);
		ShowActivity2(client, buffer, "added a note for %s: \"%s\"", menuNoteTarget, sArgs);
		return Plugin_Stop;
	}
	return Plugin_Continue;
}

public Action Command_AddNote(int client, int args) {
	if(args < 2) {
		ReplyToCommand(client, "Syntax: sm_note <player> <note>");
	} else {
		static char target_name[MAX_TARGET_LENGTH];
		GetCmdArg(1, target_name, sizeof(target_name));
		GetCmdArg(2, reason, sizeof(reason));

		int target_list[MAXPLAYERS], target_count;
		bool tn_is_ml;
		if ((target_count = ProcessTargetString(
			target_name,
			client,
			target_list,
			1,
			COMMAND_FILTER_NO_MULTI,
			target_name,
			sizeof(target_name),
			tn_is_ml)) <= 0
		) {
			ReplyToTargetError(client, target_count);
			return Plugin_Handled;
		}
		static char auth[32];
		GetClientAuthId(target_list[0], AuthId_Steam2, auth, sizeof(auth));
		static char authMarker[32];
		if(client > 0)
			GetClientAuthId(client, AuthId_Steam2, authMarker, sizeof(authMarker));
		DB.Format(query, sizeof(query), "INSERT INTO `notes` (steamid, markedBy, content) VALUES ('%s', '%s', '%s')", auth, authMarker, reason);
		DB.Query(DB_AddNote, query);
		LogAction(client, target_list[0], "\"%L\" added note for \"%L\": \"%s\"", client, target_list[0], reason);
		ShowActivity(client, "added a note for \"%N\": \"%s\"", target_list[0], reason);
	}
	return Plugin_Handled;
}

public Action Command_ListNotes(int client, int args) {
	if(args < 1) {
		ReplyToCommand(client, "Syntax: sm_notes <player>");
	} else {
		static char target_name[MAX_TARGET_LENGTH];
		GetCmdArg(1, target_name, sizeof(target_name));
		GetCmdArg(2, reason, sizeof(reason));

		int target_list[MAXPLAYERS], target_count;
		bool tn_is_ml;
		if ((target_count = ProcessTargetString(
			target_name,
			client,
			target_list,
			1,
			COMMAND_FILTER_NO_MULTI,
			target_name,
			sizeof(target_name),
			tn_is_ml)) <= 0
		) {
			ReplyToTargetError(client, target_count);
			return Plugin_Handled;
		}
		static char auth[32];
		GetClientAuthId(target_list[0], AuthId_Steam2, auth, sizeof(auth));

		DB.Format(query, sizeof(query), "SELECT notes.content, stats_users.last_alias FROM `notes` JOIN stats_users ON markedBy = stats_users.steamid WHERE notes.`steamid` = '%s'", auth);
		ReplyToCommand(client, "Fetching notes...");
		DataPack pack = new DataPack();
		pack.WriteCell(GetClientUserId(client));
		pack.WriteCell(GetClientUserId(target_list[0]));
		pack.WriteString(auth);
		DB.Query(DB_ListNotesForPlayer, query, pack);
	}
	return Plugin_Handled;
}

bool ConnectDB() {
    static char error[255];
    DB = SQL_Connect("stats", true, error, sizeof(error));
    if (DB== null) {
		LogError("Database error %s", error);
		delete DB;
		return false;
    } else {
		PrintToServer("Connected to database stats");
		SQL_LockDatabase(DB);
		SQL_FastQuery(DB, "SET NAMES \"UTF8mb4\"");  
		SQL_UnlockDatabase(DB);
		DB.SetCharset("utf8mb4");
		return true;
    }
}

public Action Event_FirstSpawn(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(client > 0 && client <= MaxClients && !IsFakeClient(client)) {
		static char auth[32];
		GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth));
		DB.Format(query, sizeof(query), "SELECT notes.content, stats_users.last_alias FROM `notes` JOIN stats_users ON markedBy = stats_users.steamid WHERE notes.`steamid` = '%s'", auth);
		DB.Query(DB_FindNotes, query, GetClientUserId(client));
	}
}

public Action Event_PlayerDisconnect(Event event, const char[] name, bool dontBroadcast) {
	if(!event.GetBool("bot")) {
		PlayerData data;
		event.GetString("networkid", data.id, sizeof(data.id));
		if(!StrEqual(data.id, "BOT")) {
			if(!IsPlayerInHistory(data.id)) {
				event.GetString("name", data.name, sizeof(data.name));
				lastPlayers.PushArray(data);
				if(lastPlayers.Length > MAX_PLAYER_HISTORY) {
					lastPlayers.Erase(0);
				} 
			}
		}
	}
}

bool IsPlayerInHistory(const char[] id) {
	static PlayerData data;
	for(int i = 0; i < lastPlayers.Length; i++) {
		lastPlayers.GetArray(i, data, sizeof(data));
		if(StrEqual(data.id, id))
			return true;
	}
	return false;
}

public void DB_FindNotes(Database db, DBResultSet results, const char[] error, any data) {
	if(db == null || results == null) {
        LogError("DB_FindNotes returned error: %s", error);
        return;
    }
	//initialize variables
	int client = GetClientOfUserId(data); 
	if(client > 0 && results.RowCount > 0) {
		static char noteCreator[32];
		PrintChatToAdmins("Notes for %N", client);
		while(results.FetchRow()) {
			results.FetchString(0, reason, sizeof(reason));
			results.FetchString(1, noteCreator, sizeof(noteCreator));
			PrintChatToAdmins("%s: %s", noteCreator, reason);
		}
	}
}


public void DB_ListNotesForPlayer(Database db, DBResultSet results, const char[] error, DataPack pack) {
	if(db == null || results == null) {
        LogError("DB_ListNotesForPlayer returned error: %s", error);
        return;
    }
	//initialize variables
	static char auth[32];
	pack.Reset();
	int client = GetClientOfUserId(pack.ReadCell());
	int target = GetClientOfUserId(pack.ReadCell());
	pack.ReadString(auth, sizeof(auth));
	delete pack;
	if(client > 0) {
		if(results.RowCount > 0) {
			if(target > 0) {
				PrintToChat(client, "Notes for %N:", target);
			} else {
				PrintToChat(client, "Notes for %s:", auth);
			}
			char noteCreator[32];
			while(results.FetchRow()) {
				results.FetchString(0, reason, sizeof(reason));
				results.FetchString(1, noteCreator, sizeof(noteCreator));
				PrintToChat(client, "%s: %s", noteCreator, reason);
			}
		} else {
			if(target > 0)
				PrintToChat(client, "No notes found for %N", target);
			else
				PrintToChat(client, "No notes found for %s", auth);
		}
	}
}

public void DB_AddNote(Database db, DBResultSet results, const char[] error, any data) {
	if(db == null || results == null) {
        LogError("DB_AddNote returned error: %s", error);
        return;
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
