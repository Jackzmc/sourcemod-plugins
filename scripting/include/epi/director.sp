// SETTINGS
// TODO: make cvars
#define DIRECTOR_TIMER_INTERVAL 3.0
#define DIRECTOR_WITCH_MIN_TIME 120 // The minimum amount of time to pass since last witch spawn for the next extra witch to spawn
#define DIRECTOR_WITCH_CHECK_TIME 30.0 // How often to check if a witch should be spawned
#define DIRECTOR_WITCH_MAX_WITCHES 5 // The maximum amount of extra witches to spawn 
#define DIRECTOR_WITCH_ROLLS 4 // The number of dice rolls, increase if you want to increase freq
#define DIRECTOR_MIN_SPAWN_TIME 12.0 // Possibly randomized, per-special
#define DIRECTOR_SPAWN_CHANCE 0.05 // The raw chance of a spawn 
#define DIRECTOR_CHANGE_LIMIT_CHANCE 0.05 // The chance that the maximum amount per-special is changed
#define DIRECTOR_SPECIAL_TANK_CHANCE 0.05 // The chance that specials can spawn when a tank is active
#define DIRECTOR_STRESS_CUTOFF 0.75 // The minimum chance a random cut off stress value is chosen [this, 1.0]
#define DIRECTOR_REST_CHANCE 0.03 // The chance the director ceases spawning
#define DIRECTOR_REST_MAX_COUNT 10 // The maximum amount of rest given (this * DIRECTOR_TIMER_INTERVAL)

#define DIRECTOR_DEBUG_SPAWN 1 // Dont actually spawn

/// DEFINITIONS
#define NUM_SPECIALS 6
#define TOTAL_NUM_SPECIALS 8
char SPECIAL_IDS[TOTAL_NUM_SPECIALS][] = {
	"invalid",
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
	Special_Smoker = 1,
	Special_Boomer = 2,
	Special_Hunter = 3,
	Special_Spitter = 4,
	Special_Jockey = 5,
	Special_Charger = 6,
	Special_Witch = 7,
	Special_Tank = 8,
};
enum directorState {
	DState_Normal,
	DState_NoPlayersOrNotCoop,
	DState_PendingMinFlowOrDisabled,
	DState_MaxSpecialTime,
	DState_PlayerChance,
	DState_Resting,
	DState_TankInPlay,
	DState_HighStress
}
char DIRECTOR_STATE[8][] = {
	"normal",
	"no players / not coop",
	"pending minflow OR disabled",
	"max special in window",
	"player scaled chance",
	"rest period",
	"tank in play",
	"high stress",
};
directorState g_lastState; 

static float g_highestFlowAchieved;
static float g_lastSpawnTime[TOTAL_NUM_SPECIALS];
static float g_lastSpecialSpawnTime; // for any special
static int g_spawnLimit[TOTAL_NUM_SPECIALS];
static int g_spawnCount[TOTAL_NUM_SPECIALS];
static float g_minFlowSpawn; // The minimum flow for specials to start spawning (waiting for players to leave saferom)
static float g_maxStressIntensity; // The max stress that specials arent allowed to spawn

static int extraWitchCount;
static int g_infectedCount;
static int g_restCount;
static Handle witchSpawnTimer = null;

float g_extraWitchFlowPositions[DIRECTOR_WITCH_MAX_WITCHES] = {};

/// EVENTS

void Director_OnMapStart() {
	if(cvEPISpecialSpawning.IntValue & 2 && abmExtraCount > 4) { 
		InitExtraWitches();
	}
	float time = GetGameTime();
	for(int i = 0; i < TOTAL_NUM_SPECIALS; i++) {
		g_lastSpawnTime[i] = time;
		g_spawnLimit[i] = 1;
		g_spawnCount[i] = 0;
	}
	g_highestFlowAchieved = 0.0;
	g_lastSpecialSpawnTime = time;
	g_infectedCount = 0;
	g_restCount = 0;
	Director_RandomizeThings();
}

void Director_OnMapEnd() {
	for(int i = 0; i < DIRECTOR_WITCH_MAX_WITCHES; i++) {
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
	// Wait a frame for the bot to be assigned a team
	RequestFrame(Director_CheckClient, client);
}
void Director_CheckClient(int client) {
	if(IsClientConnected(client) && GetClientTeam(client) == 3) {
		// To bypass director limits many plugins spawn an infected "bot" that immediately gets kicked, which allows a window to spawn a special
		// The fake bot's class is usually 9, an invalid
		int class = GetEntProp(client, Prop_Send, "m_zombieClass");
		if(class > view_as<int>(Special_Tank)) {
			return;
		}
		if(IsFakeClient(client) && class == Special_Tank && abmExtraCount > 4 && cvEPISpecialSpawning.IntValue & 4) {
			OnTankBotSpawn(client);
		}
		
		g_spawnCount[class]++;
		float time = GetGameTime();
		g_lastSpawnTime[class] = time;
		g_lastSpecialSpawnTime = time;
		g_infectedCount++;

	}
}

void OnTankBotSpawn(int client) {
	if(g_finaleStage == Stage_FinaleActive) {

	} else {
		int health = GetEntProp(client, Prop_Send, "m_iHealth");
		int additionalHealth = float(abmExtraCount - 4) * cvEPITankHealth.FloatValue;
		health += additionalHealth;
		SetEntProp(client, Prop_Send, "m_iHealth", health);
	}
}

void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(client > 0) {
		int team = GetClientTeam(client);
		if(team == 3) {
			int class = GetEntProp(client, Prop_Send, "m_zombieClass");
			if(class > view_as<int>(Special_Tank)) return;
			g_spawnCount[class]--;
			if(g_spawnCount[class] < 0) {
				g_spawnCount[class] = 0;
			}
			g_infectedCount--;
			if(g_infectedCount < 0) {
				g_infectedCount = 0;
			}
		} else if(team == 2) {
			TryGrantRest();
		}
	} 
}

void Event_PlayerIncapped(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(client > 0 && GetClientTeam(client) == 2) {
		TryGrantRest();
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
		int min = RoundToFloor(float(count - 5) / 4.0);
		// TODO: max based on count
		int max = RoundToFloor(float(count) / 4.0);

		extraWitchCount = DiceRoll(min, DIRECTOR_WITCH_MAX_WITCHES, DIRECTOR_WITCH_ROLLS, BIAS_LEFT);
		PrintDebug(DEBUG_SPAWNLOGIC, "InitExtraWitches: %d witches (min=%d, max=%d, rolls=%d) checkInterval=%f", extraWitchCount, min, max, DIRECTOR_WITCH_ROLLS, DIRECTOR_WITCH_CHECK_TIME);
		for(int i = 0; i <= extraWitchCount; i++) {
			g_extraWitchFlowPositions[i] = GetURandomFloat() * (flowMax-FLOW_CUTOFF) + FLOW_CUTOFF;
			PrintDebug(DEBUG_SPAWNLOGIC, "Witch position #%d: flow %.2f (%.0f%%)", i, g_extraWitchFlowPositions[i], g_extraWitchFlowPositions[i] / flowMax);
		}
		witchSpawnTimer = CreateTimer(DIRECTOR_WITCH_CHECK_TIME, Timer_DirectorWitch, _, TIMER_REPEAT);
	}
	// TODO: spawn them early instead
}

void Director_PrintDebug(int client) {
	PrintToConsole(client, "===Extra Witches===");
	PrintToConsole(client, "State: %s(%d)", DIRECTOR_STATE[g_lastState], g_lastState);
	PrintToConsole(client, "Map Bounds: [%f, %f]", FLOW_CUTOFF, L4D2Direct_GetMapMaxFlowDistance() - (FLOW_CUTOFF*2.0));
	PrintToConsole(client, "Total Witches Spawned: %d | Target: %d", g_spawnCount[Special_Witch], extraWitchCount);
	for(int i = 0; i < extraWitchCount && i < DIRECTOR_WITCH_MAX_WITCHES; i++) {
		PrintToConsole(client, "%d. %f", i+1, g_extraWitchFlowPositions[i]);
	}
	PrintToConsole(client, "highestFlow = %f, g_minFlowSpawn = %f, current flow = %f", g_highestFlowAchieved, g_minFlowSpawn, L4D2Direct_GetFlowDistance(client));
	PrintToConsole(client, "g_maxStressIntensity = %f, current avg = %f", g_maxStressIntensity, L4D_GetAvgSurvivorIntensity());
	PrintToConsole(client, "TankInPlay=%b, FinaleEscapeReady=%b, DirectorTankCheck:%b", L4D2_IsTankInPlay(), g_isFinaleEnding, L4D2_IsTankInPlay() && !g_isFinaleEnding);
	char buffer[128];
	float time = GetGameTime();
	PrintToConsole(client, "Last Spawn Deltas: (%.1f s) (min %f)", time - g_lastSpecialSpawnTime, DIRECTOR_MIN_SPAWN_TIME);
	for(int i = 0; i < TOTAL_NUM_SPECIALS; i++) {
		Format(buffer, sizeof(buffer), "%s %s=%.1f", buffer, SPECIAL_IDS[i], time-g_lastSpawnTime[i]);
	}
	PrintToConsole(client, "\t%s", buffer);
	buffer[0] = '\0';
	PrintToConsole(client, "Spawn Counts: (%d/%d)", g_infectedCount, abmExtraCount);
	for(int i = 0; i < TOTAL_NUM_SPECIALS; i++) {
		Format(buffer, sizeof(buffer), "%s %s=%d/%d", buffer, SPECIAL_IDS[i], g_spawnCount[i], g_spawnLimit[i]);
	}
	PrintToConsole(client, "\t%s", buffer);
	PrintToConsole(client, "timer interval=%.0f, rest count=%d", DIRECTOR_TIMER_INTERVAL, g_restCount);
}

void Director_RandomizeLimits() {
	// We add +1 to spice it up
	int max = RoundToCeil(float(abmExtraCount - 4) / 4) + 1;
	for(int i = 0; i < NUM_SPECIALS; i++) {
		g_spawnLimit[i] = GetRandomInt(0, max);
		// PrintDebug(DEBUG_SPAWNLOGIC, "new spawn limit (special=%d, b=[0,%d], limit=%d)", i, max, g_spawnLimit[i]);
	}
}
void Director_RandomizeThings() {
	g_maxStressIntensity = GetRandomFloat(DIRECTOR_STRESS_CUTOFF, 1.0);
	g_minFlowSpawn = GetRandomFloat(FLOW_CUTOFF, FLOW_CUTOFF * 2);

}

bool Director_ShouldRest() { 
	if(g_restCount > 0) {
		g_restCount--;
		return true;
	}
	TryGrantRest();
	return false;
}

void TryGrantRest() {
	if(GetURandomFloat() <= DIRECTOR_REST_CHANCE) {
		g_restCount = GetRandomInt(0, DIRECTOR_REST_MAX_COUNT);
		if(g_restCount > 0)
			PrintDebug(DEBUG_SPAWNLOGIC, "new rest period: %.1f s", g_restCount * DIRECTOR_TIMER_INTERVAL);
	}
}

// Little hacky, need to track when one leaves instead
void Director_CheckSpawnCounts() {
	if(abmExtraCount <= 4 || !isCoop) return;
	for(int i = 0; i < TOTAL_NUM_SPECIALS; i++) {
		g_spawnCount[i] = 0;
	}
	g_infectedCount = 0;
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientInGame(i) && GetClientTeam(i) == 3) {
			int class = GetEntProp(i, Prop_Send, "m_zombieClass") - 1; // make it 0-based
			if(class == 8) continue;
			g_spawnCount[class]++;
			g_infectedCount++;
		}
	}
}

/// TIMERS

// TODO: maybe make specials spaw nmore during horde events (alarm car, etc)
// less during calms, making that the automatic rest periods?
directorState Director_Think() { 
	if(abmExtraCount <= 4 || !isCoop) return DState_NoPlayersOrNotCoop;
	float time = GetGameTime();

	// Calculate the new highest flow
	int highestPlayer = L4D_GetHighestFlowSurvivor();
	if(highestPlayer <= 0) return DState_NoPlayersOrNotCoop;
	float flow = L4D2Direct_GetFlowDistance(highestPlayer);
	if(flow > g_highestFlowAchieved) { 
		g_highestFlowAchieved = flow;
	}

	
	// Only run once until:
	// A. They reach minimum flow (little past start saferoom)
	// B. Under the total limited (equal to player count)
	// C. Special spawning is enabled
	// TODO: scaling chance, low chance when hitting g_infectedCount, higher on 0
	if(g_highestFlowAchieved < g_minFlowSpawn ||  ~cvEPISpecialSpawning.IntValue & 1) return DState_PendingMinFlowOrDisabled;

	// Only spawn more than one special within 2s at 10%
	if(time - g_lastSpecialSpawnTime < 2.0 && GetURandomFloat() > 0.5) return DState_MaxSpecialTime;

	if(GetURandomFloat() < DIRECTOR_CHANGE_LIMIT_CHANCE) {
		Director_RandomizeLimits();
	}

	// Decrease chance of spawning based on how close to infected count 
	// abmExtraCount=6 g_infectedCount=0   chance=1.0   ((abmExtraCount-g_infectedCount)/abmExtraCount)
	// abmExtraCount=6 g_infectedCount=1   chance=0.9   ((6-1)/6)) = (5/6)
	// abmExtraCount=6 g_infectedCount=6   chance=0.2
	float eCount = float(abmExtraCount - 3);
	float chance = (eCount - float(g_infectedCount)) / eCount;
	// TODO: verify (abmExtraCount-4)
	if(GetURandomFloat() > chance) return DState_PlayerChance;

	// Check if a rest period is given
	if(Director_ShouldRest()) {
		return DState_Resting;
	}

	float curAvgStress = L4D_GetAvgSurvivorIntensity();
	// Don't spawn specials when tanks active, but have a small chance (DIRECTOR_SPECIAL_TANK_CHANCE) to bypass
	if((L4D2_IsTankInPlay() && !g_isFinaleEnding) && GetURandomFloat() > DIRECTOR_SPECIAL_TANK_CHANCE) {
		return DState_TankInPlay;
	} else if(curAvgStress >= g_maxStressIntensity) {
		// Stop spawning when players are stressed from a random value chosen by [DIRECTOR_STRESS_CUTOFF, 1.0]
		return DState_HighStress;
	}
	// Scale the chance where stress = 0.0, the chance is 50% more, and stress = 1.0, the chance is 50% less
	float spawnChance = DIRECTOR_SPAWN_CHANCE + ((0.5 - curAvgStress) / 10.0);
	for(int i = 0; i < NUM_SPECIALS; i++) {
		specialType special = view_as<specialType>(i);
		// Skip if we hit our limit, or too soon:
		if(g_spawnCount[i] >= g_spawnLimit[i]) continue;
		if(time - g_lastSpawnTime[i] < DIRECTOR_MIN_SPAWN_TIME) continue;

		if(GetURandomFloat() <= spawnChance) {
			DirectorSpawn(special);
		}
	}

	return DState_Normal;
}

Action Timer_Director(Handle h) {
	g_lastState = Director_Think();
	return Plugin_Continue;
}


Action Timer_DirectorWitch(Handle h) {
	if(g_spawnCount[Special_Witch] < extraWitchCount) { //&& time - g_lastSpawnTimes.witch > DIRECTOR_WITCH_MIN_TIME
 		for(int i = 0; i <= extraWitchCount; i++) {
			if(g_extraWitchFlowPositions[i] > 0.0 && g_highestFlowAchieved >= g_extraWitchFlowPositions[i]) {
				// Reset the flow so we don't spawn another
				g_extraWitchFlowPositions[i] = 0.0;
				int target = L4D_GetHighestFlowSurvivor();
				if(!target) return Plugin_Continue;
				DirectorSpawn(Special_Witch, target);
				break;
			}
		}
	}
	return Plugin_Continue;
}

// UTIL functions
void DirectorSpawn(specialType special, int player = -1) {
	if(player <= 0)
		player = GetSuitableVictim();
	PrintDebug(DEBUG_SPAWNLOGIC, "Director: spawning %s(%d) around %N (cnt=%d,lim=%d)", SPECIAL_IDS[view_as<int>(special)], special, player, g_spawnCount[view_as<int>(special)], g_spawnLimit[view_as<int>(special)]);
	if(special != Special_Witch && special != Special_Tank) {
		// Bypass director
		int bot = CreateFakeClient("EPI_BOT");
		if (bot != 0) {
			ChangeClientTeam(bot, 3);
			CreateTimer(0.1, Timer_Kick, bot);
		}
	}
	// TODO: dont use z_spawn_old, spawns too close!!
	float pos[3];
	if(L4D_GetRandomPZSpawnPosition(player, view_as<int>(special), 10, pos)) {
		// They use 1-index
		L4D2_SpawnSpecial(view_as<int>(special) + 1, pos, NULL_VECTOR);
		g_lastSpawnTime[view_as<int>(special)] = GetGameTime();
	}
}

// Finds a player that is suitable (lowest intensity)
// TODO: biased random (lower intensity : bias)
// dice roll, #sides = #players, sort list of players by intensity
// then use biased left dice, therefore lower intensity = higher random weight
int g_iLastVictim;
int GetSuitableVictim() {
	// TODO: randomize?
	return GetRandomSurvivor(1, -1);
	// ArrayList survivors = new ArrayList(2);
	// for(int i = 1; i <= MaxClients; i++) {
	// 	if(IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i)) {
	// 		int index = survivors.Push(i);
	// 		survivors.Set(index, 1, L4D_GetPlayerIntensity(i));
	// 	}
	// }
	// // Soe
	// survivors.SortCustom()

	int victim = -1;
	float lowestIntensity = 0.0;
	for(int i = 1; i <= MaxClients; i++) {
		if(g_iLastVictim != i && IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i)) {
			float intensity = L4D_GetPlayerIntensity(i);
			// TODO: possibly add perm health into calculations
			if(intensity < lowestIntensity || victim == -1) {
				lowestIntensity = intensity;
				victim = i;
			}
		}
	}
	g_iLastVictim = victim;
	return victim;
}