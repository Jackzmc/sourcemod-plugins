#define AUTOPUNISH_FLOW_MIN_DISTANCE 5000.0
#define AUTOPUNISH_MODE_COUNT 3

void ActivateAutoPunish(int client) {
	if(hAutoPunish.IntValue & 2 == 2) 
		ApplyTroll(lastButtonUser, "SpecialMagnet", 0, TrollMod_Constant);
	if(hAutoPunish.IntValue & 1 == 1) 
		ApplyTroll(lastButtonUser, "TankMagnet", 0, TrollMod_Constant);
	if(hAutoPunish.IntValue & 8 == 8)
		ApplyTroll(lastButtonUser, "VomitPlayer", 0, TrollMod_Instant);
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
