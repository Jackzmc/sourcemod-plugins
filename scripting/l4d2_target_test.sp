#pragma semicolon 1
#pragma newdecls required

//#define DEBUG

#define PLUGIN_VERSION "1.0"
#define GAMEDATA			"l4d_target_override"

#include <sourcemod>
#include <sdktools>
#include <left4dhooks>

enum L4D2Infected
{
	L4D2Infected_None = 0,
	L4D2Infected_Smoker = 1,
	L4D2Infected_Boomer = 2,
	L4D2Infected_Hunter = 3,
	L4D2Infected_Spitter = 4,
	L4D2Infected_Jockey = 5,
	L4D2Infected_Charger = 6,
	L4D2Infected_Witch = 7,
	L4D2Infected_Tank = 8
}

public Plugin myinfo = 
{
	name =  "L4D2 target poo", 
	author = "jackzmc", 
	description = "", 
	version = PLUGIN_VERSION, 
	url = ""
};

bool g_bIsVictim[MAXPLAYERS+1];
Handle g_hDetour;

public void OnPluginStart()
{
	EngineVersion g_Game = GetEngineVersion();
	if(g_Game != Engine_Left4Dead2)
	{
		SetFailState("This plugin is for L4D2 only.");	
	}


	RegAdminCmd("sm_set_victim", Cmd_SetVictim, ADMFLAG_CHEATS);

	HookEvent("player_death", Event_PlayerDeath);
}

public void OnPluginEnd()
{
}

public Action Cmd_SetVictim(int client, int args) {
	if(args == 0) {
		ReplyToCommand(client, "Please enter a player to target");
	}else{
		char arg1[32];
		GetCmdArg(1, arg1, sizeof(arg1));

		char target_name[MAX_TARGET_LENGTH];
		int target_list[1], target_count;
		bool tn_is_ml;

		if ((target_count = ProcessTargetString(
				arg1,
				client,
				target_list,
				MAXPLAYERS,
				COMMAND_FILTER_ALIVE, /* Only allow alive players */
				target_name,
				sizeof(target_name),
				tn_is_ml)) <= 0)
		{
			/* This function replies to the admin with a failure message */
			ReplyToTargetError(client, target_count);
			return Plugin_Handled;
		}
		for(int i = 0; i < target_count; i++) {
			int victim = target_list[i];
			//g_iSITargets
			g_bIsVictim[victim] = !g_bIsVictim[victim];
			ReplyToCommand(client, "Successfully toggled %N victim status to: %b", victim, g_bIsVictim[victim]);
			ShowActivity(client, "toggled special infected victim status for %N to %b", victim, g_bIsVictim[victim]);
		}
	}
	return Plugin_Handled;
}

static int b_attackerTarget[MAXPLAYERS+1];
public Action L4D2_OnChooseVictim(int attacker, int &curTarget) {
	// =========================
	// OVERRIDE VICTIM
	// =========================
	L4D2Infected class = view_as<L4D2Infected>(GetEntProp(attacker, Prop_Send, "m_zombieClass"));
	if(class != L4D2Infected_Tank) {
		int existingTarget = GetClientOfUserId(b_attackerTarget[attacker]);
		if(existingTarget > 0) {
			curTarget = existingTarget;
			return Plugin_Changed;
		}

		float closestDistance, survPos[3], spPos[3];
		GetClientAbsOrigin(attacker, spPos); 
		int closestClient = -1;
		for(int i = 1; i <= MaxClients; i++) {
			if(g_bIsVictim[i] && IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2) {
				GetClientAbsOrigin(i, survPos);
				float dist = GetVectorDistance(survPos, spPos, true);
				if(closestClient == -1 || dist < closestDistance) {
					closestDistance = dist;
					closestClient = i;
				}
			}
		}
		
		if(closestClient > 0) {
			PrintToConsoleAll("Attacker %N new target: %N", attacker, closestClient);
			b_attackerTarget[attacker] = GetClientUserId(closestClient);
			curTarget = closestClient;
			return Plugin_Changed;
		}
	}
	return Plugin_Continue;
}

public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	b_attackerTarget[client] = 0;
}

public void OnClientDisconnect(int client) {
	b_attackerTarget[client] = 0;
}