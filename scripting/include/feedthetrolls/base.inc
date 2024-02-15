
#define MAX_TROLL_NAME_LENGTH 32
#define MAX_TROLL_FLAG_LENGTH 32
//Allow MAX_TROLLS to be defined elsewhere
#if defined MAX_TROLLS
#else
    #define MAX_TROLLS 56
#endif

Troll t_metaReverse;

enum trollModifier {
    TrollMod_Invalid = 0,
	TrollMod_Instant = 1 << 0,
	TrollMod_Constant = 1 << 1,
    TrollMod_PlayerOnly = 1 << 2, // Does the troll only work on players, not bots? If set, troll only applied on real user. If not, troll applied to both bot and idler
}

enum TrollEffectResponse { 
	TE_Success, // Success, continue menu
	TE_Error, // Error, continue menu (retry)
	TE_Menu // Switching menus / etc, don't continue menu
}

typedef ActivateFunction = function void (Troll troll, int activator, int victim, int flags, trollModifier mod);
typedef ResetFunction = function void (Troll troll, int activator, int victim);
typedef PromptActivateFunction = function TrollEffectResponse (Troll troll, int activator, int victim, any data, int flags, trollModifier mod);

StringMap trollKV;
char trollIds[MAX_TROLLS+1][MAX_TROLL_NAME_LENGTH];
char DEFAULT_FLAG_PROMPT_MULTIPLE[] = "Enable options (Multiple)";
char DEFAULT_FLAG_PROMPT[] = "Select an option";
bool SilentMenuSelected[MAXPLAYERS+1];

static int g_trollAddPromptIndex;

char SPECIAL_NAMES[][] = {
	"Smoker", "Boomer", "Hunter", "Spitter", "Jockey", "Charger", "Witch", "Tank"
};

enum struct TrollFlagPrompt {
    char promptText[MAX_TROLL_FLAG_LENGTH];
    // enabled flags
    int flags;
    // default values
    int defaults;
    // is multiple flags selectable?
    bool multiselect;
    // flags that need to be active to show this prompt
    int requireFlags;

    PrivateForward activateFn;

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

enum struct TrollOptionData {
    char name[MAX_TROLL_FLAG_LENGTH];
    int data; // can also be float
}

enum struct TrollData {
    int id; // The id or the index into the global Trolls[] array
    int categoryID; // The category this troll belongs in

    char name[MAX_TROLL_NAME_LENGTH];
    char description[128];
    bool hidden;

    PrivateForward activateFn;
    PrivateForward resetFn;

    int mods; // Combination of valid modifiers. Only two are ever supported

    // Flags
    int activeFlagClients[MAXPLAYERS+1];
    ArrayList flagNames;
    ArrayList promptOptions;
    ArrayList flagPrompts;

    // Custom timer
    Timer timerFunction;
    Handle timerHandles[MAXPLAYERS+1];
    float timerInterval;
    int timerRequiredFlags;

    void Toggle(int client, int flags) {
        if(this.IsActive(client)) {
            this.Disable(client);
        } else {
            this.Enable(client, flags);
        }
    }

    void Enable(int client, int flags) {
        this.activeFlagClients[client] = flags;
        // If a timer is assigned, start it:
        if(this.timerHandles[client] != null) {
            delete this.timerHandles[client];
            PrintToServer("FTT Debug: Old timer for %N, killing", client);
        }
        if(this.timerInterval > 0.0) {
            this.timerHandles[client] = CreateTimer(this.timerInterval, this.timerFunction, GetClientUserId(client), TIMER_REPEAT);
        }
    }

    void Disable(int client) {
        this.activeFlagClients[client] = -1;
        // Stop any running timer:
        if(this.timerHandles[client] != null) {
            PrintToServer("FTT Debug: Disabling timer for %N", client);
            delete this.timerHandles[client];
        }
        if(this.resetFn != null) {
            Call_StartForward(this.resetFn);
            Call_PushCell(0);
            Call_PushCell(client);
            Call_PushCell(0);
            Call_Finish();
        }
    }

    bool IsActive(int client) {
        return this.activeFlagClients[client] != -1;
    }

}

TrollData Trolls[MAX_TROLLS+1];

ArrayList categories;
static int categoryID = -1;

void ResetClient(int victim, bool wipe = true) {
    if(victim == 0 || !IsClientConnected(victim)) return;
    if(wipe) {
        for(int i = 1; i <= MAX_TROLLS; i++) {
            Troll(i).Reset(victim);
        }
    }
    // TODO: move to reset functions!!
    noRushingUsSpeed[victim] = 1.0;
    BaseComm_SetClientMute(victim, false);
    SetEntityGravity(victim, 1.0);
    SetEntPropFloat(victim, Prop_Send, "m_flLaggedMovementValue", 1.0);
    SetEntProp(victim, Prop_Send, "m_iHideHUD", 0)
    SDKUnhook(victim, SDKHook_WeaponCanUse, Event_ItemPickup);
    int wpn = GetClientWeaponEntIndex(victim, 0);
    if(wpn > -1)
        SDKUnhook(wpn, SDKHook_Reload, Event_WeaponReload);
}

// TrollInstance of TrollData
methodmap Troll {
    public Troll(int index) {
        return view_as<Troll>(index);
    }

    public static Troll FromName(const char[] name) {
        int i = GetTrollID(name);
        if(i == -1)
            LogError("Unknown troll \"%s\"", name);
        return view_as<Troll>(i);
    }
    property bool Hidden {
        public get() { return Trolls[this.Id].hidden; }
    }
    property int CategoryId {
        public get() { return Trolls[this.Id].categoryID; }
    }
    property int PromptCount {
        public get() { return Trolls[this.Id].flagPrompts.Length; }
    }
    property int TotalOptionsCount {
        public get() { 
            return Trolls[this.Id].promptOptions == null ? -1 : Trolls[this.Id].promptOptions.Length; 
        }
    }
    property bool HasTimer {
        public get() { return Trolls[this.Id].timerInterval > 0.0; }
    }
    property int Id {
        public get() { return view_as<int>(this); }
    }
    property bool HasOptions {
        public get() { return this.TotalOptionsCount > 0; }
    }

    public bool IsActive(int client) {
        return Trolls[this.Id].activeFlagClients[client] != -1;
    }

    public bool HasFlag(int client, int flag) {
        return Trolls[this.Id].activeFlagClients[client] & flag != 0;
    }

    public int GetFlags(int client) {
        return Trolls[this.Id].activeFlagClients[client]
    }

    public bool HasMod(trollModifier mod) {
        return Trolls[this.Id].mods & view_as<int>(mod) != 0;
    }

    public void GetName(char[] output, int maxlen) {
        strcopy(output, maxlen, Trolls[this.Id].name);
    }

    public TrollEffectResponse Activate(int activator, int victim, trollModifier modifier = TrollMod_Invalid, int flags = 0, bool silent = false) {
        PrintToServer("Activate: act:%d vic:%d", activator, victim);
        if(modifier == TrollMod_Invalid) modifier = this.GetDefaultMod();
        return ApplyTroll(victim, this, activator, modifier, flags, silent);
    }
    public void Reset(int victim) {
        Trolls[this.Id].activeFlagClients[victim] = -1;
        if(Trolls[this.Id].resetFn != null) {
            Call_StartForward(Trolls[this.Id].resetFn);
            Call_PushCell(this);
            Call_PushCell(0);
            Call_PushCell(victim);
            Call_PushCell(0);
            Call_Finish();
        }
    }

    public bool GetOptionData(int optionIndex, TrollOptionData data) {
        if(optionIndex < 0 || optionIndex >= Trolls[this.Id].promptOptions.Length) return false;
        Trolls[this.Id].promptOptions.GetArray(optionIndex, data);
        return true;
    }

    /// If prompt is NOT multiselect, returns the selected value from the option's data property
    public bool GetPromptDataInt(int client, int promptIndex, int &out) {
        if(promptIndex < 0 || promptIndex >= Trolls[this.Id].flagPrompts.Length) {
            ThrowError(".GetPromptData called with invalid prompt index (%d, max %d) on troll #%d", promptIndex, Trolls[this.Id].flagPrompts.Length, this.Id);
        }
        TrollFlagPrompt prompt;
        Trolls[this.Id].flagPrompts.GetArray(promptIndex, prompt);
        if(prompt.multiselect) {
            ThrowError(".GetPromptData: attempted to receive data for a multiselect prompt. Operation unspported. promptIndex:%d troll:%d", promptIndex, this.Id);
        }
        TrollOptionData option;
        int flags = this.GetFlags(client);
        for(int i = 0; i < Trolls[this.Id].promptOptions.Length; i++) {
            int bit = 1 << i;
            // If prompt has flag AND flag is active:
            if(prompt.flags & bit && flags & bit) {
                Trolls[this.Id].promptOptions.GetArray(i, option);
                out = option.data;
                return true;
            }
        }
        return false;
    }

    public bool GetPromptDataFloat(int client, int promptIndex, float &out) {
        int value;
        if(this.GetPromptDataInt(client, promptIndex, value)) {
            // We just retagged it as int, but it's float data
            out = view_as<float>(value);
            return true;
        }
        return false;
    }

    public bool GetPrompt(int promptIndex, TrollFlagPrompt prompt) {
        if(promptIndex < 0 || promptIndex >= Trolls[this.Id].flagPrompts.Length) return false;
        Trolls[this.Id].flagPrompts.GetArray(promptIndex, prompt);
        return true;
    }

    public void GetOptionName(int optionIndex, char[] output, int maxlen) {
        TrollOptionData option;
        this.GetOptionData(optionIndex, option);
        strcopy(output, maxlen, option.name);
    }

    public bool GetFlagNames(int client, int flags = -1, char[] output, int maxlength) {
        if(this.TotalOptionsCount == 0) return false;
        char buffer[32];
        if(flags == -1) flags = Trolls[this.Id].activeFlagClients[client];
        int count;
        for(int i = 0; i < this.TotalOptionsCount; i++) {
            int bit = 1 << i;
            // If client has this flag:
            if(flags & bit) {
                this.GetOptionName(i, buffer, sizeof(buffer));
                if(count == 0)
                    Format(output, maxlength, "%s", buffer);
                else
                    Format(output, maxlength, "%s,%s", output, buffer);
                count++;
            }
        }
        return true;
    }

    /// Gets the default modifier to use
    public trollModifier GetDefaultMod() {
        // If the flags is equal to the 2^n flag, then it must be the only flag:
        if(Trolls[this.Id].mods == view_as<int>(TrollMod_Instant)) return TrollMod_Instant;
        else if(Trolls[this.Id].mods == view_as<int>(TrollMod_Constant)) return TrollMod_Constant;
        else return TrollMod_Invalid;
    }
}

int g_iTrollIndex;
methodmap TrollBuilder {
    public TrollBuilder(const char[] name, const char description[128], int mods) {
        if(mods == 0) {
            ThrowError("Troll \"%s\" has no modifiers defined.", name);
        } else if(g_iTrollIndex == MAX_TROLLS + 1) {
            ThrowError("Maximum number of trolls (%d) reached. Up MAX_TROLLS value.", MAX_TROLLS);
        }
        int i = g_iTrollIndex;
        g_iTrollIndex++;
        g_trollAddPromptIndex = 0;
        Trolls[i].id = i;
        strcopy(Trolls[i].name, MAX_TROLL_NAME_LENGTH, name);
        strcopy(Trolls[i].description, 128, description);
        Trolls[i].categoryID = categoryID;
        Trolls[i].mods = mods;
        Trolls[i].flagPrompts = new ArrayList(sizeof(TrollFlagPrompt));

        char buffer[MAX_TROLL_NAME_LENGTH];
        strcopy(buffer, sizeof(buffer), name); 
        StringToLower(buffer);
        trollKV.SetValue(buffer, i);
        return view_as<TrollBuilder>(i);
    }

    property int Id {
        public get() { return view_as<int>(this); }
    }

    public TrollBuilder Hide() {
        Trolls[this.Id].hidden = true;
    }

    public TrollBuilder SetDescription(const char description[128]) {
        strcopy(Trolls[this.Id].description, 128, description);
    }

    public TrollBuilder SetTimer(float interval, Timer timer, int requiredFlags = 0) {
        Trolls[this.Id].timerInterval = interval;
        Trolls[this.Id].timerFunction = timer;
        Trolls[this.Id].timerRequiredFlags = requiredFlags;
        for(int i = 0; i <= MAXPLAYERS; i++) {
            Trolls[this.Id].timerHandles[i] = null;
        }
        return this;
    }

    public TrollBuilder AddPrompt(const char[] customPrompt = "", int requiredFlags = 0) {
        this._AddPrompt(false, requiredFlags, customPrompt);
        return this;
    }

    public TrollBuilder AddPromptMulti(const char[] customPrompt = "", int requiredFlags = 0) {
        this._AddPrompt(true, requiredFlags, customPrompt);
        return this;
    }

    // Adds event handle for when an option for a non-multi prompt is selected. If current prompt is multi, will error
    public TrollBuilder OnPromptActivate(PromptActivateFunction fn) {
        TrollFlagPrompt prompt;
        Trolls[this.Id].flagPrompts.GetArray(g_trollAddPromptIndex, prompt);
        if(prompt.multiselect) ThrowError("Current prompt is multiselect");
        if(prompt.activateFn == null) prompt.activateFn = new PrivateForward(ET_Single, Param_Cell, Param_Cell, Param_Cell, Param_Any, Param_Cell, Param_Cell);
        prompt.activateFn.AddFunction(INVALID_HANDLE, fn);

        Trolls[this.Id].flagPrompts.SetArray(g_trollAddPromptIndex, prompt);
        return this;
    }

    public void _AddPrompt(bool multiselect, int requiredFlags = 0, const char[] customPrompt) {
        TrollFlagPrompt prompt;
        prompt.multiselect = multiselect;
        prompt.requireFlags = requiredFlags;
        if(customPrompt[0] != '\0')
            strcopy(prompt.promptText, MAX_TROLL_FLAG_LENGTH, customPrompt);
        int index = Trolls[this.Id].flagPrompts.PushArray(prompt);
        g_trollAddPromptIndex = index;
    }

    public TrollBuilder AddOption(const char[] name, bool defaultOn = false) {
        this._AddOption(name, defaultOn);
        return this;
    }

    public TrollBuilder AddOptionInt(const char[] name, bool defaultOn = false, int data) {
        this._AddOption(name, defaultOn, data);
        return this;
    }
    public TrollBuilder AddOptionFloat(const char[] name, bool defaultOn = false, float data) {
        // This is intentional - we do not want to convert float -> int, just change type
        this._AddOption(name, defaultOn, view_as<int>(data));
        return this;
    }

    public void _AddOption(const char[] name, bool defaultOn = false, int data = 0) {
        if(Trolls[this.Id].promptOptions == null) {
            Trolls[this.Id].promptOptions = new ArrayList(sizeof(TrollOptionData));
        }
        TrollOptionData option;
        strcopy(option.name, MAX_TROLL_FLAG_LENGTH, name);
        option.data = data;
        int optionIndex = Trolls[this.Id].promptOptions.PushArray(option);

        // Add option to current prompt
        TrollFlagPrompt prompt;
        if(g_trollAddPromptIndex >= Trolls[this.Id].flagPrompts.Length) {
            ThrowError("No prompt added for troll \"%s\", for flag \"%s\"", this.Id, name);
        }
        Trolls[this.Id].flagPrompts.GetArray(g_trollAddPromptIndex, prompt);
        prompt.flags |= ( 1 << optionIndex );
        if(defaultOn) {
            // If out of bounds, set to default -1 -> pick global prompt
            if(Trolls[this.Id].flagPrompts.Length == 0) {
                ThrowError("Troll \"%s\" does not have any flag prompts, thus a default value cannot be set. (flag=\"%s\")", Trolls[this.Id].name, name);
            } else if(!prompt.multiselect && prompt.defaults > 0) {
                ThrowError("Flag \"%s\" cannot be set as default flag in single select mode, as one has already been set for prompt %d", name, g_trollAddPromptIndex);
            }
            prompt.defaults |= (1 << optionIndex);
        }
        // Save changes to prompt
        Trolls[this.Id].flagPrompts.SetArray(g_trollAddPromptIndex, prompt); 

    }

    public TrollBuilder SetActivationFunction(ActivateFunction fn) {
        if(Trolls[this.Id].activateFn == null) {
            Trolls[this.Id].activateFn = new PrivateForward(ET_Ignore, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
        }
        Trolls[this.Id].activateFn.AddFunction(INVALID_HANDLE, fn);
        return this;
    }

    public TrollBuilder SetResetFunction(ResetFunction fn) {
        if(Trolls[this.Id].resetFn == null) {
            Trolls[this.Id].resetFn = new PrivateForward(ET_Ignore, Param_Cell, Param_Cell, Param_Cell);
        }
        Trolls[this.Id].resetFn.AddFunction(INVALID_HANDLE, fn);
        return this;
    }

    public Troll Build() {
        return Troll(this.Id);
    }

}

int GetTrollID(const char[] name) {
    static int i = 0;
    char buffer[MAX_TROLL_NAME_LENGTH];
    strcopy(buffer, sizeof(buffer), name);
    StringToLower(buffer);
    if(trollKV.GetValue(buffer, i)) {
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

void SetTrollFlags(int client, const char[] name, int flags = -1) {
    int index = GetTrollID(name);
    if(flags == -1)
        Trolls[index].Disable(client);
    else
        Trolls[index].Enable(client, flags);
}


TrollEffectResponse ApplyTroll(int victim, Troll troll, int activator, trollModifier modifier, int flags = 0, bool silent = false) {
    char name[MAX_TROLL_NAME_LENGTH];
    troll.GetName(name, sizeof(name));
    int trollIndex = troll.Id;

    bool isActive = troll.IsActive(victim);

    // Clear troll specific timer:
    if(troll.HasTimer) {
        if(!isActive) {
            if(modifier & TrollMod_Constant && (Trolls[trollIndex].timerRequiredFlags == 0 || Trolls[trollIndex].timerRequiredFlags & flags)) {
                Trolls[trollIndex].timerHandles[victim] = CreateTimer(Trolls[trollIndex].timerInterval, Trolls[trollIndex].timerFunction, victim, TIMER_REPEAT);
            }
        } else if(Trolls[trollIndex].timerHandles[victim] != null) {
            delete Trolls[trollIndex].timerHandles[victim];
        }
    }


    if(!silent && SilentMenuSelected[activator]) silent = true;

    if(activator > 0 && t_metaReverse.IsActive(activator)) {
        float chance;
        t_metaReverse.GetPromptDataFloat(activator, 0, chance);
        if(GetURandomFloat() <= chance) {
            victim = activator;
        }
    }

    // If victim is a survivor bot, check if has an idle player
    if(IsFakeClient(victim) && GetClientTeam(victim) == 2) {
        int player = GetSpectatorClient(victim);
        if(player > 0) {
            // If there is an idle player, apply troll to them
            ApplyTroll(player, troll, activator, modifier, flags, silent);
            // And continue IF there is TrollMod_PlayerOnly mod
            if(troll.HasMod(TrollMod_PlayerOnly)) return TE_Success;
            // Don't want to show two logs, so just ignore the bot
            silent = true;
        }
    }


    // Toggle on flags for client, if it's not a single run.
    if(modifier & TrollMod_Constant) {
        Trolls[trollIndex].activeFlagClients[victim] = isActive ? -1 : flags;
    }

    // Applies any custom logic needed for a troll, mostly only used for TrollMod_Instant
    TrollEffectResponse response = ApplyAffect(victim, troll, activator, modifier, flags);
    if(response != TE_Success) return response; // Let the menu handler deal with checking

    // Invoke Callbacks:
    if(!isActive) {
        Troll instance = Troll(trollIndex);
        if(Trolls[trollIndex].activateFn != null) {
            Call_StartForward(Trolls[trollIndex].activateFn);
            Call_PushCell(instance);
            Call_PushCell(activator);
            Call_PushCell(victim);
            Call_PushCell(flags);
            Call_PushCell(modifier);
            Call_Finish();
        }

        // Call the corresponding prompt callback if applicable
        TrollFlagPrompt prompt;
        for(int i = 0; i < Trolls[trollIndex].flagPrompts.Length; i++) {
            Trolls[trollIndex].flagPrompts.GetArray(i, prompt);
            if(!prompt.multiselect && prompt.activateFn != null) {
                int value;
                instance.GetPromptDataInt(victim, i, value);
                for(int j = 0; j < Trolls[trollIndex].promptOptions.Length; i++) {
                    int bit = 1 << j;
                    if(flags & bit && prompt.flags & bit) {
                        Call_StartForward(prompt.activateFn);
                        Call_PushCell(instance);
                        Call_PushCell(activator);
                        Call_PushCell(victim);
                        Call_PushCell(value);
                        Call_PushCell(flags);
                        Call_PushCell(modifier);
                        response = view_as<TrollEffectResponse>(Call_Finish());
                        if(response != TE_Success) return response; // Let the menu handler deal with checking
                        break;
                    }
                }
                break;
            }
        }

    } else if(isActive && Trolls[trollIndex].resetFn != null) {
        Call_StartForward(Trolls[trollIndex].resetFn);
        Call_PushCell(Troll(trollIndex));
        Call_PushCell(activator);
        Call_PushCell(victim);
        Call_PushCell(modifier);
        Call_Finish();
    }
    
    // Log all actions, indicating if constant or single-fire, and if any flags
    if(!silent) {
        if(isActive) {
            CShowActivityEx(activator, "[FTT] ", "deactivated {yellow}%s{default} on %N. ", name, victim);
            LogAction(activator, victim, "\"%L\" deactivated \"%s\" on \"%L\"", activator, name, victim);
        } else {
            char flagName[50];
            if(flags > 0 && troll.GetFlagNames(victim, flags, flagName, sizeof(flagName))) {
                Format(flagName, sizeof(flagName), " (\x04%s|%d\x01)", flagName, flags);
            }
            if(modifier & TrollMod_Constant) {
                CShowActivityEx(activator, "[FTT] ", "activated constant {yellow}%s{default}%s for %N. ", name, flagName, victim);
            } else {
                CShowActivityEx(activator, "[FTT] ", "activated {yellow}%s{default}%s for %N. ", name, flagName, victim);
            }
            LogAction(activator, victim, "\"%L\" activated \"%s\" (%d) for \"%L\"", activator, name, flags, victim);
        }
    } else {
        CReplyToCommand(activator, "[FTT] Applied silently {yellow}\"%s\"{default} on %N with flags=%d", name, victim, flags);
    }
    return TE_Success;
}


void EnableTroll(int client, const char[] troll, int flags = 0) {
    SetTrollFlags(client, troll, flags);
}

void DisableTroll(int client, const char[] troll) {
    SetTrollFlags(client, troll, -1);
}

public void SetCategory(const char[] newCat) {
    categoryID = categories.FindString(newCat);
    if(categoryID == -1)
        categoryID = categories.PushString(newCat);
}
void GetCategory(int category, char[] buffer, int size) {
    categories.GetString(category, buffer, size);
} 


public int Native_ApplyTroll(Handle plugin, int numParams) {
    int victim = GetNativeCell(1);
    char name[MAX_TROLL_NAME_LENGTH];
    GetNativeString(2, name, sizeof(name));
    trollModifier modifier = view_as<trollModifier>(GetNativeCell(3));
    if(view_as<int>(modifier) < 0) {
        ThrowNativeError(SP_ERROR_NATIVE, "Provided modifier is invalid (out of range)");
    }
    int flags = GetNativeCell(4);
    int activator = GetNativeCell(5);

    Troll troll = Troll.FromName(name);
    troll.Activate(victim, activator, modifier, flags, GetNativeCell(6));
    return 0;
}
 