#define AUTOPUNISH_FLOW_MIN_DISTANCE 5000.0
#define AUTOPUNISH_MODE_COUNT 3
#define TROLL_NAME_MAX_LENGTH 64

enum trollMode {
	Troll_Reset = 0,
	Troll_SlowSpeed,
	Troll_HigherGravity,
	Troll_HalfPrimaryAmmo,
	Troll_UziRules,
	Troll_PrimaryDisable,
	Troll_SlowDrain,
	Troll_Clumsy,
	Troll_iCantSpellNoMore,
	Troll_CameTooEarly,
	Troll_KillMeSoftly,
	Troll_ThrowItAll,
	Troll_GunJam,
	Troll_NoPickup,
	Troll_Swarm,
	Troll_Honk,
	Troll_SpecialMagnet,
	Troll_TankMagnet,
	Troll_NoShove,
	Troll_DamageBoost,
	Troll_TempHealthQuickDrain,
	Troll_VomitPlayer,
	Troll_VocalizeGag,
	Troll_TakePills
}

enum trollModifier {
	Modifier_Auto = 0,
	Modifier_Constant = 1,
	Modifier_Repeat = 2,
	Modifier_Single = 4
}
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
int g_iTrollUsers[MAXPLAYERS+1], g_iAttackerTarget[MAXPLAYERS+1];
int autoPunished = -1, autoPunishMode, lastButtonUser, lastCrescendoUser;
bool g_bPendingItemGive[MAXPLAYERS+1], g_PendingBanTroll[MAXPLAYERS+1];
GlobalForward g_PlayerMarkedForward;

//HANDLES
Handle hThrowTimer;
//CONVARS
ConVar hVictimsList, hThrowItemInterval, hAutoPunish, hMagnetChance, hShoveFailChance, hAutoPunishExpire;
//BOOLS
bool lateLoaded; //Is plugin late loaded
bool bChooseVictimAvailable = false; //For charge player feature, is it available?
//INTEGERS
int g_iAmmoTable; //Loads the ammo table to get ammo amounts
int gChargerVictim = -1; //For charge player feature

enum struct Troll {
	char name[TROLL_NAME_MAX_LENGTH];
	char id[16];
	char description[128];

	int modifiers;
	bool players[MAXPLAYERS+1];

	bool IsTrolled(int client) {
		return this.players[client];
	}

	void SetTrolled(int client, bool value) {
		this.players[client] = value;
	}
}

StringMap trolls; //<id, Troll>
StringMapSnapshot trollIds;

void LoadTrolls() {
	trolls = new StringMap();
	KeyValues kv = new KeyValues("Trolls");
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "data/feedthetrolls.cfg");

	if(!FileExists(sPath) || !kv.ImportFromFile(sPath)) {
		delete kv;
		SetFailState("Could not load list of trolls from data/feedthetrolls.cfg");
	}

	kv.GotoFirstSubKey();

	char modifiers[8];
	int loaded;
	do {
		Troll troll;

		kv.GetSectionName(troll.name, sizeof(troll.name));
		kv.GetString("description", troll.description, sizeof(troll.description), "<no description>");
		kv.GetString("id", troll.id, sizeof(troll.id));
		kv.GetString("modifiers", modifiers, sizeof(modifiers));
		
		if(troll.id[0] == '\0') strcopy(troll.id, sizeof(troll.id), troll.name);

		//Parse the types of troll
		for(int i = 0; i < strlen(modifiers); i++) {
			if(modifiers[i] == 's') troll.modifiers |= view_as<int>(Modifier_Single);
			else if(modifiers[i] == 'r') troll.modifiers |= view_as<int>(Modifier_Repeat);
			else if(modifiers[i] == 'c') troll.modifiers |= view_as<int>(Modifier_Constant);
		}
		trolls.SetArray(troll.id, troll, sizeof(troll), true);
		++loaded;
	} while (kv.GotoNextKey(false));
	delete kv;
	trollIds = trolls.Snapshot();
	PrintToServer("[FTT] Loaded %d trolls successfully", loaded);
}

void ApplyTrollByKey(const char[] key, int victim, int activator, trollModifier modifier, bool silent = false) {
	Troll troll;
	trolls.GetArray(key, troll, sizeof(troll));
	ApplyTroll(troll, victim, activator, modifier, silent);
}

void ApplyTrollByIndex(int index, int victim, int activator, trollModifier modifier, bool silent = false) {
	Troll troll;
	GetTrollByIndex(index, troll);
	ApplyTroll(troll, victim, activator, modifier, silent);
}

void ApplyTroll(Troll troll, int victim, int activator, trollModifier modifier, bool silent = false) {
	if(GetClientTeam(victim) == 1) {
		//Victim is spectating, find its bot
		victim = FindIdlePlayerBot(victim);
	}

	if(modifier == Modifier_Auto) {
		if(troll.modifiers & view_as<int>(Modifier_Single) == view_as<int>(Modifier_Single)) 
			modifier = Modifier_Single;
		else if(troll.modifiers & view_as<int>(Modifier_Repeat) == view_as<int>(Modifier_Repeat))
			modifier = Modifier_Repeat;
		else
			modifier = Modifier_Constant;
	}

	bool isActive = troll.IsTrolled(victim);

	if(StrEqual(troll.id, "reset")) {
		ResetClient(victim, true);
		ClearAllTrolls(victim);
		ShowActivity(activator, "reset troll effects for %N. ", victim);
	} else if(StrEqual(troll.id, "slow", true))
		SetEntPropFloat(victim, Prop_Send, "m_flLaggedMovementValue", isActive ? 1.0 : 0.8);
	else if(StrEqual(troll.id, "highergrav", true))
		SetEntityGravity(victim,  isActive ? 1.3 : 0.8);
	else if(StrEqual(troll.id, "half", true)) {
		int current = GetPrimaryReserveAmmo(victim);
		SetPrimaryReserveAmmo(victim, current / 2);
	} else if(StrEqual(troll.id, "uzirules", true)) {
		TurnOffTrollByKey(victim, "nopickup");
		TurnOffTrollByKey(victim, "disable");
		SDKHook(victim, SDKHook_WeaponCanUse, Event_ItemPickup);
	} else if(StrEqual(troll.id, "disable", true)) {
		TurnOffTrollByKey(victim, "uzirules");
		TurnOffTrollByKey(victim, "nopickup");
		SDKHook(victim, SDKHook_WeaponCanUse, Event_ItemPickup);
	} else if(StrEqual(troll.id, "nopickup", true)) {
		TurnOffTrollByKey(victim, "uzirules");
		TurnOffTrollByKey(victim, "disable");
		SDKHook(victim, SDKHook_WeaponCanUse, Event_ItemPickup);
	} else if(StrEqual(troll.id, "clumsy", true)) {
		int wpn = GetClientSecondaryWeapon(victim);
		bool hasMelee = DoesClientHaveMelee(victim);
		if(hasMelee) {
			float pos[3];
			int clients[4];
			GetClientAbsOrigin(victim, pos);
			int clientCount = GetClientsInRange(pos, RangeType_Visibility, clients, sizeof(clients));
			for(int i = 0; i < clientCount; i++) {
				if(clients[i] != victim) {
					float targPos[3];
					GetClientAbsOrigin(clients[i], targPos);
					SDKHooks_DropWeapon(victim, wpn, targPos);
					CreateTimer(0.2, Timer_GivePistol);
					return;
				}
			}
			SDKHooks_DropWeapon(victim, wpn);
		}
	}else if(StrEqual(troll.id, "cametooearly", true)) {
		ReplyToCommand(activator, "This troll mode is not implemented.");
	} else if(StrEqual(troll.id, "killsoftly", true)) {
		char wpn[32];
		GetClientWeaponName(victim, 4, wpn, sizeof(wpn));
		if(StrEqual(wpn, "weapon_adrenaline") || StrEqual(wpn, "weapon_pain_pills")) {
			ClientCommand(victim, "slot5");
			g_bPendingItemGive[victim] = true;
		}else{
			ReplyToCommand(activator, "User does not have pills or adrenaline");
			return;
		}
		//TODO: Implement TrollMod_Repeat
		return;
	} else if(StrEqual(troll.id, "throwitall", true)) {
		if(modifier == Modifier_Single)
			ThrowAllItems(victim);
		if(hThrowTimer == INVALID_HANDLE && modifier == Modifier_Repeat) {
			hThrowTimer = CreateTimer(hThrowItemInterval.FloatValue, Timer_ThrowTimer, _, TIMER_REPEAT);
		}
	} else if(StrEqual(troll.id, "gunjam", true)) {
		int wpn = GetClientWeaponEntIndex(victim, 0);
		if(wpn > -1)
			SDKHook(wpn, SDKHook_Reload, Event_WeaponReload);
		else
			ReplyToCommand(activator, "Victim does not have a primary weapon.");
	} else if(StrEqual(troll.id, "swarm", true)) {
		if(modifier == Modifier_Single) {
			FakeClientCommandEx(activator, "sm_swarm #%d", victim);
		}else if(modifier == Modifier_Repeat) {
			FakeClientCommandEx(activator, "sm_swarmtoggle #%d", victim);
		}else{
			ReplyToCommand(activator, "Invalid modifier for mode.");
			return;
		}
	} else if(StrEqual(troll.id, "vomit", true)) 
		L4D_CTerrorPlayer_OnVomitedUpon(victim, victim);
	else if(modifier != Modifier_Single) {
		ReplyToCommand(activator, "Troll you attempted to apply does not exist.");
		PrintToServer("Troll \"%s\" not implemented (%s)", troll.name, troll.id);
		return;
	}

	if(modifier == Modifier_Constant || modifier == Modifier_Constant) {
		troll.SetTrolled(victim, !isActive);
	}

	if(!silent) {
		if(isActive) {
			ShowActivity(activator, "deactivated troll \"%s\" on %N. ", troll.name, victim);
		}else{
			if(modifier == Modifier_Repeat)
				ShowActivity(activator, "activated troll \"%s\" on repeat for %N. ", troll.name, victim);
			else
				ShowActivity(activator, "activated troll \"%s\" for %N. ", troll.name, victim);
		}
	}
}

void GetTrollByIndex(int index, Troll troll) {
	char key[TROLL_NAME_MAX_LENGTH];
	trollIds.GetKey(index, key, sizeof(key));
	trolls.GetArray(key, troll, sizeof(troll));
}

void ClearAllTrolls(int client) {
	Troll troll;
	for(int i = 0; i < trollIds.Length; i++) {
		GetTrollByIndex(i, troll);
		troll.players[i] = false;
	}
}

void TurnOffTrollByKey(int client, const char[] key) {
	Troll troll;
	trolls.GetArray(key, troll, sizeof(troll));
	troll.players[client] = false;
}

void TurnOffTrollByIndex(int client, int index) {
	Troll troll;
	GetTrollByIndex(index, troll);
	troll.players[client] = false;
}

bool HasTroll(int client, int index) {
	Troll troll;
	GetTrollByIndex(index, troll);
	return troll.players[client];
}

void ResetClient(int victim, bool wipe = true) {
	SetEntityGravity(victim, 1.0);
	SetEntPropFloat(victim, Prop_Send, "m_flLaggedMovementValue", 1.0);
	SDKUnhook(victim, SDKHook_WeaponCanUse, Event_ItemPickup);
	int wpn = GetClientWeaponEntIndex(victim, 0);
	if(wpn > -1)
		SDKUnhook(wpn, SDKHook_Reload, Event_WeaponReload);
}

void ActivateAutoPunish(int client) {
	if(hAutoPunish.IntValue & 2 == 2) 
		ApplyTrollByKey("specialmagnet", lastButtonUser, 0, Modifier_Constant);
	if(hAutoPunish.IntValue & 1 == 1) 
		ApplyTrollByKey("tankmagnet", lastButtonUser, 0, Modifier_Constant);
	if(hAutoPunish.IntValue & 8 == 8)
		ApplyTrollByKey("vomit", lastButtonUser, 0, Modifier_Single);
	else if(hAutoPunish.IntValue & 4 == 4) 
		ApplyTrollByKey("swarm", lastButtonUser, 0, Modifier_Single);

	if(hAutoPunishExpire.IntValue > 0) {
		CreateTimer(60.0 * hAutoPunishExpire.FloatValue, Timer_ResetAutoPunish, GetClientOfUserId(lastButtonUser));
	}
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