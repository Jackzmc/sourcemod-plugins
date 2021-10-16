// UP THE VALUE 'MAX_TROLLS' in base.inc before adding new ones!

void SetupTrolls() {
    trollKV = new StringMap();
    categories = new ArrayList(ByteCountToCells(16));
    int index;
    SetupTroll("Reset User", "Resets the user, removes all troll effects", TrollMod_Instant);

    SetCategory("Magnets");
    index = SetupTroll("Special Magnet", "Attracts ALL specials to any alive target with this troll enabled", TrollMod_Constant, false);
    AddMagnetFlags(index);
    index = SetupTroll("Tank Magnet", "Attracts ALL tanks to any alive target with this troll enabled", TrollMod_Constant, false);
    AddMagnetFlags(index);
    index = SetupTroll("Witch Magnet", "All witches when startled will target any player with this troll", TrollMod_Constant, false);

    SetCategory("Infected");
    SetupTroll("Swarm", "Swarms a player with zombies. Requires swarm plugin", TrollMod_Instant | TrollMod_Constant);
    SetupTroll("Vomit Player", "Shortcut to sm_vomitplayer. vomits the player.", TrollMod_Instant);
    SetupTroll("Inface Special", "Shortcut to sm_inface", TrollMod_Instant);
    SetupTroll("Insta Special", "Shortcut to sm_insta", TrollMod_Instant);
    SetupTroll("Goo", "Spawns a spitter puddle underneath them", TrollMod_Instant);

    SetCategory("Items");
    index = SetupTroll("Throw It All", "Player throws their item(s) periodically to a nearby player", TrollMod_Instant, false);
    //Can't add directly, is custom troll: 
    // Trolls[index].AddFlag("Throw to Admin", true);
    // Trolls[index].AddFlag("Drop At Feet", false);
    // Trolls[index].AddFlag("Drop At Admin", false);
    index = SetupTroll("Bad Throw", "Player drops throwables on throw, and biles/molotovs themselves", TrollMod_Constant, true);
    Trolls[index].AddFlagPrompt(true);
    Trolls[index].AddFlag("Biles", true);
    Trolls[index].AddFlag("Molotovs", true);
    Trolls[index].AddFlag("Pipebombs", true);
    SetupTroll("No Pickup", "Prevents a player from picking up ANY (new) item. Use ThrowItAll to make them drop", TrollMod_Constant);
    SetupTroll("UziRules", "Picking up a weapon gives them a UZI instead", TrollMod_Constant);
    SetupTroll("Primary Disable", "Player cannot pickup any weapons, only melee/pistols", TrollMod_Constant);
    index = SetupTroll("Dull Melee", "Player's melee weapon does 0 damage (based on %). Headshots still work", TrollMod_Constant);
    Trolls[index].AddFlagPrompt(false);
    Trolls[index].AddFlag("Always (100%)", false);
    Trolls[index].AddFlag("Half Time (50%)", true);
    Trolls[index].AddFlag("Rare (10%)", false);
    SetupTroll("Half Primary Ammo", "Cuts their primary reserve ammo in half", TrollMod_Instant);

    SetCategory("Chat");
    SetupTroll("iCantSpellNoMore", "Chat messages letter will randomly changed with wrong letters", TrollMod_Constant);
    index = SetupTroll("No Profanity", "Replaces some words with random phrases", TrollMod_Constant);
    Trolls[index].AddFlagPrompt(false);
    Trolls[index].AddFlag("Only Replace Swears", false);
    Trolls[index].AddFlag("Replace Full Messages", true);
    Trolls[index].AddFlagPrompt(false);
    Trolls[index].AddFlag("Show Modified to Them", true);
    Trolls[index].AddFlag("Show Original to Them", false);
    SetupTroll("Vocalize Gag", "Prevents player from sending any vocalizations (even automatic)", TrollMod_Constant);
    index = SetupTroll("Honk / Meow", "Honk or Meow", TrollMod_Constant, false);
    Trolls[index].AddCustomFlagPrompt("Choose Sound Type:");
    Trolls[index].AddFlag("Honk", true);
    Trolls[index].AddFlag("Meow", false);
    Trolls[index].AddCustomFlagPrompt("Choose Chat modifier:", false, 1);
    Trolls[index].AddFlag("Show Modified to Them", true);
    Trolls[index].AddFlag("Show Original to Them", false);
    SetupTroll("Reversed", "Reserves their message", TrollMod_Constant);

    SetCategory("Health");
    SetupTroll("Damage Boost", "Makes a player take more damage than normal", TrollMod_Constant);
    SetupTroll("Temp Health Quick Drain", "Makes a player's temporarily health drain very quickly", TrollMod_Constant);
    SetupTroll("Slow Drain", "Will make the player slowly lose health over time", TrollMod_Constant);
    SetupTroll("KillMeSoftly", "Make player eat or waste pills whenever possible", TrollMod_Instant | TrollMod_Constant);
    index = SetupTroll("Reverse FF", "All damage dealt to a player is reversed", TrollMod_Constant, false);
    Trolls[index].AddCustomFlagPrompt("Choose Reverse FF", false);
    Trolls[index].AddFlag("1:1 Ratio", true);
    Trolls[index].AddFlag("2x Ratio", false);
    Trolls[index].AddFlag("0.5x Ratio", false);

    SetCategory("Misc");
    SetupTroll("Gun Jam", "On reload, small chance their gun gets jammed - Can't reload.", TrollMod_Constant);
    SetupTroll("Slow Speed", "Sets player speed to 0.8x of normal speed", TrollMod_Constant);
    SetupTroll("Higher Gravity", "Sets player gravity to 1.3x of normal gravity", TrollMod_Constant);
    SetupTroll("No Shove", "Prevents a player from shoving", TrollMod_Constant);
    SetupTroll("CameTooEarly", "When they shoot, random chance they empty whole clip", TrollMod_Constant);
    SetupTroll("Inverted Controls", "Well, aint it obvious", TrollMod_Constant);
    SetupTroll("Stagger", "Like a slap, but different", TrollMod_Instant);
    //INFO: UP MAX_TROLLS when adding new trolls!
    

    // Initialize the default flag values to -1
    for(int i = 0; i <= MAX_TROLLS; i++) {
        for(int j = 1; j <= MAXPLAYERS; j++) {
            Trolls[i].activeFlagClients[j] = -1;
        }
    }
}

void AddMagnetFlags(int index) {
    Trolls[index].AddCustomFlagPrompt("Choose Magnet Chance:", false);
    Trolls[index].AddFlag("Always (100%)", true);
    Trolls[index].AddFlag("Half Time (50%)", false);
    Trolls[index].AddFlag("Rare (10%)", false);
}

bool ApplyAffect(int victim, const Troll troll, int activator, trollModifier modifier, int flags) {
    bool isActive = IsTrollActiveByRawID(victim, troll.id);
    if(StrEqual(troll.name, "Reset User")) {
        LogAction(activator, victim, "\"%L\" reset all troll effects for \"%L\"", activator, victim);
        ShowActivityEx(activator, "[FTT] ", "reset troll effects for %N. ", victim);
        for(int i = 0; i <= MAX_TROLLS; i++) {
            Trolls[i].activeFlagClients[victim] = -1;
        }
        SetEntPropFloat(victim, Prop_Send, "m_flLaggedMovementValue", 1.0);
        SetEntityGravity(victim, 1.0);
        return false;
    } else if(StrEqual(troll.name, "Slow Speed"))
        SetEntPropFloat(victim, Prop_Send, "m_flLaggedMovementValue", isActive ? 1.0 : 0.8);
    else if(StrEqual(troll.name, "Higher Gravity"))
        SetEntityGravity(victim, isActive ? 1.0 : 1.3);
    else if(StrEqual(troll.name, "Half Primary Ammo")) {
        int current = GetPrimaryReserveAmmo(victim);
        SetPrimaryReserveAmmo(victim, current / 2);
    } else if(StrEqual(troll.name, "UziRules")) {
        DisableTroll(victim, "No Pickup");
        DisableTroll(victim, "Primary Disable");
        SDKHook(victim, SDKHook_WeaponCanUse, Event_ItemPickup);
    } else if(StrEqual(troll.name, "Primary Disable")) {
        DisableTroll(victim, "UziRules");
        DisableTroll(victim, "No Pickup");
        SDKHook(victim, SDKHook_WeaponCanUse, Event_ItemPickup);
    } else if(StrEqual(troll.name, "No Pickup")) {
        DisableTroll(victim, "UziRules");
        DisableTroll(victim, "Primary Disable");
        SDKHook(victim, SDKHook_WeaponCanUse, Event_ItemPickup);
    } else if(StrEqual(troll.name, "CameTooEarly")) {
        ReplyToCommand(activator, "This troll mode is not implemented.");
    } else if(StrEqual(troll.name, "KillMeSoftly")) {
        static char wpn[32];
        GetClientWeaponName(victim, 4, wpn, sizeof(wpn));
        if(StrEqual(wpn, "weapon_adrenaline") || StrEqual(wpn, "weapon_pain_pills")) {
            ClientCommand(victim, "slot5");
            g_bPendingItemGive[victim] = true;
        }else{
            ReplyToCommand(activator, "User does not have pills or adrenaline");
            return false;
        }
        //TODO: Implement TrollMod_Constant
        return false;
    } else if(StrEqual(troll.name, "Throw It All")) {
        if(modifier == TrollMod_Instant)
            ThrowAllItems(victim);
        if(hThrowTimer == INVALID_HANDLE && modifier == TrollMod_Constant) {
            hThrowTimer = CreateTimer(hThrowItemInterval.FloatValue, Timer_ThrowTimer, _, TIMER_REPEAT);
        }
    } else if(StrEqual(troll.name, "Swarm")) {
        if(modifier == TrollMod_Instant) {
            L4D2_RunScript("RushVictim(GetPlayerFromUserID(%d), %d)", victim, 15000);
        }
        return true;
    } else if(StrEqual(troll.name, "Gun Jam")) {
        int wpn = GetClientWeaponEntIndex(victim, 0);
        if(wpn > -1)
            SDKHook(wpn, SDKHook_Reload, Event_WeaponReload);
        else {
            ReplyToCommand(activator, "Victim does not have a primary weapon.");
            return false;
        }
    } else if(StrEqual(troll.name, "Vomit Player"))
        L4D_CTerrorPlayer_OnVomitedUpon(victim, victim);
    else if(StrEqual(troll.name, "Inface Special")) {
        FakeClientCommand(victim, "sm_inface");
        return false;
    } else if(StrEqual(troll.name, "Insta Special")) {
        FakeClientCommand(victim, "sm_insta");
        return false;
    } else if(StrEqual(troll.name, "Goo")) {
        static float pos[3], ang[3];
        GetClientAbsOrigin(victim, pos);
        GetClientAbsAngles(victim, ang);
        L4D2_SpitterPrj(victim, pos, ang);
    } else if(StrEqual(troll.name, "Stagger")) {
        L4D_StaggerPlayer(victim, victim, NULL_VECTOR);
    } else if(modifier != TrollMod_Constant) {
        PrintToServer("[FTT] Warn: Possibly invalid troll, no apply action defined for \"%s\"", troll.name);
        #if defined DEBUG
        ReplyToCommand(activator, "[FTT/Debug] If nothing occurs, this troll possibly was not implemented correctly. ");
        #endif
    }
    return true;
}