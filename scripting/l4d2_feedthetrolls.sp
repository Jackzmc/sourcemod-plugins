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
#include <ftt>
#include <multicolors>

#undef REQUIRE_PLUGIN
#include <adminmenu>

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

	LoadTrolls();

	LoadTranslations("common.phrases");
	g_iAmmoTable = FindSendPropInfo("CTerrorPlayer", "m_iAmmo");

	g_PlayerMarkedForward = new GlobalForward("FTT_OnClientMarked", ET_Ignore, Param_Cell, Param_Cell);

	hThrowItemInterval = CreateConVar("sm_ftt_throw_interval", "30", "The interval in seconds to throw items. 0 to disable", FCVAR_NONE, true, 0.0);
	hThrowItemInterval.AddChangeHook(Change_ThrowInterval);
	hAutoPunish 		= CreateConVar("sm_ftt_autopunish_action", "0", "Setup automatic punishment of players. Add bits together\n0=Disabled, 1=Tank magnet, 2=Special magnet, 4=Swarm, 8=InstantVomit", FCVAR_NONE, true, 0.0);
	hAutoPunishExpire 	= CreateConVar("sm_ftt_autopunish_expire", "0", "How many minutes of gametime until autopunish is turned off? 0 for never.", FCVAR_NONE, true, 0.0);
	hMagnetChance 	 	= CreateConVar("sm_ftt_magnet_chance", "1.0", "% of the time that the magnet will work on a player.", FCVAR_NONE, true, 0.0, true, 1.0);
	hShoveFailChance 	= CreateConVar("sm_ftt_shove_fail_chance", "0.5", "The % chance that a shove fails", FCVAR_NONE, true, 0.0, true, 1.0);

	RegAdminCmd("sm_ftl", Command_ListTheTrolls, ADMFLAG_KICK, "Lists all the trolls currently ingame.");
	RegAdminCmd("sm_ftm", Command_ListModes, ADMFLAG_KICK, "Lists all the troll modes and their description");
	RegAdminCmd("sm_ftr", Command_ResetUser, ADMFLAG_KICK, "Resets user of any troll effects.");
	RegAdminCmd("sm_fta", Command_ApplyUser, ADMFLAG_KICK, "Apply a troll mod to a player, or shows menu if no parameters.");
	RegAdminCmd("sm_fth", Command_HelpMenu, ADMFLAG_KICK, "Opens a list that shows all the commands");
	RegAdminCmd("sm_ftt", Command_ApplyTroll, ADMFLAG_KICK, "WIP replacement to sm_fta");
	RegAdminCmd("sm_mark", Command_MarkPendingTroll, ADMFLAG_KICK, "Marks a player as to be banned on disconnect");
	RegAdminCmd("sm_ftc", Command_FeedTheCrescendoTroll, ADMFLAG_KICK, "Applies a manual punish on the last crescendo activator");

	HookEvent("player_disconnect", Event_PlayerDisconnect);
	HookEvent("player_death", Event_PlayerDeath);
	HookEvent("triggered_car_alarm", Event_CarAlarm);
	AddNormalSoundHook(view_as<NormalSHook>(SoundHook));

	AutoExecConfig(true, "l4d2_feedthetrolls");

	if(lateLoaded) {
		CreateTimer(MAIN_TIMER_INTERVAL_S, Timer_Main, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
		HookEntityOutput("func_button", "OnPressed", Event_ButtonPress);
	}
}

///////////////////////////////////////////////////////////////////////////////
// EVENTS
///////////////////////////////////////////////////////////////////////////////

public void OnPluginEnd() {
	UnhookEntityOutput("func_button", "OnPressed", Event_ButtonPress);
}
public void OnMapEnd() {
	UnhookEntityOutput("func_button", "OnPressed", Event_ButtonPress);
}
public void OnMapStart() {
	lastButtonUser = -1;
	HookEntityOutput("func_button", "OnPressed", Event_ButtonPress);
	CreateTimer(MAIN_TIMER_INTERVAL_S, Timer_Main, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	PrecacheSound("player/footsteps/clown/concrete1.wav");
	//CreateTimer(30.0, Timer_AutoPunishCheck, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}
public void OnClientPutInServer(int client) {
	g_PendingBanTroll[client] = false;
	SDKHook(client, SDKHook_OnTakeDamage, Event_TakeDamage);
}
public void Event_PlayerDisconnect(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(g_PendingBanTroll[client]) {
		g_PendingBanTroll[client] = false;
		if(!IsFakeClient(client) && GetUserAdmin(client) == INVALID_ADMIN_ID)
			BanClient(client, 0, BANFLAG_AUTO, "TrollMarked", "Banned", "ftt", 0);
	}
	g_iTrollUsers[client] = 0;
	g_iAttackerTarget[client] = 0;
}
public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	g_iAttackerTarget[client] = 0;
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
public Action Event_ButtonPress(const char[] output, int entity, int client, float delay) {
	if(client > 0 && client <= MaxClients) {
		lastButtonUser = client;
	}
	return Plugin_Continue;
}
public void Event_PanicEventCreate(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(client) {
		lastButtonUser = client;
	}
}
public void Event_CarAlarm(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(client) {
		PrintToChatAll("%N has alerted the horde!", client);
		FakeClientCommandEx(client, "sm_swarm #%d", client);
	}
	//Ignore car alarms for autopunish
	lastButtonUser = -1;
}
//TODO: Add cvar to turn on/off targetting incapped
//TODO: Auto Special Maagnet on Anti-rush
public Action L4D2_OnChooseVictim(int attacker, int &curTarget) {
	// =========================
	// OVERRIDE VICTIM
	// =========================
	if(hMagnetChance.FloatValue < GetRandomFloat()) return Plugin_Continue;
	L4D2Infected class = view_as<L4D2Infected>(GetEntProp(attacker, Prop_Send, "m_zombieClass"));
	int existingTarget = GetClientOfUserId(g_iAttackerTarget[attacker]);
	if(existingTarget > 0 && IsPlayerAlive(existingTarget)) {
		curTarget = existingTarget;
		return Plugin_Changed;
	}

	float closestDistance, survPos[3], spPos[3];
	GetClientAbsOrigin(attacker, spPos); 
	int closestClient = -1;
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i)) {
			if(class == L4D2Infected_Tank && HasTrollMode(i, Troll_TankMagnet) || (class != L4D2Infected_Tank && HasTrollMode(i, Troll_SpecialMagnet))) {
				GetClientAbsOrigin(i, survPos);
				float dist = GetVectorDistance(survPos, spPos, true);
				if(closestClient == -1 || dist < closestDistance) {
					closestDistance = dist;
					closestClient = i;
				}
			}
		}
	}
	
	if(closestClient > 0) {
		g_iAttackerTarget[attacker] = GetClientUserId(closestClient);
		curTarget = closestClient;
		return Plugin_Changed;
	}
	return Plugin_Continue;
}
public Action L4D2_OnEntityShoved(int client, int entity, int weapon, float vecDir[3], bool bIsHighPounce) {
	if(client > 0 && client <= MaxClients && HasTrollMode(client, Troll_NoShove) && hShoveFailChance.FloatValue > GetRandomFloat()) {
		return Plugin_Handled;
	}
	return Plugin_Continue;
}
public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs) {
	if(HasTrollMode(client, Troll_Honk)) {
		char strings[32][7];
		int words = ExplodeString(sArgs, " ", strings, sizeof(strings), 5);
		for(int i = 0; i < words; i++) {
			if(GetRandomFloat() <= 0.8) strings[i] = "honk";
			else strings[i] = "squeak";
		}
		int length = 7 * words;
		char[] message = new char[length];
		ImplodeStrings(strings, 32, " ", message, length);
		CPrintToChatAll("{blue}%N {default}:  %s", client, message);
		PrintToServer("%N: %s", client, sArgs);
		return Plugin_Handled;
	}else if(HasTrollMode(client, Troll_iCantSpellNoMore)) {
		int type = GetRandomInt(1, TROLL_MODE_COUNT + 8);
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
			case 13: {
				letterSrc = 'e';
				replaceChar = 'r';
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
		PrintToServer("%N: %s", client, sArgs);
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

public Action Event_TakeDamage(int victim, int& attacker, int& inflictor, float& damage, int& damagetype) {
	//Stop FF from marked:
	if(attacker > 0 && attacker <= MaxClients && IsClientInGame(attacker) && IsPlayerAlive(attacker)) {
		if(g_PendingBanTroll[attacker] && GetClientTeam(attacker) == 2 && GetClientTeam(victim) == 2) {
			
			return Plugin_Stop;
		}
		if(HasTrollMode(attacker, Troll_DamageBoost)) {
			damage * 2;
			return Plugin_Changed;
		}
	}
	return Plugin_Continue;
}
public Action SoundHook(int[] clients, int& numClients, char sample[PLATFORM_MAX_PATH], int& entity, int& channel, float& volume, int& level, int& pitch, int& flags, char[] soundEntry, int& seed) {
	if(lastButtonUser > -1 && StrEqual(sample, "npc/mega_mob/mega_mob_incoming.wav")) {
		PrintToConsoleAll("CRESCENDO STARTED BY %N", lastButtonUser);
		#if defined DEBUG
		PrintToChatAll("CRESCENDO STARTED BY %N", lastButtonUser);
		#endif
		
		lastCrescendoUser = lastButtonUser;
		if(IsPlayerFarDistance(lastButtonUser, AUTOPUNISH_FLOW_MIN_DISTANCE)) {
			NotifyAllAdmins("Autopunishing player %N for activation of event far from team", lastButtonUser);
			ShowActivity(0, "activated autopunish for crescendo activator %N (auto)", lastButtonUser);
			ActivateAutoPunish(lastButtonUser);
		}
		lastButtonUser = -1;
	}else if(numClients > 0 && entity > 0 && entity <= MaxClients) {
		if(StrContains(sample, "survivor/voice") > -1) {
			if(HasTrollMode(entity, Troll_Honk)) {
				strcopy(sample, sizeof(sample), "player/footsteps/clown/concrete1.wav");
				return Plugin_Changed;
			} else if(HasTrollMode(entity, Troll_VocalizeGag)) {
				return Plugin_Stop;
			}
		}
		
	}
	return Plugin_Continue;
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
// COMMANDS
///////////////////////////////////////////////////////////////////////////////

public Action Command_FeedTheCrescendoTroll(int client, int args) {
	if(lastCrescendoUser > -1) {
		ActivateAutoPunish(lastCrescendoUser);
		ReplyToCommand(client, "Activated auto punish on %N", lastCrescendoUser);
		ShowActivity(client, "activated autopunish for crescendo activator %N",lastCrescendoUser);
	}else{
		ReplyToCommand(client, "No player could be found to autopunish.");
	}
	return Plugin_Handled;
}

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
			if(g_iTrollUsers[target_list[i]] > 0) {
				ResetClient(target_list[i], true);
				ShowActivity(client, "reset troll effects on \"%N\". ", target_list[i]);
			}
		}
	}
	return Plugin_Handled;
}
//TODO: Categorize trolls into menus (Constant, Repeat, On Demand?)
//TODO: Add a 'punish crescendo activator' to categoriey main menu (sm_ftt)
//TODO: Add SurvivorBot magnet
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
		char arg1[32], arg2[32], arg3[8];
		GetCmdArg(1, arg1, sizeof(arg1));
		GetCmdArg(2, arg2, sizeof(arg2));
		GetCmdArg(3, arg3, sizeof(arg3));

		bool silent = StrEqual(arg3, "silent") || StrEqual(arg3, "quiet") || StrEqual(arg3, "mute");

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
				if(IsClientConnected(target_list[i]) && IsClientInGame(target_list[i]) && GetClientTeam(target_list[i]) == 2)
					ApplyModeToClient(client, target_list[i], view_as<trollMode>(mode), TrollMod_None, silent);
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
		if(IsClientConnected(i) && IsClientInGame(i) && IsPlayerAlive(i) && g_iTrollUsers[i] > 0) {
			int modes = g_iTrollUsers[i], modeCount = 0;
			char modeListArr[TROLL_MODE_COUNT][32];
			for(int mode = 1; mode < TROLL_MODE_COUNT; mode++) {
				//If troll mode exists:
				if(HasTrollMode(i, view_as<trollMode>(mode))) {
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

public Action Command_MarkPendingTroll(int client, int args) {
	if(args == 0) {
		Menu menu = new Menu(ChooseMarkedTroll);
		menu.SetTitle("Choose a troll to mark");
		char userid[8], display[16];
		for(int i = 1; i < MaxClients; i++) {
			if(IsClientConnected(i) && IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == 2) {
				AdminId admin = GetUserAdmin(i);
				if(admin == INVALID_ADMIN_ID) {
					Format(userid, sizeof(userid), "%d", GetClientUserId(i));
					GetClientName(i, display, sizeof(display));
					menu.AddItem(userid, display);
				}else{
					ReplyToCommand(client, "%N is an admin cannot be marked.", i);
				}
			}
		}
		menu.ExitButton = true;
		menu.Display(client, 0);
	} else {
		char arg1[32];
		GetCmdArg(1, arg1, sizeof(arg1));
		char target_name[MAX_TARGET_LENGTH];
		int target_list[MAXPLAYERS], target_count;
		bool tn_is_ml;
		if ((target_count = ProcessTargetString(
			arg1,
			client,
			target_list,
			1,
			COMMAND_FILTER_ALIVE, /* Only allow alive players */
			target_name,
			sizeof(target_name),
			tn_is_ml)) <= 0
		) {
			/* This function replies to the admin with a failure message */
			ReplyToTargetError(client, target_count);
			return Plugin_Handled;
		}
		int target = target_list[0];
		if(IsClientConnected(target) && IsClientInGame(target) && GetClientTeam(target) == 2) {
			ToggleMarkPlayer(client, target);
		}else{
			ReplyToCommand(client, "Player does not exist or is not a survivor.");
		}
	}
	return Plugin_Handled;
}

public Action Command_HelpMenu(int client, int args) {
	ReplyToCommand(client, "sm_ftl - Lists all the active trolls on players");
	ReplyToCommand(client, "sm_ftm - Lists all available troll modes & descriptions");
	ReplyToCommand(client, "sm_ftr - Resets target users' of their trolls");
	ReplyToCommand(client, "sm_fta - Applies a troll mode on targets");
	ReplyToCommand(client, "sm_ftt - Opens this menu");
	ReplyToCommand(client, "sm_ftc - Will apply a punishment to last crescendo activator");
	ReplyToCommand(client, "sm_mark - Marks the user to be banned on disconnect, prevents their FF.");
	return Plugin_Handled;
}

public Action Command_ApplyTroll(int client, int args) {
	Menu menu = new Menu(Menu_ChoosePlayer);
	menu.SetTitle("Choose a player to punish");
	for(int i = 1; i < MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == 2) {
			char userid[8], display[16];
			Format(userid, sizeof(userid), "%d", GetClientUserId(i));
			GetClientName(i, display, sizeof(display));
			menu.AddItem(userid, display);
		}
	}
	menu.AddItem("s", "All Survivors");
	menu.ExitButton = true;
	menu.Display(client, 0);
	return Plugin_Handled;
}
///////////////////////////////////////////////////////////////////////////////
// MENU HANDLER
///////////////////////////////////////////////////////////////////////////////

public int ChooseMarkedTroll(Menu menu, MenuAction action, int activator, int param2) {
	if (action == MenuAction_Select) {
		char info[16];
		menu.GetItem(param2, info, sizeof(info));
		int target = GetClientOfUserId(StringToInt(info));
		ToggleMarkPlayer(activator, target);
	} else if (action == MenuAction_End)
		delete menu;
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
		int modifier = StringToInt(str[2]);
		if(modifier == 2 || modifier == 3)
			ApplyModeToClient(param1, client, mode, TrollMod_Repeat);
		else
			ApplyModeToClient(param1, client, mode, TrollMod_InstantFire);
	} else if (action == MenuAction_End)	
		delete menu;
}

///NEW FTT COMMAND MENU HANDLING:
public int Menu_ChoosePlayer(Menu menu, MenuAction action, int activator, int item) {
	if (action == MenuAction_Select) {
		char info[16];
		menu.GetItem(item, info, sizeof(info));
		if(StrEqual(info, "s", true)) {
			delete menu;
			ReplyToCommand(activator, "Sorry, not implemented yet.");
			return;
		}
		int targetUserid = StringToInt(info);
		// TopMenu categoryMenu = new TopMenu(Menu_CategorySelector);
		// categoryMenu.AddCategory("One Time Trolls", Menu_TrollSelector, "sm_fta", 0, info);
		// categoryMenu.AddCategory("Constant Trolls", Menu_TrollSelector, "sm_fta", 0, info);
		// categoryMenu.AddCategory("Repeat Trolls",   Menu_TrollSelector, "sm_fta", 0, info);

		// categoryMenu.Display(activator, TopMenuPosition_Start);
		
		Menu categoryMenu = new Menu(Menu_ChooseCategory);
		categoryMenu.SetTitle("Select a troll category");

		char itemId[8];
		Format(itemId, sizeof(itemId), "%d|s", targetUserid);
		categoryMenu.AddItem(itemId, "One Time Trolls");
		Format(itemId, sizeof(itemId), "%d|c", targetUserid);
		categoryMenu.AddItem(itemId, "Constant Trolls");
		Format(itemId, sizeof(itemId), "%d|r", targetUserid);
		categoryMenu.AddItem(itemId, "Repeat Trolls");
		categoryMenu.ExitButton = true;
		categoryMenu.Display(activator, 0);
	} else if (action == MenuAction_End)
		delete menu;
}

public void Menu_CategorySelector(TopMenu topmenu, TopMenuAction action, TopMenuObject topobj_id, int param, char[] buffer, int maxlength) {
	PrintToChatAll("param=%d", param);
}

public void Menu_TrollSelector(TopMenu topmenu, TopMenuAction action, TopMenuObject topobj_id, int param, char[] buffer, int maxlength) {
	PrintToChatAll("param=%d", param);
}

public int Menu_ChooseCategory(Menu menu, MenuAction action, int activator, int item) {
	if (action == MenuAction_Select) {
		//Parse the item id
		char info[16];
		menu.GetItem(item, info, sizeof(info));
		char str[3][8];
		ExplodeString(info, "|", str, 3, 8, false);

		int targetUserid = StringToInt(str[0]);
		
		//Check category type
		trollType selectedType;
		if(StrEqual(str[1], "s", true)) {
			selectedType = Type_Single;
		}else if(StrEqual(str[1], "r", true)) {
			selectedType = Type_Repeat;
		}else if(StrEqual(str[1], "c", true)) {
			selectedType = Type_Constant;
		}

		Menu trollsMenu = new Menu(Menu_ChooseTroll);
		trollsMenu.SetTitle("Select a troll");

		char itemId[16];
		for(int i = 0 ; i < trolls.Length; i++) {
			Troll troll;
			trolls.GetArray(i, troll, sizeof(troll));
			if(troll.modifiers & view_as<int>(selectedType) == view_as<int>(selectedType)) {
				Format(itemId, sizeof(itemId), "%d|%d|%d", targetUserid, i, selectedType);
				trollsMenu.AddItem(itemId, troll.name);
			}
		}
		trollsMenu.ExitButton = true;
		trollsMenu.Display(activator, 0);
	} else if (action == MenuAction_End)
		delete menu;
}

public int Menu_ChooseTroll(Menu menu, MenuAction action, int activator, int item) {
	if (action == MenuAction_Select) {
		//Parse the item id
		char info[16];
		menu.GetItem(item, info, sizeof(info));
		char str[3][8];
		ExplodeString(info, "|", str, 3, 8, false);

		int targetUserid = StringToInt(str[0]);
		int trollIndex = StringToInt(str[1]);
		int victim = GetClientOfUserId(targetUserid);
		trollType type = view_as<trollType>(StringToInt(str[2]));

		ApplyTroll(trollIndex, victim, activator, type);
	} else if (action == MenuAction_End)
		delete menu;
}



public void StopItemGive(int client) {
	g_bPendingItemGive[client] = false;
}
///////////////////////////////////////////////////////////////////////////////
// TIMERS
///////////////////////////////////////////////////////////////////////////////

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
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && IsPlayerAlive(i)) {
			if(HasTrollMode(i, Troll_SlowDrain)) {
				if(loop % 4 == 0) {
					int hp = GetClientHealth(i);
					if(hp > 50) {
						SetEntProp(i, Prop_Send, "m_iHealth", hp - 1); 
					}
				}
			}else if(HasTrollMode(i, Troll_TempHealthQuickDrain)) {
				if(loop % 2 == 0) {
					float bufferTime = GetEntPropFloat(i, Prop_Send, "m_healthBufferTime");
					float buffer = GetEntPropFloat(i, Prop_Send, "m_healthBuffer");
					float tempHealth = GetTempHealth(i);
					if(tempHealth > 0.0) {
						PrintToConsole(i, "%f | %f %f", tempHealth, buffer, bufferTime);
						//SetEntPropFloat(i, Prop_Send, "m_healthBuffer", buffer - 10.0); 
						SetEntPropFloat(i, Prop_Send, "m_healthBufferTime", bufferTime - 7.0); 
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

public Action Timer_ResetAutoPunish(Handle timer, int user) {
	int client = GetClientOfUserId(user);
	if(client) {
		if(hAutoPunish.IntValue & 2 == 2) 
			TurnOffTrollMode(client, Troll_SpecialMagnet);
		if(hAutoPunish.IntValue & 1 == 1) 
			TurnOffTrollMode(client, Troll_TankMagnet);
	}
}

// /////////////////////////////////////////////////////////////////////////////
// NATIVES & FORWARDS
// /////////////////////////////////////////////////////////////////////////////

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
    if(buffer > 0.0) {
        //This is the difference between the time we used the temporal item, and the current time
        float difference = GetGameTime() - GetEntPropFloat(client, Prop_Send, "m_healthBufferTime");
        
        //We get the decay rate from this convar (Note: Adrenaline uses this value)
        float decay = GetConVarFloat(FindConVar("pain_pills_decay_rate"));
        
        //This is a constant we create to determine the amount of health. This is the amount of time it has to pass
        //before 1 Temporal HP is consumed.
        float constant = 1.0 / decay;
        
        //Then we do the calcs
        return buffer - (difference / constant);
    }else{
		return 0.0;
	}
}