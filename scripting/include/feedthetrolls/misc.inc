#define AUTOPUNISH_FLOW_MIN_DISTANCE 5000.0
#define AUTOPUNISH_MODE_COUNT 3
// #define DEBUG_PHRASE_LOAD 1

void ActivateAutoPunish(int client) {
	if(hAutoPunish.IntValue & 2 == 2) 
		ApplyTroll(lastButtonUser, "Special Magnet", 0, TrollMod_Constant);
	if(hAutoPunish.IntValue & 1 == 1) 
		ApplyTroll(lastButtonUser, "Tank Magnet", 0, TrollMod_Constant);
	if(hAutoPunish.IntValue & 8 == 8)
		ApplyTroll(lastButtonUser, "Vomit Player", 0, TrollMod_Instant);
	else if(hAutoPunish.IntValue & 4 == 4) 
		ApplyTroll(lastButtonUser, "Swarm", 0, TrollMod_Instant);
	if(hAutoPunishExpire.IntValue > 0) {
		CreateTimer(60.0 * hAutoPunishExpire.FloatValue, Timer_ResetAutoPunish, GetClientOfUserId(lastButtonUser));
	}
}

void SetWitchTarget(int witch, int target) {
	Behavior behavior = Behavior(witch, WITCH_QUERY);
	BehaviorAction action = behavior.CurrentAction.Last;
	
	BehaviorAction newaction = view_as<BehaviorAction>(AllocateMemory(18556));
	SDKCall(g_hWitchAttack, newaction, target);
	
	IActionResult result; result.Init(CHANGE_TO, newaction);
	result.ToAction(action);
}

bool ToggleMarkPlayer(int client, int target) {
	if(g_PendingBanTroll[target] > 0) {
		g_PendingBanTroll[target] = 0;
		LogAction(client, target, "\"%L\" unmarked \"%L\" as troll", client, target);
		ShowActivityEx(client, "[FTT] ", "unmarked %N as troll", target);
		return true;
	}else{
		bool isClientAdmin = GetUserAdmin(client) != INVALID_ADMIN_ID;
		bool isTargetAdmin = GetUserAdmin(target) != INVALID_ADMIN_ID;
		if(isClientAdmin && !isTargetAdmin) {
			Call_StartForward(g_PlayerMarkedForward);
			Call_PushCell(client);
			Call_PushCell(target);
			Call_Finish();
			g_PendingBanTroll[target] = GetClientUserId(client);
			EnableTroll(target, "No Profanity");
			LogAction(client, target, "\"%L\" marked \"%L\" as troll", client, target);
			ShowActivityEx(client, "[FTT] ", "marked %N as troll", target);
			return true;
		}else{
			ReplyToCommand(client, "cannot mark %N as troll as they are an admin.", target);
			return false;
		}
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
	static char word[32];
	char phrase[MAX_PHRASE_LENGTH];
	// Go through all the words:
	kv.GotoFirstSubKey();
	int i = 0;
	static char buffer[4];
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


int FindClosestClientAdminPriority(int source, bool ignoreBots, float pos[3]) {
	int c = FindClosestAdmin(source, ignoreBots, pos);
	if(c == -1) return FindClosestClient(source, ignoreBots, pos);
	else return c;
}

int FindClosestClient(int source, bool ignoreBots, float pos[3]) {
	int closest = -1;
	float minDist = -1.0;
	static float pos1[3];
	static float pos2[3];
	GetClientAbsOrigin(source, pos1);
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i) && (!ignoreBots || !IsFakeClient(i)) && i != source) {
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

int FindClosestAdmin(int source, bool ignoreBots, float pos[3]) {
	int closest = -1;
	float minDist = -1.0;
	static float pos1[3];
	static float pos2[3];
	GetClientAbsOrigin(source, pos);
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i) && (|ignoreBots || !IsFakeClient(i)) && GetUserAdmin(i) != INVALID_ADMIN_ID && i != source) {
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

int SpawnItem(const char[] entityName, float pos[3], float ang[3] = NULL_VECTOR) {
	static char classname[32];
	Format(classname, sizeof(classname), "weapon_%s", entityName);
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

void ThrowItemToClosestPlayer(int victim, int slot) {
	int wpn = GetPlayerWeaponSlot(victim, slot);
	if(wpn > 0 && (slot != 1 || DoesClientHaveMelee(victim))) {
		static float pos[3];
		int clients[4];
		GetClientAbsOrigin(victim, pos);
		int clientCount = GetClientsInRange(pos, RangeType_Visibility, clients, sizeof(clients));
		for(int i = 0; i < clientCount; i++) {
			if(clients[i] != victim) {
				static float targPos[3];
				GetClientAbsOrigin(clients[i], targPos);
				SDKHooks_DropWeapon(victim, wpn, targPos);
				if(slot == 1)
					CreateTimer(0.2, Timer_GivePistol, GetClientUserId(victim));
				return;
			}
		}
		// No client found, drop on ground:
		SDKHooks_DropWeapon(victim, wpn, NULL_VECTOR);
	}
}

void DropItem(int victim, int slot) {
	int wpn = GetPlayerWeaponSlot(victim, slot);
	if(slot != 1 || DoesClientHaveMelee(victim)) {
		SDKHooks_DropWeapon(victim, wpn, NULL_VECTOR);
	}
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
	//First filter -> Must be a valid client, successfully in-game and not an spectator (The dont have health).
	if(!client
	|| !IsValidEntity(client)
	|| !IsClientInGame(client)
	|| !IsPlayerAlive(client)
	|| IsClientObserver(client))
	{
		return -1;
	}
	
	//If the client is not on the survivors team, then just return the normal client health.
	if(GetClientTeam(client) != 2)
	{
		return GetClientHealth(client);
	}
	
	//First, we get the amount of temporal health the client has
	float buffer = GetEntPropFloat(client, Prop_Send, "m_healthBuffer");
	
	//We declare the permanent and temporal health variables
	float TempHealth;
	int PermHealth = GetClientHealth(client);
	
	//In case the buffer is 0 or less, we set the temporal health as 0, because the client has not used any pills or adrenaline yet
	if(buffer <= 0.0)
	{
		TempHealth = 0.0;
	}
	
	//In case it is higher than 0, we proceed to calculate the temporl health
	else
	{
		//This is the difference between the time we used the temporal item, and the current time
		float difference = GetGameTime() - GetEntPropFloat(client, Prop_Send, "m_healthBufferTime");
		
		//We get the decay rate from this convar (Note: Adrenaline uses this value)
		float decay = GetConVarFloat(FindConVar("pain_pills_decay_rate"));
		
		//This is a constant we create to determine the amount of health. This is the amount of time it has to pass
		//before 1 Temporal HP is consumed.
		float constant = 1.0/decay;
		
		//Then we do the calcs
		TempHealth = buffer - (difference / constant);
	}
	
	//If the temporal health resulted less than 0, then it is just 0.
	if(TempHealth < 0.0)
	{
		TempHealth = 0.0;
	}
	
	//Return the value
	return RoundToFloor(PermHealth + TempHealth);
}  


/// Returns TRUE if set, FALSE if not (if no weapon to shoot)
bool SetBotTarget(int bot, int target, int targetHP, int loops = 15) {
	if(shootAtTarget[target] == bot) {
		return false;
	} else if(shootAtTarget[target] > 0) {
		return false;
	}
	LookAtClient(target, bot);
	int weapon = GetPlayerWeaponSlot(target, 0);
	if(weapon > -1) {
		shootAtTarget[target] = bot;
		shootAtTargetLoops[target] = loops;
		shootAtTargetHP[bot] = targetHP;
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

stock bool IsAreaClear(const float pos[3], const float ang[3]) { 
	float min[3] = { -30.0, -30.0, -2.0};
	float max[3] = { 30.0, 30.0, 50.0 };

	// DebugTraceHull(pos, pos, min, max);
	TR_TraceHullFilter(pos, pos, min, max, MASK_SOLID, Filter_Solid);
	if(TR_DidHit()) {
		return false;
	}
	return true;
}

bool SpawnCarOnPlayer(int target) {
	float pos[3];
	float ang[3];
	GetClientEyePosition(target, pos);
	GetClientEyeAngles(target, ang);
	if(IsAreaClear(pos, ang)) {
		pos[2] += 40.0;
		int id = CreateProp("prop_physics", MODEL_CAR, pos, ang);
		CreateTimer(4.0, Timer_Delete, id);
		return true;
	}
	return false;
}

stock int CreateProp(const char[] entClass, const char[] model, const float pos[3], const float ang[3]) {
	int entity = CreateEntityByName(entClass);
	DispatchKeyValue(entity, "model", model);
	DispatchKeyValue(entity, "solid", "6");
	DispatchKeyValue(entity, "targetname", "hsprop");
	DispatchKeyValue(entity, "disableshadows", "1");
	TeleportEntity(entity, pos, ang, NULL_VECTOR);
	DispatchSpawn(entity);
	#if defined DEBUG_LOG_MAPSTART
	PrintToServer("spawn prop %.1f %.1f %.1f model %s", pos[0], pos[1], pos[2], model[7]);
	#endif
	return entity;
}

public bool Filter_Solid(int entity, int contentsMask, any data) {
	return entity <= 0;
}

public Action Timer_Delete(Handle h, int id) {
	AcceptEntityInput(id, "Kill");
}