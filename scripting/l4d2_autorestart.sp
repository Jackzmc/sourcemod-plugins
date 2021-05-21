#pragma semicolon 1
#pragma newdecls required

//#define DEBUG

#define PLUGIN_VERSION "1.0"

#include <sourcemod>
#include <sdktools>
//#include <sdkhooks>

public Plugin myinfo = 
{
	name =  "L4D2 Autorestart", 
	author = "jackzmc", 
	description = "", 
	version = PLUGIN_VERSION, 
	url = ""
};

public void OnPluginStart()
{
	EngineVersion g_Game = GetEngineVersion();
	if(g_Game != Engine_Left4Dead && g_Game != Engine_Left4Dead2)
	{
		SetFailState("This plugin is for L4D/L4D2 only.");	
	}

	RegAdminCmd("sm_request_restart", Command_RequestRestart, ADMFLAG_GENERIC);

	CreateTimer(60.0, Timer_Check, _, TIMER_REPEAT);
}

public Action Command_RequestRestart(int client, int args) {
	if(IsServerEmpty()) {
		ReplyToCommand(client, "Restarting...");
		LogAction(client, -1, "requested to restart server if empty.");
		ServerCommand("quit");
	}else{
		ReplyToCommand(client, "Players are online.");
	}
	return Plugin_Handled;
}

public Action Timer_Check(Handle h) {
	// char time[8];
	// FormatTime(strtime, sizeof(strtime), "%H%M");
	// int time = StringToInt(time);
	// if(0400 <= time && time <= 0401) {
	//     //If around 4 AM
	//     ServerCommand("quit");
	//     return Plugin_Stop;
	// }else 
	if(IsServerEmptyWithOnlyBots()) {
		//Server is stuck in non-hibernation with only bots, quit
		LogAction(0, -1, "Detected server in hibernation with no players, restarting...");
		ServerCommand("quit");
	}
}

bool IsServerEmptyWithOnlyBots() {
	bool hasBot;
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i)) {
			if(IsFakeClient(i))
				//Has a bot, but there could be other players.
				hasBot = true;
			else
				//Is player, not empty.
				return false;

		}
	}
	return hasBot;
}

//Returns true if there is a bot connected and there is no real players
bool IsServerEmpty() {
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i)) {
			if(!IsFakeClient(i))
				return false;

		}
	}
	return true;
}
