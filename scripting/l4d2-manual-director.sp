#pragma semicolon 1
#pragma newdecls required

#define DEBUG

#define PLUGIN_NAME "L4D2 Manual Director"
#define PLUGIN_DESCRIPTION "Tell the director to spawn specials manually, even bypassing limits"
#define PLUGIN_AUTHOR "jackzmc"
#define PLUGIN_VERSION "1.2"

#include <sourcemod>
#include <sdktools>

ConVar g_cMdNotify, g_cMdEnableTank, g_cMdEnableWitch, g_cMdEnableMob, g_cMdAnnounceLevel;
bool g_bMdIsL4D2 = false;

int g_icSpawnStats[15];
/*
0 - Commons
1 - Mob
2 - Panics
3 - Jockey
4 - Hunter
5 - Charger
6 - Smoker
7 - Spitter
8 - Boomer
9 - Witch
10 - Tank
11 - Weapons
12 - Health
13 - Throwables
14 - Restarts (cvar?)
*/

public Plugin myinfo = 
{
	name = PLUGIN_NAME, 
	author = PLUGIN_AUTHOR, 
	description = PLUGIN_DESCRIPTION, 
	version = PLUGIN_VERSION, 
	url = ""
};
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	EngineVersion test = GetEngineVersion();
	if (test != Engine_Left4Dead2 && test != Engine_Left4Dead)
	{
		strcopy(error, err_max, "Plugin only supports Left 4 Dead [2].");
		return APLRes_SilentFailure;
	}
	if (test == Engine_Left4Dead2) {
		g_bMdIsL4D2 = true;
	}
	return APLRes_Success;
}

public void OnPluginStart()
{
	CreateConVar("manual_director_version", PLUGIN_VERSION, "Manual Director Version", FCVAR_SPONLY | FCVAR_DONTRECORD);
	CreateConVar("mandirector_version", PLUGIN_VERSION, "Manual Director Version", FCVAR_SPONLY | FCVAR_DONTRECORD);
	
	g_cMdNotify = CreateConVar("mandirector_notify_spawn", "0", "Should spawning specials notify on use?", FCVAR_NONE, true, 0.0, true, 1.0);
	g_cMdAnnounceLevel = CreateConVar("mandirector_announce_level", "0", "Announcement types. 0 - None, 1 - Only bosses, 2 - Only specials+, 3 - Everything", FCVAR_NONE, true, 0.0, true, 3.0);
	g_cMdEnableTank = CreateConVar("mandirector_enable_tank", "1", "Should tanks be allowed to be spawned?", FCVAR_NONE, true, 0.0, true, 1.0);
	g_cMdEnableWitch = CreateConVar("mandirector_enable_witch", "1", "Should witches be allowed to be spawned?", FCVAR_NONE, true, 0.0, true, 1.0);
	g_cMdEnableMob = CreateConVar("mandirector_enable_mob", "1", "Should mobs be allowed to be spawned?", FCVAR_NONE, true, 0.0, true, 1.0);
	
	
	RegAdminCmd("sm_spawnspecial", Command_SpawnSpecial, ADMFLAG_CHEATS, "Spawn a special via director");
	RegAdminCmd("sm_forcespecial", Command_SpawnSpecialForce, ADMFLAG_CHEATS, "Force spawn a special via director, bypassing spawn limits");
	RegAdminCmd("sm_forcecursor", Command_SpawnSpecialForceLocal, ADMFLAG_CHEATS, "Force spawn a special at cursor, bypassing spawn limits");
	RegAdminCmd("sm_cursormenu", ShowLocalSpecialMenu, ADMFLAG_CHEATS, "Show the spawn menu for cursor spawning");
	RegAdminCmd("sm_specialmenu", ShowSpecialMenu, ADMFLAG_CHEATS, "Show the spawn menu for director spawning");
	RegAdminCmd("sm_directormenu", ShowSpecialMenu, ADMFLAG_CHEATS, "Show the director main menu");
	PrintToServer("Manual Director V"...PLUGIN_VERSION..." is now loaded.");
	AutoExecConfig(true, "l4d2_manual_director");
}

public Action Command_SpawnSpecial(int client, int args) {
	char arg1[32], arg2[4];
	GetCmdArg(1, arg1, sizeof(arg1));
	GetCmdArg(2, arg2, sizeof(arg2));
	int amount = StringToInt(arg2);
	if(amount == 0) amount = 1;
	int executioner = GetAnyValidClient();
	if (args < 1) {
		ReplyToCommand(client, "[SM] Usage: sm_spawnspecial <hunter|smoker|boomer|spitter|charger|jockey|mob|tank|witch> [amount] - Requests a special to spawn via director", arg1);
	} else {
		if(amount <= 0 || amount > MaxClients && !StrEqual(arg1, "common")) {
			ReplyToCommand(client, "[SM] Amount specified is out of range of 1 to %d", MaxClients);
		}else if (executioner <= 0) {
			ReplyToCommand(client, "[SM] Cannot spawn a %s as there are no players online.", arg1);
		} else {
			if (StrEqual(arg1, "mob", false) && !g_cMdEnableMob.BoolValue) {
				ReplyToCommand(client, "[SM] Spawning mobs has been disabled.");
			} else if (StrEqual(arg1, "witch", false) && !g_cMdEnableWitch.BoolValue) {
				ReplyToCommand(client, "[SM] Spawning witches has been disabled.");
			} else if (StrEqual(arg1, "tank", false) && !g_cMdEnableTank.BoolValue) {
				ReplyToCommand(client, "[SM] Spawning tanks has been disabled.");
			} else {
				if(StrEqual(arg1,"panic",false)) {
					CheatCommand(executioner, "director_force_panic_event", "", "");
				}else{
					CheatCommandMultiple(executioner, amount, g_bMdIsL4D2 ? "z_spawn_old" : "z_spawn", arg1, "auto");
				}
				if (g_cMdNotify.BoolValue) {
					ReplyToCommand(client, "[SM] Director will now attempt to spawn %dx %s.", amount, arg1);
				}
				AnnounceSpawn(arg1);
				ShowActivity(client, "spawned %dx \"%s\"", amount, arg1);
			}
		}
	}
	return Plugin_Handled;
}
public Action Command_SpawnSpecialForceLocal(int client, int args) {
	if(client == 0) {
		ReplyToCommand(client, "[SM] This command can only be used as a player.");
		return Plugin_Handled;
	}
	char arg1[32], arg2[4];
	GetCmdArg(1, arg1, sizeof(arg1));
	GetCmdArg(2, arg2, sizeof(arg2));
	int amount = StringToInt(arg2);
	if(amount == 0) amount = 1;
	if (args < 1) {
		ReplyToCommand(client, "[SM] Usage: sm_forcecursor <hunter|smoker|boomer|spitter|charger|jockey|mob|tank|witch> [amount] - Requests a special to spawn at cursor", arg1);
	} else if(amount <= 0 || amount > MaxClients && !StrEqual(arg1, "common")) {
		ReplyToCommand(client, "[SM] Amount specified is out of range of 1 to %d", MaxClients);
	}else {
		if(StrEqual(arg1,"panic",false)) {
			CheatCommand(client, "director_force_panic_event", "", "");
		}else{
			for(int i = 0; i < amount; i++) {
				if(!StrEqual(arg1, "common")) {
					int bot = CreateFakeClient("ManualDirectorBot");
					if (bot != 0) {
						ChangeClientTeam(bot, 3);
						CreateTimer(0.1, kickbot, bot);
					}
				}
				CheatCommand(client, g_bMdIsL4D2 ? "z_spawn_old" : "z_spawn", arg1,"");
			}
		}
		if(g_cMdNotify.BoolValue) {
			ReplyToCommand(client, "[SM] Spawned %dx %s.", amount, arg1);
		}
		AnnounceSpawn(arg1);
		ShowActivity(client, "cursor spawned %dx \"%s\"", amount, arg1);
	}
	return Plugin_Continue;
}

public Action Command_SpawnSpecialForce(int client, int args) {
	char arg1[32], arg2[4];
	GetCmdArg(1, arg1, sizeof(arg1));
	GetCmdArg(2, arg2, sizeof(arg2));
	int amount = StringToInt(arg2);
	if(amount == 0) amount = 1;
	int executioner = GetAnyValidClient();
	if (args < 1) {
		ReplyToCommand(client, "[SM] Usage: sm_forcespecial <hunter|smoker|boomer|spitter|charger|jockey|mob|tank|witch> - Requests a special to spawn via director", arg1);
	} else if (executioner <= 0) {
		ReplyToCommand(client, "[SM] Cannot spawn a %s as there are no players online.", arg1);
	} else if(amount <= 0 || amount > MaxClients && !StrEqual(arg1, "common")) {
		ReplyToCommand(client, "[SM] Amount specified is out of range of 1 to %d", MaxClients);
	}else {
		if(StrEqual(arg1,"panic",false)) {
			CheatCommand(executioner, "director_force_panic_event", "", "");
		}else{
			for(int i = 0; i < amount; i++) {
				if(!StrEqual(arg1, "common")) {
					int bot = CreateFakeClient("ManualDirectorBot");
					if (bot != 0) {
						ChangeClientTeam(bot, 3);
						CreateTimer(0.1, kickbot, bot);
					}
				}
				CheatCommand(executioner, g_bMdIsL4D2 ? "z_spawn_old" : "z_spawn", arg1, "auto");
			}
		}
		if (g_cMdNotify.BoolValue) {
			ReplyToCommand(client, "[SM] Spawned a %dx %s.", amount, arg1);
		}
		AnnounceSpawn(arg1);
		ShowActivity(client, "forced spawned %dx \"%s\"", amount, arg1);
	}
	return Plugin_Handled;
}
public Action ShowSpecialMenu(int client, int args) {
	
	Menu menu = new Menu(Handle_SpawnMenu);
	menu.SetTitle("Manual Director - Auto");
	if (g_bMdIsL4D2) {
		menu.AddItem("jockey", "Jockey");
		menu.AddItem("charger", "Charger");
		menu.AddItem("spitter", "Spitter");
	}
	menu.AddItem("hunter", "Hunter");
	menu.AddItem("smoker", "Smoker");
	menu.AddItem("boomer", "Boomer");
	if (g_cMdEnableWitch.BoolValue)menu.AddItem("witch", "Witch");
	if (g_cMdEnableTank.BoolValue)menu.AddItem("tank", "Tank");
	if (g_cMdEnableMob.BoolValue)menu.AddItem("mob", "Mob");
	menu.ExitButton = true;
	menu.Display(client, 0);
}
public Action ShowLocalSpecialMenu(int client, int args) {
	Menu menu = new Menu(Handle_LocalSpawnMenu);
	menu.SetTitle("Manual Director - Cursor");
	menu.AddItem("common", "Single Common");
	
	if (g_bMdIsL4D2) {
		menu.AddItem("jockey", "Jockey");
		menu.AddItem("charger", "Charger");
		menu.AddItem("spitter", "Spitter");
	}
	
	menu.AddItem("hunter", "Hunter");
	menu.AddItem("smoker", "Smoker");
	menu.AddItem("boomer", "Boomer");
	if (g_cMdEnableWitch.BoolValue) menu.AddItem("witch", "Witch");
	if (g_cMdEnableTank.BoolValue) menu.AddItem("tank", "Tank");
	if (g_cMdEnableMob.BoolValue) menu.AddItem("mob", "Mob");
	menu.ExitButton = true;
	menu.Display(client, 0);
}

public int Handle_SpawnMenu(Menu menu, MenuAction action, int client, int index)
{
	/* If an option was selected, tell the client about the item. */
	if (action == MenuAction_Select)
	{
		char info[32];
		menu.GetItem(index, info, sizeof(info));
		FakeClientCommand(client, "sm_forcespecial %s", info);
		ShowSpecialMenu(client, 0);
		//PrintToConsole(param1, "You selected item: %d (found? %d info: %s)", index, found, info);
	}
	/* If the menu was cancelled, print a message to the server about it. */
	else if (action == MenuAction_Cancel)
	{
		PrintToServer("Client %d's menu was cancelled.  Reason: %d", client, index);
	}
	/* If the menu has ended, destroy it */
	else if (action == MenuAction_End)
	{
		delete menu;
	}
}
public int Handle_LocalSpawnMenu(Menu menu, MenuAction action, int client, int index)
{
	if (action == MenuAction_Select)
	{
		char info[32];
		menu.GetItem(index, info, sizeof(info));
		FakeClientCommand(client, "sm_forcecursor %s", info);
		ShowLocalSpecialMenu(client, 0);
	}
	else if (action == MenuAction_Cancel)
	{
		PrintToServer("Client %d's menu was cancelled.  Reason: %d", client, index);
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
}

stock Action kickbot(Handle timer, int client)
{
	if (IsClientInGame(client) && (!IsClientInKickQueue(client)))
	{
		if (IsFakeClient(client))KickClient(client);
	}
}
int FindStatIndex(const char[] type) {
	return SpawnStats
	if (StrEqual(type, "common") return 0;
	else if (StrEqual(type, "mob")) return 1;
	else if (StrEqual(type, "panic")) return 2;
	else if (StrEqual(type, "jockey")) return 3;
	else if (StrEqual(type, "hunter")) return 4;
	else if (StrEqual(type, "charger")) return 5;
	else if (StrEqual(type, "smoker")) return 6;
	else if (StrEqual(type, "spitter")) return 7;
	else if (StrEqual(type, "boomer")) return 8;
	else if (StrEqual(type, "witch")) return 9;
	else if (StrEqual(type, "tank")) return 10;
	else if (StrEqual(type, "weapon")) return 11;
	else if (StrEqual(type, "health")) return 12;
	else if (StrEqual(type, "throwable")) return 13;
	else if (StrEqual(type, "restart")) return 14;
	else return sizeof(g_icSpawnStats);
}
stock void UpdateIndex(char[] type) {
	int index = FindStatIndex(type);
	g_icSpawnStats[index]++;
}

stock int GetAnyValidClient() {
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i) && !IsFakeClient(i)) {
			return i;
		}
	}
	return -1;
}

stock void CheatCommand(int client, const char[] command, const char[] argument1, const char[] argument2)
{
	int userFlags = GetUserFlagBits(client);
	SetUserFlagBits(client, ADMFLAG_ROOT);
	int flags = GetCommandFlags(command);
	SetCommandFlags(command, flags & ~FCVAR_CHEAT);
	FakeClientCommand(client, "%s %s %s", command, argument1, argument2);
	SetCommandFlags(command, flags);
	SetUserFlagBits(client, userFlags);
} 
stock void CheatCommandMultiple(int client, int count, const char[] command, const char[] argument1, const char[] argument2)
{
	int userFlags = GetUserFlagBits(client);
	SetUserFlagBits(client, ADMFLAG_ROOT);
	int flags = GetCommandFlags(command);
	SetCommandFlags(command, flags & ~FCVAR_CHEAT);
	for(int i = 0; i < count; i++) {
		FakeClientCommand(client, "%s %s %s", command, argument1, argument2);
	}
	SetCommandFlags(command, flags);
	SetUserFlagBits(client, userFlags);
} 

void AnnounceSpawn(const char[] type) {
	switch(g_cMdAnnounceLevel.IntValue) {
		case 1:
			if(StrEqual(type,"tank") || StrEqual(type,"witch")) {
				PrintToChatAll("A %s has spawned!", type);
			}
		case 2:
			if(!StrEqual(type,"mob") && !StrEqual(type,"common") && !StrEqual(type,"panic")) {
				PrintToChatAll("A %s has spawned!", type);
			}
		case 3:
			PrintToChatAll("A %s has spawned!", type);
	}
}