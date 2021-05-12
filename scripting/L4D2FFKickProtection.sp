#pragma semicolon 1
#pragma newdecls required


#define PLUGIN_NAME "L4D2 FF Kick Protection"
#define PLUGIN_DESCRIPTION "Prevents assholes from friendly firing when being kicked."
#define PLUGIN_AUTHOR "jackzmc"
#define PLUGIN_VERSION "1.0"
#define PLUGIN_URL ""

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

static int disableFFClient, ffDamageCount; //client to disable FF for
static ConVar forceKickFFThreshold;

public Plugin myinfo = {
	name = PLUGIN_NAME, 
	author = PLUGIN_AUTHOR, 
	description = PLUGIN_DESCRIPTION, 
	version = PLUGIN_VERSION, 
	url = PLUGIN_URL
};

public void OnPluginStart() {
	EngineVersion g_Game = GetEngineVersion();
	if(g_Game != Engine_Left4Dead && g_Game != Engine_Left4Dead2)
	{
		SetFailState("This plugin is for L4D/L4D2 only.");	
	}
	AddCommandListener(VoteStart, "callvote");
	HookUserMessage(GetUserMessageId("VotePass"), VotePassFail);
	HookUserMessage(GetUserMessageId("VoteFail"), VotePassFail);

	forceKickFFThreshold = CreateConVar("sm_votekick_force_threshold","30.0","The threshold of amount of FF to then automatically kick.\n0: Any attempted damage\n -1: No auto kick.\n>0: When FF count > this", FCVAR_NONE, true, -1.0);
}

public void OnClientPutInServer(int client) {
	int team = GetClientTeam(client);
	if(team == 2) {
		SDKHook(client, SDKHook_OnTakeDamageAlive, OnTakeDamage);
	}
}

public void Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast) {
	if(!event.GetBool("disconnect")) {
		int team = event.GetInt("team");
		int userid = GetClientOfUserId(event.GetInt("userid"));
		if(team == 2) {
			SDKHook(userid, SDKHook_OnTakeDamageAlive, OnTakeDamage);
			//add new hook
		}else{
			SDKUnhook(userid, SDKHook_OnTakeDamageAlive, OnTakeDamage);
		}
	}
}

public Action VoteStart(int client, const char[] command, int argc) {
	if(GetClientCount(true) == 0 || client == 0) return Plugin_Handled; //prevent votes while server is empty or if server tries calling vote
	if(argc >= 1) {
		char issue[32];
		char caller[32];

		GetCmdArg(1, issue, sizeof(issue));
		Format(caller, sizeof(caller), "%N", client);

		if(StrEqual(issue, "Kick", false)) {
			char option[32];
			GetCmdArg(2, option, sizeof(option));
			if(strlen(option) < 1) { //empty userid/console can't call votes
				int target = GetClientOfUserId(StringToInt(option));
				AdminId callerAdmin = GetUserAdmin(client);
				AdminId targetAdmin = GetUserAdmin(target);
				if(callerAdmin != INVALID_ADMIN_ID && targetAdmin == INVALID_ADMIN_ID || GetAdminImmunityLevel(targetAdmin) < GetAdminImmunityLevel(callerAdmin)) {
					PrintToChat(target, "%N has attempted to vote kick you.", client);
					//possibly plugin_stop
					return Plugin_Handled;
				}
				if(GetClientTeam(target) == 2) {
					disableFFClient = target;
					ffDamageCount = 0;
				}
				PrintToServer("VOTE KICK STARTED | Target=%N | Caller=%N", issue, target, client);
				return Plugin_Continue;
			}	
			//Kick vote started
		}
	}	
	return Plugin_Continue; //if it wasn't handled up there I would start panicking
}

public Action VotePassFail(UserMsg msg_id, BfRead msg, const int[] players, int playersNum, bool reliable, bool init) {
	disableFFClient = -1;
	ffDamageCount = 0;
}	

public Action OnTakeDamage(int victim,  int& attacker, int& inflictor, float& damage, int& damagetype, int& weapon, float damageForce[3], float damagePosition[3]) {
	if(disableFFClient == attacker && damage > 0.0 && victim > 0 && victim <= MaxClients && GetClientTeam(victim) == 2) {
		if(forceKickFFThreshold.IntValue > -1 && ffDamageCount > 0.0) {
			//auto kick
			if(ffDamageCount > forceKickFFThreshold.FloatValue) {
				KickClient(disableFFClient, "Kicked for excessive friendly fire");
			}
		}
		return Plugin_Stop;
	} 
	return Plugin_Continue;
}
