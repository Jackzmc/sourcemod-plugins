#pragma semicolon 1
#pragma newdecls required

//#define DEBUG

#define MAIN_TIMER_INTERVAL_S 5.0
#define PLUGIN_VERSION "1.0"
#define ANTI_RUSH_DEFAULT_FREQUENCY 20.0
#define ANTI_RUSH_FREQ_INC 0.75

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <jutils>
#include <left4dhooks>
#tryinclude <sceneprocessor>
#tryinclude <actions>
#include <basecomm>
#include <ftt>
#include <multicolors>
#tryinclude <l4d_anti_rush>


public Plugin myinfo = 
{
	name = "L4D2 Feed The Trolls", 
	author = "jackzmc", 
	description = "https://forums.alliedmods.net/showthread.php?t=325331", 
	version = PLUGIN_VERSION, 
	url = "https://github.com/Jackzmc/sourcemod-plugins"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
	CreateNative("ApplyTroll", Native_ApplyTroll);
	return APLRes_Success;
}


public void OnPluginStart() {
	EngineVersion g_Game = GetEngineVersion();
	if(g_Game != Engine_Left4Dead2) {
		SetFailState("This plugin is for L4D2 only.");	
	}
	LoadTranslations("common.phrases");

	g_PlayerMarkedForward = new GlobalForward("OnTrollMarked", ET_Ignore, Param_Cell, Param_Cell);
	g_TrollAppliedForward = new GlobalForward("OnTrollApplied", ET_Ignore, Param_Cell, Param_Cell);


	// Load core things (trolls & phrases):
	REPLACEMENT_PHRASES = new StringMap();
	TYPOS_DICT = new StringMap();
	LoadPhrases();
	LoadTypos();
	SetupTrolls();
	SetupsTrollCombos();

	CreateTimer(1.0, Timer_DecreaseAntiRush, TIMER_REPEAT);

	g_spSpawnQueue = new ArrayList(sizeof(SpecialSpawnRequest));

	// Witch target overwrite stuff:
	GameData data = new GameData("feedthetrolls");
	StartPrepSDKCall(SDKCall_Raw);
	PrepSDKCall_SetFromConf(data, SDKConf_Signature, "WitchAttack::WitchAttack");
	PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer, VDECODE_FLAG_ALLOWNULL | VDECODE_FLAG_ALLOWWORLD);
	g_hWitchAttack = EndPrepSDKCall();
	delete data;
	
	hThrowItemInterval = CreateConVar("sm_ftt_throw_interval", "30", "The interval in seconds to throw items. 0 to disable", FCVAR_NONE, true, 0.0);
	hThrowItemInterval.AddChangeHook(Change_ThrowInterval);
	hAutoPunish 		= CreateConVar("sm_ftt_autopunish_action", "0", "Setup automatic punishment of players. Add bits together\n0=Disabled, 1=Tank magnet, 2=Special magnet, 4=Swarm, 8=InstantVomit", FCVAR_NONE, true, 0.0);
	hAutoPunishExpire 	= CreateConVar("sm_ftt_autopunish_expire", "0", "How many minutes of gametime until autopunish is turned off? 0 for never.", FCVAR_NONE, true, 0.0);
	hMagnetChance 	 	= CreateConVar("sm_ftt_magnet_chance", "1.0", "% of the time that the magnet will work on a player.", FCVAR_NONE, true, 0.0, true, 1.0);
	hMagnetTargetMode   = CreateConVar("sm_ftt_magnet_targetting", "6", "How does the specials target players. Add bits together\n0=Incapped are ignored, 1=Specials targets incapped, 2=Tank targets incapped 4=Witch targets incapped");
	hShoveFailChance 	= CreateConVar("sm_ftt_shove_fail_chance", "0.65", "The % chance that a shove fails", FCVAR_NONE, true, 0.0, true, 1.0);
	hBadThrowHitSelf    = CreateConVar("sm_ftt_badthrow_fail_chance", "1", "The % chance that on a throw, they will instead hit themselves. 0 to disable", FCVAR_NONE, true, 0.0, true, 1.0);
	hBotReverseFFDefend = CreateConVar("sm_ftt_bot_defend", "0", "Should bots defend themselves?\n0 = OFF\n1 = Will retaliate against non-admins\n2 = Anyone", FCVAR_NONE, true, 0.0, true, 2.0);
	hAntirushBaseFreq   = CreateConVar("sm_ftt_antirush_freq_base", "24", "The base frequency of anti-rush", FCVAR_NONE, true, 0.0);
	hAntirushIncFreq    = CreateConVar("sm_ftt_antirush_freq_inc", "1", "The incremental frequency of anti-rush", FCVAR_NONE, true, 0.0);
	hBotDefendChance = CreateConVar("sm_ftt_bot_defend_chance", "0.75", "% Chance bots will defend themselves.", FCVAR_NONE, true, 0.0, true, 1.0);

	hSbFriendlyFire = FindConVar("sb_friendlyfire");

	if(hBotReverseFFDefend.IntValue > 0) hSbFriendlyFire.BoolValue = true;
	hBotReverseFFDefend.AddChangeHook(Change_BotDefend);

	RegAdminCmd("sm_ftl",  Command_ListTheTrolls, ADMFLAG_GENERIC, "Lists all the trolls currently ingame.");
	RegAdminCmd("sm_ftm",  Command_ListModes,     ADMFLAG_GENERIC, "Lists all the troll modes and their description");
	RegAdminCmd("sm_ftr",  Command_ResetUser, 	  ADMFLAG_GENERIC, "Resets user of any troll effects.");
	RegAdminCmd("sm_fta",  Command_ApplyUser,     ADMFLAG_KICK, "Apply a troll mod to a player, or shows menu if no parameters.");
	RegAdminCmd("sm_ftas", Command_ApplyUserSilent,  ADMFLAG_ROOT, "Apply a troll mod to a player, or shows menu if no parameters.");
	RegAdminCmd("sm_ftt",  Command_FeedTheTrollMenu, ADMFLAG_GENERIC, "Opens a list that shows all the commands");
	RegAdminCmd("sm_mark", Command_MarkPendingTroll, ADMFLAG_KICK, "Marks a player as to be banned on disconnect");
	RegAdminCmd("sm_ftp",  Command_FeedTheCrescendoTroll, ADMFLAG_KICK, "Applies a manual punish on the last crescendo activator");
	RegAdminCmd("sm_ftc",  Command_ApplyComboTrolls, ADMFLAG_KICK, "Applies predefined combinations of trolls");
	#if defined _actions_included
	RegAdminCmd("sm_witch_attack", Command_WitchAttack, ADMFLAG_BAN, "Makes all witches target a player");
	#endif
	RegAdminCmd("sm_insta", Command_InstaSpecial, ADMFLAG_KICK, "Spawns a special that targets them, close to them.");
	RegAdminCmd("sm_stagger", Command_Stagger, ADMFLAG_KICK, "Stagger a player");
	RegAdminCmd("sm_inface", Command_InstaSpecialFace, ADMFLAG_KICK, "Spawns a special that targets them, right in their face.");
	RegAdminCmd("sm_bots_attack", Command_BotsAttack, ADMFLAG_BAN, "Instructs all bots to attack a player until they have X health.");
	RegAdminCmd("sm_scharge", Command_SmartCharge, ADMFLAG_BAN, "Auto Smart charge");
	RegAdminCmd("sm_healbots", Command_HealTarget, ADMFLAG_BAN, "Make bots heal a player");

	HookEvent("player_spawn", Event_PlayerSpawn);
	HookEvent("player_first_spawn", Event_PlayerFirstSpawn);
	HookEvent("player_death", Event_PlayerDeath);
	HookEvent("triggered_car_alarm", Event_CarAlarm);
	HookEvent("witch_harasser_set", Event_WitchVictimSet);
	HookEvent("door_open", Event_DoorToggle);
	HookEvent("door_close", Event_DoorToggle);
	HookEvent("adrenaline_used", Event_SecondaryHealthUsed);
	HookEvent("pills_used", Event_SecondaryHealthUsed);
	HookEvent("entered_spit", Event_EnteredSpit);
	HookEvent("bot_player_replace", Event_BotPlayerSwap);
	HookEvent("heal_success", Event_HealSuccess);
	
	AddNormalSoundHook(SoundHook);

	AutoExecConfig(true, "l4d2_feedthetrolls");

	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i)) {
			SDKHook(i, SDKHook_OnTakeDamage, Event_TakeDamage);
		}
	}
}
///////////////////////////////////////////////////////////////////////////////
// CVAR CHANGES
///////////////////////////////////////////////////////////////////////////////

public void Change_ThrowInterval(ConVar convar, const char[] oldValue, const char[] newValue) {
	//If a throw timer exists (someone has mode 11), destroy & recreate w/ new interval
	if(hThrowTimer != INVALID_HANDLE) {
		delete hThrowTimer;
		hThrowTimer = CreateTimer(convar.FloatValue, Timer_ThrowTimer, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	}
}

// Turn on bot FF if bot defend enabled
public void Change_BotDefend(ConVar convar, const char[] oldValue, const char[] newValue) {
	hSbFriendlyFire.IntValue = convar.IntValue != 0;
}

///////////////////////////////////////////////////////////////////////////////
// METHODS - Old methods, some are also in feedthetrolls/misc.inc
///////////////////////////////////////////////////////////////////////////////


void ThrowAllItems(int victim) {
	float vicPos[3], destPos[3];
	int clients[4];
	GetClientAbsOrigin(victim, vicPos);
	//Find a survivor to throw to (grabs the first nearest non-self survivor)
	int clientCount = GetClientsInRange(vicPos, RangeType_Visibility, clients, sizeof(clients));
	for(int i = 0; i < clientCount; i++) {
		if(clients[i] != victim) {
			GetClientAbsOrigin(clients[i], destPos);
			break;
		}
	}

	//Loop all item slots
	for(int slot = 0; slot <= 4; slot++) {
		Handle pack;
		CreateDataTimer(0.22 * float(slot), Timer_ThrowWeapon, pack);

		WritePackFloat(pack, destPos[0]);
		WritePackFloat(pack, destPos[1]);
		WritePackFloat(pack, destPos[2]);
		WritePackCell(pack, slot);
		WritePackCell(pack, victim);
	}
}

bool IsPlayerFarDistance(int client, float distance) {
	int farthestClient = -1, secondClient = -1;
	float highestFlow, secondHighestFlow;
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == 2) {
			float flow = L4D2Direct_GetFlowDistance(i);
			if(flow > highestFlow || farthestClient == -1) {
				secondHighestFlow = highestFlow;
				secondClient = farthestClient;
				farthestClient = i;
				highestFlow = flow;
			}
		}
	}
	//Incase the first player checked is the farthest:
	if(secondClient == -1) {
		for(int i = 1; i <= MaxClients; i++) {
			if(IsClientConnected(i) && IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == 2) {
				float flow = L4D2Direct_GetFlowDistance(i);
				if(farthestClient != i && ((flow < highestFlow && flow > secondHighestFlow) || secondClient == -1)) {
					secondClient = i;
					secondHighestFlow = flow;
				}
			}
		}
	}
	float difference = highestFlow - secondHighestFlow;
	PrintToConsoleAll("Flow Check | Player1=%N Flow1=%f Delta=%f", farthestClient, highestFlow, difference);
	PrintToConsoleAll("Flow Check | Player2=%N Flow2=%f", secondClient, secondHighestFlow);
	return client == farthestClient && difference > distance;
}

BehaviorAction CreateWitchAttackAction(int target = 0) {
    BehaviorAction action = ActionsManager.Allocate(18556);    
    SDKCall(g_hWitchAttack, action, target);
    return action;
}  

Action OnWitchActionUpdate(BehaviorAction action, int actor, float interval, ActionResult result) {
    /* Change to witch attack */
    result.type = CHANGE_TO;
    result.action = CreateWitchAttackAction(g_iWitchAttackVictim);
    result.SetReason("FTT");
    return Plugin_Handled;
} 
