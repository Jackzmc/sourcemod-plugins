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

	CreateTimer(60.0, Timer_Check, _, TIMER_REPEAT);
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
	if(IsServerEmptyAndNonHibernating()) {
		//Server is stuck in non-hibernation with only bots, quit
		LogAction(0, -1, "Detected server in hibernation with no players, restarting...");
		ServerCommand("quit");
	}
}

//Returns true if there is a bot connected and there is no real players
bool IsServerEmptyAndNonHibernating() {
	bool hasClient;
	for(int i = 1; i < MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i)) {
			if(IsFakeClient(i))
				hasClient = true;
			else
				return false;

		}
	}
	return hasClient;
}
