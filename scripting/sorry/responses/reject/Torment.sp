static char STORE_KEY[] = "Torment";

// instead of % every s, do:
/**
 * pick max attempts (10-20)
 * create timer for random N seconds, that spawns new one after, until max attempts
 */

#define TORMENT_SOUNDS_MAX 16
char TORMENT_SOUNDS[TORMENT_SOUNDS_MAX][] = {
    // jockey
    "player/jockey/voice/idle/jockey_recognize08.wav",
    "player/jockey/voice/idle/jockey_lurk11.wav",
    // boomer
    "player/boomer/voice/idle/female_boomer_lurk_12.wav",
    "player/boomer/voice/idle/male_boomer_lurk_13.wav",
    // charger
    "player/charger/voice/idle/charger_lurk_09.wav",
    "player/charger/voice/idle/charger_spotprey_02.wav",
    // spitter
    "player/spitter/voice/idle/spitter_lurk_03.wav",
    "player/spitter/voice/idle/spitter_spotprey_01.wav",
    // hunter
    "player/hunter/voice/idle/hunter_stalk_08.wav",
    "player/hunter/voice/idle/hunter_stalk_01.wav",
    // smoker
    "player/smoker/voice/idle/smoker_lurk_10.wav",
    "player/smoker/voice/idle/smoker_spotprey_13.wav",
    // tank
    "player/tank/voice/idle/tank_growl_02.wav",
    "player/tank/voice/idle/tank_voice_05.wav",
    // witch
    "npc/witch/voice/idle/female_cry_2.wav",
    "npc/witch/voice/idle/walking_cry_12.wav"
}

void Torment_OnActivate(int apologizer, int target, const char[] eventId) {
    int attempts = GetRandomInt(5, 15);
    SorryStore[apologizer].SetValue(STORE_KEY, attempts);

    PrintToServer("Torment: %d attempts for %N", attempts, apologizer);

    ScheduleNextTorment(apologizer);
}

void ScheduleNextTorment(int apologizer) {
    int attempts;
    if(SorryStore[apologizer].GetValue(STORE_KEY, attempts) && attempts > 0) {
        float duration = GetRandomFloat(1.0, 15.0);
        CreateTimer(duration, Timer_Tick, GetClientUserId(apologizer));
    }
}

Action Timer_Tick(Handle h, int userid) {
    int client = GetClientOfUserId(userid);
    if(client > 0) {
        SorryStore[client].IncrementValue(STORE_KEY, -1);

        // Bypass towards non-boss specials, 10% for them
        int soundIndex = GetRandomFloat() < 0.9 
            ? GetRandomInt(0, TORMENT_SOUNDS_MAX - 5)
            : GetRandomInt(TORMENT_SOUNDS_MAX - 4, TORMENT_SOUNDS_MAX - 1);
        PrecacheSound(TORMENT_SOUNDS[soundIndex]);

        int speakerEntity = GetRandomClient(-1, -1, -1);

        float origin[3], direction[3];
        GetRandomLocation(client, origin);
        GetRandomLocation(client, direction);
        SubtractVectors(origin, direction, direction);
        EmitSoundToClient(client, TORMENT_SOUNDS[soundIndex], speakerEntity, .origin = origin, .dir = direction);

        ScheduleNextTorment(client);
    }
    return Plugin_Handled;
}