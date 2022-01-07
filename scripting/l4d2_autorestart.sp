#pragma semicolon 1
#pragma newdecls required

//#define DEBUG

#define PLUGIN_VERSION "1.0"
#define MAX_TIME_ONLINE_MS 604800

#include <sourcemod>
#include <sdktools>
//#include <sdkhooks>
int startupTime, triesBots, triesEmpty;

public Plugin myinfo = {
	name =  "L4D2 Autorestart", 
	author = "jackzmc", 
	description = "", 
	version = PLUGIN_VERSION, 
	url = ""
};

public void OnPluginStart() {
	startupTime = GetTime();
	EngineVersion g_Game = GetEngineVersion();
	if(g_Game != Engine_Left4Dead && g_Game != Engine_Left4Dead2)
	{
		SetFailState("This plugin is for L4D/L4D2 only.");	
	}

	RegAdminCmd("sm_request_restart", Command_RequestRestart, ADMFLAG_GENERIC);

	CreateTimer(30.0, Timer_Check, _, TIMER_REPEAT);
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
	if(IsServerEmptyWithOnlyBots()) {
		if(++triesBots > 0) {
			//Server is stuck in non-hibernation with only bots, quit
			LogAction(0, -1, "Detected server in hibernation with no players, restarting...");
			ServerCommand("quit");
		}
		return Plugin_Continue;
	} else if(GetTime() - startupTime > MAX_TIME_ONLINE_MS) {
		LogAction(0, -1, "Server has passed max online time threshold, will restart if remains empty");
		if(IsServerEmpty()) {
			if(++triesEmpty > 4) {
				LogAction(0, -1, "Server has passed max online time threshold and is empty after %d tries, restarting now", triesEmpty);
				ServerCommand("quit");
			}
			return Plugin_Continue;
		}
	}
	triesBots = 0;
	triesEmpty = 0;
	return Plugin_Continue;
}

// Returns true if server is empty, and there is only bots. No players
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
		if(IsClientConnected(i) && !IsFakeClient(i)) {
			return false;
		}
	}
	return true;
}
