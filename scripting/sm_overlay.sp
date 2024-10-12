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
#include <overlay>

WebSocket g_ws;
ConVar cvarManagerUrl; char managerUrl[128];
ConVar cvarManagerToken; char authToken[512];
int connectAttempts;
authState g_authState;
JSONObject g_globalVars;

StringMap actionFallbackHandlers; // namespace -> action name has no handler, falls to this.
StringMap actionNamespaceHandlers; // { namespace: { [action name] -> handler } }

enum authState {
	Auth_Error = -1,
	Auth_None,
	Auth_Success,
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
	RegPluginLibrary("overlay");

	CreateNative("IsOverlayConnected", Native_IsOverlayConnected);
	CreateNative("RegisterActionAnyHandler", Native_ActionHandler);
	CreateNative("RegisterActionHandler", Native_ActionHandler);

	CreateNative("UIElement.SendAll", Native_UpdateUI);
	CreateNative("UIElement.SendTo", Native_UpdateUI);
	CreateNative("TempUI.SendAll", Native_UpdateTempUI);
	CreateNative("TempUI.SendTo", Native_UpdateTempUI);
	return APLRes_Success;
}

public void OnPluginStart() {
	EngineVersion g_Game = GetEngineVersion();
	if(g_Game != Engine_Left4Dead && g_Game != Engine_Left4Dead2) {
		SetFailState("This plugin is for L4D/L4D2 only.");	
	}

	actionFallbackHandlers = new StringMap();
	actionNamespaceHandlers = new StringMap();

	g_globalVars = new JSONObject();

	cvarManagerUrl = CreateConVar("sm_overlay_manager_url", "ws://desktop:3011/socket", "");
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
	return g_ws != null && g_ws.WsOpen() && g_authState == Auth_Success;
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
		bool result = SendEvent_RegisterTempUI("temp", 180, temp);
		ReplyToCommand(client, result ? "Sent" : "Error");
	} else if(StrEqual(arg, "trigger_login")) {
		for(int i = 1; i <= MaxClients; i++) {
			if(IsClientInGame(i) && !IsFakeClient(i)) {
				GetClientAuthId(i, AuthId_Steam2, steamidCache[i], 32);
				SendEvent_PlayerJoined(steamidCache[i]);
			}
		}	
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
	steamidCache[client][0] = '\0';
}

void OnWSConnect(WebSocket ws, any arg) {
	connectAttempts = 0;
	g_authState = Auth_None;
	PrintToServer("[Overlay] Connected, authenticating");
	JSONObject obj = new JSONObject();
	obj.SetString("type", "server");
	obj.SetString("auth_token", authToken);
	ws.Write(obj);
	delete obj;
}

void OnWSDisconnect(WebSocket ws, int attempt) {
	if(g_authState == Auth_Error) {
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
	if(g_authState == Auth_None) {
		if(obj.HasKey("error")) {
			g_authState = Auth_Error;
			char buffer[2048];
			message.ToString(buffer, sizeof(buffer));
			PrintToServer("[Overlay] Auth Failure: %s", buffer);
			DisconnectManager();
		} else if(obj.HasKey("type")) {
			char buffer[128];
			obj.GetString("type", buffer, sizeof(buffer));
			PrintToServer("[Overlay::Debug] Auth: %s", buffer);
			if(StrEqual(buffer, "authorized")) {
				g_authState = Auth_Success;
			}
		}
	} else if(obj.HasKey("error")) {
		char buffer[2048];
		message.ToString(buffer, sizeof(buffer));
		PrintToServer("[Overlay] Error: %s", buffer);
	} else {
		char type[32];
		obj.GetString("type", type, sizeof(type));
		if(StrEqual(type, "action")) {
			OnAction(obj);
		}

		char buffer[2048];
		message.ToString(buffer, sizeof(buffer));
		PrintToServer("[Overlay] Got JSON: %s", buffer);
	}
}

stock int ExplodeStringToArrayList(const char[] text, const char[] split, ArrayList buffers, int maxStringLength) {
	int reloc_idx, idx, total;
	
	if (buffers == null || !split[0]) {
		return 0;
	}
	
	char[] item = new char[maxStringLength];
	while ((idx = SplitString(text[reloc_idx], split, item, maxStringLength)) != -1) {
		reloc_idx += idx;
		++total;
		buffers.PushString(item);
	}
	++total;
	buffers.PushString(text[reloc_idx]);
	
	return buffers.Length;
}

void OnAction(JSONObject obj) {
	char steamid[32];
	obj.GetString("steamid", steamid, sizeof(steamid));
	char ns[64];
	obj.GetString("namespace", ns, sizeof(ns));
	char id[64];
	obj.GetString("elem_id", id, sizeof(id));
	char action[256];
	obj.GetString("action", action, sizeof(action));

	int client = FindClientBySteamId2(steamid);

	StringMap nsHandler;
	PrivateForward fwd;
	if(!actionNamespaceHandlers.GetValue(ns, nsHandler) || !nsHandler.GetValue(id, fwd)) {
		if(!actionFallbackHandlers.GetValue(ns, fwd)) {
			// No handler or catch all namespace handler
			return;
		}
	}

	ArrayList args = new ArrayList(ACTION_ARG_LENGTH);
	ExplodeStringToArrayList(action, " ", args, ACTION_ARG_LENGTH);
	UIActionEvent event = UIActionEvent(args);

	Call_StartForward(fwd);
	Call_PushCell(event);
	Call_PushCell(client);
	Call_Finish();
	event._Delete();
}

int FindClientBySteamId2(const char[] steamid) {
	for(int i = 1; i <= MaxClients; i++) {
		if(StrEqual(steamidCache[i], steamid)) {
			return i;
		}
	}
	return -1;
}


bool ConnectManager() {
	DisconnectManager();
	if(authToken[0] == '\0') return false;

	PrintToServer("[Overlay] Connecting to \"%s\"", managerUrl);
	if(g_ws.Connect()) {
		PrintToServer("[Overlay] Connected");
		return true;
	}
	return false;
}

void DisconnectManager() {
	if(g_ws.WsOpen()) {
		g_ws.Close();
	}
}

bool SendEvent_PlayerJoined(const char[] steamid) {
	if(!isManagerReady()) return false;
	JSONObject obj = new JSONObject();
	obj.SetString("type", OUT_EVENT_IDS[Event_PlayerJoin]);
	obj.SetString("steamid", steamid);
	g_ws.Write(obj);
	obj.Clear();
	delete obj;
	return true;
}

bool SendEvent_PlayerLeft(const char[] steamid) {
	if(!isManagerReady()) return false;
	JSONObject obj = new JSONObject();
	obj.SetString("type", OUT_EVENT_IDS[Event_PlayerLeft]);
	obj.SetString("steamid", steamid);
	g_ws.Write(obj);
	obj.Clear();
	delete obj;
	return true;
}

bool SendEvent_RegisterTempUI(const char[] elemId, int expiresSeconds = 0, JSONObject element) {
	if(!isManagerReady()) return false;
	JSONObject obj = new JSONObject();
	obj.SetString("type", OUT_EVENT_IDS[Event_RegisterTempUI]);
	obj.SetString("elem_id", elemId);
	if(expiresSeconds > 0)
		obj.SetInt("expires_seconds", expiresSeconds);
	obj.Set("element", element);
	g_ws.Write(obj);
	obj.Clear();
	delete obj;
	return true;
}

methodmap PlayerList < JSONArray {
}

// namespace optional
bool SendEvent_UpdateUI(const char[] elemNamespace, const char[] elemId, bool visibility, JSONObject variables) {
	if(!isManagerReady()) return false;
	JSONObject obj = new JSONObject();
	if(elemNamespace[0] != '\0')
		obj.SetString("namespace", elemNamespace);
	obj.SetString("elem_id", elemId);
	obj.SetBool("visibility", visibility);
	obj.Set("variables", variables);
	g_ws.Write(obj);
	obj.Clear();
	delete obj;
	return true;
}

//SendTempUI(int client, const char[] id, int lifetime, JSONObject element);
any Native_SendTempUI(Handle plugin, int numParams) {
	if(!isManagerReady()) return false;

	int client = GetNativeCell(1);
	if (client <= 0 || client > MaxClients) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d)", client);
	} else if (!IsClientConnected(client) || steamidCache[client][0] == '\0') {
		return ThrowNativeError(SP_ERROR_NATIVE, "Client %d is not connected/authorized yet", client);
	}

	char id[64];
	GetNativeString(2, id, sizeof(id));

	int lifetime = GetNativeCell(3);

	JSONObject obj = GetNativeCell(4);

	SendEvent_RegisterTempUI(id, lifetime, obj);
	return true;
}

//ShowUI(int client, const char[] elemNamespace, const char[] elemId, JSONObject variables);
any Native_ShowUI(Handle plugin, int numParams) {
	if(!isManagerReady()) return false;

	char elemNamespace[64], id[64];
	GetNativeString(1, elemNamespace, sizeof(elemNamespace));
	GetNativeString(2, id, sizeof(id));

	JSONObject variables = GetNativeCell(3);

	SendEvent_UpdateUI(elemNamespace, id, true, variables);
	return true;
}

//HideUI(int client, const char[] elemNamespace, const char[] elemId);
any Native_HideUI(Handle plugin, int numParams) {
	if(!isManagerReady()) return false;

	char elemNamespace[64], id[64];
	GetNativeString(1, elemNamespace, sizeof(elemNamespace));
	GetNativeString(2, id, sizeof(id));

	SendEvent_UpdateUI(elemNamespace, id, false, null);
	return true;
}

//PlayAudio(int client, const char[] url);
any Native_PlayAudio(Handle plugin, int numParams) {
	if(!isManagerReady()) return false;

	char url[256];
	GetNativeString(1, url, sizeof(url));

	return false;
	return true;
}

any Native_UpdateUI(Handle plugin, int numParams) {
	if(!isManagerReady()) return false;

	UIElement elem = GetNativeCell(1);
	JSONObject obj = view_as<JSONObject>(elem);

	JSONArray arr = view_as<JSONArray>(obj.Get("steamids"));
	if(numParams == 0) {
		arr.Clear();
	} else if(numParams == 1) {
		int client = GetNativeCell(2);
		if (client <= 0 || client > MaxClients) {
			return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d)", client);
		} else if (!IsClientConnected(client) || steamidCache[client][0] == '\0') {
			return ThrowNativeError(SP_ERROR_NATIVE, "Client %d is not connected/authorized yet", client);
		}
		arr.PushString(steamidCache[client]);
	}

	g_ws.Write(view_as<JSON>(elem));
	arr.Clear();

	return true;
}

any Native_UpdateTempUI(Handle plugin, int numParams) {
	if(!isManagerReady()) return false;

	TempUI elem = GetNativeCell(1);
	JSONObject obj = view_as<JSONObject>(elem);

	JSONArray arr = view_as<JSONArray>(obj.Get("steamids"));
	if(numParams == 0) {
		arr.Clear();
	} else if(numParams == 1) {
		int client = GetNativeCell(2);
		if (client <= 0 || client > MaxClients) {
			return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d)", client);
		} else if (!IsClientConnected(client) || steamidCache[client][0] == '\0') {
			return ThrowNativeError(SP_ERROR_NATIVE, "Client %d is not connected/authorized yet", client);
		}
		arr.PushString(steamidCache[client]);
	}

	g_ws.Write(view_as<JSON>(elem));
	arr.Clear();

	return true;
}

//IsOverlayConnected();
any Native_IsOverlayConnected(Handle plugin, int numParams) {
	return isManagerReady();
}

//RegisterActionHandler
//RegisterActionAnyHandler
any Native_ActionHandler(Handle plugin, int numParams) {
	char ns[64];
	GetNativeString(1, ns, sizeof(ns));

	if(numParams == 3) {
		// RegisterActionHandler
		StringMap nsHandlers;
		if(!actionNamespaceHandlers.GetValue(ns, nsHandlers)) {
			nsHandlers = new StringMap();
		}

		char actionId[64];
		GetNativeString(2, actionId, sizeof(actionId));

		PrivateForward fwd;
		if(!nsHandlers.GetValue(actionId, fwd)) {
			fwd = new PrivateForward(ET_Ignore, Param_Cell);
		}
		fwd.AddFunction(INVALID_HANDLE, GetNativeFunction(3));
		nsHandlers.SetValue(actionId, fwd);
	} else {
		// RegisterActionAnyHandler

		PrivateForward fwd;
		if(!actionFallbackHandlers.GetValue(ns, fwd)) {
			fwd = new PrivateForward(ET_Ignore, Param_Cell);
		}
		fwd.AddFunction(INVALID_HANDLE, GetNativeFunction(2));
		actionFallbackHandlers.SetValue(ns, fwd);
	}
	return 1;
}