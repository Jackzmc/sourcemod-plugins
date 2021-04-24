#pragma semicolon 1
#pragma newdecls required

//#define DEBUG 1

#define PLUGIN_VERSION "1.0"

#include <sourcemod>
#include <sdktools>
#include <left4dhooks>

public ConVar hExtraChance, hExtraCount;

public Plugin myinfo = 
{
	name =  "L4D2 Extra Finale Tanks", 
	author = "jackzmc", 
	description = "Adds an extra set amount of tanks after the second tank.", 
	version = PLUGIN_VERSION, 
	url = ""
};

public void OnPluginStart()
{
	EngineVersion g_Game = GetEngineVersion();
	if(g_Game != Engine_Left4Dead2)
	{
		SetFailState("This plugin is for L4D2 only.");	
	}
	hExtraChance = CreateConVar("l4d2_eft_chance", "0.0", "The chance that each extra tank should spawn", FCVAR_NONE, true, 0.0, true, 1.0);
	hExtraCount = CreateConVar("l4d2_eft_count", "1.0", "The amount of extra tanks that should spawn", FCVAR_NONE, true, 1.0);

	HookEvent("tank_killed", Event_TankKilled);
	HookEvent("tank_spawn", Event_TankSpawn);

	#if defined DEBUG
		CreateTimer(1.0, Timer_ShowFinale, _, TIMER_REPEAT);
	#endif
}

static int extraTankStage = 0;
static int extraTanksCount = 0;
/* extraTankStage stages:
0 -> normal / reset
1 -> 1 has spawned 
2 -> 2nd spawned
3 -> waiting for extras to spawn
4 -> all extras spawned, waiting on death
*/
public Action L4D2_OnChangeFinaleStage(int &finaleType, const char[] arg) {
	if(hExtraChance.FloatValue == 0.0 || extraTankStage == -1) return Plugin_Continue;
	if(finaleType == 8 && extraTankStage <= 1) {
		extraTankStage++;
		return Plugin_Continue;
	}else if(finaleType == 10 && extraTankStage == 2) {
		finaleType = 8;
		extraTankStage = 3;
		return Plugin_Changed;
	}
	return Plugin_Continue;
}
public Action Event_TankSpawn(Event event, const char[] name, bool dontBroadcast) {
	if(extraTankStage == 3) {
		if(++extraTanksCount <= hExtraCount.IntValue) {
			if(GetRandomFloat() > hExtraChance.FloatValue)
				AcceptEntityInput(event.GetInt("tankid"), "kill");
		}else{
			extraTankStage = 4;
		}
	}else if(extraTankStage == 4) {
		AcceptEntityInput(event.GetInt("tankid"), "kill");
	}
}
public Action Event_TankKilled(Event event, const char[] name, bool dontBroadcast) {
	if(extraTankStage == 4 && --extraTanksCount == 0) {
		L4D2_ForceNextStage();
		extraTankStage = 0;
	}
}
public void OnMapStart() {
	char map[32];
	GetCurrentMap(map, sizeof(map));
	extraTankStage = StrEqual(map, "c14m2_lighthouse") ? -1 : 0;
	extraTanksCount = 0;
}

#if defined DEBUG
public Action Timer_ShowFinale(Handle h) {
	int stage = L4D2_GetCurrentFinaleStage();
	int tanks = L4D2_GetTankCount();
	PrintHintTextToAll("stage=%d tanks=%d tts=%d", stage, tanks, thirdTankStage);
}
#endif