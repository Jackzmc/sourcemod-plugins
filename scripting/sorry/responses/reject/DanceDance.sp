static char REQUIRED_BTN_KEY[] = "DanceDance_btn";
static char LAST_BTN_TIME_KEY[] = "DanceDance_btn_time";
static char POINTS_KEY[] = "DanceDance_points";

static float DURATION = 30.0;
static float PRESS_TIME = 4.0; 
static float NEXT_KEY_GRACE = 0.2; // prevent last key being entered for next key

#define NUM_GRADES 6

// we don't include F, it's done automatically
int GRADE_MIN_POINTS[NUM_GRADES-1] = {
    47,
    40,
    30,
    20,
    10,
}

char GRADE_LETTER[NUM_GRADES][] = {
    "S",
    "A",
    "B",
    "C",
    "D",
    "F"
};

/**
 * @param apologizer is apologizing to target
 * @param target the one that picked this response outcome for the apologizer
 * @param eventId id of event or blank string
 **/
// Use SorryStore[apologizer] to record data
void DanceDance_OnActivate(int apologizer, int target, const char[] eventId) {
    if(!IsPlayerAlive(apologizer) || L4D_IsPlayerIncapacitated(apologizer)) {
        PrintToChat(target, "The dead (or incapped) can't dance :(");
        ShowSorryAcceptMenu(apologizer, target, eventId);
        return;
    }
    ChooseDirection(apologizer);
    PrintToChat(apologizer, "Time to dance for the next %.0f seconds", DURATION);
    CreateTimer(DURATION, Timer_EndDanceDance, GetClientUserId(apologizer));
}

Action Timer_EndDanceDance(Handle h, int data) {
    int client = GetClientOfUserId(data);
    if(client > 0) {
        EndDance(client);
    }
    return Plugin_Handled;
}

void EndDance(int client) {
    // Get points and calculate grade
    int points;
    SorryStore[client].GetValue(POINTS_KEY, points);
    int gradeIndex = NUM_GRADES - 1; //'F'
    for(int i = 0; i < NUM_GRADES - 1; i++) {
        if(points >= GRADE_MIN_POINTS[i]) {
            gradeIndex = i;
            break;
        }
    }

    PrintToChat(client, "===========");
    PrintToChat(client, "GAME OVER");
    PrintToChat(client, "");
    CPrintToChat(client, "{olive}%s{default} grade, {olive}%d{default} points", GRADE_LETTER[gradeIndex], points);
    PrintToChat(client, "");
    if(points > 0)
        PrintHintText(client, "Good dancing!");
    else
        PrintHintText(client, "Needs some work...");
    PrintToChat(client, "===========");

    SorryStore[client].Remove(REQUIRED_BTN_KEY);
    SorryStore[client].Remove(LAST_BTN_TIME_KEY);
    SorryStore[client].Remove(POINTS_KEY);
}

Action DanceDance_OnPlayerRunCmd(int client, int& buttons, int& impulse, float vel[3], float angles[3], int& weapon, int& subtype, int& cmdnum, int& tickcount, int& seed, int mouse[2]) {
    if(SorryStore[client].ContainsKey(REQUIRED_BTN_KEY)) {
        if(!IsPlayerAlive(client) || L4D_IsPlayerIncapacitated(client)) {
            EndDance(client);
            return Plugin_Continue;
        }
        float lastBtnPressedTime;
        SorryStore[client].GetValue(LAST_BTN_TIME_KEY, lastBtnPressedTime);
        if(GetGameTime() - lastBtnPressedTime < NEXT_KEY_GRACE) return Plugin_Handled;

        int result = CheckDirection(client, buttons);
        bool expired = GetGameTime() - lastBtnPressedTime > PRESS_TIME;

        if(result == 1) {
            EmitSoundToClient(client, SOUND_ACCEPT, client, .pitch = 140, .volume = 0.4, .flags = SND_CHANGEVOL | SND_CHANGEPITCH);
            int health = GetClientHealth(client);
            SetEntProp(client, Prop_Send, "m_iHealth", health + 1);
            ChooseDirection(client);
            SorryStore[client].IncrementValue(POINTS_KEY, 1);
        } else if(result == -1 || expired) {
            if(expired) {
                EmitSoundToClient(client, SOUND_REJECT, client, .pitch = 80, .flags = SND_CHANGEPITCH);
                PrintToChat(client, "TOO SLOW!");
            } else {
                EmitSoundToClient(client, SOUND_REJECT, client);
            }
            SDKHooks_TakeDamage(client, client, client, 1.0);
            ChooseDirection(client);
            SorryStore[client].IncrementValue(POINTS_KEY, -1);
        }
    }
    return Plugin_Continue;
}

#define NUM_DIRS 5

int BUTTON_MAP[NUM_DIRS] = {
    IN_FORWARD,
    IN_BACK,
    IN_MOVELEFT,
    IN_MOVERIGHT,
    IN_JUMP
};

char DIR_LABEL[NUM_DIRS][] = {
    "↑",
    "↓",
    "←",
    "→",
    "JUMP!"
};


void ChooseDirection(int client) {
    int val = GetRandomInt(0, NUM_DIRS - 1);
    SorryStore[client].SetValue(REQUIRED_BTN_KEY, val);
    SorryStore[client].SetValue(LAST_BTN_TIME_KEY, GetGameTime());
    PrintHintText(client, "%s", DIR_LABEL[val]);
}

// Check if they pressd *any* of the valid keys. 1: valid, -1: wrong, 0: no valid btn pressed
int CheckDirection(int client, int buttons) {
    int required;
    if(!SorryStore[client].GetValue(REQUIRED_BTN_KEY, required)) return 0;

    for(int i = 0; i < NUM_DIRS; i++) {
        if(buttons & BUTTON_MAP[i]) {
            // They pressed a button on the list of valid buttons
            // Check if it's correct or not
            if(BUTTON_MAP[required] == BUTTON_MAP[i]) return 1;
            else return -1;
        }
    }
    return 0;
}