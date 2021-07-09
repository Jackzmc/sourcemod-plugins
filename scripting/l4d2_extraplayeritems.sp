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
#define DEBUG_LEVEL DEBUG_GENERIC
#define EXTRA_PLAYER_HUD_UPDATE_INTERVAL 0.8
//Sets abmExtraCount to this value if set
//#define DEBUG_FORCE_PLAYERS 5

#define PLUGIN_VERSION "1.0"

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <left4dhooks>
#include <l4d_info_editor>
#include <jutils>

#define L4D2_WEPUPGFLAG_NONE            (0 << 0)
#define L4D2_WEPUPGFLAG_INCENDIARY      (1 << 0)
#define L4D2_WEPUPGFLAG_EXPLOSIVE       (1 << 1)
#define L4D2_WEPUPGFLAG_LASER 			(1 << 2)  

#define AMMOPACK_ENTID 0
#define AMMOPACK_USERS 1

#define TANK_CLASS_ID 8

/* 5+ Tank Improvement 
Every X amount of L4D2_OnChooseVictim() calls,
if a player has done < Y amount since last call
Add to a list
Find the closest player in that list & target
*/

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
	url = ""
};

static ConVar hExtraItemBasePercentage, hAddExtraKits, hMinPlayers, hUpdateMinPlayers, hMinPlayersSaferoomDoor, hSaferoomDoorWaitSeconds, hSaferoomDoorAutoOpen, hEPIHudState;
static int extraKitsAmount, extraKitsStarted, abmExtraCount, firstSaferoomDoorEntity, playersLoadedIn, playerstoWaitFor;
static int isBeingGivenKit[MAXPLAYERS+1];
static bool isCheckpointReached, isLateLoaded, firstGiven, isFailureRound;
static ArrayList ammoPacks;
static Handle updateHudTimer;

static StringMap weaponMaxClipSizes;

static char HUD_SCRIPT[] = "ExtraPlayerHUD <- { Fields = { players = { slot = g_ModeScript.HUD_RIGHT_BOT, dataval = \"%s\", flags = g_ModeScript.HUD_FLAG_ALIGN_LEFT | g_ModeScript.HUD_FLAG_TEAM_SURVIVORS | g_ModeScript.HUD_FLAG_NOBG } } }; HUDSetLayout( ExtraPlayerHUD ); HUDPlace( g_ModeScript.HUD_RIGHT_BOT, 0.72, 0.78, 0.3, 0.3 ); g_ModeScript";

#define CABINET_ITEM_BLOCKS 4
enum struct Cabinet {
	int id;
	int items[CABINET_ITEM_BLOCKS];
}

static Cabinet cabinets[10]; //Store 10 cabinets

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
	if(late) isLateLoaded = true;
} 


public void OnPluginStart() {
	EngineVersion g_Game = GetEngineVersion();
	if(g_Game != Engine_Left4Dead2) {
		SetFailState("This plugin is for L4D2 only.");	
	}

	weaponMaxClipSizes = new StringMap();
	ammoPacks = new ArrayList(2); //<int entityID, ArrayList clients>
	
	HookEvent("player_hurt", 		Event_PlayerHurt);
	HookEvent("player_spawn", 		Event_PlayerSpawn);
	HookEvent("player_first_spawn", Event_PlayerFirstSpawn);
	//Tracking player items:
	HookEvent("item_pickup",		Event_ItemPickup);
	HookEvent("weapon_drop",		Event_ItemPickup);

	HookEvent("round_end", 			Event_RoundEnd);
	HookEvent("map_transition", 	Event_MapTransition);
	HookEvent("game_start", 		Event_GameStart);
	HookEvent("round_freeze_end",   Event_RoundFreezeEnd);
	HookEvent("tank_spawn", 		Event_TankSpawn);

	hExtraItemBasePercentage = CreateConVar("l4d2_extraitem_chance", "0.056", "The base chance (multiplied by player count) of an extra item being spawned.", FCVAR_NONE, true, 0.0, true, 1.0);
	hAddExtraKits 			 = CreateConVar("l4d2_extraitems_kitmode", "0", "Decides how extra kits should be added.\n0 -> Overwrites previous extra kits, 1 -> Adds onto previous extra kits", FCVAR_NONE, true, 0.0, true, 1.0);
	hUpdateMinPlayers		 = CreateConVar("l4d2_extraitems_updateminplayers", "1", "Should the plugin update abm\'s cvar min_players convar to the player count?\n 0 -> NO, 1 -> YES", FCVAR_NONE, true, 0.0, true, 1.0);
	hMinPlayersSaferoomDoor  = CreateConVar("l4d2_extraitems_doorunlock_percent", "0.75", "The percent of players that need to be loaded in before saferoom door is opened.\n 0 to disable", FCVAR_NONE, true, 0.0, true, 1.0);
	hSaferoomDoorWaitSeconds = CreateConVar("l4d2_extraitems_doorunlock_wait", "55", "How many seconds after to unlock saferoom door. 0 to disable", FCVAR_NONE, true, 0.0);
	hSaferoomDoorAutoOpen 	 = CreateConVar("l4d2_extraitems_doorunlock_open", "0", "Controls when the door automatically opens after unlocked. Add bits together.\n0 = Never, 1 = When timer expires, 2 = When all players loaded in", FCVAR_NONE, true, 0.0);
	hEPIHudState 			 = CreateConVar("l4d2_extraitems_hudstate", "1", "Controls when the hud displays.\n0 -> OFF, 1 = When 5+ players, 2 = ALWAYS", FCVAR_NONE, true, 0.0, true, 2.0);
	
	hEPIHudState.AddChangeHook(Cvar_HudStateChange);
	
	if(hUpdateMinPlayers.BoolValue) {
		hMinPlayers = FindConVar("abm_minplayers");
		if(hMinPlayers != null) PrintDebug(DEBUG_INFO, "Found convar abm_minplayers");
	}

	if(isLateLoaded) {
		for(int i = 1; i <= MaxClients; i++) {
			if(IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2) {
				GetPlayerInventory(i);
				SDKHook(i, SDKHook_WeaponEquip, Event_Pickup);
			}
		}
		int count = GetRealSurvivorsCount();
		abmExtraCount = count;
		int threshold = hEPIHudState.IntValue == 1 ? 5 : 0;
		if(hEPIHudState.IntValue > 0 && count > threshold && updateHudTimer == null) {
			updateHudTimer = CreateTimer(EXTRA_PLAYER_HUD_UPDATE_INTERVAL, Timer_UpdateHud, _, TIMER_REPEAT);
		}
	}

	#if defined DEBUG_FORCE_PLAYERS 
	abmExtraCount = DEBUG_FORCE_PLAYERS;
	#endif

	AutoExecConfig(true, "l4d2_extraplayeritems");

	#if defined DEBUG_LEVEL
		RegAdminCmd("sm_epi_setkits", Command_SetKitAmount, ADMFLAG_CHEATS, "Sets the amount of extra kits that will be provided");
		RegAdminCmd("sm_epi_lock", Command_ToggleDoorLocks, ADMFLAG_CHEATS, "Toggle all toggle\'s lock state");
		RegAdminCmd("sm_epi_kits", Command_GetKitAmount, ADMFLAG_CHEATS);
		RegAdminCmd("sm_epi_items", Command_RunExtraItems, ADMFLAG_CHEATS);
	#endif

}

public void OnPluginEnd() {
	delete weaponMaxClipSizes;
	delete ammoPacks;
}

///////////////////////////////////////////////////////////////////////////////
// CVAR HOOKS 
///////////////////////////////////////////////////////////////////////////////
public void Cvar_HudStateChange(ConVar convar, const char[] oldValue, const char[] newValue) {
	if(convar.IntValue == 0 && updateHudTimer != null) {
		CloseHandle(updateHudTimer);
		updateHudTimer = null;
	}else {
		int count = GetRealSurvivorsCount();
		int threshold = hEPIHudState.IntValue == 1 ? 5 : 0;
		if(convar.IntValue > 0 && count > threshold && updateHudTimer == null) {
			updateHudTimer = CreateTimer(EXTRA_PLAYER_HUD_UPDATE_INTERVAL, Timer_UpdateHud, _, TIMER_REPEAT);
		}
	}
	
}

/////////////////////////////////////
/// COMMANDS
////////////////////////////////////
#if defined DEBUG_LEVEL
public Action Command_SetKitAmount(int client, int args) {
	char arg[32];
	GetCmdArg(1, arg, sizeof(arg));
	int number = StringToInt(arg);
	if(number > 0 || number == -1) {
		extraKitsAmount = number;
		extraKitsStarted = extraKitsAmount;
		ReplyToCommand(client, "Set extra kits amount to %d", number);
	}else{
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
#endif
/////////////////////////////////////
/// EVENTS
////////////////////////////////////

public void OnGetWeaponsInfo(int pThis, const char[] classname) {
	char clipsize[8];
	InfoEditor_GetString(pThis, "clip_size", clipsize, sizeof(clipsize));

	int maxClipSize = StringToInt(clipsize);
	if(maxClipSize > 0) 
		weaponMaxClipSizes.SetValue(classname, maxClipSize);
}

//Called on the first spawn in a mission. 
public Action Event_GameStart(Event event, const char[] name, bool dontBroadcast) {
	firstGiven = false;
	extraKitsAmount = 0;
	extraKitsStarted = 0;
	abmExtraCount = 4;
	hMinPlayers.IntValue = 4;
}

public Action Event_PlayerFirstSpawn(Event event, const char[] name, bool dontBroadcast) { 
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(GetClientTeam(client) == 2 && !IsFakeClient(client)) {
		if(L4D_IsFirstMapInScenario() && !firstGiven) {
			//Check if all clients are ready, and survivor count is > 4. 
			if(AreAllClientsReady()) {
				abmExtraCount = GetRealSurvivorsCount();
				if(abmExtraCount > 4) {
					firstGiven = true;
					//Set the initial value ofhMinPlayers
					if(hUpdateMinPlayers.BoolValue && hMinPlayers != null) {
						hMinPlayers.IntValue = abmExtraCount;
					}
					PopulateItems();	
					CreateTimer(1.0, Timer_GiveKits);
				}
				if(firstSaferoomDoorEntity > 0 && IsValidEntity(firstSaferoomDoorEntity)) {
					UnlockDoor(firstSaferoomDoorEntity, 2);
				}
			}
		} else {
			RequestFrame(Frame_GiveNewClientKit, client);
			CreateTimer(1.2, Timer_UpdateMinPlayers);
		}
	}
}
public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast) {
	int user = event.GetInt("userid");
	int client = GetClientOfUserId(user);
	if(GetClientTeam(client) == 2) {
		if(!IsFakeClient(client)) {
			if(!L4D_IsFirstMapInScenario()) {
				if(++playersLoadedIn == 1) {
					CreateTimer(hSaferoomDoorWaitSeconds.FloatValue, Timer_OpenSaferoomDoor, _, TIMER_FLAG_NO_MAPCHANGE);
				}
				if(playerstoWaitFor > 0) {
					float percentIn = float(playersLoadedIn) / float(playerstoWaitFor);
					if(firstSaferoomDoorEntity > 0 && percentIn > hMinPlayersSaferoomDoor.FloatValue) {
						UnlockDoor(firstSaferoomDoorEntity, 2);
					}
				}else if(firstSaferoomDoorEntity > 0) {
					UnlockDoor(firstSaferoomDoorEntity, 2);
				}
			}
		}
		CreateTimer(0.5, Timer_GiveClientKit, user);
		SDKHook(client, SDKHook_WeaponEquip, Event_Pickup);
	}
	int count = GetRealSurvivorsCount();
	int threshold = hEPIHudState.IntValue == 1 ? 5 : 0;
	if(hEPIHudState.IntValue > 0 && count > threshold && updateHudTimer == null) {
		updateHudTimer = CreateTimer(EXTRA_PLAYER_HUD_UPDATE_INTERVAL, Timer_UpdateHud, _, TIMER_REPEAT);
	}
	GetPlayerInventory(client);
}

public Action Event_ItemPickup(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(client > 0) {
		GetPlayerInventory(client);
	}
}


public Action L4D_OnIsTeamFull(int team, bool &full) {
	if(team == 2 && full) {
		full = false;
		return Plugin_Continue;
	} 
	return Plugin_Continue;
}

public void Frame_GiveNewClientKit(int client) {
	if(!DoesClientHaveKit(client) && GetRealSurvivorsCount() > 4) {
		int item = GivePlayerItem(client, "weapon_first_aid_kit");
		EquipPlayerWeapon(client, item);
	}
}
public Action Timer_GiveClientKit(Handle hdl, int user) {
	int client = GetClientOfUserId(user);
	if(client > 0 && !DoesClientHaveKit(client)) {
		UseExtraKit(client);
	}
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
}

public Action Timer_GiveKits(Handle timer) { GiveStartingKits(); }

public void OnMapStart() {
	//If previous round was a failure, restore the amount of kits that were left directly after map transition
	if(isFailureRound) {
		extraKitsAmount = extraKitsStarted;
		//give kits if first
		if(L4D_IsFirstMapInScenario()) {
			GiveStartingKits();
		}
		isFailureRound = false;
	}else if(!L4D_IsFirstMapInScenario()) {
		//Re-set value incase it reset.
		//hMinPlayers.IntValue = abmExtraCount;
	}else if(L4D_IsMissionFinalMap()) {
		//Add extra kits for finales
		int extraKits = GetSurvivorsCount() - 4;
		if(extraKits > 0) {
			extraKitsAmount += extraKits;
			extraKitsStarted = extraKitsAmount;
		}
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
				firstSaferoomDoorEntity = entity;
				AcceptEntityInput(firstSaferoomDoorEntity, "Close");
				AcceptEntityInput(firstSaferoomDoorEntity, "Lock");
				AcceptEntityInput(firstSaferoomDoorEntity, "ForceClosed");
				SDKHook(firstSaferoomDoorEntity, SDKHook_Use, Hook_Use);
				break;
			}
		}
		
	}

	//Hook the end saferoom as event
	HookEntityOutput("info_changelevel", "OnStartTouch", EntityOutput_OnStartTouchSaferoom);
	HookEntityOutput("trigger_changelevel", "OnStartTouch", EntityOutput_OnStartTouchSaferoom);

	playersLoadedIn = 0;
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
	L4D2_RunScript("ExtraPlayerHUD  <- { Fields = { } }; HUDSetLayout(ModeHUD); HUDPlace( g_ModeScript.HUD_RIGHT_BOT, 0.72, 0.79, 0.25, 0.2 ); g_ModeScript");
}

public void Event_RoundFreezeEnd(Event event, const char[] name, bool dontBroadcast) {
	CreateTimer(50.0, Timer_Populate);
}
public Action Timer_Populate(Handle h) {
	PopulateItems();	
}

public void EntityOutput_OnStartTouchSaferoom(const char[] output, int caller, int client, float time) {
    if(!isCheckpointReached  && client > 0 && client <= MaxClients && IsValidClient(client) && GetClientTeam(client) == 2) {
		isCheckpointReached = true;
		abmExtraCount = GetSurvivorsCount();
		if(abmExtraCount > 4) {
			int extraPlayers = abmExtraCount - 4;
			float averageTeamHP = GetAverageHP();
			if(averageTeamHP <= 30.0) extraPlayers += extraPlayers; //if perm. health < 30, give an extra 4 on top of the extra
			else if(averageTeamHP <= 50.0) extraPlayers = (extraPlayers / 2); //if the team's average health is less than 50 (permament) then give another
			//Chance to get 1-2 extra kits (might need to be nerfed or restricted to > 50 HP)
			if(GetRandomFloat() < 0.3 && averageTeamHP <= 80.0) ++extraPlayers;


			//If hAddExtraKits TRUE: Append to previous, FALSE: Overwrite
			if(hAddExtraKits.BoolValue) 
				extraKitsAmount += extraPlayers;
			else
				extraKitsAmount = extraPlayers;
				
			extraKitsStarted = extraKitsAmount;
			PrintToConsoleAll("CHECKPOINT REACHED BY %N | EXTRA KITS: %d", client, extraPlayers);
			PrintToServer("Player entered saferoom. Providing %d extra kits", extraKitsAmount);
		}
    }
}

public Action Event_RoundEnd(Event event, const char[] name, bool dontBroadcast) {
	if(!isFailureRound) isFailureRound = true;
}

public Action Event_MapTransition(Event event, const char[] name, bool dontBroadcast) {
	#if defined DEBUG
	PrintToServer("Map transition | %d Extra Kits", extraKitsAmount);
	#endif
	isCheckpointReached = false;
	isLateLoaded = false;
	extraKitsStarted = extraKitsAmount;
	abmExtraCount = GetRealSurvivorsCount();
	playerstoWaitFor = GetRealSurvivorsCount();
}
//TODO: Possibly hacky logic of on third different ent id picked up, in short timespan, detect as set of 4 (pills, kits) & give extra
public Action Event_Pickup(int client, int weapon) {
	char name[32];
	GetEntityClassname(weapon, name, sizeof(name));
	if(StrEqual(name, "weapon_first_aid_kit", true)) {
		if(isBeingGivenKit[client]) return Plugin_Continue;
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

int tankChooseVictimTicks[MAXPLAYERS+1]; //Per tank
int totalTankDamage[MAXPLAYERS+1]; //Per survivor

public Action L4D2_OnChooseVictim(int attacker, int &curTarget) {
	if(abmExtraCount <= 4) return Plugin_Continue;
	int class = GetEntProp(attacker, Prop_Send, "m_zombieClass");
	if(class != TANK_CLASS_ID) return Plugin_Continue;

	//Find a new victim
	if(++tankChooseVictimTicks[attacker] > 200) {
		tankChooseVictimTicks[attacker] = 0;
		ArrayList clients = new ArrayList(2);
		float tankPos[3], clientPos[3];
		GetClientAbsOrigin(attacker, tankPos);

		for(int i = 1; i <= MaxClients; i++) {
			if(IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i)) {
				//If a player does less than 50 damage, and has health add them to list
				if(totalTankDamage[i] < 100 && GetClientHealth(i) > 40) {
					GetClientAbsOrigin(i, clientPos);
					float dist = GetVectorDistance(clientPos, tankPos);
					if(dist <= 5000) {
						PrintDebug(DEBUG_ANY, "Adding player %N to possible victim list. Dist=%f, Dmg=%d", i, dist, totalTankDamage[i]);
						int index = clients.Push(i);
						clients.Set(index, dist, 1);
					}
				}
			}
		}

		if(clients.Length == 0) return Plugin_Continue;

		clients.SortCustom(Sort_TankTargetter);
		/*curTarget = clients.Get(0);*/
		PrintDebug(DEBUG_ANY, "Player Selected to target: %N", curTarget);
		//TODO: Possibly clear totalTankDamage
		delete clients;
		//return Plugin_Changed;
	}
	return Plugin_Continue;
}

int Sort_TankTargetter(int index1, int index2, Handle array, Handle hndl) {
	int client1 = GetArrayCell(array, index1);
	int client2 =GetArrayCell(array, index2);
	float distance1 = GetArrayCell(array, index2, 0);
	float distance2 = GetArrayCell(array, index2, 1);
	/*500 units away, 0 damage vs 600 units away, 0 damage
		-> target closest 500
	  500 units away, 10 damage, vs 600 units away 0 damage
	  500 - 10 = 450 vs 600
	*/
	return (totalTankDamage[client1] + RoundFloat(distance1)) - (totalTankDamage[client2] + RoundFloat(distance2));
}

public void Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast) {
	int victim = GetClientOfUserId(event.GetInt("userid"));
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	int dmg = event.GetInt("dmg_health");
	if(dmg > 0 && attacker > 0 && victim > 0 && IsFakeClient(victim) && GetEntProp(victim, Prop_Send, "m_zombieClass") == TANK_CLASS_ID) {
		if(GetClientTeam(victim) == 3 && GetClientTeam(attacker) == 2) {
			totalTankDamage[victim] += dmg;
		}
	}
}

public void Event_TankSpawn(Event event, const char[] name, bool dontBroadcast) {
	int tank = GetClientOfUserId(GetEventInt(event, "userid"));
	if(tank > 0 && IsFakeClient(tank)) { 
		tankChooseVictimTicks[tank] = -20;
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
}

public Action Hook_CabinetSpawn(int entity) {
	for(int i = 0; i < sizeof(cabinets); i++) {
		if(cabinets[i].id == 0) {
			cabinets[i].id = entity;
			break;
		}
	}
	PrintDebug(DEBUG_SPAWNLOGIC, "Adding cabinet %d", entity);
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

		char classname[32];
		int upgradeBits = GetEntProp(primaryWeapon, Prop_Send, "m_upgradeBitVec"), ammo;

		//Get the new flag bits
		GetEntityClassname(entity, classname, sizeof(classname));
		//SetUsedBySurvivor(activator, entity);
		int newFlags = StrEqual(classname, "upgrade_ammo_explosive") ? L4D2_WEPUPGFLAG_EXPLOSIVE : L4D2_WEPUPGFLAG_INCENDIARY;
		if(upgradeBits & L4D2_WEPUPGFLAG_LASER == L4D2_WEPUPGFLAG_LASER) newFlags |= L4D2_WEPUPGFLAG_LASER; 
		SetEntProp(primaryWeapon, Prop_Send, "m_upgradeBitVec", newFlags);
		GetEntityClassname(primaryWeapon, classname, sizeof(classname));

		if(!weaponMaxClipSizes.GetValue(classname, ammo)) {
			if(StrEqual(classname, "weapon_grenade_launcher", true)) ammo = 1;
			else if(StrEqual(classname, "weapon_rifle_m60", true)) ammo = 150;
			else {
				int currentAmmo = GetEntProp(primaryWeapon, Prop_Send, "m_iClip1");
				if(currentAmmo > 10) ammo = 10;
			}
		}
		//Reset after minute after first pickup
		if(clients.Length == 0) {
			CreateTimer(60.0, Timer_ResetAmmoPack, entity);
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
	if(firstSaferoomDoorEntity > 0)
		UnlockDoor(firstSaferoomDoorEntity, 1);
	return Plugin_Continue;
}

void UnlockDoor(int entity, int flag) {
	PrintDebug(DEBUG_GENERIC, "Door unlocked, flag %d", flag);
	SetEntProp(entity, Prop_Send, "m_bLocked", 0);
	SDKUnhook(entity, SDKHook_Use, Hook_Use);
	if(hSaferoomDoorAutoOpen.IntValue % flag == flag) {
		AcceptEntityInput(entity, "Open");
	}
	firstSaferoomDoorEntity = -1;
	PopulateItems();
}

public Action Timer_UpdateHud(Handle h) {
	int threshold = hEPIHudState.IntValue == 1 ? 4 : 0;
	if(hEPIHudState.IntValue == 0 || abmExtraCount <= threshold) {
		L4D2_RunScript("ExtraPlayerHUD <- { Fields = { } }; HUDSetLayout(ExtraPlayerHUD); HUDPlace( g_ModeScript.HUD_RIGHT_BOT, 0.72, 0.77, 0.25, 0.2); g_ModeScript");
		updateHudTimer = null;
		return Plugin_Stop;
	}
	char players[512];
	char data[32];
	char prefix[16];
	for(int i = 1; i <= MaxClients; i++) { 
		if(IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2) {
			data[0] = '\0';
			prefix[0] = '\0';
			int health = GetClientRealHealth(i);
			if(IsFakeClient(i) && HasEntProp(i, Prop_Send, "m_humanSpectatorUserID")) {
				int client = GetClientOfUserId(GetEntProp(i, Prop_Send, "m_humanSpectatorUserID"));
				if(client > 0) {
					Format(prefix, 13, "IDLE %N", client);
				}else{
					Format(prefix, 8, "%N", i);
				}
			}else{
				Format(prefix, 8, "%N", i);
			}
			//TOOD: Move to bool instead of ent prop
			if(!IsPlayerAlive(i)) 
				Format(data, sizeof(data), "Dead");
			else if(GetEntProp(i, Prop_Send, "m_bIsOnThirdStrike") == 1) 
				Format(data, sizeof(data), "+%d b&&w %s%s%s", health, items[i].throwable, items[i].usable, items[i].consumable);
			else if(GetEntProp(i, Prop_Send, "m_isIncapacitated") == 1) {
				Format(data, sizeof(data), "+%d (down)", health);
			}else{
				Format(data, sizeof(data), "+%d %s%s%s", health, items[i].throwable, items[i].usable, items[i].consumable);
			}
			Format(players, sizeof(players), "%s%s %s\\n", players, prefix, data);
		}
	}
	RunVScriptLong(HUD_SCRIPT, players);
	return Plugin_Continue;
}

///////////////////////////////////////////////////////////////////////////////
// Methods
///////////////////////////////////////////////////////////////////////////////

public void PopulateItems() {
	int survivors = GetRealSurvivorsCount();
	if(survivors <= 4) return;

	//Generic Logic
	float percentage = hExtraItemBasePercentage.FloatValue * survivors;
	PrintToServer("[EPI] Populating extra items based on player count (%d) | Percentage %.2f%%", survivors, percentage * 100);
	PrintToConsoleAll("[EPI] Populating extra items based on player count (%d) | Percentage %.2f%%", survivors, percentage * 100);
	static char classname[32];
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
		if(cabinets[i].id == 0) break;
		int spawnCount = GetEntProp(cabinets[i].id, Prop_Data, "m_pillCount");
		int extraAmount = RoundToCeil(float(abmExtraCount) * (float(spawnCount)/4.0) - spawnCount);
		bool hasASpawner;
		while(extraAmount > 0) {
			//FIXME: spawner is sometimes invalid entity. Ref needed?
			for(int block = 0; block < CABINET_ITEM_BLOCKS; block++) {
				spawner = cabinets[i].items[block];
				if(spawner > 0) {
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
		isBeingGivenKit[client] = true;
		int ent = GivePlayerItem(client, "weapon_first_aid_kit");
		EquipPlayerWeapon(client, ent);
		isBeingGivenKit[client] = false;
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

void GetPlayerInventory(int client) {
	char item[16];
	GetClientWeaponName(client, 2, item, sizeof(item));
	items[client].throwable[0] = CharToUpper(item[7]);
	items[client].throwable[1] = '\0';

	if(GetClientWeaponName(client, 3, item, sizeof(item))) {
		items[client].usable[0] = CharToUpper(item[7]);
		items[client].usable[1] = '\0';
	}

	if(GetClientWeaponName(client, 4, item, sizeof(item))) {
		items[client].consumable[0] = CharToUpper(item[7]);
		items[client].consumable[1] = '\0';
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
	
	static char sBuffer[1024];
	VFormat(sBuffer, sizeof(sBuffer), sCode, 2);
	
	SetVariantString(sBuffer);
	AcceptEntityInput(iScriptLogic, "RunScriptCode");
}