static char STORE_KEY[] = "Jail_Parent";
static char STORE_KEY2[] = "Jail_Amount";

#define JAIL_CLICKS_NEEDED 30

#define CAGE_MODEL "models/props_exteriors/roadsidefence_64.mdl"
float CAGE_OFFSETS[4][2][3] = {
    //       x       y    z        p       y    r   
    { {   0.0,    0.0, 0.0 }, { 0.0,    0.0, 0.0 } },
    { { 28.19,  28.19, 0.0 }, { 0.0,  -90.0, 0.0 } },
    { { 55.69,    0.0, 0.0 }, { 0.0, -180.0, 0.0 } },
    { { 28.25, -28.95, 0.0 }, { 0.0, -270.0, 0.0 } },
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
    PrecacheModel(CAGE_MODEL);

    float targetPos[3], pos[3];
    GetClientAbsOrigin(apologizer, targetPos);

    int jail = SpawnJail(targetPos, false);

    for(int i = 0 ; i < 3; i++)
        cagePosition[apologizer][i] = targetPos[i];

    PrintHintText(apologizer, "Spam the attack and shove keys to escape");

    SorryStore[apologizer].SetValue(STORE_KEY, EntIndexToEntRef(jail));
    SorryStore[apologizer].SetValue(STORE_KEY2, JAIL_CLICKS_NEEDED);
    PrintHintText(apologizer, "%d", JAIL_CLICKS_NEEDED);
}


int SpawnJail(const float origin[3], bool physics) {
    int parentEnt;
    float pos[3];

    for(int i = 0; i < 4; i++) {
        pos[0] = origin[0] + CAGE_OFFSETS[i][0][0] - CAGE_PLAYER_OFFSET[0];
        pos[1] = origin[1] + CAGE_OFFSETS[i][0][1] - CAGE_PLAYER_OFFSET[1];
        pos[2] = origin[2] + CAGE_OFFSETS[i][0][2] - CAGE_PLAYER_OFFSET[2];
        int ent = CreateProp(physics ? "prop_physics_override" : "prop_dynamic", CAGE_MODEL, pos, CAGE_OFFSETS[i][1]);
        // For easy cleanup just parent:
        if(!physics) {
            if(i == 0) parentEnt = ent;
            else SetParent(ent, parentEnt);
        }
    }
    return parentEnt;
}



Action Jail_OnPlayerRunCmd(int client, int& buttons, int& impulse, float vel[3], float angles[3], int& weapon, int& subtype, int& cmdnum, int& tickcount, int& seed, int mouse[2]) {
    if(SorryStore[client].ContainsKey(STORE_KEY)) {
	    SetWeaponDelay(client, 1.0);

        int value;
        SorryStore[client].GetValue(STORE_KEY2, value);

	    int oldButtons = GetEntProp(client, Prop_Data, "m_nOldButtons");
        if((buttons & IN_ATTACK) && !(oldButtons & IN_ATTACK)) {
            SorryStore[client].IncrementValue(STORE_KEY2, -1);
            value--;
        } else if((buttons & IN_ATTACK2) && !(oldButtons & IN_ATTACK2)) {
            SorryStore[client].IncrementValue(STORE_KEY2, -1);
            value--;
        } else {
            return Plugin_Continue;
        }

        PrintHintText(client, "%d", value);

        if(value <= 0) {
            int entity;
            if(SorryStore[client].GetValue(STORE_KEY, entity) && IsValidEntity(entity))
                RemoveEntity(entity);
            SpawnJail(cagePosition[client], true);
            SorryStore[client].Remove(STORE_KEY);
            SorryStore[client].Remove(STORE_KEY2);
        } else {
            SorryStore[client].SetValue(STORE_KEY2, value);
        }
    }
    return Plugin_Continue;
}