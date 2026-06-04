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
    int attempts = GetRandomInt(10, 20);
    SorryStore[apologizer].SetValue(STORE_KEY, attempts);

    ScheduleNextTorment(apologizer);
}

void ScheduleNextTorment(int apologizer) {
    int attempts;
    if(SorryStore[apologizer].GetValue(STORE_KEY, attempts) && attempts > 0) {
        float duration = GetRandomFloat(1.0, 15.0);
        CreateTimer(duration, Timer_Tick, GetClientOfUserId(apologizer));
    }
}

Action Timer_Tick(Handle h, int userid) {
    int client = GetClientOfUserId(userid);
    if(client > 0) {
        SorryStore[client].IncrementValue(STORE_KEY, -1);

        int soundIndex = GetRandomInt(0, TORMENT_SOUNDS_MAX - 1);
        PrecacheSound(TORMENT_SOUNDS[soundIndex]);
        // use random player (infected or survvior) to play it from
        int speakerEntity = GetAnyRandomClient();
        EmitSoundToClient(client, TORMENT_SOUNDS[soundIndex], speakerEntity);

        ScheduleNextTorment(client);
    }
    return Plugin_Handled;
}