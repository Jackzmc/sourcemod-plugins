#pragma semicolon 1
#pragma newdecls required

//#define DEBUG

#define PLUGIN_VERSION "1.0"

#include <sourcemod>
#include <sdktools>
//#include <sdkhooks>

public Plugin myinfo = 
{
	name =  "L4D2 Tank Priority", 
	author = "jackzmc", 
	description = "", 
	version = PLUGIN_VERSION, 
	url = ""
};

#define TANK_CLASS_ID 8

static int tankChooseVictimTicks[MAXPLAYERS+1]; //Per tank
static int tankChosenVictim[MAXPLAYERS+1];
static int totalTankDamage[MAXPLAYERS+1]; //Per survivor
static ArrayList clients;

public void OnPluginStart() {
	EngineVersion g_Game = GetEngineVersion();
	if(g_Game != Engine_Left4Dead && g_Game != Engine_Left4Dead2) {
		SetFailState("This plugin is for L4D/L4D2 only.");	
	}

	clients = new ArrayList(2);

	HookEvent("player_hurt", Event_PlayerHurt);
	HookEvent("tank_spawn", Event_TankSpawn);
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

		for(int i = 1; i <= MaxClients; i++) {
			if(IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i) && !IsPlayerIncapacitated(i)) {
				//If a player does less than 50 damage, and has green health add them to list
				if(totalTankDamage[i] < 100 && GetClientHealth(i) > 40) {
					GetClientAbsOrigin(i, clientPos);
					float dist = GetVectorDistance(clientPos, tankPos);
					// Only add targets who are far enough away from tank
					if(dist > 3000.0) {
						PrintToConsoleAll("[TankPriority/debug] Adding player %N to possible victim list. Dist=%f Dmg=%d", i, dist, totalTankDamage[i]);
						int index = clients.Push(i);
						clients.Set(index, dist, 1);
					}
				}
			}
		}

		if(clients.Length == 0) return Plugin_Continue;

		clients.SortCustom(Sort_TankTargetter);
		curTarget = clients.Get(0);
		tankChosenVictim[attacker] = curTarget;
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

bool IsPlayerIncapacitated(int client) {
    return (GetEntProp(client, Prop_Send, "m_isIncapacitated") == 1);
}