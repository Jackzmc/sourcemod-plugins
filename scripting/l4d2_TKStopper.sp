#pragma semicolon 1
#pragma newdecls required

//#define DEBUG

#define PLUGIN_VERSION "1.0"

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <jutils>
#include <left4dhooks>

bool lateLoaded, isFinaleEnding;
bool isPlayerTroll[MAXPLAYERS+1], isImmune[MAXPLAYERS+1], isUnderAttack[MAXPLAYERS+1];
int iJoinTime[MAXPLAYERS+1];
int iIdleStartTime[MAXPLAYERS+1];
int iLastFFTime[MAXPLAYERS+1];
int iJumpAttempts[MAXPLAYERS+1];

float playerTotalDamageFF[MAXPLAYERS+1];
float autoFFScaleFactor[MAXPLAYERS+1];

ConVar hForgivenessTime, hBanTime, hThreshold, hJoinTime, hTKAction, hSuicideAction, hSuicideLimit, hFFAutoScaleAmount, hFFAutoScaleForgivenessAmount, hFFAutoScaleMaxRatio, hFFAutoScaleIgnoreAdmins;

public Plugin myinfo = {
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

public void OnPluginStart() {
	EngineVersion g_Game = GetEngineVersion();
	if(g_Game != Engine_Left4Dead && g_Game != Engine_Left4Dead2) {
		SetFailState("This plugin is for L4D/L4D2 only.");	
	}

	hForgivenessTime = CreateConVar("l4d2_tk_forgiveness_time", "15", "The minimum amount of time to pass (in seconds) where a player's previous accumulated FF is forgiven", FCVAR_NONE, true, 0.0);
	hBanTime = CreateConVar("l4d2_tk_bantime", "120", "How long in minutes should a player be banned for? 0 for permanently",  FCVAR_NONE, true, 0.0);
	hThreshold = CreateConVar("l4d2_tk_ban_ff_threshold", "75.0", "How much damage does a player need to do before being instantly banned",  FCVAR_NONE, true, 0.0);
	hJoinTime = CreateConVar("l4d2_tk_ban_join_time", "2", "Upto how many minutes should any new player be subjected to instant bans on any FF",  FCVAR_NONE, true, 0.0);
	hTKAction = CreateConVar("l4d2_tk_action", "3", "How should the TK be punished?\n0 = No action (No message), 1 = Kick, 2 = Instant Ban, 3 = Ban on disconnect", FCVAR_NONE, true, 0.0, true, 3.0);
	hSuicideAction = CreateConVar("l4d2_suicide_action", "3", "How should a suicider be punished?\n0 = No action (No message), 1 = Kick, 2 = Instant Ban, 3 = Ban on disconnect", FCVAR_NONE, true, 0.0, true, 3.0);
	hSuicideLimit = CreateConVar("l4d2_suicide_limit", "1", "How many attempts does a new joined player have until action is taken for suiciding?", FCVAR_NONE, true, 0.0);
	// Reverse FF Auto Scale
	hFFAutoScaleAmount = CreateConVar("l4d2_tk_auto_ff_rate", "0.02", "The rate at which auto reverse-ff is scaled by.", FCVAR_NONE, true, 0.0);
	hFFAutoScaleMaxRatio = CreateConVar("l4d2_tk_auto_ff_max_ratio", "5.0", "The maximum amount that the reverse ff can go. 0.0 for unlimited", FCVAR_NONE, true, 0.0);
	hFFAutoScaleForgivenessAmount = CreateConVar("l4d2_tk_auto_ff_forgive_rate", "0.03", "This amount times amount of minutes since last ff is removed from ff rate", FCVAR_NONE, true, 0.0);
	hFFAutoScaleIgnoreAdmins = CreateConVar("l4d2_tk_auto_ff_ignore_admins", "1", "Should automatic reverse ff ignore admins? 0 = Admins are subjected\n1 = Admins are excempt", FCVAR_NONE, true, 0.0, true, 1.0);

	AutoExecConfig(true, "l4d2_tkstopper");

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

	HookEvent("player_bot_replace", Event_PlayerToBot);
	HookEvent("bot_player_replace", Event_BotToPlayer);


	RegAdminCmd("sm_ignore", Command_IgnorePlayer, ADMFLAG_KICK, "Makes a player immune for any anti trolling detection for a session");
	RegAdminCmd("sm_tkinfo", Command_TKInfo, ADMFLAG_KICK, "Debug info for TKSTopper");

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
		isUnderAttack[victim] = StrEqual(name, "charger_carry_start");
	}
	return Plugin_Continue; 
}

public Action Event_HunterPounce(Event event, const char[] name, bool dontBroadcast) {
	int victim = GetClientOfUserId(event.GetInt("victim"));
	if(victim) {
		isUnderAttack[victim] = StrEqual(name, "lunge_pounce");
	}
	return Plugin_Continue; 
}

public Action Event_SmokerChoke(Event event, const char[] name, bool dontBroadcast) {
	int victim = GetClientOfUserId(event.GetInt("victim"));
	if(victim) {
		isUnderAttack[victim] = StrEqual(name, "choke_start");
	}
	return Plugin_Continue; 
}
public Action Event_JockeyRide(Event event, const char[] name, bool dontBroadcast) {
	int victim = GetClientOfUserId(event.GetInt("victim"));
	if(victim) {
		isUnderAttack[victim] = StrEqual(name, "jockey_ride");
	}
	return Plugin_Continue; 
}
///////////////////////////////////////////////////////////////////////////////
// IDLE 
///////////////////////////////////////////////////////////////////////////////
public Action Event_BotToPlayer(Event event, const char[] name, bool dontBroadcast) {
	int player = GetClientOfUserId(event.GetInt("player"));

	// ignore fake players (side product of creating bots)
	if (!IsValidClient(player) || (GetClientTeam(player) != 2 && GetClientTeam(player) != 3) || IsFakeClient(player)) return Plugin_Continue;  

	// If a player has been idle for over 600s (10 min), reset to them "just joined"
	// Purpose: Some trolls idle till end and then attack @ escape, or "gain trust"
	if(GetTime() - iIdleStartTime[player] >= 600) {
		iJoinTime[player] = GetTime();
	}
	return Plugin_Continue; 
}
public Action Event_PlayerToBot(Event event, char[] name, bool dontBroadcast) {
	int player = GetClientOfUserId(event.GetInt("player"));
	iIdleStartTime[player] = GetTime(); 
	return Plugin_Continue; 
}
///////////////////////////////////////////////////////////////////////////////
// Misc events
///////////////////////////////////////////////////////////////////////////////
public void Event_FinaleVehicleReady(Event event, const char[] name, bool dontBroadcast) {
	isFinaleEnding = true;
	for(int i = 1; i <= MaxClients; i++) {
		if(isPlayerTroll[i] && IsClientConnected(i) && IsClientInGame(i)) {
			PrintChatToAdmins("Note: %N is still marked as troll and will be banned after this game. Use /ignore to ignore them.", i);
		}
	}
}

public void OnMapEnd() {
	isFinaleEnding = false;
}

public void OnClientPutInServer(int client) {
	iJoinTime[client] = GetTime();
	iLastFFTime[client] = GetTime();
	SDKHook(client, SDKHook_OnTakeDamage, Event_OnTakeDamage);
}

// Called on map changes, so only reset some variables:
public void OnClientDisconnect(int client) {
	playerTotalDamageFF[client] = 0.0;
	isUnderAttack[client] = false;
	iJumpAttempts[client] = 0;
}

// Only clear things when they fully left on their own accord:
public void Event_PlayerDisconnect(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(client > 0 && isPlayerTroll[client]) {
		BanClient(client, hBanTime.IntValue, BANFLAG_AUTO | BANFLAG_AUTHID, "Excessive FF", "Excessive Friendly Fire", "TKStopper");
	}
	isPlayerTroll[client] = false;
	autoFFScaleFactor[client] = 0.0;
}

public Action Event_OnTakeDamage(int victim,  int& attacker, int& inflictor, float& damage, int& damagetype, int& weapon, float damageForce[3], float damagePosition[3]) {
	if(damage > 0.0 && victim <= MaxClients && attacker <= MaxClients && attacker > 0 && victim > 0 && attacker != victim) {
		if(GetClientTeam(victim) != GetClientTeam(attacker) || attacker == victim) return Plugin_Continue;
		else if(damagetype & DMG_BURN && IsFakeClient(attacker) && GetClientTeam(attacker) == 2) {
			// Ignore damage from fire caused by bots (players who left after causing fire)
			damage = 0.0;
			return Plugin_Changed;
		}
		// Otherwise if attacker was ignored or is a bot, stop here and let vanilla handle it
		else if(isImmune[attacker] || IsFakeClient(attacker)) return Plugin_Continue;

		bool isAdmin = GetUserAdmin(attacker) != INVALID_ADMIN_ID;
		
		//Allow friendly firing BOTS that aren't idle players:
		//if(IsFakeClient(victim) && !HasEntProp(attacker, Prop_Send, "m_humanSpectatorUserID") || GetEntProp(attacker, Prop_Send, "m_humanSpectatorUserID") == 0) return Plugin_Continue;
		
		// Stop all damage early if already marked as troll
		if(isPlayerTroll[attacker]) {
			SDKHooks_TakeDamage(attacker, attacker, attacker, autoFFScaleFactor[attacker] * damage);

			return Plugin_Stop;
		}
		// Allow vanilla-damage if being attacked by special (example, charger carry)
		if(isUnderAttack[victim]) return Plugin_Continue;
	
		// Is damage not caused by fire or pipebombs?
		bool isDamageDirect = damagetype & (DMG_BLAST|DMG_BURN|DMG_BLAST_SURFACE) == 0;
		int time = GetTime();
		// If is a fall within first 2 minutes, do appropiate action
		if(!isAdmin && damagetype & DMG_FALL && attacker == victim && damage > 0.0 && time - iJoinTime[victim] <= hJoinTime.IntValue * 60) {
			iJumpAttempts[victim]++;
			float pos[3];
			GetNearestPlayerPosition(victim, pos);
			PrintToConsoleAdmins("%N within join time (%d min), attempted to fall");
			if(iJumpAttempts[victim] > hSuicideLimit.IntValue) {
				if(hSuicideAction.IntValue == 1) {
					LogMessage("[NOTICE] Kicking %N for suicide attempts", victim, hBanTime.IntValue);
					NotifyAllAdmins("[Notice]  Kicking %N for suicide attempts", victim, hBanTime.IntValue);
					KickClient(victim, "Troll");
				} else if(hSuicideAction.IntValue == 2) {
					LogMessage("[NOTICE] Banning %N for suicide attempts for %d minutes.", victim, hBanTime.IntValue);
					NotifyAllAdmins("[Notice] Banning %N for suicide attempts for %d minutes.", victim, hBanTime.IntValue);
					BanClient(victim, hBanTime.IntValue, BANFLAG_AUTO | BANFLAG_AUTHID, "Suicide fall attempts", "Troll", "TKStopper");
				} else if(hSuicideAction.IntValue == 3) {
					LogMessage("[NOTICE] %N will be banned for suicide attempts for %d minutes. ", victim, hBanTime.IntValue);
					NotifyAllAdmins("[Notice] %N will be banned for suicide attempts for %d minutes. Use /ignore <player> to make them immune.", victim, hBanTime.IntValue);
					isPlayerTroll[victim] = true;
				}
			}
		}

		// Forgive player based on threshold, resetting accumlated damage
		if(time - iLastFFTime[attacker] > hForgivenessTime.IntValue) {
			playerTotalDamageFF[attacker] = 0.0;
		}
		playerTotalDamageFF[attacker] += damage;

		// Auto reverse ff logic
		iLastFFTime[attacker] = time;
		if(isDamageDirect && (!hFFAutoScaleIgnoreAdmins.BoolValue || !isAdmin)) {
			// Decrement any forgiven ratio (computed on demand)
			float minutesSinceiLastFFTime = (time - iLastFFTime[attacker]) / 60.0;
			autoFFScaleFactor[attacker] -= minutesSinceiLastFFTime * hFFAutoScaleForgivenessAmount.FloatValue;
			if(autoFFScaleFactor[attacker] < 0.0) {
				autoFFScaleFactor[attacker] = 0.0;
			}
			// Then calculate a new reverse ff ratio
			autoFFScaleFactor[attacker] += hFFAutoScaleAmount.FloatValue * damage;
			if(isPlayerTroll[attacker]) {
				autoFFScaleFactor[attacker] *= 2;
			}
			
			if(!isPlayerTroll[attacker] && hFFAutoScaleMaxRatio.FloatValue > 0.0 && autoFFScaleFactor[attacker] > hFFAutoScaleMaxRatio.FloatValue) {
				autoFFScaleFactor[attacker] = hFFAutoScaleMaxRatio.FloatValue;
			}
		}
		
		// Check for excessive friendly fire damage in short timespan
		if(!isAdmin && playerTotalDamageFF[attacker] > hThreshold.IntValue && !isFinaleEnding && isDamageDirect) {
			LogAction(-1, attacker, "Excessive FF (%.2f HP) (%.2f RFF Rate)", playerTotalDamageFF[attacker], autoFFScaleFactor[attacker]);
			if(hTKAction.IntValue == 1) {
				LogMessage("[NOTICE] Kicking %N for excessive FF (%.2f HP) for %d minutes.", attacker, playerTotalDamageFF[attacker], hBanTime.IntValue);
				NotifyAllAdmins("[Notice] Kicking %N for excessive FF (%.2f HP) for %d minutes.", attacker, playerTotalDamageFF[attacker], hBanTime.IntValue);
				KickClient(attacker, "Excessive FF");
			} else if(hTKAction.IntValue == 2) {
				LogMessage("[NOTICE] Banning %N for excessive FF (%.2f HP) for %d minutes.", attacker, playerTotalDamageFF[attacker], hBanTime.IntValue);
				NotifyAllAdmins("[Notice] Banning %N for excessive FF (%.2f HP) for %d minutes.", attacker, playerTotalDamageFF[attacker], hBanTime.IntValue);
				BanClient(attacker, hBanTime.IntValue, BANFLAG_AUTO | BANFLAG_AUTHID, "Excessive FF", "Excessive Friendly Fire", "TKStopper");
			} else if(hTKAction.IntValue == 3) {
				LogMessage("[NOTICE] %N will be banned for FF on disconnect (%.2f HP) for %d minutes. ", attacker, playerTotalDamageFF[attacker], hBanTime.IntValue);
				NotifyAllAdmins("[Notice] %N will be banned for FF on disconnect (%.2f HP) for %d minutes. Use /ignore <player> to make them immune.", attacker, playerTotalDamageFF[attacker], hBanTime.IntValue);
				isPlayerTroll[attacker] = true;
			}
			damage = 0.0;
			return Plugin_Handled;
		}

		// Modify damages based on criteria		
		if(iJumpAttempts[victim] > 0 || L4D_IsInFirstCheckpoint(victim) || L4D_IsInLastCheckpoint(victim) || time - iJoinTime[attacker] <= hJoinTime.IntValue * 60) {
			/* 
			If the amount of seconds since they joined is <= the minimum join time cvar (min) threshold
				or if the player is in a saferoom
				or if the player tried to suicide jump
			Then cancel all damage: 
			*/
			damage = 0.0;
			return Plugin_Handled;
		}else if(isFinaleEnding) {
			// Keep admins immune if escape vehicle out
			if(isAdmin) return Plugin_Continue;
			SDKHooks_TakeDamage(attacker, attacker, attacker, damage * 2.0);
			damage = 0.0;
			return Plugin_Changed;
		}else if(isDamageDirect) { // Ignore fire and propane damage, mistakes can happen
			// Apply their reverse ff damage, and have victim take a decreasing amount
			SDKHooks_TakeDamage(attacker, attacker, attacker, autoFFScaleFactor[attacker] * damage);
			if(isPlayerTroll[attacker]) return Plugin_Stop;
			if(autoFFScaleFactor[attacker] > 1.0)
				damage /= autoFFScaleFactor[attacker];
			else
				damage /= 2.0;
			return Plugin_Changed;
		}
	}
	return Plugin_Continue;
}

/// COMMANDS

public Action Command_TKInfo(int client, int args) {
	int time = GetTime();
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && !IsFakeClient(i)) {
			float minutesSinceiLastFFTime = (time - iLastFFTime[i]) / 60.0;
			float activeRate = autoFFScaleFactor[i] - (minutesSinceiLastFFTime * hFFAutoScaleForgivenessAmount.FloatValue);
			if(activeRate < 0.0) {
				activeRate = 0.0;
			} 
			ReplyToCommand(client, "%N: %f TK-FF buffer | %.3f (buf %f), reverse FF rate | last ff %.1f min ago | %d suicide jumps", i, playerTotalDamageFF[i], activeRate, autoFFScaleFactor[i], minutesSinceiLastFFTime,  iJumpAttempts[i]);
		}
	}
	return Plugin_Handled;
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
		tn_is_ml)) <= 0
	) {
		ReplyToTargetError(client, target_count);
		return Plugin_Handled;
	}

	for(int i = 0; i < target_count; i++) {
		int target = target_list[i];
		if(GetUserAdmin(target) != INVALID_ADMIN_ID) {
			ReplyToCommand(client, "%N is an admin and is already immune.");
		}else{
			if(isImmune[target]) {
				LogAction(client, target, "\"%L\" re-enabled teamkiller detection for \"%L\"",  client, target);
				ShowActivity2(client, "[FTT] ", "%N has re-enabled teamkiller detection for %N", client, target);
			} else {
				LogAction(client, target, "\"%L\" ignored teamkiller detection for \"%L\"",  client, target);
				ShowActivity2(client, "[FTT] ", "%N has ignored teamkiller detection for %N", client, target);
			}
			isImmune[target] = !isImmune[target];
		}
		isPlayerTroll[target] = false;
	}

	return Plugin_Handled;
}


/// STOCKS

stock bool GetNearestPlayerPosition(int client, float pos[3]) {
	static float targetPos[3], lowestDist;
	int lowestID = -1;
	GetClientAbsOrigin(client, targetPos);
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == 2 && i != client) {
			GetClientAbsOrigin(i, pos);
			float distance = GetVectorDistance(pos, targetPos);
			if(lowestID == -1 || distance < lowestDist) {
				lowestID = i;
				lowestDist = distance;
			}
		}
	}
	GetClientAbsOrigin(lowestID, pos);
	return lowestID > 0;
}

stock void PrintChatToAdmins(const char[] format, any ...) {
	char buffer[254];
	VFormat(buffer, sizeof(buffer), format, 2);
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i)) {
			AdminId admin = GetUserAdmin(i);
			if(admin != INVALID_ADMIN_ID) {
				PrintToChat(i, "%s", buffer);
			}
		}
	}
	PrintToServer("%s", buffer);
}

stock void PrintToConsoleAdmins(const char[] format, any ...) {
	char buffer[254];
	VFormat(buffer, sizeof(buffer), format, 2);
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i)) {
			AdminId admin = GetUserAdmin(i);
			if(admin != INVALID_ADMIN_ID) {
				PrintToConsole(i, "%s", buffer);
			}
		}
	}
	PrintToServer("%s", buffer);
}
