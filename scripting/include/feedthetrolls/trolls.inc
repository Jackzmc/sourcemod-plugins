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
    AddMagnetFlags(index);

    SetCategory("Infected");
    SetupTroll("Swarm", "Swarms a player with zombies. Requires swarm plugin", TrollMod_Instant | TrollMod_Constant);
    SetupTroll("Vomit Player", "Shortcut to sm_vomitplayer. vomits the player.", TrollMod_Instant);
    SetupTroll("Inface Special", "Shortcut to sm_inface", TrollMod_Instant);
    SetupTroll("Insta Special", "Shortcut to sm_insta", TrollMod_Instant);
    SetupTroll("Goo", "Spawns a spitter puddle underneath them", TrollMod_Instant);

    SetCategory("Items");
    SetupTroll("Throw It All", "Player throws their item(s) periodically to a nearby player", TrollMod_Instant);
    index = SetupTroll("Bad Throw", "Player drops throwables on throw, and biles/molotovs themselves", TrollMod_Constant, true);
    Trolls[index].AddFlag("Biles", true);
    Trolls[index].AddFlag("Molotovs", true);
    Trolls[index].AddFlag("Pipebombs", true);
    SetupTroll("No Pickup", "Prevents a player from picking up ANY (new) item. Use ThrowItAll to make them drop", TrollMod_Constant);
    SetupTroll("UziRules", "Picking up a weapon gives them a UZI instead", TrollMod_Constant);
    SetupTroll("Primary Disable", "Player cannot pickup any weapons, only melee/pistols", TrollMod_Constant);
    SetupTroll("Half Primary Ammo", "Cuts their primary reserve ammo in half", TrollMod_Instant);

    SetCategory("Chat");
    SetupTroll("iCantSpellNoMore", "Chat messages letter will randomly changed with wrong letters", TrollMod_Constant);
    SetupTroll("No Profanity", "Replaces some words with random phrases", TrollMod_Constant);
    SetupTroll("Vocalize Gag", "Prevents player from sending any vocalizations (even automatic)", TrollMod_Constant);
    index = SetupTroll("Honk / Meow", "Honk", TrollMod_Constant, false);
    Trolls[index].AddFlag("Honk", true);
    Trolls[index].AddFlag("Meow", false);

    SetCategory("Health");
    SetupTroll("Damage Boost", "Makes a player take more damage than normal", TrollMod_Constant);
    SetupTroll("Temp Health Quick Drain", "Makes a player's temporarily health drain very quickly", TrollMod_Constant);
    SetupTroll("Slow Drain", "Will make the player slowly lose health over time", TrollMod_Constant);
    SetupTroll("KillMeSoftly", "Make player eat or waste pills whenever possible", TrollMod_Instant | TrollMod_Constant);

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
    for(int i = 0; i < MAX_TROLLS; i++) {
        for(int j = 1; j <= MAXPLAYERS; j++) {
            Trolls[i].activeFlagClients[j] = -1;
        }
    }
}

void AddMagnetFlags(int index) {
    Trolls[index].AddFlag("Always (100%)", true);
    Trolls[index].AddFlag("Half Time (50%)", false);
    Trolls[index].AddFlag("Rare (10%)", false);
}