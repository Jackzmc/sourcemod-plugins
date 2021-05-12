#pragma semicolon 1
#pragma newdecls required

#define DEBUG 0

#define PLUGIN_VERSION "1.0"
#define MAX_ENTITY_LIMIT 2000

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <left4dhooks>
#include <jutils>
//TODO: On 3rd/4th kit pickup in area, add more
//TODO: Add extra pills too, on pickup
//TODO: Set ammo pack ammo to max primary

#define L4D2_WEPUPGFLAG_NONE            (0 << 0)
#define L4D2_WEPUPGFLAG_INCENDIARY      (1 << 0)
#define L4D2_WEPUPGFLAG_EXPLOSIVE       (1 << 1)
#define L4D2_WEPUPGFLAG_LASER (1 << 2)  

#define AMMOPACK_ENTID 0
#define AMMOPACK_USERS 1

public Plugin myinfo = 
{
	name =  "L4D2 Extra Player Tools", 
	author = "jackzmc", 
	description = "Automatic system for management of 5+ player games. Provides extra kits, items, and more", 
	version = PLUGIN_VERSION, 
	url = ""
};

static ConVar hExtraItemBasePercentage, hAddExtraKits, hMinPlayers, hUpdateMinPlayers, hMinPlayersSaferoomDoor, hSaferoomDoorWaitSeconds, hSaferoomDoorAutoOpen;
static int extraKitsAmount, extraKitsStarted, abmExtraCount, firstSaferoomDoorEntity, playersLoadedIn, playerstoWaitFor;
static int isBeingGivenKit[MAXPLAYERS+1];
static bool isCheckpointReached, isLateLoaded, firstGiven, isFailureRound;
static ArrayList ammoPacks;
static int g_iAmmoTable;

/*
on first start: Everyone has a kit, new comers also get a kit.
then when you reach the saferoom, extraKitsAmount is set to the amount of players minus 4. Ex: 5 players -> 1 extra kit
Then on heal at the point, you get an extra kit. After a map transition when a player_spawn is fired, if they do not have a kit; give an extra kit if there is any.
Any left over kits will be used on heals until depleted. 
*/
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
	if(late) isLateLoaded = true;
} 


public void OnPluginStart() {
	EngineVersion g_Game = GetEngineVersion();
	if(g_Game != Engine_Left4Dead2) {
		SetFailState("This plugin is for L4D/L4D2 only.");	
	}

	//Create an array list that contains <int entityID, ArrayList clients>
	ammoPacks = new ArrayList(2); 
	
	HookEvent("player_spawn", 		Event_PlayerSpawn);
	HookEvent("player_first_spawn", Event_PlayerFirstSpawn);
	HookEvent("round_end", 			Event_RoundEnd);
	//HookEvent("heal_success", 		Event_HealFinished);
	HookEvent("map_transition", 	Event_MapTransition);
	HookEvent("game_start", 		Event_GameStart);

	hExtraItemBasePercentage = CreateConVar("l4d2_extraitem_chance", "0.056", "The base chance (multiplied by player count) of an extra item being spawned.", FCVAR_NONE, true, 0.0, true, 1.0);
	hAddExtraKits 			 = CreateConVar("l4d2_extraitems_kitmode", "0", "Decides how extra kits should be added.\n0 -> Overwrites previous extra kits, 1 -> Adds onto previous extra kits", FCVAR_NONE, true, 0.0, true, 1.0);
	hUpdateMinPlayers		 = CreateConVar("l4d2_extraitems_updateminplayers", "1", "Should the plugin update abm's cvar min_players convar to the player count?\n 0 -> NO, 1 -> YES", FCVAR_NONE, true, 0.0, true, 1.0);
	hMinPlayersSaferoomDoor  = CreateConVar("l4d2_extraitems_doorunlock_percent", "0.75", "The percent of players that need to be loaded in before saferoom door is opened.\n 0 to disable", FCVAR_NONE, true, 0.0, true, 1.0);
	hSaferoomDoorWaitSeconds = CreateConVar("l4d2_extraitems_doorunlock_wait", "35", "How many seconds after to unlock saferoom door. 0 to disable", FCVAR_NONE, true, 0.0);
	hSaferoomDoorAutoOpen 	 = CreateConVar("l4d2_extraitems_doorunlock_open", "0", "Controls when the door automatically opens after unlocked. Add bits together.\n0 = Never, 1 = When timer expires, 2 = When all players loaded in", FCVAR_NONE, true, 0.0);
	
	if(hUpdateMinPlayers.BoolValue) {
		hMinPlayers = FindConVar("abm_minplayers");
		if(hMinPlayers != null) PrintToServer("Found convar abm_minplayers");
	}

	if(isLateLoaded) {
		for(int i = 1; i <= MaxClients; i++) {
			if(IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2)
				SDKHook(i, SDKHook_WeaponEquip, Event_Pickup);
		}
	}

	AutoExecConfig(true, "l4d2_extraplayeritems");

	#if defined DEBUG
		RegAdminCmd("sm_epi_setkits", Command_SetKitAmount, ADMFLAG_CHEATS, "Sets the amount of extra kits that will be provided");
		RegAdminCmd("sm_epi_lock", Command_ToggleDoorLocks, ADMFLAG_CHEATS, "Toggle all toggle's lock state");
		RegAdminCmd("sm_epi_kits", Command_GetKitAmount, ADMFLAG_CHEATS);
		RegAdminCmd("sm_epi_items", Command_RunExtraItems, ADMFLAG_CHEATS);
	#endif


}

/////////////////////////////////////
/// COMMANDS
////////////////////////////////////
#if defined DEBUG
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
	CreateTimer(0.1, Timer_AddExtraCounts);
	return Plugin_Handled;
}
#endif
/////////////////////////////////////
/// EVENTS
////////////////////////////////////

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
		if(L4D_IsFirstMapInScenario()) {
			//Check if all clients are ready, and survivor count is > 4. 
			if(AreAllClientsReady() && !firstGiven) {
				abmExtraCount = GetRealSurvivorsCount();
				if(abmExtraCount > 4) {
					firstGiven = true;
					//Set the initial value ofhMinPlayers
					if(hUpdateMinPlayers.BoolValue && hMinPlayers != null) {
						hMinPlayers.IntValue = abmExtraCount;
					}
					CreateTimer(1.0, Timer_GiveKits);
				}
			}else if(firstGiven) {
				RequestFrame(Frame_GiveNewClientKit, client);
			}
		}else {
			RequestFrame(Frame_GiveNewClientKit, client);
		}
	}
}

public void Frame_GiveNewClientKit(int client) {
	if(!DoesClientHaveKit(client) && GetRealSurvivorsCount() > 4) {
		CheatCommand(client, "give", "first_aid_kit", "");
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
			PrintToServer("update abm_minplayers -> %d", abmExtraCount);
			#endif
			hMinPlayers.IntValue = abmExtraCount;
		}
	}
}

public Action Timer_GiveKits(Handle timer) { GiveStartingKits(); }

//Provide extra kits when a player spawns (aka after a map transition)
public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast) {
	int user = event.GetInt("userid");
	int client = GetClientOfUserId(user);
	if(GetClientTeam(client) == 2) {
		if(!IsFakeClient(client)) {
			if(firstSaferoomDoorEntity > 0 && playerstoWaitFor > 0 && ++playersLoadedIn / playerstoWaitFor > hMinPlayersSaferoomDoor.FloatValue) {
				SetEntProp(firstSaferoomDoorEntity, Prop_Send, "m_bLocked", 0);
				if(hSaferoomDoorAutoOpen.IntValue % 2 == 2) {
					AcceptEntityInput(firstSaferoomDoorEntity, "Open");
				}
				firstSaferoomDoorEntity = -1;
			}
		}
		CreateTimer(0.5, Timer_GiveClientKit, user);
		SDKHook(client, SDKHook_WeaponEquip, Event_Pickup);
	}
}


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
		CreateTimer(30.0, Timer_AddExtraCounts);
		isLateLoaded = false;
	}
	//Hook the end saferoom as event
	HookEntityOutput("info_changelevel", "OnStartTouch", EntityOutput_OnStartTouchSaferoom);
	HookEntityOutput("trigger_changelevel", "OnStartTouch", EntityOutput_OnStartTouchSaferoom);

	//Lock the saferoom door until 80% loaded in: //&& abmExtraCount > 4
	if(hMinPlayersSaferoomDoor.IntValue > 0 ) {
		firstSaferoomDoorEntity = FindEntityByClassname(-1, "prop_door_rotating_checkpoint");
		playersLoadedIn = 0;
		if(firstSaferoomDoorEntity > 0) {
			SetEntProp(firstSaferoomDoorEntity, Prop_Send, "m_bLocked", 1);
			CreateTimer(hSaferoomDoorWaitSeconds.IntValue, Timer_OpenSaferoomDoor);
		}
	}
}
public void OnMapEnd() {
	for(int i = 0; i < ammoPacks.Length; i++) {
		ArrayList clients = ammoPacks.Get(i, AMMOPACK_USERS);
		delete clients;
	}
	ammoPacks.Clear();
}
public void EntityOutput_OnStartTouchSaferoom(const char[] output, int caller, int client, float time) {
    if(!isCheckpointReached  && client > 0 && client <= MaxClients && IsValidClient(client) && GetClientTeam(client) == 2) {
		isCheckpointReached = true;
		int extraPlayers = GetSurvivorsCount() - 4;
		if(extraPlayers > 0) {
			
			float averageTeamHP = GetAverageHP();
			if(averageTeamHP <= 30.0) extraPlayers += extraPlayers; //if perm. health < 30, give an extra 4 on top of the extra
			else if(averageTeamHP <= 50.0) extraPlayers = (extraPlayers / 2); //if the team's average health is less than 50 (permament) then give another
			//Chance to get 1-2 extra kits (might need to be nerfed or restricted to > 50 HP)
			if(GetRandomFloat() < 0.3) ++extraPlayers;


			//If hAddExtraKits TRUE: Append to previous, FALSE: Overwrite
			if(hAddExtraKits.BoolValue) 
				extraKitsAmount += extraPlayers;
			else
				extraKitsAmount = extraPlayers;
				
			extraKitsStarted = extraKitsAmount;
			PrintToConsoleAll("CHECKPOINT REACHED BY %N | EXTRA KITS: %d", client, extraPlayers);
			PrintToServer(">>> Player entered saferoom. An extra %d kits will be provided", extraKitsAmount);
		}
    }
}
public Action Event_RoundEnd(Event event, const char[] name, bool dontBroadcast) {
	if(!isFailureRound) isFailureRound = true;
}
public Action Event_MapTransition(Event event, const char[] name, bool dontBroadcast) {
	isCheckpointReached = false;
	isLateLoaded = false;
	//If any kits were consumed before map transition, decrease from reset-amount (for if a round fails)
	#if defined DEBUG
	PrintToServer("Map transition | Extra Kits Left %d | Starting Amount %d", extraKitsAmount, extraKitsStarted);
	#endif
	extraKitsStarted = extraKitsAmount;
	abmExtraCount = GetRealSurvivorsCount();
	playerstoWaitFor = GetSurvivorsCount();
}
public Action Event_Pickup(int client, int weapon) {

	if(extraKitsAmount > 0) {
		char name[32];
		GetEntityClassname(weapon, name, sizeof(name));
		if(StrEqual(name, "weapon_first_aid_kit", true)) {
			if(isBeingGivenKit[client]) {
				isBeingGivenKit[client] = false;
				return Plugin_Continue;
			}else{
				isBeingGivenKit[client] = true;
				UseExtraKit(client);
				return Plugin_Stop;
			}
		}
	}
	return Plugin_Continue;
}

public void OnEntityCreated(int entity, const char[] classname) {
	if (StrEqual(classname, "upgrade_ammo_explosive") || StrEqual(classname, "upgrade_ammo_incendiary")) {
		int index = ammoPacks.Push(entity);
		ammoPacks.Set(index, new ArrayList(1), AMMOPACK_USERS);
		SDKHook(entity, SDKHook_Use, OnUpgradePackUse);
	}
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
			return Plugin_Stop;
		}

		char classname[32];
		int upgradeBits = GetEntProp(primaryWeapon, Prop_Send, "m_upgradeBitVec"), ammo = 40;

		//Get the new flag bits
		GetEntityClassname(entity, classname, sizeof(classname));
		//SetUsedBySurvivor(activator, entity);
		int newFlags = StrEqual(classname, "upgrade_ammo_explosive") ? L4D2_WEPUPGFLAG_EXPLOSIVE : L4D2_WEPUPGFLAG_INCENDIARY;
		if(upgradeBits & L4D2_WEPUPGFLAG_LASER == L4D2_WEPUPGFLAG_LASER) newFlags |= L4D2_WEPUPGFLAG_LASER; 
		SetEntProp(primaryWeapon, Prop_Send, "m_upgradeBitVec", newFlags);

		GetEntityClassname(primaryWeapon, classname, sizeof(classname));
		if(StrEqual(classname, "weapon_grenade_launcher", true)) ammo = 1;
		else if(StrEqual(classname, "weapon_rifle_m60", true)) ammo = 150;
		else {
			int currentAmmo = GetEntProp(primaryWeapon, Prop_Send, "m_iClip1");
			if(currentAmmo > ammo) ammo = currentAmmo;
		}
		SetEntProp(primaryWeapon, Prop_Send, "m_nUpgradedPrimaryAmmoLoaded", ammo);

		clients.Push(activator);
		ClientCommand(activator, "play player/orch_hit_csharp_short.wav");

		if(clients.Length >= GetSurvivorsCount()) {
			AcceptEntityInput(entity, "kill");
			delete clients;
			ammoPacks.Erase(index);
		}
		return Plugin_Stop;
	}
	return Plugin_Continue;
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
public Action Timer_AddExtraCounts(Handle hd) {
	int survivors = GetRealSurvivorsCount();
	if(survivors <= 4) return;

	float percentage = hExtraItemBasePercentage.FloatValue * survivors;
	PrintToServer("Populating extra items based on player count (%d) | Percentage %f%%", survivors, percentage * 100);
	PrintToConsoleAll("Populating extra items based on player count (%d) | Percentage %f%%", survivors, percentage * 100);
	char classname[32];
	int affected = 0;
	for(int i = MaxClients + 1; i < 2048; i++) {
		if(IsValidEntity(i)) {
			GetEntityClassname(i, classname, sizeof(classname));
			if(StrContains(classname, "_spawn", true) > -1 
				&& StrContains(classname, "zombie", true) == -1
				&& StrContains(classname, "scavenge", true) == -1
			) {
				int count = GetEntProp(i, Prop_Data, "m_itemCount");
				//Add extra kits (equal to player count) to any 4 set of kits.
				if(count == 4 && StrEqual(classname, "weapon_first_aid_kit_spawn", true)) {
					SetEntProp(i, Prop_Data, "m_itemCount", survivors);
					++affected;
				}else if(count > 0 && GetRandomFloat() < percentage) {
					SetEntProp(i, Prop_Data, "m_itemCount", ++count);
					++affected;
				}
			}
		}
	}
	PrintToServer("Incremented counts for %d items", affected);
}

public Action Timer_OpenSaferoomDoor(Handle h) {
	if(firstSaferoomDoorEntity != -1) {
		SetEntProp(firstSaferoomDoorEntity, Prop_Send, "m_bLocked", 0);
		if(hSaferoomDoorAutoOpen.IntValue % 1 == 1) {
			AcceptEntityInput(firstSaferoomDoorEntity, "Open");
		}
		firstSaferoomDoorEntity = -1;
	}
}

/////////////////////////////////////
/// Stocks
////////////////////////////////////

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
				CheatCommand(i, "give", "first_aid_kit", "");
			}
		}
	}
}

stock int GetSurvivorsCount() {
	int count = 0;
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2) {
			++count;
		}
	}
	return count;
}

stock int GetRealSurvivorsCount() {
	int count = 0;
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2) {
			if(IsFakeClient(i) && GetEntProp(i, Prop_Send, "m_humanSpectatorUserID") == 0) continue;
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

stock void UseExtraKit(int client) {
	if(extraKitsAmount > 0) {
		CheatCommand(client, "give", "first_aid_kit", "");
		if(--extraKitsAmount <= 0) {
			extraKitsAmount = 0;
		}
	}
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

void SetUsedBySurvivor(int client, int entity) {
	int usedMask = GetEntProp(entity, Prop_Send, "m_iUsedBySurvivorsMask");
	bool bAlreadyUsed = !(usedMask & (1 << client - 1));
	if (bAlreadyUsed) return;

	int newMask = usedMask | (1 << client - 1);
	SetEntProp(entity, Prop_Send, "m_iUsedBySurvivorsMask", newMask);
}