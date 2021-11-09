#define PLUGIN_VERSION	"1.1.0"
#define MAX_LINE_WIDTH	 64

#define MESSAGE_FOR_PLAYERS_LINE1	""
#define MESSAGE_FOR_PLAYERS_LINE2	"\x04RECEIVED SERVER RESERVATION REQUEST"
#define MESSAGE_FOR_PLAYERS_LINE3	"\x04YOU WILL BE RETURNED TO LOBBY"
#define MESSAGE_FOR_PLAYERS_LINE4	""

#pragma semicolon 1

#include <sourcemod>

#pragma newdecls required

ConVar PluginCvarSearchKey, PluginCvarMode, PluginCvarTimeout, PluginCvarImmuneLevel, 
       SteamGroupExclusiveCvar, SearchKeyCvar, HibernationCvar;

int HibernationCvarValue;
bool isMapChange = false, doRestartMap = false;
char PluginSearchKeyString[MAX_LINE_WIDTH] = "", PluginCvarImmuneFlagString[MAX_LINE_WIDTH] = "", CurrentMapString[MAX_LINE_WIDTH] = "";

public Plugin myinfo =
{
	name = "Reserve The Server",
	author = "Jack'lul [Edited by Dosergen]",
	description = "Frees the server from all players and reserves it.",
	version = PLUGIN_VERSION,
	url = "https://forums.alliedmods.net/showthread.php?p=2084993"
}

public void OnPluginStart() {
	EngineVersion g_Game = GetEngineVersion();
	if(g_Game != Engine_Left4Dead && g_Game != Engine_Left4Dead2) {
		SetFailState("This plugin is for L4D/L4D2 only.");	
	}
	
	CreateConVar("l4d_rts_version", PLUGIN_VERSION, "Reserve The Server plugin version", 0|FCVAR_NOTIFY|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_DONTRECORD);	
	PluginCvarMode = CreateConVar("l4d_rts_mode", "1", "0 - only remove players using lobby vote, 1 - remove players using lobby vote and then disconnect server from matchmaking", 0, true, 0.0, true, 1.0);
	PluginCvarSearchKey = CreateConVar("l4d_rts_searchkey", "", "sv_search_key will be set to this while server is reserved", 0);
	PluginCvarTimeout = CreateConVar("l4d_rts_timeout", "30", "How long will the server stay disconnected from matchmaking? 0 - never restore matchmaking connection", 0, true, 0.0, true, 300.0);
	PluginCvarImmuneLevel = CreateConVar("l4d_rts_immunelevel", "1", "Any player >= to this level will cancel the lobby vote.", 0);

	RegAdminCmd("sm_rts", Command_MakeReservation, ADMFLAG_BAN, "Free the server from all players, then reserve it.");
	RegAdminCmd("sm_cr", Command_CancelReservation, ADMFLAG_BAN, "Cancel reservation and make server public again.");
	
	SteamGroupExclusiveCvar	= FindConVar("sv_steamgroup_exclusive");
	SearchKeyCvar = FindConVar("sv_search_key");
	HibernationCvar = FindConVar("sv_hibernate_when_empty");
	HibernationCvarValue = GetConVarInt(HibernationCvar);
	
	AutoExecConfig(true, "l4d_rts");
}

public void OnClientDisconnect(int client) {
	if (client == 0 || isMapChange || IsFakeClient(client))
		return;
	
	if(doRestartMap == true)
		CreateTimer(1.0, MapReloadCheck);
}

public void OnMapEnd() {
	isMapChange = true;
	doRestartMap = false;
}

public void OnMapStart() {
	isMapChange = false;
}

public Action Command_MakeReservation(int client, int args) {
	bool isAdminOnline, isServerEmpty = true;
	if(client > 0) {
		for (int i = 1; i <= MaxClients; i++) {
			if (IsClientConnected(i) && IsClientInGame(i)) {
				AdminId admin = GetUserAdmin(i);
				if (admin != INVALID_ADMIN_ID && GetAdminImmunityLevel(admin) >= PluginCvarImmuneLevel.IntValue) {
					isAdminOnline = true;
					break;
				}
				if(isServerEmpty) isServerEmpty = false;
			}
		}
	}
	//If there is no admins playing OR request is from server itself then reserve:
	if(!isAdminOnline)
	{
		LogMessage("Received server reservation request.");
		if(!isServerEmpty) {	
			if(GetConVarInt(PluginCvarMode) == 1)
			{
				doRestartMap = true;
				ReplyToCommand(client, "Server will be freed from all players and reserved."); 
			}
			else
				ReplyToCommand(client, "Server will be freed from all players."); 	
			
			PrintToChatAll(MESSAGE_FOR_PLAYERS_LINE1);
			PrintToChatAll(MESSAGE_FOR_PLAYERS_LINE2);
			PrintToChatAll(MESSAGE_FOR_PLAYERS_LINE3);
			PrintToChatAll(MESSAGE_FOR_PLAYERS_LINE4);
			
			CreateTimer(5.0, FreeTheServer);
		} else if(GetConVarInt(PluginCvarMode) == 1) {
			DisconnectFromMatchmaking();
			ReloadMap();
		}
	}
	else
		ReplyToCommand(client, "Server reservation request denied - admin is online!");
	return Plugin_Handled;
}

public Action Command_CancelReservation(int client, int args) {
	CreateTimer(0.1, MakeServerPublic);
}

public Action FreeTheServer(Handle timer) {
	CallLobbyVote();
	PassVote();
	
	if(GetConVarInt(PluginCvarMode) == 1) {
		DisconnectFromMatchmaking();
	}
}

public Action MakeServerPublic(Handle timer) {
	ConnectToMatchmaking();
	
	int notConnected = 0;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientConnected (i) && IsClientInGame (i))
			break;
		else
			notConnected++;
	}
	
	if(notConnected == MaxClients)
		ReloadMap();
	
	if(HibernationCvarValue != 0 && GetConVarInt(HibernationCvar) == 0)
		SetConVarInt(HibernationCvar, 1);
}

public Action MapReloadCheck(Handle timer) {
	if (!isMapChange && doRestartMap) {
		doRestartMap = false;
		ReloadMap();
	}
}

void CallLobbyVote() {
	for (int iClient = 1; iClient <= MaxClients; iClient++) {
		if (IsClientConnected (iClient) && IsClientInGame (iClient)) {
			FakeClientCommand (iClient, "callvote returntolobby");
		}
	}
}

void PassVote() {
	for(int iClient = 1; iClient <= MaxClients; iClient++) {
		if (IsClientConnected (iClient) && IsClientInGame (iClient)) {
			FakeClientCommand(iClient, "Vote Yes");
		}
	}
}

void ReloadMap() {
	GetCurrentMap(CurrentMapString, sizeof(CurrentMapString));
	ServerCommand("map %s", CurrentMapString);
}

void DisconnectFromMatchmaking() {
	GetConVarString(PluginCvarSearchKey, PluginSearchKeyString, sizeof(PluginSearchKeyString));
	SetConVarInt(SteamGroupExclusiveCvar, 1);
	SetConVarString(SearchKeyCvar, PluginSearchKeyString);
	
	if(HibernationCvarValue != 0)
		SetConVarInt(HibernationCvar, 0);	
	
	if(GetConVarFloat(PluginCvarTimeout)>0)
		CreateTimer(GetConVarFloat(PluginCvarTimeout), MakeServerPublic);
}

void ConnectToMatchmaking() {
	SetConVarInt(SteamGroupExclusiveCvar, 0);
	SetConVarString(SearchKeyCvar, "");
}
