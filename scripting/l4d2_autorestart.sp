#pragma semicolon 1
#pragma newdecls required

//#define DEBUG


/// (int) The maximum amount of seconds server being online 
/// should the plugin start trying to find a time to restart
#define MAX_TIME_ONLINE_SECONDS 60 * 60 * 24 * 1 // 1 day 

/// (float) The interval to check for uptime & for an empty server when pending restart
#define CHECK_TIME_INTERVAL 60.0 * 13.0 // 13 min

#define PLUGIN_VERSION "1.1"

#include <sourcemod>
#include <sdktools>
//#include <sdkhooks>
int startupTime, triesBots, triesEmpty;
bool pendingRestart;

public Plugin myinfo = {
	name =  "L4D2 Autorestart", 
	author = "jackzmc", 
	description = "", 
	version = PLUGIN_VERSION, 
	url = "https://github.com/Jackzmc/sourcemod-plugins"
};

ConVar cvar_hibernateWhenEmpty;

public void OnPluginStart() {
	startupTime = GetTime();
	EngineVersion g_Game = GetEngineVersion();
	if(g_Game != Engine_Left4Dead && g_Game != Engine_Left4Dead2)
	{
		SetFailState("This plugin is for L4D/L4D2 only.");	
	}

	cvar_hibernateWhenEmpty = FindConVar("sv_hibernate_when_empty");

	RegAdminCmd("sm_request_restart", Command_RequestRestart, ADMFLAG_GENERIC);
	RegAdminCmd("sm_ar_status", Command_Status, ADMFLAG_GENERIC);

	CreateTimer(CHECK_TIME_INTERVAL, Timer_Check, _, TIMER_REPEAT);
}

Action Command_Status(int client, int args) {
	char buffer[100];
	FormatTime(buffer, sizeof(buffer), "%F at %I:%M %p", startupTime);
	ReplyToCommand(client, "Started: %s", buffer);
	int diff = GetTime() - startupTime;
	int exceedRestart = diff - MAX_TIME_ONLINE_SECONDS;
	int exceedRestartMin = exceedRestart / 60;
	int exceedRestartHour = exceedRestartMin / 60;
	ReplyToCommand(client, "Overdue restart time: %d hr / %d min / %d s", exceedRestartHour, exceedRestartMin, exceedRestart);
	ReplyToCommand(client, "triesBots = %d\ttriesEmpty = %d / %d", triesBots, triesEmpty, 4);
	return Plugin_Handled;
}

Action Command_RequestRestart(int client, int args) {
	if(IsServerEmpty()) {
		ReplyToCommand(client, "Restarting...");
		LogAction(client, -1, "requested to restart server if empty.");
		ServerCommand("quit");
	} else {
		ReplyToCommand(client, "Players are online.");
	}
	return Plugin_Handled;
}

Action Timer_Check(Handle h) {
	if(IsServerEmptyWithOnlyBots()) {
		if(++triesBots > 0) {
			//Server is stuck in non-hibernation with only bots, quit
			LogAction(0, -1, "Detected server in hibernation with no players, restarting...");
			ServerCommand("quit");
		}
		return Plugin_Continue;
	} else if(pendingRestart || GetTime() - startupTime > MAX_TIME_ONLINE_SECONDS) {
		LogAction(0, -1, "Server has passed max online time threshold, will restart if remains empty (chk%d)", triesEmpty);
		pendingRestart = true;
		cvar_hibernateWhenEmpty.BoolValue = false;
		if(IsServerEmpty()) {
			if(++triesEmpty >= 4) {
				LogAction(0, -1, "Server has passed max online time threshold and is empty after %d tries, restarting now", triesEmpty);
				ServerCommand("quit");
			}
			return Plugin_Continue;
		}
		// If server is occupied, falls down below and resets:
	}
	triesBots = 0;
	triesEmpty = 0;
	return Plugin_Continue;
}

public void OnConfigsExecuted() {
	// Reset no hibernate setting when level changes:
	if(pendingRestart) {
		cvar_hibernateWhenEmpty.BoolValue = false;
	}
}

// Returns true if server is empty, and there is only bots. No players
bool IsServerEmptyWithOnlyBots() {
	bool hasBot;
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i)) {
			if(IsFakeClient(i)) {
				//Has a bot, but there could be other players.
				hasBot = true;
			} else {
				//Is player, not empty.
				return false;
			}

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
