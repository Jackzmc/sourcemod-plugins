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

static int disableFFClient; //client to disable FF for
static float  ffDamageDone; //amount of damage offending user has attempted
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

	forceKickFFThreshold = CreateConVar("sm_votekick_force_threshold","0","The threshold of damage where the offending player is just immediately kicked. 0 -> Any attempted damage, -1 -> No auto kick.", FCVAR_NONE, true, -1.0);

	//HookEvent("vote_started",Event_VoteStarted);
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

		if(StrEqual(issue, "Kick", true)) {
			char option[32];
			GetCmdArg(2, option, sizeof(option));
			if(strlen(option) < 1) { //empty userid/console can't call votes
				int target = GetClientOfUserId(StringToInt(option));
				int team = GetClientTeam(target);
				if(team == 2) {
					disableFFClient = target;
					ffDamageDone = -1.0;
				}
				return Plugin_Handled;
			}	
			//Kick vote started
			PrintToServer("KICK VOTE STARTED | Issue=%s Option=%s Caller=%N", issue, option, client);
		}
	}	
	return Plugin_Handled; //if it wasn't handled up there I would start panicking
}

public Action VotePassFail(UserMsg msg_id, BfRead msg, const int[] players, int playersNum, bool reliable, bool init) {
	disableFFClient = -1;
	ffDamageDone = -1.0;
}	

public Action OnTakeDamage(int victim,  int& attacker, int& inflictor, float& damage, int& damagetype, int& weapon, float damageForce[3], float damagePosition[3]) {
	if(disableFFClient == attacker) {
		if(ffDamageDone == -1) {
			PrintToServer("Player in vote to be kicked has done ff damage");
		}
		ffDamageDone = damage;
		if(forceKickFFThreshold.FloatValue > -1.0) {
			//auto kick
			if(forceKickFFThreshold.FloatValue == 0.0) {
				KickClient(disableFFClient, "Kicked for excessive friendly fire");
			}else if(FloatCompare(ffDamageDone, forceKickFFThreshold.FloatValue) == 1) {
				KickClient(disableFFClient, "Kicked for excessive friendly fire");
			}
		}
		damage = 0.0;
		return Plugin_Handled;
	} 
	return Plugin_Continue;
}
