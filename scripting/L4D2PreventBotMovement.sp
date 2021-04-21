#pragma semicolon 1
#pragma newdecls required

//#define DEBUG

#define PLUGIN_NAME "L4D2 Prevent Bot Movement"
#define PLUGIN_DESCRIPTION "Prevents bots from moving in the beginning of the round for a set period of time."
#define PLUGIN_AUTHOR "jackzmc"
#define PLUGIN_VERSION "1.0"
#define PLUGIN_URL ""

#include <sourcemod>
#include <sdktools>
//#include <sdkhooks>

public Plugin myinfo = 
{
	name = PLUGIN_NAME, 
	author = PLUGIN_AUTHOR, 
	description = PLUGIN_DESCRIPTION, 
	version = PLUGIN_VERSION, 
	url = PLUGIN_URL
};

static ConVar hSBStop, hStopTime;

public void OnPluginStart()
{
	EngineVersion g_Game = GetEngineVersion();
	if(g_Game != Engine_Left4Dead && g_Game != Engine_Left4Dead2)
	{
		SetFailState("This plugin is for L4D/L4D2 only.");	
	}
	HookEvent("round_start",Event_RoundStart);
	
	hStopTime = CreateConVar("sm_freeze_bot_time","20.0","How long should the bots be frozen for on beginning of round? 0 to disable",FCVAR_NONE,true,0.0);
	hSBStop = FindConVar("sb_stop");
}
public void OnMapStart() {
	if(hStopTime.IntValue != 0) {
		PrintToChatAll("round start");
		hSBStop.BoolValue = true;
		CreateTimer(hStopTime.FloatValue, ResumeBots);
	}
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast) {
	if(hStopTime.IntValue != 0) {
		PrintToChatAll("round start");
		hSBStop.BoolValue = true;
		CreateTimer(hStopTime.FloatValue, ResumeBots);
	}
}
public Action ResumeBots(Handle timer) {
	PrintToChatAll("Resuming bots");
	hSBStop.BoolValue = false;
}
