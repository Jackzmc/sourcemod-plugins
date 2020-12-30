#pragma semicolon 1
#pragma newdecls required

//#define DEBUG

#define MAIN_TIMER_INTERVAL_S 5.0
#define PLUGIN_VERSION "1.0"

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include "jutils.inc"

#undef REQUIRE_PLUGIN
#include <adminmenu>

/*
1 -> Slow speed (0.8 < 1.0 base)
2 -> Higher gravity (1.3 > 1.0)
3 -> Set primary reserve ammo in half
4 -> UziRules (Pickup weapon defaults to uzi)
5 -> PrimaryDisable (Cannot pickup primary weapons at all)
6 -> Slow Drain (Slowly drains hp over time)
7 -> Clusmy (Drops their melee weapon)
8 -> IcantSpellNoMore (Chat messages letter will randomly changed with wrong letters )
9 -> CameTooEarly (When they shoot, they empty the whole clip at once.)
10 -> KillMeSoftly (Make player eat or waste pills whenever)
11 -> ThrowItAll (Makes player just throw all their items at a nearby player, and periodically)
*/
#define TROLL_MODE_COUNT 13
enum TrollMode {
	Troll_Reset, //0
	Troll_SlowSpeed, //1
	Troll_HigherGravity, //2
	Troll_HalfPrimaryAmmo, //3
	Troll_UziRules, //4
	Troll_PrimaryDisable, //5
	Troll_SlowDrain, //6
	Troll_Clumsy, //7
	Troll_iCantSpellNoMore, //8
	Troll_CameTooEarly, //9
	Troll_KillMeSoftly, //10
	Troll_ThrowItAll, //11
	Troll_GunJam //12
}
static const char TROLL_MODES_NAMES[TROLL_MODE_COUNT][32] = {
	"Reset User", //0
	"Slow Speed", //1
	"Higher Gravity", //2 
	"Half Primary Ammo", //3 
	"UziRules", //4
	"PrimaryDisable", //5
	"SlowDrain", //6
	"Clusmy", //7
	"iCantSpellNoMore", //8
	"CameTooEarly", //9
	"KillMeSoftly", //10
	"ThrowItAll", //11
	"GunJam" //12
};
static const char TROLL_MODES_DESCRIPTIONS[TROLL_MODE_COUNT][128] = {
	"Resets the user, removes all troll effects", //0
	"Sets player speed to 0.8x of normal speed", //1
	"Sets player gravity to 1.3x of normal gravity", //2 
	"Cuts their primary reserve ammo in half", //3 
	"Picking up a weapon gives them a UZI instead", //4
	"Player cannot pickup any weapons, only melee/pistols", //5
	"Player slowly loses health", //6
	"Player drops axe periodically or on demand", //7
	"Chat messages letter will randomly changed with wrong letters ", //8
	"When they shoot, random chance they empty whole clip", //9
	"Make player eat or waste pills whenever possible", //10
	"Player throws all their items at nearby player, periodically", //11
	"On reload, small chance their gun gets jammed - Can't reload." //12
};

public Plugin myinfo = 
{
	name = "L4D(2) Feed The Trolls", 
	author = "jackzmc", 
	description = "https://forums.alliedmods.net/showthread.php?t=325331", 
	version = PLUGIN_VERSION, 
	url = ""
};
Handle hThrowTimer;
ConVar hVictimsList, hThrowItemInterval;
bool bTrollTargets[MAXPLAYERS+1], lateLoaded;
int iTrollMode = 0; //troll mode. 0 -> Slosdown | 1 -> Higher Gravity | 2 -> CameTooEarly | 3 -> UziRules

int g_iAmmoTable;
TrollMode iTrollUsers[MAXPLAYERS+1];
int gChargerVictim = -1;

bool bChooseVictimAvailable = false;

//plugin start
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
	if(late) {
		lateLoaded = true;
	}
} 
//TODO: Register a main loop (create / destroy on troll targets count). Implement 'slow drain' with loop.

public void OnPluginStart() {
	EngineVersion g_Game = GetEngineVersion();
	if(g_Game != Engine_Left4Dead && g_Game != Engine_Left4Dead2) {
		SetFailState("This plugin is for L4D/L4D2 only.");	
	}
	LoadTranslations("common.phrases");
	g_iAmmoTable = FindSendPropInfo("CTerrorPlayer", "m_iAmmo");

	hVictimsList = CreateConVar("sm_ftt_victims", "", "Comma seperated list of steamid64 targets (ex: STEAM_0:0:75141700)", FCVAR_NONE);
	hVictimsList.AddChangeHook(Change_VictimList);
	hThrowItemInterval = CreateConVar("sm_ftt_throw_interval", "30", "The interval in seconds to throw items. 0 to disable", FCVAR_NONE, true, 0.0);
	hThrowItemInterval.AddChangeHook(Change_ThrowInterval);

	RegAdminCmd("sm_ftl", Command_ListTheTrolls, ADMFLAG_ROOT, "Lists all the trolls currently ingame.");
	RegAdminCmd("sm_ftm", Command_ListModes, ADMFLAG_ROOT, "Lists all the troll modes and their description");
	RegAdminCmd("sm_ftr", Command_ResetUser, ADMFLAG_ROOT, "Reset user");
	RegAdminCmd("sm_fta", Command_ApplyUser, ADMFLAG_ROOT, "apply mode");

	if(lateLoaded) {
		UpdateTrollTargets();
		CreateTimer(MAIN_TIMER_INTERVAL_S, Timer_Main, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	}

}

//(dis)connection events
public void OnMapStart() {
	CreateTimer(MAIN_TIMER_INTERVAL_S, Timer_Main, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}
public void OnClientAuthorized(int client, const char[] auth) {
    if(StrContains(auth, "BOT", true) == -1) {
        TestForTarget(client, auth);
    }
}
public void OnClientDisconnect(int client) {
	bTrollTargets[client] = false;
}
// #region evrnts
public void Change_VictimList(ConVar convar, const char[] oldValue, const char[] newValue) {
    UpdateTrollTargets();
}
public void Change_ThrowInterval(ConVar convar, const char[] oldValue, const char[] newValue) {
	//If a throw timer exists (someone has mode 11), destroy & recreate w/ new interval
	if(hThrowTimer != INVALID_HANDLE) {
		delete hThrowTimer;
		PrintToServer("Reset new throw item timer");
		hThrowTimer = CreateTimer(convar.FloatValue, Timer_ThrowTimer, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	}
}
// #endregion
// #region commands
public Action Command_ResetUser(int client, int args) {
	if(args < 1) {
		ReplyToCommand(client, "Usage: sm_ftr <user(s)>");
	}else{
		char arg1[32];
		GetCmdArg(1, arg1, sizeof(arg1));
		char target_name[MAX_TARGET_LENGTH];
		int target_list[MAXPLAYERS], target_count;
		bool tn_is_ml;
		if ((target_count = ProcessTargetString(
				arg1,
				client,
				target_list,
				MAXPLAYERS,
				COMMAND_FILTER_ALIVE, /* Only allow alive players */
				target_name,
				sizeof(target_name),
				tn_is_ml)) <= 0)
		{
			/* This function replies to the admin with a failure message */
			ReplyToTargetError(client, target_count);
			return Plugin_Handled;
		}
		for (int i = 0; i < target_count; i++)
		{
			ResetClient(target_list[i]);
			ShowActivity(client, "reset troll effects on \"%N\". ", target_list[i]);
		}
		ReplyToCommand(client, "Cleared troll effects for %d players", target_count);
	}
	return Plugin_Handled;
}
public Action Command_ApplyUser(int client, int args) {
	if(args < 2) {
		Menu menu = new Menu(ChoosePlayerHandler);
		menu.SetTitle("Choose a player");
		for(int i = 1; i < MaxClients; i++) {
			if(IsClientConnected(i) && IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == 2) {
				char userid[8], display[16];
				Format(userid, sizeof(userid), "%d", GetClientUserId(i));
				GetClientName(i, display, sizeof(display));
				menu.AddItem(userid, display);
			}
		}
		menu.ExitButton = true;
		menu.Display(client, 0);
	}else{
		char arg1[32], arg2[32];
		GetCmdArg(1, arg1, sizeof(arg1));
		GetCmdArg(2, arg2, sizeof(arg2));

		int mode = StringToInt(arg2);
		if(mode == 0) {
			ReplyToCommand(client, "Not a valid mode. Must be greater than 0. Usage: sm_fta <player> <mode>. Use sm_ftr <player> to reset.");
		}else{
			char target_name[MAX_TARGET_LENGTH];
			int target_list[MAXPLAYERS], target_count;
			bool tn_is_ml;
			if ((target_count = ProcessTargetString(
					arg1,
					client,
					target_list,
					MAXPLAYERS,
					COMMAND_FILTER_ALIVE, /* Only allow alive players */
					target_name,
					sizeof(target_name),
					tn_is_ml)) <= 0)
			{
				/* This function replies to the admin with a failure message */
				ReplyToTargetError(client, target_count);
				return Plugin_Handled;
			}
			for (int i = 0; i < target_count; i++)
			{
				if(GetClientTeam(target_list[i]) == 2)
					ApplyModeToClient(client, target_list[i], view_as<TrollMode>(mode), false);
			}
		}
	}
	return Plugin_Handled;
}
public Action Command_ListModes(int client, int args) {
	for(int mode = 0; mode < TROLL_MODE_COUNT; mode++) {
		ReplyToCommand(client, "%d. %s - %s", mode, TROLL_MODES_NAMES[mode], TROLL_MODES_DESCRIPTIONS[mode]);
	}
	return Plugin_Handled;
}
public Action Command_ListTheTrolls(int client, int args) {
	int count = 0;
	for(int i = 1; i < MaxClients; i++) {
		if(IsClientConnected(i) && IsPlayerAlive(i) && view_as<int>(iTrollUsers[i]) > 0) {
			TrollMode mode = iTrollUsers[i];
			ReplyToCommand(client, "%N | Mode %s (#%d)", i, TROLL_MODES_NAMES[mode], mode);
			count++;
		}
	}
	if(count == 0) {
		ReplyToCommand(client, "No clients have a mode applied.");
	}
	return Plugin_Handled;
}
public int ChoosePlayerHandler(Menu menu, MenuAction action, int param1, int param2) {
	/* If an option was selected, tell the client about the item. */
    if (action == MenuAction_Select) {
		char info[16];
		menu.GetItem(param2, info, sizeof(info));
		int userid = StringToInt(info);
		
		Menu trollMenu = new Menu(ChooseModeMenuHandler);
		trollMenu.SetTitle("Choose a troll mode");
		for(int i = 0; i < TROLL_MODE_COUNT; i++) {
			char id[8];
			Format(id, sizeof(id), "%d|%d", userid, i);
			trollMenu.AddItem(id, TROLL_MODES_NAMES[i]);
		}
		trollMenu.ExitButton = true;
		trollMenu.Display(param1, 0);
    } else if (action == MenuAction_End)
        delete menu;
}
public int ChooseModeMenuHandler(Menu menu, MenuAction action, int param1, int param2) {
    /* If an option was selected, tell the client about the item. */
    if (action == MenuAction_Select) {
		char info[16];
		menu.GetItem(param2, info, sizeof(info));
		char str[2][8];
		ExplodeString(info, "|", str, 2, 8, false);
		int client = GetClientOfUserId(StringToInt(str[0]));
		TrollMode mode = view_as<TrollMode>(StringToInt(str[1]));
		//If mode has an option to be single-time fired/continous/both, prompt:
		if(mode == Troll_Clumsy 
			|| mode ==Troll_ThrowItAll
			|| mode == Troll_PrimaryDisable
			|| mode == Troll_CameTooEarly
		) {
			Menu modiferMenu = new Menu(CHooseTrollModiferHandler); 
			modiferMenu.SetTitle("Choose Troll Modifer Option");
			char singleUse[16], multiUse[16], bothUse[16];
			Format(singleUse, sizeof(singleUse), "%d|%d|1");
			Format(multiUse,   sizeof(multiUse), "%d|%d|2");
			Format(bothUse,     sizeof(bothUse), "%d|%d|0");
			menu.AddItem(singleUse, "Activate once");
			menu.AddItem(multiUse, "Activate Periodically");
			menu.AddItem(bothUse, "Activate Periodically & Instantly");
			modiferMenu.ExitButton = true;
			modiferMenu.Display(param1, 0);
		} else {
			ApplyModeToClient(param1, client, mode, 0);
		}
    } else if (action == MenuAction_End)
        delete menu;
}
public int CHooseTrollModiferHandler(Menu menu, MenuAction action, int param1, int param2) {
	if (action == MenuAction_Select) {
		char info[16];
		menu.GetItem(param2, info, sizeof(info));
		char str[3][8];
		ExplodeString(info, "|", str, 3, 8, false);
		int client = GetClientOfUserId(StringToInt(str[0]));
		TrollMode mode = view_as<TrollMode>(StringToInt(str[1]));
		int modifier = StringToInt(str[2]);
		ApplyModeToClient(param1, client, mode, modifier);
	} else if (action == MenuAction_End)	
		delete menu;
}
public Action Event_ItemPickup(int client, int weapon) {
	char wpnName[64];
	GetEdictClassname(weapon, wpnName, sizeof(wpnName));
	if(StrContains(wpnName, "rifle") > -1 
		|| StrContains(wpnName, "smg") > -1 
		|| StrContains(wpnName, "weapon_grenade_launcher") > -1 
		|| StrContains(wpnName, "sniper") > -1
		|| StrContains(wpnName, "shotgun") > -1
	) {
		//If 4: Only UZI, if 5: Can't switch.
		if(iTrollUsers[client] == Troll_UziRules) {
			char currentWpn[32];
			GetClientWeaponName(client, 0, currentWpn, sizeof(currentWpn));
			if(StrEqual(wpnName, "weapon_smg", true)) {
				return Plugin_Continue;
			} else if(StrEqual(currentWpn, "weapon_smg", true)) {
				return Plugin_Stop;
			}else{
				int flags = GetCommandFlags("give");
				SetCommandFlags("give", flags & ~FCVAR_CHEAT);
				FakeClientCommand(client, "give smg");
				SetCommandFlags("give", flags|FCVAR_CHEAT);
				return Plugin_Stop;
			}
		}else if(iTrollUsers[client] == Troll_PrimaryDisable) {
			return Plugin_Stop;
		}
		return Plugin_Continue;
	}else{
		return Plugin_Continue;
	}
}
public Action Event_WeaponReload(int weapon) {
	int client = GetEntPropEnt(weapon, Prop_Send, "m_hOwner");
	if(iTrollUsers[client] == Troll_GunJam) {
		float dec = GetRandomFloat(0.0, 1.0);
		if(FloatCompare(dec, 0.10) == -1) { //10% chance gun jams
			return Plugin_Stop;
		}
	}
	return Plugin_Continue;
}
// #endregion
// #region timer
public Action Timer_ThrowTimer(Handle timer) {
	int count = 0;
	for(int i = 1; i < MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && IsPlayerAlive(i) && iTrollUsers[i] == Troll_ThrowItAll) {
			ThrowAllItems(i);
			count++;
		}
	}
	return count > 0 ? Plugin_Continue : Plugin_Stop;
}
public Action Timer_Main(Handle timer) {
	static int loop;
	for(int i = 1; i < MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && IsPlayerAlive(i)) {
			switch(iTrollUsers[i]) {
				case Troll_SlowDrain:
					if(loop % 4 == 0) {
						int hp = GetClientHealth(i);
						if(hp > 50) {
							SetEntProp(i, Prop_Send, "m_iHealth", hp - 1); 
						}
					}
			}
		}
	}
	if(++loop >= 60) {
		loop = 0;
	}
	return Plugin_Continue;
}
//Applies the selected TrollMode to the victim.
//Modifiers are as followed: 0 -> Both (fire instant, and timer), 1 -> Fire Once, 2 -> Start timer
void ApplyModeToClient(int client, int victim, TrollMode mode, int modifier) {
	ResetClient(victim);
	if(view_as<int>(mode) > TROLL_MODE_COUNT || view_as<int>(mode) < 0) {
		ReplyToCommand(client, "Unknown troll mode ID '%d'. Pick a mode between 1 and %d", mode, TROLL_MODE_COUNT - 1);
		return;
	}

	switch(mode) {
		case Troll_SlowDrain: 
			SetEntPropFloat(victim, Prop_Send, "m_flLaggedMovementValue", 0.8);
		case Troll_HigherGravity:
			SetEntityGravity(victim, 1.3);
		case Troll_HalfPrimaryAmmo: {
			int current = GetPrimaryReserveAmmo(victim);
			SetPrimaryReserveAmmo(victim, current / 2);
		}
		case Troll_UziRules:
			SDKHook(victim, SDKHook_WeaponCanUse, Event_ItemPickup);
		case Troll_PrimaryDisable: 
			SDKHook(victim, SDKHook_WeaponCanUse, Event_ItemPickup);
		case Troll_Clumsy: {
			int wpn = GetClientSecondaryWeapon(victim);
			bool hasMelee = DoesClientHaveMelee(victim);
			if(hasMelee) {
				float pos[3];
				int clients[4];
				GetClientAbsOrigin(victim, pos);
				int clientCount = GetClientsInRange(pos, RangeType_Visibility, clients, sizeof(clients));
				for(int i = 0; i < clientCount; i++) {
					if(clients[i] != victim) {
						float targPos[3];
						GetClientAbsOrigin(clients[i], targPos);
						SDKHooks_DropWeapon(victim, wpn, targPos);
						iTrollUsers[victim] = mode;
						CreateTimer(0.2, Timer_GivePistol);
						return;
					}
				}
				SDKHooks_DropWeapon(victim, wpn);
			}
		}
		case Troll_CameTooEarly:
			ReplyToCommand(client, "This troll mode is not implemented.");
		case Troll_ThrowItAll: {
			ThrowAllItems(victim);
			if(hThrowTimer == INVALID_HANDLE && modifier != 2) {
				PrintToServer("Created new throw item timer");
				hThrowTimer = CreateTimer(hThrowItemInterval.FloatValue, Timer_ThrowTimer, _, TIMER_REPEAT);
			}
		}
		case Troll_GunJam: {
			int wpn = GetClientWeaponEntIndex(victim, 0);
			if(wpn > -1)
				SDKHook(wpn, SDKHook_Reload, Event_WeaponReload);
			else
				ReplyToCommand(client, "Victim does not have a primary weapon.");
		} default: {
			ReplyToCommand(client, "This trollmode is not implemented.");
			PrintToServer("Troll Mode #%d not implemented (%s)", mode, TROLL_MODES_NAMES[mode]);
		}
	}
	ShowActivity(client, "activated troll mode \"%s\" on %N. ", TROLL_MODES_NAMES[mode], victim);
	iTrollUsers[victim] = mode;
}

public Action Timer_GivePistol(Handle timer, int client) {
	int flags = GetCommandFlags("give");
	SetCommandFlags("give", flags & ~FCVAR_CHEAT);
	FakeClientCommand(client, "give pistol");
	SetCommandFlags("give", flags|FCVAR_CHEAT);
}
public Action Timer_ThrowWeapon(Handle timer, Handle pack) {
	ResetPack(pack);
	float dest[3];
	dest[0] = ReadPackFloat(pack);
	dest[1] = ReadPackFloat(pack);
	dest[2] = ReadPackFloat(pack);
	int slot = ReadPackCell(pack);
	int victim = ReadPackCell(pack);

	int wpnRef = GetPlayerWeaponSlot(victim, slot);
	if(wpnRef != -1) {
		int wpn = EntRefToEntIndex(wpnRef);
		if(wpn != INVALID_ENT_REFERENCE) {
			if(slot == 1) {
				char name[16];
				GetEdictClassname(wpn, name, sizeof(name));
				if(!StrEqual(name, "weapon_pistol", false)) {
					SDKHooks_DropWeapon(victim, wpn, dest);
					CreateTimer(0.2, Timer_GivePistol, victim);
				}
			}else 
				SDKHooks_DropWeapon(victim, wpn, dest);
		}
	}
}

void ResetClient(int victim) {
	iTrollUsers[victim] = Troll_Reset;
	SetEntityGravity(victim, 1.0);
	SetEntPropFloat(victim, Prop_Send, "m_flLaggedMovementValue", 1.0);
	SDKUnhook(victim, SDKHook_WeaponCanUse, Event_ItemPickup);
	int wpn = GetClientWeaponEntIndex(victim, 0);
	if(wpn > -1)
		SDKUnhook(wpn, SDKHook_Reload, Event_WeaponReload);
}

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


bool ApplyModeToTargets() {
	int users = 0;
	for(int i=1; i < MaxClients; i++) {
		if(bTrollTargets[i]) {
			users++;
			//clear effects from previous troll:
			SetEntityGravity(i, 1.0);
			SetEntPropFloat(i, Prop_Send, "m_flLaggedMovementValue", 1.0);
			
			if(iTrollMode == 0) { //slow mode, apply slow down affects
				SetEntPropFloat(i, Prop_Send, "m_flLaggedMovementValue", 0.8);
			}else if(iTrollMode == 1) { //higher gravity
				SetEntityGravity(i, 1.2);
			}
		}
	}
	//Stop loop if no one is being affected.
	return (users == 0) ? true : false;
	
}
void UpdateTrollTargets() {
	for(int i = 1; i <= MaxClients; i++) {
        bTrollTargets[i] = false;
        if(IsClientInGame(i) && IsClientAuthorized(i)) {
			if(!IsFakeClient(i)) {
				char auth[64];
				GetClientAuthId(i, AuthId_Steam2, auth, sizeof(auth));
				TestForTarget(i, auth);
			}
		}
	}
}
bool TestForTarget(int client, const char[] auth) {
	char targets[32][8];
	char raw_targets[64];
	hVictimsList.GetString(raw_targets, sizeof(raw_targets));
	ExplodeString(raw_targets, ",", targets, 8, 32, false);
	for(int i = 0; i < 8; i++) {
		if(StrEqual(targets[i], auth, true)) {
            #if defined debug
			PrintToServer("[Debug] Troll target detected with id %d and steamid %s", client, auth);
            #endif
			bTrollTargets[client] = true;
			return true;
		}
	}
	return false;
}
// #endregion
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
