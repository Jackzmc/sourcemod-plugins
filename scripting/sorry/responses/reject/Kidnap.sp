#define KIDNAP_SOUND "player/ammo_pack_use.wav"

#include "kidnap/vehicles.sp"

static char STORE_KEY[] = "kidnapMidpoint";


void Kidnap_OnActivate(int apologizer, int target, const char[] eventId) {
    if(SorryStore[apologizer].ContainsKey(STORE_KEY)) {
        ShowSorryAcceptMenu(apologizer, target, eventId);
        PrintToChat(target, "They are already being kidnapped");
        return;
    }

    float clientPos[3], startPos[3], endPos[3], ang[3];
    GetClientAbsOrigin(apologizer, clientPos);
    GetClientEyeAngles(apologizer, ang);

    VehCfg cfg = SelectVehicle();

    // Get initial position from behind and front of player
    GetHorizontalPositionFromOrigin(clientPos, ang, -cfg.Distance, startPos);
    GetHorizontalPositionFromOrigin(clientPos, ang, cfg.Distance, endPos);

    int vehicleEnt = SpawnVehicle(cfg, startPos);
    StartKidnapVehicle(apologizer, cfg, vehicleEnt, startPos, endPos, true);
}

void StartKidnapVehicle(int victim, VehCfg cfg, int vehicle, float startPos[3], float endPos[3], bool isPickup) {
    // Face vehicle towards end pos
    LookAtPoint(vehicle, endPos);
    if(isPickup) {
        LookAtPoint(victim, startPos);
        TempSetSpeed(victim, cfg.Duration, 0.1);
    }
    // Move vehicle start -> end
    DataPack pack;
    CreateDataTimer(0.1, Timer_KidnapMoveVehicle, pack, TIMER_REPEAT);
    pack.WriteCell(cfg);
    pack.WriteCell(EntIndexToEntRef(vehicle));
    pack.WriteCell(GetClientUserId(victim));
    pack.WriteCell(isPickup); 
    pack.WriteFloat(GetGameTime() + cfg.Delay);
    pack.WriteFloatArray(startPos, 3);
    pack.WriteFloatArray(endPos, 3);

    SorryStore[victim].SetValue(STORE_KEY, KidnapState_Active);
}

Action Timer_KidnapMoveVehicle(Handle h, DataPack pack) {
    pack.Reset();
    VehCfg cfg = pack.ReadCell();
    int ref = pack.ReadCell();
    if(!IsValidEntity(ref)) return Plugin_Handled;
    int client = GetClientOfUserId(pack.ReadCell());
    if(client == 0) {
        // Cleanup if client leaves
        cfg.Cleanup(ref);
        return Plugin_Handled;
    }
    bool isPickup = pack.ReadCell();
    float pos[3], endPos[3];
    float startTime = pack.ReadFloat();
    pack.ReadFloatArray(pos, 3);
    pack.ReadFloatArray(endPos, 3);

    float endTime = startTime + cfg.Duration;
    float t = (GetGameTime() - startTime) / (endTime - startTime);

    LerpVec(pos, endPos, t);
    SetAbsOrigin(ref, pos);
    // TeleportEntity(ref, pos);

    if(t > 1.0) {
        if(isPickup) {
            // Pick random location, random angle, and start drop off
            GetRandomLocation(client, pos);
            float startPos[3], ang[3];
            for(int i = 0; i < 3; i++)
                ang[i] = GetRandomFloat(0.0, 360.0);

            GetHorizontalPositionFromOrigin(pos, ang, -cfg.Distance, startPos);
            GetHorizontalPositionFromOrigin(pos, ang, cfg.Distance, endPos);

            TeleportEntity(ref, startPos);
            StartKidnapVehicle(client, cfg, EntRefToEntIndex(ref), startPos, endPos, false);
        } else {
            // Cleanup (removes child ents too)
            cfg.Cleanup(ref);
            SorryStore[client].Remove(STORE_KEY);
        }
        // Stop movement
        return Plugin_Stop;
    } else if(t > 0.5) {
        // Midpoint. Only fire once
        int val;
        if(!SorryStore[client].GetValue(STORE_KEY, val) || val != view_as<int>(KidnapState_Midpoint)) {
            // EmitSoundToAll(SOUND_KIDNAP_HORN, .level = SNDLEVEL_CAR, .origin = pos);
            if(isPickup) {
                SorryStore[client].SetValue(STORE_KEY, KidnapState_Midpoint);
                TeleportEntity(ref, pos); // reset client side lerp movement
                float offset[3];
                cfg.GetOffset(offset);
                GetHorizontalPositionFromEntity(ref, offset[0], pos);
                pos[2] += offset[2];
                TeleportEntity(client, pos);
                SetParent(client, ref);
                // SetPlayerBlind(apologizer, 255, 700);
                cfg.PlayHornSound(ref);
            } else {
                SorryStore[client].SetValue(STORE_KEY, KidnapState_Midpoint);

                ClearParent(client);
                TeleportEntity(client, pos);
                // Clear blindness
                SetPlayerBlind(client, 0, 2000, Fade_Out | Fade_Purge);
                RequestFrame(Frame_UnstickPlayer, client);
                cfg.PlayHornSound(ref);
                // Just in case stuck
            }
        }
    }
    return Plugin_Continue
}

void Frame_UnstickPlayer(int client) {
    if(IsClientInGame(client)) {
        L4D_WarpToValidPositionIfStuck(client);
    }
}

/**
 * Lerp value a towards b given time
 */
stock float LerpFloat(float a, float b, float t) {
    return a + (b - a) * t;
}
/**
 * Lerp vector a towards b given time, outputs into a
 */
stock void LerpVec(float a[3], float b[3], float t) {
    for(int i = 0; i < 3; i++) {
        a[i] = LerpFloat(a[i], b[i], t);
    }
}