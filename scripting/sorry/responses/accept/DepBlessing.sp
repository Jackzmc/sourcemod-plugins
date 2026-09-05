static float SPREAD = 60.0; // radius of circle

static int NUM_KITS = 20;
static float BUMP_INTERVAL = 0.4; // interval kits tped back up
static float BUMP_INTERVAL_DELAY = 0.1; // delay between all kits
static float DURATION = 20.0;
static float HEAL_INTERVAL = 0.5;

void DepBlessing_OnActivate(int apologizer, int target, const char[] eventId) {
    float pos[3];
    GetClientAbsOrigin(apologizer, pos);

    ArrayList timers = new ArrayList();
    for(int i = 0; i < NUM_KITS; i++) {
        // Create each kit with a staggered delay
        DataPack pack;
        CreateDataTimer(0.1 * float(i), Timer_SpawnKit, pack);
        pack.WriteCell(i);
        pack.WriteCell(GetClientUserId(apologizer));
        pack.WriteCell(timers);
    }

    timers.Push(CreateTimer(HEAL_INTERVAL, Timer_HealPlayer, GetClientUserId(apologizer), TIMER_REPEAT));

    CreateTimer(DURATION, Timer_CloseHandleArray, timers);
}

Action Timer_HealPlayer(Handle h, int data) {
    int client = GetClientOfUserId(data);
    if(client > 0) {
        int health = GetClientHealth(client);
        if(health < 100) {
            SetEntProp(client, Prop_Send, "m_iHealth", health + 1);
        }
    }
    return Plugin_Continue;
}

Action Timer_SpawnKit(Handle h, DataPack pack) {
    pack.Reset();
    int id = pack.ReadCell();
    int apologizer = GetClientOfUserId(pack.ReadCell());
    if(apologizer == 0) return Plugin_Handled;
    ArrayList timers = pack.ReadCell();

    int kit = SpawnKit(apologizer);

    // Create interval timer to teleport kit back up
    DataPack pack2;
    Handle timer = CreateDataTimer(BUMP_INTERVAL + (float(id) * BUMP_INTERVAL_DELAY), Timer_Process, pack2, TIMER_REPEAT);
    pack2.WriteCell(EntIndexToEntRef(kit));
    pack2.WriteCell(GetClientUserId(apologizer));

    timers.Push(timer);
    return Plugin_Handled;
}

Action Timer_CloseHandleArray(Handle h, ArrayList list) {
    if(list != null) {
        for(int i = 0; i < list.Length; i++) {
            Handle handle = list.Get(i);
            if(handle != INVALID_HANDLE) {
                CloseHandle(handle);
            }
        }
        delete list;
    }
    return Plugin_Handled;
}

#define PI 3.14

float GetRandomVecOnCircleEdge(float center[3], float radius) {
    // float r = minRadius * SquareRoot(GetURandomFloat())
    float theta = GetURandomFloat() * 2 * PI;
    center[0] += radius * Cosine(theta)
    center[1] += radius * Sine(theta);
    return theta;
}

void PickSpot(int client, int entRef) {
    float pos[3];
    GetClientEyePosition(client, pos);
    GetRandomVecOnCircleEdge(pos, SPREAD);
    pos[2] += 60.0;
    // Set a velocity so it's not stuck floating
    float vel[3];
    vel[2] -= 1.0;
    TeleportEntity(entRef, pos, NULL_VECTOR, vel);
}

Action Timer_Process(Handle h, DataPack pack) {
    pack.Reset();
    int ref = pack.ReadCell();
    int client = GetClientOfUserId(pack.ReadCell());
    if(client == 0 || !IsValidEntity(ref)) {
        return Plugin_Continue;
    }
    PickSpot(client, ref);
    return Plugin_Continue;
}

int SpawnKit(int client) {
    int entity = CreateEntityByName("weapon_first_aid_kit");
    if(entity <= 0) return -1;
    PickSpot(client, entity);
    DispatchKeyValueInt(entity, "spawnflags", 4 | 2097152);
    if(DispatchSpawn(entity)) {
        return entity;
    }
    return -1;
}