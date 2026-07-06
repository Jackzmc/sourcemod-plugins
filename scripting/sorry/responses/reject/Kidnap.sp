#define KIDNAP_SOUND "player/ammo_pack_use.wav"

#define MODEL_CEDA_VEHICLE "models/props_vehicles/deliveryvan_armored.mdl"
#define SOUND_KIDNAP_HORN "vehicles/humvee_horn.wav"
#define SOUND_KIDNAP_IDLE_ENGINE "vehicles/v8/skid_lowfriction.wav" // TODO: change pitcH?

static float VEHICLE_DIST = 800.0;
static float VEHICLE_DURATION = 4.0;
static float VEHICLE_DELAY = 0.0;

static char STORE_KEY[] = "kidnapMidpoint";

enum KidnapState {
    KidnapState_Active = 1,
    KidnapState_Midpoint = 2
}

/**
 * TODO:
 * - on game frame
 * - offset player slightly in back
 */

void Kidnap_OnActivate(int apologizer, int target, const char[] eventId) {
    if(SorryStore[apologizer].ContainsKey(STORE_KEY)) {
        ShowSorryAcceptMenu(apologizer, target, eventId);
        PrintToChat(target, "They are already being kidnapped");
        return;
    }
    PrecacheModel(MODEL_CEDA_VEHICLE);
    PrecacheSound(SOUND_KIDNAP_HORN);
    PrecacheSound(SOUND_KIDNAP_IDLE_ENGINE);

    float clientPos[3], startPos[3], endPos[3], ang[3];
    GetClientAbsOrigin(apologizer, clientPos);
    GetClientEyeAngles(apologizer, ang);
    // Get initial position from behind and front of player
    GetHorizontalPositionFromOrigin(clientPos, ang, -VEHICLE_DIST, startPos);
    GetHorizontalPositionFromOrigin(clientPos, ang, VEHICLE_DIST, endPos);

    int vehicle = CreateProp("prop_dynamic", MODEL_CEDA_VEHICLE, startPos);
    StartKidnapVehicle(apologizer, vehicle, startPos, endPos, true);

}

void StartKidnapVehicle(int victim, int vehicle, float startPos[3], float endPos[3], bool isPickup) {
    // Face vehicle towards end pos
    LookAtPoint(vehicle, endPos);
    if(isPickup) LookAtPoint(victim, startPos);
    // Move vehicle start -> end
    DataPack pack;
    CreateDataTimer(0.1, Timer_KidnapMoveVehicle, pack, TIMER_REPEAT);
    pack.WriteCell(EntIndexToEntRef(vehicle));
    pack.WriteCell(GetClientUserId(victim));
    pack.WriteCell(isPickup); 
    pack.WriteFloat(GetGameTime() + VEHICLE_DELAY);
    pack.WriteFloatArray(startPos, 3);
    pack.WriteFloatArray(endPos, 3);

    SorryStore[victim].SetValue(STORE_KEY, KidnapState_Active);
    EmitSoundToAll(SOUND_KIDNAP_IDLE_ENGINE, vehicle, .level = SNDLEVEL_CAR, .origin = startPos, .soundtime = VEHICLE_DURATION*2.0);
}

Action Timer_KidnapMoveVehicle(Handle h, DataPack pack) {
    pack.Reset();
    int ref = pack.ReadCell();
    if(!IsValidEntity(ref)) return Plugin_Handled;
    int client = GetClientOfUserId(pack.ReadCell());
    if(client == 0) {
        // Cleanup if the vehicle disappared
        RemoveEntity(ref);
        EmitSoundToAll(SOUND_KIDNAP_HORN, ref, .level = SNDLEVEL_CAR);
        return Plugin_Handled;
    }
    bool isPickup = pack.ReadCell();
    float pos[3], endPos[3];
    float startTime = pack.ReadFloat();
    pack.ReadFloatArray(pos, 3);
    pack.ReadFloatArray(endPos, 3);

    float endTime = startTime + VEHICLE_DURATION;
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

            GetHorizontalPositionFromOrigin(pos, ang, -VEHICLE_DIST, startPos);
            GetHorizontalPositionFromOrigin(pos, ang, VEHICLE_DIST, endPos);

            TeleportEntity(ref, startPos);
            StartKidnapVehicle(client, EntRefToEntIndex(ref), startPos, endPos, false);
        } else {
            // Cleaup
            RemoveEntity(ref);
            SorryStore[client].Remove(STORE_KEY);
        }
        // Stop movement
        return Plugin_Stop;
    } else if(t > 0.5) {
        // Midpoint. Only fire once
        int val;
        if(!SorryStore[client].GetValue(STORE_KEY, val) || val != view_as<int>(KidnapState_Midpoint)) {
            EmitSoundToAll(SOUND_KIDNAP_HORN, ref, .level = SNDLEVEL_CAR, .origin = pos);
            if(isPickup) {
                SorryStore[client].SetValue(STORE_KEY, KidnapState_Midpoint);
                TeleportEntity(ref, pos); // reset client side lerp movement
                TeleportEntity(client, pos);
                SetParent(client, ref);
                // SetPlayerBlind(apologizer, 255, 700);
                PrecacheSound(KIDNAP_SOUND);
                EmitSoundToClient(client, KIDNAP_SOUND, client, SNDCHAN_AUTO, SNDLEVEL_RUSTLE, SND_CHANGEVOL | SND_CHANGEPITCH, 0.4, 50);
            } else {
                SorryStore[client].SetValue(STORE_KEY, KidnapState_Midpoint);

                ClearParent(client);
                TeleportEntity(client, pos);
                // Clear blindness
                SetPlayerBlind(client, 0, 2000, Fade_Out | Fade_Purge);
                // Just in case stuck
                L4D_WarpToValidPositionIfStuck(client);
            }
        }
    }
    return Plugin_Continue
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