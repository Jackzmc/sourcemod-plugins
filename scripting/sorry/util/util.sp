// Creates an ArrayList of [count] integer numbers from [minValue] to [maxValue], with no duplicates
stock ArrayList CreateRandomSequence(int minValue, int maxValue, int count = 0) {
	ArrayList list = new ArrayList();
	if(count == 0)
		count = maxValue - minValue;
	int iterationsLeft = count * 2;
	if(count < 0) ThrowError("Min has to be less than Max");
	while(list.Length < count && iterationsLeft > 0) {
		int number = (GetURandomInt() % maxValue) + minValue;
		if(list.FindValue(number) == -1) {
			list.Push(number);
		}
		iterationsLeft--;
	}
	return list;
}

stock void CreateRagdoll(int client, const float vel[3]) {
	int Ragdoll = CreateEntityByName("cs_ragdoll");
	float fPos[3], fAng[3];
	GetClientAbsOrigin(client, fPos); 
	GetClientAbsAngles(client, fAng);
	
	TeleportEntity(Ragdoll, fPos, fAng, NULL_VECTOR);
	
	SetEntPropVector(Ragdoll, Prop_Send, "m_vecRagdollOrigin", fPos);
	SetEntProp(Ragdoll, Prop_Send, "m_nModelIndex", GetEntProp(client, Prop_Send, "m_nModelIndex"));
	SetEntProp(Ragdoll, Prop_Send, "m_iTeamNum", GetClientTeam(client));
	SetEntPropEnt(Ragdoll, Prop_Send, "m_hPlayer", client);
	SetEntProp(Ragdoll, Prop_Send, "m_iDeathPose", GetEntProp(client, Prop_Send, "m_nSequence"));
	SetEntProp(Ragdoll, Prop_Send, "m_iDeathFrame", GetEntProp(client, Prop_Send, "m_flAnimTime"));
	SetEntProp(Ragdoll, Prop_Send, "m_nForceBone", GetEntProp(client, Prop_Send, "m_nForceBone"));
	SetEntPropVector(Ragdoll, Prop_Send, "m_vecForce", vel);
	
	if (GetClientTeam(client) == 2)
	{
		SetEntProp(Ragdoll, Prop_Send, "m_ragdollType", 4);
		SetEntProp(Ragdoll, Prop_Send, "m_survivorCharacter", GetEntProp(client, Prop_Send, "m_survivorCharacter"));
	}
	else if (GetClientTeam(client) == 3)
	{
		int infclass = GetEntProp(client, Prop_Send, "m_zombieClass");
		// if (g_bRagdollLimit)
		// 	SetEntProp(Ragdoll, Prop_Send, "m_ragdollType", 1);
		if (infclass == 8)
			SetEntProp(Ragdoll, Prop_Send, "m_ragdollType", 3);
		else
			SetEntProp(Ragdoll, Prop_Send, "m_ragdollType", 2);
		SetEntProp(Ragdoll, Prop_Send, "m_zombieClass", infclass);
		
		int effect = GetEntPropEnt(client, Prop_Send, "m_hEffectEntity");
		if (effect != -1) {
			char effectclass[13]; 
			GetEntityClassname(effect, effectclass, sizeof(effectclass));
			if (strcmp(effectclass, "entityflame", false) == 0)
				SetEntProp(Ragdoll, Prop_Send, "m_bOnFire", 1);
		}
	}
	else
		SetEntProp(Ragdoll, Prop_Send, "m_ragdollType", 1);
	
	int prev_ragdoll = GetEntPropEnt(client, Prop_Send, "m_hRagdoll");
	if (!IsPlayerAlive(client) && prev_ragdoll == -1) {
		SetEntPropEnt(client, Prop_Send, "m_hRagdoll", Ragdoll);
	} else {
		SetVariantString("OnUser1 !self:Kill::1.0:-1");
		AcceptEntityInput(Ragdoll, "AddOutput");
		AcceptEntityInput(Ragdoll, "FireUser1");
	}
	
	DispatchSpawn(Ragdoll);
	ActivateEntity(Ragdoll);
}

/** 
 * Gets existing zombie or spawns new one in random area around survivor
*/
int GetRandomZombie(int survivor, float outPos[3], int tries = 5) {
	int zombie = 0; // GetRandomInfected();
	if(zombie == 0) {
		float curFlow = L4D2Direct_GetFlowDistance(survivor);
		float bounds = 25.0;
		do {
			GetRandomNearbyPos(curFlow, outPos, -bounds, bounds);
			// Don't spawn smoker (0) because they don't listen to the run away
			zombie = L4D2_SpawnSpecial(GetRandomInt(1, 6), outPos, NULL_VECTOR);
			tries--;
			bounds += 25.0;
		} while(tries > 0 && zombie <= 0);
	}
	return zombie;
}

/**	
 * Gets a random position centered around curFlow
 * @param curFlow the flow distance to center around
 * @param pos the output position
 * @param flowBehindMinDelta the lowest flow to accept from curFlow (curFlow + -flowBehindMinDelta) 
 * @param flowAheadMaxDelta the lowest flow to accept from curFlow (curFlow + flowAheadMaxDelta) 
 * @param flowMinAway a flow must be at least this far away from curFlow
 * @returns true if a random pos was found or false if not, pos to get
 */
bool GetRandomNearbyPos(float curFlow, float pos[3], float flowBehindMinDelta = -300.0, float flowAheadMaxDelta = 150.0, float flowMinAway = 20.0) {
	ArrayList navs = new ArrayList(); 
	L4D_GetAllNavAreas(navs);
	navs.Sort(Sort_Random, Sort_Integer);
	float flowBehindMin = curFlow + flowBehindMinDelta;
	float flowAheadMax = curFlow + flowAheadMaxDelta;
	bool result = false;
	// This finds the first nav area in range, usually closer
	for(int i = 0; i < navs.Length; i++) {
		float flow = L4D2Direct_GetTerrorNavAreaFlow(navs.Get(i));
		if(flow >= flowBehindMin && flow <= flowAheadMax && flow - curFlow >= flowMinAway) {
			L4D_FindRandomSpot(navs.Get(i), pos);
			result = true;
			break;
		}
	}
	delete navs;
	return result;
}

bool IsAllAdmins() {
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) == 2) {
			if(GetUserAdmin(i) == INVALID_ADMIN_ID) return false;
		}
	}
	return true;
}

int GetRandomRealPlayer(int ignore1, int ignore2) { 
	ArrayList arr = new ArrayList();
	for(int i = 1; i <= MaxClients; i++) {
		if(i != ignore1 && i != ignore2 && IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) == 2) {
			arr.Push(GetClientUserId(i));
		}
	}
	if(arr.Length == 0) return -1;
	int player = arr.Get(GetURandomInt() % (arr.Length - 1));
	delete arr;
	return GetClientOfUserId(player);
}

int SpawnPropAbovePlayer(int target, const char[] model, bool autoKill = true) {
	// float min[3] = { -30.0, -30.0, -2.0};
	// float max[3] = { 30.0, 30.0, 50.0 };
	float pos[3];
	float ang[3];
	float vel[3] = { 0.0, 0.0, -1000.0 };
	GetClientEyePosition(target, pos);
	GetClientEyeAngles(target, ang);
	pos[2] += 60.0;
	PrecacheModel(model);
	int id = CreateProp("prop_physics", model, pos, ang, vel);
	if(autoKill) CreateTimer(5.0, Timer_KillEntity, id);
	return id;
}

stock int GetNearestEntityMax(const char[] classname, float center[3], float maxDistance = 0.0) {
	int entity = -1;
	float smallestDist;
	float pos[3];
	int nearestEnt = -1;
	while((entity = FindEntityByClassname(entity, classname)) != INVALID_ENT_REFERENCE) {
		GetEntPropVector(entity, Prop_Send, "m_vecOrigin", pos);

		float dist = GetVectorDistance(center, pos);
		if((maxDistance <= 0 || dist < maxDistance) && dist < smallestDist || nearestEnt == -1) {
			smallestDist = dist;
			nearestEnt = entity;
		}
	}
	return nearestEnt;
}

stock bool GetCursorPosition(int client, float pos[3], float ang[3]) {
	GetClientEyePosition(client, pos);
	GetClientEyeAngles(client, ang);
	TR_TraceRayFilter(pos, ang, MASK_OPAQUE, RayType_Infinite, TraceFilter, client);
	if(TR_DidHit()) {
		TR_GetEndPosition(pos);
		return true;
	}
	return false;
}

// Returns startIndex if failed
stock int GetNextWeaponIndex(int client, int maxSlots = 5, int startIndex = 0) {
	int currentWeapon = -1;
	int lastIndex = startIndex;
	int index = startIndex;
	do {
		index++;
		if(index == maxSlots) {
			index = 0;
		}
		currentWeapon = GetPlayerWeaponSlot(client, index);
	} while(currentWeapon == -1 && index != lastIndex);
	if(currentWeapon == -1) index = startIndex;
	return index;
}
Address FindNearestNav(int client, int targetAttrs) {
	ArrayList navs = new ArrayList();
	L4D_GetAllNavAreas(navs);
	navs.Sort(Sort_Random, Sort_Integer);
	float clientFlow = L4D2Direct_GetFlowDistance(client);
	float nearestDistance;
	Address nearestNav = Address_Null;
	// This finds the first nav area  in range, usually closer
	for(int i = 0; i < navs.Length; i++) {
		Address nav = navs.Get(i);
		int attributes = L4D_GetNavArea_SpawnAttributes(nav);
		if(attributes & targetAttrs) {
			float flow = L4D2Direct_GetTerrorNavAreaFlow(nav);
			float flowDiff = FloatAbs(clientFlow - flow);
			if(flowDiff < nearestDistance || nearestNav == Address_Null) {
				nearestDistance = flowDiff;
				nearestNav = nav;
			}
		}
		
	}
	delete navs;
	return nearestNav;
}
stock bool GetGroundTopDown(int client, float vPos[3], float vAng[3]) {
	GetClientEyePosition(client, vPos);
	vAng = vPos;
	vAng[0] = 90.0;
	vPos[2] += 20.0;

	Handle trace = TR_TraceRayFilterEx(vPos, vAng, MASK_SHOT, RayType_Infinite, TraceFilter, client);
	if(!TR_DidHit(trace)) {
		delete trace;
		return false;
	}
	TR_GetEndPosition(vPos, trace);
	delete trace;

	GetClientAbsAngles(client, vAng);
	return true;
}
stock bool L4D_IsPlayerCapped(int client) {
	if(GetEntPropEnt(client, Prop_Send, "m_pummelAttacker") > 0 || 
		GetEntPropEnt(client, Prop_Send, "m_carryAttacker") > 0 || 
		GetEntPropEnt(client, Prop_Send, "m_pounceAttacker") > 0 || 
		GetEntPropEnt(client, Prop_Send, "m_jockeyAttacker") > 0 || 
		GetEntPropEnt(client, Prop_Send, "m_pounceAttacker") > 0 ||
		GetEntPropEnt(client, Prop_Send, "m_tongueOwner") > 0)
		return true;
	return false;
}
stock bool FindGround(const float start[3], float end[3]) {
	float angle[3];
	angle[0] = 90.0;

	Handle trace = TR_TraceRayEx(start, angle, MASK_SHOT, RayType_Infinite);
	if(!TR_DidHit(trace)) {
		delete trace;
		return false;
	}
	TR_GetEndPosition(end, trace);
	delete trace;
	return true;
}
stock int ClonePlayerActiveWeapon(int client) {
	int item = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	if(item > 0) return CloneWeapon(item);
	return -1;
}

stock int CloneWeapon(int weapon) {
	char classname[64];
	GetEntityClassname(weapon, classname, sizeof(classname));
	int entity = CreateEntityByName(classname);
	PrintToServer("cloned weapon %d (%s) -> %d", weapon, classname, entity);
	if(StrEqual(classname, "weapon_melee")) {
		PrintToServer("cloned melee (%s)", classname);
		GetEntPropString(weapon, Prop_Data, "m_strMapSetScriptName", classname, sizeof(classname));
		SetEntPropString(entity, Prop_Data, "m_strMapSetScriptName", classname);
	}
	DispatchSpawn(entity);
	return entity;
}