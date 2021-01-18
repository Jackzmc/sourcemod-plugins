#pragma semicolon 1
#pragma newdecls required

//#define DEBUG

#define MAIN_TIMER_INTERVAL_S 5.0
#define PLUGIN_VERSION "1.0"

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include "jutils.inc"
#include <multicolors>

#undef REQUIRE_PLUGIN
#include <adminmenu>
//TODO: Detect if player activates crescendo from far away
//Possibly cancel event, make poll for other users. if no one responds, activate troll mode/swarm or kick/ban depending on FF amount?


public Plugin myinfo = 
{
	name = "L4D2 Feed The Trolls", 
	author = "jackzmc", 
	description = "https://forums.alliedmods.net/showthread.php?t=325331", 
	version = PLUGIN_VERSION, 
	url = ""
};
//HANDLES
Handle hThrowTimer;
//CONVARS
ConVar hVictimsList, hThrowItemInterval, hAutoPunish;
//BOOLS
bool lateLoaded; //Is plugin late loaded
bool bChooseVictimAvailable = false; //For charge player feature, is it available?
//INTEGERS
int g_iAmmoTable; //Loads the ammo table to get ammo amounts
int gChargerVictim = -1; //For charge player feature


#include "feedthetrolls.inc"


//plugin start
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

	hVictimsList = CreateConVar("sm_ftt_victims", "", "Comma seperated list of steamid64 targets (ex: STEAM_0:0:75141700)", FCVAR_NONE);
	hVictimsList.AddChangeHook(Change_VictimList);
	hThrowItemInterval = CreateConVar("sm_ftt_throw_interval", "30", "The interval in seconds to throw items. 0 to disable", FCVAR_NONE, true, 0.0);
	hThrowItemInterval.AddChangeHook(Change_ThrowInterval);
	hAutoPunish = CreateConVar("sm_ftt_autopunish_mode", "0", "Setup automatic punishment of players. Add bits together. 0: Disabled, 1: Early Crescendos", FCVAR_NONE, true, 0.0);

	RegAdminCmd("sm_ftl", Command_ListTheTrolls, ADMFLAG_ROOT, "Lists all the trolls currently ingame.");
	RegAdminCmd("sm_ftm", Command_ListModes, ADMFLAG_ROOT, "Lists all the troll modes and their description");
	RegAdminCmd("sm_ftr", Command_ResetUser, ADMFLAG_ROOT, "Resets user of any troll effects.");
	RegAdminCmd("sm_fta", Command_ApplyUser, ADMFLAG_ROOT, "Apply a troll mod to a player, or shows menu if no parameters.");

	HookEvent("player_disconnect", Event_PlayerDisconnect);

	AutoExecConfig(true, "l4d2_feedthetrolls");

	if(lateLoaded) {
		CreateTimer(MAIN_TIMER_INTERVAL_S, Timer_Main, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
		HookEntityOutput("func_button", "OnPressed", Event_ButtonPress);
	}
}
public void OnPluginEnd() {
	UnhookEntityOutput("func_button", "OnPressed", Event_ButtonPress);
}
public void OnMapEnd() {
	UnhookEntityOutput("func_button", "OnPressed", Event_ButtonPress);
}
public void OnMapStart() {
	HookEntityOutput("func_button", "OnPressed", Event_ButtonPress);
	CreateTimer(MAIN_TIMER_INTERVAL_S, Timer_Main, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}
public void Event_PlayerDisconnect(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	g_iTrollUsers[client] = 0;
}
public void OnClientAuthorized(int client, const char[] auth) {
    if(StrContains(auth, "BOT", true) == -1) {
        TestForTarget(client, auth);
    }
}
// #region evrnts
public void Change_VictimList(ConVar convar, const char[] oldValue, const char[] newValue) {
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
			if(IsClientConnected(target_list[i]) && IsClientInGame(target_list[i]) && IsPlayerAlive(target_list[i]) && GetClientTeam(target_list[i]) == 2) {
				ResetClient(target_list[i], true);
				ShowActivity(client, "reset troll effects on \"%N\". ", target_list[i]);
			}
		}
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
					ApplyModeToClient(client, target_list[i], view_as<trollMode>(mode), TrollMod_None);
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
		if(IsClientConnected(i) && IsPlayerAlive(i) && g_iTrollUsers[i] > 0) {
			int modes = g_iTrollUsers[i], modeCount = 0;
			char modeListArr[TROLL_MODE_COUNT][32];
			for(int mode = 1; mode < TROLL_MODE_COUNT; mode++) {
				//If troll mode exists:
				bool hasTrollMode = HasTrollMode(i, view_as<trollMode>(mode));
				PrintToConsole(i, "[%d]: #%d %s value: %b", modes, mode, TROLL_MODES_NAMES[mode], hasTrollMode);
				if(hasTrollMode) {
					modeListArr[modeCount] = TROLL_MODES_NAMES[mode];
					modeCount++;
				}
			}
			char modeList[255];
			ImplodeStrings(modeListArr, modeCount, ", ", modeList, sizeof(modeList));
			ReplyToCommand(client, "%N | %d | %s", i, modes, modeList);
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
		int userid = StringToInt(str[0]);
		int client = GetClientOfUserId(userid);
		trollMode mode = view_as<trollMode>(StringToInt(str[1]));
		//If mode has an option to be single-time fired/continous/both, prompt:
		if(mode == Troll_Clumsy 
			|| mode ==Troll_ThrowItAll
			|| mode == Troll_PrimaryDisable
			|| mode == Troll_CameTooEarly
			|| mode == Troll_Swarm
		) {
			Menu modiferMenu = new Menu(ChooseTrollModiferHandler); 
			modiferMenu.SetTitle("Choose Troll Modifer Option");
			char singleUse[16], multiUse[16], bothUse[16];
			Format(singleUse, sizeof(singleUse), "%d|%d|1", userid, mode);
			Format(multiUse,   sizeof(multiUse), "%d|%d|2", userid, mode);
			Format(bothUse,     sizeof(bothUse), "%d|%d|3", userid, mode);
			modiferMenu.AddItem(singleUse, "Activate once");
			modiferMenu.AddItem(multiUse, "Activate Periodically");
			modiferMenu.AddItem(bothUse, "Activate Periodically & Instantly");
			modiferMenu.ExitButton = true;
			modiferMenu.Display(param1, 0);
		} else {
			ApplyModeToClient(param1, client, mode, TrollMod_None);
		}
    } else if (action == MenuAction_End)
        delete menu;
}
public int ChooseTrollModiferHandler(Menu menu, MenuAction action, int param1, int param2) {
	if (action == MenuAction_Select) {
		char info[16];
		menu.GetItem(param2, info, sizeof(info));
		char str[3][8];
		ExplodeString(info, "|", str, 3, 8, false);
		int client = GetClientOfUserId(StringToInt(str[0]));
		trollMode mode = view_as<trollMode>(StringToInt(str[1]));
		TrollModifer modifier = view_as<TrollModifer>(StringToInt(str[2]));
		ApplyModeToClient(param1, client, mode, modifier);
	} else if (action == MenuAction_End)	
		delete menu;
}
public Action Event_ButtonPress(const char[] output, int entity, int client, float delay) {
	PrintToServer("Client %N pressed a func_button", client);
	PrintToConsoleAll("Client %N pressed a func_button", client);
	if(hAutoPunish.IntValue & 1 > 0) {
		float closestDistance = -1.0, cPos[3], scanPos[3];
		GetClientAbsOrigin(client, cPos);

		for(int i = 1; i < MaxClients; i++) {
			if(IsClientConnected(i) && IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == 2 && i != client) {
				GetClientAbsOrigin(i, scanPos);
				float dist = GetVectorDistance(cPos, scanPos, false);
				if(closestDistance < dist) {
					closestDistance = dist;
				}
			}
		}
		if(FloatCompare(closestDistance, -1.0) == 1 && closestDistance >= 1200) {
			PrintToServer("Detected button_use firing when no nearby players. Closest Distance: %f.", closestDistance);
			trollMode mode = view_as<trollMode>(GetRandomInt(1, TROLL_MODE_COUNT));
			PrintToServer("Activating troll mode #%d: %s for player %N", mode, TROLL_MODES_NAMES[mode], client);
			ApplyModeToClient(0, client, mode, TrollMod_InstantFire);
			UnhookSingleEntityOutput(entity, "OnPressed", Event_ButtonPress);
		}
	}
	return Plugin_Continue;
}
public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs) {
	if(HasTrollMode(client, Troll_iCantSpellNoMore)) {
		int type = GetRandomInt(1, 24);
		char letterSrc, replaceChar;
		switch(type) {
			case 1: {
				letterSrc = 'e';
				replaceChar = 'b';
			}
			case 2: {
				letterSrc = 't';
				replaceChar = 'e';
			}
			case 3: {
				letterSrc = 'i';
				replaceChar = 'e';
			}
			case 4: {
				letterSrc = 'a';
				replaceChar = 's';
			}
			case 5: {
				letterSrc = 'u';
				replaceChar = 'i';
			}
			case 6: {
				letterSrc = '.';
				replaceChar = '/';
			}
			case 7: {
				letterSrc = 'm';
				replaceChar = 'n';
			}
			case 8: {
				letterSrc = 'n';
				replaceChar = 'm';
			}
			case 9: {
				letterSrc = 'l';
				replaceChar = 'b';
			}
			case 10: {
				letterSrc = 'l';
				replaceChar = 'b';
			}
			case 11: {
				letterSrc = 'h';
				replaceChar = 'j';
			}
			case 12: {
				letterSrc = 'o';
				replaceChar = 'i';
			}

			default:
				return Plugin_Continue;
		}
		
		int strLength = strlen(sArgs);
		char[] newMessage = new char[strLength + 20];
		int n = 0;
		while (sArgs[n] != '\0') {
			if(sArgs[n] == letterSrc) {
				newMessage[n] = replaceChar;
			}else{
				newMessage[n] = sArgs[n];
			}
			n++;
		}  
		CPrintToChatAll("{blue}%N {default}:  %s", client, newMessage);
		return Plugin_Handled;
	}
	return Plugin_Continue;
}
public Action Event_ItemPickup(int client, int weapon) {
	if(HasTrollMode(client,Troll_NoPickup)) {
		return Plugin_Stop;
	}else{
		char wpnName[64];
		GetEdictClassname(weapon, wpnName, sizeof(wpnName));
		if(StrContains(wpnName, "rifle") > -1 
			|| StrContains(wpnName, "smg") > -1 
			|| StrContains(wpnName, "weapon_grenade_launcher") > -1 
			|| StrContains(wpnName, "sniper") > -1
			|| StrContains(wpnName, "shotgun") > -1
		) {
			//If 4: Only UZI, if 5: Can't switch.
			if(HasTrollMode(client,Troll_UziRules)) {
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
			}else if(HasTrollMode(client,Troll_PrimaryDisable)) {
				return Plugin_Stop;
			}
			return Plugin_Continue;
		}else{
			return Plugin_Continue;
		}
	}
}
public Action OnPlayerRunCmd(int client, int& buttons, int& impulse, float vel[3], float angles[3], int& weapon, int& subtype, int& cmdnum, int& tickcount, int& seed, int mouse[2]) {
	if(g_bPendingItemGive[client] && !(buttons & IN_ATTACK2)) {
		int target = GetClientAimTarget(client, true);
		if(target > -1) {
			buttons |= IN_ATTACK2;
			RequestFrame(StopItemGive, client);
			return Plugin_Changed;
		}
		return Plugin_Continue;
	}
	return Plugin_Continue;
}
public void StopItemGive(int client) {
	g_bPendingItemGive[client] = false;
}
public Action Event_WeaponReload(int weapon) {
	int client = GetEntPropEnt(weapon, Prop_Send, "m_hOwner");
	if(HasTrollMode(client,Troll_GunJam)) {
		float dec = GetRandomFloat(0.0, 1.0);
		if(FloatCompare(dec, 0.50) == -1) { //10% chance gun jams
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
		if(IsClientConnected(i) && IsClientInGame(i) && IsPlayerAlive(i) &&HasTrollMode(i,Troll_ThrowItAll)) {
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
			switch(g_iTrollUsers[i]) {
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


stock void SendChatToAll(int client, const char[] message) {
	char nameBuf[MAX_NAME_LENGTH];
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
		{
			continue;
		}
		FormatActivitySource(client, i, nameBuf, sizeof(nameBuf));
		PrintToChat(i, "\x03 %s : \x01%s", nameBuf, message);
	}
}