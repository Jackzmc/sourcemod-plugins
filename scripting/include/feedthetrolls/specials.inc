char SPECIAL_NAMES[][] = {
	"Smoker", "Boomer", "Hunter", "Spitter", "Jockey", "Charger", "Witch", "Tank"
};

stock int GetSpecialType(const char[] input) {
	for(int i = 0; i < 8; i++) {
		if(strcmp(SPECIAL_NAMES[i], input, false) == 0) return i + 1;
	}
	return -1;
}

stock bool FindSuitablePosition(int target, const float pos[3], float outputPos[3], float minDistance = 19000.0, int tries = 100) {
	outputPos = pos;
	for(int i = tries; i > 0; i--) {
		// int nav = L4D_GetNearestNavArea(pos);
		// L4D_FindRandomSpot(nav, testPos);
		// float dist = GetVectorDistance(testPos, pos, true);
		outputPos[0] += GetRandomFloat(-30.0, 30.0);
		outputPos[1] += GetRandomFloat(-30.0, 30.0);
		float dist = GetVectorDistance(outputPos, pos, true);
		if(dist >= minDistance && L4D2Direct_GetTerrorNavArea(outputPos) != Address_Null) { //5m^2
			return true;
		}
	}
	return false;
}

float GetIdealMinDistance(int specialType) {
	switch(specialType) {
		// /*Boomer*/ case 2: return 1200.0;
		/*Charger*/ case 6: return 19500.0;
		/*Smoker*/ case 1: return 20000.0;
	
		default:
			return 12000.0;
	}
}

bool SpawnSpecialInFace(int target, int specialType) {
	if(specialType > 8) return false;
	static float pos[3], ang[3];
	static float testPos[3];
	testPos = pos;
	GetClientAbsOrigin(target, pos);
	GetClientEyeAngles(target, ang);
	if(specialType != 5 && specialType != 2) { //If not jockey/hunter find a suitable area that is at least 5 m away
		float minDistance = GetIdealMinDistance(specialType);
		GetHorizontalPositionFromOrigin(pos, ang, minDistance, testPos);
		if(!FindSuitablePosition(target, pos, testPos, minDistance, 100)) {
			L4D_GetRandomPZSpawnPosition(target, specialType, 10, testPos);
		}
		pos = testPos;
	} else { // Else spawn a little bit off, and above (above for jockeys)
		pos[2] += 10.0;
		pos[0] += 5.0;
	}
	pos[2] += 1.0;
	NegateVector(ang);

	return SpawnSpecialInternal(specialType, target, pos, NULL_VECTOR) > 0;
}

bool SpawnSpecialNear(int target, int specialType) {
	if(specialType > 8) return false;
	static float pos[3];
	if(L4D_GetRandomPZSpawnPosition(target, specialType, 10, pos)) {
		return SpawnSpecialInternal(specialType, target, pos, NULL_VECTOR) > 0;
	}
	return false;
}

// doesnt seem to work with l4dhooks methods
void BypassLimit() {
	int bot = CreateFakeClient("Infected Bot");
	if (bot != 0) {
		ChangeClientTeam(bot, 3);
		CreateTimer(0.1, Timer_KickBot, bot);
	}
}

int SpawnSpecialInternal(int type, int target, float pos[3], float ang[3]) {
	if(type <= 6) {
		// BypassLimit();
		int special = L4D2_SpawnSpecial(type, pos, ang);
		if(special != -1)
			g_iAttackerTarget[special] = GetClientUserId(target);
		return special;
	}
	else if(type == 7) {
		int witch = L4D2_SpawnWitch(pos, ang);
		if(witch != -1)
			SetWitchTarget(witch, target);
		return witch;
	}
	else if(type == 8) {
		// BypassLimit();
		int tank = L4D2_SpawnTank(pos, ang);
		if(tank <= 0 || !IsClientConnected(tank)) return -1;
		if(tank != -1)
			g_iAttackerTarget[tank] = GetClientUserId(target);
		return tank;
	}
	else return -1;
}