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
        float longestTime = 0.5*spawnPoints.Length + 0.1;
        TempSetSpeed(apologizer, longestTime, 0.2);

        for(int i = 0; i < spawnPoints.Length; i++) {
            spawnPoints.GetArray(i, pos, 3);
            // Make sure they see their impending doom
            if(i == 0) {
                LookAtPoint(apologizer, pos);
            }
            FireRocketDelay(pos, orgPos, 0.25*float(i) + 0.4, 3.5);
        }
    }
    delete spawnPoints;
}

stock void LookAtPoint(int entity, const float destination[3]){
	float angles[3], pos[3], result[3];
	GetEntPropVector(entity, Prop_Send, "m_vecOrigin", pos);
	MakeVectorFromPoints(destination, pos, result);
	GetVectorAngles(result, angles);
	if(angles[0] >= 270){
		angles[0] -= 270;
		angles[0] = (90-angles[0]);
	} else {
		if(angles[0] <= 90){
			angles[0] *= -1;
		}
	}
	angles[1] -= 180;
	TeleportEntity(entity, NULL_VECTOR, angles, NULL_VECTOR);
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
    PrintToServer("sorry: %d/%d attempts", attempts, maxAttempts);
    return list;
}

void FireRocketDelay(const float origin[3], const float target[3], float delay = 0.1, float flightTime = 2.0) {
    DataPack pack;
    CreateDataTimer(delay, Timer_FireRocket, pack);
    pack.WriteFloatArray(origin, 3);
    pack.WriteFloatArray(target, 3);
    pack.WriteFloat(flightTime);
}

Action Timer_FireRocket(Handle h, DataPack pack) {
    pack.Reset();
    float origin[3], target[3];
    pack.ReadFloatArray(origin, 3);
    pack.ReadFloatArray(target, 3);
    float flightTime = pack.ReadFloat();
    FireRocket(origin, target, flightTime);
    return Plugin_Handled;
}

int FireRocket(const float origin[3], const float target[3], float flightTime) {
    float vel[3], ang[3];
    float speed = CalcProjectileLaunch(origin, target, flightTime, vel, ang);
    if(speed > 0.0) {
        int ent = L4D2_GrenadeLauncherPrj(0, origin, ang, vel, NULL_VECTOR);
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