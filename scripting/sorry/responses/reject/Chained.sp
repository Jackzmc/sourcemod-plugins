float targetPos[MAXPLAYERS+1][3]; // TODO: replace w/ SorryStore?

static char TARGET_CLIENT_KEY[] = "CHAINED_TARGET";

float DURATION_SEC = 180.0; //3 min 

void Chained_OnActivate(int apologizer, int target, const char[] eventId) {
    SorryStore[apologizer].SetValueTemp(TARGET_CLIENT_KEY, target, DURATION_SEC);
}


static float MAX_DIST = 30_000.0;
static float LASER_HEIGHT = 40.0;

float SPEED = 200.0;

Action Chained_OnPlayerRunCmd(int client, int& buttons, int& impulse, float vel[3], float angles[3], int& weapon, int& subtype, int& cmdnum, int& tickcount, int& seed, int mouse[2]) {
    int targetEnt;
    if(client > 0 && SorryStore[client].GetValue(TARGET_CLIENT_KEY, targetEnt)) {
        if(!IsClientInGame(targetEnt)) {
            // Select new target, and wait until next cmd
            PrintToChat(client, "You have been freed");
            SorryStore[client].Remove(TARGET_CLIENT_KEY);
            return Plugin_Continue;
        }
        // PrintCenterText(client, "%N", targetEnt[client]);
        // Make client "look at" the target for the calculation
        float result[3], pos[3];
        GetClientAbsOrigin(client, pos);
        GetClientAbsOrigin(targetEnt, targetPos[client]);
        MakeVectorFromPoints(targetPos[client], pos, result);
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

        float dist = GetVectorDistance(pos, targetPos[client], true);

        float delta = dist / MAX_DIST; // >= 1
        float width = delta / 4.0;
        if(width < 0.2) width = 0.2;

        targetPos[client][2] += LASER_HEIGHT;
        pos[2] += LASER_HEIGHT;


        int color[4];
        GetChainColor(delta, 1.0, color);

        // TODO: increase color green -> red on distance?
        TE_SetupBeamPoints(pos, targetPos[client], g_iLaserIndex, 0, 0, 1, 0.1, width / 2, width, 0, 0.0, color, 0);
        TE_SendToClient(client, 0.0);
        TE_SetupBeamPoints(targetPos[client], pos, g_iLaserIndex, 0, 0, 1, 0.1, width / 2, width, 0, 0.0, color, 0);
        TE_SendToClient(targetEnt, 0.0);

        if(GetEntityMoveType(client) == MOVETYPE_NOCLIP) return Plugin_Changed;

        // PrintToServer("look at -> (%.0f %.0f %.0f) %d", targetPos[client][0], targetPos[client][1], targetPos[client][2], targetEnt[client]);
        // if(buttons & IN_FORWARD) {
        //     if(dist <= MIN_DIST) {
        //         return Plugin_Handled;
        //     }
        //     SetVelocityDir(client, vel, angles[1], SPEED);
        // } else if(buttons & IN_BACK) {
        //     SetVelocityDir(client, vel, angles[1], -SPEED);
        // }
        if(buttons & IN_MOVELEFT) {
            SetVelocityDir(client, vel, angles[1] - 90.0, -SPEED);
        } else if(buttons & IN_MOVERIGHT) {
            SetVelocityDir(client, vel, angles[1] - 90.0, SPEED);
        }
        if(dist >= MAX_DIST) {
            // Pull player if too far, increasing vertical bump the further they are
            // TODO: swap linear with more?
            float vDist = pos[2] - targetPos[client][2]; // < 0: below, > 0: above
            vel[2] -= (vDist/2);
            AddVelocityDir(client, vel, angles[1], SPEED*delta);
            // PrintCenterText(client, "v:(%.1f %.1f %.1f)", vel[0], vel[1], vel[2]);
        }
        return Plugin_Changed;
	}
	return Plugin_Continue;
}

void GetChainColor(float value, float K, int color[4]) {
    if(value < 1.0) {
        color[0] = 255;
        color[1] = 255;
        color[2] = 255;
    } else {
        float f = value / (value + K); // 0.0 -> 1.0
        if (f < 0.0) f = 0.0;

        // green (0,255,0) -> yellow (255,255,0) -> red (255,0,0)
        if (f <= 0.5)
        {
            color[0] = RoundToNearest(255.0 * (f * 2.0));
            color[1] = 255;
        }
        else
        {
            color[0] = 255;
            color[1] = RoundToNearest(255.0 * ((1.0 - f) * 2.0));
        }
    }
    color[3] = 255;
}

void SetVelocityDir(int client, float vel[3], const float heading, const float speed) {
    float theta = DegToRad(heading);
    vel[0] = speed * Cosine(theta);
    vel[1] = speed * Sine(theta);
    SetAbsVelocity(client, vel);
}

void AddVelocityDir(int client, float vel[3], const float heading, const float speed) {
    float theta = DegToRad(heading);
    vel[0] += speed * Cosine(theta);
    vel[1] += speed * Sine(theta);
    SetAbsVelocity(client, vel);
}