
ArrayList combos;

enum struct SpecifiedTroll {
    int id;
    trollModifier mod;
    int flags;
}
enum struct TrollComboData {
    char name[32];
    ArrayList trolls;

    bool AddTroll(const char[] name, int flags = 0, trollModifier mod = TrollMod_Invalid) {
        Troll instance; 
        if(!Troll.TryFromName(name, instance)) {
            PrintToServer("[FTT] Combo \"%s\": unknown troll named \"%s\"", this.name, name);
            return false;
        }
        if(mod == TrollMod_Invalid) mod = instance.GetDefaultMod();
        SpecifiedTroll troll;
        troll.id = instance.Id;
        troll.mod = mod;
        troll.flags = flags;
        this.trolls.PushArray(troll, sizeof(troll));
        return true;
    }

    void Activate(int client, int target) {
        PrintToServer("Applying %d trolls for combo %s for %N", this.trolls.Length, this.name, target);
        SpecifiedTroll troll;
        for(int i = 0; i < this.trolls.Length; i++) {
            this.trolls.GetArray(i, troll, sizeof(troll));
            Troll(troll.id).Activate(client, target, troll.mod, troll.flags);
        }
    }
}

void SetupCombo(TrollComboData combo, const char[] name) {
    strcopy(combo.name, sizeof(combo.name), name);
    combo.trolls = new ArrayList(sizeof(SpecifiedTroll));
    combos.PushArray(combo, sizeof(combo));
}

void SetupsTrollCombos() {
    combos = new ArrayList(sizeof(TrollComboData));

    TrollComboData combo;
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
    combo.AddTroll("No Button Touchie", 17, TrollMod_Constant);
    combo.AddTroll("Slow Speed", 2, TrollMod_Constant);
    combo.AddTroll("Instant Commons", 1, TrollMod_Instant);
    // combo.AddTroll("Swarm", TrollMod_Instant);
    combo.AddTroll("Vomit Player");
    combo.AddTroll("Dull Melee", .flags=2);

    SetupCombo(combo, "Tank Run Noob");
    combo.AddTroll("Slow Speed");
    combo.AddTroll("Tank Magnet");

    SetupCombo(combo, "Nuclear");
    combo.AddTroll("Slow Speed");
    combo.AddTroll("Special Magnet", .flags=1);
    combo.AddTroll("Tank Magnet", .flags=1);
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
    combo.AddTroll("Honk & Animal Sounds", .flags=1);

    SetupCombo(combo, "Weakness Compels You");
    combo.AddTroll("No Shove");
    combo.AddTroll("Dull Melee", .flags=2);
    combo.AddTroll("Temp Health Quick Drain");

    SetupCombo(combo, "Blindness");
    combo.AddTroll("Vomit Player", 0, TrollMod_Constant);
    combo.AddTroll("Shakey Camera", .flags=16);
    combo.AddTroll("Randomize Angles", .flags=16);

    PrintToServer("[FTT] Loaded %d troll combos", combos.Length);
}