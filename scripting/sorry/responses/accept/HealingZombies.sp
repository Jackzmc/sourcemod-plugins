char HEALING_ITEMS[3][] = {
    "weapon_first_aid_kit",
    "weapon_pain_pills",
    "weapon_adrenaline"
}

void HealingZombies_OnActivate(int apologizer, int target, const char[] eventId) {
    SDKHook(apologizer, SDKHook_OnTakeDamageAlive, HealingZombies_OnTakeDamage);
    int userid = GetClientUserId(apologizer);

    float pos[3];
    GetClientAbsOrigin(apologizer, pos);
    ArrayList list = SpawnZombiesNearbyList(pos, 10);
    for(int i = 0; i < list.Length; i++) {
        int common = list.Get(i);
        // Target player
        L4D2_CommandABot(common, userid, BOT_CMD_ATTACK);
        SetEntPropEnt(common, Prop_Send, "m_clientLookatTarget", apologizer);
        // Spawn kit above zombie
        GetEntPropVector(common, Prop_Send, "m_vecOrigin", pos);
        pos[2] += 72.0;
        int kit = CreateEntityByName(HEALING_ITEMS[GetRandomInt(0,2)]); // pick 1-3 items
        DispatchKeyValue(kit, "solid", "0");
        TeleportEntity(kit, pos);
        SetParent(kit, common);
        SetParentAttachment(kit, "ValveBiped.Bip01_Head1", true);
        DispatchSpawn(kit);
    }
    delete list;
    // CommandABot doesn't guarentee :(
    L4D2_CTerrorPlayer_OnHitByVomitJar(apologizer, apologizer);
    CreateTimer(30.0, Timer_HealingZombiesStop, GetClientOfUserId(apologizer));
}

Action Timer_HealingZombiesStop(Handle h, int userid) {
    int client = GetClientOfUserId(userid);
    if(client > 0) {
        SDKUnhook(client, SDKHook_OnTakeDamage, HealingZombies_OnTakeDamage);
    }
    return Plugin_Handled;
}

Action HealingZombies_OnTakeDamage(int victim, int& attacker, int& inflictor, float& damage, int& damagetype) {
    if(attacker > MaxClients) {
        static char buffer[32];
        GetEntityClassname(attacker, buffer, sizeof(buffer));
        if(StrEqual(buffer, "infected")) {
            // Disable dmg, instead give victim health, and hurt zombie
            damage = 0.0;

            int health = GetClientHealth(victim);
	        SetEntProp(victim, Prop_Send, "m_iHealth", health + 1);

            SDKHooks_TakeDamage(attacker, victim, victim, 50.0);
            return Plugin_Changed;
        }
    }
	return Plugin_Continue;
}