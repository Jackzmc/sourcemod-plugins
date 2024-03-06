
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
stock bool SpawnSpecialForTarget(SpecialType specialType, int target, int spawnFlags = view_as<int>(Special_Anywhere)) {
	static float pos[3];
	
	if(spawnFlags & view_as<int>(Special_OnTarget)) {
		static float ang[3];
		static float testPos[3];
		testPos = pos;

		GetClientAbsOrigin(target, pos);
		GetClientEyeAngles(target, ang);

		if(specialType == Special_Jockey || specialType == Special_Boomer || specialType == Special_Spitter) { // Else spawn a little bit off, and above (above for jockeys)
			pos[2] += 25.0;
			pos[0] += 5.0;
		} else { //If not jockey/hunter find a suitable area that is at least 5 m away
			float minDistance = GetIdealMinDistance(specialType);
			GetHorizontalPositionFromOrigin(pos, ang, minDistance, testPos);
			if(!FindSuitablePosition(pos, testPos, minDistance, 100)) {
				PrintToServer("[FTT] Could not find suitable position, trying in front");
				GetHorizontalPositionFromOrigin(pos, ang, -minDistance, testPos);
				if(!FindSuitablePosition(pos, testPos, minDistance, 50)) {
					PrintToServer("[FTT] Could not find suitable position, falling back");
					if(spawnFlags & view_as<int>(Special_SpawnDirectOnFailure))
						GetClientAbsOrigin(target, testPos);
					else
						L4D_GetRandomPZSpawnPosition(target, view_as<int>(specialType), 10, testPos);
				}
			}
			pos = testPos;
		} 
		pos[2] += 1.0;
		return SpawnSpecialAtPosition(specialType, pos, ang, target, spawnFlags);
	}
	// Spawn via director, or fail
	if(!L4D_GetRandomPZSpawnPosition(target, view_as<int>(specialType), 10, pos)) {
		if(spawnFlags & view_as<int>(Special_SpawnDirectOnFailure))
			GetClientAbsOrigin(target, pos);
		else
			return false;
	} 
	return SpawnSpecialAtPosition(specialType, pos, NULL_VECTOR, target, spawnFlags);
}

// Target is optional
stock bool SpawnSpecialAtPosition(SpecialType specialType, const float destination[3], const float angle[3], int target = 0, int spawnFlags = 0) {
	int internalFlags = 0;
	if(spawnFlags & view_as<int>(Special_AlwaysTarget)) {
		internalFlags |= view_as<int>(SPI_AlwaysTarget);
	}
	if(spawnFlags & view_as<int>(Special_KillOnIncap)) {
		internalFlags |= view_as<int>(SPI_KillOnTargetIncap);
	}
	if(spawnFlags & view_as<int>(Special_OnTarget)) {
		if(specialType == Special_Boomer || specialType == Special_Spitter) 
			internalFlags |= view_as<int>(SPI_KillOnSpawn);
	}
	SpecialSpawnRequest request;
	request.type = specialType;
	if(target)
		request.targetUserId = GetClientUserId(target);
	request.flags = internalFlags;
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
			CreateTimer(2.0, Timer_CheckSpecialSpawned, g_iSpId);
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
			return true;
		} else if(spActiveRequest.type == Special_Witch) {
			int witch = L4D2_SpawnWitch(spActiveRequest.position, spActiveRequest.angle);
			DataPack pack;
			CreateDataTimer(0.2, Timer_SetWitchTarget, pack);
			pack.WriteCell(witch);
			pack.WriteCell(spActiveRequest.targetUserId);
			if(witch != -1)
				SetWitchTarget(witch, target);
			spIsActive = false;
			return ProcessSpecialQueue();
		} else if(spActiveRequest.type == Special_Tank) {
			// BypassLimit();
			int tank = L4D2_SpawnTank(spActiveRequest.position, spActiveRequest.angle);
			if(tank > 0 && IsClientConnected(tank)) {
				TeleportEntity(tank, spActiveRequest.position, spActiveRequest.angle, NULL_VECTOR);
				pdata[tank].attackerTargetUid = spActiveRequest.targetUserId;
				pdata[tank].specialAttackFlags = view_as<int>(SPI_AlwaysTarget);
			}
			spIsActive = false;
			return ProcessSpecialQueue();
		}
		return false;
	}
	spIsActive = false;
	return false;
}

Action Timer_SetWitchTarget(Handle h, DataPack pack) {
	pack.Reset();
	int witch = pack.ReadCell();
	int target = GetClientOfUserId(pack.ReadCell());
	if(IsValidEntity(witch) && target > 0) {
		SetWitchTarget(witch, target);
	}
	return Plugin_Handled;
}

stock SpecialType GetSpecialType(const char[] input) {
	if(StrEqual(input, "random")) {
		return view_as<SpecialType>(GetRandomInt(0, 6))
	}
	for(int i = 0; i < 8; i++) {
		if(strcmp(SPECIAL_NAMES[i], input, false) == 0) return view_as<SpecialType>(i + 1);
	}
	return Special_Invalid;
}

stock bool FindSuitablePosition(const float pos[3], float outputPos[3], float minDistance = 19000.0, int tries = 100) {
	outputPos = pos;
	for(int i = tries; i > 0; i--) {
		// Shift position aroudn randomly
 		outputPos[1] += GetRandomFloat(-35.0, 35.0);
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
		case Special_Tank: return 20000.0;
		case Special_Spitter: return 15000.0;
		default:
			return 12000.0;
	}
}

static float TARGET_GROUND_BOUNDS[3] = { 35.0, 35.0, 32.0 };

stock bool GetGroundBehind(int client, float vPos[3], float vAng[3]) {
	GetClientEyePosition(client, vPos);
	GetClientEyeAngles(client, vAng);
	vAng[1] -= 180.0; //Flip to behind
	vAng[2] = 35.0; //Angle downwards
	// vPos[2] -= 500.0;
	Handle trace = TR_TraceHullFilterEx(vPos, vAng, TARGET_GROUND_BOUNDS, TARGET_GROUND_BOUNDS, MASK_SOLID, RayFilter_NonClient);
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
	if (entity <= 0 || entity > MaxClients) {
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