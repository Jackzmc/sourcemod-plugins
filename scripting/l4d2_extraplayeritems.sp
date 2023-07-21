/* 
	Logic Flow:

	Once a player reaches the saferoom, it will give at a minimum a kit for each extra player over 4.
	There is a small chance of bonus kit, and will give bonus depending on average team health

	Kits are provided when a player attempts to pickup a new kit, 
	or when they load back in after map transition (and don't already have one)

	Once a new map starts, all item spawners are checked and randomly their spawn count will be increased by 1.
	Also on map start, cabinets will be populated with extra items dependent on player count
		extraitems = (playerCount) * (cabinetAmount/4) - cabinetAmount
*/

//TODO: On 3rd/4th kit pickup in area, add more
//TODO: Add extra pills too, on pickup

#pragma semicolon 1
#pragma newdecls required

#define DEBUG_INFO 0
#define DEBUG_GENERIC 1
#define DEBUG_SPAWNLOGIC 2
#define DEBUG_ANY 3

//Set the debug level
#define DEBUG_LEVEL DEBUG_ANY
#define EXTRA_PLAYER_HUD_UPDATE_INTERVAL 0.8
//Sets abmExtraCount to this value if set
// #define DEBUG_FORCE_PLAYERS 7


#define EXTRA_TANK_MIN_SEC 2.0
#define EXTRA_TANK_MAX_SEC 20.0
#define DATE_FORMAT "%F at %I:%M %p"



/// DONT CHANGE

#define PLUGIN_VERSION "1.0"

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <left4dhooks>
#include <l4d_info_editor>
#include <jutils>
#include <l4d2_weapon_stocks>

#define L4D2_WEPUPGFLAG_NONE            (0 << 0)
#define L4D2_WEPUPGFLAG_INCENDIARY      (1 << 0)
#define L4D2_WEPUPGFLAG_EXPLOSIVE       (1 << 1)
#define L4D2_WEPUPGFLAG_LASER 			(1 << 2)  

#define AMMOPACK_ENTID 0
#define AMMOPACK_USERS 1

#define TANK_CLASS_ID 8

// configurable:
#define PLAYER_DROP_TIMEOUT_SECONDS 120000.0


enum struct PlayerItems {
	char throwable[2];
	char usable[2];
	char consumable[2];
}
PlayerItems items[MAXPLAYERS+1];

public Plugin myinfo = 
{
	name =  "L4D2 Extra Player Tools", 
	author = "jackzmc", 
	description = "Automatic system for management of 5+ player games. Provides extra kits, items, and more", 
	version = PLUGIN_VERSION, 
	url = "https://github.com/Jackzmc/sourcemod-plugins"
};

static ConVar hExtraItemBasePercentage, hAddExtraKits, hMinPlayers, hUpdateMinPlayers, hMinPlayersSaferoomDoor, hSaferoomDoorWaitSeconds, hSaferoomDoorAutoOpen, hEPIHudState, hExtraFinaleTank, cvDropDisconnectTime, hSplitTankChance, cvFFDecreaseRate, cvZDifficulty, cvEPIHudFlags;
static int extraKitsAmount, extraKitsStarted, abmExtraCount, firstSaferoomDoorEntity, playersLoadedIn, playerstoWaitFor;
static int currentChapter;
static bool isCheckpointReached, isLateLoaded, firstGiven, isFailureRound, areItemsPopulated;
static ArrayList ammoPacks;
static Handle updateHudTimer;
static bool showHudPingMode;
static int hudModeTicks;
static char gamemode[32];


bool isCoop;

enum Difficulty {
	Difficulty_Easy,
	Difficulty_Normal,
	Difficulty_Advanced,
	Difficulty_Expert,
}

Difficulty zDifficulty;

static bool allowTankSplit = true;

enum State {
	State_Empty,
	State_PendingEmpty,
	State_Active
}
#if defined DEBUG_LEVEL
char StateNames[3][] = {
	"Empty",
	"PendingEmpty",
	"Active"
};
#endif

#define HUD_NAME_LENGTH 8

stock float SnapTo(const float value, const float degree) {
	return float(RoundFloat(value / degree)) * degree;
}
stock int StrLenMB(const char[] str){
    int len = strlen(str);
    int count;
    for(int i; i < len; i++) {
        count += ((str[i] & 0xc0) != 0x80) ? 1 : 0;
    }
    return count;
}  

enum struct PlayerData {
	bool itemGiven; //Is player being given an item (such that the next pickup event is ignored)
	bool isUnderAttack; //Is the player under attack (by any special)
	State state;
	bool hasJoined;
	
	char nameCache[64];
	int scrollIndex;
	int scrollMax;

	void Setup(int client) {
		char name[32];
		GetClientName(client, name, sizeof(name));
		this.scrollMax = strlen(name);
		for(int i = 0; i < this.scrollMax; i++) {
			// if(IsCharMB(name[i])) {
			// 	this.scrollMax--;
			// 	name[i] = '\0';
			// }
		}
		
		Format(this.nameCache, 64, "%s %s", name, name);
		this.ResetScroll();
	}

	void ResetScroll() {
		this.scrollIndex = 0;
		// TOOD: figure out keeping unicode symbols and not scrolling when 7 characters view
		// this.scrollMax = strlen(name);
		// this.scrollMax = RoundFloat(SnapTo(float(this.scrollMax), float(HUD_NAME_LENGTH)));
		if(this.scrollMax >= 32) {
			this.scrollMax = 31;
		}
	}

	void AdvanceScroll() {
		if(cvEPIHudFlags.IntValue & 1) {
			if(this.scrollMax > HUD_NAME_LENGTH) {
				this.scrollIndex += 1;
				// TODO: if name is < 8
				if(this.scrollIndex >= this.scrollMax) {
					this.scrollIndex = 0;
				}
			}
		}
	}
}

enum struct PlayerInventory {
	int timestamp;
	bool isAlive;

	WeaponId itemID[6]; //int -> char?
	bool lasers;
	char meleeID[32];

	int primaryHealth;
	int tempHealth;

	char model[64];
	int survivorType;

	float location[3];
}

PlayerData playerData[MAXPLAYERS+1];

/*
TODO:
1. Save player inventory on:
	a. Disconnect (saferoom disconnect too)
	b. Periodically?
2. On new map join (OnClientPutInServer¿) check following item matches:
	a. primary weapon
	b. secondary weapon (excl melee)
If a || b != saved items, then their character was dropped/swapped
Restore from saved inventory
*/

static StringMap weaponMaxClipSizes;
static StringMap pInv;


static char HUD_SCRIPT_DATA[] = "eph <- { Fields = { players = { slot = g_ModeScript.HUD_RIGHT_BOT, dataval = \"%s\", flags = g_ModeScript.HUD_FLAG_ALIGN_LEFT | g_ModeScript.HUD_FLAG_TEAM_SURVIVORS | g_ModeScript.HUD_FLAG_NOBG } } }\nHUDSetLayout(eph)\nHUDPlace(g_ModeScript.HUD_RIGHT_BOT,0.78,0.77,0.3,0.3)\ng_ModeScript;";
 
static char HUD_SCRIPT_CLEAR[] = "g_ModeScript._eph <- { Fields = { players = { slot = g_ModeScript.HUD_RIGHT_BOT, dataval = \"\", flags = g_ModeScript.HUD_FLAG_ALIGN_LEFT|g_ModeScript.HUD_FLAG_TEAM_SURVIVORS|g_ModeScript.HUD_FLAG_NOBG } } };HUDSetLayout( g_ModeScript._eph );g_ModeScript";

static char HUD_SCRIPT_DEBUG[] = "g_ModeScript._ephdebug <- {Fields = {players = {slot = g_ModeScript.HUD_RIGHT_BOT, dataval = \"DEBUG!!! %s\", flags = g_ModeScript.HUD_FLAG_ALIGN_LEFT|g_ModeScript.HUD_FLAG_TEAM_SURVIVORS|g_ModeScript.HUD_FLAG_NOBG}}};HUDSetLayout(g_ModeScript._ephdebug);HUDPlace(g_ModeScript.HUD_RIGHT_BOT, 0.72,0.78,0.3,0.3);g_ModeScript";


#define CABINET_ITEM_BLOCKS 4
enum struct Cabinet {
	int id;
	int items[CABINET_ITEM_BLOCKS];
}
static Cabinet cabinets[10]; //Store 10 cabinets

//// Definitions complete

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
	if(late) isLateLoaded = true;
	return APLRes_Success;
} 

public void OnPluginStart() {
	EngineVersion g_Game = GetEngineVersion();
	if(g_Game != Engine_Left4Dead2) {
		SetFailState("This plugin is for L4D2 only.");	
	}

	weaponMaxClipSizes = new StringMap();
	pInv = new StringMap();
	ammoPacks = new ArrayList(2); //<int entityID, ArrayList clients>
	
	HookEvent("player_spawn", 		Event_PlayerSpawn);
	HookEvent("player_first_spawn", Event_PlayerFirstSpawn);
	//Tracking player items:
	HookEvent("item_pickup",		Event_ItemPickup);
	HookEvent("weapon_drop",		Event_ItemPickup);

	HookEvent("round_end", 			Event_RoundEnd);
	HookEvent("map_transition", 	Event_MapTransition);
	HookEvent("game_start", 		Event_GameStart);
	HookEvent("game_end", 			Event_GameStart);
	HookEvent("round_freeze_end",   Event_RoundFreezeEnd);
	HookEvent("tank_spawn", 		Event_TankSpawn);

	//Special Event Tracking
	HookEvent("player_info", Event_PlayerInfo);
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


	hExtraItemBasePercentage = CreateConVar("l4d2_extraitems_chance", "0.056", "The base chance (multiplied by player count) of an extra item being spawned.", FCVAR_NONE, true, 0.0, true, 1.0);
	hAddExtraKits 			 = CreateConVar("l4d2_extraitems_kitmode", "0", "Decides how extra kits should be added.\n0 -> Overwrites previous extra kits, 1 -> Adds onto previous extra kits", FCVAR_NONE, true, 0.0, true, 1.0);
	hUpdateMinPlayers		 = CreateConVar("l4d2_extraitems_updateminplayers", "1", "Should the plugin update abm\'s cvar min_players convar to the player count?\n 0 -> NO, 1 -> YES", FCVAR_NONE, true, 0.0, true, 1.0);
	hMinPlayersSaferoomDoor  = CreateConVar("l4d2_extraitems_doorunlock_percent", "0.75", "The percent of players that need to be loaded in before saferoom door is opened.\n 0 to disable", FCVAR_NONE, true, 0.0, true, 1.0);
	hSaferoomDoorWaitSeconds = CreateConVar("l4d2_extraitems_doorunlock_wait", "25", "How many seconds after to unlock saferoom door. 0 to disable", FCVAR_NONE, true, 0.0);
	hSaferoomDoorAutoOpen 	 = CreateConVar("l4d2_extraitems_doorunlock_open", "0", "Controls when the door automatically opens after unlocked. Add bits together.\n0 = Never, 1 = When timer expires, 2 = When all players loaded in", FCVAR_NONE, true, 0.0);
	hEPIHudState 			 = CreateConVar("l4d2_extraitems_hudstate", "1", "Controls when the hud displays.\n0 -> OFF, 1 = When 5+ players, 2 = ALWAYS", FCVAR_NONE, true, 0.0, true, 3.0);
	hExtraFinaleTank 		 = CreateConVar("l4d2_extraitems_extra_tanks", "3", "Add bits together. 0 = Normal tank spawning, 1 = 50% tank split on non-finale (half health), 2 = Tank split (full health) on finale ", FCVAR_NONE, true, 0.0, true, 3.0);
	hSplitTankChance 		 = CreateConVar("l4d2_extraitems_splittank_chance", "0.75", "The % chance of a split tank occurring in non-finales", FCVAR_NONE, true, 0.0, true, 1.0);
	cvDropDisconnectTime     = CreateConVar("l4d2_extraitems_disconnect_time", "120.0", "The amount of seconds after a player has actually disconnected, where their character slot will be void. 0 to disable", FCVAR_NONE, true, 0.0);
	cvFFDecreaseRate         = CreateConVar("l4d2_extraitems_ff_decrease_rate", "0.3", "The friendly fire factor is subtracted from the formula (playerCount-4) * this rate. Effectively reduces ff penalty when more players. 0.0 to subtract none", FCVAR_NONE, true, 0.0);
	cvEPIHudFlags = CreateConVar("l4d2_extraitems_hud_flags", "3", "Add together.\n1 = Scrolling hud, 2 = Show ping", FCVAR_NONE, true, 0.0);
	// TODO: hook flags, reset name index / ping mode
	cvEPIHudFlags.AddChangeHook(Cvar_HudFlagChange);

	cvEPIHudFlags.AddChangeHook(Cvar_HudStateChange);
	
	if(hUpdateMinPlayers.BoolValue) {
		hMinPlayers = FindConVar("abm_minplayers");
		if(hMinPlayers != null) PrintDebug(DEBUG_INFO, "Found convar abm_minplayers");
	}

	if(isLateLoaded) {
		for(int i = 1; i <= MaxClients; i++) {
			if(IsClientConnected(i) && IsClientInGame(i)) {
				if(GetClientTeam(i) == 2) {
					SaveInventory(i);
					SDKHook(i, SDKHook_WeaponEquip, Event_Pickup);
				}
				playerData[i].Setup(i);
			}
		}
		
		int count = GetRealSurvivorsCount();
		abmExtraCount = count;
		int threshold = hEPIHudState.IntValue == 1 ? 5 : 0;
		if(hEPIHudState.IntValue > 0 && count > threshold && updateHudTimer == null) {
			PrintToServer("[EPI] Creating new hud timer");
			updateHudTimer = CreateTimer(EXTRA_PLAYER_HUD_UPDATE_INTERVAL, Timer_UpdateHud, _, TIMER_REPEAT);
		}
	}

	#if defined DEBUG_FORCE_PLAYERS 
	abmExtraCount = DEBUG_FORCE_PLAYERS;
	#endif

	char buffer[16];
	cvZDifficulty = FindConVar("z_difficulty");
	cvZDifficulty.GetString(buffer, sizeof(buffer));
	cvZDifficulty.AddChangeHook(Event_DifficultyChange);
	Event_DifficultyChange(cvZDifficulty, buffer, buffer);

	ConVar hGamemode = FindConVar("mp_gamemode"); 
	hGamemode.GetString(gamemode, sizeof(gamemode));
	hGamemode.AddChangeHook(Event_GamemodeChange);
	Event_GamemodeChange(hGamemode, gamemode, gamemode);


	AutoExecConfig(true, "l4d2_extraplayeritems");

	RegAdminCmd("sm_epi_sc", Command_SetSurvivorCount, ADMFLAG_KICK);
	#if defined DEBUG_LEVEL
		RegAdminCmd("sm_epi_setkits", Command_SetKitAmount, ADMFLAG_CHEATS, "Sets the amount of extra kits that will be provided");
		RegAdminCmd("sm_epi_lock", Command_ToggleDoorLocks, ADMFLAG_CHEATS, "Toggle all toggle\'s lock state");
		RegAdminCmd("sm_epi_kits", Command_GetKitAmount, ADMFLAG_CHEATS);
		RegAdminCmd("sm_epi_items", Command_RunExtraItems, ADMFLAG_CHEATS);
		RegConsoleCmd("sm_epi_stats", Command_DebugStats);
	#endif
	RegAdminCmd("sm_epi_restore", Command_RestoreInventory, ADMFLAG_KICK);
	RegAdminCmd("sm_epi_save", Command_SaveInventory, ADMFLAG_KICK);

	CreateTimer(30.0, Timer_ForceUpdateInventories, _, TIMER_REPEAT);
}

public Action Timer_ForceUpdateInventories(Handle h) {
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2) {
			// SaveInventory(i);
		}
	}
	return Plugin_Continue;
}

public void OnClientPutInServer(int client) {
	if(!IsFakeClient(client)) {
		playerData[client].Setup(client);

		if(GetClientTeam(client) == 2) {
			if(!StrEqual(gamemode, "hideandseek")) {
				// CreateTimer(0.2, Timer_CheckInventory, client);
			}
		}
	}
}

public void OnClientDisconnect(int client) {
	if(!IsFakeClient(client)) {
		SaveInventory(client);
	}
}

public void OnPluginEnd() {
	delete weaponMaxClipSizes;
	delete ammoPacks;
	L4D2_ExecVScriptCode(HUD_SCRIPT_CLEAR);
}

///////////////////////////////////////////////////////////////////////////////
// Special Infected Events 
///////////////////////////////////////////////////////////////////////////////
public Action Event_ChargerCarry(Event event, const char[] name, bool dontBroadcast) {
	int victim = GetClientOfUserId(event.GetInt("victim"));
	if(victim) {
		playerData[victim].isUnderAttack = StrEqual(name, "charger_carry_start");
	}
	return Plugin_Continue; 
}

public Action Event_HunterPounce(Event event, const char[] name, bool dontBroadcast) {
	int victim = GetClientOfUserId(event.GetInt("victim"));
	if(victim) {
		playerData[victim].isUnderAttack = StrEqual(name, "lunge_pounce");
	}
	return Plugin_Continue; 
}

public Action Event_SmokerChoke(Event event, const char[] name, bool dontBroadcast) {
	int victim = GetClientOfUserId(event.GetInt("victim"));
	if(victim) {
		playerData[victim].isUnderAttack = StrEqual(name, "choke_start");
	}
	return Plugin_Continue; 
}
public Action Event_JockeyRide(Event event, const char[] name, bool dontBroadcast) {
	int victim = GetClientOfUserId(event.GetInt("victim"));
	if(victim) {
		playerData[victim].isUnderAttack = StrEqual(name, "jockey_ride");
	}
	return Plugin_Continue; 
}

///////////////////////////////////////////////////////////////////////////////
// CVAR HOOKS 
///////////////////////////////////////////////////////////////////////////////
public void Cvar_HudStateChange(ConVar convar, const char[] oldValue, const char[] newValue) {
	if(convar.IntValue == 0) {
		if(updateHudTimer != null) {
		PrintToServer("[EPI] Stopping timer externally: Cvar changed to 0");
		delete updateHudTimer;
		}
	} else {
		int count = GetRealSurvivorsCount();
		int threshold = 0;
		// Default to 0 for state == 2 (force)
		if(hEPIHudState.IntValue == 1) {
			// On L4D1 map start if 5 players, on L4D2 start with 6
			// On L4D1 more chance of duplicate models, so can't see health
			threshold = L4D2_GetSurvivorSetMap() == 2 ? 4 : 5;
		}
		if(count > threshold && updateHudTimer == null) {
			PrintToServer("[EPI] Creating new hud timer");
			updateHudTimer = CreateTimer(EXTRA_PLAYER_HUD_UPDATE_INTERVAL, Timer_UpdateHud, _, TIMER_REPEAT);
		}
	}
}
void Cvar_HudFlagChange(ConVar convar, const char[] oldValue, const char[] newValue) {
	hudModeTicks = 0;
	showHudPingMode = false;
	for(int i = 0; i <= MaxClients; i++) {
		playerData[i].ResetScroll();
	}
}

public void Event_GamemodeChange(ConVar cvar, const char[] oldValue, const char[] newValue) {
	cvar.GetString(gamemode, sizeof(gamemode));
	isCoop = StrEqual(gamemode, "coop", false);
}

ConVar GetActiveFriendlyFireFactor() {
	if(zDifficulty == Difficulty_Easy) {
		// Typically is 0 but doesn't matter
		return FindConVar("survivor_friendly_fire_factor_easy");
	} else if(zDifficulty == Difficulty_Normal) {
		return FindConVar("survivor_friendly_fire_factor_normal");
	} else if(zDifficulty == Difficulty_Advanced) {
		return FindConVar("survivor_friendly_fire_factor_hard");
	} else if(zDifficulty == Difficulty_Expert) {
		return FindConVar("survivor_friendly_fire_factor_expert");
	} else {
		return null;
	}
}

public void Event_DifficultyChange(ConVar cvar, const char[] oldValue, const char[] newValue) {
	if(StrEqual(newValue, "easy", false)) {
		zDifficulty = Difficulty_Easy;
	} else if(StrEqual(newValue, "normal", false)) {
		zDifficulty = Difficulty_Normal;
	} else if(StrEqual(newValue, "hard", false)) {
		zDifficulty = Difficulty_Advanced;
	} else if(StrEqual(newValue, "impossible", false)) {
		zDifficulty = Difficulty_Expert;
	}
	// Unknown difficulty, silently ignore
}

/////////////////////////////////////
/// COMMANDS
////////////////////////////////////
Action Command_SaveInventory(int client, int args) {
	if(args == 0) {
		ReplyToCommand(client, "Syntax: /epi_save <player>");
		return Plugin_Handled;
	}
	char arg[32];
	GetCmdArg(1, arg, sizeof(arg));
	int player = GetSinglePlayer(client, arg, COMMAND_FILTER_NO_BOTS);
	if(player == -1) {
		ReplyToCommand(client, "No player found");
		return Plugin_Handled;
	}
	SaveInventory(player);
	ReplyToCommand(client, "Saved inventory for %N", player);
}
Action Command_RestoreInventory(int client, int args) {
	if(args == 0) {
		ReplyToCommand(client, "Syntax: /epi_restore <player> <full/pos/model/items>");
		return Plugin_Handled;
	}
	char arg[32];
	GetCmdArg(1, arg, sizeof(arg));
	int player = GetSinglePlayer(client, arg, COMMAND_FILTER_NO_BOTS);
	if(player == -1) {
		ReplyToCommand(client, "No player found");
		return Plugin_Handled;
	}
	GetCmdArg(2, arg, sizeof(arg));
	PlayerInventory inv;
	if(!GetLatestInventory(client, inv)) {
		ReplyToCommand(client, "No stored inventory for player");
		return Plugin_Handled;
	}

	if(StrEqual(arg, "full")) { 
		RestoreInventory(client, inv);
	} else if(StrEqual(arg, "pos")) {
		TeleportEntity(player, inv.location, NULL_VECTOR, NULL_VECTOR);
	} else {
		ReplyToCommand(client, "Syntax: /epi_restore <player> <full/pos/model/items>");
		return Plugin_Handled;
	}
	return Plugin_Handled;
}
public Action Command_SetSurvivorCount(int client, int args) {
	int oldCount = abmExtraCount;
	if(args > 0) {
		static char arg1[8];
		GetCmdArg(1, arg1, sizeof(arg1));
		int newCount;
		if(StringToIntEx(arg1, newCount) > 0) {
			if(newCount < 0 || newCount > MaxClients) {
				ReplyToCommand(client, "Invalid survivor count. Must be between 0 and %d", MaxClients);
				return Plugin_Handled;
			} else {
				abmExtraCount = newCount;
				hMinPlayers.IntValue = abmExtraCount;
				ReplyToCommand(client, "Changed extra survivor count to %d -> %d", oldCount, newCount);
				bool add = (newCount - oldCount) > 0;
				if(add)
					ServerCommand("abm-mk -%d 2", newCount);
				else
					ServerCommand("abm-rm -%d 2", newCount);
			}
		} else {
			ReplyToCommand(client, "Invalid number");
		}
	} else {
		ReplyToCommand(client, "Current extra count is %d.", oldCount);
	}
	return Plugin_Handled;
}
#if defined DEBUG_LEVEL
public Action Command_SetKitAmount(int client, int args) {
	char arg[32];
	GetCmdArg(1, arg, sizeof(arg));
	int number = StringToInt(arg);
	if(number > 0 || number == -1) {
		extraKitsAmount = number;
		extraKitsStarted = extraKitsAmount;
		ReplyToCommand(client, "Set extra kits amount to %d", number);
	} else {
		ReplyToCommand(client, "Must be a number greater than 0. -1 to disable");
	}
	return Plugin_Handled;
}

public Action Command_ToggleDoorLocks(int client, int args) {
	for(int i = MaxClients + 1; i < GetMaxEntities(); i++) {
		if(HasEntProp(i, Prop_Send, "m_bLocked")) {
			int state = GetEntProp(i, Prop_Send, "m_bLocked");
			SetEntProp(i, Prop_Send, "m_bLocked", state > 0 ? 0 : 1);
		}
	}
	return Plugin_Handled;
}

public Action Command_GetKitAmount(int client, int args) {
	ReplyToCommand(client, "Extra kits available: %d (%d) | Survivors: %d", extraKitsAmount, extraKitsStarted, GetSurvivorsCount());
	ReplyToCommand(client, "isCheckpointReached %b, isLateLoaded %b, firstGiven %b", isCheckpointReached, isLateLoaded, firstGiven);
	return Plugin_Handled;
}
public Action Command_RunExtraItems(int client, int args) {
	ReplyToCommand(client, "Running extra item count increaser...");
	PopulateItems();
	return Plugin_Handled;
}
public Action Command_DebugStats(int client, int args) {
	if(args == 0) {
		ReplyToCommand(client, "Player Statuses:");
		for(int i = 1; i <= MaxClients; i++) {
			if(IsClientConnected(i) && !IsFakeClient(i)) {
				ReplyToCommand(client, "\t\x04%d. %N:\x05 %s", i, i, StateNames[view_as<int>(playerData[i].state)]);
			}
		}
	} else {
		char arg[32];
		GetCmdArg(1, arg, sizeof(arg));
		PlayerInventory inv;
		int player = GetSinglePlayer(client, arg, COMMAND_FILTER_NO_BOTS);
		if(player == 0) {
			if(!GetInventory(arg, inv)) {
				ReplyToCommand(client, "No player found");
				return Plugin_Handled;
			}
		}

		if(!GetLatestInventory(player, inv)) {
			ReplyToCommand(client, "No saved inventory for %N", player);
			return Plugin_Handled;
		}
		if(inv.isAlive)
			ReplyToCommand(client, "\x04State: \x05%s (Alive)", StateNames[view_as<int>(playerData[player].state)]);
		else
			ReplyToCommand(client, "\x04State: \x05%s (Dead)", StateNames[view_as<int>(playerData[player].state)]);
		FormatTime(arg, sizeof(arg), DATE_FORMAT, inv.timestamp);
		ReplyToCommand(client, "\x04Timestamp: \x05%s (%d seconds)", arg, GetTime() - inv.timestamp);
		ReplyToCommand(client, "\x04Location: \x05%.1f %.1f %.1f", inv.location[0], inv.location[1], inv.location[2]);
		ReplyToCommand(client, "\x04Model: \x05%s (%d)", inv.model, inv.survivorType);
		ReplyToCommand(client, "\x04Health: \x05%d perm. / %d temp.", inv.primaryHealth, inv.tempHealth);
		ReplyToCommand(client, "\x04Items: \x05(Lasers:%b)", inv.lasers);
		for(int i = 0; i < 6; i++) {
			if(inv.itemID[i] != WEPID_NONE) {
				GetLongWeaponName(inv.itemID[i], arg, sizeof(arg));
				ReplyToCommand(client, "\x04%d. \x05%s", i, arg);
			}
		}
		ReplyToCommand(client, "%s", inv.meleeID);
	}
	return Plugin_Handled;
}
#endif
/////////////////////////////////////
/// EVENTS
////////////////////////////////////

#define FINALE_TANK 8
#define FINALE_STARTED 1
#define FINALE_RESCUE_READY 6
#define FINALE_HORDE 7
#define FINALE_WAIT 10

enum FinaleStage {
	Stage_Inactive = 0,
	Stage_FinaleActive = 1,
	Stage_FinaleTank1 = 2,
	Stage_FinaleTank2 = 3,
	Stage_FinaleDuplicatePending = 4,
	Stage_TankSplit = 5,
	Stage_InactiveFinale = -1
}
int extraTankHP;
FinaleStage finaleStage;

public Action L4D2_OnChangeFinaleStage(int &finaleType, const char[] arg) {
	if(finaleType == FINALE_STARTED && abmExtraCount > 4) {
		finaleStage = Stage_FinaleActive;
		PrintToConsoleAll("[EPI] Finale started and over threshold");
	} else if(finaleType == FINALE_TANK) {
		if(finaleStage == Stage_FinaleActive) {
			finaleStage = Stage_FinaleTank1;
			PrintToConsoleAll("[EPI] First tank stage has started");
		} else if(finaleStage == Stage_FinaleTank1) {
			finaleStage = Stage_FinaleTank2;
			PrintToConsoleAll("[EPI] Second stage started, waiting for tank");
		}
	}
	return Plugin_Continue;
}

public void Event_TankSpawn(Event event, const char[] name, bool dontBroadcast) {
	int user = event.GetInt("userid");
	int tank = GetClientOfUserId(user);
	if(tank > 0 && IsFakeClient(tank) && abmExtraCount > 4 && hExtraFinaleTank.IntValue > 0) {
		PrintToConsoleAll("[EPI] Split tank is enabled, checking new spawned tank");
		if(finaleStage == Stage_FinaleTank2 && allowTankSplit && hExtraFinaleTank.IntValue & 2) {
			PrintToConsoleAll("[EPI] Second tank spawned, setting health.");
			// Sets health in half, sets finaleStage to health
			float duration = GetRandomFloat(EXTRA_TANK_MIN_SEC, EXTRA_TANK_MAX_SEC);
			CreateTimer(duration, Timer_SpawnFinaleTank, user);
		} else if(finaleStage == Stage_FinaleDuplicatePending) {
			PrintToConsoleAll("[EPI] Third & final tank spawned");
			RequestFrame(Frame_SetExtraTankHealth, user);
		} else if(finaleStage == Stage_Inactive && allowTankSplit && hExtraFinaleTank.IntValue & 1 && GetSurvivorsCount() > 6) {
			finaleStage = Stage_TankSplit;
			if(GetRandomFloat() <= hSplitTankChance.FloatValue) {
				// Half their HP, assign half to self and for next tank
				int hp = GetEntProp(tank, Prop_Send, "m_iHealth") / 2;
				PrintToConsoleAll("[EPI] Creating a split tank (hp=%d)", hp);
				extraTankHP = hp;
				CreateTimer(0.2, Timer_SetHealth, user);
				CreateTimer(GetRandomFloat(10.0, 18.0), Timer_SpawnSplitTank, user);
			} else {
				PrintToConsoleAll("[EPI] Random chance for split tank failed");
			}
			// Then, summon the next tank
		} else if(finaleStage == Stage_TankSplit) {
			CreateTimer(0.2, Timer_SetHealth, user);
		}
	}
}
public Action Timer_SpawnFinaleTank(Handle t, int user) {
	if(finaleStage == Stage_FinaleTank2) {
		ServerCommand("sm_forcespecial tank");
		finaleStage = Stage_Inactive;
	}
	return Plugin_Handled;
}
public Action Timer_SpawnSplitTank(Handle t, int user) {
	ServerCommand("sm_forcespecial tank");
	return Plugin_Handled;
}
public Action Timer_SetHealth(Handle h, int user) {
	int client = GetClientOfUserId(user);
	if(client > 0 ) {
		SetEntProp(client, Prop_Send, "m_iHealth", extraTankHP);
	}
	return Plugin_Handled;
}

public void Frame_SetExtraTankHealth(int user) {
	int tank = GetClientOfUserId(user);
	if(tank > 0 && finaleStage == Stage_FinaleDuplicatePending) {
		SetEntProp(tank, Prop_Send, "m_iHealth", extraTankHP);
		finaleStage = Stage_InactiveFinale;
	}
}

public void OnGetWeaponsInfo(int pThis, const char[] classname) {
	char clipsize[8];
	InfoEditor_GetString(pThis, "clip_size", clipsize, sizeof(clipsize));

	int maxClipSize = StringToInt(clipsize);
	if(maxClipSize > 0) 
		weaponMaxClipSizes.SetValue(classname, maxClipSize);
}

///////////////////////////////////////////////////////
//// PLAYER STATE MANAGEMENT
///////////////////////////////////////////////////////

//Called on the first spawn in a mission. 
public void Event_GameStart(Event event, const char[] name, bool dontBroadcast) {
	firstGiven = false;
	extraKitsAmount = 0;
	extraKitsStarted = 0;
	abmExtraCount = 4;
	hMinPlayers.IntValue = 4;
	currentChapter = 0;
	pInv.Clear();
	for(int i = 1; i <= MaxClients; i++) {
		playerData[i].state = State_Empty;
	}
}

public void Event_PlayerFirstSpawn(Event event, const char[] name, bool dontBroadcast) { 
	int userid = event.GetInt("userid");
	int client = GetClientOfUserId(userid);
	if(GetClientTeam(client) != 2) return;
	if(IsFakeClient(client)) {
		// Make the real player's bot invincible, ONLY for the first time it appears
		int player = L4D_GetIdlePlayerOfBot(client);
		if(player > 0 && !playerData[client].hasJoined) {
			playerData[client].hasJoined = true;
			// TODO: Confirm this fix works
			CreateTimer(1.5, Timer_RemoveInvincibility, userid);
			SDKHook(client, SDKHook_OnTakeDamage, OnInvincibleDamageTaken);
		}
	} else {
		// Make the (real) player invincible:
		CreateTimer(1.5, Timer_RemoveInvincibility, userid);
		SDKHook(client, SDKHook_OnTakeDamage, OnInvincibleDamageTaken);

		playerData[client].state = State_Active;
		if(L4D_IsFirstMapInScenario() && !firstGiven) {
			//Check if all clients are ready, and survivor count is > 4. 
			if(AreAllClientsReady()) {
				abmExtraCount = GetRealSurvivorsCount();
				if(abmExtraCount > 4) {
					PrintToServer("[EPI] First chapter kits given");
					firstGiven = true;
					//Set the initial value ofhMinPlayers
					if(hUpdateMinPlayers.BoolValue && hMinPlayers != null) {
						hMinPlayers.IntValue = abmExtraCount;
					}
					PopulateItems();	
					CreateTimer(1.0, Timer_GiveKits);
				}
				UnlockDoor(2);
			}
		} else {
			// New client has connected, not on first map.
			// TODO: Check if Timer_UpdateMinPlayers is needed, or if this works:
			// Never decrease abmExtraCount
			int newCount = GetRealSurvivorsCount();
			if(newCount > abmExtraCount && abmExtraCount > 4) {
				abmExtraCount = newCount;
				hMinPlayers.IntValue = abmExtraCount;
				
				ConVar friendlyFireFactor = GetActiveFriendlyFireFactor();
				// TODO: Get previous default
				friendlyFireFactor.FloatValue = friendlyFireFactor.FloatValue - ((newCount - 4) * cvFFDecreaseRate.FloatValue);
				if(friendlyFireFactor.FloatValue < 0.0) {
					friendlyFireFactor.FloatValue = 0.01;
				}
			}
			// If 5 survivors, then set them up, TP them.
			if(newCount > 4) {
				CreateTimer(0.1, Timer_SetupNewClient, userid);
			}
		}
	}
}
public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast) {
	if(!StrEqual(gamemode, "coop") && !StrEqual(gamemode, "realism")) return;

	int user = event.GetInt("userid");
	int client = GetClientOfUserId(user);
	if(GetClientTeam(client) == 2) {
		if(!IsFakeClient(client)) {
			if(!L4D_IsFirstMapInScenario()) {
				playersLoadedIn++;
				if(playersLoadedIn == 1) {
					CreateTimer(hSaferoomDoorWaitSeconds.FloatValue, Timer_OpenSaferoomDoor, _, TIMER_FLAG_NO_MAPCHANGE);
				}
				if(playerstoWaitFor > 0) {
					float percentIn = float(playersLoadedIn) / float(playerstoWaitFor);
					if(percentIn > hMinPlayersSaferoomDoor.FloatValue)
						UnlockDoor(2);
				}else{
					UnlockDoor(2);
				}
			}
		}
		CreateTimer(0.5, Timer_GiveClientKit, user);
		SDKHook(client, SDKHook_WeaponEquip, Event_Pickup);
	}
	int count = GetRealSurvivorsCount();
	int threshold = 0;
	if(hEPIHudState.IntValue == 1) {
		threshold = L4D2_GetSurvivorSetMap() == 2 ? 4 : 5;
	}
	if(hEPIHudState.IntValue > 0 && count > threshold && updateHudTimer == null) {
		PrintToServer("[EPI] Creating new hud timer (player spawn)");
		updateHudTimer = CreateTimer(EXTRA_PLAYER_HUD_UPDATE_INTERVAL, Timer_UpdateHud, _, TIMER_REPEAT);
	}
	UpdatePlayerInventory(client);

}

// public Action Timer_CheckInventory(Handle h, int client) {
// 	if(IsClientConnected(client) && IsClientInGame(client) && GetClientTeam(client) == 2 && DoesInventoryDiffer(client)) {
// 		PrintToConsoleAll("[EPI] Detected mismatch inventory for %N, restoring", client);
// 		RestoreInventory(client);
// 	}
// 	return Plugin_Handled;
// }

public void Event_PlayerDisconnect(Event event, const char[] name, bool dontBroadcast) {
	int userid = event.GetInt("userid");
	int client = GetClientOfUserId(userid);
	if(client > 0 && IsClientConnected(client) && IsClientInGame(client) && !IsFakeClient(client) && GetClientTeam(client) == 2) { //TODO: re-add && !event.GetBool("isbot") 
		playerData[client].hasJoined = false;
		PrintToServer("debug: Player %N (index %d, uid %d) now pending empty", client, client, userid);
		playerData[client].state = State_PendingEmpty;
		playerData[client].nameCache[0] = '\0';
		/*DataPack pack;
		CreateDataTimer(cvDropDisconnectTime.FloatValue, Timer_DropSurvivor, pack);
		pack.WriteCell(userid);
		pack.WriteCell(client);*/
		CreateTimer(cvDropDisconnectTime.FloatValue, Timer_DropSurvivor, client);
	}
}

public void Event_PlayerInfo(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(client && !IsFakeClient(client)) {
		playerData[client].Setup(client);
	}
}

public Action Timer_DropSurvivor(Handle h, int client) {
	if(playerData[client].state == State_PendingEmpty) {
		playerData[client].state = State_Empty;
		if(hMinPlayers != null) {
			PrintToServer("[EPI] Dropping survivor %d. hMinPlayers-pre:%d abmCount=%d", client, hMinPlayers.IntValue, abmExtraCount);
			PrintToConsoleAll("[EPI] Dropping survivor %d. hMinPlayers-pre:%d abmCount=%d", client, hMinPlayers.IntValue, abmExtraCount);
			hMinPlayers.IntValue = --abmExtraCount;
			if(hMinPlayers.IntValue < 4) {
				hMinPlayers.IntValue = 4;
			}
		}
		DropDroppedInventories();
	}
	return Plugin_Handled;
}

/*public Action Timer_DropSurvivor(Handle h, DataPack pack) {
	pack.Reset();
	int userid = pack.ReadCell();
	int client = pack.ReadCell();
	// If the userid occupying client index is diff (or 0)
	if(GetClientOfUserId(userid) != client) {
		// If player was not replaced
		if(!IsClientConnected(client)) {
			PrintToConsoleAll("Dropping disconnected player after inactivity. UID:%d, index:%d, new MinPlayers: %d", userid, client, hMinPlayers.IntValue-1);
			//playerData[client].active = false;
			abmExtraCount--;
			hMinPlayers.IntValue--;
		}
	}
	DropDroppedInventories();
}*/

/////////////////////////////////////////
/////// Events
/////////////////////////////////////////

public void Event_ItemPickup(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(client > 0) {
		UpdatePlayerInventory(client);
	}

}


public Action L4D_OnIsTeamFull(int team, bool &full) {
	if(team == 2 && full) {
		full = false;
		return Plugin_Continue;
	} 
	return Plugin_Continue;
}

#define TIER1_WEAPON_COUNT 5
char TIER1_WEAPONS[TIER1_WEAPON_COUNT][] = {
	"shotgun_chrome",
	"pumpshotgun",
	"smg",
	"smg_silenced",
	"smg_mp5"
};

#define TIER2_WEAPON_COUNT 9
char TIER2_WEAPONS[9][] = {
	"weapon_autoshotgun",
	"weapon_rifle_ak47",
	"weapon_sniper_military",
	"weapon_rifle_sg552",
	"weapon_rifle_desert",
	"weapon_sniper_scout",
	"weapon_rifle",
	"weapon_hunting_rifle",
	"weapon_shotgun_spas"
};

public Action Timer_SetupNewClient(Handle h, int userid) {
	int client = GetClientOfUserId(userid);
	if(client == 0) return Plugin_Handled;
	if(!DoesClientHaveKit(client)) {
		int item = GivePlayerItem(client, "weapon_first_aid_kit");
		EquipPlayerWeapon(client, item);
	}

	int lowestClient = -1;
	float lowestIntensity;
	char weaponName[64];

	ArrayList tier2Weapons = new ArrayList(ByteCountToCells(32));
	ArrayList tier1Weapons = new ArrayList(ByteCountToCells(32));
	ArrayList secondaryWeapons = new ArrayList(ByteCountToCells(32));

	for(int i = 1; i <= MaxClients; i++) {
		if(i != client && IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i)) {
			int wpn = GetPlayerWeaponSlot(i, 0);
			if(wpn > 0) {
				GetEdictClassname(wpn, weaponName, sizeof(weaponName));
				if(!StrEqual(weaponName, "weapon_grenade_launcher") && !StrEqual(weaponName, "weapon_rifle_m60")) {
					for(int j = 0; j < TIER2_WEAPON_COUNT; j++) {
						if(StrEqual(TIER2_WEAPONS[j], weaponName)) {
							tier2Weapons.PushString(weaponName);
							break;
						}
					}
					tier1Weapons.PushString(weaponName);
					// playerWeapons.PushString(weaponName);
				}
			}
			wpn = GetPlayerWeaponSlot(i, 1);
			if(wpn > 0) {
				GetEdictClassname(wpn, weaponName, sizeof(weaponName));
				if(StrEqual(weaponName, "weapon_melee")) {
					// Get melee name, won't have weapon_ prefix
					GetEntPropString(wpn, Prop_Data, "m_strMapSetScriptName", weaponName, sizeof(weaponName));
				}
				secondaryWeapons.PushString(weaponName);
			}

			float intensity = L4D_GetPlayerIntensity(i);
			if(intensity < lowestIntensity || lowestClient == -1) {
				lowestIntensity = intensity;
				lowestClient = i;
			}
		}
	}

	// Give player any random t2 weapon, if no one has one, fallback to t1, if no one has one, give them a magnum
	if(tier2Weapons.Length > 0) {
		tier2Weapons.GetString(GetRandomInt(0, tier2Weapons.Length - 1), weaponName, sizeof(weaponName));
		// Format(weaponName, sizeof(weaponName), "weapon_%s", weaponName);
		PrintToServer("[EPI/debug] Giving new client (%N) tier 2: %s", client, weaponName);
		GiveWeapon(client, weaponName, 0.3, 0);
	} else if(tier1Weapons.Length > 0) {
		// Format(weaponName, sizeof(weaponName), "weapon_%s", TIER1_WEAPONS[GetRandomInt(0, TIER1_WEAPON_COUNT - 1)]);
		tier1Weapons.GetString(GetRandomInt(0, tier1Weapons.Length - 1), weaponName, sizeof(weaponName));
		PrintToServer("[EPI/debug] Giving new client (%N) tier 1: %s", client, weaponName);
		GiveWeapon(client, weaponName, 0.6, 0);
	}
	PrintToServer("%N: Giving random secondary / %d", secondaryWeapons.Length, client);
	PrintToConsoleAll("%N: Giving random secondary / %d", secondaryWeapons.Length, client);
	if(secondaryWeapons.Length > 0) {
		secondaryWeapons.GetString(GetRandomInt(0, secondaryWeapons.Length - 1), weaponName, sizeof(weaponName));
		GiveWeapon(client, weaponName, 0.6, 1);
	}

	if(lowestClient > 0) {
		float pos[3];
		GetClientAbsOrigin(lowestClient, pos);
		TeleportEntity(client, pos, NULL_VECTOR, NULL_VECTOR);
	}

	delete tier2Weapons;
	delete tier1Weapons;
	delete secondaryWeapons;

	return Plugin_Handled;
}

void GiveWeapon(int client, const char[] weaponName, float delay = 0.3, int clearSlot = -1) {
	if(clearSlot > 0) {
		int oldWpn = GetPlayerWeaponSlot(client, clearSlot);
		if(oldWpn != -1) {
			AcceptEntityInput(oldWpn, "Kill");
		}
	}
	PrintToServer("%N: Giving %s", client, weaponName);
	PrintToConsoleAll("%N: Giving %s", client, weaponName);
	DataPack pack;
	CreateDataTimer(delay, Timer_GiveWeapon, pack);
	pack.WriteCell(GetClientUserId(client));
	pack.WriteString(weaponName);
}

public Action Timer_GiveWeapon(Handle h, DataPack pack) {
	pack.Reset();
	int userid = pack.ReadCell();
	int client = GetClientOfUserId(userid);
	if(client > 0) {
		char wpnName[32];
		pack.ReadString(wpnName, sizeof(wpnName));
		
		int realSurvivor = L4D_GetBotOfIdlePlayer(client);
		if(realSurvivor <= 0) realSurvivor = client;
		CheatCommand(realSurvivor, "give", wpnName, "");
	}
	return Plugin_Handled;
}
public Action Timer_RemoveInvincibility(Handle h, int userid) {
	int client = GetClientOfUserId(userid);
	if(client > 0) {
		SetEntProp(client, Prop_Send, "m_iHealth", 100); 
		SDKUnhook(client, SDKHook_OnTakeDamage, OnInvincibleDamageTaken);
	}
	return Plugin_Handled;
}
public Action OnInvincibleDamageTaken(int victim,  int& attacker, int& inflictor, float& damage, int& damagetype, int& weapon, float damageForce[3], float damagePosition[3]) {
	damage = 0.0;
	return Plugin_Stop;
}
public Action Timer_GiveClientKit(Handle hdl, int user) {
	int client = GetClientOfUserId(user);
	if(client > 0 && !DoesClientHaveKit(client)) {
		UseExtraKit(client);
	}
	return Plugin_Continue;

}
public Action Timer_UpdateMinPlayers(Handle hdl) {
	//Set abm's min players to the amount of real survivors. Ran AFTER spawned incase they are pending joining
	int newPlayerCount = GetRealSurvivorsCount();
	if(hUpdateMinPlayers.BoolValue && hMinPlayers != null) {
		if(newPlayerCount > 4 && hMinPlayers.IntValue < newPlayerCount && newPlayerCount < 18) {
			abmExtraCount = newPlayerCount;
			#if defined DEBUG
			PrintDebug(DEBUG_GENERIC, "update abm_minplayers -> %d", abmExtraCount);
			#endif
			//Create the extra player hud
			hMinPlayers.IntValue = abmExtraCount;
		}
	}
	return Plugin_Continue;
}

public Action Timer_GiveKits(Handle timer) { 
	GiveStartingKits(); 
	return Plugin_Continue;	
}

public void OnMapStart() {
	isCheckpointReached = false;
	//If previous round was a failure, restore the amount of kits that were left directly after map transition
	if(isFailureRound) {
		extraKitsAmount = extraKitsStarted;
		//give kits if first
		if(L4D_IsFirstMapInScenario()) {
			GiveStartingKits();
		}
		isFailureRound = false;
	} else if(!L4D_IsFirstMapInScenario()) {
		//Re-set value incase it reset.
		//hMinPlayers.IntValue = abmExtraCount;
		currentChapter++;
	} else if(L4D_IsMissionFinalMap()) {
		//Add extra kits for finales
		char curMap[64];
		GetCurrentMap(curMap, sizeof(curMap));

		if(StrEqual(curMap, "c4m5_milltown_escape")) {
			allowTankSplit = false;
		} else {
			allowTankSplit = true;
		}

		int extraKits = GetSurvivorsCount() - 4;
		if(extraKits > 0) {
			extraKitsAmount += extraKits;
			extraKitsStarted = extraKitsAmount;
		}
		currentChapter++;
	} else {
		currentChapter++;
	}
	

	if(!isLateLoaded) {
		isLateLoaded = false;
	}

	//Lock the beginning door
	if(hMinPlayersSaferoomDoor.FloatValue > 0.0) {
		int entity = -1;
		while ((entity = FindEntityByClassname(entity, "prop_door_rotating_checkpoint")) != -1 && entity > MaxClients) {
			bool isLocked = GetEntProp(entity, Prop_Send, "m_bLocked") == 1;
			if(isLocked) {
				firstSaferoomDoorEntity = EntIndexToEntRef(entity);
				AcceptEntityInput(entity, "Close");
				AcceptEntityInput(entity, "Lock");
				AcceptEntityInput(entity, "ForceClosed");
				SDKHook(entity, SDKHook_Use, Hook_Use);
				// Failsafe:
				CreateTimer(20.0, Timer_OpenSaferoomDoor, _, TIMER_FLAG_NO_MAPCHANGE);
				break;
			}
		}
		
	}

	//Hook the end saferoom as event
	HookEntityOutput("info_changelevel", "OnStartTouch", EntityOutput_OnStartTouchSaferoom);
	HookEntityOutput("trigger_changelevel", "OnStartTouch", EntityOutput_OnStartTouchSaferoom);

	playersLoadedIn = 0;
	finaleStage = Stage_Inactive;

	L4D2_RunScript(HUD_SCRIPT_CLEAR);
}

public void OnConfigsExecuted() {
	if(hUpdateMinPlayers.BoolValue && hMinPlayers != null) {
		hMinPlayers.IntValue = abmExtraCount;
	}
}


public void OnMapEnd() {
	for(int i = 0; i < ammoPacks.Length; i++) {
		ArrayList clients = ammoPacks.Get(i, AMMOPACK_USERS);
		delete clients;
	}
	for(int i = 0; i < sizeof(cabinets); i++) {
		cabinets[i].id = 0;
		for(int b = 0; b < CABINET_ITEM_BLOCKS; b++) {
			cabinets[i].items[b] = 0;
		}
	}
	ammoPacks.Clear();
	playersLoadedIn = 0;
	abmExtraCount = 4;
	delete updateHudTimer;
}

public void Event_RoundFreezeEnd(Event event, const char[] name, bool dontBroadcast) {
	CreateTimer(50.0, Timer_Populate);
}
public Action Timer_Populate(Handle h) {
	PopulateItems();	
	return Plugin_Continue;

}

public void EntityOutput_OnStartTouchSaferoom(const char[] output, int caller, int client, float time) {
	if(!isCheckpointReached  && client > 0 && client <= MaxClients && IsValidClient(client) && GetClientTeam(client) == 2) {
		isCheckpointReached = true;
		abmExtraCount = GetSurvivorsCount();
		if(abmExtraCount > 4) {
			int extraPlayers = abmExtraCount - 4;
			float averageTeamHP = GetAverageHP();
			if(averageTeamHP <= 30.0) extraPlayers += (extraPlayers / 2); //if perm. health < 30, give an extra 4 on top of the extra
			else if(averageTeamHP <= 50.0) extraPlayers += (extraPlayers / 3); //if the team's average health is less than 50 (permament) then give another
			//Chance to get an extra kit (might need to be nerfed or restricted to > 50 HP)
			if(GetRandomFloat() < 0.3 && averageTeamHP <= 80.0) ++extraPlayers;


			//If hAddExtraKits TRUE: Append to previous, FALSE: Overwrite
			if(hAddExtraKits.BoolValue) 
				extraKitsAmount += extraPlayers;
			else
				extraKitsAmount = extraPlayers;
				
			extraKitsStarted = extraKitsAmount;

			hMinPlayers.IntValue = abmExtraCount;
			PrintToConsoleAll("CHECKPOINT REACHED BY %N | EXTRA KITS: %d", client, extraPlayers);
			PrintToServer("Player entered saferoom. Providing %d extra kits", extraKitsAmount);
		}
	}
}

public Action Event_RoundEnd(Event event, const char[] name, bool dontBroadcast) {
	if(!isFailureRound) isFailureRound = true;
	areItemsPopulated = false;
	return Plugin_Continue;
}

public Action Event_MapTransition(Event event, const char[] name, bool dontBroadcast) {
	#if defined DEBUG
	PrintToServer("Map transition | %d Extra Kits", extraKitsAmount);
	#endif
	isLateLoaded = false;
	extraKitsStarted = extraKitsAmount;
	abmExtraCount = GetRealSurvivorsCount();
	playerstoWaitFor = GetRealSurvivorsCount();
	return Plugin_Continue;
}
//TODO: Possibly hacky logic of on third different ent id picked up, in short timespan, detect as set of 4 (pills, kits) & give extra
public Action Event_Pickup(int client, int weapon) {
	static char name[32];
	GetEntityClassname(weapon, name, sizeof(name));
	if(StrEqual(name, "weapon_first_aid_kit", true)) {
		if(playerData[client].itemGiven) return Plugin_Continue;
		if((L4D_IsInFirstCheckpoint(client) || L4D_IsInLastCheckpoint(client)) && UseExtraKit(client)) {
			return Plugin_Handled;
		}
	}
	return Plugin_Continue;
}

public void OnEntityCreated(int entity, const char[] classname) {
	if(StrEqual(classname, "weapon_pain_pills_spawn") || StrEqual(classname, "weapon_first_aid_kit_spawn")) {
		SDKHook(entity, SDKHook_SpawnPost, Hook_CabinetItemSpawn);
	}else if(StrEqual(classname, "prop_health_cabinet", true)) {
		SDKHook(entity, SDKHook_SpawnPost, Hook_CabinetSpawn);
	}else if (StrEqual(classname, "upgrade_ammo_explosive") || StrEqual(classname, "upgrade_ammo_incendiary")) {
		int index = ammoPacks.Push(entity);
		ammoPacks.Set(index, new ArrayList(1), AMMOPACK_USERS);
		SDKHook(entity, SDKHook_Use, OnUpgradePackUse);
	}
}

///////////////////////////////////////////////////////////////////////////////
// Hooks
///////////////////////////////////////////////////////////////////////////////

//TODO: Implement extra kit amount to this
//TODO: Possibly check ammo stash and kit (relv. distance). Would fire on Last Stand 2nd .
public Action Hook_CabinetItemSpawn(int entity) {
	int cabinet = FindNearestEntityInRange(entity, "prop_health_cabinet", 60.0);
	if(cabinet > 0) {
		int ci = FindCabinetIndex(cabinet);
		//Check for any open block
		for(int block = 0; block < CABINET_ITEM_BLOCKS; block++) {
			int cabEnt = cabinets[ci].items[block];
			PrintDebug(DEBUG_ANY, "cabinet %d spawner %d block %d: %d", cabinet, entity, block, cabEnt);
			if(cabEnt <= 0) {
				cabinets[ci].items[block] = entity;
				PrintDebug(DEBUG_SPAWNLOGIC, "Adding spawner %d for cabinet %d block %d", entity, cabinet, block);
				break;
			}
		}
		//If Cabinet is full, spawner can not be a part of cabinet and is ignored. 
	}
	return Plugin_Continue;

}

public Action Hook_CabinetSpawn(int entity) {
	for(int i = 0; i < sizeof(cabinets); i++) {
		if(cabinets[i].id == 0) {
			cabinets[i].id = entity;
			break;
		}
	}
	PrintDebug(DEBUG_SPAWNLOGIC, "Adding cabinet %d", entity);
	return Plugin_Continue;

}

public Action OnUpgradePackUse(int entity, int activator, int caller, UseType type, float value) {
	if (entity > 2048 || entity <= MaxClients || !IsValidEntity(entity)) return Plugin_Continue;

	int primaryWeapon = GetPlayerWeaponSlot(activator, 0);
	if(IsValidEdict(primaryWeapon) && HasEntProp(primaryWeapon, Prop_Send, "m_upgradeBitVec")) {
		int index = ammoPacks.FindValue(entity, AMMOPACK_ENTID);
		if(index == -1) return Plugin_Continue;

		ArrayList clients = ammoPacks.Get(index, AMMOPACK_USERS);
		if(clients.FindValue(activator) > -1) {
			ClientCommand(activator, "play ui/menu_invalid.wav");
			return Plugin_Handled;
		}

		static char classname[32];
		int upgradeBits = GetEntProp(primaryWeapon, Prop_Send, "m_upgradeBitVec"), ammo;

		//Get the new flag bits
		GetEntityClassname(entity, classname, sizeof(classname));
		//SetUsedBySurvivor(activator, entity);
		int newFlags = StrEqual(classname, "upgrade_ammo_explosive") ? L4D2_WEPUPGFLAG_EXPLOSIVE : L4D2_WEPUPGFLAG_INCENDIARY;
		if(upgradeBits & L4D2_WEPUPGFLAG_LASER == L4D2_WEPUPGFLAG_LASER) newFlags |= L4D2_WEPUPGFLAG_LASER; 
		SetEntProp(primaryWeapon, Prop_Send, "m_upgradeBitVec", newFlags);
		GetEntityClassname(primaryWeapon, classname, sizeof(classname));

		if(!weaponMaxClipSizes.GetValue(classname, ammo)) {
			if(StrEqual(classname[7], "grenade_launcher", true)) ammo = 1;
			else if(StrEqual(classname[7], "rifle_m60", true)) ammo = 150;
			else {
				int currentAmmo = GetEntProp(primaryWeapon, Prop_Send, "m_iClip1");
				if(currentAmmo > 10) ammo = 10;
			}
		}
		
		if(GetEntProp(primaryWeapon, Prop_Send, "m_iClip1") < ammo) {
			SetEntProp(primaryWeapon, Prop_Send, "m_iClip1", ammo);
		}
		SetEntProp(primaryWeapon, Prop_Send, "m_nUpgradedPrimaryAmmoLoaded", ammo);
		clients.Push(activator);
		ClientCommand(activator, "play player/orch_hit_csharp_short.wav");

		if(clients.Length >= GetSurvivorsCount()) {
			AcceptEntityInput(entity, "kill");
			delete clients;
			ammoPacks.Erase(index);
		}
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

public Action Hook_Use(int entity, int activator, int caller, UseType type, float value) {
	SetEntProp(entity, Prop_Send, "m_bLocked", 1);
	AcceptEntityInput(entity, "Close");
	ClientCommand(activator, "play ui/menu_invalid.wav");
	PrintHintText(activator, "Waiting for players");
	return Plugin_Handled;
}

/////////////////////////////////////
/// TIMERS
////////////////////////////////////

//TODO: In future, possibly have a total percentage of spawns that are affected instead on a per-level
//TODO: In future, also randomize what items are selected? Two loops:
/*
	first loop pushes any valid _spawns into dynamic array
	while / for loop that runs until X amount affected (based on % of GetEntityCount()).
	
	Prioritize first aid kits somehow? Or split two groups: "utility" (throwables, kits, pill/shots), and "weapon" (all other spawns) 
*/

public Action Timer_ResetAmmoPack(Handle h, int entity) {
	if(IsValidEntity(entity)) {
		int index = ammoPacks.FindValue(entity, AMMOPACK_ENTID);
		if(index == -1) return Plugin_Continue;

		ArrayList clients = ammoPacks.Get(index, AMMOPACK_USERS);
		clients.Clear();
	}
	return Plugin_Continue;
}

public Action Timer_OpenSaferoomDoor(Handle h) {
	UnlockDoor(1);
	return Plugin_Continue;
}


void UnlockDoor(int flag) {
	int entity = EntRefToEntIndex(firstSaferoomDoorEntity);
	if(entity > 0) {
		PrintDebug(DEBUG_GENERIC, "Door unlocked, flag %d", flag);
			AcceptEntityInput(entity, "Unlock");
		SetEntProp(entity, Prop_Send, "m_bLocked", 0);
		SDKUnhook(entity, SDKHook_Use, Hook_Use);
		if(hSaferoomDoorAutoOpen.IntValue & flag) {
			AcceptEntityInput(entity, "Open");
		}
		firstSaferoomDoorEntity = INVALID_ENT_REFERENCE;
		if(!areItemsPopulated)
			PopulateItems();
	}

}

public Action Timer_UpdateHud(Handle h) {
	if(hEPIHudState.IntValue == 1 && !isCoop) {
		PrintToServer("[EPI] Gamemode no longer coop, stopping (hudState=%d, abmExtraCount=%d)", hEPIHudState.IntValue, abmExtraCount);
		L4D2_RunScript(HUD_SCRIPT_CLEAR);
		updateHudTimer = null;
		return Plugin_Stop;
	} 
	// TODO: Turn it off when state == 1
	int threshold = hEPIHudState.IntValue == 1 ? 4 : 0;
	if(hEPIHudState.IntValue == 1 && abmExtraCount < threshold) { //||  broke  && abmExtraCount < threshold
		PrintToServer("[EPI] Less than threshold (%d), stopping hud timer (hudState=%d, abmExtraCount=%d)", threshold, hEPIHudState.IntValue, abmExtraCount);
		L4D2_RunScript(HUD_SCRIPT_CLEAR);
		updateHudTimer = null;
		return Plugin_Stop;
	}

	if(cvEPIHudFlags.IntValue & 2) {
		hudModeTicks++;
		if(hudModeTicks > (showHudPingMode ? 8 : 20)) { 
			hudModeTicks = 0;
			showHudPingMode = !showHudPingMode;
		}
	}

	static char players[512], data[32], prefix[16];
	players[0] = '\0';
	// TODO: name scrolling
	// TODO: name cache (hook name change event), strip out invalid
	for(int i = 1; i <= MaxClients; i++) { 
		if(IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2) {
			data[0] = '\0';
			prefix[0] = '\0';
			int health = GetClientRealHealth(i);
			int client = i;
			if(IsFakeClient(i) && HasEntProp(i, Prop_Send, "m_humanSpectatorUserID")) {
				client = GetClientOfUserId(GetEntProp(i, Prop_Send, "m_humanSpectatorUserID"));
				if(client > 0)
					Format(prefix, 5 + HUD_NAME_LENGTH, "AFK %s", playerData[client].nameCache[playerData[client].scrollIndex]);
				else
					Format(prefix, HUD_NAME_LENGTH, "%N", i);
			} else {
				Format(prefix, HUD_NAME_LENGTH, "%s", playerData[client].nameCache[playerData[client].scrollIndex]);
			}

			playerData[client].AdvanceScroll();
			
			if(showHudPingMode) {
				if(client == 0) continue;
				int ping = L4D_GetPlayerResourceData(client, L4DResource_Ping);
				Format(data, sizeof(data), "%d ms", ping);
			} else {
				if(!IsPlayerAlive(i)) 
					Format(data, sizeof(data), "xx");
				else if(GetEntProp(i, Prop_Send, "m_bIsOnThirdStrike") == 1) 
					Format(data, sizeof(data), "+%d b&w %s%s%s", health, items[i].throwable, items[i].usable, items[i].consumable);
				else if(GetEntProp(i, Prop_Send, "m_isIncapacitated") == 1)
					Format(data, sizeof(data), "+%d --", health);
				else
					Format(data, sizeof(data), "+%d %s%s%s", health, items[i].throwable, items[i].usable, items[i].consumable);
			}
			
			Format(players, sizeof(players), "%s%s %s\\n", players, prefix, data);
		}
	}
	if(players[0] == '\0') {
		PrintToServer("[EPI] No players online", hEPIHudState.IntValue, abmExtraCount);
		L4D2_RunScript(HUD_SCRIPT_CLEAR);
		updateHudTimer = null;
		return Plugin_Stop;
	}
	if(hEPIHudState.IntValue < 3) {
		// PrintToConsoleAll(HUD_SCRIPT_DATA, players);
		RunVScriptLong(HUD_SCRIPT_DATA, players);
	} else {
		PrintHintTextToAll("DEBUG HUD TIMER");
		RunVScriptLong(HUD_SCRIPT_DEBUG, players);
	}
	
	return Plugin_Continue;
}

///////////////////////////////////////////////////////////////////////////////
// Methods
///////////////////////////////////////////////////////////////////////////////

public void PopulateItems() {
	int survivors = GetRealSurvivorsCount();
	if(survivors <= 4) return;

	areItemsPopulated = true;

	//Generic Logic
	float percentage = hExtraItemBasePercentage.FloatValue * survivors;
	PrintToServer("[EPI] Populating extra items based on player count (%d) | Percentage %.2f%%", survivors, percentage * 100);
	PrintToConsoleAll("[EPI] Populating extra items based on player count (%d) | Percentage %.2f%%", survivors, percentage * 100);
	char classname[64];
	int affected = 0;

	for(int i = MaxClients + 1; i < 2048; i++) {
		if(IsValidEntity(i)) {
			GetEntityClassname(i, classname, sizeof(classname));
			if(StrContains(classname, "_spawn", true) > -1 
				&& StrContains(classname, "zombie", true) == -1
				&& StrContains(classname, "scavenge", true) == -1
				&& HasEntProp(i, Prop_Data, "m_itemCount")
			) {
				int count = GetEntProp(i, Prop_Data, "m_itemCount");
				if(count > 0 && GetRandomFloat() < percentage) {
					SetEntProp(i, Prop_Data, "m_itemCount", ++count);
					++affected;
				}
			}
		}
	}
	PrintDebug(DEBUG_SPAWNLOGIC, "Incremented counts for %d items", affected);


	//Cabinet logic
	PrintDebug(DEBUG_SPAWNLOGIC, "Populating cabinets with extra items");
	int spawner, count;
	for(int i = 0; i < sizeof(cabinets); i++) {
		if(cabinets[i].id == 0 || !IsValidEntity(cabinets[i].id)) break;
		GetEntityClassname(cabinets[i].id, classname, sizeof(classname));
		if(!StrEqual(classname, "prop_health_cabinet")) {
			PrintToServer("Cabinet %d (ent %d) is not a valid entity, is %s. Skipping", i, cabinets[i].id, classname);
			cabinets[i].id = 0;
			continue;
		}
		int spawnCount = GetEntProp(cabinets[i].id, Prop_Data, "m_pillCount");
		int extraAmount = RoundToCeil(float(abmExtraCount) * (float(spawnCount)/4.0) - spawnCount);
		bool hasASpawner;
		while(extraAmount > 0) {
			//FIXME: spawner is sometimes invalid entity. Ref needed?
			for(int block = 0; block < CABINET_ITEM_BLOCKS; block++) {
				spawner = cabinets[i].items[block];
				if(spawner > 0) {
					if(!HasEntProp(spawner, Prop_Data, "m_itemCount")) continue;
					hasASpawner = true;
					count = GetEntProp(spawner, Prop_Data, "m_itemCount") + 1;
					SetEntProp(spawner, Prop_Data, "m_itemCount", count);
					if(--extraAmount == 0) break;
				}
			}
			//Incase cabinet is empty
			if(!hasASpawner) break;
		}
	}
}

/////////////////////////////////////
/// Stocks
////////////////////////////////////
// enum struct PlayerData {
// 	bool itemGiven; //Is player being given an item (such that the next pickup event is ignored)
// 	bool isUnderAttack; //Is the player under attack (by any special)
// 	bool active;

// 	WeaponId itemID[6]; //int -> char?
// 	bool lasers;
// 	char meleeID[32];


// 	int primaryHealth;
// 	int tempHealth;

// 	char model[32];
// }

void DropDroppedInventories() {
	StringMapSnapshot snapshot = pInv.Snapshot();
	static PlayerInventory inv;
	static char buffer[32];
	int time = GetTime();
	for(int i = 0; i < snapshot.Length; i++) {
		snapshot.GetKey(i, buffer, sizeof(buffer));
		pInv.GetArray(buffer, inv, sizeof(inv));
		if(time - inv.timestamp > PLAYER_DROP_TIMEOUT_SECONDS) {
			PrintDebug(DEBUG_GENERIC, "[EPI] Dropping inventory for %s", buffer);
			pInv.Remove(buffer);
		}
	}
}
void SaveInventory(int client) {
	PrintDebug(DEBUG_GENERIC, "Saving inventory for %N", client);
	PlayerInventory inventory;
	inventory.timestamp = GetTime();
	inventory.isAlive = IsPlayerAlive(client);
	playerData[client].state = State_Active;
	GetClientAbsOrigin(client, inventory.location);

	inventory.primaryHealth = GetClientHealth(client);
	GetClientModel(client, inventory.model, 64);
	inventory.survivorType = GetEntProp(client, Prop_Send, "m_survivorCharacter");

	int weapon;
	static char buffer[32];
	for(int i = 5; i >= 0; i--) {
		weapon = GetPlayerWeaponSlot(client, i);
		inventory.itemID[i] = IdentifyWeapon(weapon);
	}
	if(inventory.itemID[0] != WEPID_MELEE && inventory.itemID[0] != WEPID_NONE)
		inventory.lasers = GetEntProp(weapon, Prop_Send, "m_upgradeBitVec") == 4;
	
	GetClientAuthId(client, AuthId_Steam3, buffer, sizeof(buffer));
	pInv.SetArray(buffer, inventory, sizeof(inventory));
}

void RestoreInventory(int client, PlayerInventory inventory) {
	PrintToConsoleAll("[debug:RINV] health=%d primaryID=%d secondID=%d throw=%d kit=%d pill=%d surv=%d", inventory.primaryHealth, inventory.itemID[0], inventory.itemID[1], inventory.itemID[2], inventory.itemID[3], inventory.itemID[4], inventory.itemID[5], inventory.survivorType);

	SetEntityModel(client, inventory.model);
	SetEntProp(client, Prop_Send, "m_survivorCharacter", inventory.survivorType);

	char buffer[32];
	if(inventory.isAlive) {
		SetEntProp(client, Prop_Send, "m_iHealth", inventory.primaryHealth);

		int weapon;
		for(int i = 5; i >= 0; i--) {
			WeaponId id = inventory.itemID[i];
			if(id != WEPID_NONE) {
				if(id == WEPID_MELEE)
					GetWeaponName(id, buffer, sizeof(buffer));
				else 
					GetMeleeWeaponName(id, buffer, sizeof(buffer));
				weapon = GiveClientWeapon(client, buffer);
			}
		}
		if(inventory.lasers) {
			SetEntProp(weapon, Prop_Send, "m_upgradeBitVec", 4);
		}
	}
}

bool GetLatestInventory(int client, PlayerInventory inventory) {
	static char buffer[32];
	GetClientAuthId(client, AuthId_Steam3, buffer, sizeof(buffer));
	return pInv.GetArray(buffer, inventory, sizeof(inventory));
}

bool GetInventory(const char[] steamid, PlayerInventory inventory) {
	return pInv.GetArray(steamid, inventory, sizeof(inventory));
}

bool DoesInventoryDiffer(int client) {
	static char buffer[32];
	GetClientAuthId(client, AuthId_Steam3, buffer, sizeof(buffer));
	PlayerInventory inventory;
	if(!pInv.GetArray(buffer, inventory, sizeof(inventory)) || inventory.timestamp == 0) {
		return false;
	}

	WeaponId currentPrimary = IdentifyWeapon(GetPlayerWeaponSlot(client, 0));
	WeaponId currentSecondary = IdentifyWeapon(GetPlayerWeaponSlot(client, 1));
	WeaponId storedPrimary = inventory.itemID[0];
	WeaponId storedSecondary = inventory.itemID[1];

	return currentPrimary != storedPrimary || currentSecondary != storedSecondary;
}

stock int FindFirstSurvivor() {
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2) {
			return i;
		}
	}
	return -1;
}

stock void GiveStartingKits() {
	int skipLeft = 4;
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == 2) {
			//Skip at least the first 4 players, as they will pickup default kits. 
			//If player somehow already has it ,also skip them.
			if(skipLeft > 0 || DoesClientHaveKit(i)) {
				--skipLeft;
				continue;
			}else{
				int item = GivePlayerItem(i, "weapon_first_aid_kit");
				EquipPlayerWeapon(i, item);
			}
		}
	}
}

stock int GetSurvivorsCount() {
	#if defined DEBUG_FORCE_PLAYERS
	return DEBUG_FORCE_PLAYERS;
	#endif
	int count = 0;
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2) {
			++count;
		}
	}
	return count;
}

stock int GetActiveCount() {
	int count;
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2 && playerData[i].state == State_Active) {
			count++;
		}
	}
	return count;
}

stock int GetRealSurvivorsCount() {
	#if defined DEBUG_FORCE_PLAYERS
	return DEBUG_FORCE_PLAYERS;
	#endif
	int count = 0;
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2) {
			if(IsFakeClient(i) && HasEntProp(i, Prop_Send, "m_humanSpectatorUserID") && GetEntProp(i, Prop_Send, "m_humanSpectatorUserID") == 0) continue;
			++count;
		}
	}
	return count;
}

stock bool AreAllClientsReady() {
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && !IsClientInGame(i)) {
			return false;
		}
	}
	return true;
}

stock bool DoesClientHaveKit(int client) {
	char wpn[32];
	if(IsClientConnected(client) && IsClientInGame(client) && GetClientWeaponName(client, 3, wpn, sizeof(wpn))) {
		if(StrEqual(wpn, "weapon_first_aid_kit")) {
			return true;
		}
	}
	return false;
}

stock bool UseExtraKit(int client) {
	if(extraKitsAmount > 0) {
		playerData[client].itemGiven = true;
		int ent = GivePlayerItem(client, "weapon_first_aid_kit");
		EquipPlayerWeapon(client, ent);
		playerData[client].itemGiven = false;
		if(--extraKitsAmount <= 0) {
			extraKitsAmount = 0;
		}
		return true;
	}
	return false;
}

stock void PrintDebug(int level, const char[] format, any ... ) {
	#if defined DEBUG_LEVEL
	if(level <= DEBUG_LEVEL) {
		char buffer[256];
		VFormat(buffer, sizeof(buffer), format, 3);
		PrintToServer("[Debug] %s", buffer);
		PrintToConsoleAll("[Debug] %s", buffer);
	}
	#endif
}
stock float GetAverageHP() {
	int totalHP, clients;
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i)) {
			totalHP += GetClientHealth(i);
			++clients;
		}
	}
	return float(totalHP) / float(clients);
}

stock int GetClientRealHealth(int client) {
	//First filter -> Must be a valid client, successfully in-game and not an spectator (The dont have health).
	if(!client
	|| !IsValidEntity(client)
	|| !IsClientInGame(client)
	|| !IsPlayerAlive(client)
	|| IsClientObserver(client))
	{
		return -1;
	}
	
	//If the client is not on the survivors team, then just return the normal client health.
	if(GetClientTeam(client) != 2)
	{
		return GetClientHealth(client);
	}
	
	//First, we get the amount of temporal health the client has
	float buffer = GetEntPropFloat(client, Prop_Send, "m_healthBuffer");
	
	//We declare the permanent and temporal health variables
	float TempHealth;
	int PermHealth = GetClientHealth(client);
	
	//In case the buffer is 0 or less, we set the temporal health as 0, because the client has not used any pills or adrenaline yet
	if(buffer <= 0.0)
	{
		TempHealth = 0.0;
	}
	
	//In case it is higher than 0, we proceed to calculate the temporl health
	else
	{
		//This is the difference between the time we used the temporal item, and the current time
		float difference = GetGameTime() - GetEntPropFloat(client, Prop_Send, "m_healthBufferTime");
		
		//We get the decay rate from this convar (Note: Adrenaline uses this value)
		float decay = GetConVarFloat(FindConVar("pain_pills_decay_rate"));
		
		//This is a constant we create to determine the amount of health. This is the amount of time it has to pass
		//before 1 Temporal HP is consumed.
		float constant = 1.0/decay;
		
		//Then we do the calcs
		TempHealth = buffer - (difference / constant);
	}
	
	//If the temporal health resulted less than 0, then it is just 0.
	if(TempHealth < 0.0)
	{
		TempHealth = 0.0;
	}
	
	//Return the value
	return RoundToFloor(PermHealth + TempHealth);
}  

int FindCabinetIndex(int cabinetId) {
	for(int i = 0; i < sizeof(cabinets); i++) {
		if(cabinets[i].id == cabinetId) return i;
	}
	return -1;
}

void UpdatePlayerInventory(int client) {
	static char item[16];
	if(GetClientWeaponName(client, 2, item, sizeof(item))) {
		items[client].throwable[0] = CharToUpper(item[7]);
		if(items[client].throwable[0] == 'V') {
			items[client].throwable[0] = 'B'; //Replace [V]omitjar with [B]ile
		}
		items[client].throwable[1] = '\0';
	} else {
		items[client].throwable[0] = '\0';
	}

	if(GetClientWeaponName(client, 3, item, sizeof(item))) {
		items[client].usable[0] = CharToUpper(item[7]);
		items[client].usable[1] = '\0';
		if(items[client].throwable[0] == 'F') {
			items[client].throwable[0] = '+'; //Replace [V]omitjar with [B]ile
		}
	} else {
		items[client].usable[0] = '-';
		items[client].usable[1] = '\0';
	}

	if(GetClientWeaponName(client, 4, item, sizeof(item))) {
		items[client].consumable[0] = CharToUpper(item[7]);
		items[client].consumable[1] = '\0';
	} else {
		items[client].consumable[0] = '\0';
	}
}

stock void RunVScriptLong(const char[] sCode, any ...) {
	static int iScriptLogic = INVALID_ENT_REFERENCE;
	if(iScriptLogic == INVALID_ENT_REFERENCE || !IsValidEntity(iScriptLogic)) {
		iScriptLogic = EntIndexToEntRef(CreateEntityByName("logic_script"));
		if(iScriptLogic == INVALID_ENT_REFERENCE|| !IsValidEntity(iScriptLogic))
			SetFailState("Could not create 'logic_script'");
		
		DispatchSpawn(iScriptLogic);
	}
	
	static char sBuffer[2048];
	VFormat(sBuffer, sizeof(sBuffer), sCode, 2);
	
	SetVariantString(sBuffer);
	AcceptEntityInput(iScriptLogic, "RunScriptCode");
}

// Gets a position (from a nav area)
stock bool GetIdealPositionInSurvivorFlow(int target, float pos[3]) {
	static float ang[3];
	int client = GetLowestFlowSurvivor(target);
	if(client > 0) {
		GetClientAbsOrigin(client, pos);
		GetClientAbsAngles(client, ang);
		ang[2] = -ang[2];
		TR_TraceRayFilter(pos, ang, MASK_SHOT, RayType_Infinite, Filter_GroundOnly);
		if(TR_DidHit()) {
			TR_GetEndPosition(pos);
			return true;
		} else {
			return false;
		}
	}
	return false;
}

bool Filter_GroundOnly(int entity, int mask) {
	return entity == 0;
}

stock int GetLowestFlowSurvivor(int ignoreTarget = 0) {
	int client = L4D_GetHighestFlowSurvivor();
	if(client != ignoreTarget) {
		return client;
	} else {
		client = -1;
		float lowestFlow = L4D2Direct_GetFlowDistance(client);
		for(int i = 1; i <= MaxClients; i++) {
			if(ignoreTarget != i && IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i)) {
				if(L4D2Direct_GetFlowDistance(i) < lowestFlow) {
					client = i;
					lowestFlow = L4D2Direct_GetFlowDistance(i);
				}
			}
		}
		return client;
	}
}

stock int GetHighestFlowSurvivor(int ignoreTarget = 0) {
	int client = L4D_GetHighestFlowSurvivor();
	if(client != ignoreTarget) {
		return client;
	} else {
		client = -1;
		float highestFlow = L4D2Direct_GetFlowDistance(client);
		for(int i = 1; i <= MaxClients; i++) {
			if(ignoreTarget != i && IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i)) {
				float dist = L4D2Direct_GetFlowDistance(i);
				if(dist > highestFlow) {
					client = i;
					highestFlow = dist;
				}
			}
		}
		return client;
	}
}


stock float GetSurvivorFlowDifference() {
	int client = L4D_GetHighestFlowSurvivor();
	float highestFlow = L4D2Direct_GetFlowDistance(client);
	client = GetLowestFlowSurvivor();
	return highestFlow - L4D2Direct_GetFlowDistance(client);
}