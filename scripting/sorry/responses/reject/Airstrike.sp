#define SOUND_ROCKET_LAUNCH "plats/hall_elev_stop.wav"
#define ROCKET_TARGETNAME "airstrike_rocket"

int AIRSTRIKE_TARGET_BEACON_COLOR[4] = { 255, 0, 0, 255 };

float INITIAL_DELAY = 5.0;

static char STORE_KEY[] = "AirstrikeRecv"; // Counter for number of received airstrikes

/**
 * @param apologizer is apologizing to target
 * @param target the one that picked this response outcome for the apologizer
 * @param eventId id of event or blank string
 **/
// Use SorryStore[apologizer] to record data
void Airstrike_OnActivate(int apologizer, int target, const char[] eventId) {
    float orgPos[3], pos[3]
    GetClientAbsOrigin(apologizer, orgPos);

    ArrayList spawnPoints = GetRocketPointsAround(orgPos, 800.0, 5, 20);
    if(spawnPoints.Length == 0) {
        ShowSorryAcceptMenu(apologizer, target, eventId);
        PrintToChat(target, "Airstrike failed, cannot see target. They must be in an open area");
    } else {
        PrintHintTextToAll("Airstrike!");
        PrecacheSound(SOUND_ROCKET_LAUNCH);

        float longestTime = 0.25*spawnPoints.Length + INITIAL_DELAY;
        TempSetSpeed(apologizer, longestTime, 0.2);

        orgPos[2] += 1.0;
		TE_SetupBeamRingPoint(orgPos, 40.0, 40.0, g_iLaserIndex, g_HaloSprite, 0, 10, longestTime, 5.0, 0.0, AIRSTRIKE_TARGET_BEACON_COLOR, 10, 0);

        TE_SendToAll();

        SorryStore[apologizer].IncrementValueTemp(STORE_KEY, longestTime, 1);

        for(int i = 0; i < spawnPoints.Length; i++) {
            spawnPoints.GetArray(i, pos, 3);
            FireRocketDelay(pos, orgPos, 0.25*float(i) + INITIAL_DELAY, 3.5);

            DataPack soundPack;
            CreateDataTimer(0.5*float(i) + 1.0, Timer_RocketSound, soundPack);
            soundPack.WriteFloatArray(orgPos, 3); // can't usually hear if we used origin, so just play it on target
        }
        // Make player looks up to see their impending doom
        CreateTimer(INITIAL_DELAY, Timer_LookAtSky, GetClientUserId(apologizer));
    }
    delete spawnPoints;
}

Action Airstrike_OnTakeDamage(int victim, int& attacker, int& inflictor, float& damage, int& damagetype) {
    if(victim <= MaxClients && attacker == inflictor && damagetype & DMG_BLAST) {
        char targetname[64];
        GetEntPropString(attacker, Prop_Data, "m_iName", targetname, sizeof(targetname));
        if(StrEqual(targetname, ROCKET_TARGETNAME)) {
            int pendingAirstrikes;

            // We know it's a rocket spawned by world, check if player should be damaged
            if(!SorryStore[victim].GetValue(STORE_KEY, pendingAirstrikes) || pendingAirstrikes <= 0) {
                damage = 1.0;
                return Plugin_Changed;
            } else {
                // Intended to keep player just barely alive, but means they incap. Works i guess.
                int health = GetClientHealth(victim);
                if(health - damage <= 0) {
                    damage = float(health) - 1.0;
                    return Plugin_Changed;
                }
            }
        }
    } 
    // if(attacker > MaxClients) {
    //     static char buffer[32];
    //     GetEntityClassname(attacker, buffer, sizeof(buffer));
    //     if(StrEqual(buffer, "infected")) {
    //         // Disable dmg, instead give victim health, and hurt zombie
    //         damage = 0.0;

    //         int health = GetClientHealth(victim);
	//         SetEntProp(victim, Prop_Send, "m_iHealth", health + 1);

    //         SDKHooks_TakeDamage(attacker, victim, victim, 50.0);
    //         return Plugin_Changed;
    //     }
    // }
	return Plugin_Continue;
}


// Gets random offset that is at least minDist and under maxDist
void RandomHorizontalOffset(float minDist, float maxDist, float out[2]) {
    float dist = GetRandomFloat(minDist, maxDist);
    float angle = GetRandomFloat(0.0, 2.0 * 3.14159265);
    out[0] = dist * Cosine(angle);
    out[1] = dist * Sine(angle);
}

ArrayList GetRocketPointsAround(const float origin[3], float distance, int numPoints, int maxAttempts) {
    int attempts;
    ArrayList list = new ArrayList(3);
    float pos[3];
    float offset[2];
    PrintToServer("origin: %f %f %f", origin[0], origin[1], origin[2]);
    while(attempts < maxAttempts && numPoints > 0) {
        RandomHorizontalOffset(300.0, distance, offset);
        pos[0] = origin[0] + offset[0];
        pos[1] = origin[1] + offset[1];
        pos[2] = origin[2] + GetRandomFloat(300.0, 450.0);
        // PrintToServer("attempt[%d]: %f %f %f", attempts, pos[0], pos[1], pos[2]);

        TR_TraceRay(pos, origin, MASK_ALL, RayType_EndPoint);
        if(!TR_DidHit()) {
            // Effect_DrawBeamBoxRotatableToAll(pos, { -10.0, -10.0, -10.0 }, { 10.0, 10.0, 10.0 }, {0.0,0.0,0.0}, g_iLaserIndex, 0, 0, 30, 30.0, 0.4, 0.4, 0, 0.1, { 0, 255, 0, 255 }, 0);
            numPoints--;
            list.PushArray(pos, 3);
        }
        attempts++;
    }
    if(numPoints > 0 && attempts >= maxAttempts) {
        PrintToServer("sorry: warn: GetRocketPointsAround failed after %d attempts", attempts);
    }
    PrintToServer("sorry: %d missed points after %d/%d attempts", numPoints, attempts, maxAttempts);
    return list;
}

void FireRocketDelay(const float origin[3], const float target[3], float delay = 0.1, float flightTime = 2.0) {
    DataPack pack;
    CreateDataTimer(delay, Timer_FireRocket, pack);
    pack.WriteFloatArray(origin, 3);
    pack.WriteFloatArray(target, 3);
    pack.WriteFloat(flightTime);
}

Action Timer_LookAtSky(Handle h, int userid) {
    int client = GetClientOfUserId(userid);
    if(client > 0)
        TeleportEntity(client, NULL_VECTOR, { -90.0, 0.0, 0.0 });
    return Plugin_Handled;
}

Action Timer_RocketSound(Handle h, DataPack pack) {
    pack.Reset();
    float origin[3];
    pack.ReadFloatArray(origin, 3);
    EmitSoundToAll(SOUND_ROCKET_LAUNCH, .origin = origin, .level = SNDLEVEL_GUNFIRE);
    return Plugin_Handled;
}

Action Timer_FireRocket(Handle h, DataPack pack) {
    pack.Reset();
    float origin[3], target[3];
    pack.ReadFloatArray(origin, 3);
    pack.ReadFloatArray(target, 3);
    float flightTime = pack.ReadFloat();
    FireRocket(origin, target, flightTime);
    target[2] += 5.0;
    // TE_SetupBeamRingPoint(target, 25.0, 25.0, g_iLaserIndex, g_HaloSprite, 0, 15, INITIAL_DELAY, 2.0, 0.0, AIRSTRIKE_TARGET_BEACON_COLOR, 1, 0);
    // TE_SendToAll();
    return Plugin_Handled;
}

int FireRocket(const float origin[3], const float target[3], float flightTime) {
    float vel[3], ang[3];
    float speed = CalcProjectileLaunch(origin, target, flightTime, vel, ang);
    if(speed > 0.0) {
        int ent = L4D2_GrenadeLauncherPrj(0, origin, ang, vel, NULL_VECTOR);
        SetEntPropString(ent, Prop_Data, "m_iName", ROCKET_TARGETNAME);
        // Effect_DrawBeamBoxRotatableToAll(origin, { -10.0, -10.0, -10.0 }, { 10.0, 10.0, 10.0 }, ang, g_iLaserIndex, 0, 0, 30, 30.0, 0.4, 0.4, 0, 0.1, { 0, 255, 0, 235 }, 0);
        // PrintToServer("vel=<%.0f,%.0f,%.0f> ang=<%.0f,%.0f,%.0f> ent=%d speed=%f", vel[0], vel[1], vel[2], ang[0], ang[1], ang[2], ent, speed);
        return ent;
    } else {
        // Effect_DrawBeamBoxRotatableToAll(origin, { -10.0, -10.0, -10.0 }, { 10.0, 10.0, 10.0 }, NULL_VECTOR, g_iLaserIndex, 0, 0, 30, 30.0, 0.4, 0.4, 0, 0.1, { 255, 0, 0, 235 }, 0);
    }
    return -1;
}

#define PROJ_GRAVITY 300.0 // projectile gravity lower

/**
 * Calculate launch velocity and angles to hit a target from an origin. 
 *
 * @param origin        Launch position
 * @param target        Target position
 * @param flightTime    Desired flight time. 
 * @param velocity      Output velocity vector
 * @param angles        Output angles [pitch, yaw, roll]
 * @return              speed of launch
 */
stock float CalcProjectileLaunch(const float origin[3], const float target[3], float flightTime = 2.0, float velocity[3], float angles[3]) {
    float dx = target[0] - origin[0];
    float dy = target[1] - origin[1];
    float dz = target[2] - origin[2];

    if (flightTime <= 0.0) return -1.0;

    // Velocity to hit target in exactly flightTime seconds
    velocity[0] = dx / flightTime;
    velocity[1] = dy / flightTime;
    velocity[2] = (dz / flightTime) + (PROJ_GRAVITY * flightTime / 2.0); 

    GetVectorAngles(velocity, angles);

    return SquareRoot(Pow(velocity[0],2.0) + Pow(velocity[1],2.0) + Pow(velocity[2], 2.0));
}