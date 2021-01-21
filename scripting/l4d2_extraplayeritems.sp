#pragma semicolon 1
#pragma newdecls required

#define DEBUG

#define PLUGIN_VERSION "1.0"
#define MAX_ENTITY_LIMIT 2000

#include <sourcemod>
#include <sdktools>
#include <left4dhooks>
#include <jutils>
//#include <sdkhooks>

public Plugin myinfo = 
{
	name =  "L4D2 Extra Player Items", 
	author = "jackzmc", 
	description = "Automatic system to give extra players kits, and provide extra items.", 
	version = PLUGIN_VERSION, 
	url = ""
};

static ConVar hExtraItemBasePercentage, hAddExtraKits, hMinPlayers;
static int extraKitsAmount, extraKitsStarted, isFailureRound, abmExtraCount;
static bool isCheckpointReached, isLateLoaded, firstGiven;

/*
on first start: Everyone has a kit, new comers also get a kit.
then when you reach the saferoom, extraKitsAmount is set to the amount of players minus 4. Ex: 5 players -> 1 extra kit
Then on heal at the point, you get an extra kit. After a map transition when a player_spawn is fired, if they do not have a kit; give an extra kit if there is any.
Any left over kits will be used on heals until depleted. 
*/

/*
extra utilities:
Far away player detection (ahead), start countdown if they continue to be farther away then a majority of the group (% based on Surv. count)
	-> probably dynamic array if using % system.
Far away player detection (behind), tell players in chat.
*/
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
	if(late) 
		isLateLoaded = true;
	
} 


public void OnPluginStart()
{
	EngineVersion g_Game = GetEngineVersion();
	if(g_Game != Engine_Left4Dead && g_Game != Engine_Left4Dead2)
	{
		SetFailState("This plugin is for L4D/L4D2 only.");	
	}
	
	HookEvent("player_spawn", Event_PlayerSpawn);
	HookEvent("player_first_spawn", Event_PlayerFirstSpawn);
	HookEvent("round_end", Event_RoundEnd);
	HookEvent("player_entered_checkpoint", Event_EnterSaferoom);
	HookEvent("heal_success", Event_HealFinished);
	HookEvent("map_transition", Event_MapTransition);
	HookEvent("game_start", Event_GameStart);

	hExtraItemBasePercentage = CreateConVar("l4d2_extraitem_chance", "0.056", "The base chance (multiplied by player count) of an extra item being spawned.", FCVAR_NONE, true, 0.0, true, 1.0);
	hAddExtraKits = CreateConVar("l4d2_extraitems_kitmode", "0", "Decides how extra kits should be added. 0 -> Overwrites previous extra kits, 1 -> Adds onto previous extra kits");
	hMinPlayers = FindConVar("abm_minplayers");
	if(hMinPlayers != null) PrintToServer("Found convar abm_minplayers");

	AutoExecConfig(true, "l4d2_extraplayeritems");

	RegAdminCmd("sm_epi_setkits", Command_SetKitAmount, ADMFLAG_CHEATS, "Sets the amount of extra kits that will be provided");
	#if defined DEBUG
		RegAdminCmd("sm_epi_kits", Command_GetKitAmount, ADMFLAG_CHEATS);
		RegAdminCmd("sm_epi_items", Command_RunExtraItems, ADMFLAG_CHEATS);
	#endif
}

/////////////////////////////////////
/// COMMANDS
////////////////////////////////////

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

#if defined DEBUG
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
}

public Action Event_PlayerFirstSpawn(Event event, const char[] name, bool dontBroadcast) { 
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(GetClientTeam(client) == 2) {
		if(L4D_IsFirstMapInScenario()) {
			//Check if all clients are ready, and survivor count is > 4. 
			//TODO: Possibly stop redudant double loops (ready check & survivor count)0
			if(AreAllClientsReady() && GetSurvivorsCount() > 4 && !firstGiven) {
				firstGiven = true;
				CreateTimer(1.0, Timer_GiveKits);
			}
		}else{
			if(!DoesClientHaveKit(client)) {
				CheatCommand(client, "give", "first_aid_kit", "");
			} 
		}
	}
}
public Action Timer_GiveKits(Handle timer) { GiveStartingKits(); }

//Provide extra kits when a player spawns (aka after a map transition)
public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(GetClientTeam(client) == 2) {
		if(!DoesClientHaveKit(client))
			UseExtraKit(client);
		
		int survivors = GetSurvivorsCount();
		if(hMinPlayers != null && hMinPlayers.IntValue < abmExtraCount) {
			#if defined DEBUG
			PrintToServer("update abm_minplayers -> %d", abmExtraCount);
			#endif
			hMinPlayers.IntValue = abmExtraCount;
		}
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
	}
	#if defined DEBUG
	PrintToServer(">>> MAP START. Extra Kits: %d", extraKitsAmount);
	#endif
	if(!isLateLoaded) {
		CreateTimer(30.0, Timer_AddExtraCounts);
		isLateLoaded = false;
	}
}
public void Event_EnterSaferoom(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(client > 0 && !isCheckpointReached && GetClientTeam(client) == 2 && L4D_IsInLastCheckpoint(client)) {
		isCheckpointReached = true;
		int extraPlayers = GetSurvivorsCount() - 4;
		if(extraPlayers > 0) {
			#if defined DEBUG
			PrintToConsoleAll("CHECKPOINT REACHED BY %N | EXTRA KITS: %d", client, extraPlayers);
			#endif
			//If hAddExtraKits TRUE: Append to previous, FALSE: Overwrite
			if(hAddExtraKits.BoolValue) 
				extraKitsAmount += extraPlayers;
			else
				extraKitsAmount = extraPlayers;
			extraKitsStarted = extraKitsAmount;
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
	abmExtraCount = GetSurvivorsCount();
}


public Action Event_HealFinished(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	#if defined DEBUG
	PrintToConsoleAll("Client %N Used Kit (healed). Extras: %d", client, extraKitsAmount);
	#endif
	UseExtraKit(client);
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
	int survivors = GetSurvivorsCount();
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

/////////////////////////////////////
/// Stocks
////////////////////////////////////

stock void GiveStartingKits() {
	int skipLeft = 4, realPlayersCount = 0;
	for(int i = 1; i < MaxClients + 1; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == 2) {
			if(!IsFakeClient(i))
				++realPlayersCount;
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
	//Set abm's min players to the amount of real survivors
	//TODO: Reset on map start when changed
	if(hMinPlayers != null && hMinPlayers.IntValue < realPlayersCount) {
		#if defined DEBUG
		PrintToServer("Found abm_minplayers, setting to %d", realPlayersCount);
		#endif
		hMinPlayers.IntValue = realPlayersCount;
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
	if(GetClientWeaponName(client, 3, wpn, sizeof(wpn))) {
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
		#if defined DEBUG
		PrintToServer("Client %N used extra: %d", client, extraKitsAmount);
		#endif
	}
}