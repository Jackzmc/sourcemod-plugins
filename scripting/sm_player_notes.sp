#pragma semicolon 1
#pragma newdecls required

//#define DEBUG

#define PLUGIN_VERSION "1.0"
#define MAX_PLAYER_HISTORY 25
#define MAX_NOTES_TO_SHOW 10
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
static char menuNoteTargetName[32];

enum struct PlayerData {
	char id[32];
	char name[32];
}

static ArrayList lastPlayers;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("AddNoteIdentity", Native_AddNoteIdentity);
	return APLRes_Success;
}

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

	RegConsoleCmd("sm_rep", Command_RepPlayer, "+rep or -rep a player");
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

void ShowRepMenu(int client, int targetUserid) { 
	Menu menu = new Menu(RepFinalHandler);
	menu.SetTitle("Choose a rating");
	char id[8];
	Format(id, sizeof(id), "%d|1", targetUserid);
	menu.AddItem(id, "+Rep");
	Format(id, sizeof(id), "%d|1", targetUserid);
	menu.AddItem(id, "-Rep");
	menu.Display(client, 0);
}

public int RepPlayerHandler(Menu menu, MenuAction action, int param1, int param2) {
	/* If an option was selected, tell the client about the item. */
	if (action == MenuAction_Select) {
		static char info[4];
		menu.GetItem(param2, info, sizeof(info));
		int targetUserid = StringToInt(info);
		int target = GetClientOfUserId(targetUserid);

		if(target == 0) {
			ReplyToCommand(param1, "Could not acquire player");
			return 0;
		}
		
		ShowRepMenu(param1, targetUserid);
	} else if (action == MenuAction_End) {
		delete menu;
	}
	return 0;
}

public int RepFinalHandler(Menu menu, MenuAction action, int param1, int param2) {
	/* If an option was selected, tell the client about the item. */
	if (action == MenuAction_Select) {
		char info[8];
		menu.GetItem(param2, info, sizeof(info));
		char str[2][8];
		ExplodeString(info, "|", str, 2, 8, false);
		int targetUserid = StringToInt(str[0]);
		int target = GetClientOfUserId(targetUserid);
		int rep = StringToInt(str[1]);

		if(target == 0) {
			ReplyToCommand(param1, "Could not acquire player");
			return 0;
		}
		
		ApplyRep(param1, target, rep);
	} else if (action == MenuAction_End) {
		delete menu;
	}
	return 0;
}

public Action Command_RepPlayer(int client, int args) {
	if(client == 0) { 
		ReplyToCommand(client, "You must be a player to use this command.");
		return Plugin_Handled;
	}
	if(args == 0) {
		Menu menu = new Menu(RepPlayerHandler);
		menu.SetTitle("Choose a player to rep");
		char id[8], display[64];
		// int clientTeam = GetClientTeam(client);
		for(int i = 1; i <= MaxClients; i++) { 
			if(i != client && IsClientConnected(i) && IsClientInGame(i) && !IsFakeClient(i)) {
				Format(id, sizeof(id), "%d", GetClientUserId(i));
				Format(display, sizeof(display), "%N", i);
				menu.AddItem(id, display);
			}
		}
		menu.Display(client, 0);
		return Plugin_Handled;
	} else if(args > 0) { 
		char arg1[32];
		GetCmdArg(1, arg1, sizeof(arg1));
		char target_name[MAX_TARGET_LENGTH];
		int target_list[1], target_count;
		bool tn_is_ml;
		if ((target_count = ProcessTargetString(
				arg1,
				client,
				target_list,
				1,
				COMMAND_FILTER_ALIVE,
				target_name,
				sizeof(target_name),
				tn_is_ml)) <= 0)
		{
			/* This function replies to the admin with a failure message */
			ReplyToTargetError(client, target_count);
			return Plugin_Handled;
		}
		if (args == 1) {
			ShowRepMenu(client, GetClientUserId(target_list[0]));
		} else {
			char arg2[2];
			GetCmdArg(2, arg2, sizeof(arg2));
			int rep;
			if(arg2[0] == 'y' || arg2[0] == '+' || arg2[0] == 'p') {
				rep = 1;
			} else if(arg2[0] == 'n' || arg2[0] == '-' || arg2[0] == 's') { 
				rep = -1;
			} else {
				ReplyToCommand(client, "Invalid rep value: Use (y/+/p) for +rep or (n/-/s) for -rep");
				return Plugin_Handled;
			}
			ApplyRep(client, target_list[0], rep);
		}
	}
	return Plugin_Handled;
}

void ApplyRep(int client, int target, int rep) { 
	char[] msg = "+rep";
	if(rep == -1) msg[0] = '-';

	LogAction(client, target, "\"%L\" %srep \"%L\"", client, msg, target);
	if(rep > 0)
		CShowActivity(client, "{green}+rep %N", target);
	else
		CShowActivity(client, "{yellow}-rep %N", target);

	char activatorId[32], targetId[32];
	GetClientAuthId(client, AuthId_Steam2, activatorId, sizeof(activatorId));
	GetClientAuthId(target, AuthId_Steam2, targetId, sizeof(targetId));
	AddNoteIdentity(activatorId, targetId, msg);
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
		int style;
		menu.GetItem(item, menuNoteTarget, sizeof(menuNoteTarget), style, menuNoteTargetName, sizeof(menuNoteTargetName));
		CPrintToChat(client, "Enter a note in the chat for {yellow}%s {olive}(%s){default}: (or 'cancel' to cancel)", menuNoteTargetName, menuNoteTarget);
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
			int size = strlen(sArgs) + 1;
			char[] sArgsTrimmed = new char[size];
			strcopy(sArgsTrimmed, size, sArgs);
			TrimString(sArgsTrimmed);
			char buffer[32];
			GetClientAuthId(client, AuthId_Steam2, buffer, sizeof(buffer));
			DB.Format(query, sizeof(query), "INSERT INTO `notes` (steamid, markedBy, content) VALUES ('%s', '%s', '%s')", menuNoteTarget, buffer, sArgsTrimmed);
			DB.Query(DB_AddNote, query);
			LogAction(client, -1, "\"%L\" added note for \"%s\" (%s): \"%s\"", client, menuNoteTargetName, menuNoteTarget, sArgsTrimmed);
			Format(buffer, sizeof(buffer), "%N: ", client);
			CShowActivity2(client, buffer, "added a note for {green}%s: {default}\"%s\"", menuNoteTargetName, sArgsTrimmed);
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
		TrimString(reason);
		if(args > 2) {
			// Correct commands that don't wrap message in quotes
			char buffer[64];
			for(int i = 3; i <= args; i++) {
				GetCmdArg(i, buffer, sizeof(buffer));
				Format(reason, sizeof(reason), "%s %s", reason, buffer);
			}
		}

		if(reason[0] == '\0') {
			ReplyToCommand(client, "Can't create an empty note");
			return Plugin_Handled;
		}

		int target_list[1], target_count;
		bool tn_is_ml;
		if ((target_count = ProcessTargetString(
			target_name,
			client,
			target_list,
			1,
			COMMAND_FILTER_NO_MULTI | COMMAND_FILTER_NO_IMMUNITY,
			target_name,
			sizeof(target_name),
			tn_is_ml)) <= 0
		) {
			if(target_count == COMMAND_TARGET_NONE) {
				ReplyToCommand(client, "Could not find any online user. If user has disconnected, use sm_notedisconnected");
			} else {
				ReplyToTargetError(client, target_count);
			}
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
			COMMAND_FILTER_NO_MULTI | COMMAND_FILTER_NO_IMMUNITY,
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
		DB.Format(query, sizeof(query), "SELECT notes.content, stats_users.last_alias, markedBy FROM `notes` JOIN stats_users ON markedBy = stats_users.steamid WHERE notes.`steamid` = '%s'", auth);
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
		int actions = 0;
		int repP = 0, repN = 0;
		while(results.FetchRow()) {
			DBResult result;
			results.FetchString(0, reason, sizeof(reason));
			results.FetchString(1, noteCreator, sizeof(noteCreator), result);
			if(result == DBVal_Null) {
				// No name for admin, get the raw id:
				results.FetchString(2, noteCreator, sizeof(noteCreator), result);
			}
			TrimString(reason);
			if(ParseActions(data, reason)) {
				actions++;
			} else if((reason[0] == '+' || reason[0] == '-') && reason[1] == 'r' && reason[2] == 'e' && reason[3] == 'p') {
				if(reason[0] == '+') {
					repP++;
				} else {
					repN--;
				}
			} else {
				CPrintChatToAdmins("  {olive}%s: {default}%s", noteCreator, reason);
			}
		}

		if(actions > 0) {
			CPrintChatToAdmins("  > {olive}%d Auto Actions Applied", actions);
		}
		if(repP > 0 || repN > 0) {
			CPrintChatToAdmins("  > {olive}%d +rep\t{yellow}-rep", repP, repN);
		}
	}
}

#define ACTION_DESTINATOR '@'
#define ACTION_SEPERATOR "."
bool ParseActions(int userid, const char[] input) {
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
		strcopy(key, sizeof(key), piece[keyIndex + 1]);
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

	ApplyAction(userid, piece[1], key, value);
	// } while((index = SplitString(input[prevIndex], " ", piece, sizeof(piece))) != -1);

	return true;
}

bool ApplyAction(int targetUserId, const char[] action, const char[] key, const char[] value) {
	// If action is 'fta*' or 'ftas'
	int target = GetClientOfUserId(targetUserId);
	if(target == 0) return false;
	LogAction(-1, target, "activating automatic action on \"%L\": @%s.%s.%s", target, action, key, value);
	if(StrContains(action, "fta") > -1) {
		#if defined _ftt_included_
			// Replace under scores with spaces
			char newKey[32];
			strcopy(newKey, sizeof(newKey), key);
			ReplaceString(newKey, sizeof(newKey), "_", " ", true);
			int flags = StringToInt(value);
			ApplyTroll(target, newKey, TrollMod_Invalid, flags, 0, action[4] == 's');
		#else
			PrintToServer("[PlayerNotes] Warn: Action \"%s\" for %N has missing plugin: Feed The Trolls", action, target);
			return false;
		#endif
	} else if(strncmp(action, "ignore", 6) == 0) {
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
			return false;
		#endif
	} else if(strncmp(action, "slap", 4) == 0) {
		float delay = StringToFloat(key);
		CreateTimer(delay, Timer_SlapPlayer, targetUserId);
	} else {
		PrintToServer("[PlayerNotes] Warn: Action (\"%s\") for %N is not valid", action, target);
		return false;
	}

	return true;
}

Action Timer_SlapPlayer(Handle h, int userid) {
	int client = GetClientOfUserId(userid);
	if(client > 0) {
		SlapPlayer(client, 0, true);
	}
	return Plugin_Handled;
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

any Native_AddNoteIdentity(Handle plugin, int numParams) {
	char noteCreator[32];
	char noteTarget[32];
	int length;
	GetNativeStringLength(3, length);
	char[] message = new char[length + 1];
	GetNativeString(1, noteCreator, sizeof(noteCreator));
	GetNativeString(2, noteTarget, sizeof(noteTarget));
	GetNativeString(3, message, length);
	AddNoteIdentity(noteCreator, noteTarget, message);
	return 0;
}

void AddNoteIdentity(const char noteCreator[32], const char noteTarget[32], const char[] message) {
	// messaege length + steamids (32 + 32 + null term)
	// char[] query = new char[strlen(message) + 65];
	DB.Format(query, sizeof(query), "INSERT INTO `notes` (steamid, markedBy, content) VALUES ('%s', '%s', '%s')", noteCreator, noteTarget, message);
	DB.Query(DB_AddNote, query);
}