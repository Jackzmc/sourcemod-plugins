#pragma semicolon 1
#pragma newdecls required

//#define DEBUG

#define PLUGIN_VERSION "1.0"

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include "jutils.inc"
#include <dhooks>

#undef REQUIRE_PLUGIN
#include <adminmenu>

/*
1 -> Slow speed (0.8 < 1.0 base)
2 -> Higher gravity (1.3 > 1.0)
3 -> Set primary reserve ammo in half
4 -> UziRules (Pickup weapon defaults to uzi)
5 -> PrimaryDisable (Cannot pickup primary weapons at all)
6 -> Slow Drain
7 -> Clusmy
8 -> IcantSpellNoMore
9 -> CameTooEarly
10 -> KillMeSoftly
*/
enum trollMode {
	Disabled,
	SlowSpeed,
	HigherGravity,
	HalfPrimary,
	UziRules,
	PrimaryDisable,
	SlowDrain,
	Clusmy,
	iCantSpellNoMore,
	CameTooEArly,
	KillMeSoftly
}

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
bool bTrollTargets[MAXPLAYERS+1], lateLoaded, bTimerEnabled = false;
int iTrollMode = 0; //troll mode. 0 -> Slosdown | 1 -> Higher Gravity | 2 -> CameTooEarly | 3 -> UziRules

int g_iAmmoTable;
int iTrollUsers[MAXPLAYERS+1];
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
	TopMenu topmenu;
	if (LibraryExists("adminmenu") && ((topmenu = GetAdminTopMenu()) != null))
	{
		/* If so, manually fire the callback */
		OnAdminMenuReady(topmenu);
	}
	LoadTranslations("common.phrases");
	g_iAmmoTable = FindSendPropInfo("CTerrorPlayer", "m_iAmmo");

	hVictimsList = CreateConVar("sm_ftt_victims", "", "Comma seperated list of steamid64 targets (ex: STEAM_0:0:75141700)", FCVAR_NONE);
	hVictimsList.AddChangeHook(Change_VictimList);
	hThrowItemInterval = CreateConVar("sm_ftt_throw_interval", "30", "The interval in seconds to throw items. 0 to disable", FCVAR_NONE, true, 0.0);
	hThrowItemInterval.AddChangeHook(Change_ThrowInterval);

	RegAdminCmd("sm_ftl", Command_ListTheTrolls, ADMFLAG_ROOT, "Lists all the trolls currently ingame.");

	RegAdminCmd("sm_ftr", Command_ResetUser, ADMFLAG_ROOT, "Reset user");
	RegAdminCmd("sm_fta", Command_ApplyUser, ADMFLAG_ROOT, "apply mode");

	if(lateLoaded) UpdateTrollTargets();

	CreateTimer(10.0, Timer_MainProcess, _, TIMER_REPEAT);
	hThrowTimer = CreateTimer(hThrowItemInterval.FloatValue, Timer_ThrowTimer, _, TIMER_REPEAT);
}
public void OnLibraryRemoved(const char[] name) {
  if (StrEqual(name, "adminmenu", false)) {
    hAdminMenu = null;
  }
}
public void OnAdminMenuReady(Handle aTopMenu) {
  TopMenu topmenu = TopMenu.FromHandle(aTopMenu);
 
  /* Try to add the category first, if we want to add one.
     Leave this out, if you don't add a new category. */
  if (obj_dmcommands == INVALID_TOPMENUOBJECT) {
    OnAdminMenuCreated(topmenu);
  }
  if (topmenu == hAdminMenu) {
    return;
  }
  hAdminMenu = topmenu;
}


//(dis)connection events
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
	CloseHandle(hThrowTimer);
	hThrowTimer = CreateTimer(convar.FloatValue, Timer_ThrowTimer, _, TIMER_REPEAT);
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
		}
		ReplyToCommand(client, "Cleared troll effects for %d players", target_count);
	}
	return Plugin_Handled;
}
public Action Command_ApplyUser(int client, int args) {
	if(args < 2) {
		ReplyToCommand(client, "Usage: sm_fta <user(s)> <mode>");
	}else{
		char arg1[32], arg2[32];
		GetCmdArg(1, arg1, sizeof(arg1));
		GetCmdArg(2, arg2, sizeof(arg2));

		int mode = StringToInt(arg2);
		if(mode == 0) {
			ReplyToCommand(client, "Not a valid mode. Must be greater than 0. Usage: sm_fta <user(s)> <mode>");
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
				ReplyToCommand(client, "Applied troll mode %d to %N", mode, target_list[i]);
				ApplyModeToClient(client, target_list[i], mode);
			}
		}
	}
	return Plugin_Handled;
}
public Action Command_ListTheTrolls(int client, int args) {
	int count = 0;
	for(int i = 1; i < MaxClients; i++) {
		if(IsClientConnected(i) && IsPlayerAlive(i) && iTrollUsers[i] > 0) {
			ReplyToCommand(client, "%N | Mode %d", i, iTrollUsers[i]);
			count++;
		}
	}
	if(count == 0) {
		ReplyToCommand(client, "No clients have a mode applied.");
	}
	return Plugin_Handled;
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
		if(iTrollUsers[client] == 4) {
			char currentWpn[16];
			//TODO: Fix new weapons being given when user has one??
			GetClientWeapon(client, currentWpn, sizeof(currentWpn));
			if(StrEqual(wpnName, "weapon_smg", true)) {
				return StrEqual(currentWpn, "weapon_smg", true) ? Plugin_Stop : Plugin_Continue;
			} else if(StrEqual(currentWpn, "weapon_smg", true)) {
				return Plugin_Stop;
			}else{
				int flags = GetCommandFlags("give");
				SetCommandFlags("give", flags & ~FCVAR_CHEAT);
				FakeClientCommand(client, "give smg");
				SetCommandFlags("give", flags|FCVAR_CHEAT);
				return Plugin_Stop;
			}
		}else{
			return Plugin_Stop;
		}
	}else{
		return Plugin_Continue;
	}
}
// #endregion
// #region timer
public Action Timer_MainProcess(Handle timer) {
	for(int i = 1; i < MaxClients; i++) {
		if(IsClientConnected(i) && iTrollUsers[i] > 0) {
			int mode = iTrollUsers[i];
			if(mode == 11) {
				ThrowAllItems(i);
			}
		}
	}
}
public Action Timer_ThrowTimer(Handle timer) {
	for(int i = 1; i < MaxClients; i++) {
		if(IsClientConnected(i) && iTrollUsers[i] == 11) {
			ThrowAllItems(i);
		}
	}
}

// #endregion
// #region methods
/*
TROLL MODES
1 -> Slow speed (0.8 < 1.0 base)
2 -> Higher gravity (1.3 > 1.0)
3 -> Set primary reserve ammo in half
4 -> UziRules (Pickup weapon defaults to uzi)
5 -> PrimaryDisable (Cannot pickup primary weapons at all)
6 -> Slow Drain
7 -> Clusmy
8 -> IcantSpellNoMore
9 -> CameTooEarly
10 -> KillMeSoftly
11 -> ThrowItAll
12 -> TakeMyPills
*/
void ApplyModeToClient(int client, int victim, int mode) {
	ResetClient(victim);
	switch(mode) {
		case 1: 
			SetEntPropFloat(victim, Prop_Send, "m_flLaggedMovementValue", 0.8);
		case 2:
			SetEntityGravity(victim, 1.3);
		case 3: {
			int current = GetPrimaryReserveAmmo(victim);
			SetPrimaryReserveAmmo(victim, current / 2);
		}
		case 4:
			SDKHook(victim, SDKHook_WeaponEquip, Event_ItemPickup);
		case 5: 
			SDKHook(victim, SDKHook_WeaponEquip, Event_ItemPickup);
		case 7: {
			int wpn = GetClientSecondaryWeapon(victim);
			bool hasMelee = DoesClientHaveMelee(victim);
			if(hasMelee) {
				float pos[3];
				int clients[4];
				GetClientAbsOrigin(victim, pos);
				int clientCount = GetClientsInRange(pos, RangeType_Visibility, clients, sizeof(clients));
				for(int i = 0; i < clientCount; i++) {
					if(clients[i] != victim) {
						PrintToChatAll("client %d throw to %d", victim, clients[i]);
						float targPos[3];
						GetClientAbsOrigin(clients[i], targPos);
						SDKHooks_DropWeapon(victim, wpn, targPos);
						iTrollUsers[victim] = mode;
						return;
					}
				}
				SDKHooks_DropWeapon(victim, wpn);
			}
			ReplyToCommand(client, "res = %d" , hasMelee ? 1 : 0);
		}
		case 8:
			ReplyToCommand(client, "This troll mode is not implemented.");
		case 11: {
			if(IsFakeClient(victim)) {
				ReplyToCommand(client, "This mode does not work for bots.");
				return;
			}
			ThrowAllItems(victim);
		}
		default: {
			ReplyToCommand(client, "Unknown troll mode: %d", mode);
			PrintToServer("Unknown troll mode to apply: %d", mode);
		}
	}
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
	iTrollUsers[victim] = 0;
	SetEntityGravity(victim, 1.0);
	SetEntPropFloat(victim, Prop_Send, "m_flLaggedMovementValue", 1.0);
	SDKUnhook(victim, SDKHook_WeaponEquip, Event_ItemPickup);
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
			if(!bTimerEnabled) {
				bTimerEnabled = true;
				
			}
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
