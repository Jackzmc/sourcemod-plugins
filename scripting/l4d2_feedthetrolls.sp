#pragma semicolon 1
#pragma newdecls required

//#define DEBUG

#define MAIN_TIMER_INTERVAL_S 5.0
#define PLUGIN_VERSION "1.0"

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <jutils>
#include <left4dhooks>
#include <sceneprocessor>
#include <l4d2_behavior>
#include <ftt>
#include <multicolors>


public Plugin myinfo = 
{
	name = "L4D2 Feed The Trolls", 
	author = "jackzmc", 
	description = "https://forums.alliedmods.net/showthread.php?t=325331", 
	version = PLUGIN_VERSION, 
	url = ""
};

//TODO: Make bots target player. Possibly automatic . See https://i.jackz.me/2021/05/NVIDIA_Share_2021-05-05_19-36-51.png
//TODO: Friendly trolling VS punishment trolling
//TODO: Trolls: Force take pills, Survivor Bot Magnet

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
	if(late) {
		lateLoaded = true;
	}
} 

public void OnPluginStart() {
	EngineVersion g_Game = GetEngineVersion();
	if(g_Game != Engine_Left4Dead2) {
		SetFailState("This plugin is for L4D/L4D2 only.");	
	}
	LoadTranslations("common.phrases");
	g_iAmmoTable = FindSendPropInfo("CTerrorPlayer", "m_iAmmo");

	g_PlayerMarkedForward = new GlobalForward("FTT_OnClientMarked", ET_Ignore, Param_Cell, Param_Cell);

	REPLACEMENT_PHRASES = new StringMap();
	LoadPhrases();
	SetupTrolls();

	GameData data = new GameData("l4d2_behavior");
	
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
	hMagnetTargetMode   = CreateConVar("sm_ftt_magnet_targetting", "1", "How does the specials target players. Add bits together\n0= Target until Dead, 1=Specials ignore incapped, 2=Tank ignores incapped");
	hShoveFailChance 	= CreateConVar("sm_ftt_shove_fail_chance", "0.5", "The % chance that a shove fails", FCVAR_NONE, true, 0.0, true, 1.0);
	hWitchTargetIncapp  = CreateConVar("sm_ftt_witch_target_incapped", "1", "Should the witch target witch magnet victims who are incapped?\n 0 = No, 1 = Yes", FCVAR_NONE, true, 0.0, true, 1.0);

	RegAdminCmd("sm_ftl", Command_ListTheTrolls, ADMFLAG_KICK, "Lists all the trolls currently ingame.");
	RegAdminCmd("sm_ftm", Command_ListModes, ADMFLAG_KICK, "Lists all the troll modes and their description");
	RegAdminCmd("sm_ftr", Command_ResetUser, ADMFLAG_KICK, "Resets user of any troll effects.");
	RegAdminCmd("sm_fta", Command_ApplyUser, ADMFLAG_KICK, "Apply a troll mod to a player, or shows menu if no parameters.");
	RegAdminCmd("sm_ftt", Command_FeedTheTrollMenu, ADMFLAG_KICK, "Opens a list that shows all the commands");
	RegAdminCmd("sm_mark", Command_MarkPendingTroll, ADMFLAG_KICK, "Marks a player as to be banned on disconnect");
	RegAdminCmd("sm_ftc", Command_FeedTheCrescendoTroll, ADMFLAG_KICK, "Applies a manual punish on the last crescendo activator");
	RegAdminCmd("sm_witch_attack", Command_WitchAttack, ADMFLAG_CHEATS, "Makes all witches target a player");
	RegAdminCmd("sm_insta", Command_InstaSpecial, ADMFLAG_KICK, "Spawns a special that targets them, close to them.");
	RegAdminCmd("sm_instaface", Command_InstaSpecialFace, ADMFLAG_KICK, "Spawns a special that targets them, right in their face.");
	RegAdminCmd("sm_inface", Command_InstaSpecialFace, ADMFLAG_KICK, "Spawns a special that targets them, right in their face.");

	HookEvent("player_disconnect", Event_PlayerDisconnect);
	HookEvent("player_death", Event_PlayerDeath);
	HookEvent("triggered_car_alarm", Event_CarAlarm);
	HookEvent("witch_harasser_set", Event_WitchVictimSet);
	
	AddNormalSoundHook(view_as<NormalSHook>(SoundHook));

	AutoExecConfig(true, "l4d2_feedthetrolls");

	if(lateLoaded) {
		CreateTimer(MAIN_TIMER_INTERVAL_S, Timer_Main, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
		HookEntityOutput("func_button", "OnPressed", Event_ButtonPress);
	}
}

///////////////////////////////////////////////////////////////////////////////
// CVAR CHANGES
///////////////////////////////////////////////////////////////////////////////

public void Change_ThrowInterval(ConVar convar, const char[] oldValue, const char[] newValue) {
	//If a throw timer exists (someone has mode 11), destroy & recreate w/ new interval
	if(hThrowTimer != INVALID_HANDLE) {
		delete hThrowTimer;
		PrintToServer("Reset new throw item timer");
		hThrowTimer = CreateTimer(convar.FloatValue, Timer_ThrowTimer, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	}
}

///////////////////////////////////////////////////////////////////////////////
// METHODS
///////////////////////////////////////////////////////////////////////////////

void ThrowAllItems(int victim) {
	float vicPos[3], destPos[3];
	int clients[4];
	GetClientAbsOrigin(victim, vicPos);
	//Find a bot to throw to
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
	PrintToConsoleAll("Flow Check | Player=%N Flow=%f Delta=%f", farthestClient, highestFlow, difference);
	PrintToConsoleAll("Flow Check | Player2=%N Flow2=%f", secondClient, secondHighestFlow);
	return client == farthestClient && difference > distance;
}

int GetAutoPunishMode() {
	int number = 2 ^ GetRandomInt(0, AUTOPUNISH_MODE_COUNT - 1);
	if(hAutoPunish.IntValue & number == 0) {
		return GetAutoPunishMode();
	}else{
		return number;
	}
}

stock int GetPrimaryReserveAmmo(int client) {
	int weapon = GetPlayerWeaponSlot(client, 0);
	if(weapon > -1) {
		int primaryAmmoType = GetEntProp(weapon, Prop_Send, "m_iPrimaryAmmoType");
		return GetEntData(client, g_iAmmoTable + (primaryAmmoType * 4));
	} else {
		return -1;
	}
}
stock bool SetPrimaryReserveAmmo(int client, int amount) {
	int weapon = GetPlayerWeaponSlot(client, 0);
	if(weapon > -1) {
		int primaryAmmoType = GetEntProp(weapon, Prop_Send, "m_iPrimaryAmmoType");
		SetEntData(client, g_iAmmoTable + (primaryAmmoType * 4), amount);
		return true;
	} else {
		return false;
	}
}

stock void SendChatToAll(int client, const char[] message) {
	char nameBuf[MAX_NAME_LENGTH];
	
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i) && IsFakeClient(i)) {
			FormatActivitySource(client, i, nameBuf, sizeof(nameBuf));
			PrintToChat(i, "\x03 %s : \x01%s", nameBuf, message);
		}
	}
}

stock float GetTempHealth(int client) {
	//First filter -> Must be a valid client, successfully in-game and not an spectator (The dont have health).
	if(!client || !IsValidEntity(client) || !IsClientInGame(client)|| !IsPlayerAlive(client) || IsClientObserver(client)) {
		return -1.0;
	}
	
	//If the client is not on the survivors team, then just return the normal client health.
	if(GetClientTeam(client) != 2) {
		return 0.0;
	}
	
	//First, we get the amount of temporal health the client has
	float buffer = GetEntPropFloat(client, Prop_Send, "m_healthBuffer");

	//In case the buffer is 0 or less, we set the temporal health as 0, because the client has not used any pills or adrenaline yet
	if(buffer <= 0.0) return 0.0;


	//This is the difference between the time we used the temporal item, and the current time
	float difference = GetGameTime() - GetEntPropFloat(client, Prop_Send, "m_healthBufferTime");
	
	//We get the decay rate from this convar (Note: Adrenaline uses this value)
	float decay = GetConVarFloat(FindConVar("pain_pills_decay_rate"));
	
	//This is a constant we create to determine the amount of health. This is the amount of time it has to pass
	//before 1 Temporal HP is consumed.
	float constant = 1.0 / decay;
	
	//Then we do the calcs
	return buffer - (difference / constant);
}