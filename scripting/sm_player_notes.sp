#pragma semicolon 1
#pragma newdecls required

//#define DEBUG

#define PLUGIN_VERSION "1.0"
#define MAX_PLAYER_HISTORY 25
#define DATABASE_CONFIG_NAME "stats"

#include <sourcemod>
#include <sdktools>
#include <multicolors>
// Addons:
#tryinclude <feedthetrolls>
#tryinclude <tkstopper>

public Plugin myinfo = 
{
	name =  "Player Notes", 
	author = "jackzmc", 
	description = "", 
	version = PLUGIN_VERSION, 
	url = "https://github.com/Jackzmc/sourcemod-plugins"
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
	if(!SQL_CheckConfig(DATABASE_CONFIG_NAME)) {
		SetFailState("No database entry for %s; no database to connect to.", DATABASE_CONFIG_NAME);
	}
	if(!ConnectDB()) {
		SetFailState("Failed to connect to database.");
	}

	LoadTranslations("common.phrases");

	lastPlayers = new ArrayList(sizeof(PlayerData));

	HookEvent("player_disconnect", Event_PlayerDisconnect);
	HookEvent("player_first_spawn", Event_FirstSpawn);

	RegAdminCmd("sm_note", Command_AddNote, ADMFLAG_KICK, "Add a note to a player");
	RegAdminCmd("sm_notes", Command_ListNotes, ADMFLAG_KICK, "List notes for a player");
	RegAdminCmd("sm_notedisconnected", Command_AddNoteDisconnected, ADMFLAG_KICK, "Add a note to any disconnected players");

	// PrintToServer("Parse Test #1");
	// ParseActions(0, "!fta:Slow_Speed:16");
	// PrintToServer("");

	// PrintToServer("Parse Test #2");
	// ParseActions(0, "SPACE !testSPACE:val1:val2");
	// PrintToServer("");

	// PrintToServer("Parse Test #3");
	// ParseActions(0, "donotfire");
	// PrintToServer("");
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
		PrintToChat(client, "Enter a note in the chat for %s: (or 'cancel' to cancel)", menuNoteTarget);
		WaitingForNotePlayer = client;
	} else if (action == MenuAction_End)	
		delete menu;
	return 0;
}

public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs) {
	if(client > 0 && WaitingForNotePlayer == client) {
		WaitingForNotePlayer = 0;
		if(StrEqual(sArgs, "cancel", false)) {
			PrintToChat(client, "Note cancelled.");
		} else {
			char buffer[32];
			GetClientAuthId(client, AuthId_Steam2, buffer, sizeof(buffer));
			DB.Format(query, sizeof(query), "INSERT INTO `notes` (steamid, markedBy, content) VALUES ('%s', '%s', '%s')", menuNoteTarget, buffer, sArgs);
			DB.Query(DB_AddNote, query);
			LogAction(client, -1, "\"%L\" added note for \"%s\": \"%s\"", client, menuNoteTarget, sArgs);
			Format(buffer, sizeof(buffer), "%N: ", client);
			CShowActivity2(client, buffer, "added a note for {green}%s: {default}\"%s\"", menuNoteTarget, sArgs);
		}
		return Plugin_Stop;
	}
	return Plugin_Continue;
}

public Action Command_AddNote(int client, int args) {
	if(args < 2) {
		ReplyToCommand(client, "Syntax: sm_note <player> \"your message here\" or if they left, use sm_notedisconnected");
	} else {
		char target_name[MAX_TARGET_LENGTH];
		GetCmdArg(1, target_name, sizeof(target_name));
		GetCmdArg(2, reason, sizeof(reason));

		int target_list[1], target_count;
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
		if(args == 1) {
			ReplyToCommand(client, "Enter the note for %N in the chat: (type 'cancel' to cancel)", target_list[0]);
			WaitingForNotePlayer = client;
			return Plugin_Handled;
		}
		char auth[32];
		GetClientAuthId(target_list[0], AuthId_Steam2, auth, sizeof(auth));
		char authMarker[32];
		if(client > 0)
			GetClientAuthId(client, AuthId_Steam2, authMarker, sizeof(authMarker));
		DB.Format(query, sizeof(query), "INSERT INTO `notes` (steamid, markedBy, content) VALUES ('%s', '%s', '%s')", auth, authMarker, reason);
		DB.Query(DB_AddNote, query);
		LogAction(client, target_list[0], "\"%L\" added note for \"%L\": \"%s\"", client, target_list[0], reason);
		CShowActivity(client, "added a note for {green}%N: {default}\"%s\"", target_list[0], reason);
	}
	return Plugin_Handled;
}

public Action Command_ListNotes(int client, int args) {
	if(args < 1) {
		ReplyToCommand(client, "Syntax: sm_notes <player>");
	} else {
		char target_name[MAX_TARGET_LENGTH];
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
		char auth[32];
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
    char error[255];
    DB = SQL_Connect(DATABASE_CONFIG_NAME, true, error, sizeof(error));
    if (DB== null) {
		LogError("Database error %s", error);
		delete DB;
		return false;
    } else {
		PrintToServer("Connected to database %s", DATABASE_CONFIG_NAME);
		SQL_LockDatabase(DB);
		SQL_FastQuery(DB, "SET NAMES \"UTF8mb4\"");  
		SQL_UnlockDatabase(DB);
		DB.SetCharset("utf8mb4");
		return true;
    }
}

public void Event_FirstSpawn(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(client > 0 && client <= MaxClients && !IsFakeClient(client)) {
		static char auth[32];
		GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth));
		DB.Format(query, sizeof(query), "SELECT notes.content, stats_users.last_alias FROM `notes` JOIN stats_users ON markedBy = stats_users.steamid WHERE notes.`steamid` = '%s'", auth);
		DB.Query(DB_FindNotes, query, GetClientUserId(client));
	}
}

public void Event_PlayerDisconnect(Event event, const char[] name, bool dontBroadcast) {
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
		CPrintChatToAdmins("{yellow}> Notes for %N", client);
		// PrintChatToAdmins("> Notes for %N", client);
		int actions = 0;
		while(results.FetchRow()) {
			results.FetchString(0, reason, sizeof(reason));
			results.FetchString(1, noteCreator, sizeof(noteCreator));
			if(ParseActions(client, reason)) {
				actions++;
			} else {
				CPrintChatToAdmins("  {olive}%s: {default}%s", noteCreator, reason);
				// PrintChatToAdmins("%s: %s", noteCreator, reason);
			}
		}
		
		if(actions > 0) {
			PrintChatToAdmins("  {olive}%d Auto Actions Applied", actions);
		}
	}
}

#define ACTION_DESTINATOR '!'
#define ACTION_SEPERATOR "."
bool ParseActions(int client, const char[] input) {
	if(input[0] != ACTION_DESTINATOR) return false;

	char piece[64], key[32], value[16];
	// int prevIndex, index;
	// Incase there is no space, have piece be filled in as input
	strcopy(piece, sizeof(piece), input);
	// Loop through all spaces
	// do {
		// prevIndex += index;
		// If piece contains !flag, parse !flag:value
	int keyIndex = StrContains(piece, ACTION_SEPERATOR);
	if(keyIndex > -1) {
		strcopy(value, sizeof(value), piece[keyIndex + 1]);
		piece[keyIndex] = '\0';
	} else {
		key[0] = '\0';
		value[0] = '\0';
	}

	int valueIndex = StrContains(key, ACTION_SEPERATOR);
	if(valueIndex > -1) {
		strcopy(value, sizeof(value), key[valueIndex + 1]);
		key[valueIndex] = '\0';
	} else {
		value[0] = '\0';
	}
	ApplyAction(client, piece[1], key, value);
	// } while((index = SplitString(input[prevIndex], " ", piece, sizeof(piece))) != -1);

	return true;
}

void ApplyAction(int target, const char[] action, const char[] key, const char[] value) {
	// If action is 'fta*' or 'ftas'
	if(strncmp(action, "fta", 4) >= 0) {
		#if defined _ftt_included_
			// Replace under scores with spaces
			char newKey[32];
			strcopy(newKey, sizeof(newKey), key);
			ReplaceString(newKey, sizeof(newKey), "_", " ", true);
			int flags = StringToInt(value);
			ApplyTroll(target, newKey, TrollMod_Invalid, flags, 0, action[4] == 's');
		#else
			PrintToServer("[PlayerNotes] Warn: Action \"%s\" for %N has missing plugin: Feed The Trolls", action, target);
		#endif
	} else if(StrEqual(action, "ignore")) {
		#if defined _tkstopper_included_
			if(StrEqual(key, "rff")) {
				SetImmunity(target, TKImmune_ReverseFriendlyFire, true);
			} else if(StrEqual(key, "tk")) {
				SetImmunity(target, TKImmune_Teamkill, true);
			} else {
				PrintToServer("[PlayerNotes] Warn: Unknown ignore type \"%s\" for TKStopper", key, target);
			}
		#else
			PrintToServer("[PlayerNotes] Warn: Action \"%s\" for %N has missing plugin: TKStopper", action, target);
		#endif
	} else {
		PrintToServer("[PlayerNotes] Warn: Action (\"%s\") for %N is not valid", action, target);
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
		if(target > 0) {
			GetClientName(target, auth, sizeof(auth));
		}
		if(results.RowCount > 0) {
			CPrintToChat(client, "{green}> Notes for %s:", auth);
			char noteCreator[32];
			while(results.FetchRow()) {
				results.FetchString(0, reason, sizeof(reason));
				results.FetchString(1, noteCreator, sizeof(noteCreator));
				CPrintToChat(client, "  {olive}%s: {default}%s", noteCreator, reason);
			}
			
		} else {
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

stock void CPrintChatToAdmins(const char[] format, any ...) {
	char buffer[254];
	VFormat(buffer, sizeof(buffer), format, 2);
	for(int i = 1; i < MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i)) {
			AdminId admin = GetUserAdmin(i);
			if(admin != INVALID_ADMIN_ID) {
				CPrintToChat(i, "%s", buffer);
			}
		}
	}
	CPrintToServer("%s", buffer);
}
