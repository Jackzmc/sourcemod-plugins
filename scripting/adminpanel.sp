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


ConVar cvar_debug;
ConVar cvar_gamemode; char gamemode[32];
ConVar cvar_difficulty; int gameDifficulty;
ConVar cvar_id; char serverId[32];
ConVar cvar_address; char serverIp[16] = "127.0.0.1"; int serverPort = DEFAULT_SERVER_PORT; 

char currentMap[64];
int numberOfPlayers = 0;
int campaignStartTime;
int uptime;
bool g_inTransition;
bool isL4D1Survivors;
int lastReceiveTime;

char steamidCache[MAXPLAYERS+1][32];
char nameCache[MAXPLAYERS+1][MAX_NAME_LENGTH];
int g_icBeingHealed[MAXPLAYERS+1];
int playerJoinTime[MAXPLAYERS+1];
Handle updateHealthTimer[MAXPLAYERS+1];
Handle updateItemTimer[MAXPLAYERS+1];
Handle receiveTimeoutTimer = null;

bool lateLoaded;

Socket g_socket;
bool g_isPaused;
#define BUFFER_SIZE 2048
Buffer sendBuffer;
Buffer receiveBuffer; // Unfortunately there's no easy way to have this not be the same as BUFFER_SIZE

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	lateLoaded = late;
	return APLRes_Success;
}

public void OnPluginStart()
{
	// TODO: periodic reconnect
	g_socket = new Socket(SOCKET_TCP, OnSocketError);
	g_socket.SetOption(SocketKeepAlive, 1);
	g_socket.SetOption(SocketReuseAddr, 1);

	uptime = GetTime();
	cvar_debug = CreateConVar("sm_adminpanel_debug", "0", "Turn on debug mode", FCVAR_DONTRECORD, true, 0.0, true, 1.0);

	cvar_id = CreateConVar("sm_adminpanel_id", "", "The server ID to post updates for", FCVAR_NONE);
	cvar_id.AddChangeHook(OnCvarChanged);
	cvar_id.GetString(serverId, sizeof(serverId));

	cvar_address = CreateConVar("sm_adminpanel_host", "100.108.152.125:7888", "The IP and port to connect to, default is 7888", FCVAR_NONE);
	cvar_address.AddChangeHook(OnCvarChanged);
	cvar_address.GetString(serverIp, sizeof(serverIp));
	OnCvarChanged(cvar_address, "", serverIp);

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
	HookEvent("player_first_spawn", Event_PlayerFirstSpawn);
	HookEvent("map_transition", Event_MapTransition);
	HookEvent("player_death", Event_PlayerDeath);

	campaignStartTime = GetTime();
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i)) {
			playerJoinTime[i] = GetTime();
			OnClientPutInServer(i);
		}
	}

	AutoExecConfig(true, "adminpanel");

	RegAdminCmd("sm_panel_debug", Command_PanelDebug, ADMFLAG_GENERIC);
	RegAdminCmd("sm_panel_request_stop", Command_RequestStop, ADMFLAG_GENERIC);
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

void OnSocketReceive(Socket socket, const char[] receiveData, int dataSize, int arg) {
	receiveBuffer.FromArray(receiveData, dataSize);
	LiveRecordResponse response = view_as<LiveRecordResponse>(receiveBuffer.ReadByte());
	if(cvar_debug.BoolValue) {
		PrintToServer("[AdminPanel] Received: %d", response);
	}
	lastReceiveTime = GetTime();
	switch(response) {
		case Live_OK: {
			int viewerCount = receiveBuffer.ReadByte();
			g_isPaused = viewerCount == 0;
		} 
		case Live_Reconnect:
			CreateTimer(5.0, Timer_Reconnect);
		case Live_Refresh: {
			PrintToServer("[AdminPanel] Refresh requested, performing");
			StartPayload();
			AddGameRecord();
			SendPayload();

			SendPlayers();
		}
	}
	if(receiveTimeoutTimer != null) {
		delete receiveTimeoutTimer;
	}
	receiveTimeoutTimer = CreateTimer(SOCKET_TIMEOUT_DURATION, Timer_Reconnect, 1);
}

void OnSocketConnect(Socket socket, int any) {
	if(cvar_debug.BoolValue)
		PrintToServer("[AdminPanel] Connected to %s:%d", serverIp, serverPort);
	g_socket.SetArg(0);
	// Late loads / first setup we can't send
	if(currentMap[0] != '\0' && StartPayload()) {
		AddGameRecord();
		SendPayload();
		// Resend all players
		SendPlayers();
	}
}

void OnSocketDisconnect(Socket socket, int attempt) {
	g_socket.SetArg(attempt + 1);
	float nextAttempt = Exponential(float(attempt) / 2.0) + 2.0;
	if(nextAttempt > MAX_ATTEMPT_TIMEOUT) nextAttempt = MAX_ATTEMPT_TIMEOUT;
	PrintToServer("[AdminPanel] Disconnected, retrying in %.0f seconds", nextAttempt);
	CreateTimer(nextAttempt, Timer_Reconnect);
}

Action Timer_Reconnect(Handle h, int type) {
	if(type == 1) {
		PrintToServer("[AdminPanel] No response after %f seconds, attempting reconnect", SOCKET_TIMEOUT_DURATION);
	}
	ConnectSocket();
	return Plugin_Handled;
}

void ConnectSocket() {
	if(g_socket == null) LogError("Socket is invalid");
	if(g_socket.Connected)
		g_socket.Disconnect();
	if(serverId[0] == '\0') return;
	g_socket.SetOption(DebugMode, cvar_debug.BoolValue);
	g_socket.Connect(OnSocketConnect, OnSocketReceive, OnSocketDisconnect, serverIp, serverPort);
}

#define DATE_FORMAT "%F at %I:%M %p"
Action Command_PanelDebug(int client, int args) {
	char arg[32];
	GetCmdArg(1, arg, sizeof(arg));
	if(StrEqual(arg, "connect")) {
		if(serverId[0] == '\0') 
			ReplyToCommand(client, "No server id.");
		else
			ConnectSocket();
	} else if(StrEqual(arg, "info")) {
		ReplyToCommand(client, "Connected: %b\tPaused: %b\t#Player: %d", g_socket.Connected, g_isPaused, numberOfPlayers);
		ReplyToCommand(client, "ID: %s", serverId);
		ReplyToCommand(client, "Target Host: %s:%d", serverIp, serverPort);
		ReplyToCommand(client, "Buffer Size: %d", BUFFER_SIZE);
	} else if(g_socket.Connected) {
		if(StrEqual(arg, "game")) {
			StartPayload();
			AddGameRecord();
			SendPayload();
		} else if(StrEqual(arg, "players")) {
			SendPlayers();
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
	if(StartPayload()) {
		AddGameRecord();
		SendPayload();
	}
}
void Event_GameEnd(Event event, const char[] name, bool dontBroadcast) {
	campaignStartTime = 0;
}

void Event_MapTransition(Event event, const char[] name, bool dontBroadcast) {
	g_inTransition = true;
	if(StartPayload()) {
		AddGameRecord();
		SendPayload();
	}
}

void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(client > 0) {
		PrintToServer("death: %N", client);
		TriggerHealthUpdate(client, true);
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

void Event_PlayerFirstSpawn(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	playerJoinTime[client] = GetTime();
	RecalculatePlayerCount();
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
			StartPayload();
			AddPlayerRecord(i);
			SendPayload();
		}
	}
}

// public void OnPlayerRunCmdPost(int client, int buttons, int impulse, const float vel[3], const float angles[3], int weapon, int subtype, int cmdnum, int tickcount, int seed, const int mouse[2]) {
// 	float time = GetGameTime();
// 	// if(time - lastUpdateTime[client] > 7.0) {
// 	// 	if(StartPayload()) {
// 	// 		lastUpdateTime[client] = time;
// 	// 		AddSurvivorRecord(client);
// 	// 		SendPayload();
// 	// 	}
// 	// }
// }

public void OnMapStart() {
	GetCurrentMap(currentMap, sizeof(currentMap));
	numberOfPlayers = 0;
	if(lateLoaded) {
		StartPayload();
		AddGameRecord();
		SendPayload();

		SendPlayers();
	}
}

public void OnConfigsExecuted() {
	isL4D1Survivors = L4D2_GetSurvivorSetMap() == 1;
}
// Player counts
public void OnClientPutInServer(int client) {
	if(g_inTransition) {
		g_inTransition = false;
		if(StartPayload()) {
			AddGameRecord();
			SendPayload();
		}
	}
	GetClientName(client, nameCache[client], MAX_NAME_LENGTH);
	if(!IsFakeClient(client)) {
		GetClientAuthId(client, AuthId_SteamID64, steamidCache[client], 32);
		numberOfPlayers++;
	} else {
		// Check if they are not a bot, such as ABMBot or EPIBot, etc
		char classname[32];
		GetEntityClassname(client, classname, sizeof(classname));
		if(StrContains(classname, "bot", false) > -1) {
			return;
		}
		strcopy(steamidCache[client], 32, "BOT");
	}
	SDKHook(client, SDKHook_WeaponEquipPost, OnWeaponPickUp);
	SDKHook(client, SDKHook_OnTakeDamageAlivePost, OnTakeDamagePost);
	// We wait a frame because Event_PlayerFirstSpawn sets their join time
	RequestFrame(SendNewClient, client);
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
	if(cvar_id == convar) {
		strcopy(serverId, sizeof(serverId), newValue);
		PrintToServer("[AdminPanel] Server ID changed to: %s", serverId);
	} else if(cvar_address == convar) {
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

enum LiveRecordType {
	Live_Game,
	Live_Player,
	Live_Survivor,
	Live_Infected,
	Live_Finale,
	Live_SurvivorItems,
	Live_CommandResponse,
	Live_Auth
}

enum LiveRecordResponse {
	Live_OK,
	Live_Reconnect,
	Live_Error,
	Live_Refresh,
	Live_RunComand
}

bool StartPayload() {
	if(!cvar_debug.BoolValue && (g_isPaused || numberOfPlayers == 0)) return false;
	sendBuffer.Reset();
	sendBuffer.WriteByte(LIVESTATUS_VERSION);
	sendBuffer.WriteString(serverId);
	return g_socket.Connected;
}

void StartRecord(LiveRecordType type) {
	sendBuffer.WriteChar('\x1e'); // record separator
	sendBuffer.WriteByte(view_as<int>(type));
}

void AddGameRecord() {
	PrintToServer("pushing Live_Game");
	StartRecord(Live_Game);
	sendBuffer.WriteInt(uptime);
	sendBuffer.WriteInt(campaignStartTime);
	sendBuffer.WriteByte(gameDifficulty);
	sendBuffer.WriteByte(g_inTransition);
	sendBuffer.WriteString(gamemode);
	sendBuffer.WriteString(currentMap);
}	

void AddFinaleRecord(int stage) {
	StartRecord(Live_Finale);
	sendBuffer.WriteByte(stage); // finale stage
	sendBuffer.WriteByte(L4D_IsFinaleEscapeInProgress()); // escape or not
}

void AddPlayerRecord(int client, bool connected = true) {
	// fake bots are ignored:

	int originalClient = client;
	bool isIdle = false;
	if(connected) {
		// If this is an idle player's bot, then we use the real player's info instead.
		if(IsFakeClient(client)) {
			int realPlayer = L4D_GetIdlePlayerOfBot(client);
			if(realPlayer > 0) {
				PrintToServer("%d is idle bot of %N", client, realPlayer);
				isIdle = true;
				client = realPlayer;
			} else if(steamidCache[client][0] == '\0') {
				PrintToServer("skipping %N %s", client, steamidCache[client]);
				return;
			}
		}
	}
	StartRecord(Live_Player);
	sendBuffer.WriteInt(GetClientUserId(client));
	sendBuffer.WriteString(steamidCache[client]);
	if(connected) {
		sendBuffer.WriteByte(isIdle);
		sendBuffer.WriteInt(playerJoinTime[client]);
		sendBuffer.WriteString(nameCache[client]);

		if(GetClientTeam(originalClient) == 2) {
			AddSurvivorRecord(originalClient, client);
			AddSurvivorItemsRecord(originalClient, client);
		} else if(GetClientTeam(client) == 3) {
			AddInfectedRecord(client);
		}
	}
}

void AddSurvivorRecord(int client, int forClient = 0) {
	if(forClient == 0) forClient = client;
	int survivor = GetEntProp(client, Prop_Send, "m_survivorCharacter");
	// The icons are mapped for survivors as 4,5,6,7; so inc to that for L4D1 survivors
	if(isL4D1Survivors) {
		survivor += 4; 
	}
	if(survivor >= 8) return;
	StartRecord(Live_Survivor);
	sendBuffer.WriteInt(GetClientUserId(forClient));
	sendBuffer.WriteByte(survivor);
	sendBuffer.WriteByte(L4D_GetPlayerTempHealth(client)); //temp health
	sendBuffer.WriteByte(GetEntProp(client, Prop_Send, "m_iHealth")); //perm health
	sendBuffer.WriteByte(L4D2_GetVersusCompletionPlayer(client)); // flow%
	sendBuffer.WriteInt(GetPlayerStates(client)); // state (incl. alive)
	sendBuffer.WriteInt(GetPlayerMovement(client)); // move
	sendBuffer.WriteInt(GetAction(client)); // action
}
void AddSurvivorItemsRecord(int client, int forClient = 0) {
	if(forClient == 0) forClient = client;
	StartRecord(Live_SurvivorItems);
	sendBuffer.WriteInt(GetClientUserId(client));
	char name[32];
	for(int slot = 0; slot < 6; slot++) {
		name[0] = '\0';
		GetClientWeaponNameSmart2(client, slot, name, sizeof(name));
		sendBuffer.WriteString(name);
	}
}
void AddInfectedRecord(int client) {
	StartRecord(Live_Infected);
	sendBuffer.WriteInt(GetClientUserId(client));
	sendBuffer.WriteShort(GetEntProp(client, Prop_Send, "m_iHealth")); //cur health
	sendBuffer.WriteShort(GetEntProp(client, Prop_Send, "m_iMaxHealth")); //max health
	sendBuffer.WriteByte(L4D2_GetPlayerZombieClass(client)); // class
	int victim = L4D2_GetSurvivorVictim(client);
	if(victim > 0)
		sendBuffer.WriteInt(GetClientUserId(victim));
	else
		sendBuffer.WriteInt(0);
}

void SendPayload() {
	sendBuffer.Finish();
	if(cvar_debug.BoolValue)
		PrintToServer("[AdminPanel] Sending %d bytes of data", sendBuffer.offset);
	g_socket.Send(sendBuffer.buffer, sendBuffer.offset);
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

	void WriteShort(int value) {
		this.buffer[this.offset++] = value & 0xFF;
		this.buffer[this.offset++] = (value >> 8) & 0xFF;
	}

	void WriteInt(int value, int bytes = 4) {
		this.buffer[this.offset++] = value & 0xFF;
		this.buffer[this.offset++] = (value >> 8) & 0xFF;
		this.buffer[this.offset++] = (value >> 16) & 0xFF;
		this.buffer[this.offset++] = (value >> 24) & 0xFF;
	}

	void WriteFloat(float value) {
		this.WriteInt(view_as<int>(value));
	}

	/// Writes a variable-width string, with the size being prepended. Only supports strings up to 2^15 in size
	/// @param lenHint - optional, but the length of the string, to avoid strlen() twice
	void WriteVarString(const char[] string, int lenHint = -1) {
		if(lenHint < 0) lenHint = strlen(string);
		this.WriteShort(lenHint);
		// null term written will just get overwritten
		strcopy(this.buffer[this.offset], BUFFER_SIZE, string);
		this.offset += lenHint;
	}

	// Writes a null-terminated length string, strlen > size is truncated.
	void WriteString(const char[] string) {
		int written = strcopy(this.buffer[this.offset], BUFFER_SIZE, string);
		this.offset += written + 1;
	}

	void Finish() {
		// Set newline
		this.buffer[this.offset++] = '\n';
	}

	int ReadByte() {
		return this.buffer[this.offset++] & 0xFF;
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
}