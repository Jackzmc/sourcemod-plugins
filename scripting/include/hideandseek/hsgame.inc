static int mapChangeMsgTicks = 5;


int GetColorInt(int r, int g, int b) {
	int color = r;
	color += 256 * g;
	color += 65536 * b;
	return color;
}

void Cleanup() {
	EntFire("hsprop", "kill");
	EntFire("hsblocker", "kill");
	EntFire("hsportal", "kill");
	PeekCam.Destroy();

}

GameState GetState() {
	if(!isEnabled) return State_Unknown;
	static char buffer[4];
	L4D2_GetVScriptOutput("g_ModeScript.MutationState.CurrentStage", buffer, sizeof(buffer));
	int stage = -1;
	if(StringToIntEx(buffer, stage) > 0) {
		return view_as<GameState>(stage);
	} else {
		return State_Unknown;
	}
}

int GetSlasher() {
	if(!isEnabled) return -1;
	static char buffer[8];
	L4D2_GetVScriptOutput("g_ModeScript.MutationState.CurrentSlasher && \"GetPlayerUserId\" in g_ModeScript.MutationState.CurrentSlasher ? g_ModeScript.MutationState.CurrentSlasher.GetPlayerUserId() : -1", buffer, sizeof(buffer));
	int uid = StringToInt(buffer);
	if(uid > 0) {
		return GetClientOfUserId(uid);
	} else {
		PrintToServer("[H&S] Could not find real slasher, falling back to manual check");
		return FindSlasher();
	}
}

int FindSlasher() {
	char buf[16];
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i)) {
			int entity = GetPlayerWeaponSlot(i, 1);
			if(entity > -1 && GetEntityClassname(entity, buf, sizeof(buf)) && StrEqual(buf, "melee")) {
				GetEntPropString(entity, Prop_Data, "m_strMapSetScriptName", buf, sizeof(buf));
				if(StrEqual(buf, "fireaxe")) {
					return i;
				}
			}
		}
	}
	return -1;
}

void SetSlasher(int client, bool ignoreBalance = false) { 
	if(ignoreBalance) {
		ignoreSeekerBalance = true;
	}
	GameState state = GetState();
	char buf[128];
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && i != client) {
			for(int s = 0; s < 6; s++) {
				int ent = GetPlayerWeaponSlot(i, s);
				if(ent > 0) AcceptEntityInput(ent, "Kill");
			}
			if(state == State_Hunting)
				CheatCommand(i, "give", "pistol_magnum");
			else
				CheatCommand(i, "give", "knife");
		}
	}
	Format(buf, sizeof(buf), "g_ModeScript.MutationState.CurrentSlasher = GetPlayerFromUserID(%d); g_ModeScript.GiveSeekerItem(GetPlayerFromUserID(%d))", GetClientUserId(client), GetClientUserId(client));
	L4D2_ExecVScriptCode(buf);
	currentSeeker = client;
	// CheatCommand(client, "give", "fireaxe");
	CheatCommand(client, "give", "adrenaline");
}

int GetTick() {
	if(!isEnabled) return -1;
	static char buffer[4];
	L4D2_GetVScriptOutput("g_ModeScript.MutationState.StateTick", buffer, sizeof(buffer));
	int value = -1;
	if(StringToIntEx(buffer, value) > 0) {
		return value;
	} else {
		return -1;
	}
}

void SetTick(int tick) {
	static char buf[64];
	Format(buf, sizeof(buf), "g_ModeScript.MutationState.StateTick = %d", tick);
	L4D2_ExecVScriptCode(buf);
}


int GetMapTime() {
	static char mapTime[16];
	L4D2_GetVScriptOutput("g_ModeScript.MutationState.MapTime", mapTime, sizeof(mapTime));
	return StringToInt(mapTime);
}

void SetMapTime(int seconds) {
	static char buf[64];
	Format(buf, sizeof(buf), "g_ModeScript.MutationState.MapTime = %d", seconds);
	L4D2_ExecVScriptCode(buf);
}

Action Timer_ChangeMap(Handle h) {
	PrintToChatAll("Changing map to %s in %d seconds", nextRoundMap, mapChangeMsgTicks);
	if(mapChangeMsgTicks-- == 0) {
		ForceChangeLevel(nextRoundMap, "H&SMapSelect");
		nextRoundMap[0] = '\0';
		return Plugin_Stop;
	}
	return Plugin_Continue;
}

void ChangeMap(const char map[64], int time = 5) {
	strcopy(nextRoundMap, sizeof(nextRoundMap), map);
	mapChangeMsgTicks = time;
	CreateTimer(1.0, Timer_ChangeMap, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

bool GetSpawnPosition(float pos[3], bool includePlayers = true) {
	if(includePlayers) {
		for(int i = 1; i <= MaxClients; i++) {
			if(IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i)) {
				GetClientAbsOrigin(i, pos);
				return true;
			}
		}
	}
	int entity = INVALID_ENT_REFERENCE;
	while ((entity = FindEntityByClassname(entity, "info_player_start")) != INVALID_ENT_REFERENCE) {
		GetEntPropVector(entity, Prop_Send, "m_vecOrigin", pos);
		return true;
	}
	return false;
}

bool SetState(GameState state) {
	if(!isEnabled) return false;
	static char buffer[64];
	Format(buffer, sizeof(buffer), "g_ModeScript.MutationState.CurrentStage = %d", view_as<int>(state));
	return L4D2_ExecVScriptCode(buffer);
}

bool IsGameSoloOrPlayersLoading() {
	int connecting, ingame;
	for(int i = 1;  i <= MaxClients; i++) {
		if(IsClientConnected(i)) {
			if(IsClientInGame(i))
				ingame++;
			else
				connecting++;
		}
	}
	return connecting > 0 || ingame == 1;
}

//cm_NoSurvivorBots 
bool SetBotsEnabled(bool value) {
	static char buffer[64];
	if(value) 
		Format(buffer, sizeof(buffer), "g_ModeScript.MutationOptions.cm_NoSurvivorBots = true");
	else
		Format(buffer, sizeof(buffer), "g_ModeScript.MutationOptions.cm_NoSurvivorBots = false");
	return L4D2_ExecVScriptCode(buffer);
}

bool IsBotsEnabled() {
	static char result[8];
	L4D2_GetVScriptOutput("g_ModeScript.MutationState.cm_NoSurvivorBots", result, sizeof(result));
	return StrEqual(result, "true", false);
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

stock void GetAnglesLookAt(int iClient, int iTarget, float fFinalPos[3]) {
	static float fTargetPos[3]; 
	static float fTargetAngles[3]; 
	static float fClientPos[3]; 
	
	GetEntPropVector(iClient, Prop_Send, "m_vecOrigin", fClientPos);
	GetClientEyePosition(iTarget, fTargetPos);
	GetClientEyeAngles(iTarget, fTargetAngles);
	
	float fVecFinal[3];
	AddInFrontOf(fTargetPos, fTargetAngles, 7.0, fVecFinal);
	MakeVectorFromPoints(fClientPos, fVecFinal, fFinalPos);
	
	GetVectorAngles(fFinalPos, fFinalPos);

	// TeleportEntity(iClient, NULL_VECTOR, fFinalPos, NULL_VECTOR);
}
stock void AddInFrontOf(float fVecOrigin[3], float fVecAngle[3], float fUnits, float fOutPut[3])
{
	float fVecView[3]; GetViewVector(fVecAngle, fVecView);
	
	fOutPut[0] = fVecView[0] * fUnits + fVecOrigin[0];
	fOutPut[1] = fVecView[1] * fUnits + fVecOrigin[1];
	fOutPut[2] = fVecView[2] * fUnits + fVecOrigin[2];
}
stock void GetViewVector(float fVecAngle[3], float fOutPut[3])
{
	fOutPut[0] = Cosine(fVecAngle[1] / (180 / FLOAT_PI));
	fOutPut[1] = Sine(fVecAngle[1] / (180 / FLOAT_PI));
	fOutPut[2] = -Sine(fVecAngle[0] / (180 / FLOAT_PI));
}


bool Filter_IgnoreAll(int entity, int mask) {
	return false;
}

