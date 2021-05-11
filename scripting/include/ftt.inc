#define AUTOPUNISH_FLOW_MIN_DISTANCE 5000.0
#define AUTOPUNISH_MODE_COUNT 3
#define TROLL_MODE_COUNT 23
//
enum trollMode {
	Troll_Reset = 0, //0
	Troll_SlowSpeed, //1
	Troll_HigherGravity, //2
	Troll_HalfPrimaryAmmo, //3
	Troll_UziRules, //4
	Troll_PrimaryDisable, //5
	Troll_SlowDrain, //6
	Troll_Clumsy, //7
	Troll_iCantSpellNoMore, //8
	Troll_CameTooEarly, //9
	Troll_KillMeSoftly, //10
	Troll_ThrowItAll, //11
	Troll_GunJam, //12
	Troll_NoPickup, //13
	Troll_Swarm, //14
	Troll_Honk, //15, //TODO: Modify sounds :)
	Troll_SpecialMagnet, //16
	Troll_TankMagnet, //17
	Troll_NoShove, //18
	Troll_DamageBoost, //19
	Troll_TempHealthQuickDrain, //20
	Troll_VomitPlayer, //21
	Troll_VocalizeGag
}
enum TrollModifier {
	TrollMod_None = 0,
	TrollMod_InstantFire = 1,
	TrollMod_Repeat = 2
}
enum trollType {
	Type_Constant = 1,
	Type_Repeat = 2,
	Type_Single = 4
}

char TROLL_MODES_NAMES[TROLL_MODE_COUNT][32] = {
	"Reset User", //0
	"Slow Speed", //1
	"Higher Gravity", //2 
	"Half Primary Ammo", //3 
	"UziRules", //4
	"PrimaryDisable", //5
	"SlowDrain", //6
	"Clusmy", //7
	"iCantSpellNoMore", //8
	"CameTooEarly", //9
	"KillMeSoftly", //10
	"ThrowItAll", //11
	"GunJam", //12
	"NoPickup",
	"Swarm",
	"Honk",
	"Special Magnet",
	"Tank Magnet",
	"No Shove",
	"Damage Boost",
	"Temp Quick Drain",
	"Vomit Player",
	"Vocalize Gag"
};
char TROLL_MODES_DESCRIPTIONS[TROLL_MODE_COUNT][128] = {
	"Resets the user, removes all troll effects", //0
	"Sets player speed to 0.8x of normal speed", //1
	"Sets player gravity to 1.3x of normal gravity", //2 
	"Cuts their primary reserve ammo in half", //3 
	"Picking up a weapon gives them a UZI instead", //4
	"Player cannot pickup any weapons, only melee/pistols", //5
	"Player slowly loses health", //6
	"Player drops axe periodically or on demand", //7
	"Chat messages letter will randomly changed with wrong letters ", //8
	"When they shoot, random chance they empty whole clip", //9
	"Make player eat or waste pills whenever possible", //10
	"Player throws all their items at nearby player, periodically", //11
	"On reload, small chance their gun gets jammed - Can't reload.", //12
	"Prevents a player from picking up ANY (new) item. Use ThrowItAll to make them drop",
	"Swarms a player with zombies. Requires swarm plugin",
	"Honk",
	"Attracts ALL specials to any alive target with this troll enabled",
	"Attracts ALL tanks to any alive target with this troll enabled",
	"Prevents a player from shoving",
	"Makes a player take more damage than normal",
	"Makes a player's temporarily health drain very quickly",
	"Shortcut to sm_vomitplayer. vomits the player.",
	"Prevents player from sending any vocalizations (even automatic)"
};
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
	char name[64];
	char id[16];
	char description[128];

	int modifiers;
}

ArrayList trolls; //<id, Troll>

void LoadTrolls() {
	trolls = new ArrayList(sizeof(Troll));
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
			if(modifiers[i] == 's') troll.modifiers |= view_as<int>(Type_Single);
			else if(modifiers[i] == 'r') troll.modifiers |= view_as<int>(Type_Repeat);
			else if(modifiers[i] == 'c') troll.modifiers |= view_as<int>(Type_Constant);
		}
		trolls.PushArray(troll);
		++loaded;
	} while (kv.GotoNextKey(false));
	delete kv;

	PrintToServer("[FTT] Loaded %d trolls successfully", loaded);
}

void ApplyTroll(int trollIndex, int victim, int activator, trollType modifier, bool silent = false) {
	if(GetClientTeam(victim) == 1) {
		//Victim is spectating, find its bot
		victim = FindIdlePlayerBot(victim);
	}

	Troll troll;
	trolls.GetArray(trollIndex, troll, sizeof(troll));

	bool isActive = HasTroll(trollIndex, victim);

	PrintToChatAll("a=%N v=%N active=%b | %s (%s)", activator, victim, isActive, troll.name, troll.id);
	if(StrEqual(troll.id, "reset")) {
		ResetClient(victim, true);
		ShowActivity(activator, "reset troll effects for %N. ", victim);
	} else if(StrEqual(troll.id, "slow", true))
		SetEntPropFloat(victim, Prop_Send, "m_flLaggedMovementValue", isActive ? 1.0 : 0.8);
	else if(StrEqual(troll.id, "highergrav", true))
		SetEntityGravity(victim,  isActive ? 1.3 : 0.8);
	else if(StrEqual(troll.id, "half", true)) {
		int current = GetPrimaryReserveAmmo(victim);
		SetPrimaryReserveAmmo(victim, current / 2);
	} else if(StrEqual(troll.id, "uzirules", true)) {
		TurnOffTrollMode(victim, Troll_NoPickup);
		TurnOffTrollMode(victim, Troll_PrimaryDisable);
		SDKHook(victim, SDKHook_WeaponCanUse, Event_ItemPickup);
	} else if(StrEqual(troll.id, "disable", true)) {
		TurnOffTrollMode(victim, Troll_UziRules);
		TurnOffTrollMode(victim, Troll_NoPickup);
		SDKHook(victim, SDKHook_WeaponCanUse, Event_ItemPickup);
	} else if(StrEqual(troll.id, "drain", true)) {
		TurnOffTrollMode(victim, Troll_UziRules);
		TurnOffTrollMode(victim, Troll_PrimaryDisable);
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
		if(modifier == Type_Single)
			ThrowAllItems(victim);
		if(hThrowTimer == INVALID_HANDLE && modifier == Type_Repeat) {
			hThrowTimer = CreateTimer(hThrowItemInterval.FloatValue, Timer_ThrowTimer, _, TIMER_REPEAT);
		}
	} else if(StrEqual(troll.id, "gunjam", true)) {
		int wpn = GetClientWeaponEntIndex(victim, 0);
		if(wpn > -1)
			SDKHook(wpn, SDKHook_Reload, Event_WeaponReload);
		else
			ReplyToCommand(activator, "Victim does not have a primary weapon.");
	} else if(StrEqual(troll.id, "swarm", true)) {
		if(modifier == Type_Single) {
			FakeClientCommandEx(activator, "sm_swarm #%d", victim);
		}else if(modifier == Type_Repeat) {
			FakeClientCommandEx(activator, "sm_swarmtoggle #%d", victim);
		}else{
			ReplyToCommand(activator, "Invalid modifier for mode.");
			return;
		}
	} else if(StrEqual(troll.id, "vomit", true)) 
		L4D_CTerrorPlayer_OnVomitedUpon(victim, victim);
	else if(modifier != Type_Single) {
		ReplyToCommand(activator, "Troll you attempted to apply does not exist.");
		PrintToServer("Troll \"%s\" not implemented (%s)", troll.name, troll.id);
		return;
	}

	if(modifier == Type_Constant || modifier == Type_Repeat) {
		g_iTrollUsers[victim] ^= 1 << view_as<int>(trollIndex) -1;
	}
	if(!silent) {
		if(isActive) {
			ShowActivity(activator, "deactivated troll \"%s\" on %N. ", troll.name, victim);
		}else{
			if(modifier == Type_Repeat)
				ShowActivity(activator, "activated troll \"%s\" on repeat for %N. ", troll.name, victim);
			else
				ShowActivity(activator, "activated troll \"%s\" for %N. ", troll.name, victim);
		}
	}
}

bool HasTroll(int trollIndex, int client) {
	return ((g_iTrollUsers[client] >> view_as<int>(trollIndex) - 1) & 1) == 1;
}

//Applies the selected trollMode to the victim.
//Modifiers are as followed: 0 -> Both (fire instant, and timer), 1 -> Fire Once, 2 -> Start timer
//TODO: change it to only modifier at once? at least for instant fire & repeat. Menu runs ApplyMode twice
void ApplyModeToClient(int client, int victim, trollMode mode, TrollModifier modifier, bool silent = false) {
	ResetClient(victim, false);
	if(view_as<int>(mode) > TROLL_MODE_COUNT || view_as<int>(mode) < 0) {
		ReplyToCommand(client, "Unknown troll mode ID '%d'. Pick a mode between 1 and %d", mode, TROLL_MODE_COUNT - 1);
		return;
	}

	if(GetClientTeam(victim) == 1) {
		//Victim is spectating, find its bot
		victim = FindIdlePlayerBot(victim);
	}

	//bool activating = !HasTrollMode(victim, mode);
	switch(mode) {
		case Troll_iCantSpellNoMore: {}
		case Troll_Honk: {}
		case Troll_TankMagnet: {}
		case Troll_SpecialMagnet: {}
		case Troll_NoShove: {}
		case Troll_SlowDrain: {}
		case Troll_TempHealthQuickDrain: {}
		case Troll_VomitPlayer: {
			L4D_CTerrorPlayer_OnVomitedUpon(victim, victim);
		}
		
		case Troll_Reset: {
			ShowActivity(client, "reset troll effects for %N. ", victim);
			g_iTrollUsers[victim] = Troll_Reset;
			return;
		} 
		case Troll_SlowSpeed: 
			SetEntPropFloat(victim, Prop_Send, "m_flLaggedMovementValue", 0.8);
		case Troll_HigherGravity:
			SetEntityGravity(victim, 1.3);
		case Troll_HalfPrimaryAmmo: {
			//TODO: Implement modifier code
			int current = GetPrimaryReserveAmmo(victim);
			SetPrimaryReserveAmmo(victim, current / 2);
		}
		case Troll_UziRules: {
			TurnOffTrollMode(victim, Troll_NoPickup);
			TurnOffTrollMode(victim, Troll_PrimaryDisable);
			SDKHook(victim, SDKHook_WeaponCanUse, Event_ItemPickup);
		}
		case Troll_PrimaryDisable: {
			TurnOffTrollMode(victim, Troll_UziRules);
			TurnOffTrollMode(victim, Troll_NoPickup);
			SDKHook(victim, SDKHook_WeaponCanUse, Event_ItemPickup);
		}
		case Troll_NoPickup: {
			TurnOffTrollMode(victim, Troll_UziRules);
			TurnOffTrollMode(victim, Troll_PrimaryDisable);
			SDKHook(victim, SDKHook_WeaponCanUse, Event_ItemPickup);
		}
		case Troll_Clumsy: {
			//TODO: Implement modifier code
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
						g_iTrollUsers[victim] = mode;
						CreateTimer(0.2, Timer_GivePistol);
						return;
					}
				}
				SDKHooks_DropWeapon(victim, wpn);
			}
		}
		case Troll_CameTooEarly:
			//TODO: Implement modifier code
			ReplyToCommand(client, "This troll mode is not implemented.");
		case Troll_KillMeSoftly: {
			char wpn[32];
			GetClientWeaponName(victim, 4, wpn, sizeof(wpn));
			if(StrEqual(wpn, "weapon_adrenaline") || StrEqual(wpn, "weapon_pain_pills")) {
				ClientCommand(victim, "slot5");
				g_bPendingItemGive[victim] = true;
			}else{
				ReplyToCommand(client, "User does not have pills or adrenaline");
				return;
			}
			//TODO: Implement TrollMod_Repeat
			return;
		}
		case Troll_ThrowItAll: {
			if(modifier == TrollMod_InstantFire)
				ThrowAllItems(victim);
			if(hThrowTimer == INVALID_HANDLE && modifier == TrollMod_Repeat) {
				PrintToServer("Created new throw item timer");
				hThrowTimer = CreateTimer(hThrowItemInterval.FloatValue, Timer_ThrowTimer, _, TIMER_REPEAT);
			}
		}
		case Troll_Swarm: {
			if(modifier == TrollMod_InstantFire) {
				FakeClientCommandEx(client, "sm_swarm #%d", victim);
			}else if(modifier == TrollMod_Repeat) {
				FakeClientCommandEx(client, "sm_swarmtoggle #%d", victim);
			}else{
				ReplyToCommand(client, "Invalid modifier for mode.");
				return;
			}
		}
		case Troll_GunJam: {
			int wpn = GetClientWeaponEntIndex(victim, 0);
			if(wpn > -1)
				SDKHook(wpn, SDKHook_Reload, Event_WeaponReload);
			else
				ReplyToCommand(client, "Victim does not have a primary weapon.");
		} default: {
			ReplyToCommand(client, "This trollMode is not implemented.");
			PrintToServer("Troll Mode #%d not implemented (%s)", mode, TROLL_MODES_NAMES[mode]);
		}
	}
	if(!silent) {
		if(HasTrollMode(victim, mode)) {
			ShowActivity(client, "deactivated troll \"%s\" on %N. ", TROLL_MODES_NAMES[mode], victim);
		}else{
			if(modifier == TrollMod_Repeat)
				ShowActivity(client, "activated troll \"%s\" on repeat for %N. ", TROLL_MODES_NAMES[mode], victim);
			else
				ShowActivity(client, "activated troll \"%s\" for %N. ", TROLL_MODES_NAMES[mode], victim);
		}
	}
	//If instant fire mod not provided (aka instead of no modifiers which equals both) OR repeat turned on, set bit:
	if(modifier == TrollMod_Repeat || modifier == TrollMod_None) {
		g_iTrollUsers[victim] ^= 1 << view_as<int>(mode) -1;
	}
}

bool HasTrollMode(int client, trollMode mode) {
	return ((g_iTrollUsers[client] >> view_as<int>(mode) - 1) & 1) == 1;
}

void ToggleTrollMode(int client, trollMode mode) {
	g_iTrollUsers[client] ^= 1 << view_as<int>(mode) -1;
}

void TurnOffTrollMode(int client, trollMode mode) {
	if(HasTrollMode(client, mode)) {
		ToggleTrollMode(client, mode);
	}
}

void ResetClient(int victim, bool wipe = true) {
	if(wipe) g_iTrollUsers[victim] = Troll_Reset;
	SetEntityGravity(victim, 1.0);
	SetEntPropFloat(victim, Prop_Send, "m_flLaggedMovementValue", 1.0);
	SDKUnhook(victim, SDKHook_WeaponCanUse, Event_ItemPickup);
	int wpn = GetClientWeaponEntIndex(victim, 0);
	if(wpn > -1)
		SDKUnhook(wpn, SDKHook_Reload, Event_WeaponReload);
}

void ActivateAutoPunish(int client) {
	if(hAutoPunish.IntValue & 2 == 2) 
		ApplyModeToClient(0, lastButtonUser, Troll_SpecialMagnet, TrollMod_None);
	if(hAutoPunish.IntValue & 1 == 1) 
		ApplyModeToClient(0, lastButtonUser, Troll_TankMagnet, TrollMod_None);
	if(hAutoPunish.IntValue & 8 == 8)
		ApplyModeToClient(0, lastButtonUser, Troll_VomitPlayer, TrollMod_None);
	else if(hAutoPunish.IntValue & 4 == 4) 
		ApplyModeToClient(0, lastButtonUser, Troll_Swarm, TrollMod_None);

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