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
bool lateLoaded, IsFinaleEnding;
int iJoinTime[MAXPLAYERS+1];
float playerTotalDamageFF[MAXPLAYERS+1];
int lastFF[MAXPLAYERS+1];

ConVar hForgivenessTime, hBanTime, hThreshold, hJoinTime;

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

	//AutoExecConfig(true, "l4d2_tkstopper");

	HookEvent("finale_vehicle_ready", Event_FinaleVehicleReady);

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

//TODO: Autopunish on troll instead of ban. Activate troll that does 0 damage from their guns & xswarm

public Action Event_OnTakeDamage(int victim,  int& attacker, int& inflictor, float& damage, int& damagetype, int& weapon, float damageForce[3], float damagePosition[3]) {
	if(damage > 0.0 && damagetype & (DMG_BLAST|DMG_BURN|DMG_BLAST_SURFACE) == 0 && GetClientTeam(victim) == 2 && GetClientTeam(attacker) == 2 && attacker != victim) {
		//Allow friendly firing BOTS that aren't idle players:
		if(IsFakeClient(victim) && GetEntProp(attacker, Prop_Send, "m_humanSpectatorUserID") == 0) {
			return Plugin_Continue;
		}
		int time = GetTime();
		if(time - lastFF[attacker] > hForgivenessTime.IntValue) {
			playerTotalDamageFF[attacker] = 0.0;
		}
		playerTotalDamageFF[attacker] += damage;
		lastFF[attacker] = time;
		if(GetUserAdmin(attacker) == INVALID_ADMIN_ID) {
			if(playerTotalDamageFF[attacker] > hThreshold.IntValue) {
				LogMessage("[NOTICE] Banning %N for excessive FF (%f HP) for %d minutes.", attacker, playerTotalDamageFF[attacker], hBanTime.IntValue);
				NotifyAllAdmins("[Notice] Banning %N for excessive FF (%f HP) for %d minutes.", attacker, playerTotalDamageFF[attacker], hBanTime.IntValue);
				BanClient(attacker, hBanTime.IntValue, BANFLAG_AUTO | BANFLAG_AUTHID, "Excessive FF", "Excessive Friendly Fire", "TKStopper");
				return Plugin_Stop;
			}

			if(IsFinaleEnding || GetTime() - iJoinTime[attacker] <= hJoinTime.IntValue / 60000) {
				return Plugin_Stop;
			}else{
				SDKHooks_TakeDamage(attacker, attacker, attacker, damage / 3.0);
				damage /= 2.0;
			}
			return Plugin_Stop;
		}
	}
	return Plugin_Continue;
}
