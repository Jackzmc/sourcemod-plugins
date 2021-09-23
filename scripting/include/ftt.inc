#define AUTOPUNISH_FLOW_MIN_DISTANCE 5000.0
#define AUTOPUNISH_MODE_COUNT 3
// #define TROLL_MODE_COUNT 26
//


enum L4D2Infected
{
	L4D2Infected_None = 0,
	L4D2Infected_Smoker = 1,
	L4D2Infected_Boomer = 2,
	L4D2Infected_Hunter = 3,
	L4D2Infected_Spitter = 4,
	L4D2Infected_Jockey = 5,
	L4D2Infected_Charger = 6,
	L4D2Infected_Witch = 7,
	L4D2Infected_Tank = 8
};
int  g_iAttackerTarget[MAXPLAYERS+1];
int autoPunished = -1, autoPunishMode, lastButtonUser, lastCrescendoUser;
bool g_bPendingItemGive[MAXPLAYERS+1], g_PendingBanTroll[MAXPLAYERS+1];
GlobalForward g_PlayerMarkedForward;
char steamids[MAXPLAYERS+1][64];
Handle g_hWitchAttack;

//HANDLES
Handle hThrowTimer;
//CONVARS
ConVar hVictimsList, hThrowItemInterval, hAutoPunish, hMagnetChance, hShoveFailChance, hAutoPunishExpire, hMagnetTargetMode, hWitchTargetIncapp;
//BOOLS
bool lateLoaded; //Is plugin late loaded
bool bChooseVictimAvailable = false; //For charge player feature, is it available?
//INTEGERS
int g_iAmmoTable; //Loads the ammo table to get ammo amounts
int gChargerVictim = -1; //For charge player feature

float ZERO_VECTOR[3] = {0.0, 0.0, 0.0};

#include <feedthetrolls/base>

void ResetClient(int victim, bool wipe = true) {
	if(wipe) ActiveTrolls[victim] = 0;
	SetEntityGravity(victim, 1.0);
	SetEntPropFloat(victim, Prop_Send, "m_flLaggedMovementValue", 1.0);
	SDKUnhook(victim, SDKHook_WeaponCanUse, Event_ItemPickup);
	int wpn = GetClientWeaponEntIndex(victim, 0);
	if(wpn > -1)
		SDKUnhook(wpn, SDKHook_Reload, Event_WeaponReload);
}

void ActivateAutoPunish(int client) {
	if(hAutoPunish.IntValue & 2 == 2) 
		ApplyTroll(lastButtonUser, "SpecialMagnet", 0, TrollMod_None);
	if(hAutoPunish.IntValue & 1 == 1) 
		ApplyTroll(lastButtonUser, "TankMagnet", 0, TrollMod_None);
	if(hAutoPunish.IntValue & 8 == 8)
		ApplyTroll(lastButtonUser, "VomitPlayer", 0, TrollMod_None);
	else if(hAutoPunish.IntValue & 4 == 4) 
		ApplyTroll(lastButtonUser, "Swarm", 0, TrollMod_None);
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
	if(g_PendingBanTroll[target]) {
		g_PendingBanTroll[target] = false;
		ShowActivity(client, "unmarked %N as troll", target);
		return true;
	}else{
		AdminId admin_client = GetUserAdmin(client);
		AdminId admin_target = GetUserAdmin(target);
		if(admin_client != INVALID_ADMIN_ID && admin_target == INVALID_ADMIN_ID ) {
			Call_StartForward(g_PlayerMarkedForward);
			Call_PushCell(client);
			Call_PushCell(target);
			Call_Finish();
			g_PendingBanTroll[target] = true;
			ShowActivity(client, "marked %N as troll", target);
			return true;
		}else{
			ReplyToCommand(client, "cannot mark %N as troll as they are an admin.", target);
			return false;
		}
	}
}

stock int FindIdlePlayerBot(int client) {
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsFakeClient(i)) {
			int user = GetEntProp(i, Prop_Send, "m_humanSpectatorUserID");
			int bot = GetClientOfUserId(user);
			return bot > 0 ? bot : client;
		}
	}
	return client;
}
stock bool IsPlayerIncapped(int client) {
	return GetEntProp(client, Prop_Send, "m_isIncapacitated") == 1;
}
char SPECIAL_NAMES[][] = {
	"Smoker", "Boomer", "Hunter", "Spitter", "Jockey", "Charger", "Witch"
};
stock int GetSpecialType(const char[] input) {
	for(int i = 0; i < sizeof(SPECIAL_NAMES); i++) {
		if(strcmp(SPECIAL_NAMES[i], input, false) == 0) return i + 1;
	}
	return -1;
}

stock bool FindSuitablePosition(int target, const float pos[3], float outputPos[3], float minDistance = 19000.0, int tries = 100) {
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

#define MAX_PHRASES_PER_WORD 8
#define MAX_PHRASE_LENGTH 191
StringMap REPLACEMENT_PHRASES; 
//TODO: Load from cfg
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
		phrases.Clear();
		for(;;) {
			IntToString(++i, buffer, sizeof(buffer));
			kv.GetString(buffer, phrase, MAX_PHRASE_LENGTH, "_null");
			if(strcmp(phrase, "_null") == 0) break;
			phrases.PushString(phrase);
		}
		i = 0;
		REPLACEMENT_PHRASES.SetValue(word, phrases.Clone(), true);
	} while (kv.GotoNextKey(false));
	delete kv;
}

float GetIdealMinDistance(int specialType) {
	switch(specialType) {
		// /*Boomer*/ case 2: return 1200.0;
		/*Charger*/ case 6: return 19000.0;
		/*Smoker*/ case 1: return 20000.0;
	
		default:
			return 12000.0;
	}
}

public Action Timer_Kill(Handle h, int client) {
	AcceptEntityInput(client, "Kill");
}
//TODO: Add Insta-Witch
bool SpawnSpecialInFace(int target, int specialType) {
	static float pos[3], ang[3];
	static float testPos[3];
	testPos = pos;
	GetClientAbsOrigin(target, pos);
	GetClientEyeAngles(target, ang);
	if(specialType != 5 && specialType != 2) { //If charger/hunter, find a suitable area that is at least 5 m away
		float minDistance = GetIdealMinDistance(specialType);
		GetHorizontalPositionFromOrigin(pos, ang, minDistance, testPos);
		FindSuitablePosition(target, pos, testPos, minDistance, 100);
		pos = testPos;
	} else { // Else spawn a little bit off, and above (above for jockeys)
		pos[2] += 10.0;
		pos[0] += 5.0;
	}
	pos[2] += 1.0;
	NegateVector(ang);
	int special = (specialType == 7) ? L4D2_SpawnWitch(pos, ang) : L4D2_SpawnSpecial(specialType, pos, ang);
	if(special == -1) return false;

	if(specialType == 7) 
		SetWitchTarget(special, target);
	else 
		g_iAttackerTarget[special] = GetClientUserId(target);

	if(specialType == 2) { //Kill boomer
		ForcePlayerSuicide(special);
	}
	return true;
}

bool SpawnSpecialNear(int target, int specialType) {
	static float pos[3];
	if(L4D_GetRandomPZSpawnPosition(target, specialType, 10, pos)) {
		int special = (specialType == 7) ? L4D2_SpawnWitch(pos, ZERO_VECTOR) : L4D2_SpawnSpecial(specialType, pos, ZERO_VECTOR);
		if(special == -1) return false;
		if(specialType == 7) 
			SetWitchTarget(special, target);
		else 
			g_iAttackerTarget[special] = GetClientUserId(target);
		return true;
	}
	return false;
}