#define AUTOPUNISH_FLOW_MIN_DISTANCE 5000.0
#define AUTOPUNISH_MODE_COUNT 3
// #define DEBUG_PHRASE_LOAD 1

void ActivateAutoPunish(int client) {
	if(hAutoPunish.IntValue & 2 == 2) 
		ApplyTroll(client, "Special Magnet", 0, TrollMod_Constant);
	if(hAutoPunish.IntValue & 1 == 1) 
		ApplyTroll(client, "Tank Magnet", 0, TrollMod_Constant);
	if(hAutoPunish.IntValue & 8 == 8)
		ApplyTroll(client, "Vomit Player", 0, TrollMod_Instant);
	else if(hAutoPunish.IntValue & 4 == 4) 
		ApplyTroll(client, "Swarm", 0, TrollMod_Instant);
	if(hAutoPunishExpire.IntValue > 0) {
		CreateTimer(60.0 * hAutoPunishExpire.FloatValue, Timer_ResetAutoPunish, GetClientOfUserId(client));
	}
}

// NOTE: Only supports one target at a time, stored globally
bool SetWitchTarget(int witch, int target) {
	#if defined _actions_included
		g_iWitchAttackVictim = target;
		BehaviorAction action = ActionsManager.GetAction(witch, "WitchBehavior");
		if(action == INVALID_ACTION || action.Child == INVALID_ACTION) {
			return false;
		}
		action = action.Child;
		action.OnUpdate = OnWitchActionUpdate; 
		return true;
	#else
		PrintToServer("[FTT] SetWitchTarget() called when behaviors plugin not found");
		return false;
	#endif
}

bool ToggleMarkPlayer(int client, int target) {
	if(pdata[target].pendingTrollBan > 0) {
		pdata[target].pendingTrollBan = 0;
		LogAction(client, target, "\"%L\" unmarked \"%L\" as troll", client, target);
		ShowActivityEx(client, "[FTT] ", "unmarked %N as troll", target);
		return true;
	}else{
		bool isClientAdmin = GetUserAdmin(client) != INVALID_ADMIN_ID;
		if(!isClientAdmin) {
			ReplyToCommand(client, "cannot mark %N as troll as you are not an admin.", target);
			return false;
		}
		bool isTargetAdmin = GetUserAdmin(target) != INVALID_ADMIN_ID;
		if(isTargetAdmin) {
			ReplyToCommand(client, "cannot mark %N as troll as they are an admin.", target);
			return false;
		}

		Call_StartForward(g_PlayerMarkedForward);
		Call_PushCell(client);
		Call_PushCell(target);
		Call_Finish();
		pdata[target].pendingTrollBan = GetClientUserId(client);
		EnableTroll(target, "No Profanity");
		LogAction(client, target, "\"%L\" marked \"%L\" as troll", client, target);
		ShowActivityEx(client, "[FTT] ", "marked %N as troll", target);
		return true;
	}
}

// Finds the survivor bot that took over an idle player
int GetSpectatorClient(int bot) {
	if(!IsFakeClient(bot)) return -1;
	static char netclass[16];
	GetEntityNetClass(bot, netclass, sizeof(netclass));
	if(strcmp(netclass, "SurvivorBot") == 0 ) {
		int user = GetEntProp(bot, Prop_Send, "m_humanSpectatorUserID");
		if(user > 0) return GetClientOfUserId(user);
	}
	return -1;
}

stock bool IsPlayerIncapped(int client) {
	return GetEntProp(client, Prop_Send, "m_isIncapacitated") == 1;
}

#define MAX_TYPOS_LENGTH 16
StringMap TYPOS_DICT;
void LoadTypos() {
	TYPOS_DICT.Clear();
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "data/ftt_typos.txt");

	if(!FileExists(sPath)) {
		PrintToServer("[FTT] Missing typos list: data/ftt_typos.txt");
		return;
	}
	File file = OpenFile(sPath, "r", false, NULL_STRING);
	if(file == null) {
		PrintToServer("[FTT] Cannot open: data/ftt_typos.txt");
		return;
	}


	char buffer[140], key[32];
	while(file.ReadLine(buffer, sizeof(buffer))) {
		int index = SplitString(buffer, " ", key, sizeof(key));
		TYPOS_DICT.SetString(key, buffer[index]);
	}

	file.Close();
}

#define MAX_PHRASES_PER_WORD 8
#define MAX_PHRASE_LENGTH 191
StringMap REPLACEMENT_PHRASES; 
ArrayList fullMessagePhraseList;

/* Example:
exWord 
{
	"1" "phrase1"
	"2" "phrase2"
}
*/
void LoadPhrases() {
	KeyValues kv = new KeyValues("Phrases");
	ArrayList phrases = new ArrayList(ByteCountToCells(MAX_PHRASE_LENGTH));

	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "data/ftt_phrases.cfg");

	if(!FileExists(sPath) || !kv.ImportFromFile(sPath)) {
		delete kv;
		PrintToServer("[FTT] Could not load phrase list from data/ftt_phrases.cfg");
		return;
	}
	char word[32];
	char phrase[MAX_PHRASE_LENGTH];
	// Go through all the words:
	kv.GotoFirstSubKey();
	int i = 0;
	char buffer[4];
	do {
		kv.GetSectionName(word, sizeof(word));
		StringToLower(word);
		phrases.Clear();
		for(;;) {
			IntToString(++i, buffer, sizeof(buffer));
			kv.GetString(buffer, phrase, MAX_PHRASE_LENGTH, "_null");
			if(strcmp(phrase, "_null") == 0) break;
			phrases.PushString(phrase);
		}
		i = 0;
		if(StrEqual(word, "_full message phrases")) {
			fullMessagePhraseList = phrases.Clone();
			continue;
		}
		#if defined DEBUG_PHRASE_LOAD
			PrintToServer("Loaded %d phrases for word \"%s\"", phrases.Length, word);
		#endif
		REPLACEMENT_PHRASES.SetValue(word, phrases.Clone(), true);
	} while (kv.GotoNextKey(false));
	delete kv;
}

ArrayList GetPhrasesArray(const char[] key) {
	int len = strlen(key);
	char[] keyLower = new char[len];
	for(int i = 0; i < len; i++) {
		keyLower[i] = CharToLower(key[i]);
	}
	ArrayList phrases;
	if(REPLACEMENT_PHRASES.GetValue(keyLower, phrases)) {
		return phrases;
	} else {
		return null;
	}
}


stock int FindClosestClientAdminPriority(int source, float pos[3]) {
	int c = FindClosestAdmin(source, pos);
	if(c == -1) return FindClosestClient(source, true,pos);
	else return c;
}

stock int FindClosestClient(int source, bool ignoreBots, float pos[3]) {
	int closest = -1;
	float minDist = -1.0;
	static float pos1[3];
	static float pos2[3];
	GetClientAbsOrigin(source, pos1);
	for(int i = 1; i <= MaxClients; i++) {
		if(i != source && IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i) && (!ignoreBots || !IsFakeClient(i)) ) {
			GetClientAbsOrigin(i, pos2);
			float dist = GetVectorDistance(pos1, pos2);
			if(minDist == -1.0 || dist <= minDist) {
				closest = i;
				minDist = dist;
			}
		}
	}
	GetClientEyePosition(closest, pos);
	return closest;
}

stock int FindClosestAdmin(int source, float pos[3]) {
	int closest = -1;
	float minDist = -1.0;
	static float pos1[3];
	static float pos2[3];
	GetClientAbsOrigin(source, pos);
	for(int i = 1; i <= MaxClients; i++) {
		if(i != source && IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i) && !IsFakeClient(i) && GetUserAdmin(i) != INVALID_ADMIN_ID) {
			GetClientAbsOrigin(i, pos2);
			float dist = GetVectorDistance(pos1, pos2, true);
			if(minDist == -1.0 || dist <= minDist) {
				closest = i;
				minDist = dist;
			}
		}
	}
	GetClientEyePosition(closest, pos);
	return closest;
}

int SpawnItem(const char[] itemName, float pos[3], float ang[3] = NULL_VECTOR) {
	static char classname[32];
	Format(classname, sizeof(classname), "weapon_%s", itemName);
	int spawner = CreateEntityByName(classname);
	if(spawner == -1) return -1;
	DispatchKeyValue(spawner, "solid", "6");
	// DispatchKeyValue(entity_weapon, "model", g_bLeft4Dead2 ? g_sWeaponModels2[model] : g_sWeaponModels[model]);
	DispatchKeyValue(spawner, "rendermode", "3");
	DispatchKeyValue(spawner, "disableshadows", "1");
	TeleportEntity(spawner, pos, ang, NULL_VECTOR);
	DispatchSpawn(spawner);
	TeleportEntity(spawner, pos, ang, NULL_VECTOR);
	return spawner;
}

bool IsAnyPlayerNear(int source, float range) {
	static float pos1[3];
	static float pos2[3];
	GetClientAbsOrigin(source, pos1);
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i) && i != source) {
			GetClientAbsOrigin(i, pos2);
			float dist = GetVectorDistance(pos1, pos2);
			if(dist <= range) return true;
		}
	}
	return false;
}

void ThrowItemToPlayer(int victim, int target, int slot) {
	int wpn = GetPlayerWeaponSlot(victim, slot);
	if(wpn > 0 && (slot != 1 || DoesClientHaveMelee(victim))) {
		static float pos[3];
		GetClientAbsOrigin(target, pos);
		SDKHooks_DropWeapon(victim, wpn, pos);
	}
}


stock void AddInFrontOf(float fVecOrigin[3], float fVecAngle[3], float fUnits, float fOutPut[3]) {
	float fVecView[3]; GetViewVector(fVecAngle, fVecView);
	
	fOutPut[0] = fVecView[0] * fUnits + fVecOrigin[0];
	fOutPut[1] = fVecView[1] * fUnits + fVecOrigin[1];
	fOutPut[2] = fVecView[2] * fUnits + fVecOrigin[2];
}
stock void GetViewVector(float fVecAngle[3], float fOutPut[3]) {
	fOutPut[0] = Cosine(fVecAngle[1] / (180 / FLOAT_PI));
	fOutPut[1] = Sine(fVecAngle[1] / (180 / FLOAT_PI));
	fOutPut[2] = -Sine(fVecAngle[0] / (180 / FLOAT_PI));
}
stock void LookAtClient(int iClient, int iTarget) {
	static float fTargetPos[3]; 
	static float fTargetAngles[3]; 
	static float fClientPos[3]; 
	static float fFinalPos[3];
	
	GetClientEyePosition(iClient, fClientPos);
	GetClientEyePosition(iTarget, fTargetPos);
	GetClientEyeAngles(iTarget, fTargetAngles);
	
	float fVecFinal[3];
	AddInFrontOf(fTargetPos, fTargetAngles, 7.0, fVecFinal);
	MakeVectorFromPoints(fClientPos, fVecFinal, fFinalPos);
	
	GetVectorAngles(fFinalPos, fFinalPos);

	TeleportEntity(iClient, NULL_VECTOR, fFinalPos, NULL_VECTOR);
}


stock int GetClientRealHealth(int client) {
	if(!client || !IsValidEntity(client) || !IsClientInGame(client) || !IsPlayerAlive(client) || IsClientObserver(client)) {
		return -1;
	} else if(GetClientTeam(client) != 2) {
		return GetClientHealth(client);
	}
	float buffer = GetEntPropFloat(client, Prop_Send, "m_healthBuffer");
	float tempHealth = 0.0;
	if(buffer > 0.0) {
		float difference = GetGameTime() - GetEntPropFloat(client, Prop_Send, "m_healthBufferTime");
		float decay = FindConVar("pain_pills_decay_rate").FloatValue;
		float constant = 1.0 / decay;
		tempHealth = buffer - (difference / constant);
		if(tempHealth < 0.0) {
			tempHealth = 0.0;
		}
	}
	return RoundToFloor(GetClientHealth(client) + tempHealth);
}  


/// Returns TRUE if set, FALSE if not (if no weapon to shoot)
bool SetBotTarget(int bot, int target, int targetHP, int loops = 15) {
	if(pdata[target].shootAtTarget == bot) {
		return false;
	} else if(pdata[target].shootAtTarget > 0) {
		return false;
	}
	LookAtClient(target, bot);
	int weapon = GetPlayerWeaponSlot(target, 0);
	if(weapon > -1) {
		pdata[target].shootAtTarget = bot;
		pdata[target].shootAtLoops = loops;
		pdata[bot].shootAtTargetHealth = targetHP;
		int ammo = GetEntProp(weapon, Prop_Send, "m_iClip1");
		DataPack pack = new DataPack();
		// Reverse target and bot:
		pack.WriteCell(target);
		pack.WriteCell(bot);
		pack.WriteCell(weapon);
		pack.WriteCell(ammo);
		CreateTimer(0.1, Timer_ShootReverse, pack, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
		return true;
	} else {
		return false;
	}
}

// Taken from https://forums.alliedmods.net/showthread.php?t=220132&page=2
stock void ExplodeProjectile(int entity, bool smoke = true) {
	SetEntProp(entity, Prop_Data, "m_takedamage", 2);
	SetEntProp(entity, Prop_Data, "m_iHealth", 1);
	SDKHooks_TakeDamage(entity, 0, 0, 1.0);
	if(smoke)
		SetEntProp(entity, Prop_Data, "m_nNextThinkTick", 1); //for smoke
}  

stock int CreateProp(const char[] entClass, const char[] model, const float pos[3], const float ang[3] = { 0.0, 0.0, 0.0 }, const float vel[3] = {0.0, 0.0, 0.0}) {
	int entity = CreateEntityByName(entClass);
	DispatchKeyValue(entity, "model", model);
	DispatchKeyValue(entity, "solid", "6");
	DispatchKeyValue(entity, "targetname", "hsprop");
	DispatchKeyValue(entity, "disableshadows", "1");
	TeleportEntity(entity, pos, ang, vel);
	DispatchSpawn(entity);
	TeleportEntity(entity, pos, ang, vel);
	#if defined DEBUG_LOG_MAPSTART
	PrintToServer("spawn prop %.1f %.1f %.1f model %s", pos[0], pos[1], pos[2], model[7]);
	#endif
	return entity;
}


public bool Filter_Solid(int entity, int contentsMask, any data) {
	return entity <= 0;
}


float VEH_MIN[3] = { -30.0, -30.0, 2.0};
float VEH_MAX[3] = { 30.0, 30.0, 20.0 };

bool SpawnCarToPlayer(int target, float distance) {
	float pos[3], ang[3];
	GetClientAbsOrigin(target, pos);
	pos[2] += 40.0;
	GetClientEyeAngles(target, ang);
	ang[2] = ang[0] = 0.0;

	float endPos[3];
	GetHorizontalPositionFromOrigin(pos, ang, distance, endPos);

	TR_TraceHullFilter(endPos, pos, VEH_MIN, VEH_MAX, MASK_SOLID, Filter_Solid);
	if(TR_DidHit()) {
		return false;
	}
	if(distance > 0.0)
		ang[1] -= 180;
 	float vel[3];
	vel[0] = Cosine(DegToRad(ang[1])) * 1500.0;
	vel[1] = Sine(DegToRad(ang[1])) * 1500.0;
	int id = CreateProp("prop_physics", MODEL_CAR, endPos, ang, vel);
	CreateTimer(6.0, Timer_Delete, id);
	return true;
}

bool SpawnCarOnPlayer(int target) {
	float min[3] = { -30.0, -30.0, -2.0};
	float max[3] = { 30.0, 30.0, 50.0 };
	float pos[3];
	float ang[3];
	GetClientEyePosition(target, pos);
	GetClientEyeAngles(target, ang);
	if(IsAreaClear(pos, ang, min, max)) {
		pos[2] += 40.0;
		int id = CreateProp("prop_physics", MODEL_CAR, pos, ang);
		CreateTimer(4.0, Timer_Delete, id);
		return true;
	}
	return false;
}

bool g_iPendingSurvivorAdd;
int isCustomSurvivor[MAXPLAYERS+1];

bool AddSurvivor() {
	if (GetClientCount(false) >= MaxClients - 1) {
		return false;
	}

	int i = CreateFakeClient("FTTSurvivorBot");
	bool result;
	if (i > 0) {
		if (DispatchKeyValue(i, "classname", "SurvivorBot")) {
			ChangeClientTeam(i, 2);

			if (DispatchSpawn(i)) {
				result = true;
			}
		}

		g_iPendingSurvivorAdd = true;
		CreateTimer(0.2, Timer_KickBot, i);
	}
	return result;
}

void ClearInventory(int client) {
	for(int i = 0; i <= 5; i++) {
		int item = GetPlayerWeaponSlot(client, i);
		if(item > 0) {
			AcceptEntityInput(item, "Kill");
		}
	}
}

void StopHealingBots() {
	healTargetPlayer = 0;
	for(int i = 1; i <= MaxClients; i++) {
		pdata[i].flags &= ~view_as<int>(Flag_IsTargettingHealer);
		if(isCustomSurvivor[i]) {
			ClearInventory(i);
			KickClient(i);
		}
	}
	delete stopHealingTimer;
	if(hAbmAutoHard != null) hAbmAutoHard.IntValue = wasAbmAutoHard;
	if(hSbFixEnabled != null) hSbFixEnabled.BoolValue = wasSbFixEnabled;
}


bool IsAnySurvivorInRange(const float origin[3], float range, int ignorePlayer = 0) {
	float pos[3];
	range = range * range;
	for(int i = 1; i <= MaxClients; i++) {
		if(i != ignorePlayer && IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i)) {
			GetClientAbsOrigin(i, pos);
			if(GetVectorDistance(origin, pos, true) <= range) {
				return true;
			}
		}
	}
	return false;
}

int GetRandomThrowableMagnetTarget(ProjectileMagnetType type, int owner = -1) {
	static int throwMagnetIndex;
	if(throwMagnetIndex == 0) throwMagnetIndex = GetTrollID("Projectile Magnet");
	ArrayList checkList = new ArrayList();
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && IsPlayerAlive(i) && Trolls[throwMagnetIndex].IsActive(i)) {
			if(type == ProjType_Survivors) {
				// If the projectile is not owned by player, check if troll flag not enabled
				if(owner != i && ~Trolls[throwMagnetIndex].activeFlagClients[i] & view_as<int>(ProjType_Survivors)) continue;
			} else if(~Trolls[throwMagnetIndex].activeFlagClients[i] & view_as<int>(type)) {
				// Skip if client does not have flag
				continue;
			}
 			checkList.Push(i);
		}
	}
	int target = -1;
	if(checkList.Length > 0) {
		target = checkList.Get(0, checkList.Length - 1);
	}
	delete checkList;
	return target;
}

stock bool CanSeePoint(const float origin[3], const float point[3]) {
	TR_TraceRay(origin, point, MASK_ALL, RayType_EndPoint);
	
	return !TR_DidHit(); // Can see point if no collisions
}

stock LookAtPoint(int entity, const float destination[3]){
	float angles[3], pos[3], result[3];
	GetEntPropVector(entity, Prop_Send, "m_vecOrigin", pos);
	MakeVectorFromPoints(destination, pos, result);
	GetVectorAngles(result, angles);
	if(angles[0] >= 270){
		angles[0] -= 270;
		angles[0] = (90-angles[0]);
	}else{
		if(angles[0] <= 90){
			angles[0] *= -1;
		}
	}
	angles[1] -= 180;
	TeleportEntity(entity, NULL_VECTOR, angles, NULL_VECTOR);
}
stock void PrintToConsoleAdmins(const char[] format, any ...) {
	char buffer[254];

	VFormat(buffer, sizeof(buffer), format, 2);
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i)) {
			AdminId admin = GetUserAdmin(i);
			if(admin != INVALID_ADMIN_ID) {
				PrintToConsole(i, "%s", buffer);
			}
		}
	}
	PrintToServer("%s", buffer);
}

/**
 * Shakes a client's screen with the specified amptitude,
 * frequency & duration.
 *
 * @param client		Client Index.
 * @param amplitude		Shake magnitude/amplitude.
 * @param frequency		Shake noise frequency.
 * @param duration		Shake lasts this long.
 * @return				True on success, false otherwise.
 */
stock bool ShakePlayer(int client, float amplitude=50.0, float frequency=150.0, float duration=3.0) {
	if (amplitude <= 0.0) {
		return false;
	}
	Handle userMessage = StartMessageOne("Shake", client);
	if (userMessage == INVALID_HANDLE) {
		return false;
	}

	if (GetFeatureStatus(FeatureType_Native, "GetUserMessageType") == FeatureStatus_Available
		&& GetUserMessageType() == UM_Protobuf) {
		PbSetInt(userMessage,   "command",         0);
		PbSetFloat(userMessage, "local_amplitude", amplitude);
		PbSetFloat(userMessage, "frequency",       frequency);
		PbSetFloat(userMessage, "duration",        duration);
	} else {
		BfWriteByte(userMessage,	0);	// Shake Command
		BfWriteFloat(userMessage,	amplitude);	// shake magnitude/amplitude
		BfWriteFloat(userMessage,	frequency);	// shake noise frequency
		BfWriteFloat(userMessage,	duration);	// shake lasts this long
	}
	EndMessage();
	return true;
}

void SetSlot(int client, int slot) {
	if(slot == -1)
		slot = GetRandomInt(0, 4);
	static char slotStr[8];
	Format(slotStr, sizeof(slotStr), "slot%d", slot);
	ClientCommand(client, slotStr);
}