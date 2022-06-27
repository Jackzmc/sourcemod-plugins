
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


enum struct SpecialSpawnRequest {
	SpecialType type;
	int targetUserId;
	float position[3];
	float angle[3];
	int flags;
}

ArrayList g_spSpawnQueue;

// Finds position, sends to SpawnSpecialAtPosition
// target client index
stock bool SpawnSpecialForTarget(SpecialType specialType, int target, SpecialSpawnFlags spawnFlags = Special_Anywhere) {
	static float pos[3];
	int internalFlags = view_as<int>(SPI_AlwaysTarget);
	if(spawnFlags == Special_OnTarget) {
		static float ang[3];
		static float testPos[3];
		testPos = pos;

		GetClientAbsOrigin(target, pos);
		GetClientEyeAngles(target, ang);

		if(specialType == Special_Boomer || specialType == Special_Spitter) 
			internalFlags |= view_as<int>(SPI_KillOnSpawn);

		if(specialType == Special_Jockey || specialType == Special_Boomer || specialType == Special_Spitter) { // Else spawn a little bit off, and above (above for jockeys)
			pos[2] += 25.0;
			pos[0] += 5.0;
		} else { //If not jockey/hunter find a suitable area that is at least 5 m away
			float minDistance = GetIdealMinDistance(specialType);
			GetHorizontalPositionFromOrigin(pos, ang, minDistance, testPos);
			if(!FindSuitablePosition(pos, testPos, minDistance, 100)) {
				L4D_GetRandomPZSpawnPosition(target, view_as<int>(specialType), 10, testPos);
			}
			pos = testPos;
		} 
		pos[2] += 1.0;
		return SpawnSpecialAtPosition(specialType, pos, ang, target, internalFlags);
	} else {
		if(L4D_GetRandomPZSpawnPosition(target, view_as<int>(specialType), 10, pos)) {
			return SpawnSpecialAtPosition(specialType, pos, NULL_VECTOR, target, internalFlags);
		}
	}
	return false;
}

// Target is optional
stock bool SpawnSpecialAtPosition(SpecialType special, const float destination[3], const float angle[3], int target = 0, int flags = 0) {
	SpecialSpawnRequest request;
	request.type = special;
	if(target)
		request.targetUserId = GetClientUserId(target);
	request.flags = flags;
	request.position = destination;
	request.angle = angle;
	g_spSpawnQueue.PushArray(request);
	if(!spIsActive) ProcessSpecialQueue();
	return true;
}

SpecialSpawnRequest spActiveRequest;

// On spawn, keep id
// timer checks if passed id still == kept id, if so, it failed. 
int g_iSpId;

bool ProcessSpecialQueue() {
	if(g_spSpawnQueue.Length > 0) {
		if(g_spSpawnQueue.GetArray(0, spActiveRequest, sizeof(spActiveRequest))) {
			spIsActive = true;
			CreateTimer(4.0, Timer_CheckSpecialSpawned, g_iSpId);
		}
		g_spSpawnQueue.Erase(0);

		int target = GetClientOfUserId(spActiveRequest.targetUserId);
		if(view_as<int>(spActiveRequest.type) <= 6) {
			// CreateTimer(2.0, Timer_CheckSpecialSpawn, spCurrentId);
			int bot = CreateFakeClient("FTTSpecialBot");
			if (bot != 0) {
				ChangeClientTeam(bot, 3);
				CreateTimer(0.1, Timer_KickBot, bot);
			}
			CheatCommand(target, "z_spawn_old", SPECIAL_NAMES[view_as<int>(spActiveRequest.type) - 1], "auto");
		} else if(spActiveRequest.type == Special_Witch) {
			int witch = L4D2_SpawnWitch(spActiveRequest.position, spActiveRequest.angle);
			if(witch != -1)
				SetWitchTarget(witch, target);
			return ProcessSpecialQueue();
		} else if(spActiveRequest.type == Special_Tank) {
			// BypassLimit();
			int tank = L4D2_SpawnTank(spActiveRequest.position, spActiveRequest.angle);
			if(tank > 0 && IsClientConnected(tank))
				pdata[tank].attackerTargetUid = spActiveRequest.targetUserId;
			return ProcessSpecialQueue();
		}
		return true;
	}
	spIsActive = false;
	return false;
}

stock SpecialType GetSpecialType(const char[] input) {
	for(int i = 0; i < 8; i++) {
		if(strcmp(SPECIAL_NAMES[i], input, false) == 0) return view_as<SpecialType>(i + 1);
	}
	return Special_Invalid;
}

stock bool FindSuitablePosition(const float pos[3], float outputPos[3], float minDistance = 19000.0, int tries = 100) {
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
		case Special_Charger: return 19510.0;
		case Special_Smoker: return 20000.0;
		case Special_Spitter: return 15000.0;
		default:
			return 12000.0;
	}
}

stock bool GetGroundBehind(int client, float vPos[3], float vAng[3]) {
	GetClientEyePosition(client, vPos);
	GetClientEyeAngles(client, vAng);
	vAng[1] -= 180.0; //Flip to behind
	vAng[2] = 35.0; //Angle downwards
	// vPos[2] -= 500.0;
	float minmax[3] = { 35.0, 35.0, 32.0 };
	Handle trace = TR_TraceHullFilterEx(vPos, vAng, minmax, minmax, MASK_SOLID, RayFilter_NonClient);
	if(!TR_DidHit(trace)) {
		delete trace;
		return false;
	}
	TR_GetEndPosition(vPos, trace);
	vPos[2] += 32.0;
	// FindSuitablePosition(vPos, vPos, 100.0, 100);
	delete trace;

	GetClientAbsAngles(client, vAng);
	return true;
}

stock bool RayFilter_NonClient(int entity, int contentsMask) {
	if (entity < 1 || entity > MaxClients) {
		if (IsValidEntity(entity)) {
			static char eClass[128];
			if (GetEntityClassname(entity, eClass, sizeof(eClass))) {
				if (strcmp(eClass, "prop_physics") >= 0)
					return false;
			}
			return true;
		}
	}
	return false;
}