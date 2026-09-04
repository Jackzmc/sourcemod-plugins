
#define NUM_VEHICLES 3

#define MODEL_CEDA_VEHICLE "models/props_vehicles/deliveryvan_armored.mdl"
#define MODEL_TRAIN_LOCOMOTIVE "models/props_vehicles/train_enginecar.mdl"
#define MODEL_TRACTOR "models/props_vehicles/tractor.mdl"
#define MODEL_FLOAT "models/props_downtown/parade_float.mdl"
#define NUM_TRAIN_CARTS 2
static char TRAIN_CARTS[NUM_TRAIN_CARTS][] = {
    "models/props_vehicles/train_box_open.mdl",
    "models/props_vehicles/train_flatcar.mdl"
};

float VEH_CFG[][] = {
    // #weigh(int), dist, dura, dly, v.offset, fwd.offset
    { 50.0,   800.0,  5.0, 0.0, 0.0, 0.0   }, // Delivery van
    { 1.0,    1800.0,  7.0, 5.0, 50.0, 0.0   }, // Train,
    { 1.0,    800.0,  5.0, 2.0, 50.0, -280.0  }, // Lil' Peanut Float
};

char VEH_SDN_CFG[][][] = {
    // idle, horn (either optional, set to "")
    { "vehicles/diesel_loop2.wav", "vehicles/humvee_horn.wav" },  // Delivry van
    { "ambient/alarms/train_crossing_bell_loop1.wav", "", },       // Train
    { "vehicles/tractor/tractor_start_loop.wav", "npc/lilpeanut/lilpeanut04.wav" },
}
enum KidnapState {
    KidnapState_Active = 1,
    KidnapState_Midpoint = 2
}

methodmap VehCfg {
    public VehCfg(int type) {
        return view_as<VehCfg>(type);
    }

    property int Type {
        public get() { return view_as<int>(this); }
    }

    property int Weight {
        public get() { return RoundToFloor(VEH_CFG[this.Type][0]); }
    }
    
    property float Distance {
        public get() { return VEH_CFG[this.Type][1]; }
    }

    property float Duration {
        public get() { return VEH_CFG[this.Type][2]; }
    }

    property float Delay {
        public get() { return VEH_CFG[this.Type][3]; }
    }

    public void GetOffset(float pos[3]) {
        pos[0] = VEH_CFG[this.Type][5];
        pos[1] = 0.0;
        pos[2] = VEH_CFG[this.Type][4];
    }

    public bool GetIdleSound(char[] buffer, int maxlen) {
        if(VEH_SDN_CFG[this.Type][0][0] != '\0') {
            strcopy(buffer, maxlen, VEH_SDN_CFG[this.Type][0]);
            return true;
        }
        return false;
    }

    public bool GetHornSound(char[] buffer, int maxlen) {
        if(VEH_SDN_CFG[this.Type][1][0] != '\0') {
            strcopy(buffer, maxlen, VEH_SDN_CFG[this.Type][1]);
            return true;
        }
        return false;
    }

    public void PrecacheSounds() {
        char buffer[64];
        if(this.GetIdleSound(buffer, sizeof(buffer))) {
            PrecacheSound(buffer);
        }
        if(this.GetHornSound(buffer, sizeof(buffer))) {
            PrecacheSound(buffer);
        }
    }

    public void PlayIdleSound(int entity) {
        char buffer[64];
        if(this.GetIdleSound(buffer, sizeof(buffer))) {
            PrintToServer("Kidnap: Playing idle \"%s\"", buffer);
            EmitSoundToAll(buffer, entity, SNDCHAN_STATIC, .level = SNDLEVEL_TRAIN, .volume = 1.0, .flags = SND_CHANGEVOL);
        }
    }

    public void PlayHornSound(int entity) {
        char buffer[64];
        if(this.GetHornSound(buffer, sizeof(buffer))) {
            PrintToServer("Kidnap: Playing horn \"%s\"", buffer);
            // double the volume
            EmitSoundToAll(buffer, entity, SNDCHAN_STATIC, .level = SNDLEVEL_TRAIN, .volume = 1.0, .flags = SND_CHANGEVOL);
            EmitSoundToAll(buffer, entity, SNDCHAN_STATIC, .level = SNDLEVEL_TRAIN, .volume = 1.0, .flags = SND_CHANGEVOL);
        }
    }

    public void Cleanup(int entRef) {
        char buffer[64];
        if(this.GetIdleSound(buffer, sizeof(buffer))) {
            StopSound(entRef, SNDCHAN_STATIC, buffer);
        }
        RemoveEntity(entRef);
    }
}

VehCfg SelectVehicle() {
    ArrayList indexes = new ArrayList();
    for(int i = 0; i < NUM_VEHICLES; i++) {
        VehCfg cfg = VehCfg(i); 
        for(int c = 0; c < cfg.Weight; c++) {
            indexes.Push(i);
        }
        PrintToServer("type %d chance %d", i, cfg.Weight);
    }
    int choiceIndex = GetRandomInt(0, indexes.Length - 1);
    int vehType = indexes.Get(choiceIndex);
    delete indexes;
    return VehCfg(vehType);
}

int SpawnVehicle(VehCfg cfg, const float startPos[3]) {
    cfg.PrecacheSounds();
    int ent = -1;
    if(cfg.Type == 1) {
        ent = SpawnTrain(startPos, GetRandomInt(2, 5));
    } else if(cfg.Type == 2) {
        ent = SpawnTractorFloat(startPos);  
    } else {
        PrecacheModel(MODEL_CEDA_VEHICLE);
        ent = CreateProp("prop_dynamic", MODEL_CEDA_VEHICLE, startPos);
    }
    cfg.PlayIdleSound(ent);
    return ent;
}

/**
 * numCarts excludes locomotive
 */
int SpawnTrain(const float startPos[3], int numCarts) {
    PrecacheModel(MODEL_TRAIN_LOCOMOTIVE);
    int locomotive = CreateProp("prop_dynamic", MODEL_TRAIN_LOCOMOTIVE, startPos);
    float pos[3];
    pos[0] = startPos[0];
    pos[1] = startPos[1];
    pos[2] = startPos[2];

    int lastEntity = locomotive;

    PrintToServer("pos[0]:%f", pos[0]);

    for(int i = 0; i < numCarts; i++) {
        // Pick random model
        int modelIndex = GetRandomInt(0, NUM_TRAIN_CARTS - 1);
        PrecacheModel(TRAIN_CARTS[modelIndex]);

        // Calculate length
        float mins[3], maxs[3];
        GetEntPropVector(lastEntity, Prop_Data, "m_vecMins", mins);
        GetEntPropVector(lastEntity, Prop_Data, "m_vecMaxs", maxs);
        float length = FloatAbs(maxs[0] - mins[0]);

        // Move behind previous entity
        pos[0] -= length;

        int cart = CreateProp("prop_dynamic", TRAIN_CARTS[modelIndex], pos);
        SetParent(cart, locomotive);
        lastEntity = cart;
    }

    return locomotive;
} 

int SpawnTractorFloat(const float startPos[3]) {
    PrecacheModel(MODEL_TRACTOR);
    PrecacheModel(MODEL_FLOAT);
    PrecacheModel(MODEL_PEANUT);
    int tractor = CreateProp("prop_dynamic", MODEL_TRACTOR, startPos);
    int peanut = CreateProp("prop_dynamic", MODEL_PEANUT, startPos);
    int floatProp = CreateProp("prop_dynamic", MODEL_FLOAT, startPos, { 0.0, -90.0, 0.0 });
    SetParentOffset(peanut, tractor, { -60.0, 0.0, 60.0 });
    SetParentOffset(floatProp, tractor, { -280.0, 0.0, 0.0 });

    return tractor;
}