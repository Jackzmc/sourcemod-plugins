// SETTINGS
// TODO: make cvars
#define DIRECTOR_TIMER_INTERVAL 3.0
#define DIRECTOR_WITCH_MIN_TIME 120 // The minimum amount of time to pass since last witch spawn for the next extra witch to spawn
#define DIRECTOR_WITCH_CHECK_TIME 30.0 // How often to check if a witch should be spawned
#define DIRECTOR_WITCH_MAX_WITCHES 5 // The maximum amount of extra witches to spawn 
#define DIRECTOR_WITCH_ROLLS 4 // The number of dice rolls, increase if you want to increase freq
#define DIRECTOR_MIN_SPAWN_TIME 13.0 // Possibly randomized, per-special, in seconds
ConVar directorSpawnChance; // Base chance of a special spawning, changed by player stress
#define DIRECTOR_CHANGE_LIMIT_CHANCE 0.05 // The chance that the maximum amount per-special is changed
#define DIRECTOR_SPECIAL_TANK_CHANCE 0.05 // The chance that specials can spawn when a tank is active
#define DIRECTOR_STRESS_CUTOFF 0.75 // The minimum chance a random cut off stress value is chosen [this, 1.0]
#define DIRECTOR_REST_CHANCE 0.04 // The chance the director ceases spawning
#define DIRECTOR_REST_MAX_COUNT 8 // The maximum amount of rest given (this * DIRECTOR_TIMER_INTERVAL)
#define DIRECTOR_ESCAPE_TANK_MIN_TIME_S 40 // The min time in seconds that must elapse since escape vehicle arrival until tank can spawn

#define DIRECTOR_DEBUG_SPAWN 1 // Dont actually spawn

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
	Special_Smoker = 0,
	Special_Boomer = 1,
	Special_Hunter = 2,
	Special_Spitter = 3,
	Special_Jockey = 4,
	Special_Charger = 5,
	Special_Witch = 6,
	Special_Tank = 7,
};
enum directorState {
	DState_Normal,
	DState_NoPlayersOrNotCoop,
	DState_PendingMinFlow,
	DState_Disabled,
	DState_MaxSpecialTime,
	DState_PlayerChance,
	DState_Resting,
	DState_TankInPlay,
	DState_HighStress,
	DState_MaxDirectorSpecials,
}
char DIRECTOR_STATE[10][] = {
	"normal",
	"no players / not coop",
	"pending minflow",
	"disabled",
	"max special in window",
	"player scaled chance",
	"rest period",
	"tank in play",
	"high stress",
	"director MaxSpecials"
};
static directorState g_lastState; 

static float g_highestFlowAchieved;
static float g_lastSpawnTime[TOTAL_NUM_SPECIALS];
static float g_lastSpecialSpawnTime; // for any special
static int g_spawnLimit[TOTAL_NUM_SPECIALS];
static int g_spawnCount[TOTAL_NUM_SPECIALS];
static int gd_maxSpecials;
static float g_minFlowSpawn; // The minimum flow for specials to start spawning (waiting for players to leave saferom)
static float g_maxStressIntensity; // The max stress that specials arent allowed to spawn

int g_extraWitchCount;
static int g_infectedCount;
int g_restCount;
static Handle witchSpawnTimer = null;

float g_extraWitchFlowPositions[DIRECTOR_WITCH_MAX_WITCHES] = {};

/// EVENTS

void Director_OnMapStart() {
	// Only spawn witches if enabled, and not loate loaded
	if(!g_isLateLoaded && cvEPISpecialSpawning.IntValue & 2 && IsEPIActive()) { 
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
	if(convar.IntValue & 2) {
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
		int class = GetEntProp(client, Prop_Send, "m_zombieClass") - 1;
		if(class > view_as<int>(Special_Tank)) {
			return;
		} else if(IsFakeClient(client)) {
			// Sometimes the bot class is _not_ invalid, but usually has BOT in its name. Ignore those players.
			char name[32];
			GetClientName(client, name, sizeof(name));
			if(StrContains(name, "bot", false) != -1) {
				return;
			}
		}
		
		if(IsFakeClient(client) && class == view_as<int>(Special_Tank)) {
			OnTankBotSpawn(client);
		}
		
		g_spawnCount[class]++;
		float time = GetGameTime();
		g_lastSpawnTime[class] = time;
		g_lastSpecialSpawnTime = time;
		g_infectedCount++;

	}
}

static int g_newTankHealth = 0; 
void OnTankBotSpawn(int client) {
	if(!IsEPIActive() || !(cvEPISpecialSpawning.IntValue & 4)) return;
	if(g_finaleVehicleStartTime > 0 && GetTime() - g_finaleVehicleStartTime >  DIRECTOR_ESCAPE_TANK_MIN_TIME_S) {
		PrintDebug(DEBUG_SPAWNLOGIC, "OnTankBotSpawn: Tank too early, killing");
		ForcePlayerSuicide(client);
		return;
	} 

	// Check if any finale is active
	if(g_newTankHealth > 0) {
		// A split tank has spawned, set its health
		PrintDebug(DEBUG_SPAWNLOGIC, "OnTankBotSpawn: split tank spawned, setting health to %d", g_newTankHealth);
		SetEntProp(client, Prop_Send, "m_iHealth", g_newTankHealth);
		g_newTankHealth = 0;
		return;
	} else if(g_realSurvivorCount >= hExtraTankThreshold.IntValue && g_extraFinaleTankEnabled && hExtraFinaleTank.IntValue > 1) {
		// If we have hExtraTankThreshold or more and finale tanks enabled, spawn finale tanks:
		if(g_epiTankState == Stage_Active) {
			// 1st tank spawned
			PrintDebug(DEBUG_SPAWNLOGIC, "OnTankBotSpawn: [FINALE] 1st tank spawned");
			int health = CalculateExtraTankHealth(client);
			SetEntProp(client, Prop_Send, "m_iHealth", health);
			g_epiTankState = Stage_FirstTankSpawned;
			return;
		} else if(g_realSurvivorCount >= 6 && g_epiTankState == Stage_FirstTankSpawned) {
			PrintDebug(DEBUG_SPAWNLOGIC, "OnTankBotSpawn: [FINALE] 2nd tank spawned");
			float duration = GetRandomFloat(EXTRA_TANK_MIN_SEC, EXTRA_TANK_MAX_SEC);
			// Pass it 0, which doesnt make it a split tank, has default health
			CreateTimer(duration, Timer_SpawnSplitTank, 0);
			int health = CalculateExtraTankHealth(client);
			SetEntProp(client, Prop_Send, "m_iHealth", health);
			g_epiTankState = Stage_SecondTankSpawned;
			return;
		}
	}

	// End finale logic:
	if(g_epiTankState == Stage_SecondTankSpawned) {
		PrintDebug(DEBUG_SPAWNLOGIC, "OnTankBotSpawn: [FINALE] Health set, tank logic done");
		g_epiTankState = Stage_ActiveDone;
		// We don't return, letting the 2nd 5+ finale tank get buffed:
	}
	// This should not run on active finales (different than finale maps, such as swamp fever's, where finale isnt full map)
	// Normal tank (not stage 2 / not secondary tank) spawned. Set its health and spawn split tank
	int health = CalculateExtraTankHealth(client);

	/* Split tank can only spawn if: 
		(1) not finale
		(2) over threshold hExtraTankThreshold
		(3) split tanks enabled
		(4) random chance set by hSplitTankChance
	Otherwise, just scale health based on survivor count
	*/
	if(g_epiTankState == Stage_Inactive && g_realSurvivorCount >= hExtraTankThreshold.IntValue && hExtraFinaleTank.IntValue & 1 && GetURandomFloat() <= hSplitTankChance.FloatValue) {
		float duration = GetRandomFloat(EXTRA_TANK_MIN_SEC, EXTRA_TANK_MAX_SEC);
		int splitHealth = health / 2;
		PrintDebug(DEBUG_SPAWNLOGIC, "OnTankBotSpawn: split tank in %.1fs, health=%d", duration, splitHealth);
		CreateTimer(duration, Timer_SpawnSplitTank, splitHealth);
		SetEntProp(client, Prop_Send, "m_iHealth", splitHealth);
	} else {
		PrintDebug(DEBUG_SPAWNLOGIC, "OnTankBotSpawn: Setting tank health to %d", health);
		SetEntProp(client, Prop_Send, "m_iHealth", health);
	}
}

int CalculateExtraTankHealth(int client) {
	int health = GetEntProp(client, Prop_Send, "m_iHealth");
	float additionalHealth = float(g_survivorCount - 4) * cvEPITankHealth.FloatValue;
	health += RoundFloat(additionalHealth);
	if(health <= 0) PrintToServer("CalculateExtraTankHealth: returning 0?");
	return health;
}

Action Timer_SpawnSplitTank(Handle h, int health) {
	PrintDebug(DEBUG_SPAWNLOGIC, "Timer_SpawnSplitTank(%d)", health);
	g_newTankHealth = health;
	DirectorSpawn(Special_Tank);
	return Plugin_Handled;
}

void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(client > 0) {
		int team = GetClientTeam(client);
		if(team == 3) {
			int class = GetEntProp(client, Prop_Send, "m_zombieClass") - 1;
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


/*
Extra Witch Algo:
On map start, knowing # of total players, compute a random number of witches. 
The random number calculated by DiceRoll with 2 rolls and biased to the left. [min, 6]
The minimum number in the dice is shifted to the right by the # of players (abmExtraCount-4)/4 (1 extra=0, 10 extra=2)

Then, with the # of witches, as N, calculate N different flow values between [0, L4D2Direct_GetMapMaxFlowDistance()]
Timer_Director then checks if highest flow achieved (never decreases) is >= each flow value, if one found, a witch is spawned
(the witch herself is not spawned at the flow, just her spawning is triggered)
*/
void InitExtraWitches() { 
	float flowMax = L4D2Direct_GetMapMaxFlowDistance() - FLOW_CUTOFF;
	// Just in case we don't have max flow or the map is extremely tiny, don't run:
	if(flowMax > 0.0) {
		int count = g_survivorCount;
		if(count < 4) count = 4;
		// Calculate the number of witches we want to spawn.
		// We bias the dice roll to the right. We slowly increase min based on player count to shift distribution to the right
		int min = RoundToFloor(float(count - 5) / 4.0);
		int max = RoundToFloor(float(count) / 4.0);

		// TODO: inc chance based on map max flow
		g_extraWitchCount = DiceRoll(min, DIRECTOR_WITCH_MAX_WITCHES, DIRECTOR_WITCH_ROLLS, BIAS_LEFT);
		PrintDebug(DEBUG_SPAWNLOGIC, "InitExtraWitches: %d witches (min=%d, max=%d, rolls=%d) checkInterval=%f", g_extraWitchCount, min, max, DIRECTOR_WITCH_ROLLS, DIRECTOR_WITCH_CHECK_TIME);
		for(int i = 0; i < g_extraWitchCount; i++) {
			g_extraWitchFlowPositions[i] = GetURandomFloat() * (flowMax-FLOW_CUTOFF) + FLOW_CUTOFF;
			PrintDebug(DEBUG_SPAWNLOGIC, "Witch position #%d: flow %.2f (%.0f%%)", i, g_extraWitchFlowPositions[i], g_extraWitchFlowPositions[i] / flowMax);
		}
		witchSpawnTimer = CreateTimer(DIRECTOR_WITCH_CHECK_TIME, Timer_DirectorWitch, _, TIMER_REPEAT);
	}
	// TODO: spawn them early instead
}

void Director_PrintDebug(int client) {
	PrintToConsole(client, "State: %s(%d)", DIRECTOR_STATE[g_lastState], g_lastState);
	float eCount = float(g_survivorCount - 3);
	float chance = (eCount - float(g_infectedCount)) / eCount;
	PrintToConsole(client, "Player Scale Chance: %f%%", chance * 100.0);
	PrintToConsole(client, "Map Bounds: [%f, %f]", FLOW_CUTOFF, L4D2Direct_GetMapMaxFlowDistance() - (FLOW_CUTOFF*2.0));
	PrintToConsole(client, "Total Witches Spawned: %d | Target: %d", g_spawnCount[Special_Witch], g_extraWitchCount);
	for(int i = 0; i < g_extraWitchCount && i < DIRECTOR_WITCH_MAX_WITCHES; i++) {
		PrintToConsole(client, "%d. %f", i+1, g_extraWitchFlowPositions[i]);
	}
	PrintToConsole(client, "highestFlow = %f, g_minFlowSpawn = %f, current flow = %f", g_highestFlowAchieved, g_minFlowSpawn, L4D2Direct_GetFlowDistance(client));
	PrintToConsole(client, "g_maxStressIntensity = %f, current avg = %f", g_maxStressIntensity, L4D_GetAvgSurvivorIntensity());
	PrintToConsole(client, "TankInPlay=%b, FinaleStage=%d, FinaleEscapeReady=%b, DirectorTankCheck:%b", L4D2_IsTankInPlay(), g_epiTankState, g_isFinaleEnding, L4D2_IsTankInPlay() && !g_isFinaleEnding);
	char buffer[128];
	float time = GetGameTime();
	PrintToConsole(client, "Last Spawn Deltas: (%.1f s) (min %f)", time - g_lastSpecialSpawnTime, DIRECTOR_MIN_SPAWN_TIME);
	for(int i = 0; i < TOTAL_NUM_SPECIALS; i++) {
		Format(buffer, sizeof(buffer), "%s %s=%.1f", buffer, SPECIAL_IDS[i], time-g_lastSpawnTime[i]);
	}
	PrintToConsole(client, "\t%s", buffer);
	buffer[0] = '\0';
	PrintToConsole(client, "Spawn Counts: (%d/%d)", g_infectedCount, g_survivorCount - 4);
	for(int i = 0; i < TOTAL_NUM_SPECIALS; i++) {
		Format(buffer, sizeof(buffer), "%s %s=%d/%d", buffer, SPECIAL_IDS[i], g_spawnCount[i], g_spawnLimit[i]);
	}
	PrintToConsole(client, "\t%s", buffer);
	PrintToConsole(client, "timer interval=%.0f, rest count=%d, rest time left=%.0fs", DIRECTOR_TIMER_INTERVAL, g_restCount, float(g_restCount) * DIRECTOR_TIMER_INTERVAL);
}

void Director_RandomizeLimits() {
	// We add +1 to spice it up
	int max = RoundToCeil(float(g_survivorCount - 4) / 4) + 1;
	for(int i = 0; i < NUM_SPECIALS; i++) {
		g_spawnLimit[i] = GetRandomInt(0, max);
		// PrintDebug(DEBUG_SPAWNLOGIC, "new spawn limit (special=%d, b=[0,%d], limit=%d)", i, max, g_spawnLimit[i]);
	}
	gd_maxSpecials = L4D2_GetScriptValueInt("MaxSpecials", 0);
}
void Director_RandomizeThings() {
	g_maxStressIntensity = GetRandomFloat(DIRECTOR_STRESS_CUTOFF, 1.0);
	g_minFlowSpawn = GetRandomFloat(500.0 + FLOW_CUTOFF, FLOW_CUTOFF * 2);
	Director_RandomizeLimits();
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
	}
}

// Little hacky, need to track when one leaves instead
void Director_CheckSpawnCounts() {
	if(!IsEPIActive()) return;
	for(int i = 0; i < TOTAL_NUM_SPECIALS; i++) {
		g_spawnCount[i] = 0;
	}
	g_infectedCount = 0;
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientInGame(i) && GetClientTeam(i) == 3) {
			int class = GetEntProp(i, Prop_Send, "m_zombieClass") - 1; // make it 0-based
			if(class > view_as<int>(Special_Tank)) continue;
			g_spawnCount[class]++;
			g_infectedCount++;
		}
	}
}

/// TIMERS

// TODO: maybe make specials spaw nmore during horde events (alarm car, etc)
// less during calms, making that the automatic rest periods?
directorState Director_Think() { 
	if(!IsEPIActive()) return DState_NoPlayersOrNotCoop;
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
	gd_maxSpecials = L4D2_GetScriptValueInt("MaxSpecials", 0);
	if(gd_maxSpecials <= 0) return DState_MaxDirectorSpecials;
	if(~cvEPISpecialSpawning.IntValue & 1 ) return DState_Disabled;
	if(!L4D_HasAnySurvivorLeftSafeArea() || g_highestFlowAchieved < g_minFlowSpawn) return DState_PendingMinFlow;

	// Check if a rest period is given
	if(Director_ShouldRest()) {
		return DState_Resting;
	}

	// Only spawn more than one special within 2s at 10%
	// TODO: randomized time between spawns? 0, ?? instead of repeat timer?
	if(time - g_lastSpecialSpawnTime < 1.0 && GetURandomFloat() > 0.45) return DState_MaxSpecialTime;

	if(GetURandomFloat() < DIRECTOR_CHANGE_LIMIT_CHANCE) {
		Director_RandomizeLimits();
	}

	// Decrease chance of spawning based on how close to infected count 
	// abmExtraCount=6 g_infectedCount=0   chance=1.0   ((abmExtraCount-g_infectedCount)/abmExtraCount)
	// abmExtraCount=6 g_infectedCount=1   chance=0.9   ((6-1)/6)) = (5/6)
	// abmExtraCount=6 g_infectedCount=6   chance=0.2
	// TODO: in debug calculate this
	float eCount = float(g_survivorCount - 3);
	float chance = (eCount - float(g_infectedCount)) / eCount;
	// TODO: verify (abmExtraCount-4)
	if(GetURandomFloat() > chance) return DState_PlayerChance;


	float curAvgStress = L4D_GetAvgSurvivorIntensity();
	// Don't spawn specials when tanks active, but have a small chance (DIRECTOR_SPECIAL_TANK_CHANCE) to bypass
	if((L4D2_IsTankInPlay() && !g_isFinaleEnding) && GetURandomFloat() > DIRECTOR_SPECIAL_TANK_CHANCE) {
		return DState_TankInPlay;
	} else if(curAvgStress >= g_maxStressIntensity) {
		// Stop spawning when players are stressed from a random value chosen by [DIRECTOR_STRESS_CUTOFF, 1.0]
		return DState_HighStress;
	}
	// Scale the chance where stress = 0.0, the chance is 50% more, and stress = 1.0, the chance is 50% less
	float spawnChance = directorSpawnChance.FloatValue + ((0.5 - curAvgStress) / 10.0);
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
	// TODO: instead of +1, do it when director spawned a witch
	if(!IsEPIActive()) return Plugin_Continue;
	if(g_spawnCount[Special_Witch] < g_extraWitchCount + 1) { //&& time - g_lastSpawnTimes.witch > DIRECTOR_WITCH_MIN_TIME
 		for(int i = 0; i <= g_extraWitchCount; i++) {
			if(g_extraWitchFlowPositions[i] > 0.0 && g_highestFlowAchieved >= g_extraWitchFlowPositions[i]) {
				// Reset the flow so we don't spawn another
				g_extraWitchFlowPositions[i] = 0.0;
				int target = L4D_GetHighestFlowSurvivor();
				if(!target) return Plugin_Continue;
				DirectorSpawn(Special_Witch, target);
				return Plugin_Continue;
			}
		}
	}
	witchSpawnTimer = null;
	return Plugin_Stop;
}

// UTIL functions
void DirectorSpawn(specialType special, int player = -1) {
	if(player <= 0)
		player = GetSuitableVictim();
	if(special != Special_Witch && special != Special_Tank) {
		// Bypass director
		int bot = CreateFakeClient("EPI_BOT");
		if (bot != 0) {
			ChangeClientTeam(bot, 3);
			CreateTimer(0.1, Timer_Kick, bot);
		}
	}
	float pos[3];
	if(L4D_GetRandomPZSpawnPosition(player, view_as<int>(special) + 1, 10, pos)) {
		// They use 1-index
		if(special == Special_Tank) {
			L4D2_SpawnTank(pos, NULL_VECTOR);
		} else {
			L4D2_SpawnSpecial(view_as<int>(special) + 1, pos, NULL_VECTOR);
		}
	}
}

int g_iLastVictim;
int GetSuitableVictim() {
	return GetRandomSurvivor(1, -1);
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