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
	pos[0] += -150 * Cosine(theta); 
	pos[1] += -150 * Sine(theta); 
	finalPosition = pos;
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
stock int GetSurvivorId(const char str[16]) {
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
		else if(StrEqual(str, "bill", false)) return 4;
		else if(StrEqual(str, "zoey", false)) return 5;
		else if(StrEqual(str, "francis", false)) return 6;
		else if(StrEqual(str, "louis", false)) return 7;
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
stock bool TraceFilter(int entity, int contentsMask) {
	if( entity <= MaxClients )
		return false;
	return true;
}
stock bool GetGround(int client, float[3] vPos, float[3] vAng) {
	GetClientAbsOrigin(client, vPos);
	vAng = vPos;
	vAng[2] += 5.0;
	vPos[2] -= 500.0;

	Handle trace = TR_TraceRayFilterEx(vAng, vPos, MASK_SHOT, RayType_EndPoint, TraceFilter);
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

stock bool GiveClientWeapon(int client, const char[] wpnName, bool lasers) {
	char sTemp[64];
	float pos[3];
	GetClientAbsOrigin(client, pos);
	Format(sTemp, sizeof(sTemp), "weapon_%s", wpnName);

	int entity = CreateEntityByName(sTemp);
	if( entity != -1 ) {
		DispatchSpawn(entity);
		TeleportEntity(entity, pos, NULL_VECTOR, NULL_VECTOR);

		if(lasers) SetEntProp(entity, Prop_Send, "m_upgradeBitVec", 4);

		EquipPlayerWeapon(client, entity);
		return true;
	}else{
		return false;
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
        distance = GetVectorDistance(clientVecOrigin, entityVecOrigin);
        
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
stock void CheatCommand(int client, const char[] command, const char[] argument1, const char[] argument2)
{
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