
#define MAX_TROLL_NAME_LENGTH 32
#define MAX_TROLL_FLAG_LENGTH 32
//Allow MAX_TROLLS to be defined elsewhere
#if defined MAX_TROLLS
#else
    #define MAX_TROLLS 32
#endif

enum trollModifier {
    TrollMod_Invalid = 0,
	TrollMod_Instant = 1,
	TrollMod_Constant = 2
}

//up to 30 flags technically possiible
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

StringMap trollKV;
char trollIds[MAX_TROLLS+1][MAX_TROLL_NAME_LENGTH];
char DEFAULT_FLAG_PROMPT_MULTIPLE[] = "Choose flags (Multiple)";
char DEFAULT_FLAG_PROMPT[] = "Choose flags";
bool SilentMenuSelected[MAXPLAYERS+1];

static int g_trollAddPromptIndex;

enum struct TrollFlagPrompt {
    char promptText[MAX_TROLL_FLAG_LENGTH];
    int flags;
    int defaults;
    bool multiselect;
    int requireFlags;

    void GetPromptText(char[] prompt, int maxlength) {
        if(this.promptText[0] != '\0') {
            strcopy(prompt, maxlength, this.promptText);
        } else if(this.multiselect) {
            strcopy(prompt, maxlength, DEFAULT_FLAG_PROMPT_MULTIPLE);
        } else {
            strcopy(prompt, maxlength, DEFAULT_FLAG_PROMPT);
        }
    }
}

enum struct Troll {
    int id;
    int categoryID;

    char name[MAX_TROLL_NAME_LENGTH];
    char description[128];

    int mods;

    int activeFlagClients[MAXPLAYERS+1];
    ArrayList flagNames;
    bool flagsMultiselectable;
    char flagPrompt[MAX_TROLL_FLAG_LENGTH];
    ArrayList flagPrompts;

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

    int AddCustomFlagPrompt(const char[] promptText, bool multiselect = false, int requireFlags = 0) {
        TrollFlagPrompt prompt;
        prompt.multiselect = multiselect;
        prompt.requireFlags = requireFlags;
        strcopy(prompt.promptText, MAX_TROLL_FLAG_LENGTH, promptText);
        int index = this.flagPrompts.PushArray(prompt);
        g_trollAddPromptIndex = index;
        return index;
    }

    int AddFlagPrompt(bool multiselect = false, int requireFlags = 0) {
        //g_trollAddPromptIndex
        TrollFlagPrompt prompt;
        prompt.multiselect = multiselect;
        prompt.requireFlags = requireFlags;
        int index = this.flagPrompts.PushArray(prompt);
        g_trollAddPromptIndex = index;
        return index;
    }

    int AddFlag(const char[] name, bool defaultOn) {
        if(this.flagNames == null) this.flagNames = new ArrayList(MAX_TROLL_FLAG_LENGTH);

        int flagIndex = this.GetFlagIndex(name);
        if(flagIndex == -1) flagIndex = this.flagNames.PushString(name);
        
        static TrollFlagPrompt prompt;
        this.flagPrompts.GetArray(g_trollAddPromptIndex, prompt);

        prompt.flags |= (1 << flagIndex);

        if(defaultOn) {
            // If out of bounds, set to default -1 -> pick global prompt
            if(this.flagPrompts.Length == 0) {
                ThrowError("Troll \"%s\" does not have any flag prompts, thus a default value cannot be set. (flag=\"%s\")", this.name, name);
                return -1;
            }
            if(!prompt.multiselect && prompt.defaults > 0) {
                ThrowError("Flag \"%s\" cannot be set as default flag in single select mode, as one has already been set for prompt %d", name, g_trollAddPromptIndex);
                return -1;
            }
            prompt.defaults |= (1 << flagIndex);
        }
        this.flagPrompts.SetArray(g_trollAddPromptIndex, prompt); //May not be required
        return flagIndex;
    }

    int GetFlagIndex(const char[] flagName) {
        static char comprFlag[MAX_TROLL_FLAG_LENGTH]; 
        for(int i = 0; i < this.flagNames.Length; i++) {
            this.flagNames.GetString(i, comprFlag, sizeof(comprFlag));
            if(StrEqual(comprFlag, flagName)) {
                return i;
            }
        }
        return -1;
    }

    bool HasFlags() {
        return this.flagNames != null && this.flagNames.Length > 0 && this.flagPrompts.Length > 0;
    }

    bool IsFlagActive(int client, trollFlag flag) {
        return this.activeFlagClients[client] & view_as<int>(flag) != 0;
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

    void SetFlagPrompt(const char[] prompt) {
        strcopy(this.flagPrompt, MAX_TROLL_FLAG_LENGTH, prompt);
    }

    void GetFlagPrompt(int index, TrollFlagPrompt prompt) {
        this.flagPrompts.GetArray(index, prompt);
    }

/////// TROLL ACTIVATION

    void Activate(int client, int activator, trollModifier modifier = TrollMod_Invalid, int flags = 0) {
        if(modifier == TrollMod_Invalid) modifier = this.GetDefaultMod();
        ApplyTroll(client, this.name, activator, modifier, flags);
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
        return this.activeFlagClients[client] != -1;
    }
}

Troll Trolls[MAX_TROLLS+1];

ArrayList categories;
static int categoryID = -1;

void ResetClient(int victim, bool wipe = true) {
    if(victim == 0) return;
    if(wipe) {
        for(int i = 0; i <= MAX_TROLLS; i++) {
            Trolls[i].activeFlagClients[victim] = -1;
        }
    }
    SetEntityGravity(victim, 1.0);
    SetEntPropFloat(victim, Prop_Send, "m_flLaggedMovementValue", 1.0);
    SDKUnhook(victim, SDKHook_WeaponCanUse, Event_ItemPickup);
    int wpn = GetClientWeaponEntIndex(victim, 0);
    if(wpn > -1)
        SDKUnhook(wpn, SDKHook_Reload, Event_WeaponReload);
}

int SetupTroll(const char[] name, const char description[128], int mods, bool flagsMultiselectable = false) {
    if(mods == 0) {
        ThrowError("Troll \"%s\" has no flags defined.", name);
        return -1;
    }
    static int i = 0;
    if(i == MAX_TROLLS + 1) {
        ThrowError("Maximum number of trolls (%d) reached. Up MAX_TROLLS value.", MAX_TROLLS);
    }
    g_trollAddPromptIndex = 0;
    Trolls[i].id = i;
    strcopy(Trolls[i].name, MAX_TROLL_NAME_LENGTH, name);
    strcopy(Trolls[i].description, 128, description);
    Trolls[i].categoryID = categoryID;
    Trolls[i].mods = mods;
    Trolls[i].flagsMultiselectable = flagsMultiselectable;
    Trolls[i].flagPrompts = new ArrayList(sizeof(TrollFlagPrompt));

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
    PrintToServer("GetTroll: Troll was not found \"%s\"", name);
    return -1;
}
int GetTrollID(const char[] name) {
    static int i = 0;
    if(trollKV.GetValue(name, i)) {
        return i;
    }
    PrintToServer("GetTrollID: Troll was not found \"%s\"", name);
    return -1;
}

bool IsAnyTrollActive(int victim) {
    for(int i = 0; i <= MAX_TROLLS; i++) {
        if(Trolls[i].activeFlagClients[victim] >= 0) return true;
    }
    return false;
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
    GetTroll(name, troll);
    if(troll.IsActive(client))
        troll.activeFlagClients[client] = -1;
    else
        troll.activeFlagClients[client] = flags;
}

void ApplyTroll(int victim, const char[] name, int activator, trollModifier modifier, int flags = 0) {
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
    bool isActive = IsTrollActive(victim, troll.name);
    if(!SilentMenuSelected[activator]) {
        if(isActive) {
            ShowActivityEx(activator, "[FTT] ", "deactivated troll \"%s\" on %N. ", troll.name, victim);
            LogAction(activator, victim, "\"%L\" deactivated troll \"%s\" on \"%L\"", activator, troll.name, victim);
        } else {
            if(modifier == TrollMod_Constant) {
                if(flags > 0) {
                    ShowActivityEx(activator, "[FTT] ", "activated constant troll \"%s\" (%d) for %N. ", troll.name, flags, victim);
                } else
                    ShowActivityEx(activator, "[FTT] ", "activated constant troll \"%s\" for %N. ", troll.name, victim);
            } else if(flags > 0) 
				ShowActivityEx(activator, "[FTT] ", "activated troll \"%s\" (%d) for %N. ", troll.name, flags, victim);
            else 
				ShowActivityEx(activator, "[FTT] ", "activated troll \"%s\" for %N. ", troll.name, victim);
            
            LogAction(activator, victim, "\"%L\" activated troll \"%s\" (%d) for \"%L\"", activator, troll.name, flags, victim);
        }
    } else SilentMenuSelected[activator] = false;
    if(modifier == TrollMod_Constant) {
        Trolls[troll.id].activeFlagClients[victim] = isActive ? -1 : flags;
    }
}

bool IsTrollActive(int client, const char[] troll) {
    if(troll[0] == '\0') {
        ThrowError("Troll name is empty");
        return false;
    }
    static int i = 0;
    if(trollKV.GetValue(troll, i)) {
        return Trolls[i].activeFlagClients[client] != -1;
    }
    ThrowError("Troll \"%s\" does not exist", troll);
    return false; //errors instead but compiler no like
}

bool IsTrollActiveByRawID(int client, int id) {
    return Trolls[id].activeFlagClients[client] != -1;
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

public void SetCategory(const char[] newCat) {
    categoryID = categories.FindString(newCat);
    if(categoryID == -1)
        categoryID = categories.PushString(newCat);
}
void GetCategory(int category, char[] buffer, int size) {
    categories.GetString(category, buffer, size);
} 
