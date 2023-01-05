#pragma semicolon 1
#pragma newdecls required

//#define DEBUG

#define PLUGIN_VERSION "1.0"

#include <sourcemod>
#include <sdktools>
#include <left4dhooks>
//#include <sdkhooks>

public Plugin myinfo = 
{
	name =  "L4D2 Tank Priority", 
	author = "jackzmc", 
	description = "", 
	version = PLUGIN_VERSION, 
	url = "https://gi thub.com/Jackzmc/sourcemod-plugins"
};

#define TANK_CLASS_ID 8

static int tankChooseVictimTicks[MAXPLAYERS+1]; //Per tank
static int tankChosenVictim[MAXPLAYERS+1];
static int targettingTank[MAXPLAYERS+1];
// tankDamage[tank][client]
static int totalTankDamage[MAXPLAYERS+1][MAXPLAYERS+1];
static float highestFlow[MAXPLAYERS+1];
static ArrayList clients;

static bool finaleStarted;

public void OnPluginStart() {
	EngineVersion g_Game = GetEngineVersion();
	if(g_Game != Engine_Left4Dead && g_Game != Engine_Left4Dead2) {
		SetFailState("This plugin is for L4D/L4D2 only.");	
	}

	clients = new ArrayList(3);

	HookEvent("player_hurt", Event_PlayerHurt);
	HookEvent("tank_spawn", Event_TankSpawn);
	HookEvent("tank_killed", Event_TankKilled);
}


public Action L4D2_OnChooseVictim(int attacker, int &curTarget) {
	int class = GetEntProp(attacker, Prop_Send, "m_zombieClass");
	if(class != TANK_CLASS_ID) return Plugin_Continue;

	//Find a new victim
	if(++tankChooseVictimTicks[attacker] >= 200) {
		tankChooseVictimTicks[attacker] = 0;
		clients.Clear();
		static float tankPos[3], clientPos[3];
		GetClientAbsOrigin(attacker, tankPos);

		float tankFlow = L4D2Direct_GetFlowDistance(attacker);

		// TODO: check if player has been set with tankChosenVictim (or make clone var)
		for(int i = 1; i <= MaxClients; i++) {
			if(IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i) && !IsPlayerIncapacitated(i) && !IsFakeClient(i) && targettingTank[curTarget] == 0) {
				//If a player does less than 50 damage, and has green health add them to list
				if(totalTankDamage[attacker][i] < 100 && GetClientHealth(i) > 40) {
					GetClientAbsOrigin(i, clientPos);
					float flow = L4D2Direct_GetFlowDistance(i);
					if(flow > highestFlow[i]) {
						highestFlow[i] = flow;
					} 
					// Ignore far behind players who never reached the tank
					if(highestFlow[i] < tankFlow) continue;
					// float dist = GetVectorDistance(clientPos, tankPos);
					// Only add targets who are far enough away from tank
					// Add targets where their flow difference is greater than 100
					/*
					[TankPriority/debug] Adding player CoCo Nibbz to possible victim list. TankFlow=11057.665039 Flow=10753.859375 Dmg=0
					[TankPriority] Player Selected to target: CoCo Nibbz
					[TankPriority/debug] Adding player CoCo Nibbz to possible victim list. TankFlow=10650.624023 Flow=9850.155273 Dmg=0
					*/
					if(tankFlow - flow > 500.0) {
						PrintToConsoleAll("[TankPriority/debug] Add %N to possible targets. TankFlow=%f Flow=%f HighestFlow=%f Dmg=%d", i, tankFlow, flow, highestFlow[i], totalTankDamage[i]);
						int index = clients.Push(i);
						clients.Set(index, GetVectorDistance(clientPos, tankPos, true), 1);
						clients.Set(index, attacker, 2);
						clients.Set(index, tankFlow - flow, 3);
					}
				}
			}
		}

		if(clients.Length == 0) return Plugin_Continue;

		clients.SortCustom(Sort_TankTargetter);
		curTarget = clients.Get(0);
		tankChosenVictim[attacker] = curTarget;
		targettingTank[curTarget] = attacker;
		PrintToConsoleAll("[TankPriority] Player Selected to target: %N", curTarget);
		//TODO: Possibly clear totalTankDamage
		return Plugin_Changed;
	}
	
	if(tankChosenVictim[attacker] > 0) {
		if(IsClientConnected(tankChosenVictim[attacker]) && IsClientInGame(tankChosenVictim[attacker]) && IsPlayerAlive(tankChosenVictim[attacker]) && !IsPlayerIncapacitated(tankChosenVictim[attacker])) {
			curTarget = tankChosenVictim[attacker];
			return Plugin_Changed;
		} else {
			tankChosenVictim[attacker] = 0;
		}
	}
	return Plugin_Continue;
}

int Sort_TankTargetter(int index1, int index2, Handle array, Handle hndl) {
	int client1 = GetArrayCell(array, index1);
	int client2 = GetArrayCell(array, index2);
	float distance1 = GetArrayCell(array, index1, 1);
	float distance2 = GetArrayCell(array, index2, 1);
	int tankIndex = GetArrayCell(array, index2, 2);
	float flowDiff1 = GetArrayCell(array, index1, 3);
	float flowDiff2 = GetArrayCell(array, index2, 3);
	/*500 units away, 0 damage vs 600 units away, 0 damage
		-> target closest 500
	  500 units away, 10 damage, vs 600 units away 0 damage
	  500 - 10 = 450 vs 600
	*/
	return (totalTankDamage[tankIndex][client1] + RoundFloat(flowDiff1)) - (totalTankDamage[tankIndex][client2] + RoundFloat(flowDiff2));
}

public void Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast) {
	int victim = GetClientOfUserId(event.GetInt("userid"));
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	int dmg = event.GetInt("dmg_health");
	if(dmg > 0 && attacker > 0 && victim > 0 && IsFakeClient(victim) && GetEntProp(victim, Prop_Send, "m_zombieClass") == TANK_CLASS_ID) {
		if(GetClientTeam(victim) == 3 && GetClientTeam(attacker) == 2) {
			totalTankDamage[victim][attacker] += dmg;
		}
	}
}

public void Event_TankSpawn(Event event, const char[] name, bool dontBroadcast) {
	int tank = GetClientOfUserId(GetEventInt(event, "userid"));
	if(tank > 0 && IsFakeClient(tank)) { 
		tankChooseVictimTicks[tank] = -20;
	}
}

public void L4D2_OnChangeFinaleStage_Post(int finaleType, const char[] arg) {
	if(finaleType == 1) {
		finaleStarted = true;
	}
}

public void Event_TankKilled(Event event, const char[] name, bool dontBroadcast) {
	int tank = GetClientOfUserId(GetEventInt(event, "userid"));
	if(tank > 0 && IsFakeClient(tank)) {
		targettingTank[tankChosenVictim[tank]] = 0;
		tankChosenVictim[tank] = 0;
		for(int i = 1; i <= MaxClients; i++) {
			totalTankDamage[tank][i] = 0;
		}
	}
}

bool IsPlayerIncapacitated(int client) {
    return (GetEntProp(client, Prop_Send, "m_isIncapacitated") == 1);
}

public void OnClientDisconnect(int client) {
	tankChosenVictim[client] = 0;
	targettingTank[client] = 0;
	for(int i = 1; i <= MaxClients; i++) {
		if(tankChosenVictim[i] == client) {
			tankChosenVictim[i] = 0;
			targettingTank[i] = 0;
		}
		// If tank:
		totalTankDamage[client][i] = 0;
		// If player:
		totalTankDamage[i][client] = 0;
	}
	highestFlow[client] = 0.0;
}

public void OnMapEnd() {
	finaleStarted = false;
}