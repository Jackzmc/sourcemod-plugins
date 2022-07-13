#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "1.0"

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

static int disableFFClient, ffDamageCount; //client to disable FF for
static ConVar forceKickFFThreshold;

static int voteController;

public Plugin myinfo = {
	name = "L4D2 FF Kick Protection", 
	author = "jackzmc", 
	description = "Prevents friendly firing from players being voted off and admins from being kicked", 
	version = PLUGIN_VERSION, 
	url = "https://github.com/Jackzmc/sourcemod-plugins"
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

public void OnMapStart() {
	voteController = FindEntityByClassname(-1, "vote_controller");
}

int iJoinTime[MAXPLAYERS+1];
public void OnClientPutInServer(int client) {
	int team = GetClientTeam(client);
	if(team == 2) {
		SDKHook(client, SDKHook_OnTakeDamageAlive, OnTakeDamage);
	}
	iJoinTime[client] = GetTime();
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
	if(!IsClientInGame(client)) {
		PrintToServer("Preventing vote from user not in game: %N", client);
		return Plugin_Handled;
	}
	if(GetClientCount(true) == 0 || client == 0 || client >= MaxClients) return Plugin_Handled; //prevent votes while server is empty or if server tries calling vote
	if(argc >= 1) {
		static char issue[32];

		GetCmdArg(1, issue, sizeof(issue));

		if(StrEqual(issue, "Kick", false)) {
			static char option[32];
			GetCmdArg(2, option, sizeof(option));

			if(strlen(option) > 1) { //empty userid/console can't call votes
				int target = GetClientOfUserId(StringToInt(option));
				if(target <= 0 || target >= MaxClients || !IsClientConnected(target)) return Plugin_Continue; //invalid, pass it through
				if(client <= 0 || client >= MaxClients || !IsClientConnected(client)) return Plugin_Continue; //invalid, pass it through
				AdminId callerAdmin = GetUserAdmin(client);
				AdminId targetAdmin = GetUserAdmin(target);
				if(targetAdmin != INVALID_ADMIN_ID) { //Only run if vote is against an admin
					for(int i = 1; i <= MaxClients; i++) {
						if(target != i && IsClientConnected(i) && IsClientInGame(i) && GetUserAdmin(i) != INVALID_ADMIN_ID) {
							PrintToChat(i, "%N attempted to vote-kick %N", client, target);
						}
					}
					if(callerAdmin == INVALID_ADMIN_ID && GetTime() - iJoinTime[client] <= 120) {
						KickClient(client, "No.");
						PrintToChat(target, "%N has attempted to vote kick you and was kicked.", client);
					} else {
						PrintToChat(target, "%N has attempted to vote kick you.", client);
					}
					return Plugin_Handled;
				} else if(callerAdmin != INVALID_ADMIN_ID && targetAdmin == INVALID_ADMIN_ID && IsValidEntity(voteController)) {
					PrintToServer("Vote kick by admin, instantly passing");
					SetEntProp(voteController, Prop_Send, "m_votesYes", 32);
					for(int i = 1; i <= MaxClients; i++) {
						if(IsClientConnected(i) && !IsFakeClient(i) && GetClientTeam(i) == GetClientTeam(target)) {
							ClientCommand(i, "vote Yes");
						}
					}
				}
				if(GetClientTeam(target) == 2) {
					disableFFClient = target;
					ffDamageCount = 0;
				}
				PrintToServer("VOTE KICK STARTED | Target=%N | Caller=%N", issue, target, client);
				return Plugin_Continue;
			}	
		}
	}	
	return Plugin_Continue;
}

public Action VotePassFail(UserMsg msg_id, BfRead msg, const int[] players, int playersNum, bool reliable, bool init) {
	disableFFClient = -1;
	ffDamageCount = 0;
	return Plugin_Continue;
}	

public Action OnTakeDamage(int victim,  int& attacker, int& inflictor, float& damage, int& damagetype, int& weapon, float damageForce[3], float damagePosition[3]) {
	if(disableFFClient == attacker && damage > 0.0 && victim > 0 && victim <= MaxClients && GetClientTeam(victim) == 2) {
		if(forceKickFFThreshold.IntValue > -1 && ffDamageCount > 0.0) {
			//auto kick
			if(ffDamageCount > forceKickFFThreshold.FloatValue) {
				BanClient(disableFFClient, 0, 0, "Kicked for excessive friendly fire", "Dick-Be-Gone", "noFF");
			}
		}
		return Plugin_Handled;
	} 
	return Plugin_Continue;
}
