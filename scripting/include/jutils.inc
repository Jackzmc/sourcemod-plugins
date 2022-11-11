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
	if(slot >= 0 && slot <= 4) {
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
		ThrowError("Slot must be a number between 0 and 4");
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

stock bool IsEntityInSightRange(int client, int target, float angle = 90.0, float distance = 0.0, bool heightcheck = true, bool negativeangle = false) {
	if(angle > 360.0 || angle < 0.0)
		ThrowError("Angle Max : 360 & Min : 0. %d isn't proper angle.", angle);
	else if(!IsValidClient(client))
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
stock bool IsValidAdmin(int client, const char[] flags) {
	int ibFlags = ReadFlagString(flags);
	if ((GetUserFlagBits(client) & ibFlags) == ibFlags) {
		return true;
	}else if (GetUserFlagBits(client) & ADMFLAG_ROOT) {
		return true;
	}
	return false;
}  

stock void NotifyAllAdmins(const char[] format, any ...) {
	char buffer[254];
	VFormat(buffer, sizeof(buffer), format, 2);
	for(int i = 1; i < MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i)) {
			AdminId admin = GetUserAdmin(i);
			if(admin != INVALID_ADMIN_ID && admin.ImmunityLevel > 0) {
				PrintToChat(i, "%s", buffer);
			}
		}
	}
	PrintToServer("%s", buffer);
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
		if(IsClientConnected(i) && HasEntProp(i, Prop_Send, "m_humanSpectatorUserID")) {
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
