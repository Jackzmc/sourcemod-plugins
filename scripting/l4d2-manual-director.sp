#pragma semicolon 1
#pragma newdecls required

#define DEBUG

#define PLUGIN_NAME "L4D2 Manual Director"
#define PLUGIN_DESCRIPTION "Tell the director to spawn specials manually, even bypassing limits"
#define PLUGIN_AUTHOR "jackzmc"
#define PLUGIN_VERSION "1.2"

#include <sourcemod>
#include <sdktools>

ConVar g_cMdEnableTank, g_cMdEnableWitch, g_cMdEnableMob, g_cMdAnnounceLevel;
bool g_bMdIsL4D2 = false;
char g_cmd[16];

char SPECIAL_IDS[6][] = {
	"jockey",
	"smoker",
	"boomer",
	"hunter",
	"charger",
	"spitter"
};

public Plugin myinfo = 
{
	name = PLUGIN_NAME, 
	author = PLUGIN_AUTHOR, 
	description = PLUGIN_DESCRIPTION, 
	version = PLUGIN_VERSION, 
	url = "https://github.com/Jackzmc/sourcemod-plugins"
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
		g_cmd = "z_spawn_old";
	} else {
		g_cmd = "z_spawn";
	}
	return APLRes_Success;
}

public void OnPluginStart()
{
	CreateConVar("manual_director_version", PLUGIN_VERSION, "Manual Director Version", FCVAR_SPONLY | FCVAR_DONTRECORD);
	CreateConVar("mandirector_version", PLUGIN_VERSION, "Manual Director Version", FCVAR_SPONLY | FCVAR_DONTRECORD);
	
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

Action Command_SpawnSpecial(int client, int args) {
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
				SpawnX(executioner, arg1, amount, "auto");
				AnnounceSpawn(arg1);
				LogAction(client, -1, "\"%L\" spawned %dx \"%s\"", client, amount, arg1);
				ShowActivity(client, "spawned %dx \"%s\"", amount, arg1);
			}
		}
	}
	return Plugin_Handled;
}
Action Command_SpawnSpecialForceLocal(int client, int args) {
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
		SpawnX(client, arg1, amount);
		AnnounceSpawn(arg1);
		LogAction(client, -1, "\"%L\" spawned %dx \"%s\" at cursor", client, amount, arg1);
		ShowActivity(client, "spawned %dx \"%s\" at cursor", amount, arg1);
	}
	return Plugin_Continue;
}

Action Command_SpawnSpecialForce(int client, int args) {
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
		SpawnX(executioner, arg1, amount, "auto");
		AnnounceSpawn(arg1);
		LogAction(client, -1, "\"%L\" force spawned %dx \"%s\"", client, amount, arg1);
		ShowActivity(client, "force spawned %dx \"%s\"", amount, arg1);
	}
	return Plugin_Handled;
}
Action ShowSpecialMenu(int client, int args) {
	
	Menu menu = new Menu(Handle_SpawnMenu);
	menu.SetTitle("Manual Director - Auto");
	menu.AddItem("random", "Random Special");
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
	return Plugin_Handled;
}
Action ShowLocalSpecialMenu(int client, int args) {
	Menu menu = new Menu(Handle_LocalSpawnMenu);
	menu.SetTitle("Manual Director - Cursor");
	menu.AddItem("random", "Random Special");
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
	return Plugin_Handled;
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
	/* If the menu has ended, destroy it */
	else if (action == MenuAction_End)
	{
		delete menu;
	}
	return 0;
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
	else if (action == MenuAction_End)
	{
		delete menu;
	}
	return 0;
}

stock Action kickbot(Handle timer, int client) {
	if (IsClientInGame(client) && (!IsClientInKickQueue(client)))
	{
		if (IsFakeClient(client))KickClient(client);
	}
	return Plugin_Handled;
}

stock int GetAnyValidClient() {
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i) && !IsFakeClient(i)) {
			return i;
		}
	}
	return -1;
}

stock void CheatCommand(int client, const char[] command, const char[] argument1, const char[] argument2) {
	int userFlags = GetUserFlagBits(client);
	SetUserFlagBits(client, ADMFLAG_ROOT);
	int flags = GetCommandFlags(command);
	SetCommandFlags(command, flags & ~FCVAR_CHEAT);
	FakeClientCommand(client, "%s %s %s", command, argument1, argument2);
	SetCommandFlags(command, flags);
	SetUserFlagBits(client, userFlags);
} 

void SpawnX(int executioner, char[] spawn, int amount, char[] arg = "") {
	if(StrEqual(spawn, "panic")) { 
		CheatCommand(executioner, "director_force_panic_event", "", "");
		return;
	}
	bool isCommon = StrEqual(spawn, "common", false);
	bool isRandom = StrEqual(spawn, "random", false);

	int userFlags = GetUserFlagBits(executioner);
	SetUserFlagBits(executioner, ADMFLAG_ROOT);
	int flags = GetCommandFlags(g_cmd);
	SetCommandFlags(g_cmd, flags & ~FCVAR_CHEAT);
	for(int i = 0; i < amount; i++) {
		if(!isCommon && !isRandom) {
			int bot = CreateFakeClient("ManualDirectorBot");
			if (bot != 0) {
				ChangeClientTeam(bot, 3);
				CreateTimer(0.1, kickbot, bot);
			}
		} else if(isRandom) { 
			int index = GetRandomInt(0, g_bMdIsL4D2 ? 5 : 2);
			strcopy(spawn, 16, SPECIAL_IDS[index]);
		}
		FakeClientCommand(executioner, "%s %s %s", g_cmd, spawn, arg);
	}
	SetCommandFlags(g_cmd, flags);
	SetUserFlagBits(executioner, userFlags);
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