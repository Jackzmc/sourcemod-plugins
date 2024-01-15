#pragma semicolon 1
#pragma newdecls required

//#define DEBUG

#define PLUGIN_VERSION "1.0"

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <left4dhooks>
#include <multicolors>
#include <jutils>

enum {
	Immune_None,
	Immune_TK = 1,
	Immune_RFF = 2
}

bool lateLoaded, isFinaleEnding;

enum struct PlayerData {
	int joinTime;
	int idleStartTime;
	int lastFFTime;
	int jumpAttempts;

	int ffCount;
	int totalFFCount;
	float TKDamageBuffer;
	float totalDamageFF;
	float autoRFFScaleFactor;

	bool isTroll;
	bool underAttack;

	int immunityFlags;

	bool pendingAction;

	bool joined;
}

PlayerData pData[MAXPLAYERS+1];

ConVar hForgivenessTime, hBanTime, hThreshold, hJoinTime, hTKAction, hSuicideAction, hSuicideLimit, hFFAutoScaleAmount, hFFAutoScaleForgivenessAmount, hFFAutoScaleMaxRatio, hFFAutoScaleActivateTypes;

enum RffActTypes {
	RffActType_None,
	RffActType_AdminDamage = 1,
	RffActType_BlastDamage = 2,
	RffActType_MolotovDamage = 4,
	RffActType_BlackAndWhiteDamage = 8
}
char gamemode[64];
bool isEnabled = true;

public Plugin myinfo = {
	name =  "TK Stopper", 
	author = "jackzmc", 
	description = "", 
	version = PLUGIN_VERSION, 
	url = "https://github.com/Jackzmc/sourcemod-plugins"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
	CreateNative("SetImmunity", Native_SetImmunity);
	CreateNative("GetImmunity", Native_GetImmunity);
	if(late) {
		lateLoaded = true;
	}
	return APLRes_Success;
} 

public void OnPluginStart() {
	EngineVersion g_Game = GetEngineVersion();
	if(g_Game != Engine_Left4Dead && g_Game != Engine_Left4Dead2) {
		SetFailState("This plugin is for L4D/L4D2 only.");	
	}

	hForgivenessTime = CreateConVar("l4d2_tk_forgiveness_time", "15", "The minimum amount of time to pass (in seconds) where a player's previous accumulated teamkiller-detection FF is forgiven", FCVAR_NONE, true, 0.0);
	hBanTime = CreateConVar("l4d2_tk_bantime", "60", "How long in minutes should a player be banned for? 0 for permanently",  FCVAR_NONE, true, 0.0);
	hThreshold = CreateConVar("l4d2_tk_ban_ff_threshold", "75.0", "How much damage does a player need to do before being instantly banned",  FCVAR_NONE, true, 0.0);
	hJoinTime = CreateConVar("l4d2_tk_ban_join_time", "2", "Upto how many minutes should any new player's ff be disabled? Used for jump attempts detection. also",  FCVAR_NONE, true, 0.0);
	hTKAction = CreateConVar("l4d2_tk_action", "3", "How should the TK be punished?\n0 = No action (No message), 1 = Kick, 2 = Instant Ban, 3 = Ban on disconnect", FCVAR_NONE, true, 0.0, true, 3.0);
	hSuicideAction = CreateConVar("l4d2_suicide_action", "3", "How should a suicider be punished?\n0 = No action (No message), 1 = Kick, 2 = Instant Ban, 3 = Ban on disconnect", FCVAR_NONE, true, 0.0, true, 3.0);
	hSuicideLimit = CreateConVar("l4d2_suicide_limit", "1", "How many attempts does a new joined player have until action is taken for suiciding?", FCVAR_NONE, true, 0.0);
	// Reverse FF Auto Scale
	hFFAutoScaleAmount = CreateConVar("l4d2_tk_auto_ff_rate", "0.02", "The rate at which auto reverse-ff is scaled by.", FCVAR_NONE, true, 0.0);
	hFFAutoScaleMaxRatio = CreateConVar("l4d2_tk_auto_ff_max_ratio", "5.0", "The maximum amount that the reverse ff can go. 0.0 for unlimited", FCVAR_NONE, true, 0.0);
	hFFAutoScaleForgivenessAmount = CreateConVar("l4d2_tk_auto_ff_forgive_rate", "0.05", "This amount times amount of minutes since last ff is removed from ff rate", FCVAR_NONE, true, 0.0);
	hFFAutoScaleActivateTypes = CreateConVar("l4d2_tk_auto_ff_activate_types", "6", "The types of damages to ignore. Add bits together.\n0 = Just direct fire\n1 = Damage from admins\n2 = Blast damage (pipes, grenade launchers)\n4 = Molotov/gascan/firework damage\n8 = Killing black and white players", FCVAR_NONE, true, 0.0, true, 15.0);
	
	ConVar hGamemode = FindConVar("mp_gamemode"); 
	hGamemode.AddChangeHook(Event_GamemodeChange);
	Event_GamemodeChange(hGamemode, gamemode, gamemode);

	AutoExecConfig(true, "l4d2_tkstopper");

	HookEvent("finale_vehicle_ready", Event_FinaleVehicleReady);
	HookEvent("finale_start", Event_FinaleStart);
	HookEvent("player_team", Event_PlayerDisconnect);

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


	RegAdminCmd("sm_ignore", Command_IgnorePlayer, ADMFLAG_KICK, "Makes a player immune for any anti trolling detection or reverse-ff for a session");
	RegAdminCmd("sm_tkinfo", Command_TKInfo, ADMFLAG_KICK, "Debug info for TKSTopper");
	RegAdminCmd("sm_review", Command_TKInfo, ADMFLAG_KICK, "Review FF info for a player");

	if(lateLoaded) {
		for(int i = 1; i <= MaxClients; i++) {
			if(IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2) {
				SDKHook(i, SDKHook_OnTakeDamage, Event_OnTakeDamage);
			}
		}
	}
	LoadTranslations("common.phrases");
}
void Event_GamemodeChange(ConVar cvar, const char[] oldValue, const char[] newValue) {
	cvar.GetString(gamemode, sizeof(gamemode));
	if(StrEqual(gamemode, "coop")) {
		isEnabled = true;
	} else {
		isEnabled = false;
	}
}
///////////////////////////////////////////////////////////////////////////////
// Special Infected Events 
///////////////////////////////////////////////////////////////////////////////
Action Event_ChargerCarry(Event event, const char[] name, bool dontBroadcast) {
	return SetUnderAttack(event, name, "charger_carry_start");
}
Action Event_HunterPounce(Event event, const char[] name, bool dontBroadcast) {
	return SetUnderAttack(event, name, "lunge_pounce");
}
Action Event_SmokerChoke(Event event, const char[] name, bool dontBroadcast) {
	return SetUnderAttack(event, name, "choke_start");
}
Action Event_JockeyRide(Event event, const char[] name, bool dontBroadcast) {
	return SetUnderAttack(event, name, "jockey_ride");
}

Action Timer_StopSpecialAttackImmunity(Handle h, int userid) {
	int client = GetClientOfUserId(userid);
	if(client > 0) {
		pData[client].underAttack = false;
	}
	return Plugin_Continue;
}

Action SetUnderAttack(Event event, const char[] name, const char[] checkString) {
	int userid = event.GetInt("victim");
	int victim = GetClientOfUserId(userid);
	if(victim) {
		if(StrEqual(name, checkString)) {
			pData[victim].underAttack = true;
		} else {
			CreateTimer(1.0, Timer_StopSpecialAttackImmunity, userid);
		}
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
	if(GetTime() - pData[player].idleStartTime >= 600) {
		pData[player].joinTime = GetTime();
	}
	return Plugin_Continue; 
}
public Action Event_PlayerToBot(Event event, char[] name, bool dontBroadcast) {
	int player = GetClientOfUserId(event.GetInt("player"));
	pData[player].idleStartTime = GetTime();
	return Plugin_Continue; 
}
///////////////////////////////////////////////////////////////////////////////
// Misc events
///////////////////////////////////////////////////////////////////////////////
void Event_FinaleVehicleReady(Event event, const char[] name, bool dontBroadcast) {
	isFinaleEnding = true;
	WarnStillMarked();
	PrintToServer("[TKStopper] Escape vehicle active, 2x rff in effect");
}
void Event_FinaleStart(Event event, const char[] name, bool dontBroadcast) {
	WarnStillMarked();
}
public void OnMapEnd() {
	isFinaleEnding = false;
}

public void OnClientPutInServer(int client) {
	pData[client].joinTime = pData[client].idleStartTime = GetTime();
	SDKHook(client, SDKHook_OnTakeDamage, Event_OnTakeDamage);
}

public void OnClientPostAdminCheck(int client) {
	if(GetUserAdmin(client) != INVALID_ADMIN_ID && !pData[client].joined) {
		pData[client].joined = true;
		pData[client].immunityFlags = Immune_TK;
		// If no admins can do ff and they 
		if(~hFFAutoScaleActivateTypes.IntValue & view_as<int>(RffActType_AdminDamage)) {
			pData[client].immunityFlags |= Immune_RFF;
		}
	}
}

// Called on map changes, so only reset some variables:
public void OnClientDisconnect(int client) {
	pData[client].TKDamageBuffer = 0.0;
	pData[client].jumpAttempts = 0;
	pData[client].underAttack = false;
	pData[client].ffCount = 0;
}

// Only clear things when they fully left on their own accord:
void Event_PlayerDisconnect(Event event, const char[] name, bool dontBroadcast) {
	if(!event.GetBool("disconnect") || !isEnabled) return;

	int client = GetClientOfUserId(event.GetInt("userid"));
	if(client > 0 && event.GetInt("team") <= 2) {
		if (pData[client].isTroll && !IsFakeClient(client)) {
			BanClient(client, hBanTime.IntValue, BANFLAG_AUTO | BANFLAG_AUTHID, "Excessive FF (Auto)", "Excessive Friendly Fire", "TKStopper");
			if(hBanTime.IntValue > 0)
				CPrintChatToAdmins("{olive}%N{default} has been banned for %d minutes (marked as troll). If this was a mistake, you can discard their ban from the admin panel at {yellow}https://admin.jackz.me", client, hBanTime.IntValue);
			else
				CPrintChatToAdmins("{olive}%N{default} has been permanently banned (marked as troll). If this was a mistake, you can discard their ban from the admin panel at {yellow}https://admin.jackz.me", client);
			pData[client].isTroll = false;
		}

		if(!IsFakeClient(client)) {
			float minutesSinceiLastFFTime = GetLastFFMinutes(client);
			float activeRate = GetActiveRate(client);
			PrintToConsoleAll("[TKStopper] FF Summary for %N:", client);
			PrintToConsoleAll("\t%.2f TK-FF buffer (%.2f total ff, %d freq.) | %.3f (buf %f) rFF rate | lastff %.1f min ago | %d suicide jumps", 
				pData[client].TKDamageBuffer, 
				pData[client].totalDamageFF, 
				pData[client].totalFFCount,
				activeRate, 
				pData[client].autoRFFScaleFactor, 
				minutesSinceiLastFFTime, 
				pData[client].jumpAttempts
			);
		}

		pData[client].autoRFFScaleFactor = 0.0;
		pData[client].totalDamageFF = 0.0;
		pData[client].ffCount = 0;
		pData[client].immunityFlags = 0;
		pData[client].totalFFCount = 0;
		pData[client].joined = false;
	}
}

Action Event_OnTakeDamage(int victim,  int& attacker, int& inflictor, float& damage, int& damagetype, int& weapon, float damageForce[3], float damagePosition[3]) {
	if(isEnabled && damage > 0.0 && victim <= MaxClients && attacker <= MaxClients && attacker > 0 && victim > 0) {
		if(GetClientTeam(attacker) != 2 || GetClientTeam(victim) != 2 || attacker == victim) 
			return Plugin_Continue;
		else if(IsFakeClient(attacker) && attacker != victim) {
			// Ignore damage from fire/explosives caused by bots (players who left after causing fire)
			if(damagetype & DMG_BURN && hFFAutoScaleActivateTypes.IntValue & view_as<int>(RffActType_MolotovDamage)) {
				damage = 0.0;
				return Plugin_Changed;
			} else if((damagetype & DMG_BLAST || damagetype & DMG_BLAST_SURFACE) && hFFAutoScaleActivateTypes.IntValue & view_as<int>(RffActType_BlastDamage)) {
				damage = 0.0;
				return Plugin_Changed;
			}
		}
		bool isAdmin = GetUserAdmin(attacker) != INVALID_ADMIN_ID;
		int time = GetTime();
		// If is a fall within first 2 minutes, do appropiate action
		if(damagetype & DMG_FALL && attacker == victim && damage > 0.0 && time - pData[victim].joinTime <= hJoinTime.IntValue * 60) {
			pData[victim].jumpAttempts++;
			float pos[3];
			GetNearestPlayerPosition(victim, pos);
			PrintToConsoleAdmins("%N within join time (%d min), attempted to fall");
			TeleportEntity(victim, pos, NULL_VECTOR, NULL_VECTOR);
			damage = 0.0;
			if(pData[victim].jumpAttempts > hSuicideLimit.IntValue) {
				if(hSuicideAction.IntValue == 1) {
					LogMessage("[NOTICE] Kicking %N for suicide attempts", victim, hBanTime.IntValue);
					PrintChatToAdmins("[Notice]  Kicking %N for suicide attempts", victim, hBanTime.IntValue);
					KickClient(victim, "Troll");
				} else if(hSuicideAction.IntValue == 2) {
					LogMessage("[NOTICE] Banning %N for suicide attempts for %d minutes.", victim, hBanTime.IntValue);
					PrintChatToAdmins("[Notice] Banning %N for suicide attempts for %d minutes.", victim, hBanTime.IntValue);
					BanClient(victim, hBanTime.IntValue, BANFLAG_AUTO | BANFLAG_AUTHID, "Suicide fall attempts", "Troll", "TKStopper");
				} else if(hSuicideAction.IntValue == 3) {
					LogMessage("[NOTICE] %N will be banned for suicide attempts for %d minutes. ", victim, hBanTime.IntValue);
					PrintChatToAdmins("[Notice] %N will be banned for suicide attempts for %d minutes. Use \"/ignore <player> tk\" to make them immune.", victim, hBanTime.IntValue);
					pData[victim].isTroll = true;
				}
			}
			return Plugin_Stop;
		}
		// Disregard any self inflicted damage from here: 
		else if(attacker == victim) return Plugin_Continue;

		// Stop all damage early if already marked as troll
		else if(pData[attacker].isTroll) {
			SDKHooks_TakeDamage(attacker, attacker, attacker, pData[attacker].autoRFFScaleFactor * damage);
			return Plugin_Stop;
		}
		// Otherwise if attacker is immune, is a bot, or victim is a bot, let it continue
		else if(pData[attacker].immunityFlags & Immune_RFF || IsFakeClient(attacker) || IsFakeClient(victim)) return Plugin_Continue;
		// If victim is black and white and rff damage isnt turned on for it, allow it:
		else if(GetEntProp(victim, Prop_Send, "m_isGoingToDie") && ~hFFAutoScaleActivateTypes.IntValue & view_as<int>(RffActType_BlackAndWhiteDamage)) {
			return Plugin_Continue;
		}

		//Allow friendly firing BOTS that aren't idle players:
		//if(IsFakeClient(victim) && !HasEntProp(attacker, Prop_Send, "m_humanSpectatorUserID") || GetEntProp(attacker, Prop_Send, "m_humanSpectatorUserID") == 0) return Plugin_Continue;
		
		// Allow vanilla-damage if being attacked by special (example, charger carry)
		// We don't want to track someone accidently ffing them when theres a window where you can
		else if(pData[victim].underAttack) return Plugin_Continue;
	
		// Is damage not caused by fire or pipebombs?
		bool isDamageDirect = (~damagetype & DMG_BURN) != 0;

		// Forgive player teamkill based on threshold, resetting accumlated damage
		if(time - pData[attacker].lastFFTime > hForgivenessTime.IntValue) {
			pData[attacker].TKDamageBuffer = 0.0;
		}
		
		pData[attacker].TKDamageBuffer += damage;
		pData[attacker].totalDamageFF += damage;
		pData[attacker].totalFFCount++;
		pData[attacker].ffCount++;

		// Auto reverse ff logic
		if(isDamageDirect) {
			// Decrease the RFF scale based on how long since their last FF and an amount 
			float minutesSinceiLastFFTime = (time - pData[attacker].lastFFTime) / 60.0;
			pData[attacker].autoRFFScaleFactor -= minutesSinceiLastFFTime * hFFAutoScaleForgivenessAmount.FloatValue;
			if(pData[attacker].autoRFFScaleFactor < 0.0) {
				pData[attacker].autoRFFScaleFactor = 0.0;
			}

			// Decrement any accumlated ff 'counts'
			int ffCountMinutes = RoundFloat(minutesSinceiLastFFTime / 10.0);
			pData[attacker].ffCount -= (ffCountMinutes * 2);
			if(pData[attacker].ffCount < 0) {
				pData[attacker].ffCount = 0;
			}

			// Calculate a new reverse ff ratio based on scale threshold + damage dealt + # of recent friendly fires events
			pData[attacker].autoRFFScaleFactor += hFFAutoScaleAmount.FloatValue * damage * (pData[attacker].ffCount*0.25);
			if(pData[attacker].isTroll) {
				pData[attacker].autoRFFScaleFactor *= 2;
			} else if(hFFAutoScaleMaxRatio.FloatValue > 0.0 && pData[attacker].autoRFFScaleFactor > hFFAutoScaleMaxRatio.FloatValue) {
				// Cap it to the max - if they aren't marked as troll
				pData[attacker].autoRFFScaleFactor = hFFAutoScaleMaxRatio.FloatValue;
			}
			
		}

		int prevFFTime = pData[attacker].lastFFTime;
		pData[attacker].lastFFTime = time;
		
		// Check for excessive friendly fire damage in short timespan
		// If not immune to TK, if over TK threshold, not when escaping, and direct damage
		if(~pData[attacker].immunityFlags & Immune_TK
			&& pData[attacker].TKDamageBuffer > hThreshold.IntValue 
			&& !isFinaleEnding 
			&& isDamageDirect
			&& !IsFakeClient(victim) // Don't increment on bot-ff for now
		) {
			float diffJoinMin = (float(GetTime()) - float(pData[attacker].joinTime)) / 60.0;
			float lastFFMin = (float(GetTime()) - float(prevFFTime)) / 60.0;
			LogAction(-1, attacker, "Excessive FF (%.2f HP/%.2f total) (%.2f RFF Rate) (joined %.1fm ago) (%.1fmin last FF)", 
				pData[attacker].TKDamageBuffer, 
				pData[attacker].totalDamageFF, 
				pData[attacker].autoRFFScaleFactor, 
				diffJoinMin, 
				lastFFMin
			);
			if(!pData[attacker].pendingAction) {
				if(hTKAction.IntValue == 1) {
					LogMessage("[TKStopper] Kicking %N for excessive FF (%.2f HP)", attacker, pData[attacker].TKDamageBuffer);
					PrintChatToAdmins("[Notice] Kicking %N for excessive FF (%.2f HP)", attacker, pData[attacker].TKDamageBuffer);
					KickClient(attacker, "Excessive FF");
				} else if(hTKAction.IntValue == 2) {
					LogMessage("[TKStopper] Banning %N for excessive FF (%.2f HP) for %d minutes.", attacker, pData[attacker].TKDamageBuffer, hBanTime.IntValue);
					PrintChatToAdmins("[Notice] Banning %N for excessive FF (%.2f HP) for %d minutes.", attacker, pData[attacker].TKDamageBuffer, hBanTime.IntValue);
					BanClient(attacker, hBanTime.IntValue, BANFLAG_AUTO | BANFLAG_AUTHID, "Excessive FF (Auto)", "Excessive Friendly Fire (Automatic)", "TKStopper");
				} else if(hTKAction.IntValue == 3) {
					LogMessage("[TKStopper] %N will be banned for FF on disconnect (%.2f HP) for %d minutes. ", attacker, pData[attacker].TKDamageBuffer, hBanTime.IntValue);
					CPrintChatToAdmins("[Notice] %N will be banned for %d minutes for attempted teamkilling (%.2f HP) when they disconnect. Use {olive}/ignore <player> tk{default} to make them immune.", attacker, hBanTime.IntValue, pData[attacker].TKDamageBuffer);
					pData[attacker].isTroll = true;
				}
				pData[attacker].pendingAction = true;
			}
			damage = 0.0;
			return Plugin_Handled;
		}
		
		// Modify damages based on criteria		
		if(pData[victim].jumpAttempts > 0 // If they've attempted suicide, we just incase, disable their ff damage
			|| L4D_IsInFirstCheckpoint(victim) || L4D_IsInLastCheckpoint(victim) // No FF damage in saferooms
			|| time - pData[attacker].joinTime <= hJoinTime.IntValue * 60 // No FF damage within first X minutes
		) {
			/* 
			If the amount of seconds since they joined is <= the minimum join time cvar (min) threshold
				or if the player is in a saferoom
				or if the player tried to suicide jump
			Then cancel all damage: 
			*/
			damage = 0.0;
			return Plugin_Handled;
		}else if(isFinaleEnding) {
			// Keep admins immune if escape vehicle out, or if victim is a bot
			if(isAdmin || IsFakeClient(victim)) return Plugin_Continue;
			// We ignore FF for fire/molotovs, can be accidental / non-issue 
			if(isDamageDirect)
				SDKHooks_TakeDamage(attacker, attacker, attacker, damage * 2.0);
			damage = 0.0;
			return Plugin_Changed;
		}else if(isDamageDirect && pData[attacker].autoRFFScaleFactor > 0.18) { // 0.18 buffer to ignore fire and propane damage, mistakes can happen
			// Apply their reverse ff damage, and have victim take a decreasing amount
			if(pData[attacker].isTroll) return Plugin_Stop;

			SDKHooks_TakeDamage(attacker, attacker, attacker, pData[attacker].autoRFFScaleFactor * damage);
			if(pData[attacker].autoRFFScaleFactor > 1.0)
				damage = 0.0;
			else
				damage /= 2.0;
			return Plugin_Changed;
		}
	}
	return Plugin_Continue;
}

/// COMMANDS

Action Command_TKInfo(int client, int args) {
	int time = GetTime();
	if(!isEnabled) {
		ReplyToCommand(client, "Warn: Plugin is disabled in current gamemode (%s)", gamemode);
	}
	if(args > 0) {
		static char arg1[32];
		GetCmdArg(1, arg1, sizeof(arg1));

		static char target_name[MAX_TARGET_LENGTH];
		int target_list[1], target_count;
		bool tn_is_ml;

		if ((target_count = ProcessTargetString(
			arg1,
			client,
			target_list,
			1,
			COMMAND_FILTER_NO_MULTI | COMMAND_FILTER_NO_IMMUNITY, 
			target_name,
			sizeof(target_name),
			tn_is_ml)) <= 0
		|| target_count == 0) {
			ReplyToTargetError(client, target_count);
			return Plugin_Handled;
		}
		
		int target = target_list[0];
		CReplyToCommand(client, "- FF Review for {olive}%N -", target);
		if(pData[target].isTroll) {
			CReplyToCommand(client, "{olive}- will be banned on disconnect for TK -", target);
		}
		if(pData[target].immunityFlags == Immune_TK) {
			CReplyToCommand(client, "Immunity: {yellow}Teamkiller Detection", target);
		} else if(pData[target].immunityFlags == Immune_RFF) {
			CReplyToCommand(client, "Immunity: {yellow}Auto reverse-ff", target);
		} else if(view_as<int>(pData[target].immunityFlags) > 0) {
			CReplyToCommand(client, "Immunity: {yellow}Teamkiller Detection, Auto reverse-ff", target);
		} else {
			CReplyToCommand(client, "Immunity: {yellow}None", target);
			CReplyToCommand(client, "\tUse {olive}/ignore <player> [immunity type]{default} to toggle");
		}
		float minutesSinceiLastFFTime = GetLastFFMinutes(target);
		float activeRate = GetActiveRate(target);
		CReplyToCommand(client, "FF Frequency: {yellow}%d {default}(recent: %d, %d forgiven)", pData[target].totalFFCount, pData[target].ffCount, (pData[target].totalFFCount - pData[target].ffCount));
		if(pData[client].lastFFTime == 0)
			CReplyToCommand(client, "Total FF Damage: {yellow}%.1f HP{default} (last ff Never)", pData[target].totalDamageFF);
		else
			CReplyToCommand(client, "Total FF Damage: {yellow}%.1f HP{default} (last ff %.1f min ago)", pData[target].totalDamageFF, minutesSinceiLastFFTime);
		if(~pData[target].immunityFlags & Immune_TK)
			CReplyToCommand(client, "Recent FF (TKDetectBuffer): {yellow}%.1f", pData[target].TKDamageBuffer);
		if(~pData[target].immunityFlags & Immune_RFF)
			CReplyToCommand(client, "Auto Reverse-FF: {yellow}%.1fx rate", activeRate);
		CReplyToCommand(client, "Attempted suicide jumps: {yellow}%d", pData[target].jumpAttempts);
	} else {
		for(int i = 1; i <= MaxClients; i++) {
			if(IsClientConnected(i) && IsClientInGame(i) && !IsFakeClient(i)) {
				float minutesSinceiLastFFTime = (time - pData[i].lastFFTime) / 60.0;
				float activeRate = pData[i].autoRFFScaleFactor - (minutesSinceiLastFFTime * hFFAutoScaleForgivenessAmount.FloatValue);
				if(activeRate < 0.0) {
					activeRate = 0.0;
				} 
				PrintToConsoleAll("%20N: %.1f TK-FF buf / %.2f total ff / %d freq. (intrl %d) | %.3f (buf %f) rFF rate | lastff %.1f min ago | %d suicide jumps", 
					i,
					pData[i].TKDamageBuffer, 
					pData[i].totalDamageFF, 
					pData[i].totalFFCount,
					pData[i].ffCount,
					activeRate, 
					pData[i].autoRFFScaleFactor, 
					minutesSinceiLastFFTime, 
					pData[i].jumpAttempts
				);
			}
		}
	}
	return Plugin_Handled;
}


Action Command_IgnorePlayer(int client, int args) {
	char arg1[32], arg2[16];
	GetCmdArg(1, arg1, sizeof(arg1));
	GetCmdArg(2, arg2, sizeof(arg2));

	if(args < 2) {
		CReplyToCommand(client, "Usage: {yellow}sm_ignore <player> <tk|teamkill / rff|reverseff>");
		return Plugin_Handled;
	}

	int flags = 0;
	if(StrEqual(arg2, "tk") || StrEqual(arg2, "teamkill")) {
		flags = Immune_TK;
	} else if(arg2[0] == 'a') {
		flags = Immune_TK | Immune_RFF;
	} else if(StrEqual(arg2, "reverseff") || StrEqual(arg2, "rff")) {
		flags = Immune_RFF;
	} else {
		CReplyToCommand(client, "Usage: {yellow}sm_ignore <player> <tk|teamkill / rff|reverseff>");
		return Plugin_Handled;
	}

	char target_name[MAX_TARGET_LENGTH];
	int target_list[MAXPLAYERS+1], target_count;
	bool tn_is_ml;

	if ((target_count = ProcessTargetString(
		arg1,
		client,
		target_list,
		MaxClients,
		COMMAND_FILTER_NO_IMMUNITY | COMMAND_FILTER_NO_BOTS, 
		target_name,
		sizeof(target_name),
		tn_is_ml)) <= 0
	) {
		ReplyToTargetError(client, target_count);
		return Plugin_Handled;
	}

	for (int i = 0; i < target_count; i++) {
		int target = target_list[i];
		/*if (GetUserAdmin(target) != INVALID_ADMIN_ID) {
			ReplyToCommand(client, "%N is an admin and is already immune.", target);
			return Plugin_Handled;
		}*/

		if (flags & Immune_TK) {
			if (pData[target].immunityFlags & Immune_TK) {
				LogAction(client, target, "\"%L\" re-enabled teamkiller detection for \"%L\"",  client, target);
				CShowActivity2(client, "[FTT] ", "{yellow}%N{default} has re-enabled teamkiller detection for {olive}%N", client, target);
			} else {
				LogAction(client, target, "\"%L\" ignored teamkiller detection for \"%L\"",  client, target);
				CShowActivity2(client, "[FTT] ", "{yellow}%N{default} has ignored teamkiller detection for {olive}%N", client, target);
			}
			pData[target].immunityFlags ^= Immune_TK;
		} 

		if (flags & Immune_RFF) {
			if (pData[target].immunityFlags & Immune_RFF) {
				LogAction(client, target, "\"%L\" re-enabled auto reverse friendly-fire for \"%L\"",  client, target);
				CShowActivity2(client, "[FTT] ", "{yellow}%N{default} has enabled auto reverse friendly-fire for {olive}%N", client, target);
			} else {
				LogAction(client, target, "\"%L\" disabled auto reverse friendly-fire for \"%L\"",  client, target);
				CShowActivity2(client, "[FTT] ", "{yellow}%N{default} has disabled auto reverse friendly-fire for {olive}%N", client, target);
				pData[target].autoRFFScaleFactor = 0.0;
			}
			pData[target].immunityFlags ^= Immune_RFF;
		}

		pData[target].isTroll = false;
	}
	return Plugin_Handled;
}

public int Native_SetImmunity(Handle plugin, int numParams) {
	int target = GetNativeCell(1);
	int flag = GetNativeCell(2);
	_CheckNative(target, flag);
	bool value = GetNativeCell(3);
	char flagName[32];
	GetImmunityFlagName(flag, flagName, sizeof(flagName));
	if(value) {
		// Remove immunity
		pData[target].immunityFlags &= ~flag;
		LogAction(0, target, "removed immunity flag \"%s\" from \"%L\"", flagName, target);
	} else {
		// Add immunity
		pData[target].immunityFlags |= flag;
		LogAction(0, target, "added immunity flag \"%s\" to \"%L\"", flagName, target);
	}
	return 0;
}

void GetImmunityFlagName(int flag, char[] buffer, int bufferLength) {
	if(flag == Immune_RFF) {
		strcopy(buffer, bufferLength, "Reverse Friendly-Fire");
	} else if(flag == Immune_TK) {
		strcopy(buffer, bufferLength, "Teamkiller Detection");
	} else {
		strcopy(buffer, bufferLength, "-error: unknown flag-");
	}
}

public int Native_GetImmunity(Handle plugin, int numParams) {
	int target = GetNativeCell(1);
	int flag = GetNativeCell(2);
	_CheckNative(target, flag);
	return pData[target].immunityFlags & flag;
}

void _CheckNative(int target, int flag) {
	if(target <= 0 || target >= MaxClients) {
		ThrowNativeError(SP_ERROR_NATIVE, "Target is out of range (1 to MaxClients)");
	} else if(flag <= 0) {
		ThrowNativeError(SP_ERROR_NATIVE, "Flag is invalid");
	}
}
void WarnStillMarked() {
	for(int i = 1; i <= MaxClients; i++) {
		if(pData[i].isTroll && IsClientConnected(i) && IsClientInGame(i)) {
			CPrintChatToAdmins("Note: {yellow}%N is still marked as troll and will be banned after this game. Use {olive}/ignore <player> tk{default} to ignore them.", i);
		}
	}
}
/// STOCKS

float GetLastFFMinutes(int client) {
	return (GetTime() - pData[client].lastFFTime) / 60.0;
}

float GetActiveRate(int client) {
	float activeRate = pData[client].autoRFFScaleFactor - (GetLastFFMinutes(client) * hFFAutoScaleForgivenessAmount.FloatValue);
	if(activeRate < 0.0) activeRate = 0.0;
	return activeRate;
}

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
