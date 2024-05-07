#pragma semicolon 1
#pragma newdecls required

//#define DEBUG

#define PLUGIN_VERSION "1.0"
#define USER_AGENT "OverlayServer/v1.0.0"
#define MAX_ATTEMPT_TIMEOUT 120.0

#include <sourcemod>
#include <sdktools>
//#include <sdkhooks>
#include <ripext>

WebSocket g_ws;
ConVar cvarManagerUrl; char managerUrl[128];
ConVar cvarManagerToken; char authToken[512];
int connectAttempts;
authState g_authState;
JSONObject g_globalVars;

enum authState {
	AuthError = -1,
	NotAuthorized,
	Authorized,
}

public Plugin myinfo = 
{
	name =  "Overlay", 
	author = "jackzmc", 
	description = "", 
	version = PLUGIN_VERSION, 
	url = "https://github.com/Jackzmc/sourcemod-plugins"
};

enum outEvent {
	Event_PlayerJoin,
	Event_PlayerLeft,
	Event_GameState,
	Event_RegisterTempUI,
	Event_UpdateUI,
	Event_Invalid
}
char OUT_EVENT_IDS[view_as<int>(Event_Invalid)][] = {
	"player_joined",
	"player_left",
	"game_state",
	"register_temp_ui",
	"update_ui"
};
char steamidCache[MAXPLAYERS+1][32];

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
	CreateNative("UIElement.Send", Native_UpdateUI);
	return APLRes_Success;
}

public void OnPluginStart() {
	EngineVersion g_Game = GetEngineVersion();
	if(g_Game != Engine_Left4Dead && g_Game != Engine_Left4Dead2) {
		SetFailState("This plugin is for L4D/L4D2 only.");	
	}

	g_globalVars = new JSONObject();

	cvarManagerUrl = CreateConVar("sm_overlay_manager_url", "ws://localhost:3011/socket", "");
	cvarManagerUrl.AddChangeHook(OnUrlChanged);
	OnUrlChanged(cvarManagerUrl, "", "");

	cvarManagerToken = CreateConVar("sm_overlay_manager_token", "", "The auth token for this server");
	cvarManagerToken.AddChangeHook(OnTokenChanged);
	OnTokenChanged(cvarManagerToken, "", "");

	HookEvent("player_disconnect", Event_PlayerDisconnect);

	RegAdminCmd("sm_overlay", Command_Overlay, ADMFLAG_GENERIC);

	AutoExecConfig(true);

	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientInGame(i) && !IsFakeClient(i)) {
			OnClientAuthorized(i, "");
		}
	}
}

public void OnPluginEnd() {
	if(g_ws != null) {
		g_ws.Close();
		delete g_ws;
	}
}

bool isManagerReady() {
	return g_ws != null && g_ws.WsOpen() && g_authState == Authorized;
}

void SendAllPlayers() {
	if(!isManagerReady) return;
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientInGame(i) && !IsFakeClient(i)) {
			SendEvent_PlayerJoined(steamidCache[i]);
		}
	}
}

Action Command_Overlay(int client, int args) {
	char arg[32];
	GetCmdArg(1, arg, sizeof(arg));
	if(StrEqual(arg, "info")) {
		ReplyToCommand(client, "URL: %s", managerUrl);
		ReplyToCommand(client, "Socket Connected: %b | WS Connected: %b", g_ws.SocketOpen(), g_ws.WsOpen());
		ReplyToCommand(client, "Auth State: %d", g_authState);
	} else if(StrEqual(arg, "test")) {
		SendAllPlayers();

		JSONObject temp = new JSONObject();
		temp.SetString("type", "text");
		temp.SetString("text", "Blah blah blah");
		JSONObject defaults = new JSONObject();
		defaults.SetString("title", "Test Element");
		JSONObject pos = new JSONObject();
		pos.SetInt("x", 200);
		pos.SetInt("y", 200);
		defaults.Set("pos", pos);
		temp.Set("defaults", defaults);
		SendEvent_RegisterTempUI("temp", 180, temp);
		ReplyToCommand(client, "Sent");
	} else if(StrEqual(arg, "connect")) {
		ConnectManager();	
	} else {
		ReplyToCommand(client, "Unknown arg");
	}
	return Plugin_Handled;
}

void OnUrlChanged(ConVar cvar, const char[] oldValue, const char[] newValue) {
	cvarManagerUrl.GetString(managerUrl, sizeof(managerUrl));
	if(g_ws != null) {
		DisconnectManager();
		delete g_ws;
	}
	g_ws = new WebSocket(managerUrl);
	g_ws.SetHeader("User-Agent", USER_AGENT);
	g_ws.SetConnectCallback(OnWSConnect);
	g_ws.SetDisconnectCallback(OnWSDisconnect);
	g_ws.SetReadCallback(WebSocket_JSON, OnWSJson);
	PrintToServer("[Overlay] Changed url to: %s", managerUrl);
}
void OnTokenChanged(ConVar cvar, const char[] oldValue, const char[] newValue) {
	cvarManagerToken.GetString(authToken, sizeof(authToken));
}

public void OnClientAuthorized(int client, const char[] auth) {
	if(!g_ws.SocketOpen())
		ConnectManager();
	if(!IsFakeClient(client)) {
		GetClientAuthId(client, AuthId_Steam2, steamidCache[client], 32);
		SendEvent_PlayerJoined(steamidCache[client]);
	}
}

void Event_PlayerDisconnect(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(client > 0 && !IsFakeClient(client)) {
		SendEvent_PlayerLeft(steamidCache[client]);
	}
	if(GetClientCount(false) == 0) {
		DisconnectManager();
	}
}

void OnWSConnect(WebSocket ws, any arg) {
	connectAttempts = 0;
	g_authState = NotAuthorized;
	PrintToServer("[Overlay] Connected, authenticating");
	JSONObject obj = new JSONObject();
	obj.SetString("type", "server");
	obj.SetString("auth_token", authToken);
	ws.Write(obj);
	delete obj;
}

void OnWSDisconnect(WebSocket ws, int attempt) {
	if(g_authState == AuthError) {
		return;
	}
	connectAttempts++;
	float nextAttempt = Exponential(float(connectAttempts) / 2.0) + 2.0;
	if(nextAttempt > MAX_ATTEMPT_TIMEOUT) nextAttempt = MAX_ATTEMPT_TIMEOUT;
	PrintToServer("[Overlay] Disconnected, retrying in %.0f seconds", nextAttempt);
	CreateTimer(nextAttempt, Timer_Reconnect);
}

Action Timer_Reconnect(Handle h) {
	ConnectManager();
	return Plugin_Handled;
}

void OnWSJson(WebSocket ws, JSON message, any data) {
	JSONObject obj = view_as<JSONObject>(message);
	if(obj.HasKey("error")) {
		if(g_authState == NotAuthorized) {
			g_authState = AuthError;
		}
		char buffer[2048];
		message.ToString(buffer, sizeof(buffer));
		PrintToServer("[Overlay] Error: %s", buffer);
	} else {
		char buffer[2048];
		message.ToString(buffer, sizeof(buffer));
		PrintToServer("[Overlay] Got JSON: %s", buffer);
	}
}


void ConnectManager() {
	DisconnectManager();
	if(authToken[0] == '\0') return;

	PrintToServer("[Overlay] Connecting to \"%s\"", managerUrl);
	if(g_ws.Connect()) {
		PrintToServer("[Overlay] Connected");
	}
}

void DisconnectManager() {
	if(g_ws.WsOpen()) {
		g_ws.Close();
	}
}

void SendEvent_PlayerJoined(const char[] steamid) {
	if(!isManagerReady()) return;
	JSONObject obj = new JSONObject();
	obj.SetString("type", OUT_EVENT_IDS[Event_PlayerJoin]);
	obj.SetString("steamid", steamid);
	g_ws.Write(obj);
	obj.Clear();
	delete obj;
}

void SendEvent_PlayerLeft(const char[] steamid) {
	if(!isManagerReady()) return;
	JSONObject obj = new JSONObject();
	obj.SetString("type", OUT_EVENT_IDS[Event_PlayerLeft]);
	obj.SetString("steamid", steamid);
	g_ws.Write(obj);
	obj.Clear();
	delete obj;
}

void SendEvent_RegisterTempUI(const char[] elemId, int expiresSeconds = 0, JSONObject element) {
	if(!isManagerReady()) return;
	JSONObject obj = new JSONObject();
	obj.SetString("type", OUT_EVENT_IDS[Event_RegisterTempUI]);
	obj.SetString("elem_id", elemId);
	if(expiresSeconds > 0)
		obj.SetInt("expires_seconds", expiresSeconds);
	obj.Set("element", element);
	g_ws.Write(obj);
	obj.Clear();
	delete obj;
}

// namespace optional
void SendEvent_UpdateUI(const char[] elemNamespace, const char[] elemId, bool visibility, JSONObject variables) {
	if(!isManagerReady()) return;
	JSONObject obj = new JSONObject();
	if(elemNamespace[0] != '\0')
		obj.SetString("namespace", elemNamespace);
	obj.SetString("elem_id", elemId);
	obj.SetBool("visibility", visibility);
	obj.Set("variables", variables);
	g_ws.Write(obj);
	obj.Clear();
	delete obj;
}

//SendTempUI(int client, const char[] id, int lifetime, JSONObject element);
bool Native_SendTempUI(Handle plugin, int numParams) {
	if(!isManagerReady()) return false;

	int client = GetNativeCell(1);
	if(steamidCache[client][0] == '\0') return false;

	char id[64];
	GetNativeString(2, id, sizeof(id));

	int lifetime = GetNativeCell(3);

	JSONObject obj = GetNativeCell(4);

	SendEvent_RegisterTempUI(id, lifetime, obj);
	return true;
}

//ShowUI(int client, const char[] elemNamespace, const char[] elemId, JSONObject variables);
bool Native_ShowUI(Handle plugin, int numParams) {
	if(!isManagerReady()) return false;

	char elemNamespace[64], id[64];
	GetNativeString(1, elemNamespace, sizeof(elemNamespace));
	GetNativeString(2, id, sizeof(id));

	JSONObject variables = GetNativeCell(3);

	SendEvent_UpdateUI(elemNamespace, id, true, variables);
	return true;
}

//HideUI(int client, const char[] elemNamespace, const char[] elemId);
bool Native_HideUI(Handle plugin, int numParams) {
	if(!isManagerReady()) return false;

	char elemNamespace[64], id[64];
	GetNativeString(1, elemNamespace, sizeof(elemNamespace));
	GetNativeString(2, id, sizeof(id));

	SendEvent_UpdateUI(elemNamespace, id, false, null);
	return true;
}

//PlayAudio(int client, const char[] url);
bool Native_PlayAudio(Handle plugin, int numParams) {
	if(!isManagerReady()) return false;

	char url[256];
	GetNativeString(1, url, sizeof(url));

	return false;
	return true;
}

bool Native_UpdateUI(Handle plugin, int numParams) {
	if(!isManagerReady()) return false;

	UIElement elem = view_as<UIElement>(GetNativeCell(1));

	g_ws.Write(view_as<JSON>(elem));

	return true;
}

//IsOverlayConnected();
bool Native_IsOverlayConnected(Handle plugin, int numParams) {
	return isManagerReady();
}

void OnUIAction(const char[] elemNamespace, const char[] elemId, const char[] action);