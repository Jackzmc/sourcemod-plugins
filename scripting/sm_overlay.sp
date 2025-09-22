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
#include <socket>

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

enum outRequest {
	Request_PlayerJoin,
	Request_PlayerLeft,
	Request_GameState,
	Request_RequestElement,
	Request_UpdateElement,
	Request_UpdateAudioState,

	Request_Invalid
}
char OUT_REQUEST_IDS[view_as<int>(Request_Invalid)][] = {
	"player_joined",
	"player_left",
	"game_state",
	"request_element",
	"update_element",
	"change_audio_state"
};
char steamidCache[MAXPLAYERS+1][32];

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
	RegPluginLibrary("overlay");

	CreateNative("IsOverlayConnected", Native_IsOverlayConnected);
	CreateNative("RegisterActionAnyHandler", Native_ActionHandler);
	CreateNative("RegisterActionHandler", Native_ActionHandler);

	CreateNative("FindClientBySteamId2", Native_FindClientBySteamId2);
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

	cvarManagerUrl = CreateConVar("sm_overlay_manager_url", "ws://100.92.116.2:3011/socket", "");
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

/*
every request:

POST http://manager/server/auth with token and server info
{ "token": "<AUTH TOKEN>", "info": { "name": "My Server" }}
-> 
200 OK { "session_token": "..." }

IF no request in timeout the server can be timed out, and token expires? have it auto renew? idk


POST http://manager/req with JSON body AND headers `Authentication
{ "type": "player_join", ... }

 */

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
			Send_PlayerJoined(steamidCache[i]);
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
	} else if(StrEqual(arg, "players")) {
		SendAllPlayers();
	} else if(StrEqual(arg, "test")) {
		SendAllPlayers();

		JSONObject state = new JSONObject();
		state.SetString("test", "yes");
		Element elem = new Element("overlay:test", "overlay:generic_text", state, new ElementOptions());
		elem.SetTarget(client);
		elem.SendRequest();
		// TODO: server can send: steamids[], steamid, or none (manager knows who was connected)

		// JSONObject temp = new JSONObject();
		// temp.SetString("type", "text");
		// temp.SetString("text", "Blah blah blah");
		// JSONObject defaults = new JSONObject();
		// defaults.SetString("title", "Test Element");
		// JSONObject pos = new JSONObject();
		// pos.SetInt("x", 200);
		// pos.SetInt("y", 200);
		// defaults.Set("pos", pos);
		// temp.Set("defaults", defaults);
		// bool result = SendEvent_RegisterTempUI("temp", 180, temp);
		// ReplyToCommand(client, result ? "Sent" : "Error");
	} else if(StrEqual(arg, "trigger_login")) {
		for(int i = 1; i <= MaxClients; i++) {
			if(IsClientInGame(i) && !IsFakeClient(i)) {
				GetClientAuthId(i, AuthId_Steam2, steamidCache[i], 32);
				Send_PlayerJoined(steamidCache[i]);
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
		Send_PlayerJoined(steamidCache[client]);
	}
}

void Event_PlayerDisconnect(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(client > 0 && !IsFakeClient(client)) {
		Send_PlayerLeft(steamidCache[client]);
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
	ClientAction action;
	obj.GetString("steamid", action.steamid, sizeof(action.steamid));
	obj.GetString("namespace", action.ns, sizeof(action.ns));
	obj.GetString("instance_id", action.instanceId, sizeof(action.instanceId));
	obj.GetString("command", action.command, sizeof(action.command));
	if(obj.HasKey("input"))
		obj.GetString("input", action.input, sizeof(action.input));

	int client = FindClientBySteamId2(action.steamid);
	if(client <= 0) return;

	StringMap nsHandler;
	PrivateForward fwd;
	if(!actionNamespaceHandlers.GetValue(action.ns, nsHandler) || !nsHandler.GetValue(action.command, fwd)) {
		if(!actionFallbackHandlers.GetValue(action.ns, fwd)) {
			// No handler or catch all namespace handler
			PrintToServer("[Overlay] Warn: No handler found for action \"%s:%s\"", action.ns, action.command);
			return;
		}
	}

	ArrayList args = new ArrayList(ACTION_ARG_LENGTH);
	args.PushString(action.input);
	ExplodeStringToArrayList(action.input, " ", args, ACTION_ARG_LENGTH);
	UIActionEvent event = UIActionEvent(args);

	Call_StartForward(fwd);
	Call_PushCell(event);
	Call_PushCell(client);
	Call_Finish();

	if(StrEqual(action.ns, "game")) {
		if(CheckCommandAccess(client, action.command, 0)) {
			FakeClientCommand(client, "%s %s", action.command, action.input);
		}
	}
	event._Delete();
}
int _FindClientBySteamId2(const char[] steamid) {
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

bool Send_PlayerJoined(const char[] steamid) {
	if(!isManagerReady()) return false;
	JSONObject obj = new JSONObject();
	obj.SetString("type", OUT_REQUEST_IDS[Request_PlayerJoin]);
	obj.SetString("steamid", steamid);
	g_ws.Write(obj);
	obj.Clear();
	delete obj;
	return true;
}

bool Send_PlayerLeft(const char[] steamid) {
	if(!isManagerReady()) return false;
	JSONObject obj = new JSONObject();
	obj.SetString("type", OUT_REQUEST_IDS[Request_PlayerLeft]);
	obj.SetString("steamid", steamid);
	g_ws.Write(obj);
	obj.Clear();
	delete obj;
	return true;
}

methodmap Element < JSONObject {
	public Element(const char[] elemId, const char[] templateId, JSONObject state, ElementOptions options) {
		JSONObject obj = new JSONObject();
		obj.SetString("elem_id", elemId);
		obj.SetString("template_id", templateId);
		obj.Set("state", state);
		obj.Set("options", options);

		return view_as<Element>(obj);
	}

	public static Element CreateTemp(const char[] templateId, JSONObject state, ElementOptions options) {
		// TODO: make uuid later
		char id[32];
		Format(id, sizeof(id), "temp:%d%d%d%d", GetURandomInt(), GetURandomInt(), GetURandomInt(), GetURandomInt());
		return new Element(id, templateId, state, options);
	}

	property JSONObject InternalObj 
	{
		public get()
		{
			return view_as<JSONObject>(this);
		}
	}

	property JSONObject State
	{
		public get() {
			return view_as<JSONObject>(this.InternalObj.Get("state"));
		}
		public set(JSONObject newState) {
			this.InternalObj.Set("state", newState);
		}
	}

	// Set the target to a single steamid
	public void SetTargetSteamID(const char[] steamid) {
		this.InternalObj.SetString("target", steamid);
	}
	public void SetTarget(int client) {
		this.InternalObj.SetString("target", steamidCache[client]);
	}
	public void SetTargetSteamIDs(JSONArray list) {
		this.InternalObj.Set("target", list);
	}
	// Set the target to all online players
	public void SetTargetAll() {
		this.InternalObj.SetNull("target");
	}

	// Sends the initial request to create element
	public void SendRequest() {
		this.InternalObj.SetString("type", OUT_REQUEST_IDS[Request_RequestElement]);
		g_ws.Write(this.InternalObj);
	}
	// Sends an update request, updating just the state and options
	public void SendUpdate() {
		// TODO: update doesn't need template_id, delete?
		this.InternalObj.SetString("type", OUT_REQUEST_IDS[Request_UpdateElement]);
		g_ws.Write(this.InternalObj);
	}
}

methodmap ElementOptions < JSONObject {
	public ElementOptions() {
		JSONObject obj = new JSONObject();
		return view_as<ElementOptions>(obj);
	}

	property JSONObject InternalObj 
	{
		public get()
		{
			return view_as<JSONObject>(this);
		}
	}

	// property int ExampleOption {
	// 	public get() {
	// 	}
	// }
}

methodmap PlayerList < JSONArray {
}


//PlayAudio(int client, const char[] url);
any Native_PlayAudio(Handle plugin, int numParams) {
	if(!isManagerReady()) return false;

	char url[256];
	GetNativeString(1, url, sizeof(url));

	return false;
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


any Native_FindClientBySteamId2(Handle plugin, int numParams) {
	char steamid[32];
	GetNativeString(1, steamid, sizeof(steamid));
	return _FindClientBySteamId2(steamid);
}