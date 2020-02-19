#pragma semicolon 1
#pragma newdecls required

#define DEBUG

#define PLUGIN_NAME "L4D2 Auto Warp Survivors"
#define PLUGIN_DESCRIPTION ""
#define PLUGIN_AUTHOR "jackzmc"
#define PLUGIN_VERSION "1.0"
#define PLUGIN_URL ""

#include <sourcemod>
#include <sdktools>
//#include <sdkhooks>

#pragma newdecls required

public Plugin myinfo = 
{
	name = PLUGIN_NAME, 
	author = PLUGIN_AUTHOR, 
	description = PLUGIN_DESCRIPTION, 
	version = PLUGIN_VERSION, 
	url = PLUGIN_URL
};

bool g_EnteredCheckpoint = false;

public void OnPluginStart()
{
	EngineVersion g_Game = GetEngineVersion();
	if(g_Game != Engine_Left4Dead && g_Game != Engine_Left4Dead2)
	{
		SetFailState("This plugin is for L4D/L4D2 only.");	
	}
	HookEvent("player_entered_checkpoint", Event_PlayerEnteredCheckpoint);
	HookEvent("round_start",Event_RoundStart);
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast) {
	g_EnteredCheckpoint = false;
}
public void Event_PlayerEnteredCheckpoint(Event event, const char[] name, bool dontBroadcast) {
	if(!g_EnteredCheckpoint) {
		int client = GetClientOfUserId(event.GetInt("userid"));
		bool playersLeft = false;
		for (int i = 1; i < MaxClients;i++) {
			if (client == i)continue;
			if (!IsClientConnected(i)) continue;
			if (GetClientTeam(i) != 2) continue;
			
			if(!IsFakeClient(i)) {
				playersLeft = true;
				break;
			} 
		}
		if(!playersLeft) {
			g_EnteredCheckpoint = true;
			CheatCommand(client,"warp_all_survivors_to_checkpoint","","");
		}
	}
}
stock bool IsPlayerIncapped(int client)
{
	if (GetEntProp(client, Prop_Send, "m_isIncapacitated", 1)) return true;
	return false;
}

stock void CheatCommand(int client, char[] command, char[] argument1, char[] argument2)
{
	int userFlags = GetUserFlagBits(client);
	SetUserFlagBits(client, ADMFLAG_ROOT);
	int flags = GetCommandFlags(command);
	SetCommandFlags(command, flags & ~FCVAR_CHEAT);
	FakeClientCommand(client, "%s %s %s", command, argument1, argument2);
	SetCommandFlags(command, flags);
	SetUserFlagBits(client, userFlags);
} 