#define TROLL_MODE_COUNT 15
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
	Troll_Swarm //14
}
enum TrollModifer {
	TrollMod_None = 0,
	TrollMod_InstantFire = 1,
	TrollMod_Repeat = 2
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
	"Swarm"
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
	"Swarms a player with zombies. Requires swarm plugin"
};
int iTrollUsers[MAXPLAYERS+1];

//Applies the selected trollMode to the victim.
//Modifiers are as followed: 0 -> Both (fire instant, and timer), 1 -> Fire Once, 2 -> Start timer
void ApplyModeToClient(int client, int victim, trollMode mode, TrollModifer modifiers) {
	ResetClient(victim, false);
	if(view_as<int>(mode) > TROLL_MODE_COUNT || view_as<int>(mode) < 0) {
		ReplyToCommand(client, "Unknown troll mode ID '%d'. Pick a mode between 1 and %d", mode, TROLL_MODE_COUNT - 1);
		return;
	}
	//bool activating = !HasTrollMode(victim, mode);
	bool hasActivationMod = (modifiers & ~TrollMod_InstantFire & ~TrollMod_Repeat) == TrollMod_None;

	switch(mode) {
		case Troll_Reset: {
			ShowActivity(client, "reset troll effects for %N. ", victim);
			iTrollUsers[victim] = Troll_Reset;
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
						iTrollUsers[victim] = mode;
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
		case Troll_ThrowItAll: {
			if(!hasActivationMod || (modifiers | TrollMod_InstantFire) == TrollMod_InstantFire)
				ThrowAllItems(victim);
			if(hThrowTimer == INVALID_HANDLE && (!hasActivationMod|| (modifiers | TrollMod_Repeat) == TrollMod_Repeat)) {
				PrintToServer("Created new throw item timer");
				hThrowTimer = CreateTimer(hThrowItemInterval.FloatValue, Timer_ThrowTimer, _, TIMER_REPEAT);
			}
		}
		case Troll_Swarm: {
			if((modifiers | TrollMod_InstantFire) == TrollMod_InstantFire) {
				FakeClientCommandEx(client, "sm_swarm #%d", victim);
			}else if((modifiers | TrollMod_Repeat) == TrollMod_Repeat) {
				FakeClientCommandEx(client, "sm_swarmtoggle #%d", victim);
			}else{
				ReplyToCommand(client, "Invalid modifier for mode.");
				return;
			}
			//TODO: Implement swarm
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
	ShowActivity(client, "activated troll mode \"%s\" on %N. ", TROLL_MODES_NAMES[mode], victim);
	//If instant fire mod not provided (aka instead of no modifiers which equals both) OR repeat turned on, set bit:
	if((modifiers | TrollMod_InstantFire) != TrollMod_InstantFire || ((modifiers | TrollMod_Repeat) == TrollMod_Repeat)) {
		iTrollUsers[victim]  |= 1 << (view_as<int>(mode) - 1);
	}
}

bool HasTrollMode(int client, trollMode mode) {
	return ((iTrollUsers[client] >> view_as<int>(mode) - 1) & 1) == 1;
}

void ToggleTrollMode(int client, trollMode mode) {
	iTrollUsers[client] ^= 1 << view_as<int>(mode) -1;
}

void TurnOffTrollMode(int client, trollMode mode) {
	if(HasTrollMode(client, mode)) {
		ToggleTrollMode(client, mode);
	}
}

void ResetClient(int victim, bool wipe = true) {
	if(wipe) iTrollUsers[victim] = Troll_Reset;
	SetEntityGravity(victim, 1.0);
	SetEntPropFloat(victim, Prop_Send, "m_flLaggedMovementValue", 1.0);
	SDKUnhook(victim, SDKHook_WeaponCanUse, Event_ItemPickup);
	int wpn = GetClientWeaponEntIndex(victim, 0);
	if(wpn > -1)
		SDKUnhook(wpn, SDKHook_Reload, Event_WeaponReload);
}