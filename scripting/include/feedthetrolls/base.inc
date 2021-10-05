
#define MAX_TROLL_NAME_LENGTH 32
#define MAX_TROLL_FLAG_LENGTH 32
//Allow MAX_TROLLS to be defined elsewhere
#if defined MAX_TROLLS
#else
    #define MAX_TROLLS 31
#endif

enum trollModifier {
    TrollMod_Invalid = 0,
	TrollMod_Instant = 1,
	TrollMod_Constant = 2
}

enum trollFlag {
    Flag_1 = 1 << 0,
    Flag_2 = 1 << 1,
    Flag_3 = 1 << 2,
    Flag_4 = 1 << 3,
    Flag_5 = 1 << 4,
    Flag_6 = 1 << 5,
    Flag_7 = 1 << 6,
    Flag_8 = 1 << 7,
}

int ActiveTrolls[MAXPLAYERS+1];

StringMap trollKV;
char trollIds[MAX_TROLLS+1][MAX_TROLL_NAME_LENGTH];

enum struct Troll {
    int id;
    int categoryID;

    char name[MAX_TROLL_NAME_LENGTH];
    char description[128];

    int mods;

    int activeFlagClients[MAXPLAYERS+1];
    ArrayList flagNames;
    int defaultFlags;
    bool flagsMultiselectable;

    bool HasMod(trollModifier mod) {
        return ((this.mods >> (view_as<int>(mod)) - 1) & 1) == 1;
    }

    // Gets the default modifier to use
    trollModifier GetDefaultMod() {
        // If the flags is equal to the 2^n flag, then it must be the only flag:
        if(this.mods == view_as<int>(TrollMod_Instant)) return TrollMod_Instant;
        else if(this.mods == view_as<int>(TrollMod_Constant)) return TrollMod_Constant;
        else return TrollMod_Invalid;
    }

/////// FLAGS

    bool GetFlagName(int index, char[] buffer, int maxlength) {
        if(this.flagNames == null) return false;
        this.flagNames.GetString(index, buffer, maxlength);
        return true;
    }


    int AddFlag(const char[] name, bool defaultOn) {
        if(defaultOn && !this.flagsMultiselectable && this.defaultFlags > 0) {
            ThrowError("Flag \"%s\" cannot be set as default flag in single select mode, as one has already been set (%d)", name, this.defaultFlags);
            return -1;
        }
        if(this.flagNames == null) this.flagNames = new ArrayList(MAX_TROLL_FLAG_LENGTH);
        int index = this.flagNames.PushString(name);
        index = RoundFloat(Pow(2.0, float(index)));
        if(defaultOn)
            this.defaultFlags |= 1 << index;
        return index;
    }

    bool HasFlags() {
        return this.flagNames != null && this.flagNames.Length > 0;
    }


    bool IsFlagActive(int client, trollFlag flag) {
        if(ActiveTrolls[client] > 0 && IsTrollActive(client, this.name) && this.activeFlagClients[client] >= 0) {
            return this.activeFlagClients[client] & view_as<int>(flag) != 0;
        } 
        return false;
    }

    bool IsFlagNameActive(int client, const char[] flagName) {
        static char buffer[MAX_TROLL_FLAG_LENGTH];
        for(int i = 0; i < this.flagNames.Length; i++) {
            this.flagNames.GetString(i, buffer, sizeof(buffer));
            if(StrEqual(buffer, flagName, false)) return this.IsFlagActive(client, view_as<trollFlag>(i));
        }
        return false;
    }

    int GetClientFlags(int client) {
        return this.activeFlagClients[client];
    }

/////// TROLL ACTIVATION

    void Activate(int client, int activator, trollModifier modifier = TrollMod_Invalid, int flags = 0) {
        if(modifier == TrollMod_Invalid) modifier = this.GetDefaultMod();
        ApplyTroll(client, this.name, activator, modifier, false, flags);
    }

    void Toggle(int client, int flags) {
        ToggleTroll(client, this.name, flags);
    }

    void Enable(int client, int flags) {
        EnableTroll(client, this.name, flags);
    }

    void Disable(int client) {
        DisableTroll(client, this.name);
    }

    bool IsActive(int client) {
        return IsTrollActive(client, this.name);
    }
}

Troll Trolls[MAX_TROLLS+1];

ArrayList categories;
static int categoryID = -1;

void ResetClient(int victim, bool wipe = true) {
	if(wipe) {
        ActiveTrolls[victim] = 0;
    }
	SetEntityGravity(victim, 1.0);
	SetEntPropFloat(victim, Prop_Send, "m_flLaggedMovementValue", 1.0);
	SDKUnhook(victim, SDKHook_WeaponCanUse, Event_ItemPickup);
	int wpn = GetClientWeaponEntIndex(victim, 0);
	if(wpn > -1)
		SDKUnhook(wpn, SDKHook_Reload, Event_WeaponReload);
}


int SetupTroll(const char[] name, const char description[128], int mods, bool flagsMultiselectable = false, int defaultFlags = 0) {
    if(mods == 0) {
        ThrowError("Troll \"%s\" has no flags defined.", name);
        return -1;
    }
    static int i = 0;
    Trolls[i].id = i;
    strcopy(Trolls[i].name, MAX_TROLL_NAME_LENGTH, name);
    strcopy(Trolls[i].description, 128, description);
    Trolls[i].categoryID = categoryID;
    Trolls[i].mods = mods;
    Trolls[i].flagsMultiselectable = flagsMultiselectable;

    strcopy(trollIds[i], MAX_TROLL_NAME_LENGTH, name); 
    trollKV.SetValue(name, i);
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
int GetTrollIndex(const char[] name) {
    static int i = 0;
    if(trollKV.GetValue(name, i)) {
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

void ToggleTroll(int client, const char[] name, int flags = 0) {
    static Troll troll;
    int index = GetTroll(name, troll);
    ActiveTrolls[client] ^= 1 << view_as<int>(index);
    troll.activeFlagClients[client] = flags;
}
void ApplyTroll(int victim, const char[] name, int activator, trollModifier modifier, bool silent = false, int flags = 0) {
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

    if(!ApplyAffect(victim, troll, activator, modifier, flags)) {
        return;
    }
    if(!silent) {
        if(IsTrollActive(victim, troll.name)) {
            ShowActivityEx(activator, "[FTT] ", "deactivated troll \"%s\" on %N. ", troll.name, victim);
            LogAction(activator, victim, "\"%L\" deactivated troll \"%s\" on \"%L\"", activator, troll.name, victim);
        } else {
            if(modifier == TrollMod_Constant) {
                if(flags > 0) {
                    ShowActivityEx(activator, "[FTT] ", "activated constant troll \"%s\" with flags=%d for %N. ", troll.name, flags, victim);
                } else
                    ShowActivityEx(activator, "[FTT] ", "activated constant troll \"%s\" for %N. ", troll.name, victim);
            } else if(flags > 0) 
				ShowActivityEx(activator, "[FTT] ", "activated troll \"%s\" with flags=%d for %N. ", troll.name, flags, victim);
            else 
				ShowActivityEx(activator, "[FTT] ", "activated troll \"%s\" for %N. ", troll.name, victim);
            
            LogAction(activator, victim, "\"%L\" activated troll \"%s\" with flags=%d for \"%L\"", activator, troll.name, flags, victim);
        }
    }
    if(modifier == TrollMod_Constant) {
        ActiveTrolls[victim] ^= 1 << trollIndex;
    }
    Trolls[troll.id].activeFlagClients[victim] = flags;
}

bool ApplyAffect(int victim, const Troll troll, int activator, trollModifier modifier, int flags) {
    bool isActive = IsTrollActiveByRawID(victim, troll.id);
    if(StrEqual(troll.name, "Reset User")) {
        LogAction(activator, victim, "\"%L\" reset all troll effects for \"%L\"", activator, victim);
        ShowActivityEx(activator, "[FTT] ", "reset troll effects for %N. ", victim);
        ActiveTrolls[victim] = 0;
        troll.activeFlagClients[victim] = 0;
        SetEntPropFloat(victim, Prop_Send, "m_flLaggedMovementValue", 1.0);
        SetEntityGravity(victim, 1.0);
        return false;
    } else if(StrEqual(troll.name, "Slow Speed"))
        if(isActive)
            SetEntPropFloat(victim, Prop_Send, "m_flLaggedMovementValue", 1.0);
        else
            SetEntPropFloat(victim, Prop_Send, "m_flLaggedMovementValue", 0.8);
    else if(StrEqual(troll.name, "Higher Gravity"))
        if(isActive)
            SetEntityGravity(victim, 1.0);
        else
            SetEntityGravity(victim, 1.3);
    else if(StrEqual(troll.name, "Half Primary Ammo")) {
        int current = GetPrimaryReserveAmmo(victim);
        SetPrimaryReserveAmmo(victim, current / 2);
    } else if(StrEqual(troll.name, "UziRules")) {
        DisableTroll(victim, "No Pickup");
        DisableTroll(victim, "Primary Disable");
        SDKHook(victim, SDKHook_WeaponCanUse, Event_ItemPickup);
    } else if(StrEqual(troll.name, "Primary Disable")) {
        DisableTroll(victim, "UziRules");
        DisableTroll(victim, "No Pickup");
        SDKHook(victim, SDKHook_WeaponCanUse, Event_ItemPickup);
    } else if(StrEqual(troll.name, "No Pickup")) {
        DisableTroll(victim, "UziRules");
        DisableTroll(victim, "Primary Disable");
        SDKHook(victim, SDKHook_WeaponCanUse, Event_ItemPickup);
    } else if(StrEqual(troll.name, "CameTooEarly")) {
        ReplyToCommand(activator, "This troll mode is not implemented.");
    } else if(StrEqual(troll.name, "KillMeSoftly")) {
        static char wpn[32];
        GetClientWeaponName(victim, 4, wpn, sizeof(wpn));
        if(StrEqual(wpn, "weapon_adrenaline") || StrEqual(wpn, "weapon_pain_pills")) {
            ClientCommand(victim, "slot5");
            g_bPendingItemGive[victim] = true;
        }else{
            ReplyToCommand(activator, "User does not have pills or adrenaline");
            return false;
        }
        //TODO: Implement TrollMod_Constant
        return false;
    } else if(StrEqual(troll.name, "Throw It All")) {
        if(modifier == TrollMod_Instant)
            ThrowAllItems(victim);
        if(hThrowTimer == INVALID_HANDLE && modifier == TrollMod_Constant) {
            hThrowTimer = CreateTimer(hThrowItemInterval.FloatValue, Timer_ThrowTimer, _, TIMER_REPEAT);
        }
    } else if(StrEqual(troll.name, "Swarm")) {
        if(modifier == TrollMod_Instant) {
            L4D2_RunScript("RushVictim(GetPlayerFromUserID(%d), %d)", victim, 15000);
        }
        return true;
    } else if(StrEqual(troll.name, "Gun Jam")) {
        int wpn = GetClientWeaponEntIndex(victim, 0);
        if(wpn > -1)
            SDKHook(wpn, SDKHook_Reload, Event_WeaponReload);
        else {
            ReplyToCommand(activator, "Victim does not have a primary weapon.");
            return false;
        }
    } else if(StrEqual(troll.name, "Vomit Player"))
        L4D_CTerrorPlayer_OnVomitedUpon(victim, victim);
    else if(StrEqual(troll.name, "Inface Special")) {
        FakeClientCommand(victim, "sm_inface");
        return false;
    } else if(StrEqual(troll.name, "Insta Special")) {
        FakeClientCommand(victim, "sm_insta");
        return false;
    } else if(StrEqual(troll.name, "Goo")) {
        static float pos[3], ang[3];
        GetClientAbsOrigin(victim, pos);
        GetClientAbsAngles(victim, ang);
        L4D2_SpitterPrj(victim, pos, ang);
    } else if(StrEqual(troll.name, "Stagger")) {
        L4D_StaggerPlayer(victim, victim, NULL_VECTOR);
    } else {
        #if defined DEBUG
        PrintToServer("[FTT] Possibly invalid troll, no action: %s", troll.name);
        ReplyToCommand(activator, "[FTT/Debug] If nothing occurs, this troll possibly was not implemented correctly. ");
        #endif
    }
    return true;
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

bool IsTrollActiveByRawID(int client, int id) {
    if(ActiveTrolls[client] == 0) return false;
    return ((ActiveTrolls[client] >> id) & 1) == 1;
}


void EnableTroll(int client, const char[] troll, int flags = 0) {
    if(!IsTrollActive(client, troll)) {
        ToggleTroll(client, troll, flags);
    } 
}

void DisableTroll(int client, const char[] troll) {
    if(IsTrollActive(client, troll)) {
        ToggleTroll(client, troll);
    } 
}

void SetCategory(const char[] newCat) {
    categoryID = categories.PushString(newCat);
}
void GetCategory(int category, char[] buffer, int size) {
    categories.GetString(category, buffer, size);
} 
