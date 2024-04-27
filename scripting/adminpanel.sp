#pragma semicolon 1

#define DEBUG

// Every attempt waits exponentionally longer, up to this value.
#define MAX_ATTEMPT_TIMEOUT 120.0
#define DEFAULT_SERVER_PORT 7888
#define SOCKET_TIMEOUT_DURATION 90.0

#include <sourcemod>
#include <sdktools>
#include <ripext>
#include <left4dhooks>
#include <multicolors>
#include <jutils>
#include <socket>
#include <SteamWorks>

#pragma newdecls required

public Plugin myinfo = 
{
	name = "Admin Panel",
	author = "Jackz",
	description = "Plugin to integrate with admin panel",
	version = "1.0.0",
	url = "https://github.com/jackzmc/l4d2-admin-dash"
};

int LIVESTATUS_VERSION = 0;
Regex CommandArgRegex;

ConVar cvar_debug;
ConVar cvar_gamemode; char gamemode[32];
ConVar cvar_difficulty; int gameDifficulty;
ConVar cvar_maxplayers, cvar_visibleMaxPlayers;
ConVar cvar_address; char serverIp[16] = "127.0.0.1"; int serverPort = DEFAULT_SERVER_PORT; 
ConVar cvar_authToken; char authToken[256];

char currentMap[64];
int numberOfPlayers = 0;
int numberOfViewers;
int campaignStartTime;
int uptime;
bool isL4D1Survivors;
int lastReceiveTime;

char steamidCache[MAXPLAYERS+1][32];
char nameCache[MAXPLAYERS+1][MAX_NAME_LENGTH];
int g_icBeingHealed[MAXPLAYERS+1];
int playerJoinTime[MAXPLAYERS+1];
Handle updateHealthTimer[MAXPLAYERS+1];
Handle updateItemTimer[MAXPLAYERS+1];
Handle receiveTimeoutTimer = null;
int pendingTries = 3;

bool lateLoaded;

Socket g_socket;
enum AuthState {
	Auth_Fail = -1,
	Auth_Pending,
	Auth_Success,
}
AuthState authState;
enum GameState {
	State_None,
	State_Transitioning,
	State_Hibernating
}
GameState g_gameState;
#define BUFFER_SIZE 2048
Buffer sendBuffer;
Buffer receiveBuffer; // Unfortunately there's no easy way to have this not be the same as BUFFER_SIZE

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
	lateLoaded = late;
	return APLRes_Success;
}

public void OnPluginStart() {
	g_socket = new Socket(SOCKET_TCP, OnSocketError);
	g_socket.SetOption(SocketKeepAlive, 1);
	g_socket.SetOption(SocketReuseAddr, 1);
	g_socket.SetOption(SocketSendBuffer, BUFFER_SIZE);

	uptime = GetTime();
	cvar_debug = CreateConVar("sm_adminpanel_debug", "1", "Turn on debug mode", FCVAR_DONTRECORD, true, 0.0, true, 1.0);

	cvar_authToken = CreateConVar("sm_adminpanel_authtoken", "", "The token for authentication", FCVAR_PROTECTED);
	cvar_authToken.AddChangeHook(OnCvarChanged);
	cvar_authToken.GetString(authToken, sizeof(authToken));

	cvar_address = CreateConVar("sm_adminpanel_host", "127.0.0.1:7888", "The IP and port to connect to, default is 7888", FCVAR_NONE);
	cvar_address.AddChangeHook(OnCvarChanged);
	cvar_address.GetString(serverIp, sizeof(serverIp));
	OnCvarChanged(cvar_address, "", serverIp);

	cvar_maxplayers = FindConVar("sv_maxplayers");
	cvar_visibleMaxPlayers = FindConVar("sv_visiblemaxplayers");

	cvar_gamemode = FindConVar("mp_gamemode");
	cvar_gamemode.AddChangeHook(OnCvarChanged);
	cvar_gamemode.GetString(gamemode, sizeof(gamemode));

	cvar_difficulty = FindConVar("z_difficulty");
	cvar_difficulty.AddChangeHook(OnCvarChanged);
	gameDifficulty = GetDifficultyInt();

	HookEvent("game_init", Event_GameStart);
	HookEvent("game_end", Event_GameEnd);
	HookEvent("heal_begin", Event_HealStart);
	HookEvent("heal_success", Event_HealSuccess);
	HookEvent("heal_interrupted", Event_HealInterrupted);
	HookEvent("pills_used", Event_ItemUsed);
	HookEvent("adrenaline_used", Event_ItemUsed);
	HookEvent("weapon_drop", Event_WeaponDrop);
	HookEvent("player_spawn", Event_PlayerSpawn);
	HookEvent("map_transition", Event_MapTransition);
	HookEvent("player_death", Event_PlayerDeath);
	HookEvent("player_bot_replace", Event_PlayerToBot);
	HookEvent("bot_player_replace", Event_BotToPlayer);

	campaignStartTime = GetTime();
	char auth[32];
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientInGame(i)) {
			if(GetClientAuthId(i, AuthId_Steam2, auth, sizeof(auth))) {
				OnClientAuthorized(i, auth);
				OnClientPutInServer(i);
			}
		}
	}

	AutoExecConfig(true, "adminpanel");

	RegAdminCmd("sm_panel_debug", Command_PanelDebug, ADMFLAG_GENERIC);
	RegAdminCmd("sm_panel_request_stop", Command_RequestStop, ADMFLAG_GENERIC);

	CommandArgRegex = new Regex("(?:[^\\s\"]+|\"[^\"]*\")+", 0);

	CreateTimer(300.0, Timer_FullSync, _, TIMER_REPEAT);
}

Action Timer_FullSync(Handle h) {
	if(CanSendPayload(true)) {
		SendFullSync();
	}
	return Plugin_Continue;
}

void TriggerHealthUpdate(int client, bool instant = false) {
	if(updateHealthTimer[client] != null) {
		delete updateHealthTimer[client];
	}
	updateHealthTimer[client] = CreateTimer(instant ? 0.1 : 1.0, Timer_UpdateHealth, client);
}

void TriggerItemUpdate(int client) {
	if(updateItemTimer[client] != null) {
		delete updateItemTimer[client];
	}
	updateItemTimer[client] = CreateTimer(1.0, Timer_UpdateItems, client);
}

void OnSocketError(Socket socket, int errorType, int errorNumber, int any) {
	PrintToServer("[AdminPanel] Socket Error %d %d", errorType, errorNumber);
	if(!socket.Connected) {
		PrintToServer("[AdminPanel] Lost connection to socket, reconnecting", errorType, errorNumber);
		ConnectSocket();
	}
}

void SendFullSync() {
	PrintToServer("SendFullSync");
	if(StartPayload(true)) {
		PrintToServer("SendFullSync : Started");

		AddGameRecord();
		int stage = L4D2_GetCurrentFinaleStage();
		if(stage != 0)
			AddFinaleRecord(stage);
		SendPayload();

		// Resend all players
		SendPlayers();
	}
}

void OnSocketReceive(Socket socket, const char[] receiveData, int dataSize, int arg) {
	receiveBuffer.FromArray(receiveData, dataSize);
	LiveRecordResponse response = view_as<LiveRecordResponse>(receiveBuffer.ReadByte());
	if(cvar_debug.BoolValue) {
		PrintToServer("[AdminPanel] Received response=%d size=%d bytes", response, dataSize);
	}
	if(authState == Auth_Pending) {
		if(response == Live_OK) {
			authState = Auth_Success;
			pendingTries = 0;
			PrintToServer("[AdminPanel] Authenticated with server successfully.");
			SendFullSync();
		} else if(response == Live_Error) {
			authState = Auth_Fail;
			g_socket.Disconnect();
			char message[128];
			receiveBuffer.ReadString(message, sizeof(message));
			LogError("Failed to authenticate with socket: %s", message);
		} else {
			// Ignore packets when not authenticated
		}
		return;
	}

	lastReceiveTime = GetTime();
	switch(response) {
		case Live_RunCommand: {
			char command[128];
			char cmdNamespace[32];
			int id = receiveBuffer.ReadByte();
			receiveBuffer.ReadString(command, sizeof(command));
			receiveBuffer.ReadString(cmdNamespace, sizeof(cmdNamespace));
			if(cvar_debug.BoolValue) {
				PrintToServer("[AdminPanel] Running %s:%s", cmdNamespace, command);
			}
			ProcessCommand(id, command, cmdNamespace);
		}
		case Live_OK: {
			numberOfViewers = receiveBuffer.ReadByte();
		} 
		case Live_Error: {
			
		}
		case Live_Reconnect:
			CreateTimer(5.0, Timer_Reconnect);
		case Live_Refresh: {
			int userid = receiveBuffer.ReadByte();
			if(userid > 0) {
				int client = GetClientOfUserId(userid);
				if(client > 0 && StartPayload(true)) {
					PrintToServer("[AdminPanel] Sync requested for #%d, performing", userid);
					AddPlayerRecord(client);
					SendPayload();
				}
			} else {
				PrintToServer("[AdminPanel] Sync requested, performing");
				SendFullSync();
			}
		}
	}
	if(receiveTimeoutTimer != null) {
		delete receiveTimeoutTimer;
	}
	// receiveTimeoutTimer = CreateTimer(SOCKET_TIMEOUT_DURATION, Timer_Reconnect, 1);
}

void ProcessCommand(int id, const char[] command, const char[] cmdNamespace = "") {
	char output[128];
	if(!StartPayload(true)) return;
	if(cmdNamespace[0] == '\0' || StrEqual(cmdNamespace, "default")) {
		SplitString(command, " ", output, sizeof(output));
		if(CommandExists(output)) {
			ServerCommandEx(output, sizeof(output), "%s", command);
			AddCommandResponseRecord(id, Result_Boolean, 1, output);
		} else {
			AddCommandResponseRecord(id, Result_Error, -1, "Command does not exist");
		}
	} else if(StrEqual(cmdNamespace, "builtin")) {
		CommandResultType type;
		int result = ProcessBuiltin(command, type, output, sizeof(output));
		AddCommandResponseRecord(id, type, result, output);
	} else {
		AddCommandResponseRecord(id, Result_Error, -2, "Unknown namespace");
	}
	SendPayload();
}

int GetPlayersOnline() {
	int count;
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientInGame(i) && !IsFakeClient(i)) {
			count++;
		}
	}
	return count;
}

int ProcessBuiltin(const char[] fullCommand, CommandResultType &type = Result_Boolean, char[] output, int maxlen) {
	char command[32];
	int matches = CommandArgRegex.MatchAll(fullCommand);
	CommandArgRegex.GetSubString(0, command, sizeof(command), 0);
	if(StrEqual(command, "stop")) {
		type = Result_Boolean;
		RequestFrame(StopServer);
		return 1;
	} else if(StrEqual(command, "request_stop")) {
		type = Result_Boolean;
		int count = GetPlayersOnline();
		if(count > 0) {
			Format(output, maxlen, "There are %d players online", count);
			return 0;
		} else {
			RequestFrame(StopServer);
			return 1;
		}
	} else if(StrEqual(command, "kick")) {
		char arg[32];
		if(matches >= 2)
			CommandArgRegex.GetSubString(0, arg, sizeof(arg), 1);
		int player = FindPlayer(arg);
		if(player > 0) {
			// Is a player, kick em
			if(matches >= 3)
				CommandArgRegex.GetSubString(0, arg, sizeof(arg), 2);
			KickClient(player, arg);
			type = Result_Integer;
			return 1;
		} else {
			// Get the failure code
			type = Result_Error;
			GetTargetErrorReason(player, output, maxlen);
			return player;
		}
	} else if(StrEqual(command, "ban")) {
		char arg[32];
		if(matches >= 2)
			CommandArgRegex.GetSubString(0, arg, sizeof(arg), 1);
		int player = FindPlayer(arg);
		if(player > 0) {
			// Is a player, kick em
			if(matches >= 3)
				CommandArgRegex.GetSubString(0, arg, sizeof(arg), 2);
			int time = StringToInt(arg);
			if(matches >= 4)
				CommandArgRegex.GetSubString(0, arg, sizeof(arg), 3);
			type = Result_Integer;
			return BanClient(player, time, BANFLAG_AUTHID, arg, arg, "sm_adminpanel");
		} else {
			// Get the failure code
			GetTargetErrorReason(player, output, maxlen);
			type = Result_Error;
			return player;
		}
	} else if(StrEqual(command, "players")) {
		type = Result_Integer;
		return GetClientCount(false);	
	} else if(StrEqual(command, "unreserve")) {
		type = Result_Boolean;
		if(L4D_LobbyIsReserved()) {
			L4D_LobbyUnreserve();
			strcopy(output, maxlen, "Lobby reservation has been removed");
			return true;
		} else {
			strcopy(output, maxlen, "Lobby reservation has been already been removed");
			return false;
		}
	} else if(StrEqual(command, "cvar")) {
		char arg[64];
		if(matches >= 2)
			CommandArgRegex.GetSubString(0, arg, sizeof(arg), 1);
		ConVar cvar = FindConVar(arg);
		if(cvar == null) {
			type = Result_Error;
			strcopy(output, maxlen, "Cvar not found");
			return -1;
		} else {
			if(matches >= 3) {
				CommandArgRegex.GetSubString(0, arg, sizeof(arg), 2);
				cvar.SetString(arg);
				type = Result_Boolean;
				return true;
			} else {
				type = Result_Float;
				cvar.GetString(output, maxlen);
				return view_as<int>(cvar.FloatValue);
			}
		}
	} else {
		type = Result_Error;
		strcopy(output, maxlen, "Unknown builtin command");
		return -1;
	}
}

stock void GetTargetErrorReason(int reason, char[] output, int maxlen) {
	switch (reason) {
		case COMMAND_TARGET_NONE: {
			strcopy(output, maxlen, "No matching client");
		}
		case COMMAND_TARGET_NOT_ALIVE: {
			strcopy(output, maxlen, "Target must be alive");
		}
		case COMMAND_TARGET_NOT_DEAD: {
			strcopy(output, maxlen, "Target must be dead");
		}
		case COMMAND_TARGET_NOT_IN_GAME: {
			strcopy(output, maxlen, "Target is not in game");
		}
		case COMMAND_TARGET_IMMUNE: {
			strcopy(output, maxlen, "Unable to target");
		}
		case COMMAND_TARGET_EMPTY_FILTER: {
			strcopy(output, maxlen, "No matching clients");
		}
		case COMMAND_TARGET_NOT_HUMAN: {
			strcopy(output, maxlen, "Cannot target bot");
		}
		case COMMAND_TARGET_AMBIGUOUS: {
			strcopy(output, maxlen, "More than one client matched");
		}
	}
}

// Returns player index OR a target failure. > 0: player, <= 0: failure
int FindPlayer(const char[] arg) {
	// TODO: IMPLEMENT
	int targets[1];
	bool is_ml;
	int result = ProcessTargetString(arg, 0, targets, 1, 0, "", 0, is_ml);
	if(result == 1) return targets[0];
	return result;
}

void OnSocketConnect(Socket socket, int any) {
	if(cvar_debug.BoolValue)
		PrintToServer("[AdminPanel] Connected to %s:%d", serverIp, serverPort);
	g_socket.SetArg(0);

	PrintToServer("[AdminPanel] Authenticating with server");
	StartPayloadEx();
	AddAuthRecord();
	SendPayload();
}

void OnSocketDisconnect(Socket socket, int attempt) {
	authState = Auth_Pending;
	g_socket.SetArg(attempt + 1);
	float nextAttempt = Exponential(float(attempt) / 2.0) + 2.0;
	if(nextAttempt > MAX_ATTEMPT_TIMEOUT) nextAttempt = MAX_ATTEMPT_TIMEOUT;
	PrintToServer("[AdminPanel] Disconnected, retrying in %.0f seconds", nextAttempt);
	CreateTimer(nextAttempt, Timer_Reconnect);
}

Handle hibernateTimer;

public void L4D_OnServerHibernationUpdate(bool hibernating) {
	if(hibernating) {
		g_gameState = State_Hibernating;
		PrintToServer("[AdminPanel] Server is hibernating, disconnecting from socket");
		hibernateTimer = CreateTimer(30.0, Timer_Wake, 0, TIMER_REPEAT);
	} else {
		g_gameState = State_None;
		PrintToServer("[AdminPanel] Server is not hibernating");
		if(hibernateTimer != null) {
			delete hibernateTimer;
		}
	}

	if(StartPayload(true)) {
		AddGameRecord();
		SendPayload();
	}

	if(hibernating) {
		g_socket.Disconnect();
	} else {
		ConnectSocket();
	}
}

Action Timer_Wake(Handle h) {
	PrintToServer("[AdminPanel] Waking server from hibernation");
	return Plugin_Continue;
}

public void SteamWorks_SteamServersConnected() {
	if(StartPayload(true)) {
		AddMetaRecord(true);
		SendPayload();
	}
}

public void SteamWorks_SteamServersDisconnected() {
	if(StartPayload(true)) {
		AddMetaRecord(false);
		SendPayload();
	}
}

Action Timer_Reconnect(Handle h, int type) {
	if(type == 1) {
		PrintToServer("[AdminPanel] No response after %f seconds, attempting reconnect", SOCKET_TIMEOUT_DURATION);
	}
	ConnectSocket();
	return Plugin_Continue;
}

void ConnectSocket() {
	if(g_socket == null) LogError("Socket is invalid");
	if(g_socket.Connected)
		g_socket.Disconnect();
	if(authToken[0] == '\0') return;
	// Do not try to reconnect on auth failure, until token has changed
	if(authState == Auth_Fail) return;
	authState = Auth_Pending;
	g_socket.Connect(OnSocketConnect, OnSocketReceive, OnSocketDisconnect, serverIp, serverPort);
}

#define DATE_FORMAT "%F at %I:%M %p"
Action Command_PanelDebug(int client, int args) {
	char arg[32];
	GetCmdArg(1, arg, sizeof(arg));
	if(StrEqual(arg, "connect")) {
		if(authToken[0] == '\0') 
			ReplyToCommand(client, "No auth token.");
		else
			ConnectSocket();
	} else if(StrEqual(arg, "info")) {
		ReplyToCommand(client, "Connected: %b\tAuthenticated: %d\tState: %d", g_socket.Connected, authState, g_gameState);
		ReplyToCommand(client, "#Viewers: %d\t#Players: %d", numberOfViewers, numberOfPlayers);
		ReplyToCommand(client, "Target Host: %s:%d", serverIp, serverPort);
		ReplyToCommand(client, "Buffer Size: %d", BUFFER_SIZE);
		ReplyToCommand(client, "Can Send: %b\tCan Force-Send: %b", CanSendPayload(), CanSendPayload(true));
	} else if(StrEqual(arg, "cansend")) {
		if(!g_socket.Connected) ReplyToCommand(client, "Socket Not Connected");
		else if(authState != Auth_Success) ReplyToCommand(client, "Socket Not Authenticated (State=%d)", authState);
		else if(numberOfViewers == 0 || numberOfPlayers == 0) ReplyToCommand(client, "Can send forefully, but no players(%d)/viewers(%d)", numberOfPlayers, numberOfViewers);
		ReplyToCommand(client, "Can Send!");
	} else if(StrEqual(arg, "builtin")) {
		if(args < 2) {
			ReplyToCommand(client, "Usage: builtin <command>");
			return Plugin_Handled;
		}
		char command[128];
		GetCmdArg(2, command, sizeof(command));
		char output[128];
		CommandResultType type;
		int result = ProcessBuiltin(command, type, output, sizeof(output));
		if(type == Result_Float)
			ReplyToCommand(client, "Result: %f (type=%d)", result, view_as<int>(type));
		else
			ReplyToCommand(client, "Result: %d (type=%d)", result, view_as<int>(type));
		
		ReplyToCommand(client, "Output: %s", output);
	} else if(g_socket.Connected) {
		if(StrEqual(arg, "game")) {
			if(StartPayload(true)) {
				AddGameRecord();
				SendPayload();
				ReplyToCommand(client, "Sent Game record");
			} else { 
				ReplyToCommand(client, "StartPayload(): false");
			}
		} else if(StrEqual(arg, "players")) {
			SendPlayers();
		} else if(StrEqual(arg, "sync")) {
			SendFullSync();
		} else {
			ReplyToCommand(client, "Unknown type");
			return Plugin_Handled;
		}
	} else {
		ReplyToCommand(client, "Not connected");
	}
	return Plugin_Handled;
}

Action Command_RequestStop(int client, int args) {
	if(GetClientCount(false) > 0) {
		ReplyToCommand(client, "There are still %d players online.", GetClientCount(false));
	} else {
		ReplyToCommand(client, "Stopping...");
		RequestFrame(StopServer);
	}
	return Plugin_Handled;
}
void StopServer() {
	ServerCommand("exit");
}

void Event_GameStart(Event event, const char[] name, bool dontBroadcast) {
	campaignStartTime = GetTime();
	g_gameState = State_None;
	if(StartPayload(true)) {
		AddGameRecord();
		SendPayload();
	}
}
void Event_GameEnd(Event event, const char[] name, bool dontBroadcast) {
	campaignStartTime = 0;
	CreateTimer(10.0, Timer_FullSync);
}

void Event_MapTransition(Event event, const char[] name, bool dontBroadcast) {
	g_gameState = State_Transitioning;
	if(StartPayload(true)) {
		AddGameRecord();
		SendPayload();
	}
}

public void L4D_OnFirstSurvivorLeftSafeArea_Post(int client) {
	if(CanSendPayload()) {
		SendPlayers();
	}
}

void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(client > 0) {
		TriggerHealthUpdate(client, true);
	}
}
public void Event_PlayerToBot(Handle event, char[] name, bool dontBroadcast) {
	int player = GetClientOfUserId(GetEventInt(event, "player"));
	int bot    = GetClientOfUserId(GetEventInt(event, "bot")); 
	if(player > 0 && !IsFakeClient(player) && StartPayload(true)) {
		AddSurvivorRecord(player);
		SendPayload();
	}
}

public void Event_BotToPlayer(Handle event, char[] name, bool dontBroadcast) {
	int player = GetClientOfUserId(GetEventInt(event, "player"));
	int bot    = GetClientOfUserId(GetEventInt(event, "bot")); 
	if(player > 0 && !IsFakeClient(player) && StartPayload(true)) {
		// Bot is going away, remove it: (prob unnecessary OnClientDisconnect happens)
		AddPlayerRecord(bot, false);
		AddPlayerRecord(player);
		SendPayload();
	}
}

void Event_HealStart(Event event, const char[] name, bool dontBroadcast) {
	int subject = GetClientOfUserId(event.GetInt("subject"));
	g_icBeingHealed[subject] = true;
}
void Event_HealSuccess(Event event, const char[] name, bool dontBroadcast) {
	int healer = GetClientOfUserId(event.GetInt("userid"));
	int subject = GetClientOfUserId(event.GetInt("subject"));
	if(subject > 0 && StartPayload()) {
		g_icBeingHealed[subject] = false;
		// Update the subject's health:
		AddSurvivorRecord(subject);
		// Update the teammate who healed subject:
		AddSurvivorItemsRecord(healer);
		SendPayload();
	}
}
void Event_HealInterrupted(Event event, const char[] name, bool dontBroadcast) {
	int subject = GetClientOfUserId(event.GetInt("subject"));
	g_icBeingHealed[subject] = false;
}

void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast) {
	RecalculatePlayerCount();
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(client > 0 && StartPayload()) {
		AddPlayerRecord(client);
		SendPayload();
	}
}

void RecalculatePlayerCount() {
	int players = 0;
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && !IsFakeClient(i)) {
			players++;
		}
	}
	numberOfPlayers = players;
}

void SendPlayers() {
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientInGame(i)) {
			if(StartPayload(true)) {
				AddPlayerRecord(i);
				SendPayload();
			}
		}
	}
}

public void OnPlayerRunCmdPost(int client, int buttons, int impulse, const float vel[3], const float angles[3], int weapon, int subtype, int cmdnum, int tickcount, int seed, const int mouse[2]) {
	if(updateHealthTimer[client] != null)
		TriggerHealthUpdate(client);
}

public void OnMapStart() {
	GetCurrentMap(currentMap, sizeof(currentMap));
	numberOfPlayers = 0;
	if(StartPayload(true)) {
		AddGameRecord();
		SendPayload();

		SendPlayers();
	}
}

public void OnConfigsExecuted() {
	isL4D1Survivors = L4D2_GetSurvivorSetMap() == 1;
}
public void OnClientAuthorized(int client, const char[] auth) {
	if(!IsFakeClient(client)) {
		strcopy(steamidCache[client], 32, auth);
		numberOfPlayers++;
	} else {
		// Check if they are not a real survivor bot, such as ABMBot or EPIBot, etc
		if(StrContains(nameCache[client], "bot", false) > -1) {
			return;
		}
		strcopy(steamidCache[client], 32, "BOT");
	}
	GetClientName(client, nameCache[client], MAX_NAME_LENGTH);
	playerJoinTime[client] = GetTime();
	RequestFrame(SendNewClient, client);
}
// Player counts
public void OnClientPutInServer(int client) {
	if(g_gameState == State_Transitioning) {
		g_gameState = State_None;
		if(StartPayload()) {
			AddGameRecord();
			SendPayload();
		}
	}
	SDKHook(client, SDKHook_WeaponEquipPost, OnWeaponPickUp);
	SDKHook(client, SDKHook_OnTakeDamageAlivePost, OnTakeDamagePost);
	// We wait a frame because Event_PlayerFirstSpawn sets their join time
}

void OnWeaponPickUp(int client, int weapon) {
	// float time = GetGameTime();
	// if(time - lastUpdateTime[client] > 3.0 && StartPayload()) {
	// 	lastUpdateTime[client] = time;
	// 	AddSurvivorItemsRecord(client);
	// 	SendPayload();
	// }
	if(GetClientTeam(client) == 2)
		TriggerItemUpdate(client);
}

// Tracks the inventories for pills/adr used, kit used, ammo pack used, etc
void Event_WeaponDrop(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(client > 0) {
		if(GetClientTeam(client) == 2)
			TriggerItemUpdate(client);
		// if(StartPayload()) {
		// 	AddSurvivorItemsRecord(client);
		// 	SendPayload();
		// }
	}
}

void Event_ItemUsed(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(client > 0) {
		// if(StartPayload()) {
		// 	AddSurvivorRecord(client);
		// 	SendPayload();
		// }
		if(GetClientTeam(client) == 2)
			TriggerHealthUpdate(client);
	}
}

void OnTakeDamagePost(int victim, int attacker, int inflictor, float damage, int damagetype, int weapon, const float damageForce[3], const float damagePosition[3], int damagecustom) {
	if(damage > 1.0 && victim > 0 && victim <= MaxClients) {
		TriggerHealthUpdate(victim);
		// if(GetGameTime() - lastUpdateTime[victim] > 0.3 && StartPayload()) {
		// 	lastUpdateTime[victim] = GetGameTime();
		// 	if(GetClientTeam(victim) == 2)
		// 		AddSurvivorRecord(victim);
		// 	else
		// 		AddInfectedRecord(victim);
		// 	SendPayload();
		// }
	}
}

Action Timer_UpdateHealth(Handle h, int client) {
	if(IsClientInGame(client) && StartPayload()) {
		if(GetClientTeam(client) == 2)
			AddSurvivorRecord(client);
		else
			AddInfectedRecord(client);
		SendPayload();
	}
	updateHealthTimer[client] = null;
	return Plugin_Handled;
}
Action Timer_UpdateItems(Handle h, int client) {
	if(IsClientInGame(client) && StartPayload()) {
		AddSurvivorItemsRecord(client);
		SendPayload();
	}
	updateItemTimer[client] = null;
	return Plugin_Handled;
}

void SendNewClient(int client) {
	if(!IsClientInGame(client)) return;
	if(StartPayload()) {
		PrintToServer("SendNewClient(%N)", client);
		AddPlayerRecord(client);
		SendPayload();
	}
}

public void OnClientDisconnect(int client) {
	if(StartPayload()) {
		// hopefully userid is valid here?
		AddPlayerRecord(client, false);
		SendPayload();
	}
	steamidCache[client][0] = '\0';
	nameCache[client][0] = '\0';
	if(!IsFakeClient(client)) {
		numberOfPlayers--;
		// Incase somehow we lost track
		if(numberOfPlayers < 0) {
			numberOfPlayers = 0;
			CreateTimer(1.0, Timer_FullSync);
		}
	}
	if(updateHealthTimer[client] != null) {
		delete updateHealthTimer[client];
	}
	if(updateItemTimer[client] != null) {
		delete updateItemTimer[client];
	}
}

// Cvar updates
void OnCvarChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
	if(cvar_address == convar) {
		if(newValue[0] == '\0') {
			if(g_socket.Connected)
				g_socket.Disconnect();
			serverPort = DEFAULT_SERVER_PORT;
			serverIp = "127.0.0.1";
			PrintToServer("[AdminPanel] Deactivated");
		} else {
			int index = SplitString(newValue, ":", serverIp, sizeof(serverIp));
			if(index > -1) {
				serverPort = StringToInt(newValue[index]);
				if(serverPort == 0) serverPort = DEFAULT_SERVER_PORT;
			}
			PrintToServer("[AdminPanel] Sending data to %s:%d", serverIp, serverPort);
			ConnectSocket();
		}
	} else if(cvar_gamemode == convar) {
		strcopy(gamemode, sizeof(gamemode), newValue);
		if(StartPayload()) {
			AddGameRecord();
			SendPayload();
		}
	} else if(cvar_difficulty == convar) {
		gameDifficulty = GetDifficultyInt();
		if(StartPayload()) {
			AddGameRecord();
			SendPayload();
		}
	} else if(cvar_authToken == convar) {
		strcopy(authToken, sizeof(authToken), newValue);
		// Token changed, re-try authentication
		ConnectSocket();
	}
}

public void L4D2_OnChangeFinaleStage_Post(int finaleType, const char[] arg) {
	if(StartPayload()) {
		AddFinaleRecord(finaleType);
		SendPayload();
	}
}

enum {
	Action_BeingHealed      = -1,
	Action_None				= 0,	// No use action active
	Action_Healing			= 1,	// Includes healing yourself or a teammate.
	Action_AmmoPack			= 2,	// When deploying the ammo pack that was never added into the game
	Action_Defibing			= 4,	// When defib'ing a dead body.
	Action_GettingDefibed	= 5,	// When comming back to life from a dead body.
	Action_DeployIncendiary	= 6,	// When deploying Incendiary ammo
	Action_DeployExplosive	= 7,	// When deploying Explosive ammo
	Action_PouringGas		= 8,	// Pouring gas into a generator
	Action_Cola				= 9,	// For Dead Center map 2 cola event, when handing over the cola to whitalker.
	Action_Button			= 10,	// Such as buttons, timed buttons, generators, etc.
	Action_UsePointScript	= 11	// When using a "point_script_use_target" entity
}

int GetAction(int client) {
	if(g_icBeingHealed[client]) return Action_BeingHealed;
	return view_as<int>(L4D2_GetPlayerUseAction(client));
}

enum {
	Move_UnderAttack = -3,
	Move_Hanging = -2,
	Move_Incapped = -1,
	Move_Idle = 0,
	Move_Walk = 1,
	Move_Run = 2,
	Move_Crouched = 3,
	Move_Ladder = 4
}

stock float GetPlayerSpeed(int client) {
	int iVelocity = FindSendPropInfo("CTerrorPlayer", "m_vecVelocity[0]");
	float velocity[3];
	GetEntDataVector(client, iVelocity, velocity);
	return GetVectorLength(velocity, false);
}

int GetPlayerMovement(int client) {
	MoveType moveType = GetEntityMoveType(client);
	if(moveType == MOVETYPE_LADDER) return Move_Ladder;
	else if(GetEntProp(client, Prop_Send, "m_bDucked", 1)) return Move_Crouched;
	else if(GetEntProp(client, Prop_Send, "m_isIncapacitated", 1)) return Move_Incapped;
	else if(GetEntProp(client, Prop_Send, "m_isHangingFromLedge", 1)) return Move_Hanging;
	else if(L4D_GetPinnedSurvivor(client)) return Move_UnderAttack; // TODO: optimize for events
	float velocity = GetPlayerSpeed(client);
	if(velocity > 85.0) return Move_Run;
	else if(velocity > 1.0) return Move_Walk;
	return Move_Idle;
}

// TODO: pursued by witch
enum {
	pState_BlackAndWhite = 1,
	pState_InSaferoom = 2,
	pState_IsCalm = 4,
	pState_IsBoomed = 8,
	pState_IsPinned = 16,
	pState_IsAlive = 32,
}

stock bool IsPlayerBoomed(int client) {
	return (GetEntPropFloat(client, Prop_Send, "m_vomitStart") + 20.1) > GetGameTime();
}

int GetPlayerStates(int client) {
	int state = 0;
	if(L4D_IsInLastCheckpoint(client) || L4D_IsInFirstCheckpoint(client))
		state |= pState_InSaferoom;
	if(GetEntProp(client, Prop_Send, "m_bIsOnThirdStrike", 1)) state |= pState_BlackAndWhite;
	if(GetEntProp(client, Prop_Send, "m_isCalm")) state |= pState_IsCalm;
	if(IsPlayerBoomed(client)) state |= pState_IsBoomed;
	if(IsPlayerAlive(client)) state |= pState_IsAlive;
	if(L4D2_GetInfectedAttacker(client) > 0) state |= pState_IsPinned;
	return state;
}

stock int GetDifficultyInt() {
	char diff[16];
	cvar_difficulty.GetString(diff, sizeof(diff));
	if(StrEqual(diff, "easy", false)) return 0;
	else if(StrEqual(diff, "hard", false)) return 2;
	else if(StrEqual(diff, "impossible", false)) return 3;
	else return 1;
}

enum CommandResultType {
	Result_Error = -1,
	Result_None,
	Result_Boolean,
	Result_Integer,
	Result_Float
}

enum LiveRecordType {
	Live_Game = 0,
	Live_Player = 1,
	Live_Survivor = 2,
	Live_Infected = 3,
	Live_Finale = 4,
	Live_SurvivorItems = 5,
	Live_CommandResponse = 6,
	Live_Auth = 7,
	Live_Meta = 8
}
char LIVE_RECORD_NAMES[view_as<int>(Live_Meta)+1][] = {
	"Game",
	"Player",
	"Survivor",
	"Infected",
	"Finale",
	"Items",
	"Commands",
	"Auth",
	"Meta"
};

enum LiveRecordResponse {
	Live_OK,
	Live_Reconnect,
	Live_Error,
	Live_Refresh,
	Live_RunCommand
}

char pendingRecords[64];

bool CanSendPayload(bool ignorePause = false) {
	if(!g_socket.Connected) return false;
	if(authState != Auth_Success) {
		if(authState == Auth_Pending && pendingTries > 0) {
			pendingTries--;
			PrintToServer("[AdminPanel] Auth state is pending. Too early?");
			ConnectSocket();
		}
		return false;
	}
	if(!ignorePause && (numberOfViewers == 0 || numberOfPlayers == 0)) return false;
	return true;
}

bool StartPayload(bool ignorePause = false) {
	if(!CanSendPayload(ignorePause)) return false;
	StartPayloadEx();
	return true;
}

/// Starts payload, ignoring if the payload can even be sent
bool hasRecord;
int recordStart;
bool pendingRecord;

void StartPayloadEx() {
	if(pendingRecord) {
		LogError("StartPayloadEx called before EndRecord()");
	}
	sendBuffer.Reset();
	hasRecord = false;
	pendingRecords[0] = '\0';
	recordStart = 0;
	pendingRecord = false;
	
}


void StartRecord(LiveRecordType type) {
	if(pendingRecord) {
		LogError("StartRecord called before EndRecord()");
	}
	if(hasRecord) {
		sendBuffer.WriteChar('\x1e');
	}
	if(cvar_debug.BoolValue)
		Format(pendingRecords, sizeof(pendingRecords), "%s%s ", pendingRecords, LIVE_RECORD_NAMES[view_as<int>(type)]);
	recordStart = sendBuffer.offset;
	sendBuffer.WriteShort(-1); // write temp value to be replaced when record ends
	sendBuffer.WriteByte(view_as<int>(type));
	pendingRecord = true;
}

void EndRecord() {
	int length = sendBuffer.offset - recordStart - 2; // subtract 1, as don't count length inside
	sendBuffer.WriteShortAt(length, recordStart);
	// if(cvar_debug.BoolValue) {
	// 	int type = sendBuffer.ReadByteAt(recordStart + 2);
	// 	PrintToServer("End record %s(%d) (start: %d, end: %d) length: %d", LIVE_RECORD_NAMES[view_as<int>(type)], type, recordStart, sendBuffer.offset, length);
	// }
	hasRecord = true;
	pendingRecord = false;
}

void AddGameRecord() {
	StartRecord(Live_Game);
	sendBuffer.WriteInt(uptime);
	sendBuffer.WriteInt(campaignStartTime);
	sendBuffer.WriteByte(gameDifficulty);
	sendBuffer.WriteByte(view_as<int>(g_gameState));
	sendBuffer.WriteByte(GetMaxPlayers());
	sendBuffer.WriteString(gamemode);
	sendBuffer.WriteString(currentMap);
	EndRecord();
}	

void AddFinaleRecord(int stage) {
	StartRecord(Live_Finale);
	sendBuffer.WriteByte(stage); // finale stage
	sendBuffer.WriteByte(L4D_IsFinaleEscapeInProgress()); // escape or not
	EndRecord();
}

void AddPlayerRecord(int client, bool connected = true) {
	// fake bots are ignored:
	if(steamidCache[client][0] == '\0') return;

	bool isIdle = false;
	StartRecord(Live_Player);
	sendBuffer.WriteInt(GetClientUserId(client));
	sendBuffer.WriteString(steamidCache[client]);
	if(connected) {
		sendBuffer.WriteByte(isIdle);
		sendBuffer.WriteInt(playerJoinTime[client]);
		sendBuffer.WriteString(nameCache[client]);
		EndRecord();

		if(GetClientTeam(client) == 2) {
			AddSurvivorRecord(client);
			AddSurvivorItemsRecord(client);
		} else if(GetClientTeam(client) == 3) {
			AddInfectedRecord(client);
		}
	} else {
		EndRecord();
	}
}

void AddSurvivorRecord(int client) {
	if(steamidCache[client][0] == '\0') return;

	int userid = GetClientUserId(client);
	int bot = L4D_GetBotOfIdlePlayer(client);
	if(bot > 0) client = bot;

	int survivor = GetEntProp(client, Prop_Send, "m_survivorCharacter");
	// The icons are mapped for survivors as 4,5,6,7; so inc to that for L4D1 survivors
	if(isL4D1Survivors) {
		survivor += 4; 
	}
	if(survivor >= 8) LogError("invalid survivor %d", survivor);

	StartRecord(Live_Survivor);
	sendBuffer.WriteInt(userid);
	sendBuffer.WriteByte(survivor);
	sendBuffer.WriteByte(L4D_GetPlayerTempHealth(client)); //temp health
	int health = IsPlayerAlive(client) ? GetEntProp(client, Prop_Send, "m_iHealth"): 0;
	sendBuffer.WriteByte(health); //perm health
	sendBuffer.WriteByte(L4D2_GetVersusCompletionPlayer(client)); // flow%
	sendBuffer.WriteInt(GetPlayerStates(client)); // state (incl. alive)
	sendBuffer.WriteInt(GetPlayerMovement(client)); // move
	sendBuffer.WriteInt(GetAction(client)); // action
	EndRecord();
}
void AddSurvivorItemsRecord(int client) {
	if(steamidCache[client][0] == '\0') return;

	int userid = GetClientUserId(client);
	int bot = L4D_GetBotOfIdlePlayer(client);
	if(bot > 0) client = bot;

	StartRecord(Live_SurvivorItems);
	sendBuffer.WriteInt(userid);
	char name[32];
	for(int slot = 0; slot < 6; slot++) {
		name[0] = '\0';
		GetClientWeaponNameSmart2(client, slot, name, sizeof(name));
		sendBuffer.WriteString(name);
	}
	EndRecord();
}
void AddInfectedRecord(int client) {
	StartRecord(Live_Infected);
	sendBuffer.WriteInt(GetClientUserId(client));
	int health = IsPlayerAlive(client) ? GetEntProp(client, Prop_Send, "m_iHealth"): 0;
	sendBuffer.WriteShort(health); //cur health
	sendBuffer.WriteShort(GetEntProp(client, Prop_Send, "m_iMaxHealth")); //max health
	sendBuffer.WriteByte(L4D2_GetPlayerZombieClass(client)); // class
	int victim = L4D2_GetSurvivorVictim(client);
	if(victim > 0)
		sendBuffer.WriteInt(GetClientUserId(victim));
	else
		sendBuffer.WriteInt(0);
	EndRecord();
}

void AddCommandResponseRecord(int id, CommandResultType resultType = Result_None, int resultValue = 0, const char[] message = "") {
	StartRecord(Live_CommandResponse);
	sendBuffer.WriteByte(id);
	sendBuffer.WriteByte(view_as<int>(resultType));
	sendBuffer.WriteByte(resultValue);
	sendBuffer.WriteString(message);
	EndRecord();
}

void AddAuthRecord() {
	if(authToken[0] == '\0') {
		LogError("AddAuthRecord called with missing auth token");
	}
	StartRecord(Live_Auth);
	sendBuffer.WriteByte(LIVESTATUS_VERSION);
	sendBuffer.WriteString(authToken);
	EndRecord();
}

void AddMetaRecord(bool state) {
	StartRecord(Live_Meta);
	sendBuffer.WriteByte(state);
	EndRecord();
}

void SendPayload() {
	if(sendBuffer.offset == 0) return;
	int len = sendBuffer.Finish();
	if(cvar_debug.BoolValue) {
		PrintToServer("[AdminPanel] Sending %d bytes of data (records = %s)", len, pendingRecords);
	}
	g_socket.Send(sendBuffer.buffer, len);
}

enum struct Buffer {
	char buffer[BUFFER_SIZE];
	int offset;

	void Reset() {
		this.buffer[0] = '\0';
		this.offset = 0;
	}

	void FromArray(const char[] input, int size) {
		this.Reset();
		int max = BUFFER_SIZE;
		if(size < max) max = size;
		for(int i = 0; i < max; i++) {
			this.buffer[i] = input[i];
		}
	}

	void Print() {
		char[] output = new char[BUFFER_SIZE+100];
		for(int i = 0; i < BUFFER_SIZE; i++) {
			if(this.buffer[i] == '\0') {
				Format(output, BUFFER_SIZE, "%s \\0", output);
			} else {
				Format(output, BUFFER_SIZE, "%s %c", output, this.buffer[i]);
			}
		}
		PrintToServer("%s", output); 
	}

	void WriteChar(char c) {
		this.buffer[this.offset++] = c;
	}

	void WriteByte(int value) {
		this.buffer[this.offset++] = value & 0xFF;
	}

	void WriteByteAt(int value, int offset) {
		this.buffer[offset] = value & 0xFF;
    }

	void WriteShort(int value) {
		this.buffer[this.offset++] = value & 0xFF;
		this.buffer[this.offset++] = (value >> 8) & 0xFF;
	}

	void WriteShortAt(int value, int offset) {
		this.buffer[offset] = value & 0xFF;
		this.buffer[offset+1] = (value >> 8) & 0xFF;
    }

	void WriteInt(int value) {
		this.WriteIntAt(value, this.offset);
		this.offset += 4;
	}

	void WriteIntAt(int value, int offset) {
		this.buffer[offset] = value & 0xFF;
		this.buffer[offset+1] = (value >> 8) & 0xFF;
		this.buffer[offset+2] = (value >> 16) & 0xFF;
		this.buffer[offset+3] = (value >> 24) & 0xFF;
    }

	void WriteFloat(float value) {
		this.WriteInt(view_as<int>(value));
	}

	// Writes a null-terminated length string, strlen > size is truncated.
	void WriteString(const char[] string) {
		this.buffer[this.offset] = '\0';
		int written = strcopy(this.buffer[this.offset], BUFFER_SIZE, string);
		this.offset += written + 1;
	}

	int ReadByte() {
		return this.buffer[this.offset++] & 0xFF;
	}

	int ReadByteAt(int offset) {
		return this.buffer[offset] & 0xFF;
	}

	int ReadShort() {
		int value = this.buffer[this.offset++];
		value += this.buffer[this.offset++] << 8;
		return value;
	}

	int ReadInt() {
		int value = this.buffer[this.offset++];
		value += this.buffer[this.offset++] << 8;
		value += this.buffer[this.offset++] << 16;
		value += this.buffer[this.offset++] << 32;
		return value;
	}

	float ReadFloat() {
		return view_as<float>(this.ReadInt());
	}

	int ReadString(char[] output, int maxlen) {
		int len = strcopy(output, maxlen, this.buffer[this.offset]) + 1;
		this.offset += len;
		return len;
	}

	char ReadChar() {
		return this.buffer[this.offset++];
	}

	bool EOF() {
		return this.offset >= BUFFER_SIZE;
	}

	int Finish() {
		this.buffer[this.offset++] = '\x0A';
		return this.offset;
	}
}

int GetMaxPlayers() {
	if(cvar_visibleMaxPlayers != null && cvar_visibleMaxPlayers.IntValue > 0) return cvar_visibleMaxPlayers.IntValue;
	if(cvar_maxplayers != null) return cvar_maxplayers.IntValue;
	return L4D_IsVersusMode() ? 8 : 4;
}