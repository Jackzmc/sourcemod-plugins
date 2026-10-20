static char STORE_PARENT_KEY[] = "Jail_Parent";
static char STORE_AMOUNT_LEFT_KEY[] = "Jail_Amount";

#define JAIL_CLICKS_NEEDED 30

#define CAGE_WALL_MODEL "models/props_exteriors/roadsidefence_64.mdl"
#define CAGE_WALL_COUNT 4
float CAGE_WALL_OFFSETS[CAGE_WALL_COUNT][2][3] = {
    //      x       y    z        p       y    r   
    { {   0.0,    0.0, 0.0 }, { 0.0,    0.0, 0.0 } },
    { { 28.19,  28.19, 0.0 }, { 0.0,  -90.0, 0.0 } },
    { { 55.69,    0.0, 0.0 }, { 0.0, -180.0, 0.0 } },
    { { 28.25, -28.95, 0.0 }, { 0.0, -270.0, 0.0 } },
}

#define CAGE_FLOOR_MODEL "models/lighthouse/checkpoint_door_lighthouse01_plank.mdl"
#define CAGE_FLOOR_COUNT 16
float CAGE_FLOOR_OFFSETS[CAGE_FLOOR_COUNT][2][3] = {
    //     x      y    z          p    y    r   
    // floor
    { { -3.0, -27.0, 5.0 }, { -92.0, 0.0, 0.0 } },
    { {  5.0, -27.0, 5.0 }, { -92.0, 0.0, 0.0 } },
    { { 13.0, -27.0, 5.0 }, { -92.0, 0.0, 0.0 } },
    { { 21.0, -27.0, 5.0 }, { -92.0, 0.0, 0.0 } },
    { { 29.0, -27.0, 5.0 }, { -92.0, 0.0, 0.0 } },
    { { 37.0, -27.0, 5.0 }, { -92.0, 0.0, 0.0 } },
    { { 45.0, -27.0, 5.0 }, { -92.0, 0.0, 0.0 } },
    { { 53.0, -27.0, 5.0 }, { -92.0, 0.0, 0.0 } },
    // ceiling
    { { -3.0, -27.0, 134.0 }, { -92.0, 0.0, 0.0 } },
    { {  5.0, -27.0, 134.0 }, { -92.0, 0.0, 0.0 } },
    { { 13.0, -27.0, 134.0 }, { -92.0, 0.0, 0.0 } },
    { { 21.0, -27.0, 134.0 }, { -92.0, 0.0, 0.0 } },
    { { 29.0, -27.0, 134.0 }, { -92.0, 0.0, 0.0 } },
    { { 37.0, -27.0, 134.0 }, { -92.0, 0.0, 0.0 } },
    { { 45.0, -27.0, 134.0 }, { -92.0, 0.0, 0.0 } },
    { { 53.0, -27.0, 134.0 }, { -92.0, 0.0, 0.0 } },
}

float CAGE_PLAYER_OFFSET[3] = { 30.0, 0.0, 0.0 };
float cagePosition[MAXPLAYERS+1][3];

/**
 * @param apologizer is apologizing to target
 * @param target the one that picked this response outcome for the apologizer
 * @param eventId id of event or blank string
 **/
// Use SorryStore[apologizer] to record data
void Jail_OnActivate(int apologizer, int target, const char[] eventId) {
    PrecacheModel(CAGE_WALL_MODEL);
    PrecacheModel(CAGE_FLOOR_MODEL);

    float targetPos[3], pos[3];
    GetClientAbsOrigin(apologizer, targetPos);

    int jail = SpawnJail(targetPos, false);

    for(int i = 0 ; i < 3; i++)
        cagePosition[apologizer][i] = targetPos[i];

    PrintHintText(apologizer, "You have been jailed. Spam your USE key until the number hits 0 to escape.");

    SorryStore[apologizer].SetValue(STORE_PARENT_KEY, EntIndexToEntRef(jail));
    SorryStore[apologizer].SetValue(STORE_AMOUNT_LEFT_KEY, JAIL_CLICKS_NEEDED);
    PrintHintText(apologizer, "%d", JAIL_CLICKS_NEEDED);
}


int SpawnJail(const float origin[3], bool physics) {
    int parentEnt;
    float pos[3];

    for(int i = 0; i < CAGE_WALL_COUNT; i++) {
        for(int v = 0; v < 3; v++)
            pos[v] = origin[v] + CAGE_WALL_OFFSETS[i][0][v] - CAGE_PLAYER_OFFSET[v];
        int ent = CreateProp(
            physics ? "prop_physics_override" : "prop_dynamic", 
            CAGE_WALL_MODEL, 
            pos, 
            CAGE_WALL_OFFSETS[i][1]
        );
        // For easy cleanup just parent:
        if(!physics) {
            if(i == 0) parentEnt = ent;
            else SetParent(ent, parentEnt);
        }
    }

    if(!physics) {
        for(int i = 0; i < CAGE_FLOOR_COUNT; i++) {
            for(int v = 0; v < 3; v++)
                pos[v] = origin[v] + CAGE_FLOOR_OFFSETS[i][0][v] - CAGE_PLAYER_OFFSET[v];
            int ent = CreateProp("prop_dynamic", CAGE_FLOOR_MODEL, pos, CAGE_FLOOR_OFFSETS[i][1]);
            // For easy cleanup just parent:
            SetParent(ent, parentEnt);
        }
    }
    return parentEnt;
}



Action Jail_OnPlayerRunCmd(int client, int& buttons, int& impulse, float vel[3], float angles[3], int& weapon, int& subtype, int& cmdnum, int& tickcount, int& seed, int mouse[2]) {
    if(SorryStore[client].ContainsKey(STORE_PARENT_KEY)) {
	    SetWeaponDelay(client, 1.0);

        int value;
        SorryStore[client].GetValue(STORE_AMOUNT_LEFT_KEY, value);

	    int oldButtons = GetEntProp(client, Prop_Data, "m_nOldButtons");
        if((buttons & IN_USE) && !(oldButtons & IN_USE)) {
            SorryStore[client].IncrementValue(STORE_AMOUNT_LEFT_KEY, -1);
            value--;
        } else {
            return Plugin_Continue;
        }

        PrintHintText(client, "JAILED!\n%d clicks left", value);

        if(value <= 0) {
            int entity;
            if(SorryStore[client].GetValue(STORE_PARENT_KEY, entity) && IsValidEntity(entity))
                RemoveEntity(entity);
            // Spawn physics jail so it falls apart
            SpawnJail(cagePosition[client], true);
            SorryStore[client].Remove(STORE_PARENT_KEY);
            SorryStore[client].Remove(STORE_AMOUNT_LEFT_KEY);
        } else {
            SorryStore[client].SetValue(STORE_AMOUNT_LEFT_KEY, value);
        }
    }
    return Plugin_Continue;
}