#pragma semicolon 1

#define DEBUG

#define PLUGIN_AUTHOR ""
#define PLUGIN_VERSION "0.00"

#include <sourcemod>
#include <sdktools>
#include <cstrike>
//#include <sdkhooks>

#pragma newdecls required

public Plugin myinfo = 
{
	name = "",
	author = PLUGIN_AUTHOR,
	description = "",
	version = PLUGIN_VERSION,
	url = ""
};

public void OnPluginStart()
{
	EngineVersion g_Game = GetEngineVersion();
	if(g_Game != Engine_CSGO && g_Game != Engine_CSS)
	{
		SetFailState("This plugin is for CSGO/CSS only.");	
	}
	RegConsoleCmd("sm_first", Command_FirstPov, "Go back to first person");
	RegConsoleCmd("sm_third", Command_ThirdPov, "Go to third person");
}
public Action Command_FirstPov(int client, int args) {
	if(client == 0) {
		ReplyToCommand(client, "This command is for clients only");
		return Plugin_Handled;
	}
	CheatCommand(client, "firstperson", "", "");
	return Plugin_Handled;
}
public Action Command_ThirdPov(int client, int args) {
	if(client == 0) {
		ReplyToCommand(client, "This command is for clients only");
		return Plugin_Handled;
	}
	CheatCommand(client, "thirdperson", "", "");
	return Plugin_Handled;
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