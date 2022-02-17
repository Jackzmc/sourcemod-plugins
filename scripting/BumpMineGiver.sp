#pragma semicolon 1

#define DEBUG

#define PLUGIN_AUTHOR ""
#define PLUGIN_VERSION "0.00"

#include <sourcemod>
#include <sdktools>
#include <cstrike>
//#include <sdkhooks>

#pragma newdecls required

ConVar g_bmgTTeam, g_bmgEnabled, g_bmgCmdLimit;

int g_bmgBumpsGiven[MAXPLAYERS+1];

public Plugin myinfo = 
{
	name = "BumpMineGiver",
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
	g_bmgEnabled = CreateConVar("bmg_enabled", "1", "Should BumpMineGiver be enabled?", FCVAR_NONE, true, 0.0, true, 1.0);
	g_bmgTTeam = CreateConVar("bmg_restrict_team", "0", "Should BumpMineGiver be restricted to a team? 0 - All, 1 - Terrorists, 2 - CounterTerrorists", FCVAR_NONE, true, 0.0, true, 3.0);
	g_bmgCmdLimit = CreateConVar("bmg_cmdlimit", "0", "Limit of amount of bumpmines to be given with !bmp. 0: Disabled, -1: Infinity", FCVAR_NONE);
	HookEvent("round_start", Event_RoundStart);
	HookEvent("player_spawn", Event_PlayerSpawn);
	
	RegConsoleCmd("sm_bmp", Command_GiveBMP, "Give yourself a bump mine");
	RegConsoleCmd("sm_bmg", Command_GiveBMP, "Give yourself a bump mine");
	RegAdminCmd("sm_givebmp", Command_GiveOthersBMP, ADMFLAG_CHEATS, "Give someone x amount of bump mines. Usage: sm_givebmp <user>");
	AutoExecConfig();
}	

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast) {
	for (int i = 0; i < sizeof(g_bmgBumpsGiven); i++) {
		g_bmgBumpsGiven[i] = 0;
	}
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast) {
	if(g_bmgEnabled.BoolValue) {
		int client = GetClientOfUserId(event.GetInt("userid"));
		int wpn_id = GetPlayerWeaponSlot(client, 4);
		int team = GetClientTeam(client);
		if(g_bmgTTeam.IntValue > 0) { //1 or 2
			if (team != g_bmgTTeam.IntValue) return; 
		} 
		if(wpn_id == -1) {
			GivePlayerItem(client, "weapon_bumpmine");
		}
	}
}

public Action Command_GiveBMP(int client, int args) {
	if(g_bmgCmdLimit.IntValue == 0) {
		ReplyToCommand(client, "You have hit the limit of bumpmines");
		return Plugin_Handled;
	}
	//limit is enabled, check
	if(g_bmgCmdLimit.IntValue > 0) {
		if(g_bmgBumpsGiven[client] > g_bmgCmdLimit.IntValue) {
			ReplyToCommand(client, "You have hit the limit of bumpmines");
			return Plugin_Handled;
		}
	}
	GivePlayerItem(client, "weapon_bumpmine");
	g_bmgBumpsGiven[client]++;
	return Plugin_Handled;
}

public Action Command_GiveOthersBMP(int client, int args) {
	if(args < 1) {
		ReplyToCommand(client, "Usage: sm_givebmp <user>");
	}else{
		char arg1[32];
		GetCmdArg(1, arg1, sizeof(arg1));
		char target_name[MAX_TARGET_LENGTH];
		int target_list[MAXPLAYERS], target_count;
		bool tn_is_ml;
		if ((target_count = ProcessTargetString(
				arg1,
				client,
				target_list,
				MAXPLAYERS,
				COMMAND_FILTER_ALIVE,
				target_name,
				sizeof(target_name),
				tn_is_ml)) <= 0)
		{
			/* This function replies to the admin with a failure message */
			ReplyToTargetError(client, target_count);
			return Plugin_Handled;
		}
		for (int i = 0; i < target_count; i++)
		{
			GivePlayerItem(target_list[i], "weapon_bumpmine");
			LogAction(client, target_list[i], "\"%L\" gave \"%L\" a bumpmine", client, target_list[i]);
		}
	}
	return Plugin_Handled;
}