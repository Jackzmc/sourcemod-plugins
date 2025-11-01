#pragma semicolon 1
#pragma newdecls required

//#define DEBUG

#define PLUGIN_VERSION "1.0"

#include <sourcemod>
#include <sdktools>
//#include <sdkhooks>

#define MIN_TIME_BETWEEN_NAME_CHANGES 10000 // In seconds
#define MAX_NAME_COUNT 3 // How many changes max within a MIN_TIME_BETWEEN_NAME_CHANGES

public Plugin myinfo = 
{
	name =  "Name change Block", 
	author = "jackzmc", 
	description = "", 
	version = PLUGIN_VERSION, 
	url = "https://github.com/Jackzmc/sourcemod-plugins"
};

public void OnPluginStart() {
	HookEvent("player_info", Event_PlayerInfo);
	RegAdminCmd("status2", Cmd_Status2, ADMFLAG_GENERIC);
	RegAdminCmd("sm_status2", Cmd_Status2, ADMFLAG_GENERIC);
}

char firstName[64][MAXPLAYERS+1];
int joinTime[MAXPLAYERS+1];

public Action Cmd_Status2(int client, int args) {
	ArrayList players = new ArrayList();
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && !IsFakeClient(i) && GetUserAdmin(i) == INVALID_ADMIN_ID) {
			players.Push(i);
		}
	}
	players.SortCustom(Sort_Players);
	char buffer[64], steamid[32];
	ReplyToCommand(client, "Index\tUserid\tName\tSteamID");
	for(int i = 0; i < players.Length; i++) {
		int player = players.Get(i);
		GetClientAuthId(player, AuthId_Steam2, steamid, sizeof(steamid));
		GetClientName(player, buffer, sizeof(buffer));
		if(StrEqual(buffer, firstName[player]))
			ReplyToCommand(client, "%d.\t#%d\t%s\t%s", player, GetClientUserId(player), buffer, steamid);
		else
			ReplyToCommand(client, "%d.\t#%d\t%s\t%s (formely %s)", player, GetClientUserId(player), buffer, steamid, firstName[player]);
	}
	ReplySource src = GetCmdReplySource();
	if(src == SM_REPLY_TO_CONSOLE)
		ReplyToCommand(client, "You can ban players by using their userid or steamid with #. \"sm_ban #52 0\" or \"sm_ban #STEAM_1:1:5325325 0\"");
	else
		ReplyToCommand(client, "You can ban players by using their userid or steamid with #. \"/ban #52 0\" or \"/ban #STEAM_1:1:5325325 0\"");
	return Plugin_Handled;
}

public int Sort_Players(int index1, int index2, ArrayList array, Handle hndl) {
	return joinTime[index2] - joinTime[index1];
}

static int lastNameChange[MAXPLAYERS+1];
static int nameChangeCount[MAXPLAYERS+1];

public void Event_PlayerInfo(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(client && !IsFakeClient(client) && GetUserAdmin(client) == INVALID_ADMIN_ID) {
		++nameChangeCount[client];
		int time = GetTime();
		int diff = time - lastNameChange[client]; 
		if(diff < MIN_TIME_BETWEEN_NAME_CHANGES && nameChangeCount[client] > MAX_NAME_COUNT) {
			char buffer[64];
			Format(buffer, sizeof(buffer), "Excessive name changing (%d in %d seconds)", nameChangeCount[client], diff);
			BanClient(client, 20, BANFLAG_AUTO, "Excessive name changing", buffer);
			
			GetClientAuthId(client, AuthId_Steam2, buffer, sizeof(buffer), false);
			PrintChatToAdmins("%N (steamid %s) hit excessive name change and has been banned temporarily", client, buffer);
		} 
		lastNameChange[client] = time;
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
	

public void OnClientConnected(int client) {
	lastNameChange[client] = 0;
	nameChangeCount[client] = 0;
	firstName[client][0] = '\0';
	if(!IsFakeClient(client)) {
		joinTime[client] = GetTime();
		GetClientName(client, firstName[client], 64 );
	}
}
