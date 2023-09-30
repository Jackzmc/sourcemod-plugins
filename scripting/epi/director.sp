// SETTINGS
#define DIRECTOR_WITCH_MIN_TIME 120 // The minimum amount of time to pass since last witch spawn for the next extra witch to spawn
#define DIRECTOR_WITCH_CHECK_TIME 30.0 // How often to check if a witch should be spawned
#define DIRECTOR_WITCH_MAX_WITCHES 6 // The maximum amount of extra witches to spawn 
#define DIRECTOR_WITCH_ROLLS 2 // The number of dice rolls, increase if you want to increase freq
#define DIRECTOR_MIN_SPAWN_TIME 20.0 // Possibly randomized, per-special
#define DIRECTOR_SPAWN_CHANCE 30.0 // The raw chance of a spawn 
#define DIRECTOR_CHANGE_LIMIT_CHANCE 0.10 // The chance that the maximum amount per-special is changed
#define DIRECTOR_SPECIAL_TANK_CHANCE 0.05 // The chance that specials can spawn when a tank is active
#define DIRECTOR_STRESS_CUTOFF 0.60 // The minimum chance a random cut off stress value is chosen [this, 1.0]

/// DEFINITIONS
#define NUM_SPECIALS 6
#define TOTAL_NUM_SPECIALS 8
char SPECIAL_IDS[TOTAL_NUM_SPECIALS][] = {
	"smoker",
	"boomer",
	"hunter",
	"spitter",
	"jockey",
	"charger",
	"witch",
	"tank"
};
enum specialType {
	Special_Smoker,
	Special_Boomer,
	Special_Hunter,
	Special_Spitter,
	Special_Jockey,
	Special_Charger,
	Special_Witch,
	Special_Tank,
};

static float highestFlowAchieved;
static float g_lastSpawnTime[TOTAL_NUM_SPECIALS];
static int g_spawnLimit[TOTAL_NUM_SPECIALS];
static int g_spawnCount[TOTAL_NUM_SPECIALS];
static float g_minFlowSpawn; // The minimum flow for specials to start spawning (waiting for players to leave saferom)
static float g_minStressIntensity; // The minimum stress that specials arent allowed to spawn

static int extraWitchCount;
static Handle witchSpawnTimer = null;

float g_extraWitchFlowPositions[DIRECTOR_WITCH_MAX_WITCHES] = {};

/// EVENTS

void Director_OnMapStart() {
	if(cvEPISpecialSpawning.BoolValue && abmExtraCount > 4) { 
		InitExtraWitches();
	}
	float time = GetGameTime();
	for(int i = 0; i < TOTAL_NUM_SPECIALS; i++) {
		g_lastSpawnTime[i] = time;
		g_spawnLimit[i] = 1;
		g_spawnCount[i] = 0;
	}
}
void Director_OnMapEnd() {
	for(int i = 0; i <= DIRECTOR_WITCH_MAX_WITCHES; i++) {
		g_extraWitchFlowPositions[i] = 0.0;
	}
	delete witchSpawnTimer;
}

void Cvar_SpecialSpawningChange(ConVar convar, const char[] oldValue, const char[] newValue) {
	if(convar.IntValue & 2 && abmExtraCount > 4) {
		if(witchSpawnTimer == null)
			witchSpawnTimer = CreateTimer(DIRECTOR_WITCH_CHECK_TIME, Timer_DirectorWitch, _, TIMER_REPEAT);
	} else {
		delete witchSpawnTimer;
	}
}

void Event_WitchSpawn(Event event, const char[] name, bool dontBroadcast) {
	g_spawnCount[Special_Witch]++;
}
void Director_OnClientPutInServer(int client) {
	if(client > 0 && GetClientTeam(client) == 3) {
		int class = GetEntProp(client, Prop_Send, "m_zombieClass");
		// Ignore a hacky temp bot spawn
		// To bypass director limits many plugins spawn an infected "bot" that immediately gets kicked, which allows a window to spawn a special
		static char buf[32];
		GetClientName(special, buf, sizeof(buf));
		if(StrContains(buf, "bot", false) == -1) {
			g_spawnCount[class]++;
		}
	}
}
void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(client > 0 && GetClientTeam(client) == 3) {
		int class = GetEntProp(client, Prop_Send, "m_zombieClass");
		g_spawnCount[class]--;
	} 
}

/// METHODS

void InitExtraWitches() { 
	float flowMax = L4D2Direct_GetMapMaxFlowDistance() - FLOW_CUTOFF;
	// Just in case we don't have max flow or the map is extremely tiny, don't run:
	if(flowMax > 0.0) {
		int count = abmExtraCount;
		if(count < 4) count = 4;
		// Calculate the number of witches we want to spawn.
		// We bias the dice roll to the right. We slowly increase min based on player count to shift distribution to the right
		int min = RoundToFloor(float(count - 4) / 4.0);
		extraWitchCount = DiceRoll(min, DIRECTOR_WITCH_MAX_WITCHES, DIRECTOR_WITCH_ROLLS, BIAS_LEFT);
		PrintDebug(DEBUG_SPAWNLOGIC, "InitExtraWitches: %d witches (min=%d, max=%d, rolls=%d) checkInterval=%f", extraWitchCount, min, DIRECTOR_WITCH_MAX_WITCHES, DIRECTOR_WITCH_ROLLS, DIRECTOR_WITCH_CHECK_TIME);
		for(int i = 0; i <= extraWitchCount; i++) {
			g_extraWitchFlowPositions[i] = GetURandomFloat() * (flowMax-FLOW_CUTOFF) + FLOW_CUTOFF;
			PrintDebug(DEBUG_SPAWNLOGIC, "Witch position #%d: flow %.2f (%.0f%%)", i, g_extraWitchFlowPositions[i], g_extraWitchFlowPositions[i] / flowMax);
		}
		witchSpawnTimer = CreateTimer(DIRECTOR_WITCH_CHECK_TIME, Timer_DirectorWitch, _, TIMER_REPEAT);
	}
}

void Director_PrintDebug(int client) {
	PrintToConsole(client, "===Extra Witches===");
	PrintToConsole(client, "Map Bounds: [%f, %f]", FLOW_CUTOFF, L4D2Direct_GetMapMaxFlowDistance() - (FLOW_CUTOFF*2.0));
	PrintToConsole(client, "Total Witches Spawned: %d | Target: %d", g_spawnCount[Special_Witch], extraWitchCount);
	for(int i = 0; i < extraWitchCount && i < DIRECTOR_WITCH_MAX_WITCHES; i++) {
		PrintToConsole(client, "%d. %f", i, g_extraWitchFlowPositions[i]);
	}
}

void Director_RandomizeLimits() {
	// We add +1 to spice it up
	int max = RoundToCeil(float(abmExtraCount - 4) / 4) + 1;
	for(int i = 0; i < NUM_SPECIALS; i++) {
		specialType special = view_as<specialType>(i);
		g_spawnLimit[i] = GetRandomInt(0, max);
	}
}
void Director_RandomizeThings() {
	g_minStressIntensity = GetRandomFloat(DIRECTOR_STRESS_CUTOFF, 1.0);
	g_minFlowSpawn = GetRandomFloat(FLOW_CUTOFF, FLOW_CUTOFF * 2);

}

/// TIMERS

Action Timer_Director(Handle h) {
	if(abmExtraCount <= 4) return Plugin_Continue;
	float time = GetGameTime();

	// Calculate the new highest flow
	int highestPlayer = L4D_GetHighestFlowSurvivor();
	float flow = L4D2Direct_GetFlowDistance(highestPlayer);
	if(flow > highestFlowAchieved) { 
		highestFlowAchieved = flow;
	}
	// Only start spawning once they get to g_minFlowSpawn - a little past the start saferoom
	if(highestFlowAchieved < g_minFlowSpawn) return Plugin_Continue;
	float curAvgStress = L4D_GetAvgSurvivorIntensity();
	// Don't spawn specials when tanks active, but have a small chance (DIRECTOR_SPECIAL_TANK_CHANCE) to bypass
	if(L4D2_IsTankInPlay() && GetURandomFloat() > DIRECTOR_SPECIAL_TANK_CHANCE) {
		return Plugin_Continue;
	} else {
		// Stop spawning when players are stressed from a random value chosen by [DIRECTOR_STRESS_CUTOFF, 1.0]
		if(curAvgStress >= g_minStressIntensity) return Plugin_Continue;
	}

	// TODO: Scale spawning chance based on intensity? 0.0 = more likely, < g_minStressIntensity = less likely
	// Scale the chance where stress = 0.0, the chance is 50% more, and stress = 1.0, the chance is 50% less
	float spawnChance = DIRECTOR_SPAWN_CHANCE + (0.5 - curAvgStress) / 10
	for(int i = 0; i < NUM_SPECIALS; i++) {
		specialType special = view_as<specialType>(i);
		// Skip if we hit our limit, or too soon:
		if(g_spawnCount[i] >= g_spawnLimit[i]) continue;
		if(time - g_lastSpawnTime[i] < DIRECTOR_MIN_SPAWN_TIME) continue;

		if(GetURandomFloat() < spawnChance) {
			DirectorSpawn(special);
		}
	}

	if(GetURandomFloat() < DIRECTOR_CHANGE_LIMIT_CHANCE) {
		Director_RandomizeLimits();
	}

	return Plugin_Continue;
}


Action Timer_DirectorWitch(Handle h) {
	if(g_spawnCount[Special_Witch] < extraWitchCount) { //&& time - g_lastSpawnTimes.witch > DIRECTOR_WITCH_MIN_TIME
 		for(int i = 0; i <= extraWitchCount; i++) {
			if(g_extraWitchFlowPositions[i] > 0.0 && highestFlowAchieved >= g_extraWitchFlowPositions[i]) {
				// Reset the flow so we don't spawn another
				g_extraWitchFlowPositions[i] = 0.0;
				DirectorSpawn(Special_Witch);
				break;
			}
		}
	}
	return Plugin_Continue;
}

// UTIL functions
void DirectorSpawn(specialType special) {
	PrintChatToAdmins("EPI: DirectorSpawn(%s) (dont worry about it)", SPECIAL_IDS[view_as<int>(special)]);
	int player = GetSuitableVictim();
	PrintDebug(DEBUG_SPAWNLOGIC, "Director: spawning %s from %N (cnt=%d,lim=%d)", SPECIAL_IDS[view_as<int>(special)], player, g_spawnCount[view_as<int>(special)], g_spawnLimit[view_as<int>(special)]);
	PrintToServer("[EPI] Spawning %s On %N", SPECIAL_IDS[view_as<int>(special)], player);
	if(special != Special_Witch && special != Special_Tank) {
		// Bypass director
		int bot = CreateFakeClient("EPI_BOT");
		if (bot != 0) {
			ChangeClientTeam(bot, 3);
			CreateTimer(0.1, Timer_Kick, bot);
		}
	}
	CheatCommand(player, "z_spawn_old", SPECIAL_IDS[view_as<int>(special)], "auto");
	g_lastSpawnTime[view_as<int>(special)] = GetGameTime();
}

// TODO: make
void DirectSpawn(specialType special, const float pos[3]) {

}
// Finds a player that is suitable (lowest intensity)
int GetSuitableVictim() {
	int victim = -1;
	float lowestIntensity = 0.0;
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i)) {
			float intensity = L4D_GetPlayerIntensity(i);
			// TODO: possibly add perm health into calculations
			if(intensity < lowestIntensity || victim == -1) {
				lowestIntensity = intensity;
				victim = i;
			}
		}
	}
	return victim;
}