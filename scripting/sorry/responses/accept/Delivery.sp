#define TRAVEL_DUR 20.0
#define TRAVEL_SPEED 50.0

#define MODEL_YAW_OFFSET   -90.0   // model faces -Y when m_angRotation[1] == 0
#define REAR_CLEARANCE      60.0
#define LAUNCH_SPEED 100.0
#define SPAWN_DIST 220.0

#define MODEL_DELIVERY_VAN "models/props/de_nuke/truck_nuke.mdl"

#define NUM_CARGO_MODELS 11
char CARGO_MODELS[NUM_CARGO_MODELS][] = {
	// a little hacky but we want to weigh these higher:
	MODEL_CRATE,
	MODEL_CRATE,
	MODEL_CRATE,
	MODEL_CRATE2,
	MODEL_CRATE,
	MODEL_CRATE2,
	MODEL_GNOME,
	"models/props_furniture/bathtub1.mdl",
	"models/props_interiors/tv.mdl",
	"models/props_fortifications/orange_cone001_reference.mdl",
	"models/props_urban/tire001.mdl"
};

void Delivery_OnActivate(int apologizer, int target, const char[] eventId) {
    float clientPos[3], startPos[3], ang[3];
    GetClientAbsOrigin(apologizer, clientPos);
    GetClientEyeAngles(apologizer, ang);

    // Get initial position from behind and front of player
    GetHorizontalPositionFromOrigin(clientPos, ang, SPAWN_DIST, startPos);

	PrecacheModel(MODEL_DELIVERY_VAN);
	for(int i = 0; i < NUM_CARGO_MODELS; i++)
		PrecacheModel(CARGO_MODELS[i]);

	float speed = GetRandomFloat(20.0, 40.0);

	ang[0] = 0.0;
	ang[1] += 90.0; // model is 90deg sideways, adjust
	ang[2] = 0.0;
	// HACK: Source engine bug with SetAbsOrigin leaves ghost collisions. 
	// We have vehicle spawn at 0 0 0, then SetAbsOrigin to correct position
	// This leaves the ghost collision at 0 0 0, that should never collide with cargo
	int vehicleEnt = CreateProp("prop_dynamic", MODEL_DELIVERY_VAN, NULL_VECTOR, ang, NULL_VECTOR);
	SetAbsOrigin(vehicleEnt, startPos);
	ang[1] -= 90.0; // then unadjust
    StartDeliveryVehicle(vehicleEnt, ang[1], TRAVEL_DUR, speed);
}

void StartDeliveryVehicle(int vehicle, const float moveHeading, const float travelTime, const float speed) {
    // Move vehicle start -> end
    DataPack pack;
    CreateDataTimer(0.1, Timer_DeliveryMoveVehicle, pack, TIMER_REPEAT);
    pack.WriteCell(EntIndexToEntRef(vehicle));
    pack.WriteFloat(GetGameTime() + travelTime);
    pack.WriteFloat(speed);
	float ang[3];
	ang[1] = moveHeading;
	pack.WriteFloatArray(ang, 3);

	float dropInterval = 13.0 / speed; // At 30u/s, we want every 0.4sec

	CreateDataTimer(dropInterval, Timer_DeliverySpawnPackage, pack, TIMER_REPEAT);
    pack.WriteCell(EntIndexToEntRef(vehicle));
    pack.WriteFloat(GetGameTime() + travelTime);
}

Action Timer_DeliveryMoveVehicle(Handle h, DataPack pack) {
    pack.Reset();
    int ref = pack.ReadCell();
    if(!IsValidEntity(ref)) return Plugin_Handled;

    float endTime = pack.ReadFloat();
	float speed = pack.ReadFloat();
	float ang[3];
    pack.ReadFloatArray(ang, 3);

    float pos[3];
	GetEntPropVector(ref, Prop_Send, "m_vecOrigin", pos);

	GetHorizontalPositionFromOrigin(pos, ang, speed, pos);

    SetAbsOrigin(ref, pos);

    if(GetGameTime() >= endTime) {
		RemoveEntity(ref);
        // Stop movement
        return Plugin_Stop;
    }
    return Plugin_Continue
}

Action Timer_DeliverySpawnPackage(Handle h, DataPack pack) {
    pack.Reset();
    int ref = pack.ReadCell();
    if(!IsValidEntity(ref)) return Plugin_Handled;

    float endTime = pack.ReadFloat();
	float pos[3];

	GetEntPropVector(ref, Prop_Send, "m_vecOrigin", pos);

	SpawnCargo(ref, pos);
	if(GetRandomFloat() < 0.3) {
		SpawnItem(ref, pos);
	}

    return GetGameTime() >= endTime ? Plugin_Stop : Plugin_Continue
}

void SpawnItem(int ref, const float pos[3]) {
	float spawnPos[3], entAng[3], dir[3];
    GetEntPropVector(ref, Prop_Send, "m_angRotation", entAng);
	GetSpawnPos(pos, entAng, dir, spawnPos);

	// FIXME: items cant be picked up. use weapon_item_spawn ?

	int entity = CreateEntityByName("weapon_item_spawn");
	DispatchKeyValue(entity, "item3", "1"); // molotov
	DispatchKeyValue(entity, "item4", "1"); // pipe_bomb
	DispatchKeyValue(entity, "item8", "1"); // gas_can
	DispatchKeyValue(entity, "item11", "1"); // adrenaline
	DispatchKeyValue(entity, "item6", "1"); // oxygen tank
	DispatchKeyValue(entity, "item2", "1"); // first_aid_kit
	DispatchKeyValue(entity, "item12", "1"); // defib
	DispatchKeyValue(entity, "melee_weapon", "any"); 
	DispatchKeyValueInt(entity, "spawnflags", 1 | 2); // enable physics + spawned item must exist
	
	TeleportEntity(entity,  spawnPos, entAng);
	DispatchSpawn(entity);

	SetExitVelocity(entity, dir);
}


void SpawnCargo(int ref, const float pos[3]) {
	float spawnPos[3], entAng[3], dir[3];
    GetEntPropVector(ref, Prop_Send, "m_angRotation", entAng);
	GetSpawnPos(pos, entAng, dir, spawnPos);


	int cargoIndex = GetRandomInt(0, NUM_CARGO_MODELS - 1);
    int prop = CreateProp("prop_physics", CARGO_MODELS[cargoIndex], spawnPos, entAng, NULL_VECTOR, 8192);
	DispatchKeyValue(prop, "targetname", "sorry_delivery");
	
	SetExitVelocity(prop, dir);
}

void GetSpawnPos(const float pos[3], const float entAng[3], float outDir[3], float outPos[3]) {
    float modelYaw = DegToRad(entAng[1] + MODEL_YAW_OFFSET);
    outDir[0] = Cosine(modelYaw);
    outDir[1] = Sine(modelYaw);

	// get rear area to spawn in
    outPos[0] = pos[0] - REAR_CLEARANCE * outDir[0];
    outPos[1] = pos[1] - REAR_CLEARANCE * outDir[1];
    outPos[2] = pos[2] + 65.0;
}

void SetExitVelocity(int entity, const float dir[3]) {
	float launchSpeed = -GetRandomFloat(150.0, 300.0);

    float vel[3];
    vel[0] = launchSpeed * dir[0];        // backwards along the model's own axis
    vel[1] = launchSpeed * dir[1];
    vel[2] = 30.0;
	
    TeleportEntity(entity, .velocity = vel);
	float zero[3];
	// Fix source engine bug with velocity not being cleared causing trampoline effect
	SetEntPropVector(entity, Prop_Data, "m_vecAbsVelocity", zero);
	SetEntPropVector(entity, Prop_Data, "m_vecVelocity",    zero);
}