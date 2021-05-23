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

bool lateLoaded, IsFinaleEnding, isPlayerTroll[MAXPLAYERS+1], isImmune[MAXPLAYERS+1], isUnderAttack[MAXPLAYERS+1];
int iJoinTime[MAXPLAYERS+1];
float playerTotalDamageFF[MAXPLAYERS+1];
int lastFF[MAXPLAYERS+1];

ConVar hForgivenessTime, hBanTime, hThreshold, hJoinTime, hAction;

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

	HookEvent("charger_carry_start", Event_ChargerCarry);
	HookEvent("charger_carry_end", Event_ChargerCarry);

	HookEvent("lunge_pounce", Event_HunterPounce);
	HookEvent("pounce_end", Event_HunterPounce);
	HookEvent("pounce_stopped", Event_HunterPounce);

	HookEvent("choke_start", Event_SmokerChoke);
	HookEvent("choke_end", Event_SmokerChoke);
	HookEvent("choke_stopped", Event_SmokerChoke);

	HookEvent("jockey_ride", Event_JockeyRide);
	HookEvent("jockey_ride_end", Event_JockeyRide);


	RegAdminCmd("sm_ignore", Command_IgnorePlayer, ADMFLAG_KICK, "Makes a player immune for any anti trolling detection for a session");

	if(lateLoaded) {
		for(int i = 1; i <= MaxClients; i++) {
			if(IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2) {
				SDKHook(i, SDKHook_OnTakeDamage, Event_OnTakeDamage);
			}
		}
	}
}

///////////////////////////////////////////////////////////////////////////////
// Special Infected Events 
///////////////////////////////////////////////////////////////////////////////
public Action Event_ChargerCarry(Event event, const char[] name, bool dontBroadcast) {
	int victim = GetClientOfUserId(event.GetInt("victim"));
	if(victim) {
		if(StrEqual(name, "charger_carry_start")) {
			isUnderAttack[victim] = true;
		}else{
			isUnderAttack[victim] = false;
		}
	}
}

public Action Event_HunterPounce(Event event, const char[] name, bool dontBroadcast) {
	int victim = GetClientOfUserId(event.GetInt("victim"));
	if(victim) {
		if(StrEqual(name, "lunge_pounce")) {
			isUnderAttack[victim] = true;
		}else{
			isUnderAttack[victim] = false;
		}
	}
}

public Action Event_SmokerChoke(Event event, const char[] name, bool dontBroadcast) {
	int victim = GetClientOfUserId(event.GetInt("victim"));
	if(victim) {
		if(StrEqual(name, "choke_start")) {
			isUnderAttack[victim] = true;
		}else{
			isUnderAttack[victim] = false;
		}
	}
}
public Action Event_JockeyRide(Event event, const char[] name, bool dontBroadcast) {
	int victim = GetClientOfUserId(event.GetInt("victim"));
	if(victim) {
		if(StrEqual(name, "jockey_ride")) {
			isUnderAttack[victim] = true;
		}else{
			isUnderAttack[victim] = false;
		}
	}
}
///////////////////////////////////////////////////////////////////////////////
// Misc events
///////////////////////////////////////////////////////////////////////////////
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
	isUnderAttack[client] = false;
}

public void Event_PlayerDisconnect(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(client > 0 && isPlayerTroll[client]) {
		BanClient(client, hBanTime.IntValue, BANFLAG_AUTO | BANFLAG_AUTHID, "Excessive FF", "Excessive Friendly Fire", "TKStopper");
	}
	isPlayerTroll[client] = false;
}

public Action Event_OnTakeDamage(int victim,  int& attacker, int& inflictor, float& damage, int& damagetype, int& weapon, float damageForce[3], float damagePosition[3]) {
	if(damage > 0.0 && victim <= MaxClients && attacker <= MaxClients && attacker > 0 && victim > 0) {
		if(GetUserAdmin(attacker) != INVALID_ADMIN_ID || isImmune[attacker] || IsFakeClient(attacker)) return Plugin_Continue;
		if(GetClientTeam(victim) != 2 || GetClientTeam(attacker) != 2 || attacker == victim) return Plugin_Continue;
		//Allow friendly firing BOTS that aren't idle players:
		//if(IsFakeClient(victim) && !HasEntProp(attacker, Prop_Send, "m_humanSpectatorUserID") || GetEntProp(attacker, Prop_Send, "m_humanSpectatorUserID") == 0) return Plugin_Continue;
		if(isPlayerTroll[attacker]) return Plugin_Stop;
		if(isUnderAttack[victim]) return Plugin_Continue;

		bool isDamageDirect = damagetype & (DMG_BLAST|DMG_BURN|DMG_BLAST_SURFACE) == 0;

		int time = GetTime();
		if(time - lastFF[attacker] > hForgivenessTime.IntValue) {
			playerTotalDamageFF[attacker] = 0.0;
		}
		playerTotalDamageFF[attacker] += damage;
		lastFF[attacker] = time;
		
		if(playerTotalDamageFF[attacker] > hThreshold.IntValue && !IsFinaleEnding && isDamageDirect) {
			if(hAction.IntValue == 1) {
				LogMessage("[NOTICE] Kicking %N for excessive FF (%f HP) for %d minutes.", attacker, playerTotalDamageFF[attacker], hBanTime.IntValue);
				NotifyAllAdmins("[Notice] Kicking %N for excessive FF (%f HP) for %d minutes.", attacker, playerTotalDamageFF[attacker], hBanTime.IntValue);
				KickClient(attacker, "Excessive FF");
			} else if(hAction.IntValue == 2) {
				LogMessage("[NOTICE] Banning %N for excessive FF (%f HP) for %d minutes.", attacker, playerTotalDamageFF[attacker], hBanTime.IntValue);
				NotifyAllAdmins("[Notice] Banning %N for excessive FF (%f HP) for %d minutes.", attacker, playerTotalDamageFF[attacker], hBanTime.IntValue);
				BanClient(attacker, hBanTime.IntValue, BANFLAG_AUTO | BANFLAG_AUTHID, "Excessive FF", "Excessive Friendly Fire", "TKStopper");
			} else if(hAction.IntValue == 3) {
				LogMessage("[NOTICE] %N will be banned for FF on disconnect (%f HP) for %d minutes. ", attacker, playerTotalDamageFF[attacker], hBanTime.IntValue);
				NotifyAllAdmins("[Notice] %N will be banned for FF on disconnect (%f HP) for %d minutes. Use /ignore <player> to make them immune.", attacker, playerTotalDamageFF[attacker], hBanTime.IntValue);
				isPlayerTroll[attacker] = true;
			}
			damage = 0.0;
			return Plugin_Handled;
		}
		//If the amount of MS is <= join time threshold * 60000 ms then cancel
		if(L4D_IsInFirstCheckpoint(victim) || L4D_IsInLastCheckpoint(victim) || time - iJoinTime[attacker] <= hJoinTime.IntValue * 60000) {
			damage = 0.0;
			return Plugin_Handled;
		}else if(IsFinaleEnding) {
			SDKHooks_TakeDamage(attacker, attacker, attacker, damage * 2.0);
			damage = 0.0;
			return Plugin_Changed;
		}else if(!isDamageDirect) {
			SDKHooks_TakeDamage(attacker, attacker, attacker, damage / 1.9);
			damage /= 2.1;
			return Plugin_Changed;
		}
	}
	return Plugin_Continue;
}

public Action Command_IgnorePlayer(int client, int args) {
	char arg1[32];
	GetCmdArg(1, arg1, sizeof(arg1));

	char target_name[MAX_TARGET_LENGTH];
	int target_list[1], target_count;
	bool tn_is_ml;

	if ((target_count = ProcessTargetString(
			arg1,
			client,
			target_list,
			MaxClients,
			COMMAND_FILTER_ALIVE, 
			target_name,
			sizeof(target_name),
			tn_is_ml)) <= 0)
	{
		ReplyToTargetError(client, target_count);
		return Plugin_Handled;
	}

	for(int i = 0; i < target_count; i++) {
		int target = target_list[i];
		if(isImmune[target]) {
			ShowActivity2(client, "[FTT] ", "%N has re-enabled teamkiller detection for %N", client, target);
		} else {
			ShowActivity2(client, "[FTT] ", "%N has ignored teamkiller detection for %N", client, target);
		}
		isImmune[target] = !isImmune[target];
		isPlayerTroll[target] = false;
	}

	return Plugin_Handled;
}