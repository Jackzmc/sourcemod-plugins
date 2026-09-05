#define SDN_GAMBLE "music/wam_music.mp3"
#define MODEL_CASH "models/props_collectables/money_wad.mdl"

void Gamble_OnActivate(int apologizer, int target, const char[] eventId) {
    if(!IsPlayerAlive(apologizer)) {
        ShowSorryAcceptMenu(apologizer, target, eventId);
        PrintToChat(target, "Can't gamble a corpse...");
        return;
    }
    bool isHealth = true; //GetRandomFloat() > 0.5;

    PrecacheSound(SDN_GAMBLE);
    EmitSoundToClient(apologizer, SDN_GAMBLE, .channel=SNDCHAN_STATIC, .volume=1.0, .flags=SND_CHANGEVOL);

    if(isHealth)
        PrintHintText(apologizer, "%N is double or nothing your health", target);
    else
        PrintHintText(apologizer, "%N is double or nothing your ammo", target);

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
        SpawnMoney(apologizer, 20);
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

void SpawnMoney(int client, int count) {
    PrecacheModel(MODEL_CASH);
    float pos[3];

    for(int i = 0; i < count; i++) {
        GetClientEyePosition(client, pos);
        pos[0] += GetRandomFloat(-6.0, 6.0);
        pos[1] += GetRandomFloat(-6.0, 6.0);
        pos[2] += GetRandomFloat(15.0, 22.0);
        int model = CreateProp("prop_dynamic", MODEL_CASH, pos);
        // This spams the console using this model, but we need *a* model or it crashes
        int physbox = CreateProp("func_physbox", MODEL_CASH, pos, NULL_VECTOR, NULL_VECTOR, 2);
        SetParent(model, physbox);

        CreateTimer(20.0, Timer_KillEntity, _, physbox);
    }
}