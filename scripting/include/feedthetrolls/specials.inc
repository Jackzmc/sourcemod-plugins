char SPECIAL_NAMES[][] = {
	"Smoker", "Boomer", "Hunter", "Spitter", "Jockey", "Charger", "Witch"
};

stock int GetSpecialType(const char[] input) {
	for(int i = 0; i < sizeof(SPECIAL_NAMES); i++) {
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
		/*Charger*/ case 6: return 19000.0;
		/*Smoker*/ case 1: return 20000.0;
	
		default:
			return 12000.0;
	}
}

bool SpawnSpecialInFace(int target, int specialType) {
	if(specialType >= sizeof(SPECIAL_NAMES)) return false;
	static float pos[3], ang[3];
	static float testPos[3];
	testPos = pos;
	GetClientAbsOrigin(target, pos);
	GetClientEyeAngles(target, ang);
	if(specialType != 5 && specialType != 2) { //If charger/hunter, find a suitable area that is at least 5 m away
		float minDistance = GetIdealMinDistance(specialType);
		GetHorizontalPositionFromOrigin(pos, ang, minDistance, testPos);
		FindSuitablePosition(target, pos, testPos, minDistance, 100);
		pos = testPos;
	} else { // Else spawn a little bit off, and above (above for jockeys)
		pos[2] += 10.0;
		pos[0] += 5.0;
	}
	pos[2] += 1.0;
	NegateVector(ang);
	int special = (specialType == 7) ? L4D2_SpawnWitch(pos, ang) : L4D2_SpawnSpecial(specialType, pos, ang);
	if(special == -1) return false;

	if(specialType == 7) 
		SetWitchTarget(special, target);
	else 
		g_iAttackerTarget[special] = GetClientUserId(target);

	if(specialType == 2) { //Kill boomer
		ForcePlayerSuicide(special);
	}
	return true;
}

bool SpawnSpecialNear(int target, int specialType) {
	if(specialType >= sizeof(SPECIAL_NAMES)) return false;
	static float pos[3];
	if(L4D_GetRandomPZSpawnPosition(target, specialType, 10, pos)) {
		int special = (specialType == 7) ? L4D2_SpawnWitch(pos, ZERO_VECTOR) : L4D2_SpawnSpecial(specialType, pos, ZERO_VECTOR);
		if(special == -1) return false;
		if(specialType == 7) 
			SetWitchTarget(special, target);
		else 
			g_iAttackerTarget[special] = GetClientUserId(target);
		return true;
	}
	return false;
}