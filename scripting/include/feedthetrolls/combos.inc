
ArrayList combos;

enum struct SpecifiedTroll {
    int id;
    trollModifier mod;
    int flags;
}
enum struct TrollCombo {
    char name[32];
    ArrayList trolls;

    void AddTroll(const char[] name, int flags = 0, trollModifier mod = TrollMod_Invalid) {
        int id = GetTrollID(name);
        if(mod == TrollMod_Invalid) mod = Trolls[id].GetDefaultMod();
        SpecifiedTroll troll;
        troll.id = id;
        troll.mod = mod;
        troll.flags = flags;
        this.trolls.PushArray(troll, sizeof(troll));
    }

    void Activate(int client, int target) {
        for(int i = 0; i < this.trolls.Length; i++) {
            SpecifiedTroll troll;
            this.trolls.GetArray(i, troll, sizeof(troll));
            Trolls[troll.id].Activate(target, client, troll.mod, troll.flags);
        }
    }
}

void SetupCombo(TrollCombo combo, const char[] name) {
    strcopy(combo.name, sizeof(combo.name), name);
    combo.trolls = new ArrayList(sizeof(SpecifiedTroll));
    combos.PushArray(combo, sizeof(combo));
}

void SetupsTrollCombos() {
    combos = new ArrayList(sizeof(TrollCombo));

    TrollCombo combo;
    SetupCombo(combo, "Magnet Galore");
    combo.AddTroll("Special Magnet");
    combo.AddTroll("Tank Magnet");
    #if defined _behavior_included
    combo.AddTroll("Witch Magnet");
    #endif

    SetupCombo(combo, "Rush Stopper");
    combo.AddTroll("Special Magnet");
    combo.AddTroll("Tank Magnet");
    #if defined _behavior_included
    combo.AddTroll("Witch Magnet");
    #endif
    combo.AddTroll("No Button Touchie", TrollMod_Constant, 17);
    combo.AddTroll("Slow Speed", TrollMod_Constant, 2);
    combo.AddTroll("Instant Commons", TrollMod_Instant, 1);
    // combo.AddTroll("Swarm", TrollMod_Instant);
    combo.AddTroll("Vomit Player");
    combo.AddTroll("Dull Melee", .flags=2);

    SetupCombo(combo, "Tank Run Noob");
    combo.AddTroll("Slow Speed");
    combo.AddTroll("Tank Magnet");

    SetupCombo(combo, "Nuclear");
    combo.AddTroll("Slow Speed");
    combo.AddTroll("Special Magnet");
    combo.AddTroll("Tank Magnet");
    #if defined _behavior_included
    combo.AddTroll("Witch Magnet");
    #endif
    combo.AddTroll("Reverse FF", .flags=2);
    combo.AddTroll("Vomit Player");

    SetupCombo(combo, "No more survival");
    combo.AddTroll("No Pickup", .flags = 8)
    combo.AddTroll("Throw It All", .flags = 1)

    SetupCombo(combo, "Shut up");
    combo.AddTroll("Vocalize Gag");
    combo.AddTroll("Honk / Meow / Woof", .flags=1);

    SetupCombo(combo, "Weakness Compels You");
    combo.AddTroll("No Shove");
    combo.AddTroll("Dull Melee", .flags=2);
    combo.AddTroll("Temp Health Quick Drain");

    PrintToServer("[FTT] Loaded %d troll combos", combos.Length);
}