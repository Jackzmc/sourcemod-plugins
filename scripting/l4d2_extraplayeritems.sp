#pragma semicolon 1
#pragma newdecls required

//#define DEBUG

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

static ConVar hExtraItemBasePercentage;
static int extraKitsAmount = -1, totalSurvivorCount, isFailureRound;

/*
on first start: Everyone has a kit, new comers also get a kit.
then when you reach the saferoom, extraKitsAmount is set to the amount of players minus 4. Ex: 5 players -> 1 extra kit
Then on heal at the point, you get an extra kit. After a map transition when a player_spawn is fired, if they do not have a kit; give an extra kit if there is any.
Any left over kits will be used on heals until depleted. 
*/

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

	hExtraItemBasePercentage = CreateConVar("l4d2_extraitem_chance", "0.056", "The base chance (multiplied by player count) of an extra item being spawned.", FCVAR_NONE, true, 0.0, true, 1.0);

	AutoExecConfig(true, "l4d2_extraplayeritems");
}

/////////////////////////////////////
/// EVENTS
////////////////////////////////////

//Called on the first spawn in a mission. 
bool startingKitsGiven = false;
public Action Event_PlayerFirstSpawn(Event event, const char[] name, bool dontBroadcast) { 
	if(L4D_IsFirstMapInScenario() && !startingKitsGiven) {
		CreateTimer(0.5, Timer_GiveStartingKits);
	}
}
public Action Timer_GiveStartingKits(Handle hdl) {
	for(int i = 1; i < MaxClients + 1; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == 2){
			if(!DoesClientHaveKit(i)) {
				CheatCommand(i, "give", "first_aid_kit", "");
			} 
		}
	}
}

//Provide extra kits when a player spawns (aka after a map transition)
public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(GetClientTeam(client) == 2 && extraKitsAmount > 0) {
		if(!DoesClientHaveKit(client)) {
			CheatCommand(client, "give", "first_aid_kit", "");
			extraKitsAmount--;
			if(extraKitsAmount == 0) {
				extraKitsAmount = -1;
			}
		} 
	}
}

//TODO: Possibly switch to game_init or game_newmap ?
public void OnMapStart() {
	//If it is the first map, reset count as this is before any players. Needs to ignore after a round_end
	if(L4D_IsFirstMapInScenario()) {
		if(isFailureRound) 
			isFailureRound = false;
		else {
			totalSurvivorCount = 0;
			startingKitsGiven = false;
		}
	}

	if(totalSurvivorCount > 4 && GetEntityCount() < MAX_ENTITY_LIMIT)
		CreateTimer(20.0, Timer_AddExtraCounts);
}

public void Event_EnterSaferoom(Event event, const char[] name, bool dontBroadcast) {
	
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(client > 0) {
		if(extraKitsAmount == -1 && L4D_IsInLastCheckpoint(client)) {
			int survivors = GetSurvivorsCount();
			if(survivors > 4) {
				extraKitsAmount = survivors - 4;
				PrintToServer("Player entered saferoom. An extra %d kits will be provided", extraKitsAmount);
			}
		}
	}
}

public Action Event_RoundEnd(Event event, const char[] name, bool dontBroadcast) {
	if(!isFailureRound) isFailureRound = true;
}


public Action Event_HealFinished(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	//if statement 
	if(extraKitsAmount > 0) {
		CheatCommand(client, "give", "first_aid_kit", "");
		extraKitsAmount--;
		if(extraKitsAmount == 0) {
			extraKitsAmount = -1;
		}
	}
}



/////////////////////////////////////
/// TIMERS
////////////////////////////////////

public Action Timer_AddExtraCounts(Handle hd) {
	float percentage = hExtraItemBasePercentage.FloatValue * totalSurvivorCount;
	PrintToServer("Populating extra items based on player count (%d) | Percentage %d", totalSurvivorCount, percentage);
	char classname[32];
	int entityCount = GetEntityCount();
	for(int i = MaxClients + 1; i < 2048; i++) {
		if(IsValidEntity(i) && entityCount < MAX_ENTITY_LIMIT) {
			GetEntityClassname(i, classname, sizeof(classname));
			if(StrContains(classname, "_spawn", true) > -1 && !StrEqual(classname, "info_zombie_spawn", true)) {
				if(StrEqual(classname, "weapon_melee_spawn")) {

				}
				int count = GetEntProp(i, Prop_Data, "m_itemCount");
				if(GetRandomFloat() < percentage) {
					PrintToServer("Debug: Incrementing spawn count for %s from %d", classname, count);
					SetEntProp(i, Prop_Data, "m_itemCount", ++count);
				}
				entityCount++;
			}
		}
	}
}

/////////////////////////////////////
/// Stocks
////////////////////////////////////

stock int GetSurvivorsCount() {
	int count = 0;
	for(int i = 1; i < MaxClients + 1; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2) {
			count++;
		}
	}
	return count;
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