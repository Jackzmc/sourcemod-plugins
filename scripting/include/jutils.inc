#if defined _jutils_included
	#endinput
#endif
#define _jutils_included

#define MODEL_FRANCIS		"models/survivors/survivor_biker.mdl"
#define MODEL_LOUIS			"models/survivors/survivor_manager.mdl"
#define MODEL_ZOEY			"models/survivors/survivor_teenangst.mdl"
#define MODEL_BILL			"models/survivors/survivor_namvet.mdl"
#define MODEL_NICK			"models/survivors/survivor_gambler.mdl"
#define MODEL_COACH			"models/survivors/survivor_coach.mdl"
#define MODEL_ELLIS			"models/survivors/survivor_mechanic.mdl"
#define MODEL_ROCHELLE		"models/survivors/survivor_producer.mdl"
#define MODEL_MINIGUN		"models/w_models/weapons/w_minigun.mdl"

/** Gets a location horizontally X units away from the origin point. Ignores Z-axis. 
  * @noreturn
  */
stock void GetHorizontalPositionFromOrigin(const float pos[3], const float ang[3], float units, float finalPosition[3]) {
	float theta = DegToRad(ang[1]);
	finalPosition[0] = units * Cosine(theta) + pos[0];
	finalPosition[1] = units * Sine(theta) + pos[1];
	finalPosition[2] = pos[2];
}
stock void GetHorizontalPositionFromClient(int client, float units, float finalPosition[3]) {
	float pos[3], ang[3];
	GetClientEyeAngles(client, ang);
	GetClientAbsOrigin(client, pos);

	float theta = DegToRad(ang[1]);
	pos[0] += units * Cosine(theta); 
	pos[1] += units * Sine(theta); 
	finalPosition = pos;
}
stock void GetOffsetPosition(float pos[3], const float ang[3], float forwardBack, float leftRight, float upDown) {
	float theta = DegToRad(ang[1]);
	pos[0] = forwardBack * Cosine(theta) + pos[0];
	pos[1] = forwardBack * Sine(theta) + pos[1];
	pos[2] = pos[2] + upDown;
}
 // Gets velocity of an entity (ent) toward new origin with speed (fSpeed) - thanks Ryan
 stock bool GetVelocityToOrigin(int entity, const float destination[3], const float fSpeed, float outVelocity[3]) {
	float srcOrigin[3];
	GetEntPropVector(entity, Prop_Data, "m_vecVelocity", srcOrigin);
	// Velocity = Distance / Time

	float fDistance[3];
	fDistance[0] = destination[0] - srcOrigin[0];
	fDistance[1] = destination[1] - srcOrigin[1];
	fDistance[2] = destination[2] - srcOrigin[2];

	float fTime = (GetVectorDistance(srcOrigin, destination) / fSpeed);

	outVelocity[0] = (destination[0] - srcOrigin[0]) / fTime;
	outVelocity[1] = (destination[1] - srcOrigin[1]) / fTime;
	outVelocity[2] = (destination[2] - srcOrigin[2]) / fTime;

	return (outVelocity[0] && outVelocity[1] && outVelocity[2]);
 }

//Credits to Timocop for the stock :D
/**
* Runs a single line of vscript code.
* NOTE: Dont use the "script" console command, it starts a new instance and leaks memory. Use this instead!
*
* @param sCode		The code to run.
* @noreturn
*/
stock void L4D2_RunScript(const char[] sCode, any ...) {
	static int iScriptLogic = INVALID_ENT_REFERENCE;
	if(iScriptLogic == INVALID_ENT_REFERENCE || !IsValidEntity(iScriptLogic)) {
		iScriptLogic = EntIndexToEntRef(CreateEntityByName("logic_script"));
		if(iScriptLogic == INVALID_ENT_REFERENCE|| !IsValidEntity(iScriptLogic))
			SetFailState("Could not create 'logic_script'");
		
		DispatchSpawn(iScriptLogic);
	}
	
	static char sBuffer[512];
	VFormat(sBuffer, sizeof(sBuffer), sCode, 2);
	
	SetVariantString(sBuffer);
	AcceptEntityInput(iScriptLogic, "RunScriptCode");
}
stock void ShowDelayedHintToAll(const char[] format, any ...) {
	char buffer[254];
	VFormat(buffer, sizeof(buffer), format, 2);
	static int hintInt = 0;
	if(hintInt >= 7) {
		PrintHintTextToAll("%s",buffer);
		hintInt = 0;
	}
	hintInt++;
}

stock int GetSurvivorId(const char[] str, bool isL4D1 = false) {
	int possibleNumber = StringToInt(str, 10);
	if(strlen(str) == 1) {
		if(possibleNumber <= 7 && possibleNumber >= 0) {
			return possibleNumber;
		}
	}else if(possibleNumber == 0) {
		int survivorId;
		char s = CharToLower(str[0]);
		if(s == 'b') {
			survivorId = isL4D1 ? 0 : 4;
		} else if(s == 'z') {
			survivorId = isL4D1 ? 1 : 5;
		} else if(s == 'l') {
			survivorId = isL4D1 ? 2 : 7;
		} else if(s == 'f') {
			survivorId = isL4D1 ? 3 : 6;
		} else if(s == 'n') {
			survivorId = 0;
		} else if(s == 'r') {
			survivorId = 1;
		} else if(s == 'e') {
			survivorId = 3;
		} else if(s == 'c') {
			survivorId = 2;
		}
		return survivorId;
	}
	return -1;
}
stock int GetL4D2SurvivorId(const char str[16]) {
	int possibleNumber = StringToInt(str, 10);
	if(strlen(str) == 1) {
		if(possibleNumber <= 7 && possibleNumber >= 0) {
			return possibleNumber;
		}
	}else if(possibleNumber == 0) {
		if(StrEqual(str, "nick", false)) return 0;
		else if(StrEqual(str, "rochelle", false)) return 1;
		else if(StrEqual(str, "coach", false)) return 2;
		else if(StrEqual(str, "ellis", false)) return 3;
		else if(StrEqual(str, "bill", false)) return 0;
		else if(StrEqual(str, "zoey", false)) return 5;
		else if(StrEqual(str, "francis", false)) return 3;
		else if(StrEqual(str, "louis", false)) return 2;
	}
	return -1;
}
stock bool GetSurvivorModel(int character, char[] model, int modelStrSize) {
	switch(character) {
		case 0: strcopy(model, modelStrSize, MODEL_NICK);
		case 1: strcopy(model, modelStrSize, MODEL_ROCHELLE);
		case 2: strcopy(model, modelStrSize, MODEL_COACH);
		case 3: strcopy(model, modelStrSize, MODEL_ELLIS);
		case 4: strcopy(model, modelStrSize, MODEL_BILL);
		case 5: strcopy(model, modelStrSize, MODEL_ZOEY);
		case 6: strcopy(model, modelStrSize, MODEL_FRANCIS);
		case 7: strcopy(model, modelStrSize, MODEL_LOUIS);
		default: return false;
	}
	return true;
}
stock bool FindSurvivorModel(const char str[16], char[] model, int modelStrSize) {
	int possibleNumber = StringToInt(str, 10);
	if(strlen(str) == 1 && possibleNumber <= 7 && possibleNumber >= 0) {
		switch(possibleNumber) {
			case 0: strcopy(model, modelStrSize, MODEL_NICK);
			case 1: strcopy(model, modelStrSize, MODEL_ROCHELLE);
			case 2: strcopy(model, modelStrSize, MODEL_COACH);
			case 3: strcopy(model, modelStrSize, MODEL_ELLIS);
			case 4: strcopy(model, modelStrSize, MODEL_BILL);
			case 5: strcopy(model, modelStrSize, MODEL_ZOEY);
			case 6: strcopy(model, modelStrSize, MODEL_FRANCIS);
			case 7: strcopy(model, modelStrSize, MODEL_LOUIS);
			default: return false;
		}
		return true;
	}else{
		if(possibleNumber == 0) {
			//try to parse str
			if(StrEqual(str, "bill", false)) 
				strcopy(model, modelStrSize, MODEL_BILL);
			else if(StrEqual(str, "zoey", false)) 
				strcopy(model, modelStrSize, MODEL_ZOEY);
			else if(StrEqual(str, "francis", false)) 
				strcopy(model, modelStrSize, MODEL_FRANCIS);
			else if(StrEqual(str, "louis", false)) 
				strcopy(model, modelStrSize, MODEL_LOUIS);
			else if(StrEqual(str, "nick", false)) 
				strcopy(model, modelStrSize, MODEL_NICK);
			else if(StrEqual(str, "ellis", false)) 
				strcopy(model, modelStrSize, MODEL_ELLIS);
			else if(StrEqual(str, "rochelle", false)) 
				strcopy(model, modelStrSize, MODEL_ROCHELLE);
			else if(StrEqual(str, "coach", false)) 
				strcopy(model, modelStrSize, MODEL_COACH);
			else
				return false;
			return true;
		}
	}
	return false;
}
//returns true if model found
stock bool GetSurvivorName(int client, char[] buffer, int length) {

	char modelName[38];
	GetClientModel(client, modelName, sizeof(modelName));
	if(StrContains(modelName,"biker",false) > -1) {
		strcopy(buffer, length, "Francis"); 
	}else if(StrContains(modelName,"teenangst",false) > -1) {
		strcopy(buffer, length, "Zoey"); 
	}else if(StrContains(modelName,"namvet",false) > -1) {
		strcopy(buffer, length, "Bill"); 
	}else if(StrContains(modelName,"manager",false) > -1) {
		strcopy(buffer, length, "Louis"); 
	}else if(StrContains(modelName,"coach",false) > -1) {
		strcopy(buffer, length, "Coach"); 
	}else if(StrContains(modelName,"producer",false) > -1) {
		strcopy(buffer, length, "Rochelle"); 
	}else if(StrContains(modelName,"gambler",false) > -1) {
		strcopy(buffer, length, "Nick"); 
	}else if(StrContains(modelName,"mechanic",false) > -1) {
		strcopy(buffer, length, "Ellis"); 
	}else{
		return false;
	}
	return true;
}

stock int GetSurvivorType(const char[] modelName) {
	if(StrContains(modelName,"biker",false) > -1) {
		return 6;
	}else if(StrContains(modelName,"teenangst",false) > -1) {
		return 5;
	}else if(StrContains(modelName,"namvet",false) > -1) {
		return 4;
	}else if(StrContains(modelName,"manager",false) > -1) {
		return 7;
	}else if(StrContains(modelName,"coach",false) > -1) {
		return 2;
	}else if(StrContains(modelName,"producer",false) > -1) {
		return 1;
	}else if(StrContains(modelName,"gambler",false) > -1) {
		return 0;
	}else if(StrContains(modelName,"mechanic",false) > -1) {
		return 3;
	}else{
		return false;
	}
}
stock bool TraceFilter(int entity, int contentsMask) {
	if( entity <= MaxClients )
		return false;
	return true;
}
stock bool GetGround(int client, float vPos[3], float vAng[3]) {
	GetClientAbsOrigin(client, vPos);
	vAng = vPos;
	vAng[2] += 5.0;
	vPos[2] -= 500.0;

	Handle trace = TR_TraceRayFilterEx(vAng, vPos, MASK_SOLID, RayType_EndPoint, TraceFilter);
	if(!TR_DidHit(trace)) {
		delete trace;
		return false;
	}
	TR_GetEndPosition(vPos, trace);
	delete trace;

	GetClientAbsAngles(client, vAng);
	return true;
}
//Taken from https://forums.alliedmods.net/showthread.php?p=1741099
stock bool SpawnMinigun(const float vPos[3], const float vAng[3]) {
	float vDir[3], newPos[3];
	GetAngleVectors(vAng, vDir, NULL_VECTOR, NULL_VECTOR);
	vDir[0] = vPos[0] + (vDir[0] * 50);
	vDir[1] = vPos[1] + (vDir[1] * 50);
	vDir[2] = vPos[2] + 20.0;
	newPos = vDir;
	newPos[2] -= 40.0;

	Handle trace = TR_TraceRayFilterEx(vDir, newPos, MASK_SHOT, RayType_EndPoint, TraceFilter);
	if(TR_DidHit(trace)) {
		TR_GetEndPosition(vDir, trace);

		int minigun = CreateEntityByName("prop_mounted_machine_gun");
		minigun = EntIndexToEntRef(minigun);
		SetEntityModel(minigun, MODEL_MINIGUN);
		DispatchKeyValue(minigun, "targetname", "louis_holdout");
		DispatchKeyValueFloat(minigun, "MaxPitch", 360.00);
		DispatchKeyValueFloat(minigun, "MinPitch", -360.00);
		DispatchKeyValueFloat(minigun, "MaxYaw", 90.00);
		newPos[2] += 0.1;
		TeleportEntity(minigun, vDir, vAng, NULL_VECTOR);
		DispatchSpawn(minigun);
		delete trace;
		return true;
	}else{
		LogError("Spawn minigun trace failure");
		delete trace;
		return false;
	}
}

stock int GiveClientWeaponLasers(int client, const char[] wpnName) {
	int entity = GiveClientWeapon(client, wpnName);
	if(entity != -1) {
		SetEntProp(entity, Prop_Send, "m_upgradeBitVec", 4);
	}
	return entity;
}

stock int GiveClientWeapon(int client, const char[] wpnName) {
	static char sTemp[64];
	float pos[3];
	GetClientAbsOrigin(client, pos);
	Format(sTemp, sizeof(sTemp), "weapon_%s", wpnName);

	int entity = CreateEntityByName(sTemp);
	if( entity != -1 ) {
		DispatchSpawn(entity);
		TeleportEntity(entity, pos, NULL_VECTOR, NULL_VECTOR);

		EquipPlayerWeapon(client, entity);
		return entity;
	}else{
		return -1;
	}
}
stock int GetNearestEntity(int client, char[] classname)
{
	int nearestEntity = -1;
	float clientVecOrigin[3], entityVecOrigin[3];
	
	//Get the distance between the first entity and client
	float distance, nearestDistance = -1.0;
	
	//Find all the entity and compare the distances
	int entity = -1;
	while ((entity = FindEntityByClassname(entity, classname)) != -1)
	{
		GetEntPropVector(entity, Prop_Data, "m_vecOrigin", entityVecOrigin);
		distance = GetVectorDistance(clientVecOrigin, entityVecOrigin, true);
		
		if (distance < nearestDistance || nearestDistance == -1.0)
		{
			nearestEntity = entity;
			nearestDistance = distance;
		}
	}
	return nearestEntity;
}  

stock bool IsValidPlayer(int i) {
	return IsClientConnected(i) && IsClientInGame(i) && IsPlayerAlive(i);
}
stock bool IsValidTeamPlayer(int i, int team) {
	return IsValidPlayer(i) && GetClientTeam(i) == team;
}
stock int GetPrimaryAmmo(int client) {
	int weapon = GetPlayerWeaponSlot(client, 0);
	if(weapon > -1) 
		return GetEntProp(weapon, Prop_Send, "m_iClip1");
	else
		return -1;
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
//entity abs origin code from here
//http://forums.alliedmods.net/showpost.php?s=e5dce96f11b8e938274902a8ad8e75e9&p=885168&postcount=3
stock void GetEntityAbsOrigin(int entity, float origin[3]) {
	if (entity && IsValidEntity(entity)
	&& (GetEntSendPropOffs(entity, "m_vecOrigin") != -1)
	&& (GetEntSendPropOffs(entity, "m_vecMins") != -1)
	&& (GetEntSendPropOffs(entity, "m_vecMaxs") != -1))
	{
		float mins[3], maxs[3];
		GetEntPropVector(entity, Prop_Send, "m_vecOrigin", origin);
		GetEntPropVector(entity, Prop_Send, "m_vecMins", mins);
		GetEntPropVector(entity, Prop_Send, "m_vecMaxs", maxs);
		
		origin[0] += (mins[0] + maxs[0]) * 0.5;
		origin[1] += (mins[1] + maxs[1]) * 0.5;
		origin[2] += (mins[2] + maxs[2]) * 0.5;
	}
}
stock bool IsPrimaryWeapon(const char[] wpnName) {
	return StrContains(wpnName, "rifle") > -1 
		|| StrContains(wpnName, "smg") > -1 
		|| StrContains(wpnName, "weapon_grenade_launcher") > -1 
		|| StrContains(wpnName, "sniper") > -1
		|| StrContains(wpnName, "shotgun") > -1;
}
stock int GetClientWeaponEntIndex(int client, int slot) {
	if(slot >= 0 && slot <= 5) {
		int wpnRef = GetPlayerWeaponSlot(client, slot);
		if(wpnRef != -1) {
			int wpn = EntRefToEntIndex(wpnRef);
			if(wpn != INVALID_ENT_REFERENCE) {
				return wpn;
			}else{
				return -1;
			}
		}else{
			return -1;
		}
	}else{
		ThrowError("Slot must be a number between 0 and 5");
		return -1;
	}
}
stock int GetClientSecondaryWeapon(int client) {
	return GetClientWeaponEntIndex(client, 1);
}
stock bool GetClientWeaponName(int client, int slot, char[] name, int nameSize) {
	int wpn = GetClientWeaponEntIndex(client, slot);
	if(wpn > 0) {
		GetEntityClassname(wpn, name, nameSize);
		return true;
	}else{
		return false;
	}
}
stock bool GetClientWeaponNameSmart(int client, int slot, char[] name, int nameSize) {
	int wpn = GetPlayerWeaponSlot(client, slot);
	if(wpn > 0) {
		GetEntityClassname(wpn, name, nameSize);
		if(slot == 1 && StrEqual(name, "weapon_melee")) {
			GetEntPropString(wpn, Prop_Data, "m_strMapSetScriptName", name, nameSize);
		}
		return true;
	}
	return false;
}

stock int GetClientWeaponNameSmart2(int client, int slot, char[] name, int nameSize) {
	int wpn = GetPlayerWeaponSlot(client, slot);
	if(wpn > 0) {
		GetEntityClassname(wpn, name, nameSize);
		if(slot == 1 && StrEqual(name, "weapon_melee")) {
			GetEntPropString(wpn, Prop_Data, "m_strMapSetScriptName", name, nameSize);
		} else {
			Format(name, nameSize, "%s", name[7]);
		}
		return wpn;
	}
	return -1;
}


stock bool DoesClientHaveWeapon(int client, int slot, const char[] name) {
	char wpn[32];
	if(GetClientWeaponName(client, slot, wpn, sizeof(wpn))) {
		return StrEqual(wpn, name, false);
	}else{
		return false;
	}
}

stock bool DoesClientHaveMelee(int client) {
	int wpnEnt = GetClientSecondaryWeapon(client);
	if(wpnEnt > -1) {
		char wpn[16];
		GetEdictClassname(wpnEnt, wpn, sizeof(wpn));
		return StrEqual(wpn, "weapon_melee");
	}else{
		return false;
	}
}

stock bool IsValidClient(int client, int checkTeam = 0) {
	int team = checkTeam > 0 ? GetClientTeam(client) : 0;
	return IsClientConnected(client) && IsClientInGame(client) && IsPlayerAlive(client) && team == checkTeam; 
} 

stock bool IsClientInSightRange(int client, int target, float angle = 90.0, float distance = 0.0, bool heightcheck = true, bool negativeangle = false) {
	if(angle > 360.0 || angle < 0.0)
		ThrowError("Angle Max : 360 & Min : 0. %d isn't proper angle.", angle);
	else if(!IsValidClient(client))
		ThrowError("Client is not Alive.");
	else if(!IsValidClient(target))
		ThrowError("Target is not Alive.");
		
	float clientPos[3], targetPos[3], angleVector[3], targetVector[3], resultAngle, resultDistance;
	
	GetClientEyeAngles(client, angleVector);
	angleVector[0] = angleVector[2] = 0.0;
	GetAngleVectors(angleVector, angleVector, NULL_VECTOR, NULL_VECTOR);
	NormalizeVector(angleVector, angleVector);
	if(negativeangle)
		NegateVector(angleVector);

	GetClientAbsOrigin(client, clientPos);
	GetClientAbsOrigin(target, targetPos);
	if(heightcheck && distance > 0)
		resultDistance = GetVectorDistance(clientPos, targetPos);
	clientPos[2] = targetPos[2] = 0.0;
	MakeVectorFromPoints(clientPos, targetPos, targetVector);
	NormalizeVector(targetVector, targetVector);
	
	resultAngle = RadToDeg(ArcCosine(GetVectorDotProduct(targetVector, angleVector)));
	
	if(resultAngle <= angle/2)	
	{
		if(distance > 0)
		{
			if(!heightcheck)
				resultDistance = GetVectorDistance(clientPos, targetPos);
				
			return distance >= resultDistance;
		}
		else return true;
	}
	else return false;
}

/// Checks if entity is in sight of client. Angle is the FOV, distance to be squared
stock bool IsEntityInSightRange(int client, int target, float angle = 90.0, float distance = 0.0, bool heightcheck = true, bool negativeangle = false) {
	if(angle > 360.0 || angle < 0.0)
		ThrowError("Angle Max : 360 & Min : 0. %d isn't proper angle.", angle);
	else if(!IsClientConnected(client) || !IsClientInGame(client))
		ThrowError("Client is not Alive.");
	else if(target <= MaxClients || !IsValidEntity(target))
		ThrowError("Target is not valid entity.");


	float clientPos[3], targetPos[3], angleVector[3], targetVector[3], resultAngle, resultDistance;
	
	GetClientEyeAngles(client, angleVector);
	angleVector[0] = angleVector[2] = 0.0;
	GetAngleVectors(angleVector, angleVector, NULL_VECTOR, NULL_VECTOR);
	NormalizeVector(angleVector, angleVector);
	if(negativeangle)
		NegateVector(angleVector);

	GetClientAbsOrigin(client, clientPos);
	GetEntPropVector(target, Prop_Send, "m_vecOrigin", targetPos);
	if(heightcheck && distance > 0)
		resultDistance = GetVectorDistance(clientPos, targetPos, true);
	clientPos[2] = targetPos[2] = 0.0;
	MakeVectorFromPoints(clientPos, targetPos, targetVector);
	NormalizeVector(targetVector, targetVector);
	
	resultAngle = RadToDeg(ArcCosine(GetVectorDotProduct(targetVector, angleVector)));
	
	if(resultAngle <= angle/2)	
	{
		if(distance > 0)
		{
			if(!heightcheck)
				resultDistance = GetVectorDistance(clientPos, targetPos, true);
				
			return distance >= resultDistance;
		}
		else return true;
	}
	else return false;
}
stock void PrintChatToAdmins(const char[] format, any ...) {
	char buffer[254];
	VFormat(buffer, sizeof(buffer), format, 2);
	for(int i = 1; i < MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i)) {
			AdminId admin = GetUserAdmin(i);
			if(admin != INVALID_ADMIN_ID) {
				PrintToChat(i, "%s", buffer);
			}
		}
	}
	PrintToServer("%s", buffer);
}
#if defined _multicolors_included
stock void CPrintChatToAdmins(const char[] format, any ...) {
	char buffer[254];
	VFormat(buffer, sizeof(buffer), format, 2);
	for(int i = 1; i < MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i)) {
			AdminId admin = GetUserAdmin(i);
			if(admin != INVALID_ADMIN_ID) {
				CPrintToChat(i, "%s", buffer);
			}
		}
	}
	CPrintToServer("%s", buffer);
}
#endif
stock bool IsValidAdmin(int client, const char[] flags) {
	int ibFlags = ReadFlagString(flags);
	if ((GetUserFlagBits(client) & ibFlags) == ibFlags) {
		return true;
	}else if (GetUserFlagBits(client) & ADMFLAG_ROOT) {
		return true;
	}
	return false;
} 

stock float GetNearestEntityDistance(int originEntity, char[] classname) {
	float compareVec[3], entityVecOrigin[3];
	GetEntPropVector(originEntity, Prop_Send, "m_vecOrigin", compareVec);
	
	//Get the distance between the first entity and client
	float distance, nearestDistance = -1.0;
	
	int entity = -1, closest;
	while ((entity = FindEntityByClassname(entity, classname)) != -1)
	{
		GetEntPropVector(entity, Prop_Send, "m_vecOrigin", entityVecOrigin);
		distance = GetVectorDistance(compareVec, entityVecOrigin);
		// PrintDebug(DEBUG_SPAWNLOGIC, "Comparing %s (id %d) (%.2f,%.2f,%.2f) distance to entity %d (%.2f,%.2f,%.2f) is %.4f", classname, entity, entityVecOrigin[0], entityVecOrigin[1], entityVecOrigin[2], originEntity, compareVec[0], compareVec[1], compareVec[2], distance);
		
		if (distance < nearestDistance || nearestDistance == -1.0)
		{
			nearestDistance = distance;
			closest = entity;
		}
	}
	return closest > 0 ? nearestDistance : -1.0;
} 

stock int FindNearestEntityInRange(int originEntity, char[] classname, float range) {
	float compareVec[3], entityVecOrigin[3];
	GetEntPropVector(originEntity, Prop_Send, "m_vecOrigin", compareVec);
	
	//Get the distance between the first entity and client
	float distance, nearestDistance = -1.0;
	
	int entity = -1, closest = -1;
	while ((entity = FindEntityByClassname(entity, classname)) != -1) {
		GetEntPropVector(entity, Prop_Send, "m_vecOrigin", entityVecOrigin);
		distance = GetVectorDistance(compareVec, entityVecOrigin);
		
		if (distance <= range && (distance < nearestDistance || nearestDistance == -1.0)) {
			// PrintDebug(DEBUG_SPAWNLOGIC, "Comparing %s (id %d) (%.2f,%.2f,%.2f) distance to entity %d (%.2f,%.2f,%.2f) is %.4f", classname, entity, entityVecOrigin[0], entityVecOrigin[1], entityVecOrigin[2], originEntity, compareVec[0], compareVec[1], compareVec[2], distance);
			nearestDistance = distance;
			closest = entity;
		}
	}
	return closest;
} 

stock void MakeEntityGlow(int entity, const int color[3], float distance = 1500.0) {
	SetEntProp(entity, Prop_Send, "m_iGlowType", 3);
	SetEntProp(entity, Prop_Send, "m_nGlowRange", distance);
	SetEntProp(entity, Prop_Send, "m_glowColorOverride", color[0] + (color[1] * 256) + (color[2] * 65536));
}

//Unless I'm dumb, this does not exist
stock void StringToLower(char[] str) {
	int len = strlen(str);
	for(int i = 0; i < len; i++) {
		str[i] = CharToLower(str[i]);
	}
}
stock void StringToUpper(char[] str) {
	int len = strlen(str);
	for(int i = 0; i < len; i++) {
		str[i] = CharToUpper(str[i]);
	}
}

stock int GetRealClient(int client) {
	if(IsFakeClient(client)) {
		int realPlayer = GetClientOfUserId(GetEntProp(client, Prop_Send, "m_humanSpectatorUserID"));
		return realPlayer > 0 ? realPlayer : -1;
	}else{
		return client;
	}
}

stock int FindIdleBot(int client) {
	for(int i = 1; i <= MaxClients; i++ ) {
		if(IsClientConnected(i) && IsClientInGame(i) && HasEntProp(i, Prop_Send, "m_humanSpectatorUserID")) {
			int realPlayer = GetClientOfUserId(GetEntProp(i, Prop_Send, "m_humanSpectatorUserID"));
			if(realPlayer == client) {
				return i;
			}
		}
	}
	return -1;
}

stock void SetParent(int child, int parent) {
	SetVariantString("!activator");
	AcceptEntityInput(child, "SetParent", parent);
}

stock void SetParentAttachment(int child, const char[] attachment, bool withOffset = false) {
	SetVariantString(attachment);
	if(withOffset)
		AcceptEntityInput(child, "SetParentAttachmentMaintainOffset");
	else
		AcceptEntityInput(child, "SetParentAttachment");
}

stock void ClearParent(int child) {
	AcceptEntityInput(child, "ClearParent");
}

stock void GetForwardVector(float vPos[3], float vAng[3], float vReturn[3], float fDistance) {
	float vDir[3];
	GetAngleVectors(vAng, vDir, NULL_VECTOR, NULL_VECTOR);
	ScaleVector(vDir, fDistance);
	AddVectors(vPos, vDir, vReturn);
}

stock void GetDirectionVector(float pos1[3], float angle[3], float rVec[3], float distance, float force) {
	float endPos[3];
	GetForwardVector(pos1, angle, endPos, distance);

	MakeVectorFromPoints(pos1, endPos, rVec);
	NormalizeVector(rVec, rVec);

	ScaleVector(rVec, force);
}

// Taken from https://gist.github.com/Aeldrion/48c82912f632eec4c8b9da7394b89c5d
stock void HSVToRGB(const float vec[3], float out[3]) {
	// Translates HSV color to RGB color
	// H: 0.0 - 360.0, S: 0.0 - 100.0, V: 0.0 - 100.0
	// R, G, B: 0.0 - 1.0

	float hue = vec[0];
	float saturation = vec[1];
	float value = vec[2];

	float c = (value / 100.0) * (saturation / 100.0);
	float x = c * (1.0 - FloatAbs(float(RoundToFloor(hue / 60) % 2) - 1));
	float m = (value / 100.0) - c;
	
	if (hue >= 0 && hue < 60.0) {
		out[0] = c;
		out[1] = x;
		out[2] = 0.0;
	} else if (hue >= 60.0 && hue < 120.0) {
		out[0] = x;
		out[1] = c;
		out[2] = 0.0;
	} else if (hue >= 120.0 && hue < 180.0) {
		out[0] = 0.0;
		out[1] = c;
		out[2] = x;
	} else if (hue >= 180.0 && hue < 240.0) {
		out[0] = 0.0;
		out[1] = x;
		out[2] = c;
	} else if (hue >= 240.0 && hue < 300.0) {
		out[0] = x;
		out[1] = 0.0;
		out[2] = c;
	} else if (hue >= 300.0 && hue < 360.0) {
		out[0] = c;
		out[1] = 0.0;
		out[2] = x;
	}

	out[0] += m;
	out[1] += m;
	out[2] += m;

	out[0] * 255.0;
	out[1] * 255.0;
	out[2] * 255.0;
}
stock void HSVToRGBInt(const float vec[3], int out[3]) {
	// Don't initialize memory, just use the existing memory as int out[3], just tell it that is a float
	HSVToRGB(vec, view_as<float>(out));
	// Convert float to int:
	out[0] = RoundToFloor(view_as<float>(out[0]));
	out[1] = RoundToFloor(view_as<float>(out[1]));
	out[2] = RoundToFloor(view_as<float>(out[2]));
}

stock bool GetCursorLocation(int client, float outPos[3]) {
	float angle[3];
	GetClientEyePosition(client, outPos);
	GetClientEyeAngles(client, angle);
	TR_TraceRayFilter(outPos, angle, MASK_SOLID, RayType_Infinite, Filter_IgnorePlayer, client);
	if(TR_DidHit()) {
		TR_GetEndPosition(outPos);
		return true;
	} else {
		return false;
	}
} 

bool Filter_IgnorePlayer(int entity, int mask, int data) {
	return entity > 0 && entity != data;
}

bool Filter_World(int entity, int mask, int data) {
	return entity == 0;
}

// Gets a position from where the cursor is upto distance away (basically <= distance, going against walls)
stock bool GetCursorLimited(int client, float distance, float endPos[3], TraceEntityFilter filter)
{ 
	if (client > 0 && client <= MaxClients && IsClientInGame(client)) {
		float clientEye[3], clientAngle[3], direction[3];
		GetClientEyePosition(client, clientEye);
		GetClientEyeAngles(client, clientAngle);

		GetAngleVectors(clientAngle, direction, NULL_VECTOR, NULL_VECTOR);
		ScaleVector(direction, distance);
		AddVectors(clientEye, direction, endPos);

		TR_TraceRayFilter(clientEye, endPos, MASK_OPAQUE, RayType_EndPoint, filter, client);
		if (TR_DidHit(INVALID_HANDLE)) {
			TR_GetEndPosition(endPos);
		}
		return true;
	}

	return false;
}

stock void SetWeaponDelay(int client, float delay) {
	int pWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	if (pWeapon > -1) {
		SetEntPropFloat(pWeapon, Prop_Send, "m_flNextPrimaryAttack", GetGameTime() + delay); 
		SetEntPropFloat(pWeapon, Prop_Send, "m_flNextSecondaryAttack", GetGameTime() + delay); 
	}
}


// Sends client a menu selecting a player, see COMMAND_FILTER_* for flags, idPrefix is appended to menu item's id
stock void QueryPlayer(int client, MenuHandler handler, int flags = COMMAND_FILTER_NO_IMMUNITY, const char[] title = "Select a player", const char[] idPrefix = "", int time = 0) {
	Menu menu = new Menu(handler);
	menu.SetTitle(title, client);
	char id[32], display[32];
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && (IsClientInGame(i) || flags & COMMAND_FILTER_CONNECTED)) {
			if(flags & COMMAND_FILTER_NO_BOTS && IsFakeClient(i)) continue;
			if(flags & COMMAND_FILTER_ALIVE && !IsPlayerAlive(i)) continue;
			if(flags & COMMAND_FILTER_DEAD && IsPlayerAlive(i)) continue;
			if(~flags & COMMAND_FILTER_NO_IMMUNITY && !CanUserTarget(client, i)) continue;

			Format(id, sizeof(id), "%s%d", idPrefix, GetClientUserId(i));
			if(IsFakeClient(i)) {
				int realPlayer = GetRealClient(i);
				if(realPlayer > 0) {
					if(IsPlayerAlive(i)) {
						Format(display, sizeof(display), "%N (Idle)", realPlayer);
					} else {
						Format(display, sizeof(display), "%N (Idle)(Dead)", realPlayer);
					}
				} else if(IsPlayerAlive(i)) {
					Format(display, sizeof(display), "%N", i);
				} else {
					Format(display, sizeof(display), "%N (dead)", i);
				}
			} else if(IsPlayerAlive(i)) {
				Format(display, sizeof(display), "%N", i);
			} else {
				Format(display, sizeof(display), "%N (dead)", i);
			}

			menu.AddItem(id, display);
		}
	}

	menu.Display(client, time);
}
stock bool IsNearGround(int ref, float distFromGround = 15.0) {
	static float sPos[3], ePos[3];
	GetEntPropVector(ref, Prop_Send, "m_vecOrigin", sPos);
	ePos[0] = sPos[0];
	ePos[1] = sPos[1];
	ePos[2] = sPos[2] -= 15.0;
	TR_TraceRayFilter(sPos, ePos, MASK_SOLID, RayType_EndPoint, Filter_IgnorePlayer, ref);
	if(TR_DidHit()) {
		return true;
	}
	return false;
}

stock bool IsAreaClear(const float pos[3], const float ang[3], const float minBound[3], const float maxBound[3]) { 

	TR_TraceHullFilter(pos, pos, minBound, maxBound, MASK_SOLID, Filter_World);
	if(TR_DidHit()) {
		return false;
	}
	return true;
}

stock Action Timer_KillEntity(Handle h, int entity) {
	RemoveEntity(entity);
	return Plugin_Handled;
}

stock int GetSinglePlayer(int client, const char[] input, int flags = 0) {
	flags |= COMMAND_FILTER_NO_MULTI;
	char buf[2];
	int target_list[1], target_count;
	bool tn_is_ml;
	if ((target_count = ProcessTargetString(
		input,
		client,
		target_list,
		1,
		flags,
		buf,
		2,
		tn_is_ml)) <= 0
	) {
		ReplyToTargetError(client, target_count);
		return -1;
	}
	return target_list[0];
}

static int _glowColor[3] = { 255, 255, 255 };

stock void GlowPoint(const float pos[3], float lifetime = 5.0) {
	PrecacheModel("models/props_fortifications/orange_cone001_reference.mdl");
	int entity = CreateEntityByName("prop_dynamic");
	DispatchKeyValue(entity, "disableshadows", "1");
	DispatchKeyValue(entity, "model", "models/props_fortifications/orange_cone001_reference.mdl");
	TeleportEntity(entity, pos, NULL_VECTOR, NULL_VECTOR);
	DispatchSpawn(entity);
	L4D2_SetEntityGlow(entity, L4D2Glow_Constant, 10000, 0, _glowColor, false);
	CreateTimer(lifetime, Timer_KillEntity, entity);
}

stock void GlowEntity(int entity, float lifetime = 10.0) {
	L4D2_SetEntityGlow(entity, L4D2Glow_Constant, 10000, 0, _glowColor, false);
	CreateTimer(lifetime, Timer_ClearGlow, EntIndexToEntRef(entity));
}

Action Timer_ClearGlow(Handle h, int ref) {
	L4D2_RemoveEntityGlow(ref);
	return Plugin_Handled;
}

stock bool CompareVector(const float a[3], const float b[3], float delta) {
	return a[0] < b[0] + delta && a[0] > b[0] - delta &&
		a[1] < b[1] + delta && a[1] > b[1] - delta &&
		a[2] < b[2] + delta && a[2] > b[2] - delta
}

stock void CalculateWorldPosition(int entity, float pos[3]) {
	float mins[3], maxs[3];
	GetEntPropVector(entity, Prop_Send, "m_vecOrigin", pos);
	GetEntPropVector(entity, Prop_Send, "m_vecMins", mins);
	GetEntPropVector(entity, Prop_Send, "m_vecMaxs", maxs);
	pos[0] = pos[0] + (mins[0] + maxs[0]) * 0.5;
	pos[1] = pos[1] + (mins[1] + maxs[1]) * 0.5;
	pos[2] = pos[2] + (mins[2] + maxs[2]) * 0.5;
}
/// Displays either: Username, Username (AFK), Username (Dead), Userame (AFK/Dead)
stock void GetMenuDisplayName(int client, char[] display, int maxlen) {
	int realPlayer = L4D_GetIdlePlayerOfBot(client);
	// Incase player is idle, grab their bot instead of them
	if(realPlayer > 0 && IsClientConnected(realPlayer)) {
		if(IsPlayerAlive(client))
			Format(display, maxlen, "%N (AFK)", realPlayer);
		else
			Format(display, maxlen, "%N (AFK/Dead)", realPlayer);
	} else if(!IsPlayerAlive(client))
		Format(display, maxlen, "%N (Dead)", client);
	else {
		GetClientName(client, display, maxlen);
	}
}