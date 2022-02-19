char SPECIAL_NAMES[][] = {
	"Smoker", "Boomer", "Hunter", "Spitter", "Jockey", "Charger", "Witch", "Tank"
};
enum SpecialType {
	Special_Invalid = -1,
	Special_Smoker = 0,
	Special_Boomer,
	Special_Hunter,
	Special_Spitter,
	Special_Jockey,
	Special_Charger,
	Special_Witch,
	Special_Tank
}

stock SpecialType GetSpecialType(const char[] input) {
	for(int i = 0; i < 8; i++) {
		if(strcmp(SPECIAL_NAMES[i], input, false) == 0) return view_as<SpecialType>(i + 1);
	}
	return Special_Invalid;
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

float GetIdealMinDistance(SpecialType specialType) {
	switch(specialType) {
		// /*Boomer*/ case 2: return 1200.0;
		/*Charger*/ case 6: return 19500.0;
		/*Smoker*/ case 1: return 20000.0;
	
		default:
			return 12000.0;
	}
}

bool SpawnSpecialInFace(int target, SpecialType specialType) {
	static float pos[3], ang[3];
	static float testPos[3];
	testPos = pos;
	GetClientAbsOrigin(target, pos);
	GetClientEyeAngles(target, ang);
	if(specialType == Special_Boomer) 
		gInstaSpecialInstaKill = true;
	if(specialType != Special_Jockey && specialType != Special_Hunter) { //If not jockey/hunter find a suitable area that is at least 5 m away
		float minDistance = GetIdealMinDistance(specialType);
		GetHorizontalPositionFromOrigin(pos, ang, minDistance, testPos);
		if(!FindSuitablePosition(target, pos, testPos, minDistance, 100)) {
			L4D_GetRandomPZSpawnPosition(target, view_as<int>(specialType), 10, testPos);
		}
		pos = testPos;
	} else { // Else spawn a little bit off, and above (above for jockeys)
		pos[2] += 10.0;
		pos[0] += 5.0;
	}
	pos[2] += 1.0;
	NegateVector(ang);

	return SpawnSpecialInternal(specialType, target, pos, NULL_VECTOR) != -1;
}

bool SpawnSpecialNear(int target, SpecialType type) {
	gInstaSpecialInstaKill = false;
	static float pos[3];
	if(L4D_GetRandomPZSpawnPosition(target, view_as<int>(type), 10, pos)) {
		return SpawnSpecialInternal(type, target, pos, NULL_VECTOR) != -1;
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

int SpawnSpecialInternal(SpecialType type, int target, float pos[3], float ang[3]) {
	if(view_as<int>(type) <= 6) {
		// Bypass limit:
		gInstaSpecialType = view_as<int>(type);
		gInstaSpecialTarget = GetClientUserId(target);
		gInstaSpecialSpawnPos = pos;
		gInstaSpecialSpawnAng = pos;
		CreateTimer(2.0, Timer_InstaFailed);
		int bot = CreateFakeClient("ManualDirectorBot");
		if (bot != 0) {
			ChangeClientTeam(bot, 3);
			CreateTimer(0.1, Timer_KickBot, bot);
		}
		CheatCommand(target, "z_spawn_old", SPECIAL_NAMES[view_as<int>(type) = -1], "auto");
		return 0;
	}
	else if(type == Special_Witch) {
		int witch = L4D2_SpawnWitch(pos, ang);
		if(witch != -1)
			SetWitchTarget(witch, target);
		return witch;
	}
	else if(type == Special_Tank) {
		// BypassLimit();
		int tank = L4D2_SpawnTank(pos, ang);
		if(tank <= 0 || !IsClientConnected(tank)) return -1;
		if(tank != -1)
			g_iAttackerTarget[tank] = GetClientUserId(target);
		return tank;
	}
	else return -1;
}

stock bool GetGroundBehind(int client, float vPos[3], float vAng[3]) {
	GetClientAbsOrigin(client, vPos);
	vAng = vPos;
	vAng[2] += 5.0;
	vPos[2] -= 500.0;

	Handle trace = TR_TraceRayFilterEx(vAng, vPos, MASK_SHOT, RayType_EndPoint, RayFilter_NonClient);
	if(!TR_DidHit(trace)) {
		delete trace;
		return false;
	}
	TR_GetEndPosition(vPos, trace);
	delete trace;

	GetClientAbsAngles(client, vAng);
	return true;
}

stock bool RayFilter_NonClient(int entity, int contentsMask) {
	return entity > MaxClients;
}