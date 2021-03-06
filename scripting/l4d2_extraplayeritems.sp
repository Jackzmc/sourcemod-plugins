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

static ConVar hExtraItemBasePercentage, hAddExtraKits, hMinPlayers, hUpdateMinPlayers;
static int extraKitsAmount, extraKitsStarted, isFailureRound, abmExtraCount;
static bool isCheckpointReached, isLateLoaded, firstGiven;

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
	if(g_Game != Engine_Left4Dead && g_Game != Engine_Left4Dead2) {
		SetFailState("This plugin is for L4D/L4D2 only.");	
	}
	
	HookEvent("player_spawn", Event_PlayerSpawn);
	HookEvent("player_first_spawn", Event_PlayerFirstSpawn);
	HookEvent("round_end", Event_RoundEnd);
	HookEvent("heal_success", Event_HealFinished);
	HookEvent("map_transition", Event_MapTransition);
	HookEvent("game_start", Event_GameStart);

	hExtraItemBasePercentage = CreateConVar("l4d2_extraitem_chance", "0.056", "The base chance (multiplied by player count) of an extra item being spawned.", FCVAR_NONE, true, 0.0, true, 1.0);
	hAddExtraKits 			 = CreateConVar("l4d2_extraitems_kitmode", "0", "Decides how extra kits should be added.\n0 -> Overwrites previous extra kits, 1 -> Adds onto previous extra kits", FCVAR_NONE, true, 0.0, true, 1.0);
	hUpdateMinPlayers		 = CreateConVar("l4d2_extraitems_updateminplayers", "1", "Should the plugin update abm's cvar min_players convar to the player count?\n 0 -> NO, 1 -> YES", FCVAR_NONE, true, 0.0, true, 1.0);
	if(hUpdateMinPlayers.BoolValue) {
		hMinPlayers = FindConVar("abm_minplayers");
		if(hMinPlayers != null) PrintToServer("Found convar abm_minplayers");
	}

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
	extraKitsAmount = 0;
	extraKitsStarted = 0;
}

public Action Event_PlayerFirstSpawn(Event event, const char[] name, bool dontBroadcast) { 
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(GetClientTeam(client) == 2 && !IsFakeClient(client)) {
		if(L4D_IsFirstMapInScenario()) {
			//Check if all clients are ready, and survivor count is > 4. 
			abmExtraCount = GetSurvivorsCount();
			if(AreAllClientsReady() && abmExtraCount > 4 && !firstGiven) {
				firstGiven = true;
				//Set the initial value ofhMinPlayers
				if(hUpdateMinPlayers.BoolValue && hMinPlayers != null) {
					hMinPlayers.IntValue = abmExtraCount;
				}
				CreateTimer(1.0, Timer_GiveKits);
			}
			//TODO: Some logic to give extra kits on round failure on first map?
			//Give kit if first map and kits given
			if(firstGiven) {
				RequestFrame(Frame_GiveNewClientKit, client);
			}
		}else {
			RequestFrame(Frame_GiveNewClientKit, client);
		}
	}
}

public void Frame_GiveNewClientKit(int client) {
	if(!DoesClientHaveKit(client)) {
		CheatCommand(client, "give", "first_aid_kit", "");
	}
}
public void Frame_GiveClientKit(int client) {
	if(!DoesClientHaveKit(client)) {
		UseExtraKit(client);
	}
	//Set abm's min players to the amount of real survivors. Ran AFTER spawned incase they are pending joining
	if(!hUpdateMinPlayers.BoolValue) return;
	int newPlayerCount = abmExtraCount + 1;
	if(hMinPlayers != null && newPlayerCount > 4 && hMinPlayers.IntValue < newPlayerCount && newPlayerCount < 18) {
		abmExtraCount = newPlayerCount;
		#if defined DEBUG
		PrintToServer("update abm_minplayers -> %d", abmExtraCount);
		#endif
		hMinPlayers.IntValue = abmExtraCount;
	}
}

public Action Timer_GiveKits(Handle timer) { GiveStartingKits(); }

//Provide extra kits when a player spawns (aka after a map transition)
public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(GetClientTeam(client) == 2) {
		RequestFrame(Frame_GiveClientKit, client);
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
		hMinPlayers.IntValue = abmExtraCount;
	}
	if(!isLateLoaded) {
		CreateTimer(30.0, Timer_AddExtraCounts);
		isLateLoaded = false;
	}
	//Hook the end saferoom as event
	HookEntityOutput("info_changelevel", "OnStartTouch", EntityOutput_OnStartTouchSaferoom);
	HookEntityOutput("trigger_changelevel", "OnStartTouch", EntityOutput_OnStartTouchSaferoom);
}
public void EntityOutput_OnStartTouchSaferoom(const char[] output, int caller, int client, float time) {
    if(client > 0 && client <= MaxClients && !isCheckpointReached && IsValidClient(client) && GetClientTeam(client) == 2){
        isCheckpointReached = true;
		int extraPlayers = GetSurvivorsCount() - 4;
		#if defined DEBUG
		PrintToConsoleAll("CHECKPOINT REACHED BY %N | EXTRA KITS: %d", client, extraPlayers);
		#endif

		float averageTeamHP = getAverageHP();
		if(averageTeamHP <= 30) extraPlayers += extraPlayers; //if perm. health < 30, give an extra 4 on top of the extra
		else if(averageTeamHP <= 50) ++extraPlayers; //if the team's average health is less than 50 (permament) then give another
		//Chance to get 1-2 extra kits (might need to be nerfed or restricted to > 50 HP)
		if(GetRandomFloat() < 0.5) ++extraPlayers;
		if(GetRandomFloat() < 0.2) ++extraPlayers;

		if(extraPlayers > 0) {


			//If hAddExtraKits TRUE: Append to previous, FALSE: Overwrite
			if(hAddExtraKits.BoolValue) 
				extraKitsAmount += extraPlayers;
			else
				extraKitsAmount = extraPlayers;
				
			extraKitsStarted = extraKitsAmount;
			PrintToServer(">>> Player entered saferoom. An extra %d kits will be provided", extraKitsAmount);
		}
    }else if(isCheckpointReached) {
		//TODO: Auto give instead on spawn?
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
}

stock int GetSurvivorsCount() {
	int count = 0;
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2 ) {
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

stock float getAverageHP() {
	int totalHP, clients;
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i)) {
			totalHP += GetClientHealth(i);
			++clients;
		}
	}
	return totalHP / clients;
}