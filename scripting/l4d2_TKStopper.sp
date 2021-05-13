#pragma semicolon 1
#pragma newdecls required

//#define DEBUG

#define PLUGIN_VERSION "1.0"
#define FF_BAN_THRESHOLD 100.0
#define FF_BAN_JOIN_MINUTES_THRESHOLD 2
#define FF_BAN_MINUTES 60

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <jutils>
#include <left4dhooks>

bool lateLoaded, IsFinaleEnding, isPlayerTroll[MAXPLAYERS+1];
int iJoinTime[MAXPLAYERS+1];
float playerTotalDamageFF[MAXPLAYERS+1];
int lastFF[MAXPLAYERS+1];

ConVar hForgivenessTime, hBanTime, hThreshold, hJoinTime, hAction;

//TODO: Toggle ban, kick, delayed ban, etc

public Plugin myinfo = 
{
	name =  "TK Stopper", 
	author = "jackzmc", 
	description = "", 
	version = PLUGIN_VERSION, 
	url = ""
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
	if(late) {
		lateLoaded = true;
	}
} 

public void OnPluginStart()
{
	EngineVersion g_Game = GetEngineVersion();
	if(g_Game != Engine_Left4Dead && g_Game != Engine_Left4Dead2)
	{
		SetFailState("This plugin is for L4D/L4D2 only.");	
	}

	hForgivenessTime = CreateConVar("l4d2_tk_forgiveness_time", "15", "The minimum amount of time to pass (in seconds) where a player's previous accumulated FF is forgiven");
	hBanTime = CreateConVar("l4d2_tk_bantime", "60", "How long in minutes should a player be banned for? 0 for permanently");
	hThreshold = CreateConVar("l4d2_tk_ban_ff_threshold", "75.0", "How much damage does a player need to do before being instantly banned");
	hJoinTime = CreateConVar("l4d2_tk_ban_join_time", "2", "Upto how many minutes should any new player be subjected to instant bans on any FF");
	hAction = CreateConVar("l4d2_tk_action", "3", "How should the TK be punished?\n0 = No action (No message), 1 = Kick, 2 = Instant Ban, 3 = Ban on disconnect");

	//AutoExecConfig(true, "l4d2_tkstopper");

	HookEvent("finale_vehicle_ready", Event_FinaleVehicleReady);
	HookEvent("player_disconnect", Event_PlayerDisconnect);

	if(lateLoaded) {
		for(int i = 1; i <= MaxClients; i++) {
			if(IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2) {
				SDKHook(i, SDKHook_OnTakeDamage, Event_OnTakeDamage);
			}
		}
	}
}

public void Event_FinaleVehicleReady(Event event, const char[] name, bool dontBroadcast) {
	IsFinaleEnding = true;
}

public void OnMapEnd() {
	IsFinaleEnding = false;
}

public void OnClientPutInServer(int client) {
	iJoinTime[client] = GetTime();
	SDKHook(client, SDKHook_OnTakeDamage, Event_OnTakeDamage);
}

public void OnClientDisconnect(int client) {
	playerTotalDamageFF[client] = 0.0;
}

public void Event_PlayerDisconnect(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(client > 0 && isPlayerTroll[client]) {
		BanClient(client, hBanTime.IntValue, BANFLAG_AUTO | BANFLAG_AUTHID, "Excessive FF", "Excessive Friendly Fire", "TKStopper");
	}
	isPlayerTroll[client] = false;
}

//TODO: Autopunish on troll instead of ban. Activate troll that does 0 damage from their guns & xswarm

public Action Event_OnTakeDamage(int victim,  int& attacker, int& inflictor, float& damage, int& damagetype, int& weapon, float damageForce[3], float damagePosition[3]) {
	if(damage > 0.0 && damagetype & (DMG_BLAST|DMG_BURN|DMG_BLAST_SURFACE) == 0 && victim <= MaxClients && attacker <= MaxClients && attacker > 0 && victim > 0) {
		if(GetClientTeam(victim) != 2 || GetClientTeam(attacker) != 2 || attacker == victim) return Plugin_Continue;
		//Allow friendly firing BOTS that aren't idle players:
		//if(IsFakeClient(victim) && !HasEntProp(attacker, Prop_Send, "m_humanSpectatorUserID") || GetEntProp(attacker, Prop_Send, "m_humanSpectatorUserID") == 0) return Plugin_Continue;
		if(isPlayerTroll[attacker]) return Plugin_Stop;
		int time = GetTime();
		if(time - lastFF[attacker] > hForgivenessTime.IntValue) {
			playerTotalDamageFF[attacker] = 0.0;
		}
		playerTotalDamageFF[attacker] += damage;
		lastFF[attacker] = time;
		if(GetUserAdmin(attacker) == INVALID_ADMIN_ID) {
			if(playerTotalDamageFF[attacker] > hThreshold.IntValue && !IsFinaleEnding) {
				LogMessage("[NOTICE] Banning %N for excessive FF (%f HP) for %d minutes.", attacker, playerTotalDamageFF[attacker], hBanTime.IntValue);
				NotifyAllAdmins("[Notice] Banning %N for excessive FF (%f HP) for %d minutes.", attacker, playerTotalDamageFF[attacker], hBanTime.IntValue);
				if(hAction.IntValue == 1) 
					KickClient(attacker, "Excessive FF");
				else if(hAction.IntValue == 2)
					BanClient(attacker, hBanTime.IntValue, BANFLAG_AUTO | BANFLAG_AUTHID, "Excessive FF", "Excessive Friendly Fire", "TKStopper");
				else if(hAction.IntValue == 3)
					isPlayerTroll[attacker] = true;
				return Plugin_Stop;
			}
			//If the amount of MS is <= join time threshold * 60000 ms then cancel
			if(L4D_IsInFirstCheckpoint(victim) || L4D_IsInLastCheckpoint(victim) || time - iJoinTime[attacker] <= hJoinTime.IntValue * 60000) {
				return Plugin_Stop;
			}else {
				SDKHooks_TakeDamage(attacker, attacker, attacker, IsFinaleEnding ? damage * 2.0 : damage / 1.9);
				damage = IsFinaleEnding ? 0.0 : damage / 2.1;
				return Plugin_Changed;
			}
		}
	}
	return Plugin_Continue;
}
