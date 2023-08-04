#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_NAME "[L4D1/2] Survivor Identity Fix for 5+ Survivors"
#define PLUGIN_AUTHOR "Merudo, Shadowysn"
#define PLUGIN_DESC "Fix bug where a survivor will change identity when a player connects/disconnects if there are 5+ survivors"
#define PLUGIN_VERSION "1.6"
#define PLUGIN_URL "https://forums.alliedmods.net/showthread.php?p=2403731#post2403731"
#define PLUGIN_NAME_SHORT "5+ Survivor Identity Fix"
#define PLUGIN_NAME_TECH "survivor_identity_fix"

#include <sourcemod>
#include <sdktools>
#include <dhooks>
#include <clientprefs>
#include <left4dhooks>

#define TEAM_SURVIVOR 2
#define TEAM_PASSING 4

#define DEBUG 1


#define GAMEDATA "l4d_survivor_identity_fix"
#define NAME_SetModel "CBasePlayer::SetModel"
#define SIG_SetModel_LINUX "@_ZN11CBasePlayer8SetModelEPKc"
#define SIG_SetModel_WINDOWS "\\x55\\x8B\\x2A\\x8B\\x2A\\x2A\\x56\\x57\\x50\\x8B\\x2A\\xE8\\x2A\\x2A\\x2A\\x2A\\x8B\\x2A\\x2A\\x2A\\x2A\\x2A\\x8B\\x2A\\x8B\\x2A\\x2A\\x8B"
#define SIG_L4D1SetModel_WINDOWS "\\x8B\\x2A\\x2A\\x2A\\x56\\x57\\x50\\x8B\\x2A\\xE8\\x2A\\x2A\\x2A\\x2A\\x8B\\x3D"

char g_Models[MAXPLAYERS+1][128];
static int g_iPendingCookieModel[MAXPLAYERS+1];

Handle hConf = null;
static Handle hDHookSetModel = null, hModelPrefCookie;
static ConVar hCookiesEnabled;
static bool isLateLoad, cookieModelsSet, isL4D1Survivors;
static int survivors;
static bool IsTemporarilyL4D2[MAXPLAYERS];
static char currentMap[16];
Handle cookieModelTimer;

static Menu chooseMenu;

// ------------------------------------------------------------------------
//  Models & survivor names so bots can be renamed
// ------------------------------------------------------------------------
char survivor_names[8][] = { "Nick", "Rochelle", "Coach", "Ellis", "Bill", "Zoey", "Francis", "Louis"};
char survivor_models[8][] =
{
	"models/survivors/survivor_gambler.mdl",
	"models/survivors/survivor_producer.mdl",
	"models/survivors/survivor_coach.mdl",
	"models/survivors/survivor_mechanic.mdl",
	"models/survivors/survivor_namvet.mdl",
	"models/survivors/survivor_teenangst.mdl",
	"models/survivors/survivor_biker.mdl",
	"models/survivors/survivor_manager.mdl"
};


/*TODO: Setup cookie preference setting:
Need to make sure if l4d1 that cookie preference correctly setting? 
Probably if 'rochelle' && l4d1 -> rochelle model, zoey survivorType, or just leave as invalid roch

*/

public Plugin myinfo =
{
	name = PLUGIN_NAME,
	author = PLUGIN_AUTHOR,
	description = PLUGIN_DESC,
	version = PLUGIN_VERSION,
	url = PLUGIN_URL
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
	CreateNative("IdentityFix_SetPlayerModel", Native_SetPlayerModel);
	if(late) isLateLoad = true;
	return APLRes_Success;
}

public void OnPluginStart()
{
	GetGamedata();
	
	CreateConVar("l4d_survivor_identity_fix_version", PLUGIN_VERSION, "Survivor Change Fix Version", FCVAR_SPONLY|FCVAR_NOTIFY|FCVAR_DONTRECORD);
	hCookiesEnabled = CreateConVar("l4d_survivor_identity_fix_cookies", "1.0", "0 -> Disable cookie preference, 1 -> Enable for 5+, 2 -> Enable for any amount");

	HookEvent("player_bot_replace", Event_PlayerToBot, EventHookMode_Post);
	HookEvent("bot_player_replace", Event_BotToPlayer, EventHookMode_Post);
	HookEvent("game_newmap", Event_NewGame);
	HookEvent("player_first_spawn", Event_PlayerFirstSpawn);
	HookEvent("player_disconnect", Event_PlayerDisconnect);
	HookEvent("finale_start", Event_FinaleStart);
	HookEvent("player_spawn", Event_PlayerSpawn);
	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Pre);

	if(isLateLoad) {
		for(int i = 1; i <= MaxClients; i++) {
			if(IsClientConnected(i) && IsClientInGame(i) && IsPlayerAlive(i) && IsSurvivor(i))
				GetClientModel(i, g_Models[i], 64);
		}
	}

	chooseMenu = new Menu(Menu_ChooseSurvivor);
	chooseMenu.SetTitle("Select survivor preference");
	chooseMenu.AddItem("c", "Clear Prefence");
	char info[2];
	for(int i = 0; i < sizeof(survivor_names); i++) {
		Format(info, sizeof(info), "%d", (i+1));
		chooseMenu.AddItem(info, survivor_names[i]);
	}

	hModelPrefCookie = RegClientCookie("survivor_model", "Survivor model preference", CookieAccess_Public);
	RegConsoleCmd("sm_survivor", Cmd_SetSurvivor, "Sets your preferred survivor");
}

// ------------------------------------------------------------------------
//  Stores the client of each survivor each time it is changed
//  Needed because when Event_PlayerToBot fires, it's hunter model instead
// ------------------------------------------------------------------------
public MRESReturn SetModel_Pre(int client, Handle hParams)
{ return MRES_Ignored; } // We need this pre hook even though it's empty, or else the post hook will crash the game.

public MRESReturn SetModel(int client, Handle hParams)
{
	if (!IsValidClient(client)) return MRES_Ignored;
	if (!IsSurvivor(client)) 
	{
		g_Models[client][0] = '\0';
		return MRES_Ignored;
	}
	
	char model[128];
	DHookGetParamString(hParams, 1, model, sizeof(model));
	if (StrContains(model, "models/infected", false) < 0)
	{
		strcopy(g_Models[client], 128, model);
	}
	return MRES_Ignored;
}

// --------------------------------------
// Bot replaced by player
// --------------------------------------
public void Event_BotToPlayer(Handle event, const char[] name, bool dontBroadcast)
{
	int player = GetClientOfUserId(GetEventInt(event, "player"));
	int bot    = GetClientOfUserId(GetEventInt(event, "bot"));

	if (!IsValidClient(player) || !IsSurvivor(player) || IsFakeClient(player)) return;  // ignore fake players (side product of creating bots)

	char model[128];
	GetClientModel(bot, model, sizeof(model));
	SetEntityModel(player, model);
	strcopy(g_Models[player], 64, model);
	SetEntProp(player, Prop_Send, "m_survivorCharacter", GetEntProp(bot, Prop_Send, "m_survivorCharacter"));
}

// --------------------------------------
// Player -> Bot
// --------------------------------------
public void Event_PlayerToBot(Handle event, char[] name, bool dontBroadcast)
{
	int player = GetClientOfUserId(GetEventInt(event, "player"));
	int bot    = GetClientOfUserId(GetEventInt(event, "bot")); 

	if (!IsValidClient(player) || !IsSurvivor(player) || IsFakeClient(player)) return; // ignore fake players (side product of creating bots)
	if (g_Models[player][0] != '\0')
	{
		int playerType = GetEntProp(player, Prop_Send, "m_survivorCharacter");
		if(playerType >= 0 && playerType <= 7) {
			SetEntProp(bot, Prop_Send, "m_survivorCharacter", playerType);
			SetClientInfo(bot, "name", survivor_names[playerType]);
		} else {
			PrintToServer("[l4d_survivor_identity_fix]: Ignoring player's (%N) m_survivorCharacter due to out of range (%d)", player, playerType);
		}
		SetEntityModel(bot, g_Models[player]); // Restore saved model. Player model is hunter at this point
	}
}

void GetGamedata()
{
	char filePath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, filePath, sizeof(filePath), "gamedata/%s.txt", GAMEDATA);
	if( FileExists(filePath) )
	{
		hConf = LoadGameConfigFile(GAMEDATA); // For some reason this doesn't return null even for invalid files, so check they exist first.
	}
	else
	{
		PrintToServer("[SM] %s plugin unable to get %i.txt gamedata file. Generating...", PLUGIN_NAME_SHORT, GAMEDATA);
		
		Handle fileHandle = OpenFile(filePath, "a+");
		if (fileHandle == null)
		{ SetFailState("[SM] Couldn't generate gamedata file!"); }
		
		WriteFileLine(fileHandle, "\"Games\"");
		WriteFileLine(fileHandle, "{");
		WriteFileLine(fileHandle, "	\"left4dead\"");
		WriteFileLine(fileHandle, "	{");
		WriteFileLine(fileHandle, "		\"Signatures\"");
		WriteFileLine(fileHandle, "		{");
		WriteFileLine(fileHandle, "			\"%s\"", NAME_SetModel);
		WriteFileLine(fileHandle, "			{");
		WriteFileLine(fileHandle, "				\"library\"	\"server\"");
		WriteFileLine(fileHandle, "				\"linux\"	\"%s\"", SIG_SetModel_LINUX);
		WriteFileLine(fileHandle, "				\"windows\"	\"%s\"", SIG_L4D1SetModel_WINDOWS);
		WriteFileLine(fileHandle, "				\"mac\"		\"%s\"", SIG_SetModel_LINUX);
		WriteFileLine(fileHandle, "			}");
		WriteFileLine(fileHandle, "		}");
		WriteFileLine(fileHandle, "	}");
		WriteFileLine(fileHandle, "	\"left4dead2\"");
		WriteFileLine(fileHandle, "	{");
		WriteFileLine(fileHandle, "		\"Signatures\"");
		WriteFileLine(fileHandle, "		{");
		WriteFileLine(fileHandle, "			\"%s\"", NAME_SetModel);
		WriteFileLine(fileHandle, "			{");
		WriteFileLine(fileHandle, "				\"library\"	\"server\"");
		WriteFileLine(fileHandle, "				\"linux\"	\"%s\"", SIG_SetModel_LINUX);
		WriteFileLine(fileHandle, "				\"windows\"	\"%s\"", SIG_SetModel_WINDOWS);
		WriteFileLine(fileHandle, "				\"mac\"		\"%s\"", SIG_SetModel_LINUX);
		WriteFileLine(fileHandle, "			}");
		WriteFileLine(fileHandle, "		}");
		WriteFileLine(fileHandle, "	}");
		WriteFileLine(fileHandle, "}");
		
		CloseHandle(fileHandle);
		hConf = LoadGameConfigFile(GAMEDATA);
		if (hConf == null)
		{ SetFailState("[SM] Failed to load auto-generated gamedata file!"); }
		
		PrintToServer("[SM] %s successfully generated %s.txt gamedata file!", PLUGIN_NAME_SHORT, GAMEDATA);
	}
	PrepDHooks();
}

void PrepDHooks()
{
	if (hConf == null)
	{
		SetFailState("Error: Gamedata not found");
	}
	
	hDHookSetModel = DHookCreateDetour(Address_Null, CallConv_THISCALL, ReturnType_Void, ThisPointer_CBaseEntity);
	DHookSetFromConf(hDHookSetModel, hConf, SDKConf_Signature, NAME_SetModel);
	DHookAddParam(hDHookSetModel, HookParamType_CharPtr);
	DHookEnableDetour(hDHookSetModel, false, SetModel_Pre);
	DHookEnableDetour(hDHookSetModel, true, SetModel);
}
//Reset the list of models on a new game -> no players.

public void Event_NewGame(Event event, const char[] name, bool dontBroadcast) {
	PrintToServer("Clearing models");
	for(int i = 1; i <= MaxClients; i++) {
		g_Models[i][0] = '\0';
	}
	survivors = 0;
	cookieModelsSet = false;
}
//Checks if a user has a model preference cookie (set by native). If so, populate g_Models w/ it
public void OnClientCookiesCached(int client) {
	if(IsFakeClient(client) && hCookiesEnabled.IntValue == 0) return;

	char modelPref[2];
	GetClientCookie(client, hModelPrefCookie, modelPref, sizeof(modelPref));
	if(strlen(modelPref) > 0) {
		//'type' starts at 1, 5 being other l4d1 survivors for l4d2
		int type;
		if(StringToIntEx(modelPref, type) > 0) {
			PrintToServer("%N has cookie for %s", client, survivor_models[type - 1][17]);
			if(isL4D1Survivors && type > 4) {
				strcopy(g_Models[client], 64, survivor_models[type - 5]);
				g_iPendingCookieModel[client] = type - 4;
			}
			
		}
	}
}

///////////////////////////////////////////////////////////////////////////////
// Cookies & Map Fixes
///////////////////////////////////////////////////////////////////////////////
//Prevent issues with L4D1 characters being TP'd and stuck in brain dead form
public void OnMapStart() {
	isL4D1Survivors = L4D2_GetSurvivorSetMap() == 1;

	survivors = 0;

	for(int i = 0; i < sizeof(survivor_models); i++) {
		PrecacheModel(survivor_models[i], true);
	}
	
	GetCurrentMap(currentMap, sizeof(currentMap));
}

//Either use preferred model OR find the least-used.
public void Event_PlayerFirstSpawn(Event event, const char[] name, bool dontBroadcast) {
	if(hCookiesEnabled.IntValue > 0)
		RequestFrame(Frame_CheckClient, event.GetInt("userid"));
}
public void Event_PlayerDisconnect(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(client > 0) {
		IsTemporarilyL4D2[client] = false;
		g_Models[client][0] = '\0';
		if(!IsFakeClient(client) && survivors > 0)
			survivors--;
	}
}
public void Frame_CheckClient(int userid) {
	int client = GetClientOfUserId(userid);
	if(client > 0 && GetClientTeam(client) == 2 && !IsFakeClient(client)) {
		int survivorThreshold = hCookiesEnabled.IntValue == 1 ? 4 : 0;
		survivors++;
		if(survivors > survivorThreshold) {
			//A model is set: Fetched from cookie
			if(g_iPendingCookieModel[client]) {
				CreateTimer(0.2, Timer_SetClientModel, userid);
			}/* else {
				CreateTimer(0.2, Timer_SetAllCookieModels);
			}*/ //FIXME: Possibly causing people to become rochelle weirdly  
		}else{
			//Model was not set: Use least-used survivor.
			
			//RequestFrame(Frame_SetPlayerToLeastUsedModel, client);
		}
	}
}
public Action Timer_SetClientModel(Handle timer, int userid) {
	int client = GetClientOfUserId(userid);
	if(client > 0) {
		SetEntityModel(client, survivor_models[g_iPendingCookieModel[client] - 1]);
		SetEntProp(client, Prop_Send, "m_survivorCharacter", g_iPendingCookieModel[client] - 1);
		g_iPendingCookieModel[client] = 0;
	}
	return Plugin_Handled;
}
public Action Timer_SetAllCookieModels(Handle h) {
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && g_iPendingCookieModel[i] && GetClientTeam(i) == 2) {
			// TODO: Proper implement
			SetEntityModel(i, survivor_models[g_iPendingCookieModel[i] - 1]);
			SetEntProp(i, Prop_Send, "m_survivorCharacter", g_iPendingCookieModel[i] - 1);
		}
		g_iPendingCookieModel[i] = 0;
	}
	return Plugin_Handled;
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(client > 0 && client <= MaxClients && GetClientTeam(client) == 2) {
		if(StrEqual(currentMap, "c6m1_riverbank")) {
			//If player died as l4d1 character on first map, revert it
			RevertSwappedSurvivor(client);
		}else if(StrEqual(currentMap, "c6m3_port")) {
			//If player not swapped (joined, or via prev. map, switch)
			if(IsTemporarilyL4D2[client])
				RequestFrame(Frame_RevertSwappedSurvivor, client);
			else
				RequestFrame(Frame_SwapSurvivor, client);
		}
	}
}
public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) {
	//Switch players to L4D2 right before death.
	if(StrEqual(currentMap, "c6m3_port") || StrEqual(currentMap, "c6m1_riverbank")) {
		int client = GetClientOfUserId(event.GetInt("userid"));
		if(client > 0 && GetClientTeam(client) == 2) {
			SwapL4D1Survivor(client, false);
		}
	}
	return Plugin_Continue;
}


//On finale start: Set back to their L4D1 character.
public void Event_FinaleStart(Event event, const char[] name, bool dontBroadcast) {
	if(StrEqual(currentMap, "c6m3_port")) {
		for(int i = 1; i <= MaxClients; i++) {
			if(IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2) {
				RevertSwappedSurvivor(i);
			}
		}
	}
}
public void Frame_SwapSurvivor(int client) {
	if(IsClientConnected(client) && IsClientInGame(client))
		SwapL4D1Survivor(client, true);
}
public void Frame_RevertSwappedSurvivor(int client) {
	if(IsClientConnected(client) && IsClientInGame(client))
		RevertSwappedSurvivor(client);
}

void SwapL4D1Survivor(int client, bool showMessage) {
	int playerType = GetEntProp(client, Prop_Send, "m_survivorCharacter");
	//If character is L4D1 Character (4: bill, etc..) then swap
	if(playerType > 3) {
		SetEntProp(client, Prop_Send, "m_survivorCharacter", playerType - 4);
		IsTemporarilyL4D2[client] = true;
		if(showMessage && GetUserAdmin(client) != INVALID_ADMIN_ID) {
			PrintToChat(client, "Your survivor is temporarily swapped. Please do not change back, it should auto-revert after the elevator is done. This is to prevent a game bug with L4D1 Survivors on this map.");
		}
		LogMessage("SwapL4D1Survivor: Swapping %N (type=%d)", client, playerType);
	}
}
void RevertSwappedSurvivor(int client) {
	if(IsTemporarilyL4D2[client]) {
		int playerType = GetEntProp(client, Prop_Send, "m_survivorCharacter");
		if(playerType < 3) {
			SetEntProp(client, Prop_Send, "m_survivorCharacter", playerType + 4);
			IsTemporarilyL4D2[client] = false;
			LogMessage("RevertSwappedSurvivor: Reverting %N (type=%d)", client, playerType);
		}
	}
}


///////////////////////////////////////////////////////////////////////////////
// Commands
///////////////////////////////////////////////////////////////////////////////

public Action Cmd_SetSurvivor(int client, int args) {
	if(args > 0) {
		char arg1[16];
		GetCmdArg(1, arg1, sizeof(arg1));
		if(arg1[0] == 'c') {
			SetClientCookie(client, hModelPrefCookie, "");
			ReplyToCommand(client, "Your survivor preference has been reset");
			return Plugin_Handled;
		}
		int number;
		if(StringToIntEx(arg1, number) > 0 && number >= 0 && number < 8) {
			SetClientCookie(client, hModelPrefCookie, arg1);
			ReplyToCommand(client, "Your survivor preference set to %s", survivor_names[number]);
			return Plugin_Handled;
		}else{
			int type = GetSurvivorId(arg1, false); // Use false to have every character have unique id
			if(type > -1) {
				strcopy(g_Models[client], 64, survivor_models[type]);
				if(isL4D1Survivors) type = GetSurvivorId(arg1, true); // Then fetch the correct ids for the survivorCharacter
				SetEntProp(client, Prop_Send, "m_survivorCharacter", type);
			}
		}
	}
	chooseMenu.Display(client, 0);
	return Plugin_Handled;
}

int Menu_ChooseSurvivor(Menu menu, MenuAction action, int activator, int item) {
	if (action == MenuAction_Select) {
		char info[2];
		menu.GetItem(item, info, sizeof(info));
		if(info[0] == 'c') {
			SetClientCookie(activator, hModelPrefCookie, "");
			ReplyToCommand(activator, "Your survivor preference has been reset");
		}else{
			/*strcopy(g_Models[client], 64, survivor_models[type]);
			if(isL4D1Survivors) type = GetSurvivorId(str, true);
			SetEntProp(client, Prop_Send, "m_survivorCharacter", type);*/
			SetClientCookie(activator, hModelPrefCookie, info);
			ReplyToCommand(activator, "Your survivor preference set to %s", survivor_names[StringToInt(info) - 1]);
		}
	} else if (action == MenuAction_End)	
		delete menu;
	return 0;
}

///////////////////////////////////////////////////////////////////////////////
// Methods
///////////////////////////////////////////////////////////////////////////////

bool IsValidClient(int client, bool replaycheck = true)
{
	if (client <= 0 || client > MaxClients) return false;
	if (!IsClientInGame(client)) return false;
	if (replaycheck)
	{
		if (IsClientSourceTV(client) || IsClientReplay(client)) return false;
	}
	return true;
}

bool IsSurvivor(int client)
{
	if (GetClientTeam(client) != TEAM_SURVIVOR && GetClientTeam(client) != TEAM_PASSING) return false;
	return true;
}

public int Native_SetPlayerModel(Handle plugin, int numParams) {
	int client = GetNativeCell(1);
	int character = GetNativeCell(2);
	bool keep = GetNativeCell(3) == 1;
	if(numParams != 2 && numParams != 3) {
		ThrowNativeError(SP_ERROR_NATIVE, "Incorrect amount of parameters passed");
		return 3;
	}else if(client < 1 || client > MaxClients || !IsClientInGame(client)) {
		ThrowNativeError(SP_ERROR_INDEX, "Client index %d is not valid or is not in game", client);
		return 2;
	} else if(character < 0 || character > 7) {
		ThrowNativeError(SP_ERROR_INDEX, "Character ID (%d) is not in range (0-7)", character);
		return 1;
	} else {
		//Set a cookie to remember their model, starting at 1.
		char charTypeStr[2];
		Format(charTypeStr, sizeof(charTypeStr), "%d", character + 1);
		if(!IsFakeClient(client) && keep)
			SetClientCookie(client, hModelPrefCookie, charTypeStr);

		strcopy(g_Models[client], 64, survivor_models[character]);
		return 0;
	}
}

stock int GetSurvivorId(const char str[16], bool isL4D1 = false) {
	if(str[0] == 'b') {
		return isL4D1 ? 0 : 4;
	} else if(str[0] == 'z') {
		return isL4D1 ? 1 : 5;
	} else if(str[0] == 'l') {
		return isL4D1 ? 2 : 7;
	} else if(str[0] == 'f') {
		return isL4D1 ? 3 : 6;
	} else if(str[0] == 'n') {
		return 0;
	} else if(str[0] == 'r') {
		return 1;
	} else if(str[0] == 'e') {
		return 3;
	} else if(str[0] == 'c') {
		return 2;
	}
	return -1;
}