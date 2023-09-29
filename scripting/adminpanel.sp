#pragma semicolon 1

#define DEBUG

// Update intervals (only sends when > 0 players)
// The update interval when there are active viewers
#define UPDATE_INTERVAL 5.0
// The update interval when there are no viewers on.
// We still need to poll to know how many viewers are watching
#define UPDATE_INTERVAL_SLOW 20.0

#include <sourcemod>
#include <sdktools>
#include <ripext>
#include <left4dhooks>
#include <multicolors>
#include <jutils>

#pragma newdecls required

public Plugin myinfo = 
{
	name = "Admin Panel",
	author = "Jackz",
	description = "Plugin to integrate with admin panel",
	version = "1.0.0",
	url = "https://github.com/jackzmc/l4d2-admin-dash"
};

ConVar cvar_debug;
ConVar cvar_postAddress; char postAddress[128];
ConVar cvar_authKey; char authKey[512];
ConVar cvar_gamemode; char gamemode[32];

char currentMap[64];
int numberOfPlayers = 0;
int lastSuccessTime;
int campaignStartTime;
int lastErrorCode;
int uptime;
bool fastUpdateMode = false;

Handle updateTimer = null;

char steamidCache[MAXPLAYERS+1][32];
char nameCache[MAXPLAYERS+1][MAX_NAME_LENGTH];
int g_icBeingHealed[MAXPLAYERS+1];
int playerJoinTime[MAXPLAYERS+1];


public void OnPluginStart()
{
	uptime = GetTime();
	cvar_debug = CreateConVar("sm_adminpanel_debug", "0", "Turn on debug mode", FCVAR_DONTRECORD, true, 0.0, true, 1.0);

	cvar_postAddress = CreateConVar("sm_adminpanel_url", "", "The base address to post updates to", FCVAR_NONE);
	cvar_postAddress.AddChangeHook(OnCvarChanged);
	cvar_postAddress.GetString(postAddress, sizeof(postAddress));
	cvar_authKey = CreateConVar("sm_adminpanel_key", "", "The authentication key", FCVAR_NONE);
	cvar_authKey.AddChangeHook(OnCvarChanged);
	cvar_authKey.GetString(authKey, sizeof(authKey));

	cvar_gamemode = FindConVar("mp_gamemode");
	cvar_gamemode.AddChangeHook(OnCvarChanged);
	cvar_gamemode.GetString(gamemode, sizeof(gamemode));

	HookEvent("game_init", Event_GameStart);
	HookEvent("heal_success", Event_HealStop);
	HookEvent("heal_interrupted", Event_HealStop);
	HookEvent("player_first_spawn", Event_PlayerFirstSpawn);

	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i)) {
			OnClientPutInServer(i);
		}
	}

	TryStartTimer(true);

	AutoExecConfig(true, "adminpanel");

	RegAdminCmd("sm_panel_status", Command_PanelStatus, ADMFLAG_GENERIC);

}

#define DATE_FORMAT "%F at %I:%M %p"
Action Command_PanelStatus(int client, int args) {
	ReplyToCommand(client, "Active: %b", updateTimer != null);
	ReplyToCommand(client, "#Players: %d", numberOfPlayers);
	ReplyToCommand(client, "Update Interval: %0f s", fastUpdateMode ? UPDATE_INTERVAL : UPDATE_INTERVAL_SLOW);
	char buffer[32];
	ReplyToCommand(client, "Last Error Code: %d", lastErrorCode);
	if(lastSuccessTime > 0)
		FormatTime(buffer, sizeof(buffer), DATE_FORMAT, lastSuccessTime);
	else
		Format(buffer, sizeof(buffer), "(none)");
	ReplyToCommand(client, "Last Success: %s", buffer);
	return Plugin_Handled;
}

void TryStartTimer(bool fast = true) {
	if(numberOfPlayers > 0 && updateTimer == null && postAddress[0] != '\0' && authKey[0] != 0) {
		fastUpdateMode = fast;
		float interval = fast ? UPDATE_INTERVAL : UPDATE_INTERVAL_SLOW;
		updateTimer = CreateTimer(interval, Timer_PostStatus, _, TIMER_REPEAT);
		PrintToServer("[AdminPanel] Updating every %.1f seconds", interval);
	}
}


void Event_GameStart(Event event, const char[] name, bool dontBroadcast) {
	campaignStartTime = GetTime();
}

void Event_HealStart(Event event, const char[] name, bool dontBroadcast) {
	int healing = GetClientOfUserId(event.GetInt("subject"));
	g_icBeingHealed[healing] = true;
}
void Event_HealStop(Event event, const char[] name, bool dontBroadcast) {
	int healing = GetClientOfUserId(event.GetInt("subject"));
	g_icBeingHealed[healing] = false;
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

public void OnMapStart() {
	GetCurrentMap(currentMap, sizeof(currentMap));
	numberOfPlayers = 0;
}

// Player counts
public void OnClientPutInServer(int client) {
	GetClientName(client, nameCache[client], MAX_NAME_LENGTH);
	if(!IsFakeClient(client)) {
		GetClientAuthId(client, AuthId_SteamID64, steamidCache[client], 32);
		numberOfPlayers++;
		TryStartTimer(true);
	} else {
		strcopy(steamidCache[client], 32, "BOT");
	}
}

public void OnClientDisconnect(int client) {
	steamidCache[client][0] = '\0';
	nameCache[client][0] = '\0';
	if(!IsFakeClient(client)) {
		numberOfPlayers--;
		// Incase somehow we lost track
		if(numberOfPlayers < 0) {
			numberOfPlayers = 0;
		}
		if(numberOfPlayers == 0 && updateTimer != null) {
			delete updateTimer;
		}
	}
}

// Cvar updates
void OnCvarChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
	if(cvar_postAddress == convar) {
		strcopy(postAddress, sizeof(postAddress), newValue);
		PrintToServer("[AdminPanel] Update Url has updated");
	} else if(cvar_authKey == convar) {
		strcopy(authKey, sizeof(authKey), newValue);
		PrintToServer("[AdminPanel] Auth key has been updated");
	} else if(cvar_gamemode == convar) {
		strcopy(gamemode, sizeof(gamemode), newValue);
	}
	TryStartTimer(true);
}

bool isSubmitting;
Action Timer_PostStatus(Handle h) {
	if(isSubmitting) return Plugin_Continue;
	isSubmitting = true;
	// TODO: optimize only if someone is requesting live
	HTTPRequest req = new HTTPRequest(postAddress);
	JSONObject obj = GetObject();
	req.SetHeader("x-authtoken", authKey);
	// req.AppendFormParam("playerCount", "%d", numberOfPlayers);
	// req.AppendFormParam("map", currentMap);
	if(cvar_debug.BoolValue) PrintToServer("[AdminPanel] Submitting");
	req.Post(obj, Callback_PostStatus);
	delete obj;
	// req.PostForm(Callback_PostStatus);
	return Plugin_Continue;
}

void Callback_PostStatus(HTTPResponse response, any value, const char[] error) {
	isSubmitting = false;
	if(response.Status == HTTPStatus_NoContent || response.Status == HTTPStatus_OK) {
		lastErrorCode = 0;
		lastSuccessTime = GetTime();
		if(cvar_debug.BoolValue)
			PrintToServer("[AdminPanel] Response: OK/204");
		// We have subscribers, kill timer and recreate it in fast mode (if not already):
		if(!fastUpdateMode) {
			PrintToServer("[AdminPanel] Switching to fast update interval for active viewers.");
			if(updateTimer != null)
				delete updateTimer;
			TryStartTimer(true);
		}
		
	} else if(response.Status == HTTPStatus_Gone) {
		lastErrorCode = 0;
		// We have no subscribers, kill timer and recreate it in slow mode (if not already):
		if(fastUpdateMode) {
			PrintToServer("[AdminPanel] Switching to slow update interval, no viewers");
			if(updateTimer != null)
				delete updateTimer;
			TryStartTimer(false);
		}
	} else {
		lastErrorCode = view_as<int>(response.Status);
		lastSuccessTime = 0;
		// TODO: backoff
		PrintToServer("[AdminPanel] Getting response: %d", response.Status);
		if(cvar_debug.BoolValue) {
			char buffer[64];
			JSONObject json = view_as<JSONObject>(response.Data);
			if(false && json.GetString("error", buffer, sizeof(buffer))) {
				PrintToServer("[AdminPanel] Got %d response from server: \"%s\"", view_as<int>(response.Status), buffer);
				json.GetString("message", buffer, sizeof(buffer));
				PrintToServer("[AdminPanel] Error message: \"%s\"", buffer);
			} else {
				PrintToServer("[AdminPanel] Got %d response from server: <unknown json>\n%s", view_as<int>(response.Status), error);
			}
		}
		if(response.Status == HTTPStatus_Unauthorized || response.Status == HTTPStatus_Forbidden) {
			PrintToServer("[AdminPanel] API Key seems to be invalid, killing timer.");
			if(updateTimer != null)
				delete updateTimer;
		}
	}
}

JSONObject GetObject() {
	JSONObject obj = new JSONObject();
	obj.SetInt("playerCount", numberOfPlayers);
	obj.SetString("map", currentMap);
	obj.SetString("gamemode", gamemode);
	obj.SetInt("startTime", uptime);
	obj.SetInt("commonsCount", L4D_GetCommonsCount());
	obj.SetFloat("fps", 1.0 / GetGameFrameTime());
	AddFinaleInfo(obj);
	JSONArray players = GetPlayers();
	obj.Set("players", players);
	delete players;
	obj.SetFloat("refreshInterval", UPDATE_INTERVAL);
	obj.SetInt("lastUpdateTime", GetTime());
	obj.SetInt("campaignStartTime", campaignStartTime);
	return obj;
}

void AddFinaleInfo(JSONObject parentObj) {
	if(L4D_IsMissionFinalMap()) {
		JSONObject obj = new JSONObject();
		obj.SetBool("escapeLeaving", L4D_IsFinaleEscapeInProgress());
		obj.SetInt("finaleStage", L4D2_GetCurrentFinaleStage());
		parentObj.Set("finaleInfo", obj);
		delete obj;
	}
}

JSONArray GetPlayers() {
	JSONArray players = new JSONArray();
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i)) {
			int team = GetClientTeam(i);
			if( team == 2 || team == 3) {
				JSONObject player = GetPlayer(i);
				players.Push(player);
				delete player;
			}
		}
	}
	return players;
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
	pState_IsBoomed = 8
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
	return state;
}

JSONObject GetPlayer(int client) {
	int team = GetClientTeam(client);
	JSONObject player = new JSONObject();
	player.SetString("steamid", steamidCache[client]);
	player.SetInt("userId", GetClientUserId(client));
	player.SetString("name", nameCache[client]);
	player.SetInt("team", team);
	player.SetBool("isAlive", IsPlayerAlive(client));
	player.SetInt("joinTime", playerJoinTime[client]);
	player.SetInt("permHealth", GetEntProp(client, Prop_Send, "m_iHealth"));
	if(team == 2) {
		// Include idle players (player here is their idle bot)
		if(IsFakeClient(client)) {
			int idlePlayer = L4D_GetIdlePlayerOfBot(client);
			if(idlePlayer > 0) {
				player.SetString("idlePlayerId", steamidCache[idlePlayer]);
				if(IsClientInGame(idlePlayer)) {
					JSONObject idlePlayerObj = GetPlayer(idlePlayer);
					player.Set("idlePlayer", idlePlayerObj);
					delete idlePlayerObj;
				}
			}
		}
		player.SetInt("action", GetAction(client));
		player.SetInt("flowProgress", L4D2_GetVersusCompletionPlayer(client));
		player.SetFloat("flow", L4D2Direct_GetFlowDistance(client));
		player.SetBool("isPinned", L4D2_GetInfectedAttacker(client) > 0);
		player.SetInt("tempHealth", L4D_GetPlayerTempHealth(client));
		player.SetInt("states", GetPlayerStates(client));
		player.SetInt("move", GetPlayerMovement(client));
		player.SetInt("survivor", GetEntProp(client, Prop_Send, "m_survivorCharacter"));
		JSONArray weapons = GetPlayerWeapons(client);
		player.Set("weapons", weapons);
		delete weapons;
	} else if(team == 3) {
		player.SetInt("class", L4D2_GetPlayerZombieClass(client));
		player.SetInt("maxHealth", GetEntProp(client, Prop_Send, "m_iMaxHealth"));
		int victim = L4D2_GetSurvivorVictim(client);
		if(victim > 0)
			player.SetString("pinnedSurvivorId", steamidCache[victim]);
	}
	return player;
}

JSONArray GetPlayerWeapons(int client) {
	JSONArray weapons = new JSONArray();
	static char buffer[64];
	for(int slot = 0; slot < 6; slot++) {
		if(GetClientWeaponNameSmart(client, slot, buffer, sizeof(buffer))) {
			weapons.PushString(buffer);
		} else {
			weapons.PushNull();
		}
	}
	return weapons;
}