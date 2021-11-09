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
		AdminId admin_client = GetUserAdmin(client);
		AdminId admin_target = GetUserAdmin(target);
		if(admin_client != INVALID_ADMIN_ID && admin_target == INVALID_ADMIN_ID ) {
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