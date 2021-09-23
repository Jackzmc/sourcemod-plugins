
#define MAX_TROLL_NAME_LENGTH 32
#define MAX_TROLLS 25
//#define DEBUG 1

enum trollModifier {
    TrollMod_Invalid = 0,
	TrollMod_Instant = 1,
	TrollMod_Constant = 2
}


enum struct Troll {
    char name[32];
    char description[128];

    bool runsOnce;
    int flags;

    void GetID(char[] name, int length) {
        strcopy(name, length, this.name);
        ReplaceString(name, MAX_TROLL_NAME_LENGTH, " ", "", false);
    }

    bool HasMod(trollModifier mod) {
        return ((this.flags >> view_as<int>(mod)) & 1) == view_as<int>(mod);
    }

    // Gets the default modifier to use
    trollModifier GetDefaultMod() {
        // If the flags is equal to the 2^n flag, then it must be the only flag:
        if(this.flags == view_as<int>(TrollMod_Instant)) return TrollMod_Instant;
        else if(this.flags == view_as<int>(TrollMod_Constant)) return TrollMod_Constant;
        else return TrollMod_Invalid;
    }
}

Troll Trolls[MAX_TROLLS+1];
int ActiveTrolls[MAXPLAYERS+1];

StringMap trollKV;
char trollIds[MAX_TROLLS+1][MAX_TROLL_NAME_LENGTH];

void ResetClient(int victim, bool wipe = true) {
	if(wipe) ActiveTrolls[victim] = 0;
	SetEntityGravity(victim, 1.0);
	SetEntPropFloat(victim, Prop_Send, "m_flLaggedMovementValue", 1.0);
	SDKUnhook(victim, SDKHook_WeaponCanUse, Event_ItemPickup);
	int wpn = GetClientWeaponEntIndex(victim, 0);
	if(wpn > -1)
		SDKUnhook(wpn, SDKHook_Reload, Event_WeaponReload);
}

int SetupTroll(const char[] name, const char description[128], int flags) {
    if(flags == 0) {
        ThrowError("Troll has no flags defined.");
        return -1;
    }
    static int i = 0;
    strcopy(Trolls[i].name, MAX_TROLL_NAME_LENGTH, name);
    strcopy(Trolls[i].description, 128, description);
    Trolls[i].flags = flags;
    static char key[MAX_TROLL_NAME_LENGTH];
    strcopy(key, MAX_TROLL_NAME_LENGTH, name);
    ReplaceString(key, MAX_TROLL_NAME_LENGTH, " ", "", false);
    strcopy(trollIds[i], MAX_TROLL_NAME_LENGTH, key); 
    trollKV.SetValue(key, i);
    return i++;
}
// Gets the Troll enum struct via name
// Returns index of troll enum
int GetTroll(const char[] name, Troll troll) {
    static int i = 0;
    if(trollKV.GetValue(name, i)) {
        troll = Trolls[i];
        return i;
    }
    return -1;
}
// Gets the Troll enum struct via key index
// Returns index of troll enum
int GetTrollByKeyIndex(int index, Troll troll) {
    // static char name[MAX_TROLL_NAME_LENGTH];
    // trollIds.GetKey(index, name, sizeof(name));
    troll = Trolls[index];
    // return GetTroll(name, troll);
}

bool GetTrollID(int index, char name[MAX_TROLL_NAME_LENGTH]) {
    if(index > MAX_TROLLS) return false;
    strcopy(name, sizeof(name), trollIds[index]);
    return true;
}

void ToggleTroll(int client, const char[] name) {
    static Troll troll;
    int index = GetTroll(name, troll);
    ActiveTrolls[client] ^= 1 << view_as<int>(index);
}

void ApplyTroll(int victim, const char[] name, int activator, trollModifier modifier, bool silent = false) {
    static Troll troll;
    int trollIndex = GetTroll(name, troll);
    if(trollIndex == -1) {
        PrintToServer("[FTT] %N attempted to apply unknown troll: %s", activator, name);
        return;
    }
    if(GetClientTeam(victim) == 1) {
		//Victim is spectating, find its bot
		victim = FindIdlePlayerBot(victim);
	}

    ApplyAffect(victim, name, activator, modifier);

    if(!silent) {
        if(IsTrollActive(victim, name)) {
            ShowActivity(victim, "deactivated troll \"%s\" on %N. ", troll.name, victim);
        } else {
            if(modifier == TrollMod_Constant)
				ShowActivity(victim, "activated troll \"%s\" on repeat for %N. ", troll.name, victim);
			else
				ShowActivity(victim, "activated troll \"%s\" for %N. ", troll.name, victim);
        }
    }
    if(modifier == TrollMod_Constant) {
        ActiveTrolls[victim] ^= 1 << trollIndex;
    }
}

void ApplyAffect(int victim, const char[] name, int activator, trollModifier modifier) {
    if(StrEqual(name, "ResetTroll")) {
        ShowActivity(activator, "reset troll effects for %N. ", victim);
        ActiveTrolls[victim] = 0;
        return;
    } else if(StrEqual(name, "SlowSpeed"))
        SetEntPropFloat(victim, Prop_Send, "m_flLaggedMovementValue", 0.8);
    else if(StrEqual(name, "HigherGravity"))
        SetEntityGravity(victim, 1.3);
    else if(StrEqual(name, "HalfPrimaryAmmo")) {
        int current = GetPrimaryReserveAmmo(victim);
        SetPrimaryReserveAmmo(victim, current / 2);
    } else if(StrEqual(name, "UziRules")) {
        DisableTroll(victim, "NoPickup");
        DisableTroll(victim, "PrimaryDisable");
        SDKHook(victim, SDKHook_WeaponCanUse, Event_ItemPickup);
    } else if(StrEqual(name, "PrimaryDisable")) {
        DisableTroll(victim, "UziRules");
        DisableTroll(victim, "NoPickup");
        SDKHook(victim, SDKHook_WeaponCanUse, Event_ItemPickup);
    } else if(StrEqual(name, "NoPickup")) {
        DisableTroll(victim, "UziRules");
        DisableTroll(victim, "PrimaryDisable");
        SDKHook(victim, SDKHook_WeaponCanUse, Event_ItemPickup);
    } else if(StrEqual(name, "Clumsy")) {
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
                    // g_iTrollUsers[victim] = mode;
                    CreateTimer(0.2, Timer_GivePistol);
                    return;
                }
            }
            SDKHooks_DropWeapon(victim, wpn);
        }
    } else if(StrEqual(name, "CameTooEarly")) {
        ReplyToCommand(activator, "This troll mode is not implemented.");
    } else if(StrEqual(name, "KillMeSoftly")) {
        static char wpn[32];
        GetClientWeaponName(victim, 4, wpn, sizeof(wpn));
        if(StrEqual(wpn, "weapon_adrenaline") || StrEqual(wpn, "weapon_pain_pills")) {
            ClientCommand(victim, "slot5");
            g_bPendingItemGive[victim] = true;
        }else{
            ReplyToCommand(activator, "User does not have pills or adrenaline");
            return;
        }
        //TODO: Implement TrollMod_Constant
        return;
    } else if(StrEqual(name, "ThrowItAll")) {
        if(modifier == TrollMod_Instant)
            ThrowAllItems(victim);
        if(hThrowTimer == INVALID_HANDLE && modifier == TrollMod_Constant) {
            hThrowTimer = CreateTimer(hThrowItemInterval.FloatValue, Timer_ThrowTimer, _, TIMER_REPEAT);
        }
    } else if(StrEqual(name, "Swarm")) {
        if(modifier == TrollMod_Instant) {
            L4D2_RunScript("RushVictim(GetPlayerFromUserID(%d), %d)", victim, 15000);
        }else if(modifier == TrollMod_Constant) {
            
        }else{
            ReplyToCommand(activator, "Invalid modifier for mode.");
            return;
        }
    } else if(StrEqual(name, "GunJam")) {
        int wpn = GetClientWeaponEntIndex(victim, 0);
        if(wpn > -1)
            SDKHook(wpn, SDKHook_Reload, Event_WeaponReload);
        else
            ReplyToCommand(activator, "Victim does not have a primary weapon.");
    } else if(StrEqual(name, "VomitPlayer"))
        L4D_CTerrorPlayer_OnVomitedUpon(victim, victim);
    else {
        #if defined DEBUG
        PrintToServer("[FTT] Possibly invalid troll, no action: %s", name);
        ReplyToCommand(activator, "[FTT/Debug] If nothing occurs, this troll possibly was not implemented correctly. ");
        #endif
    }
}

bool IsTrollActive(int client, const char[] troll) {
    if(ActiveTrolls[client] == 0) return false;
    static int i = 0;
    if(trollKV.GetValue(troll, i)) {
        return ((ActiveTrolls[client] >> i) & 1) == 1;
    }
    ThrowError("Troll \"%s\" does not exist", troll);
    return false; //errors instead but compiler no like
}

void EnableTroll(int client, const char[] troll) {
    if(!IsTrollActive(client, troll)) {
        ToggleTroll(client, troll);
    } 
}

void DisableTroll(int client, const char[] troll) {
    if(IsTrollActive(client, troll)) {
        ToggleTroll(client, troll);
    } 
}


void SetupTrolls() {
    trollKV = new StringMap();
    SetupTroll("Reset Troll", "Resets the user, removes all troll effects", TrollMod_Instant);
    SetupTroll("Special Magnet", "Attracts ALL specials to any alive target with this troll enabled", TrollMod_Constant);
    SetupTroll("Tank Magnet", "Attracts ALL tanks to any alive target with this troll enabled", TrollMod_Constant);
    SetupTroll("Witch Magnet", "All witches when startled will target any player with this troll", TrollMod_Constant);
    SetupTroll("Vomit Player", "Shortcut to sm_vomitplayer. vomits the player.", TrollMod_Instant);
    SetupTroll("ThrowItAll", "Player throws all their items at nearby player, periodically", TrollMod_Instant | TrollMod_Constant);
    SetupTroll("Vocalize Gag", "Prevents player from sending any vocalizations (even automatic)", TrollMod_Constant);
    SetupTroll("No Profanity", "Replaces some words with random phrases", TrollMod_Constant);
    SetupTroll("Swarm", "Swarms a player with zombies. Requires swarm plugin", TrollMod_Instant);
    SetupTroll("UziRules", "Picking up a weapon gives them a UZI instead", TrollMod_Constant);
    SetupTroll("Slow Speed", "Sets player speed to 0.8x of normal speed", TrollMod_Constant);
    SetupTroll("Higher Gravity", "Sets player gravity to 1.3x of normal gravity", TrollMod_Constant);
    SetupTroll("Half Primary Ammo", "Cuts their primary reserve ammo in half", TrollMod_Instant);
    SetupTroll("PrimaryDisable", "Player cannot pickup any weapons, only melee/pistols", TrollMod_Constant);
    SetupTroll("Clusmy", "Player drops axe periodically or on demand", TrollMod_Instant | TrollMod_Constant);
    SetupTroll("iCantSpellNoMore", "Chat messages letter will randomly changed with wrong letters", TrollMod_Instant);
    SetupTroll("KillMeSoftly", "Make player eat or waste pills whenever possible", TrollMod_Instant | TrollMod_Constant);
    SetupTroll("GunJam", "On reload, small chance their gun gets jammed - Can't reload.", TrollMod_Constant);
    SetupTroll("NoPickup", "Prevents a player from picking up ANY (new) item. Use ThrowItAll to make them drop", TrollMod_Constant);
    SetupTroll("Honk", "Honk", TrollMod_Constant);
    SetupTroll("No Shove", "Prevents a player from shoving", TrollMod_Constant);
    SetupTroll("Damage Boost", "Makes a player take more damage than normal", TrollMod_Constant);
    SetupTroll("Temp Health Quick Drain", "Makes a player's temporarily health drain very quickly", TrollMod_Constant);
    SetupTroll("Slow Drain", "Will make the player slowly lose health over time", TrollMod_Constant);
    SetupTroll("CameTooEarly", "When they shoot, random chance they empty whole clip", TrollMod_Constant);
    SetupTroll("Meow", "Makes the player meow", false);
    //INFO: UP MAX_TROLLS when adding new trolls!
}