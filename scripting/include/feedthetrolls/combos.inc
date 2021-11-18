
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
    combo.AddTroll("Witch Magnet");

    SetupCombo(combo, "Tank Run Noob");
    combo.AddTroll("Slow Speed");
    combo.AddTroll("Tank Magnet");

    SetupCombo(combo, "Nuclear");
    combo.AddTroll("Slow Speed");
    combo.AddTroll("Special Magnet");
    combo.AddTroll("Tank Magnet");
    combo.AddTroll("Witch Magnet");
    combo.AddTroll("Reverse FF", .flags=2);
    combo.AddTroll("Vomit Player");

    PrintToServer("[FTT] Loaded %d troll combos", combos.Length);
}