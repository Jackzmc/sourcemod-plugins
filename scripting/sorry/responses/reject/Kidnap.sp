#define SOUND "player/ammo_pack_use.wav"

void Kidnap_OnActivate(int apologizer, int target, const char[] eventId) {
    SetPlayerBlind(apologizer, 255, 700);
    EmitSoundToClient(apologizer, SOUND, apologizer, SNDCHAN_AUTO, SNDLEVEL_RUSTLE, SND_CHANGEVOL, 0.4);
    float pos[3], ang[3];
    float curFlow = L4D2Direct_GetFlowDistance(apologizer);
    GetRandomNearbyPos(curFlow, pos, -500.0, 500.0, -500.0);
    ang[1] = GetRandomFloat(0.0, 360.0);
    TeleportEntity(apologizer, pos, ang, NULL_VECTOR);
    PrecacheSound(SOUND);


    int revealTime = GetRandomInt(5_000, 9_000);
    SetPlayerBlind(apologizer, 0, revealTime, Fade_Out | Fade_Purge);
}