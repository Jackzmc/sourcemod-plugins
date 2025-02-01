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


#pragma semicolon 1
#pragma newdecls required

#define DEBUG_INFO 0
#define DEBUG_GENERIC 1
#define DEBUG_SPAWNLOGIC 2
#define DEBUG_ANY 3

#define INV_SAVE_TIME 5.0 // How long after a save request do we actually save. Seconds.
#define MIN_JOIN_TIME 30 // The minimum amount of time after player joins where we can start saving

//Set the debug level
#define DEBUG_LEVEL DEBUG_SPAWNLOGIC
#define EXTRA_PLAYER_HUD_UPDATE_INTERVAL 0.8
//Sets g_survivorCount to this value if set
// #define DEBUG_FORCE_PLAYERS 7

#define FLOW_CUTOFF 500.0 // The cutoff of flow, so that witches / tanks don't spawn in saferooms / starting areas, [0 + FLOW_CUTOFF, MapMaxFlow - FLOW_CUTOFF]

#define EXTRA_TANK_MIN_SEC 2.0
#define EXTRA_TANK_MAX_SEC 16.0
// The map's max flow rate is divided by this. Parish Ch4 = ~16 items
#define MAX_RANDOM_SPAWNS 1700.0
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
#include <multicolors>
#undef REQUIRE_PLUGIN
#include <CreateSurvivorBot>

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
	name =  "L4D2 5+ Extra Tools & Director", 
	author = "jackzmc", 
	description = "Automatic system for management of 5+ player games. Provides extra kits, items, and more", 
	version = PLUGIN_VERSION, 
	url = "https://github.com/Jackzmc/sourcemod-plugins"
};

ConVar hExtraItemBasePercentage, hExtraSpawnBasePercentage, hAddExtraKits, hMinPlayers, hUpdateMinPlayers, hMinPlayersSaferoomDoor, hSaferoomDoorWaitSeconds, hSaferoomDoorAutoOpen, hEPIHudState, hExtraFinaleTank, cvDropDisconnectTime, hSplitTankChance, cvFFDecreaseRate, cvZDifficulty, cvEPIHudFlags, cvEPISpecialSpawning, cvEPIGamemodes, hGamemode, cvEPITankHealth, cvEPIEnabledMode;
ConVar cvEPICommonCountScale, cvEPICommonCountScaleMax;
ConVar g_ffFactorCvar, hExtraTankThreshold;


ConVar cvZCommonLimit; int commonLimitBase; bool isSettingLimit; 

int g_extraKitsAmount, g_extraKitsStart, g_saferoomDoorEnt, g_prevPlayerCount;
bool g_forcedSurvivorCount, g_extraKitsSpawnedFinale;
static int g_currentChapter;
bool g_isCheckpointReached, g_isLateLoaded, g_startCampaignGiven, g_isFailureRound, g_areItemsPopulated;
static ArrayList g_ammoPacks;
static Handle updateHudTimer;
static bool showHudPingMode;
static int hudModeTicks;
static char g_currentGamemode[32];
static bool g_isGamemodeAllowed;
int g_survivorCount, g_realSurvivorCount;
bool g_isFinaleEnding;
int g_finaleVehicleStartTime;
static bool g_epiEnabled;
bool g_isOfficialMap;

bool g_isSpeaking[MAXPLAYERS+1];

enum Difficulty {
	Difficulty_Easy,
	Difficulty_Normal,
	Difficulty_Advanced,
	Difficulty_Expert,
}

Difficulty zDifficulty;

bool g_extraFinaleTankEnabled;

enum State {
	State_Empty,
	State_PendingEmpty,
	State_Pending,
	State_Active
}
#if defined DEBUG_LEVEL
char StateNames[4][] = {
	"Empty",
	"PendingEmpty",
	"Pending",
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
	State state; // join state
	bool hasJoined;
	int joinTime;
	float returnedIdleTime;
	
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

	WeaponId itemID[6];
	MeleeWeaponId meleeID; // If itemID[1] == WeaponId_Melee, pull from this
	bool lasers;

	int primaryHealth;
	int tempHealth;

	char model[64];
	int survivorType;

	float location[3];
}

PlayerData playerData[MAXPLAYERS+1];

static StringMap weaponMaxClipSizes;
static StringMap pInv;
static int g_lastInvSave[MAXPLAYERS+1];
static Handle g_saveTimer[MAXPLAYERS+1] = { null, ... };

static char HUD_SCRIPT_DATA[] = "eph <- { Fields = { players = { slot = g_ModeScript.HUD_RIGHT_BOT, dataval = \"%s\", flags = g_ModeScript.HUD_FLAG_ALIGN_LEFT | g_ModeScript.HUD_FLAG_TEAM_SURVIVORS | g_ModeScript.HUD_FLAG_NOBG } } }\nHUDSetLayout(eph)\nHUDPlace(g_ModeScript.HUD_RIGHT_BOT,0.78,0.77,0.3,0.3)\ng_ModeScript;";
static char HUD_SCRIPT_CLEAR[] = "g_ModeScript._eph <- { Fields = { players = { slot = g_ModeScript.HUD_RIGHT_BOT, dataval = \"\", flags = g_ModeScript.HUD_FLAG_ALIGN_LEFT|g_ModeScript.HUD_FLAG_TEAM_SURVIVORS|g_ModeScript.HUD_FLAG_NOBG } } };HUDSetLayout( g_ModeScript._eph );g_ModeScript";
static char HUD_SCRIPT_DEBUG[] = "g_ModeScript._ephdebug <- {Fields = {players = {slot = g_ModeScript.HUD_RIGHT_BOT, dataval = \"DEBUG!!! %s\", flags = g_ModeScript.HUD_FLAG_ALIGN_LEFT|g_ModeScript.HUD_FLAG_TEAM_SURVIVORS|g_ModeScript.HUD_FLAG_NOBG}}};HUDSetLayout(g_ModeScript._ephdebug);HUDPlace(g_ModeScript.HUD_RIGHT_BOT, 0.72,0.78,0.3,0.3);g_ModeScript";


#define CABINET_ITEM_BLOCKS 4
enum struct Cabinet {
	int id;
	int items[CABINET_ITEM_BLOCKS];
}
static Cabinet cabinets[10]; //Store 10 cabinets

enum EPI_FinaleTankState {
	Stage_Inactive = 0,
	Stage_Active = 1, // Finale has started
	Stage_FirstTankSpawned = 2,
	Stage_SecondTankSpawned = 3,
	Stage_ActiveDone = 10 // No more logic to be done
}
EPI_FinaleTankState g_epiTankState;
int g_finaleState;

//// Definitions completSe

#include <epi/director.sp>

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
	if(late) g_isLateLoaded = true;
	return APLRes_Success;
} 

public void OnPluginStart() {
	EngineVersion g_Game = GetEngineVersion();
	if(g_Game != Engine_Left4Dead2) {
		SetFailState("This plugin is for L4D2 only.");	
	}

	weaponMaxClipSizes = new StringMap();
	pInv = new StringMap();
	g_ammoPacks = new ArrayList(2); //<int entityID, ArrayList clients>
	
	HookEvent("player_spawn", 		Event_PlayerSpawn);
	HookEvent("player_first_spawn", Event_PlayerFirstSpawn);
	HookEvent("player_left_start_area", Event_LeaveStartArea);
	//Tracking player items:
	HookEvent("item_pickup",		Event_ItemPickup);
	HookEvent("weapon_drop",		Event_ItemPickup);

	HookEvent("round_end", 			Event_RoundEnd);
	HookEvent("map_transition", 	Event_MapTransition);
	HookEvent("game_start", 		Event_GameStart);
	HookEvent("game_end", 			Event_GameStart);
	HookEvent("finale_start",       Event_FinaleStart);

	//Special Event Tracking
	HookEvent("player_info", Event_PlayerInfo);
	HookEvent("player_disconnect", Event_PlayerDisconnect);
	HookEvent("player_death", Event_PlayerDeath);
	HookEvent("player_incapacitated", Event_PlayerIncapped);

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

	HookEvent("witch_spawn", Event_WitchSpawn);
	HookEvent("finale_vehicle_incoming", Event_FinaleVehicleIncoming);
	HookEvent("player_bot_replace", Event_PlayerToIdle);
	HookEvent("bot_player_replace", Event_PlayerFromIdle);

	



	hExtraItemBasePercentage  = CreateConVar("epi_item_chance", "0.034", "The base chance (multiplied by player count) of an extra item being spawned.", FCVAR_NONE, true, 0.0, true, 1.0);
	hExtraSpawnBasePercentage = CreateConVar("epi_spawn_chance", "0.01", "The base chance (multiplied by player count) of an extra item spawner being created.", FCVAR_NONE, true, 0.0, true, 1.0);
	hAddExtraKits 			  = CreateConVar("epi_kitmode", "0", "Decides how extra kits should be added.\n0 -> Overwrites previous extra kits\n1 -> Adds onto previous extra kits", FCVAR_NONE, true, 0.0, true, 1.0);
	hUpdateMinPlayers		  = CreateConVar("epi_updateminplayers", "1", "Should the plugin update abm\'s cvar min_players convar to the player count?\n 0 -> NO\n1 -> YES", FCVAR_NONE, true, 0.0, true, 1.0);
	hMinPlayersSaferoomDoor   = CreateConVar("epi_doorunlock_percent", "0.75", "The percent of players that need to be loaded in before saferoom door is opened.\n 0 to disable", FCVAR_NONE, true, 0.0, true, 1.0);
	hSaferoomDoorWaitSeconds  = CreateConVar("epi_doorunlock_wait", "25", "How many seconds after to unlock saferoom door. 0 to disable", FCVAR_NONE, true, 0.0);
	hSaferoomDoorAutoOpen 	  = CreateConVar("epi_doorunlock_open", "0", "Controls when the door automatically opens after unlocked. Add bits together.\n0 = Never, 1 = When timer expires, 2 = When all players loaded in", FCVAR_NONE, true, 0.0);
	hEPIHudState 			  = CreateConVar("epi_hudstate", "1", "Controls when the hud displays.\n0 -> OFF, 1 = When 5+ players, 2 = ALWAYS", FCVAR_NONE, true, 0.0, true, 3.0);
	hExtraFinaleTank 		  = CreateConVar("epi_extra_tanks", "3", "Add bits together. 0 = Normal tank spawning, 1 = 50% tank split on non-finale (half health), 2 = Tank split (full health) on finale ", FCVAR_NONE, true, 0.0, true, 3.0);
	hExtraTankThreshold 	  = CreateConVar("epi_extra_tanks_min_players", "6", "The minimum number of players for extra tanks to spawn. When disabled, normal 5+ tank health applies", FCVAR_NONE, true, 0.0);
	hSplitTankChance 		  = CreateConVar("epi_splittank_chance", "0.65", "The % chance of a split tank occurring in non-finales", FCVAR_NONE, true, 0.0, true, 1.0);
	cvDropDisconnectTime      = CreateConVar("epi_disconnect_time", "120.0", "The amount of seconds after a player has actually disconnected, where their character slot will be void. 0 to disable", FCVAR_NONE, true, 0.0);
	cvFFDecreaseRate          = CreateConVar("epi_ff_decrease_rate", "0.3", "The friendly fire factor is subtracted from the formula (playerCount-4) * this rate. Effectively reduces ff penalty when more players. 0.0 to subtract none", FCVAR_NONE, true, 0.0);
	cvEPIHudFlags 			  = CreateConVar("epi_hud_flags", "3", "Add together.\n1 = Scrolling hud, 2 = Show ping", FCVAR_NONE, true, 0.0);
	cvEPISpecialSpawning      = CreateConVar("epi_sp_spawning", "2", "Determines what specials are spawned. Add bits together.\n1 = Normal specials\n2 = Witches\n4 = Tanks", FCVAR_NONE, true, 0.0);
	cvEPITankHealth			  = CreateConVar("epi_tank_chunkhp", "2500", "The amount of health added to tank, for each extra player", FCVAR_NONE, true, 0.0);
	cvEPIGamemodes            = CreateConVar("epi_gamemodes", "coop,realism,versus", "Gamemodes where plugin is active. Comma-separated", FCVAR_NONE);
	cvEPIEnabledMode		  = CreateConVar("epi_enabled", "1", "Is EPI enabled?\n0=OFF\n1=Auto (Official Maps Only)(5+)\n2=Auto (Any map) (5+)\n3=Forced on", FCVAR_NONE, true, 0.0, true, 3.0);
	cvEPICommonCountScale     = CreateConVar("epi_commons_scale_multiplier", "0", "This value is multiplied by the number of extra players playing. It's then added to z_common_limit. 5 players with value 5 would be z_common_limit + ", FCVAR_NONE, true, 0.0);
	cvEPICommonCountScaleMax  = CreateConVar("epi_commons_scale_max", "60", "The maximum amount that z_common_limit can be scaled to.", FCVAR_NONE, true, 0.0);
	cvZCommonLimit = FindConVar("z_common_limit");
	directorSpawnChance = CreateConVar("epi_director_special_chance", "0.038", "The base chance a special spawns, scaled by the survivor's average stress.", FCVAR_NONE, true, 0.0, true, 1.0);

	cvEPICommonCountScale.AddChangeHook(Cvar_CommonScaleChange);
	cvEPICommonCountScaleMax.AddChangeHook(Cvar_CommonScaleChange);
	cvZCommonLimit.AddChangeHook(Cvar_CommonScaleChange);
	
	// TODO: hook flags, reset name index / ping mode
	cvEPIHudFlags.AddChangeHook(Cvar_HudStateChange);
	cvEPISpecialSpawning.AddChangeHook(Cvar_SpecialSpawningChange);
	
	if(hUpdateMinPlayers.BoolValue) {
		hMinPlayers = FindConVar("abm_minplayers");
		if(hMinPlayers != null) PrintDebug(DEBUG_INFO, "Found convar abm_minplayers");
	}

	char buffer[16];
	cvZDifficulty = FindConVar("z_difficulty");
	cvZDifficulty.GetString(buffer, sizeof(buffer));
	cvZDifficulty.AddChangeHook(Event_DifficultyChange);
	Event_DifficultyChange(cvZDifficulty, buffer, buffer);

	hGamemode = FindConVar("mp_gamemode"); 
	hGamemode.GetString(g_currentGamemode, sizeof(g_currentGamemode));
	hGamemode.AddChangeHook(Event_GamemodeChange);
	Event_GamemodeChange(hGamemode, g_currentGamemode, g_currentGamemode);

	
	if(g_isLateLoaded) {
		for(int i = 1; i <= MaxClients; i++) {
			if(IsClientConnected(i) && IsClientInGame(i)) {
				if(GetClientTeam(i) == 2) {
					SaveInventory(i);
				}
				playerData[i].Setup(i);
				SDKHook(i, SDKHook_WeaponEquip, Event_Pickup);
			}
		}
		g_currentChapter = L4D_GetCurrentChapter();
		UpdateSurvivorCount();
		TryStartHud();
	}


	AutoExecConfig(true, "l4d2_extraplayeritems");

	RegAdminCmd("sm_epi_sc", Command_SetSurvivorCount, ADMFLAG_KICK);
	RegAdminCmd("sm_epi_val", Command_EpiVal, ADMFLAG_GENERIC);
	#if defined DEBUG_LEVEL
		RegAdminCmd("sm_epi_setkits", Command_SetKitAmount, ADMFLAG_CHEATS, "Sets the amount of extra kits that will be provided");
		RegAdminCmd("sm_epi_lock", Command_ToggleDoorLocks, ADMFLAG_CHEATS, "Toggle all toggle\'s lock state");
		RegAdminCmd("sm_epi_kits", Command_GetKitAmount, ADMFLAG_CHEATS);
		RegConsoleCmd("sm_epi_stats", Command_DebugStats);
		RegConsoleCmd("sm_epi_debug", Command_Debug);
		// RegAdminCmd("sm_epi_val", Command_EPIValue);
		RegAdminCmd("sm_epi_trigger", Command_Trigger, ADMFLAG_CHEATS);
	#endif
	RegAdminCmd("sm_epi_restore", Command_RestoreInventory, ADMFLAG_KICK);
	RegAdminCmd("sm_epi_save", Command_SaveInventory, ADMFLAG_KICK);
	CreateTimer(DIRECTOR_TIMER_INTERVAL, Timer_Director, _, TIMER_REPEAT);
	CreateTimer(30.0, Timer_ForceUpdateInventories, _, TIMER_REPEAT);

}

void Event_FinaleVehicleIncoming(Event event, const char[] name, bool dontBroadcast) {
	PrintDebug(DEBUG_INFO, "Finale vehicle incoming, preventing early tank spawns");
	g_isFinaleEnding = true;
	g_finaleVehicleStartTime = GetTime();
}

Action Timer_ForceUpdateInventories(Handle h) {
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2) {
			// SaveInventory(i);
		}
	}
	Director_CheckSpawnCounts();
	return Plugin_Continue;
}

public void OnClientPutInServer(int client) {
	Director_OnClientPutInServer(client);
	if(!IsFakeClient(client)) {
		playerData[client].Setup(client);

		if(GetClientTeam(client) == 2) {
			if(g_isGamemodeAllowed) {
				// CreateTimer(0.2, Timer_CheckInventory, client);
			}
		}/* else if(abmExtraCount >= 4 && GetClientTeam(client) == 0) {
			// TODO: revert revert
			// L4D_TakeOverBot(client);
		} */
	}
}

public void OnClientDisconnect(int client) {
	// For when bots disconnect in saferoom transitions, empty:
	if(playerData[client].state == State_PendingEmpty)
		playerData[client].state = State_Empty;
		
	if(!IsFakeClient(client) && IsClientInGame(client) && GetClientTeam(client) == 2)
		SaveInventory(client);
	g_isSpeaking[client] = false;
	g_saveTimer[client] = null;
}

public void OnPluginEnd() {
	delete weaponMaxClipSizes;
	delete g_ammoPacks;
	L4D2_ExecVScriptCode(HUD_SCRIPT_CLEAR);
	_UnsetCommonLimit();
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
void Cvar_HudStateChange(ConVar convar, const char[] oldValue, const char[] newValue) {
	hudModeTicks = 0;
	showHudPingMode = false;
	for(int i = 0; i <= MaxClients; i++) {
		playerData[i].ResetScroll();
	}
	if(convar.IntValue == 0) {
		if(updateHudTimer != null) {
			PrintToServer("[EPI] Stopping timer externally: Cvar changed to 0");
			delete updateHudTimer;
		}
	} else {
		TryStartHud();
	}
}
void Cvar_CommonScaleChange(ConVar convar, const char[] oldValue, const char[] newValue) {
	if(convar == cvZCommonLimit) {
		PrintToServer("z_common_limit changed [value=%d] [isSettingLimit=%b]", convar.IntValue, isSettingLimit);
		// Ignore our own changes:
		if(isSettingLimit) {
			isSettingLimit = false;
			return;
		}
		commonLimitBase = convar.IntValue;
	}
	_SetCommonLimit();
	
}
void TryStartHud() {
	int threshold = 0;
	// Default to 0 for state == 2 (force)
	if(hEPIHudState.IntValue == 1) {
		// On L4D1 map start if 5 players, on L4D2 start with 6
		// On L4D1 more chance of duplicate models, so can't see health
		threshold = L4D2_GetSurvivorSetMap() == 2 ? 4 : 5;
	}
	if(g_realSurvivorCount > threshold && updateHudTimer == null) {
		PrintToServer("[EPI] Creating new hud timer");
		updateHudTimer = CreateTimer(EXTRA_PLAYER_HUD_UPDATE_INTERVAL, Timer_UpdateHud, _, TIMER_REPEAT);
	}
}

public void Event_GamemodeChange(ConVar cvar, const char[] oldValue, const char[] newValue) {
	cvar.GetString(g_currentGamemode, sizeof(g_currentGamemode));
	g_isGamemodeAllowed = IsGamemodeAllowed();
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
	g_ffFactorCvar = GetActiveFriendlyFireFactor();
	SetFFFactor(false);
}

/////////////////////////////////////
/// COMMANDS
////////////////////////////////////
public void ValBool(int client, const char[] name, bool &value, const char[] input) {
	if(input[0] != '\0') {
		value = input[0] == '1' || input[0] == 't';
		CReplyToCommand(client, "Set {olive}%s{default} to {yellow}%b", name, value);
	} else {
		CReplyToCommand(client, "Value of {olive}%s{default}: {yellow}%b", name, value);
	}
}
public void ValInt(int client, const char[] name, int &value, const char[] input) {
	if(input[0] != '\0') {
		value = StringToInt(input);
		CReplyToCommand(client, "Set {olive}%s{default} to {yellow}%d", name, value);
	} else {
		CReplyToCommand(client, "Value of {olive}%s{default}: {yellow}%d", name, value);
	}
}
public void ValFloat(int client, const char[] name, float &value, const char[] input) {
	if(input[0] != '\0') {
		value = StringToFloat(input);
		CReplyToCommand(client, "Set {olive}%s{default} to {yellow}%f", name, value);
	} else {
		CReplyToCommand(client, "Value of {olive}%s{default}: {yellow}%f", name, value);
	}
}
Action Command_EpiVal(int client, int args) {
	if(args == 0) {
		PrintToConsole(client, "epiEnabled = %b", g_epiEnabled);
		PrintToConsole(client, "isGamemodeAllowed = %b", g_isGamemodeAllowed);
		PrintToConsole(client, "isOfficialMap = %b", g_isOfficialMap);
		PrintToConsole(client, "extraKitsAmount = %d", g_extraKitsAmount);
		PrintToConsole(client, "extraKitsStart = %d", g_extraKitsStart);
		PrintToConsole(client, "currentChapter = %d", g_currentChapter);
		PrintToConsole(client, "extraWitchCount = %d", g_extraWitchCount);
		PrintToConsole(client, "forcedSurvivorCount = %b", g_forcedSurvivorCount);
		PrintToConsole(client, "survivorCount = %d %s", g_survivorCount, g_forcedSurvivorCount ? "(forced)" : "");
		PrintToConsole(client, "realSurvivorCount = %d", g_realSurvivorCount);
		PrintToConsole(client, "restCount = %d", g_restCount);
		PrintToConsole(client, "extraFinaleTankEnabled = %b", g_extraFinaleTankEnabled);
		PrintToConsole(client, "g_areItemsPopulated = %b", g_areItemsPopulated);
		PrintToConsole(client, "commonLimitBase = %d", commonLimitBase);
		ReplyToCommand(client, "Values printed to console");
		return Plugin_Handled;
	}
	char arg[32], value[32];
	GetCmdArg(1, arg, sizeof(arg));
	GetCmdArg(2, value, sizeof(value));
	if(StrEqual(arg, "epiEnabled")) {
		ValBool(client, "g_epiEnabled", g_epiEnabled, value);
	} else if(StrEqual(arg, "isGamemodeAllowed")) {
		ValBool(client, "g_isGamemodeAllowed", g_isGamemodeAllowed, value);
	} else if(StrEqual(arg, "extraKitsAmount")) {
		ValInt(client, "g_extraKitsAmount", g_extraKitsAmount, value);
	} else if(StrEqual(arg, "extraKitsStart")) {
		ValInt(client, "g_extraKitsStart", g_extraKitsStart, value);
	} else if(StrEqual(arg, "currentChapter")) {
		ValInt(client, "g_currentChapter", g_currentChapter, value);
	} else if(StrEqual(arg, "extraWitchCount")) {
		ValInt(client, "g_extraWitchCount", g_extraWitchCount, value);
	} else if(StrEqual(arg, "restCount")) {
		ValInt(client, "g_restCount", g_restCount, value);
	} else if(StrEqual(arg, "survivorCount")) {
		ValInt(client, "g_survivorCount", g_survivorCount, value);
	} else if(StrEqual(arg, "realSurvivorCount")) {
		ValInt(client, "g_survivorCount", g_survivorCount, value);
	} else if(StrEqual(arg, "forcedSurvivorCount")) {
		ValBool(client, "g_forcedSurvivorCount", g_forcedSurvivorCount, value);
	} else if(StrEqual(arg, "forcedSurvivorCount")) {
		ValBool(client, "g_extraFinaleTankEnabled", g_extraFinaleTankEnabled, value);
	} else {
		ReplyToCommand(client, "Unknown value");
	}
	return Plugin_Handled;
}
Action Command_Trigger(int client, int args) {
	char arg[32];
	GetCmdArg(1, arg, sizeof(arg));
	if(StrEqual(arg, "witches")) {
		InitExtraWitches();
		ReplyToCommand(client, "Extra witches active.");
	} else if(StrEqual(arg, "items")) {
		g_areItemsPopulated = false;
		PopulateItems();
		ReplyToCommand(client, "Items populated.");
	} else if(StrEqual(arg, "kits")) {
		g_extraKitsAmount = 4;
		IncreaseKits(L4D_IsMissionFinalMap());
		ReplyToCommand(client, "Kits spawned. Finale: %b", L4D_IsMissionFinalMap());
	} else if(StrEqual(arg, "addbot")) {
		if(GetFeatureStatus(FeatureType_Native, "NextBotCreatePlayerBotSurvivorBot") != FeatureStatus_Available){
			ReplyToCommand(client, "Unsupported.");
			return Plugin_Handled;
		}
		int bot = CreateSurvivorBot();
		if(IsValidEdict(bot)) {
			ReplyToCommand(client, "Created SurvivorBot: %d", bot);
		}
	} else {
		ReplyToCommand(client, "Unknown trigger");
	}
	return Plugin_Handled;
}
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
	return Plugin_Handled;
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

	if(StrEqual(arg, "full") || StrEqual(arg, "all")) { 
		RestoreInventory(client, inv);
	} else if(StrEqual(arg, "pos")) {
		TeleportEntity(player, inv.location, NULL_VECTOR, NULL_VECTOR);
	} else {
		ReplyToCommand(client, "Syntax: /epi_restore <player> <full/pos/model/items>");
		return Plugin_Handled;
	}
	return Plugin_Handled;
}
// TODO: allow sc <players> <bots> for new sys
int parseSurvivorCount(const char arg[8]) {
	int newCount;
	if(StringToIntEx(arg, newCount) > 0) {
		if(newCount >= 0 && newCount <= MaxClients) {
			return newCount;
		}
	}
	return -1;
}
Action Command_SetSurvivorCount(int client, int args) {
	if(args > 0) {
		char arg[8];
		GetCmdArg(1, arg, sizeof(arg));
		if(arg[0] == 'c') {
			g_forcedSurvivorCount = false;
			ReplyToCommand(client, "Cleared forced survivor count.");
			UpdateSurvivorCount();
			return Plugin_Handled;
		}
		int survivorCount = parseSurvivorCount(arg);
		int oldSurvivorCount = g_survivorCount;
		if(survivorCount == -1) {
			ReplyToCommand(client, "Invalid survivor count. Must be between 0 and %d", MaxClients);
			return Plugin_Handled;
		} else if(args >= 2) {
			GetCmdArg(2, arg, sizeof(arg));
			int realCount = parseSurvivorCount(arg);
			if(realCount == -1 || realCount <= survivorCount) {
				ReplyToCommand(client, "Invalid bot count. Must be between 0 and %d", survivorCount);
				return Plugin_Handled;
			}
			int oldRealCount = g_realSurvivorCount;
			g_realSurvivorCount = realCount;
			ReplyToCommand(client, "Changed real survivor count %d -> %d", oldRealCount, realCount);
		} else {
			// If no real count count, it's the same as survivor count
			g_realSurvivorCount = survivorCount;
		}
		g_survivorCount = survivorCount;
		g_forcedSurvivorCount = true;
		ReplyToCommand(client, "Forced survivor count %d -> %d", oldSurvivorCount, survivorCount);
	} else {
		ReplyToCommand(client, "Survivor Count = %d | Real Survivor Count = %d", g_survivorCount, g_realSurvivorCount);
	}
	return Plugin_Handled;
}

#if defined DEBUG_LEVEL
Action Command_SetKitAmount(int client, int args) {
	char arg[32];
	GetCmdArg(1, arg, sizeof(arg));
	int number = StringToInt(arg);
	if(number > 0 || number == -1) {
		g_extraKitsAmount = number;
		g_extraKitsStart = g_extraKitsAmount;
		ReplyToCommand(client, "Set extra kits amount to %d", number);
	} else {
		ReplyToCommand(client, "Must be a number greater than 0. -1 to disable");
	}
	return Plugin_Handled;
}

Action Command_ToggleDoorLocks(int client, int args) {
	for(int i = MaxClients + 1; i < GetMaxEntities(); i++) {
		if(HasEntProp(i, Prop_Send, "m_bLocked")) {
			int state = GetEntProp(i, Prop_Send, "m_bLocked");
			SetEntProp(i, Prop_Send, "m_bLocked", state > 0 ? 0 : 1);
		}
	}
	return Plugin_Handled;
}

Action Command_GetKitAmount(int client, int args) {
	ReplyToCommand(client, "Extra kits available: %d (%d) | Survivors: %d", g_extraKitsAmount, g_extraKitsStart, g_survivorCount);
	ReplyToCommand(client, "isCheckpointReached %b, g_isLateLoaded %b, firstGiven %b", g_isCheckpointReached, g_isLateLoaded, g_startCampaignGiven);
	return Plugin_Handled;
}
Action Command_Debug(int client, int args) {
	PrintToConsole(client, "g_survivorCount = %d | g_realSurvivorCount = %d", g_survivorCount, g_realSurvivorCount);
	Director_PrintDebug(client);
	return Plugin_Handled;
}
Action Command_DebugStats(int client, int args) {
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
	}
	return Plugin_Handled;
}
#endif
/////////////////////////////////////
/// EVENTS
////////////////////////////////////
void OnTakeDamageAlivePost(int victim, int attacker, int inflictor, float damage, int damagetype) {
	if(victim <= MaxClients && attacker <= MaxClients && attacker > 0 && GetClientTeam(victim) == 2 && !IsFakeClient(victim))
		QueueSaveInventory(attacker);
}
void Event_PlayerToIdle(Event event, const char[] name, bool dontBroadcast) {
	int bot = GetClientOfUserId(event.GetInt("bot"));
	int client = GetClientOfUserId(event.GetInt("player"));
	if(GetClientTeam(client) != 2) return;
	PrintToServer("%N -> idle %N", client, bot);
}
void Event_PlayerFromIdle(Event event, const char[] name, bool dontBroadcast) {
	int bot = GetClientOfUserId(event.GetInt("bot"));
	int client = GetClientOfUserId(event.GetInt("player"));
	if(GetClientTeam(client) != 2) return;
	playerData[client].returnedIdleTime = GetGameTime();
	PrintToServer("idle %N -> idle %N", bot, client);
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
void Event_GameStart(Event event, const char[] name, bool dontBroadcast) {
	g_startCampaignGiven = false;
	g_extraKitsAmount = 0;
	g_extraKitsStart = 0;
	g_realSurvivorCount = 0;
	g_survivorCount = 0;
	hMinPlayers.IntValue = 4;
	g_currentChapter = 0;
	pInv.Clear();
	for(int i = 1; i <= MaxClients; i++) {
		playerData[i].state = State_Empty;
	}
}

// This is only called when a player joins for the first time during an entire campaign, unless they fully disconnect.
// Idle bots also call this as they are created and destroyed on idle/resume
void Event_PlayerFirstSpawn(Event event, const char[] name, bool dontBroadcast) { 
	int userid = event.GetInt("userid");
	int client = GetClientOfUserId(userid);
	if(GetClientTeam(client) != 2) return;
	UpdateSurvivorCount();
	if(IsFakeClient(client)) {
		// Ignore any 'BOT' bots (ABMBot, etc), they are temporarily
		char classname[32];
		GetEntityClassname(client, classname, sizeof(classname));
		if(StrContains(classname, "bot", false) > -1) return;

		// Make new bots invincible for a few seconds, as they spawn on other players. Only applies to a player's bot
		int player = L4D_GetIdlePlayerOfBot(client);
		// TODO: check instead hasJoined but state == state_empty
		if(player > 0 && !playerData[client].hasJoined) {
			playerData[client].hasJoined = true;
			playerData[client].state = State_Pending;
			CreateTimer(1.5, Timer_RemoveInvincibility, userid);
			SDKHook(client, SDKHook_OnTakeDamage, OnInvincibleDamageTaken);
		}
	} else {
		// Is a player

		// Make the (real) player invincible as well:
		CreateTimer(1.5, Timer_RemoveInvincibility, userid);
		SDKHook(client, SDKHook_OnTakeDamage, OnInvincibleDamageTaken);
		SDKHook(client, SDKHook_OnTakeDamageAlivePost, OnTakeDamageAlivePost);

		playerData[client].state = State_Active;
		playerData[client].joinTime = GetTime();

		if(L4D_IsFirstMapInScenario() && !g_startCampaignGiven) {
			// Players are joining the campaign, but not all clients are ready yet. Once a client is ready, we will give the extra players their items
			if(AreAllClientsReady()) {
				g_startCampaignGiven = true;
				if(g_realSurvivorCount > 4) {
					PrintToServer("[EPI] First chapter kits given");
					//Set the initial value ofhMinPlayers
					PopulateItems();	
					CreateTimer(1.0, Timer_GiveKits);
				}
				UnlockDoor(2);
			}
		} else {
			// New client has connected, late on the first chapter or on any other chapter
			// If 5 survivors, then set them up, TP them.
			if(g_realSurvivorCount > 4) {
				CreateTimer(0.2, Timer_SetupNewClient, userid);
			}
		}
	}
}
// This is called everytime a player joins, such as map transitions
void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast) {
	if(!g_isGamemodeAllowed) return;

	int userid = event.GetInt("userid");
	int client = GetClientOfUserId(userid);
	if(GetClientTeam(client) != 2) return;
	UpdateSurvivorCount();
	if(!IsFakeClient(client) && !L4D_IsFirstMapInScenario()) {
		// Start door timeout:
		if(g_saferoomDoorEnt != INVALID_ENT_REFERENCE) {
			CreateTimer(hSaferoomDoorWaitSeconds.FloatValue, Timer_OpenSaferoomDoor, _, TIMER_FLAG_NO_MAPCHANGE);

			if(g_prevPlayerCount > 0) {
				// Open the door if we hit % percent
				float percentIn = float(g_realSurvivorCount) / float(g_prevPlayerCount);
				if(percentIn > hMinPlayersSaferoomDoor.FloatValue)
					UnlockDoor(2);
			} else{
				UnlockDoor(2);
			}
		}
		CreateTimer(0.5, Timer_GiveClientKit, userid);
		SDKHook(client, SDKHook_WeaponEquip, Event_Pickup);
	}
	TryStartHud();
	UpdatePlayerInventory(client);
}

void Event_PlayerDisconnect(Event event, const char[] name, bool dontBroadcast) {
	int userid = event.GetInt("userid");
	int client = GetClientOfUserId(userid);
	if(client > 0 && IsClientInGame(client) && GetClientTeam(client) == 2 && playerData[client].state == State_Active) {
		playerData[client].hasJoined = false;
		playerData[client].state = State_PendingEmpty;
		playerData[client].nameCache[0] = '\0';
		PrintToServer("debug: Player (index %d, uid %d) now pending empty", client, client, userid);
		CreateTimer(cvDropDisconnectTime.FloatValue, Timer_DropSurvivor, client);
		
	}
	if(g_saveTimer[client] != null)
		delete g_saveTimer[client];
}

void Event_LeaveStartArea(Event event, const char[] name, bool dontBroadcast) {
	PopulateItems();
}

void Event_PlayerInfo(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(client && !IsFakeClient(client)) {
		playerData[client].Setup(client);
	}
}

Action Timer_DropSurvivor(Handle h, int client) {
	// Check that they are still pending empty (no one replaced them)
	if(playerData[client].state == State_PendingEmpty) {
		playerData[client].state = State_Empty;
		if(hMinPlayers != null) {
			PrintToServer("[EPI] Dropping survivor %d. hMinPlayers-pre:%d g_survivorCount=%d g_realSurvivorCount=%d", client, hMinPlayers.IntValue, g_survivorCount, g_realSurvivorCount);
			PrintToConsoleAll("[EPI] Dropping survivor %d. hMinPlayers-pre:%d g_survivorCount=%d g_realSurvivorCount=%d", client, hMinPlayers.IntValue, g_survivorCount, g_realSurvivorCount);
			hMinPlayers.IntValue = g_realSurvivorCount;
			if(hMinPlayers.IntValue < 4) {
				hMinPlayers.IntValue = 4;
			}
		}
		DropDroppedInventories();
	}
	return Plugin_Handled;
}

/////////////////////////////////////////
/////// Events
/////////////////////////////////////////

Action Event_Pickup(int client, int weapon) {
	if(g_extraKitsAmount <= 0 || playerData[client].itemGiven || playerData[client].returnedIdleTime < 0.5 ) return Plugin_Continue;
	static char name[32];
	GetEntityClassname(weapon, name, sizeof(name));
	if(StrEqual(name, "weapon_first_aid_kit", true)) {
		// Use extra kit in checkpoints
		if((L4D_IsInFirstCheckpoint(client) || L4D_IsInLastCheckpoint(client))) {
			return UseExtraKit(client) ? Plugin_Handled : Plugin_Continue;
		} else if(L4D_IsMissionFinalMap()) {
			// If kit is in finale zone, then use extra kits here:
			float pos[3];
			GetEntPropVector(weapon, Prop_Data, "m_vecOrigin", pos);
			Address address = L4D_GetNearestNavArea(pos);
			if(address != Address_Null) {
				int attributes = L4D_GetNavArea_SpawnAttributes(address);
				if(attributes & NAV_SPAWN_FINALE) {
					return UseExtraKit(client) ? Plugin_Handled : Plugin_Continue;
				}
			}
		}
	}
	return Plugin_Continue;
}

void Event_ItemPickup(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(client > 0 && GetClientTeam(client) == 2 && !IsFakeClient(client)) {
		if(!g_extraKitsSpawnedFinale && L4D_IsMissionFinalMap(true)) {
			float pos[3];
			GetAbsOrigin(client, pos);
			Address address = L4D_GetNearestNavArea(pos);
			if(address != Address_Null) {
				int attributes = L4D_GetNavArea_SpawnAttributes(address);
				if(attributes & NAV_SPAWN_FINALE) {
					IncreaseKits(true);
				}
			}
		}
		// TODO: trigger increase kits finale on kit pickup
		
		UpdatePlayerInventory(client);
		QueueSaveInventory(client);
	}

}

public Action L4D_OnIsTeamFull(int team, bool &full) {
	if(team == 2 && full) {
		full = false;
		return Plugin_Changed;
	} 
	return Plugin_Continue;
}

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

Action Timer_SetupNewClient(Handle h, int userid) {
	int client = GetClientOfUserId(userid);
	if(client == 0) return Plugin_Handled;
	if(HasSavedInventory(client)) {
		PrintDebug(DEBUG_GENERIC, "%N has existing inventory", client);
		// TODO: restore
	}

	GiveWeapon(client, "weapon_first_aid_kit", 0.1);

	// Iterate all clients and get:
	// a) the client with the lowest intensity
	// b) every survivor's tier2 / tier1 / secondary weapons
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
				// Ignore grenade launcher / m60, not a normal weapon to give
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

			if (!GetEntProp(i, Prop_Send, "m_isHangingFromLedge") && !GetEntProp(client, Prop_Send, "m_isIncapacitated")) {
				float intensity = L4D_GetPlayerIntensity(i);
				if(intensity < lowestIntensity || lowestClient == -1) {
					lowestIntensity = intensity;
					lowestClient = i;
				}
			}
		}
	}

	// Give player any random t2 weapon, if no one has one, fallback to t1. 
	if(tier2Weapons.Length > 0) {
		tier2Weapons.GetString(GetRandomInt(0, tier2Weapons.Length - 1), weaponName, sizeof(weaponName));
		// Format(weaponName, sizeof(weaponName), "weapon_%s", weaponName);
		PrintDebug(DEBUG_SPAWNLOGIC, "Giving new client (%N) tier 2: %s", client, weaponName);
		GiveWeapon(client, weaponName, 0.3, 0);
	} else if(tier1Weapons.Length > 0) {
		// Format(weaponName, sizeof(weaponName), "weapon_%s", TIER1_WEAPONS[GetRandomInt(0, TIER1_WEAPON_COUNT - 1)]);
		tier1Weapons.GetString(GetRandomInt(0, tier1Weapons.Length - 1), weaponName, sizeof(weaponName));
		PrintDebug(DEBUG_SPAWNLOGIC, "Giving new client (%N) tier 1: %s", client, weaponName);
		GiveWeapon(client, weaponName, 0.6, 0);
	}
	PrintDebug(DEBUG_SPAWNLOGIC, "%N: Giving random secondary / %d", client, secondaryWeapons.Length);
	if(secondaryWeapons.Length > 0) {
		secondaryWeapons.GetString(GetRandomInt(0, secondaryWeapons.Length - 1), weaponName, sizeof(weaponName));
		GiveWeapon(client, weaponName, 0.6, 1);
	}

	if(lowestClient > 0) {
		// Gets the nav area of lowest client, and finds a random spot inside
		float pos[3];
		GetClientAbsOrigin(lowestClient, pos);
		int nav = L4D_GetNearestNavArea(pos);
		if(nav > 0) {
			L4D_FindRandomSpot(nav, pos);
		}
		TeleportEntity(client, pos, NULL_VECTOR, NULL_VECTOR);
		// Just incase they _are_ in a wall, let the game check:
		L4D_WarpToValidPositionIfStuck(client);
	}

	delete tier2Weapons;
	delete tier1Weapons;
	delete secondaryWeapons;

	return Plugin_Handled;
}

// Gives a player a weapon, clearing their previous and with a configurable delay to prevent issues
void GiveWeapon(int client, const char[] weaponName, float delay = 0.3, int clearSlot = -1) {
	if(clearSlot > 0) {
		int oldWpn = GetPlayerWeaponSlot(client, clearSlot);
		if(oldWpn != -1) {
			AcceptEntityInput(oldWpn, "Kill");
		}
	}
	DataPack pack;
	CreateDataTimer(delay, Timer_GiveWeapon, pack);
	pack.WriteCell(GetClientUserId(client));
	pack.WriteString(weaponName);
}

Action Timer_GiveWeapon(Handle h, DataPack pack) {
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
// First spawn invincibility:
Action Timer_RemoveInvincibility(Handle h, int userid) {
	int client = GetClientOfUserId(userid);
	if(client > 0) {
		SetEntProp(client, Prop_Send, "m_iHealth", 100); 
		SDKUnhook(client, SDKHook_OnTakeDamage, OnInvincibleDamageTaken);
	}
	return Plugin_Handled;
}
Action OnInvincibleDamageTaken(int victim,  int& attacker, int& inflictor, float& damage, int& damagetype, int& weapon, float damageForce[3], float damagePosition[3]) {
	damage = 0.0;
	return Plugin_Stop;
}
// Gives 5+ kit after saferoom loaded:
Action Timer_GiveClientKit(Handle hdl, int user) {
	int client = GetClientOfUserId(user);
	if(client > 0 && !DoesClientHaveKit(client)) {
		UseExtraKit(client);
	}
	return Plugin_Continue;

}

// Gives start of campaign kits
Action Timer_GiveKits(Handle timer) { 
	GiveStartingKits(); 
	return Plugin_Continue;	
}

int SpawnItem(const char[] itemName, float pos[3], float ang[3] = NULL_VECTOR) {
	static char classname[32];
	Format(classname, sizeof(classname), "weapon_%s", itemName);
	int spawner = CreateEntityByName(classname);
	if(spawner == -1) return -1;
	DispatchKeyValue(spawner, "solid", "6");
	DispatchKeyValue(spawner, "rendermode", "3");
	DispatchKeyValue(spawner, "disableshadows", "1");
	TeleportEntity(spawner, pos, ang, NULL_VECTOR);
	DispatchSpawn(spawner);
	TeleportEntity(spawner, pos, ang, NULL_VECTOR);
	return spawner;
}

void IncreaseKits(bool inFinale) {
	if(inFinale) {
		if(g_extraKitsSpawnedFinale) return;
		g_extraKitsSpawnedFinale = true;
		g_extraKitsAmount = g_realSurvivorCount - 4;
	}
	float pos[3];
	int entity = FindEntityByClassname(-1, "weapon_first_aid_kit_spawn");
	if(entity == INVALID_ENT_REFERENCE) {
		PrintToServer("[EPI] Warn: No kit spawns (weapon_first_aid_kit_spawn) found (inFinale=%b)", inFinale);
		return;
	}
	int count = 0;
	while(g_extraKitsAmount > 0) {
		GetEntPropVector(entity, Prop_Data, "m_vecOrigin", pos);
		bool isValidKit = false;
		if(inFinale) {
			Address address = L4D_GetNearestNavArea(pos);
			if(address != Address_Null) {
				int attributes = L4D_GetNavArea_SpawnAttributes(address);
				if(attributes & NAV_SPAWN_FINALE) {
					isValidKit = true;
				}
			}
		} else {
			// Checkpoint
			isValidKit = L4D_IsPositionInLastCheckpoint(pos);
		}

		if(isValidKit) {
			count++;
			// Give it a little chance to nudge itself
			pos[0] += GetRandomFloat(-8.0, 8.0);
			pos[1] += GetRandomFloat(-8.0, 8.0);
			pos[2] += 0.8;
			SpawnItem("first_aid_kit", pos);
			g_extraKitsAmount--;
		}

		entity = FindEntityByClassname(entity, "weapon_first_aid_kit_spawn");
		// Loop around
		if(entity == INVALID_ENT_REFERENCE) {
			// If we did not find any suitable kits, stop here.
			if(count == 0) {
				PrintToServer("[EPI] Warn: No valid kit spawns (weapon_first_aid_kit_spawn) found (inFinale=%b)", inFinale);
				break;
			}
			entity = FindEntityByClassname(-1, "weapon_first_aid_kit_spawn");
		}
	}
}


char NAV_SPAWN_NAMES[32][] = {
	"EMPTY",
	"STOP_SCAN", // 1 << 1
	"",
	"",
	"",
	"BATTLESTATION", // 1 << 5
	"FINALE", // 1 << 6
	"PLAYER_START",
	"BATTLEFIELD",
	"IGNORE_VISIBILITY",
	"NOT_CLEARABLE",
	"CHECKPOINT", // 1 << 11
	"OBSCURED",
	"NO_MOBS",
	"THREAT",
	"RESCUE_VEHICLE",
	"RESCUE_CLOSET",
	"ESCAPE_ROUTE",
	"DESTROYED_DOOR",
	"NOTHREAT",
	"LYINGDOWN", // 1 << 20
	"",
	"",
	"",
	"COMPASS_NORTH", // 1 << 24
	"COMPASS_NORTHEAST",
	"COMPASS_EAST",
	"COMPASS_EASTSOUTH",
	"COMPASS_SOUTH",
	"COMPASS_SOUTHWEST",
	"COMPASS_WEST",
	"COMPASS_WESTNORTH"
};

void Debug_GetAttributes(int attributes, char[] output, int maxlen) {
	output[0] = '\0';
	for(int i = 0; i < 32; i++) {
		if(attributes & (1 << i)) {
			Format(output, maxlen, "%s %s", output, NAV_SPAWN_NAMES[i]);
		}
	}
}

public void L4D2_OnChangeFinaleStage_Post(int stage) {
	g_finaleState = stage;
	if(stage == 1 && IsEPIActive()) {
		IncreaseKits(true);
	}
}

public void OnMapStart() {
	g_extraKitsSpawnedFinale = false;
	char map[32];
	GetCurrentMap(map, sizeof(map));
	// If map starts with c#m#, 98% an official map
	g_isOfficialMap = map[0] == 'c' && IsCharNumeric(map[1]) && (map[2] == 'm' || map[3] == 'm');
	g_isCheckpointReached = false;
	//If previous round was a failure, restore the amount of kits that were left directly after map transition
	if(g_isFailureRound) {
		g_extraKitsAmount = g_extraKitsStart;
		//give kits if first
		if(L4D_IsFirstMapInScenario() && IsEPIActive()) {
			GiveStartingKits();
		}
		g_isFailureRound = false;
	} else {
		g_currentChapter++;
	}

	if(L4D_IsMissionFinalMap()) {
		// Disable tank split on hard rain finale
		g_extraFinaleTankEnabled = true;
		if(StrEqual(map, "c4m5_milltown_escape") || StrEqual(map, "c14m2_lighthouse")) {
			g_extraFinaleTankEnabled = false;
		}
	}

	//Lock the beginning door
	if(hMinPlayersSaferoomDoor.FloatValue > 0.0) {
		int entity = -1;
		while ((entity = FindEntityByClassname(entity, "prop_door_rotating_checkpoint")) != -1 && entity > MaxClients) {
			bool isLocked = GetEntProp(entity, Prop_Send, "m_bLocked") == 1;
			if(isLocked) {
				g_saferoomDoorEnt = EntIndexToEntRef(entity);
				AcceptEntityInput(entity, "Open");
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

	g_epiTankState = Stage_Inactive;

	L4D2_RunScript(HUD_SCRIPT_CLEAR);
	Director_OnMapStart();
	g_areItemsPopulated = false;

	if(g_isLateLoaded) {
		UpdateSurvivorCount();
		g_isLateLoaded = false;
	}
}

enum WallCheck {
	Wall_North,
	Wall_East,
	Wall_South,
	Wall_West
}
/// TODO: confirm this is correct
float WALL_ANG[4][3] = {
	{0.0,0.0,0.0},
	{0.0,90.0,0.0},
	{0.0,180.0,0.0},
	{0.0,270.0,0.0},
};

float WALL_CHECK_SIZE_MIN[3] = { -20.0, -5.0, -10.0 };
float WALL_CHECK_SIZE_MAX[3] = { 20.0, 5.0, 10.0 };
bool IsWallNearby(const float pos[3], WallCheck wall, float maxDistance = 80.0) {
	float endPos[3];
	GetHorizontalPositionFromOrigin(pos, WALL_ANG[wall], maxDistance, endPos);
	TR_TraceHull(pos, endPos, WALL_CHECK_SIZE_MIN, WALL_CHECK_SIZE_MAX, MASK_SOLID_BRUSHONLY);
	return TR_DidHit();
}


char WEAPON_SPAWN_CLASSNAMES[32][] = {
"weapon_pistol_magnum_spawn","weapon_smg_spawn","weapon_smg_silenced_spawn","weapon_pumpshotgun_spawn","weapon_shotgun_chrome_spawn","weapon_pipe_bomb_spawn","weapon_upgradepack_incendiary_spawn","weapon_upgradepack_explosive_spawn","weapon_adrenaline_spawn","weapon_smg_mp5_spawn","weapon_defibrillator_spawn","weapon_propanetank_spawn","weapon_oxygentank_spawn","weapon_chainsaw_spawn","weapon_gascan_spawn","weapon_ammo_spawn","weapon_sniper_scout_spawn","weapon_hunting_rifle_spawn","weapon_pain_pills_spawn","weapon_rifle_spawn","weapon_rifle_desert_spawn","weapon_sniper_military_spawn","weapon_autoshotgun_spawn","weapon_shotgun_spas_spawn","weapon_first_aid_kit_spawn","weapon_molotov_spawn","weapon_vomitjar_spawn","weapon_rifle_ak47_spawn","weapon_rifle_sg552_spawn","weapon_grenade_launcher_spawn","weapon_sniper_awp_spawn","weapon_rifle_m60_spawn"
};
int TIER_MAXES[] = { 10, 18, 28, 31 };

/**
 * Creates a weapon_*_spawn at position, with a random orientation. If classname not provided, it will be randomly selected
 * @param classname the full classname of weapon to spawn
 * @return returns -1 on error, or entity index
 */
int CreateWeaponSpawn(const float pos[3], const char[] classname = "", int tier = 0) {
	int entity;
	if(classname[0] == '\0') {
		int index = GetRandomInt(0, TIER_MAXES[tier]);
		entity = CreateEntityByName(WEAPON_SPAWN_CLASSNAMES[index]);
	} else {
		entity = CreateEntityByName(classname);
	}
	if(entity == -1) return -1;
	DispatchKeyValueInt(entity, "spawn_without_director", 0);
	DispatchKeyValueInt(entity, "spawnflags", 1);
	DispatchKeyValueInt(entity, "count", 1);
	float ang[3];
	ang[1] = GetRandomFloat(0.0, 360.0);
	TeleportEntity(entity, pos, ang, NULL_VECTOR);
	if(!DispatchSpawn(entity)) return -1;
	return entity;
}

int CreateRandomMeleeSpawn(const float pos[3], const char[] choices = "any") {
	int entity = CreateEntityByName("weapon_melee_spawn");
	if(entity == -1) return -1;
	DispatchKeyValue(entity, "melee_weapon", choices);
	DispatchKeyValueInt(entity, "spawnflags", 1);
	float ang[3];
	ang[1] = GetRandomFloat(0.0, 360.0);
	TeleportEntity(entity, pos, ang, NULL_VECTOR);
	if(!DispatchSpawn(entity)) return -1;
	return entity;
}


public void OnConfigsExecuted() {
	if(hUpdateMinPlayers.BoolValue && hMinPlayers != null) {
		hMinPlayers.IntValue = g_realSurvivorCount;
	}
	_SetCommonLimit();
}

public void OnMapEnd() {
	g_isFinaleEnding = false;
	// Reset the ammo packs, deleting the internal arraylist
	for(int i = 0; i < g_ammoPacks.Length; i++) {
		ArrayList clients = g_ammoPacks.Get(i, AMMOPACK_USERS);
		delete clients;
	}
	g_ammoPacks.Clear();
	// Reset cabinets:
	for(int i = 0; i < sizeof(cabinets); i++) {
		cabinets[i].id = 0;
		for(int b = 0; b < CABINET_ITEM_BLOCKS; b++) {
			cabinets[i].items[b] = 0;
		}
	}
	delete updateHudTimer;
	g_finaleVehicleStartTime = 0;
	Director_OnMapEnd();
}

void Event_FinaleStart(Event event, const char[] name, bool dontBroadcast) {
	g_epiTankState = Stage_Active;
}
public void OnClientSpeaking(int client) {
	g_isSpeaking[client] = true;
}
public void OnClientSpeakingEnd(int client) {
	g_isSpeaking[client] = false;
}

public void EntityOutput_OnStartTouchSaferoom(const char[] output, int caller, int client, float time) {
	if(!g_isCheckpointReached  && client > 0 && client <= MaxClients && IsValidClient(client) && GetClientTeam(client) == 2) {
		g_isCheckpointReached = true;
		UpdateSurvivorCount();
		if(IsEPIActive()) {
			SetExtraKits(g_survivorCount);
			IncreaseKits(false);
			PrintToServer("[EPI] Player entered saferoom. Extra Kits: %d", g_extraKitsAmount);
		}
	}
}

void SetExtraKits(int playerCount) {
	int extraPlayers = playerCount - 4;
	float averageTeamHP = GetAverageHP();
	if(averageTeamHP <= 30.0) extraPlayers += (extraPlayers / 2); //if perm. health < 30, give an extra 4 on top of the extra
	else if(averageTeamHP <= 50.0) extraPlayers += (extraPlayers / 3); //if the team's average health is less than 50 (permament) then give another
	//Chance to get an extra kit (might need to be nerfed or restricted to > 50 HP)
	if(GetRandomFloat() < 0.3 && averageTeamHP <= 80.0) ++extraPlayers;


	g_extraKitsAmount += extraPlayers;
	g_extraKitsStart = g_extraKitsAmount;
}

void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast) {
	if(!g_isFailureRound) g_isFailureRound = true;
	g_areItemsPopulated = false;
}

void Event_MapTransition(Event event, const char[] name, bool dontBroadcast) {
	#if defined DEBUG
	PrintToServer("Map transition | %d Extra Kits", g_extraKitsAmount);
	#endif
	g_isLateLoaded = false;
	g_extraKitsStart = g_extraKitsAmount;
	// Update g_survivorCount, people may have dipped right before transition
	UpdateSurvivorCount();
	g_prevPlayerCount = g_survivorCount;
}

public void OnEntityCreated(int entity, const char[] classname) {
	if(StrEqual(classname, "weapon_pain_pills_spawn") || StrEqual(classname, "weapon_first_aid_kit_spawn")) {
		SDKHook(entity, SDKHook_SpawnPost, Hook_CabinetItemSpawn);
	}else if(StrEqual(classname, "prop_health_cabinet", true)) {
		SDKHook(entity, SDKHook_SpawnPost, Hook_CabinetSpawn);
	}else if (StrEqual(classname, "upgrade_ammo_explosive") || StrEqual(classname, "upgrade_ammo_incendiary")) {
		int index = g_ammoPacks.Push(entity);
		g_ammoPacks.Set(index, new ArrayList(1), AMMOPACK_USERS);
		SDKHook(entity, SDKHook_Use, OnUpgradePackUse);
	}
}

///////////////////////////////////////////////////////////////////////////////
// Hooks
///////////////////////////////////////////////////////////////////////////////

//TODO: Implement extra kit amount to this
//TODO: Possibly check ammo stash and kit (relv. distance). Would fire on Last Stand 2nd .
Action Hook_CabinetItemSpawn(int entity) {
	int cabinet = FindNearestEntityInRange(entity, "prop_health_cabinet", 60.0);
	if(cabinet > 0) {
		int ci = FindCabinetIndex(cabinet);
		//Check for any open block
		for(int block = 0; block < CABINET_ITEM_BLOCKS; block++) {
			int cabEnt = cabinets[ci].items[block];
			PrintDebug(DEBUG_ANY, "cabinet %d spawner %d block %d: %d", cabinet, entity, block, cabEnt);
			if(cabEnt <= 0) {
				cabinets[ci].items[block] = EntIndexToEntRef(entity);
				PrintDebug(DEBUG_SPAWNLOGIC, "Adding spawner %d for cabinet %d block %d", entity, cabinet, block);
				break;
			}
		}
		//If Cabinet is full, spawner can not be a part of cabinet and is ignored. 
	}
	return Plugin_Handled;
}

Action Hook_CabinetSpawn(int entity) {
	for(int i = 0; i < sizeof(cabinets); i++) {
		if(cabinets[i].id == 0) {
			cabinets[i].id = entity;
			break;
		}
	}
	PrintDebug(DEBUG_SPAWNLOGIC, "Adding cabinet %d", entity);
	return Plugin_Handled;
}

Action OnUpgradePackUse(int entity, int activator, int caller, UseType type, float value) {
	if (entity > 2048 || entity <= MaxClients || !IsValidEntity(entity)) return Plugin_Continue;

	int primaryWeapon = GetPlayerWeaponSlot(activator, 0);
	if(IsValidEdict(primaryWeapon) && HasEntProp(primaryWeapon, Prop_Send, "m_upgradeBitVec")) {
		int index = g_ammoPacks.FindValue(entity, AMMOPACK_ENTID);
		if(index == -1) return Plugin_Continue;

		ArrayList clients = g_ammoPacks.Get(index, AMMOPACK_USERS);
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

		if(clients.Length >= g_survivorCount) {
			AcceptEntityInput(entity, "kill");
			delete clients;
			g_ammoPacks.Erase(index);
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

Action Timer_OpenSaferoomDoor(Handle h) {
	UnlockDoor(1);
	return Plugin_Continue;
}

void UnlockDoor(int flag) {
	int entity = EntRefToEntIndex(g_saferoomDoorEnt);
	if(entity > 0) {
		PrintDebug(DEBUG_GENERIC, "Door unlocked, flag %d", flag);
		AcceptEntityInput(entity, "Unlock");
		SetEntProp(entity, Prop_Send, "m_bLocked", 0);
		SDKUnhook(entity, SDKHook_Use, Hook_Use);
		if(hSaferoomDoorAutoOpen.IntValue & flag) {
			AcceptEntityInput(entity, "Open");
		}
		SetVariantString("Unlock");
		AcceptEntityInput(entity, "SetAnimation");
		g_saferoomDoorEnt = INVALID_ENT_REFERENCE;
	}
}

Action Timer_UpdateHud(Handle h) {
	if(hEPIHudState.IntValue == 1 && !g_isGamemodeAllowed) {
		PrintToServer("[EPI] Gamemode not whitelisted, stopping (hudState=%d, g_survivorCount=%d, g_realSurvivorCount=%d)", hEPIHudState.IntValue, g_survivorCount, g_realSurvivorCount);
		L4D2_RunScript(HUD_SCRIPT_CLEAR);
		updateHudTimer = null;
		return Plugin_Stop;
	} 
	// TODO: Turn it off when state == 1
	// int threshold = hEPIHudState.IntValue == 1 ? 4 : 0;
	// if(hEPIHudState.IntValue == 1 && abmExtraCount < threshold) { //||  broke  && abmExtraCount < threshold
	// 	PrintToServer("[EPI] Less than threshold (%d), stopping hud timer (hudState=%d, abmExtraCount=%d)", threshold, hEPIHudState.IntValue, abmExtraCount);
	// 	L4D2_RunScript(HUD_SCRIPT_CLEAR);
	// 	updateHudTimer = null;
	// 	return Plugin_Stop;
	// }

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
		if(IsClientInGame(i) && GetClientTeam(i) == 2) {
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
			// if(g_isSpeaking[i])
			// 	Format(prefix, HUD_NAME_LENGTH, "%s", prefix);

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

void PopulateItems() {
	if(g_areItemsPopulated) return;
	UpdateSurvivorCount();
	PrintToServer("[EPI:TEMP] PopulateItems hasRan=%b finale=%b willRun=%b players=%d", g_areItemsPopulated, L4D_IsMissionFinalMap(true), !g_areItemsPopulated&&IsEPIActive(), g_realSurvivorCount);
	if(!IsEPIActive()) return;

	g_areItemsPopulated = true;

	// if(L4D_IsMissionFinalMap(true)) {
	// 	IncreaseKits(true);
	// }

	//Generic Logic
	float percentage = hExtraItemBasePercentage.FloatValue * (g_survivorCount - 4);
	PrintToServer("[EPI] Populating extra items based on player count (%d-4) | Percentage %.2f%%", g_survivorCount, percentage * 100);
	PrintToConsoleAll("[EPI] Populating extra items based on player count (%d-4) | Percentage %.2f%%", g_survivorCount, percentage * 100);
	char classname[64];
	int affected = 0;

	for(int i = MaxClients + 1; i < 2048; i++) {
		if(IsValidEntity(i)) {
			GetEntityClassname(i, classname, sizeof(classname));
			if(StrContains(classname, "_spawn", true) > -1 
				&& StrContains(classname, "zombie", true) == -1 // not zombie or scavenge
				&& StrContains(classname, "scavenge", true) == -1
				&& HasEntProp(i, Prop_Data, "m_itemCount")
			) {
				int count = GetEntProp(i, Prop_Data, "m_itemCount");
				if(count == 4) {
					// Some item spawns are only for 4 players, so here we set to # of players:
					SetEntProp(i, Prop_Data, "m_itemCount", g_survivorCount);
					++affected;
				} else if(count > 0 && GetURandomFloat() < percentage) {
					SetEntProp(i, Prop_Data, "m_itemCount", ++count);
					++affected;
				}
			}
		}
	}
	PrintDebug(DEBUG_SPAWNLOGIC, "Incremented counts for %d items", affected);

	PopulateItemSpawns();
	PopulateCabinets();
}

int CalculateExtraDefibCount() {
	if(L4D_IsMissionFinalMap()) {
		int maxCount = g_survivorCount - 4;
		if(maxCount < 0) maxCount = 0;

		return DiceRoll(0, maxCount, 2, BIAS_LEFT);
	} else if(g_survivorCount > 4) {
		float chance = float(g_survivorCount) / 64.0;
		return GetRandomFloat() > chance ? 1 : 0;
	} else {
		return 0;
	}
}

void PopulateItemSpawns(int minWalls = 4) {
	ArrayList navs = new ArrayList();
	L4D_GetAllNavAreas(navs);
	navs.Sort(Sort_Random, Sort_Integer);
	float pos[3];
	float percentage = hExtraSpawnBasePercentage.FloatValue * (g_survivorCount - 4);
	int tier;
	// On first chapter, 10% chance to give tier 2
	if(g_currentChapter == 1) tier = GetRandomFloat() < 0.15 ? 1 : 0;
	else tier = DiceRoll(0, 3, 2, BIAS_LEFT);
	int count;

	float mapFlowMax = L4D2Direct_GetMapMaxFlowDistance();
	int maxSpawns = RoundFloat(mapFlowMax / MAX_RANDOM_SPAWNS);
	int defibCount = CalculateExtraDefibCount();
	bool isFinale = L4D_IsMissionFinalMap();
	PrintToServer("[EPI] Populating extra item spawns based on player count (%d-4) | Percentage %.2f%%", g_survivorCount, percentage * 100);
	PrintToServer("[EPI] PopulateItemSpawns: flow[0, %f] tier=%d maxSpawns=%d defibCount=%d", mapFlowMax, tier, maxSpawns, defibCount);

	for(int i = 0; i < navs.Length; i++) {
		Address nav = navs.Get(i);
		int spawnFlags = L4D_GetNavArea_SpawnAttributes(nav);
		int baseFlags = L4D_GetNavArea_AttributeFlags(nav);
		if((!(baseFlags & NAV_BASE_FLOW_BLOCKED)) &&
			!(spawnFlags & (NAV_SPAWN_ESCAPE_ROUTE|NAV_SPAWN_DESTROYED_DOOR|NAV_SPAWN_CHECKPOINT|NAV_SPAWN_NO_MOBS|NAV_SPAWN_STOP_SCAN))) 
		{
			L4D_FindRandomSpot(view_as<int>(nav), pos);
			bool north = IsWallNearby(pos, Wall_North);
			bool east = IsWallNearby(pos, Wall_East);
			bool south = IsWallNearby(pos, Wall_South);
			bool west = IsWallNearby(pos, Wall_West);
			// TODO: collision check (windows like c1m1)
			int wallCount = 0;
			if(north) wallCount++;
			if(east) wallCount++;
			if(south) wallCount++;
			if(west) wallCount++;
			if(wallCount >= minWalls) {
				if(GetURandomFloat() < percentage) {
					int wpn;
					pos[2] += 7.0;
					if(GetURandomFloat() > 0.30) {
						wpn = CreateWeaponSpawn(pos, "", tier);
					} else {
						wpn = CreateRandomMeleeSpawn(pos);
					}
					if(wpn == -1) continue;
					if(++count >= maxSpawns) break;
				} else if(defibCount > 0) {
					if(isFinale) {
						if(spawnFlags & NAV_SPAWN_FINALE) {
							CreateWeaponSpawn(pos, "weapon_defibrilator", tier);
							defibCount--;
						}
					} else {
						CreateWeaponSpawn(pos, "weapon_defibrilator", tier);
						defibCount--;
					}
				}
			}
			
		}
	}
	PrintToServer("[EPI] Spawned %d/%d new item spawns (tier=%d)", count, maxSpawns, tier);
	delete navs;
	// Incase there was no suitable spots, try again:
	minWalls--;
	if(count == 0 && minWalls > 0) {
		PopulateItemSpawns(minWalls);
	}
}

void PopulateCabinets() {
	char classname[64];
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
		int extraAmount = RoundToCeil(float(g_survivorCount) * (float(spawnCount)/4.0) - spawnCount);
		bool hasSpawner;
		while(extraAmount > 0) {
			//FIXME: spawner is sometimes invalid entity. Ref needed?
			for(int block = 0; block < CABINET_ITEM_BLOCKS; block++) {
				if(cabinets[i].items[block] == 0) break;
				spawner = EntRefToEntIndex(cabinets[i].items[block]);
				if(spawner > 0) {
					if(!HasEntProp(spawner, Prop_Data, "m_itemCount")) continue;
					hasSpawner = true;
					count = GetEntProp(spawner, Prop_Data, "m_itemCount") + 1;
					SetEntProp(spawner, Prop_Data, "m_itemCount", count);
					if(--extraAmount == 0) break;
				}
			}
			//Incase cabinet is empty
			if(!hasSpawner) break;
		}
	}
}

/////////////////////////////////////
/// Stocks
////////////////////////////////////
bool IsGamemodeAllowed() {
	char buffer[128];
	cvEPIGamemodes.GetString(buffer, sizeof(buffer));
	return StrContains(buffer, g_currentGamemode, false) > -1;
}

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
// Used for EPI hud
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

Action Timer_SaveInventory(Handle h, int client) {
	if(IsValidClient(client)) {
		// Force save to bypass our timeout
		SaveInventory(client);
	}
	g_saveTimer[client] = null;
	return Plugin_Stop;
}
void QueueSaveInventory(int client) {
	int time = GetTime();
	if(time - playerData[client].joinTime < MIN_JOIN_TIME) return;
	if(g_saveTimer[client] != null) {
		delete g_saveTimer[client];
	}
	g_saveTimer[client] = CreateTimer(INV_SAVE_TIME, Timer_SaveInventory, client);
}
void SaveInventory(int client) {
	if(!IsClientInGame(client) || GetClientTeam(client) != 2) return;
	int time = GetTime();
	PlayerInventory inventory;
	inventory.timestamp = time;
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
		// If slot 1 is melee, get the melee ID
		if(i == 1 && inventory.itemID[i] == WEPID_MELEE) {
			inventory.meleeID = IdentifyMeleeWeapon(weapon);
		}
	}
	if(inventory.itemID[0] != WEPID_NONE)
		inventory.lasers = GetEntProp(weapon, Prop_Send, "m_upgradeBitVec") == 4;
	
	GetClientAuthId(client, AuthId_Steam3, buffer, sizeof(buffer));
	pInv.SetArray(buffer, inventory, sizeof(inventory));
	g_lastInvSave[client] = GetTime();
}

void RestoreInventory(int client, PlayerInventory inventory) {
	PrintToConsoleAll("[debug:RINV] health=%d primaryID=%d secondID=%d throw=%d kit=%d pill=%d surv=%d", inventory.primaryHealth, inventory.itemID[0], inventory.itemID[1], inventory.itemID[2], inventory.itemID[3], inventory.itemID[4], inventory.itemID[5], inventory.survivorType);
	
	if(inventory.model[0] != '\0')
		SetEntityModel(client, inventory.model);
	SetEntProp(client, Prop_Send, "m_survivorCharacter", inventory.survivorType);

	char buffer[32];
	if(inventory.isAlive) {
		SetEntProp(client, Prop_Send, "m_iHealth", inventory.primaryHealth);

		int weapon;
		for(int i = 5; i >= 0; i--) {
			WeaponId id = inventory.itemID[i];
			if(id != WEPID_NONE) {
				if(id == WEPID_MELEE) {
					GetWeaponName(id, buffer, sizeof(buffer));
				} else { 
					GetMeleeWeaponName(inventory.meleeID, buffer, sizeof(buffer));
				}
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

bool HasSavedInventory(int client) {
	char buffer[32];
	GetClientAuthId(client, AuthId_Steam3, buffer, sizeof(buffer));
	return pInv.ContainsKey(buffer);
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

bool IsEPIActive() {
	return g_epiEnabled;
}
bool wasActive;
void UpdateSurvivorCount() {
	#if defined DEBUG_FORCE_PLAYERS
		g_survivorCount = DEBUG_FORCE_PLAYERS;
		g_realSurvivorCount = DEBUG_FORCE_PLAYERS;
		g_epiEnabled = g_realSurvivorCount > 4 && g_isGamemodeAllowed; 
		return;
	#endif
	if(g_forcedSurvivorCount) return; // Don't update if forced
	int countTotal = 0, countReal = 0, countActive = 0;
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2) {
			// Count idle player's bots as well
			if(!IsFakeClient(i) || L4D_GetIdlePlayerOfBot(i) > 0) {
				countReal++;
			}
			// FIXME: counting idle players for a brief tick
			countTotal++;
			if(playerData[i].state == State_Active) {
				countActive++;
			}
		}
	}
	g_survivorCount = countTotal;
	g_realSurvivorCount = countReal;
	// PrintDebug(DEBUG_GENERIC, "UpdateSurvivorCount: total=%d real=%d active=%d", countTotal, countReal, countActive);
	// Temporarily for now use g_realSurvivorCount, as players joining have a brief second where they are 5 players
	
	// 1 = 5+ official
	// 2 = 5+ any map
	// 3 = always on
	bool isActive = g_isGamemodeAllowed;
	if(isActive && cvEPIEnabledMode.IntValue != 3) {
		// Enable only if mode is 2 or is official map AND 5+
		isActive = (g_isOfficialMap || cvEPIEnabledMode.IntValue == 2) && g_realSurvivorCount > 4;
	}
	g_epiEnabled = isActive;
	if(g_epiEnabled && !wasActive) {
		OnEPIActive();
		wasActive = true;
	} else if(wasActive) {
		OnEPIInactive();
	}
	if(isActive) {
		SetFFFactor(g_epiEnabled);
		_SetCommonLimit();
	}
}


void OnEPIActive()  {
	_SetCommonLimit();
}

void OnEPIInactive() {
	_UnsetCommonLimit();
}

void _UnsetCommonLimit() {
	if(commonLimitBase > 0) {
		cvZCommonLimit.IntValue = commonLimitBase;
	}
	commonLimitBase = 0;
}
void _SetCommonLimit() {
	if(!g_epiEnabled || commonLimitBase <= 0) return;
	// TODO: lag check for common limit
	if(cvEPICommonCountScale.IntValue > 0 && commonLimitBase > 0) {
		int newLimit = commonLimitBase + RoundFloat(cvEPICommonCountScale.FloatValue * float(g_realSurvivorCount - 4));
		PrintDebug(DEBUG_INFO, "Setting common scale: %d + (%f * %d) [max=%d] = %d", commonLimitBase, cvEPICommonCountScale.FloatValue, g_realSurvivorCount - 4, cvEPICommonCountScaleMax.IntValue, newLimit);
		if(newLimit > 0) {
			if(newLimit > cvEPICommonCountScaleMax.IntValue) {
				newLimit = cvEPICommonCountScaleMax.IntValue;
			}
			isSettingLimit = true;
			cvZCommonLimit.IntValue = newLimit;
		}
	}
}
void SetFFFactor(bool enabled) {
	static float prevValue;
	// Restore the previous value (we use the value for the calculations of new value)
	if(g_ffFactorCvar == null) return; // Ignore invalid difficulties
	g_ffFactorCvar.FloatValue = prevValue;
	if(enabled) {
		prevValue = g_ffFactorCvar.FloatValue;
		g_ffFactorCvar.FloatValue = g_ffFactorCvar.FloatValue - ((g_realSurvivorCount - 4)  * cvFFDecreaseRate.FloatValue);
		if(g_ffFactorCvar.FloatValue < 0.01) {
			g_ffFactorCvar.FloatValue = 0.01;
		}
	}
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
			} else {
				int item = GivePlayerItem(i, "weapon_first_aid_kit");
				EquipPlayerWeapon(i, item);
			}
		}
	}
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
	if(IsClientConnected(client) && IsClientInGame(client)) {
		char wpn[32];
		if(GetClientWeaponName(client, 3, wpn, sizeof(wpn)))
			return StrEqual(wpn, "weapon_first_aid_kit");
	}
	return false;
}

stock bool UseExtraKit(int client) {
	if(g_extraKitsAmount > 0) {
		playerData[client].itemGiven = true;
		int ent = GivePlayerItem(client, "weapon_first_aid_kit");
		EquipPlayerWeapon(client, ent);
		playerData[client].itemGiven = false;
		if(--g_extraKitsAmount <= 0) {
			g_extraKitsAmount = 0;
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
	if(!client || !IsValidEntity(client)
		|| !IsClientInGame(client)
		|| !IsPlayerAlive(client)
		|| IsClientObserver(client)
	) {
		return -1;
	}
	
	//If the client is not on the survivors team, then just return the normal client health.
	if(GetClientTeam(client) != 2) {
		return GetClientHealth(client);
	}
	
	//First, we get the amount of temporal health the client has
	float buffer = GetEntPropFloat(client, Prop_Send, "m_healthBuffer");
	
	//We declare the permanent and temporal health variables
	float TempHealth;
	int PermHealth = GetClientHealth(client);
	
	//In case the buffer is 0 or less, we set the temporal health as 0, because the client has not used any pills or adrenaline yet
	if(buffer <= 0.0) {
		TempHealth = 0.0;
	} else {
		//In case it is higher than 0, we proceed to calculate the temporl health
		//This is the difference between the time we used the temporal item, and the current time
		float difference = GetGameTime() - GetEntPropFloat(client, Prop_Send, "m_healthBufferTime");
		
		//We get the decay rate from this convar (Note: Adrenaline uses this value)
		float decay = GetConVarFloat(FindConVar("pain_pills_decay_rate"));
		
		//This is a constant we create to determine the amount of health. This is the amount of time it has to pass
		//before 1 Temporal HP is consumed.
		float constant = 1.0 / decay;
		
		//Then we do the calcs
		TempHealth = buffer - (difference / constant);
	}
	
	//If the temporal health resulted less than 0, then it is just 0.
	if(TempHealth < 0.0) {
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

// Get the farthest ahead survivor, but ignoring ignoreTarget
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

Action Timer_Kick(Handle h, int bot) { 
	KickClient(bot);
	return Plugin_Handled;
}

enum DiceBias {
	BIAS_LEFT = -1,
	BIAS_RIGHT = 1
}
int DiceRoll(int min, int max, int dices = 2, DiceBias bias) {
	int compValue = -1;
	for(int i = 0; i < dices; i++) {
		int value = RoundToFloor(GetURandomFloat() * (max - min) + min);
		if(bias == BIAS_LEFT) {
			if(value < compValue || compValue == -1) {
				compValue = value;
			}
		} else {
			if(value > compValue || compValue == -1) {
				compValue = value;
			}
		}
	}
	return compValue;
}