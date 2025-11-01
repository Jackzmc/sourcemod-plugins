#pragma semicolon 1
#pragma newdecls required

#define ANTI_ADMIN_KICK_MIN_TIME 120 // The number of seconds after joining where vote kicking an admin, kicks the caller
#define PLUGIN_VERSION "1.1"

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

static int disableFFClient = -1, ffDamageCount; //client to disable FF for
static ConVar forceKickFFThreshold;

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


int iJoinTime[MAXPLAYERS+1];
public void OnClientPutInServer(int client) {
	int team = GetClientTeam(client);
	if(team == 2) {
		SDKHook(client, SDKHook_OnTakeDamageAlive, OnTakeDamage);
	}
	iJoinTime[client] = GetTime();
}

public void OnClientDisconnect(int client) {
	if(disableFFClient == client) {
		disableFFClient = -1;
		ffDamageCount = 0;
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
	if(!IsClientInGame(client)) {
		PrintToServer("Preventing vote from user not in game: %N", client);
		return Plugin_Handled;
	}
	if(GetClientCount(true) == 0 || client == 0 || client >= MaxClients) return Plugin_Handled; //prevent votes while server is empty or if server tries calling vote
	if(argc >= 1) {
		char issue[32];

		GetCmdArg(1, issue, sizeof(issue));

		if(StrEqual(issue, "Kick", false)) {
			char option[32];
			GetCmdArg(2, option, sizeof(option));

			if(strlen(option) > 1) { //empty userid/console can't call votes
				int target = GetClientOfUserId(StringToInt(option));
				if(target <= 0 || target >= MaxClients || !IsClientInGame(target)) return Plugin_Continue; //invalid, pass it through
				AdminId targetAdmin = GetUserAdmin(target);
				bool isCallerAdmin = CheckCommandAccess(client, "sm_kick", ADMFLAG_KICK);
				bool isTargetAdmin = CheckCommandAccess(target, "sm_kick", ADMFLAG_KICK);
				PrintToServer("Caller Admin: %b | Target admin: %b", isCallerAdmin, isTargetAdmin);

				//Only run if vote is against an admin
				if(isTargetAdmin) { 
					for(int i = 1; i <= MaxClients; i++) {
						if(target != i && IsClientInGame(i) && GetUserAdmin(i) != INVALID_ADMIN_ID) {
							PrintToChat(i, "%N attempted to vote-kick admin %N", client, target);
						}
					}
					LogAction(client, target, "\"%L\" attemped to vote kick admin \"%L\"", client, target);

					// Kick player if they are not an admin and just recently joined.
					// Else, just tell the target
					if(!isCallerAdmin && GetTime() - iJoinTime[client] <= ANTI_ADMIN_KICK_MIN_TIME) {
						if(GetClientTeam(target) == 2) {
							KickClient(client, "No.");
							PrintToChat(target, "%N has attempted to vote kick you and was kicked.", client);
						} else {
							PrintToChat(client, "%N is an admin and cannot be vote kicked", target);
							PrintToChat(target, "%N has attempted to kick you while you were afk.", client);
						}
					} else {
						PrintToChat(target, "%N has attempted to vote kick you.", client);
					}

					// TODO: remove debug
					targetAdmin.GetUsername(option, sizeof(option));
					PrintToServer("debug: admin immunity is %d. username: %s", targetAdmin.ImmunityLevel, option);
					PrintToServer("ADMIN VOTE KICK BLOCKED | Target=%N | Caller=%N", target, client);
					return Plugin_Handled;
				} else if(isCallerAdmin) {
					PrintToServer("Vote kick by admin, instantly passing");
					for(int i = 1; i <= MaxClients; i++) {
						if(IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) == GetClientTeam(target)) {
							ClientCommand(i, "vote Yes");
						}
					}
				}

				if(GetTime() - iJoinTime[client] <= ANTI_ADMIN_KICK_MIN_TIME) {
					PrintToServer("Preventing kick vote from user who recently joined", client);
					PrintToConsoleAll("Vote blocked from %N: recently joined", client);

					return Plugin_Handled;
				}

				// Disable target from doing FF while they are pending being vote kicked
				if(GetClientTeam(target) == 2) {
					disableFFClient = target;
					ffDamageCount = 0;
				}
				
				PrintToServer("VOTE KICK STARTED | Target=%N | Caller=%N", target, client);
				return Plugin_Continue;
			}	
		}
	}	
	return Plugin_Continue;
}

public Action VotePassFail(UserMsg msg_id, BfRead msg, const int[] players, int playersNum, bool reliable, bool init) {
	// Vote failed, re-enable ff for target
	disableFFClient = -1;
	ffDamageCount = 0;
	return Plugin_Continue;
}	

public Action OnTakeDamage(int victim,  int& attacker, int& inflictor, float& damage, int& damagetype, int& weapon, float damageForce[3], float damagePosition[3]) {
	if(disableFFClient == attacker && damage > 0.0 && victim > 0 && victim <= MaxClients && GetClientTeam(victim) == 2) {
		if(forceKickFFThreshold.IntValue > -1 && ffDamageCount > 0.0) {
			//auto kick
			if(ffDamageCount > forceKickFFThreshold.FloatValue) {
				BanClient(disableFFClient, 0, 0, "Kicked for excessive friendly fire", "Dick-Be-Gone", "kickProtection");
			}
		}
		return Plugin_Handled;
	} 
	return Plugin_Continue;
}
