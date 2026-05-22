#define KIDNAP_SOUND "player/ammo_pack_use.wav"

void Kidnap_OnActivate(int apologizer, int target, const char[] eventId) {
    SetPlayerBlind(apologizer, 255, 700);
    PrecacheSound(KIDNAP_SOUND)
    EmitSoundToClient(apologizer, KIDNAP_SOUND, apologizer, SNDCHAN_AUTO, SNDLEVEL_RUSTLE, SND_CHANGEVOL | SND_CHANGEPITCH, 0.4, 50);
    float pos[3], ang[3];
    float curFlow = L4D2Direct_GetFlowDistance(apologizer);
    if(GetRandomNearbyPos(curFlow, pos, -2000.0, 100.0, 100.0)) {
        ang[1] = GetRandomFloat(0.0, 360.0);
        TeleportEntity(apologizer, pos, ang, NULL_VECTOR);
    } else if(GetRandomNearbyPos(curFlow, pos, -3000.0, 1000.0, 80.0)) {
        ang[1] = GetRandomFloat(0.0, 360.0);
        TeleportEntity(apologizer, pos, ang, NULL_VECTOR);
    } else {
        // Nothing worked, just hope to confuse them
        ang[1] = GetRandomFloat(0.0, 360.0);
        TeleportEntity(apologizer, NULL_VECTOR, ang, NULL_VECTOR);
    }

    float duration = GetRandomFloat(6000.0, 1300.0);
    CreateTimer(duration, Timer_KidnapEnd, GetClientUserId(apologizer));
}

Action Timer_KidnapEnd(Handle h, int userid) {
    int client = GetClientOfUserId(userid);
    if(client > 0) {
        SetPlayerBlind(client, 0, 2000, Fade_Out | Fade_Purge);
    }
    return Plugin_Handled;
}