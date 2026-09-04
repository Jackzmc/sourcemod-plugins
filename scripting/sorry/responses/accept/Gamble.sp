#define SDN_GAMBLE "music/wam_music.mp3"

void Gamble_OnActivate(int apologizer, int target, const char[] eventId) {
    bool isHealth = true; //GetRandomFloat() > 0.5;

    PrecacheSound(SDN_GAMBLE);
    EmitSoundToClient(apologizer, SDN_GAMBLE, .channel=SNDCHAN_STATIC, .volume=1.0, .flags=SND_CHANGEVOL);

    if(isHealth)
        PrintHintText(apologizer, "%N is double or nothing your health", target);
    else
        PrintHintText(apologizer, "%N is double or nothing your ammo", target);
    PrintToChat(apologizer, "...");

    DataPack pack;
    CreateDataTimer(5.0, Timer_GambleResult, pack);
    pack.WriteCell(GetClientUserId(apologizer));
    pack.WriteCell(GetClientUserId(target));
    pack.WriteCell(isHealth);
}

Action Timer_GambleResult(Handle h, DataPack pack) {
    pack.Reset();
    int apologizer = GetClientOfUserId(pack.ReadCell());
    int target = GetClientOfUserId(pack.ReadCell());
    bool isHealth = pack.ReadCell() == 1;

    if(GetRandomFloat() > 0.5) {
        if(isHealth) {
            if(L4D_IsPlayerIncapacitated(apologizer)) {
                L4D_ReviveSurvivor(apologizer);
            } else {
                int health = GetClientHealth(apologizer);
                float tempHealth = L4D_GetTempHealth(apologizer);
                SetEntProp(apologizer, Prop_Send, "m_iHealth", health * 2);
                L4D_SetTempHealth(apologizer, tempHealth * 2);
            }
        }
        EmitSoundToAll(SOUND_ACCEPT, apologizer, .pitch = 120, .flags = SND_CHANGEPITCH);
    } else {
        if(isHealth) {
            SDKHooks_TakeDamage(apologizer, apologizer, apologizer, 1000.0, DMG_BLAST, -1);
        }
        EmitSoundToAll(SOUND_REJECT, apologizer, .pitch = 80, .flags = SND_CHANGEPITCH);
        PrintHintText(target, "Oh well...");
        PrintHintText(apologizer, "Oh well...");
    }

    StopSound(apologizer, SNDCHAN_STATIC, SDN_GAMBLE);

    return Plugin_Handled;
}