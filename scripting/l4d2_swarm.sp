#pragma semicolon 1
#pragma newdecls required

//#define DEBUG

#define PLUGIN_NAME "L4D2 Swarm"
#define PLUGIN_DESCRIPTION "Swarm a player with zombies to counter the trolls"
#define PLUGIN_AUTHOR "jackzmc"
#define PLUGIN_VERSION "1.0"
#define PLUGIN_URL ""

#include <sourcemod>
#include <sdktools>
#include "jutils.inc"

ConVar hSwarmDefaultRange;
//Swarm target is a userid
int SwarmTarget, SwarmRadius;

Handle timer = INVALID_HANDLE;

public Plugin myinfo = 
{
	name = PLUGIN_NAME, 
	author = PLUGIN_AUTHOR, 
	description = PLUGIN_DESCRIPTION, 
	version = PLUGIN_VERSION, 
	url = PLUGIN_URL
};

public void OnPluginStart()
{
	EngineVersion g_Game = GetEngineVersion();
	if(g_Game != Engine_Left4Dead && g_Game != Engine_Left4Dead2)
	{
		SetFailState("This plugin is for L4D/L4D2 only.");	
	}

	hSwarmDefaultRange = CreateConVar("sm_swarm_default_range", "7500", "The default range swarms will affect (As a default argument or in use in menus)", FCVAR_NONE, true, 20.0);
	SwarmRadius = hSwarmDefaultRange.IntValue;

	LoadTranslations("common.phrases");
	RegAdminCmd("sm_swarm", Cmd_Swarm, ADMFLAG_ROOT, "sm_swarm [player] [range] - Zombies swarm player (or random if not set)");
	RegAdminCmd("sm_rush", Cmd_Swarm, ADMFLAG_ROOT, "sm_swarm [player] [range] - Zombies swarm player (or random if not set)");
	RegAdminCmd("sm_rushmenu", Cmd_SwarmMenu, ADMFLAG_ROOT, "sm_swarmmenu - Open swarm menu");
	RegAdminCmd("sm_rmenu", Cmd_SwarmMenu, ADMFLAG_ROOT, "sm_swarmmenu - Open swarm menu");

	RegAdminCmd("sm_swarmtoggle", Cmd_SwarmToggle, ADMFLAG_ROOT, "sm_swarmtoggle <player> [range]");
	RegAdminCmd("sm_rushtoggle", Cmd_SwarmToggle, ADMFLAG_ROOT, "sm_swarmtoggle <player> [range]");
	RegAdminCmd("sm_rt", Cmd_SwarmToggle, ADMFLAG_ROOT, "sm_swarmtoggle <player> [range]");
	RegAdminCmd("sm_rushtogglemenu", Cmd_SwarmToggleMenu, ADMFLAG_ROOT, "sm_swarmtogglemenu - Open swarm toggle menu");
	RegAdminCmd("sm_rtmenu", Cmd_SwarmToggleMenu, ADMFLAG_ROOT, "sm_swarmtogglemenu - Open swarm toggle menu");

	HookEvent("triggered_car_alarm", Event_CarAlarm);
}

public Action Cmd_Swarm(int client, int args) {
	if(args == 0) {
		SwarmUser(-1, hSwarmDefaultRange.IntValue);
		ReplyToCommand(client, "Swarming random player at %d radius.", hSwarmDefaultRange.IntValue);
	}else{
		char arg1[32], arg2[32];
		GetCmdArg(1, arg1, sizeof(arg1));
		GetCmdArg(2, arg2, sizeof(arg2));

		int range = StringToInt(arg2);
		if(range <= 0) range = hSwarmDefaultRange.IntValue;

		char target_name[MAX_TARGET_LENGTH];
		int target_list[1], target_count;
		bool tn_is_ml;

		if ((target_count = ProcessTargetString(
				arg1,
				client,
				target_list,
				1,
				COMMAND_FILTER_ALIVE, /* Only allow alive players */
				target_name,
				sizeof(target_name),
				tn_is_ml)) <= 0)
		{
			/* This function replies to the admin with a failure message */
			ReplyToTargetError(client, target_count);
			return Plugin_Handled;
		}
		SwarmUser(GetClientUserId(target_list[0]), range);
		ReplyToCommand(client, "Swarming victim %N. Radius: %d", target_list[0], range);
	}
	return Plugin_Handled;
}

public Action Cmd_SwarmToggle(int client, int args) {
	//SwarmTarget, SwarmRadius
	if(args == 0) {
		ReplyToCommand(client, "Usage: sm_rushtoggle <player> [radius]");
	}else{
		char arg1[32], arg2[32];
		GetCmdArg(1, arg1, sizeof(arg1));
		GetCmdArg(2, arg2, sizeof(arg2));

		if(StrEqual(arg1, "disable", true) || StrEqual(arg1, "x", true)) {
			SwarmTarget = -1;
			SwarmRadius = hSwarmDefaultRange.IntValue;
			ReplyToCommand(client, "Deactivated swarm toggle.");
			CloseHandle(timer);
			return Plugin_Handled;
		}

		int range = StringToInt(arg2);
		if(range <= 0) range = hSwarmDefaultRange.IntValue;
		SwarmRadius = range;

		char target_name[MAX_TARGET_LENGTH];
		int target_list[1], target_count;
		bool tn_is_ml;

		if ((target_count = ProcessTargetString(
				arg1,
				client,
				target_list,
				1,
				COMMAND_FILTER_ALIVE, 
				target_name,
				sizeof(target_name),
				tn_is_ml)) <= 0)
		{
			ReplyToTargetError(client, target_count);
			return Plugin_Handled;
		}
		if(target_list[0] == SwarmTarget) {
			SwarmTarget = -1;
			SwarmRadius = hSwarmDefaultRange.IntValue;
			ReplyToCommand(client, "Deactivated swarm toggle.");
			CloseHandle(timer);
			timer = INVALID_HANDLE;
		}else{
			SwarmTarget = GetClientUserId(target_list[0]);
			SwarmUser(GetClientUserId(target_list[0]), range);
			ReplyToCommand(client, "Now continously swarming victim %N. Radius: %d", target_list[0], range);
			if(timer == INVALID_HANDLE)
				timer = CreateTimer(1.0, Timer_Swarm, _, TIMER_REPEAT);
		}
	}
	return Plugin_Handled;
}
public Action Cmd_SwarmMenu(int client, int args) {
	Menu menu = new Menu(Handle_SwarmMenu);
	menu.SetTitle("Swarm a Player");
	char name[32], idStr[4];
	for(int id = 1; id < MaxClients; id++) {
		if(IsClientConnected(id) && IsClientInGame(id) && IsPlayerAlive(id) && GetClientTeam(id) == 2) {
			GetClientName(id, name, sizeof(name));
			Format(idStr, sizeof(idStr), "%d", GetClientUserId(id));
			menu.AddItem(idStr, name);
		}
	}
	menu.ExitButton = true;
	menu.Display(client, 0);
}
public Action Cmd_SwarmToggleMenu(int client, int args) {
	Menu menu = new Menu(Handle_SwarmMenuToggle);
	menu.SetTitle("Toggle Swarm On Player");
	menu.AddItem("x", "Disable");
	char name[32], idStr[3];
	for(int id = 1; id < MaxClients; id++) {
		if(IsClientConnected(id) && IsClientInGame(id) && IsPlayerAlive(id) && GetClientTeam(id) == 2) {
			GetClientName(id, name, sizeof(name));
			Format(idStr, sizeof(idStr), "%d", GetClientUserId(id));
			menu.AddItem(idStr, name);
		}
	}
	menu.ExitButton = true;
	menu.Display(client, 0);
}

public int Handle_SwarmMenu(Menu menu, MenuAction action, int client, int index)
{
	/* If an option was selected, tell the client about the item. */
	if (action == MenuAction_Select)
	{
		char info[4];
		menu.GetItem(index, info, sizeof(info));
		int userid = StringToInt(info);
		SwarmUser(userid, hSwarmDefaultRange.IntValue);
		PrintToChat(client, "Swarming player #%d with radius %d", userid, hSwarmDefaultRange.IntValue);
		Cmd_SwarmMenu(client, 0);
	} else if (action == MenuAction_End) {
		delete menu;
	}
}

public int Handle_SwarmMenuToggle(Menu menu, MenuAction action, int client, int index)
{
	/* If an option was selected, tell the client about the item. */
	if (action == MenuAction_Select)
	{
		char info[4];
		menu.GetItem(index, info, sizeof(info));
		if(StrEqual(info, "x", true)) {
			SwarmTarget = -1;
			SwarmRadius = hSwarmDefaultRange.IntValue;
			PrintToChat(client, "Disabled swarm toggle.", SwarmTarget, SwarmRadius);
			CloseHandle(timer);
			timer = INVALID_HANDLE;
		}else{
			int clickedUser = StringToInt(info);
			if(clickedUser != SwarmTarget) {
				SwarmTarget = clickedUser;
				int clientID = GetClientOfUserId(SwarmTarget);
				PrintToChat(client, "Toggled swarm on for %N (#%d). Radius: %d", clientID, SwarmTarget, SwarmRadius);
				if(timer == INVALID_HANDLE)
					timer = CreateTimer(1.0, Timer_Swarm, _, TIMER_REPEAT);
			}else{
				SwarmTarget = -1;
				SwarmRadius = hSwarmDefaultRange.IntValue;
				ReplyToCommand(client, "Deactivated swarm toggle.");
				CloseHandle(timer);
				timer = INVALID_HANDLE;
			}
		}
	} else if (action == MenuAction_End) {
		delete menu;
	}
}

public Action Timer_Swarm(Handle timerH, any data) {
	if(SwarmTarget >= 0) {
		SwarmUser(SwarmTarget, SwarmRadius);
		return Plugin_Continue;
	}else {
		return Plugin_Stop;
	}
}


void SwarmUser(int clientUserId, int range) {
	L4D2_RunScript("RushVictim(GetPlayerFromUserID(%d), %d)", clientUserId, range);
}

public void Event_CarAlarm(Event event, const char[] name, bool dontBroadcast) {
	int user = event.GetInt("userid");
	SwarmUser(user, hSwarmDefaultRange.IntValue);
}