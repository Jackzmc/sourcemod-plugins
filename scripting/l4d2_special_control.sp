#pragma semicolon 1
#pragma newdecls required

#define DEBUG 1

#define PLUGIN_VERSION "1.0"

#include <sourcemod>
#include <sdktools>
#include <left4dhooks>
//#include <sdkhooks>

#define SPECIAL_COUNT 8

char SPECIAL_NAMES[SPECIAL_COUNT][] = {
    "Smoker", "Boomer", "Hunter", "Spitter", "Jockey", "Charger", "Witch", "Tank"
};


enum SpecialSpawnType {
    SpawnType_Vanilla,
    SpawnType_GroupsOf4,
    SpawnType_Constant
}

enum SpecialType {
	Special_Invalid = -1,
	Special_Smoker = 1,
	Special_Boomer,
	Special_Hunter,
	Special_Spitter,
	Special_Jockey,
	Special_Charger,
	Special_Witch,
	Special_Tank
}


// Changeable settings
#define MIN_SPAWN_DURATION 200

public Plugin myinfo = 
{
	name =  "L4D2 Special Control", 
	author = "jackzmc", 
	description = "", 
	version = PLUGIN_VERSION, 
	url = ""
};

ConVar cvar_MinPlayersNeeded, cvar_SpawnMode;

int extraSpecialCount = 1; // 4 + X

float specialTimers[SPECIAL_COUNT];

public void OnPluginStart() {
	EngineVersion g_Game = GetEngineVersion();
	if(g_Game != Engine_Left4Dead && g_Game != Engine_Left4Dead2) {
		SetFailState("This plugin is for L4D/L4D2 only.");	
	}

    cvar_MinPlayersNeeded = CreateConVar("l4d_spc_minplayers", "5", "Minimum number of players needed to enable special control.", FCVAR_NONE, true, 1.0);
    cvar_SpawnMode = CreateConVar("l4d_spc_spawn_mode", "0", "Controls how the specials will be spawned.\n0 = Vanilla Timing, 1 = ", FCVAR_NONE, true, 1.0);

    CreateTimer(30.0, SpawnTimer, _, TIMER_REPEAT);
    CreateTimer(1.0, DebugTimer, _, TIMER_REPEAT);
}

public Action DebugTimer(Handle h) {
    static char buffer[512];
    static bool a;
    int start = a ? 5 : 1;
    int end = a ? 7 : 4; 
    buffer[0] = '\0';
    for(int i = 1; i < 6; i++) {
        Format(buffer, sizeof(buffer), "%s\n%s: %f (raw %.0f)", buffer, SPECIAL_NAMES[i], specialTimers[i], GetGameTime() - specialTimers[i]);
    }
    a = !a;
    PrintCenterTextAll(buffer);
    return Plugin_Continue;
}

public Action SpawnTimer(Handle h) {
    SpecialType special = GetNextPendingSpecial();
    if(special != Special_Invalid) {
        int victim = FindSuitableVictim();
        specialTimers[view_as<int>(special) - 1] = GetGameTime();
        SpawnAutoSpecialOnPlayer(special, victim);
    }
    return Plugin_Continue;
}

int FindSuitableVictim() {
    float distance;
    int victim = -1;
    for(int i = 1; i <= MaxClients; i++) {
        if(IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i)) {
            if(GetRandomFloat() < 0.1) continue; //10% to skip
            float flow = L4D2Direct_GetFlowDistance(i);
            if(flow > distance || victim == -1) {
                flow = distance;
                victim = i;
            }
        }
    }
    Debug("Found victim: %N (flow %f)", victim, distance);
    return victim;
}

SpecialType GetNextPendingSpecial() {
    float time = GetGameTime();
    int specialId = -1;
    float spTime;
    for(int i = 1; i < SPECIAL_COUNT; i++) {
        if(time - specialTimers[i] > MIN_SPAWN_DURATION && (specialTimers[i] < spTime || specialId == -1)) {
            specialId = i;
            spTime = specialTimers[i];
        }
    }
    Debug("Found next special: %s (rel %f)", SPECIAL_NAMES[specialId-1], GetGameTime() - spTime);
    return view_as<SpecialType>(specialId);
}


public void SpawnAutoSpecialOnPlayer(SpecialType type, int target) {
    int bot = CreateFakeClient("SpecialControlBot");
    if (bot != 0) {
        ChangeClientTeam(bot, 3);
        CreateTimer(0.1, Timer_KickBot, bot);
    }
    int index = view_as<int>(type) - 1;
    Debug("Spawning special %s on %N", SPECIAL_NAMES[index], target);
    CheatCommand(target, "z_spawn_old", SPECIAL_NAMES[index], "auto");
}

stock Action Timer_KickBot(Handle timer, int client) {
	if (IsClientInGame(client) && (!IsClientInKickQueue(client))) {
		if (IsFakeClient(client)) KickClient(client);
	}
}

stock void CheatCommand(int client, const char[] command, const char[] argument1, const char[] argument2) {
	int userFlags = GetUserFlagBits(client);
	SetUserFlagBits(client, ADMFLAG_ROOT);
	int flags = GetCommandFlags(command);
	SetCommandFlags(command, flags & ~FCVAR_CHEAT);
	FakeClientCommand(client, "%s %s %s", command, argument1, argument2);
	SetCommandFlags(command, flags);
	SetUserFlagBits(client, userFlags);
} 


stock void Debug(const char[] format, any ...) {
    #if defined DEBUG
	char buffer[192];
	
	VFormat(buffer, sizeof(buffer), format, 2);
	
	PrintToServer("[SpecialControl] %s", buffer);
	PrintToConsoleAll("[SpecialControl] %s", buffer);
	
    #endif
}