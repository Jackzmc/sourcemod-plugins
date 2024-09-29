int SpawnCar(VariantEntityData entity) {
	if(entity.model[0] == '\0') {
		LogError("Missing model for entity with type \"%s\"", entity.type);
		return -1;
	}
	PrecacheModel(entity.model);
	int vehicle;

	if(StrEqual(entity.type, "_car_alarm")) {
        vehicle = SpawnAlarmCar(entity.model, entity.origin, entity.angles, entity.color);
        return vehicle;
    }

    char glassModel[64];
	strcopy(glassModel, sizeof(glassModel), entity.type);
    ReplaceString(glassModel, sizeof(glassModel), ".mdl", "_glass.mdl");
    if(StrEqual(entity.type, "_car_physics")) {
        vehicle = CreateProp("prop_physics", entity.model, entity.origin, entity.angles);
	} else {
        vehicle = CreateProp("prop_dynamic", entity.model, entity.origin, entity.angles);
    }
	if(PrecacheModel(glassModel)) {
		int glass = CreateProp(glassModel, entity.model, entity.origin, entity.angles);
        SetVariantString("!activator");
	    AcceptEntityInput(glass, "SetParent", vehicle);
    }
	SetEntityRenderColor(vehicle, GetRandomInt(0, 255), GetRandomInt(0, 255), GetRandomInt(0, 255));
    return vehicle;
}


/**
// ====================================================================================================
:::BEGIN::: -> Source Code (with changes) from:
* DieTeetasse - [L4D1&2] Spawn Alarmcars plugin https://forums.alliedmods.net/showthread.php?t=139352
* Marttt - [L4D1 & L4D2] Replace Cars Into Car Alarms plugin https://forums.alliedmods.net/showthread.php?p=2731868
// ====================================================================================================
*/

/****************************************************************************************************/

#define DISTANCE_FRONT                101.0
#define DISTANCE_SIDETURN             34.0
#define DISTANCE_UPFRONT              29.0
#define DISTANCE_BACK                 103.0
#define DISTANCE_SIDE                 27.0
#define DISTANCE_UPBACK               31.0
#define SOUND_CAR_ALARM               "vehicles/car_alarm/car_alarm.wav"
#define SOUND_CAR_ALARM_CHIRP2        "vehicles/car_alarm/car_alarm_chirp2.wav"

#define COLOR_YELLOWLIGHT             "224 162 44"
#define COLOR_REDLIGHT                "255 13 19"
#define COLOR_WHITELIGHT              "252 243 226"
#define ALARMCAR_GLOW_SPRITE          "sprites/glow.vmt"

int SpawnAlarmCar(const char[] model, float vPos[3], float vAng[3], int color[4] = { 255, 255, 255, 255})
{   
    PrecacheModel(model);
    PrecacheModel(ALARMCAR_GLOW_SPRITE, true);
    PrecacheSound(SOUND_CAR_ALARM, true);
    PrecacheSound(SOUND_CAR_ALARM_CHIRP2, true);

    char carName[64];
    char glassOnName[64];
    char glassOffName[64];
    char timerName[64];
    char alarmSoundName[64];
    char chirpSoundName[64];
    char lightsName[64];
    char headlightsName[64];
    char remarkName[64];
    char gameEventName[64];

    // create car
    int carEntity = CreateEntityByName("prop_car_alarm");

    FormatEx(carName, sizeof(carName), "randomizer_car_%d", carEntity);
    FormatEx(glassOnName, sizeof(glassOnName), "randomizer_car_glasson_%d", carEntity);
    FormatEx(glassOffName, sizeof(glassOffName), "randomizer_car_glassoff_%d", carEntity);
    FormatEx(timerName, sizeof(timerName), "randomizer_car_alarmtimer_%d", carEntity);
    FormatEx(alarmSoundName, sizeof(alarmSoundName), "randomizer_car_alarmsound_%d", carEntity);
    FormatEx(chirpSoundName, sizeof(chirpSoundName), "randomizer_car_chirpsound_%d", carEntity);
    FormatEx(lightsName, sizeof(lightsName), "randomizer_car_lights_%d", carEntity);
    FormatEx(headlightsName, sizeof(headlightsName), "randomizer_car_headlights_%d", carEntity);
    FormatEx(remarkName, sizeof(remarkName), "randomizer_car_remark_%d", carEntity);
    FormatEx(gameEventName, sizeof(gameEventName), "randomizer_car_gameevent_%d", carEntity);
    char tempString[128];

    DispatchKeyValue(carEntity, "targetname", carName);
    DispatchKeyValue(carEntity, "model", model);
    Format(tempString, sizeof(tempString), "%d %d %d %d", color[0], color[1], color[2], color[3]);
    DispatchKeyValue(carEntity, "rendercolor", tempString);
    Debug("spawning alarm car ent%d \"%s\" (m=%s) at %.0f %.0f %.0f", carEntity, carName, model, vPos[0], vPos[1], vPos[2]);

    Format(tempString, sizeof(tempString), "%s,PlaySound,,0.2,-1", chirpSoundName);
    DispatchKeyValue(carEntity, "OnCarAlarmChirpStart", tempString);
    Format(tempString, sizeof(tempString), "%s,ShowSprite,,0.2,-1", lightsName);
    DispatchKeyValue(carEntity, "OnCarAlarmChirpStart", tempString);
    Format(tempString, sizeof(tempString), "%s,HideSprite,,0.7,-1", lightsName);
    DispatchKeyValue(carEntity, "OnCarAlarmChirpEnd", tempString);
    Format(tempString, sizeof(tempString), "%s,Enable,,0,-1", timerName);
    DispatchKeyValue(carEntity, "OnCarAlarmStart", tempString);
    Format(tempString, sizeof(tempString), "%s,PlaySound,,0,-1", alarmSoundName);
    DispatchKeyValue(carEntity, "OnCarAlarmStart", tempString);
    Format(tempString, sizeof(tempString), "%s,Enable,,0,-1", glassOffName);
    DispatchKeyValue(carEntity, "OnCarAlarmStart", tempString);
    DispatchKeyValue(carEntity, "OnHitByTank", tempString);
    Format(tempString, sizeof(tempString), "%s,Kill,,0,-1", glassOnName);
    DispatchKeyValue(carEntity, "OnCarAlarmStart", tempString);
    DispatchKeyValue(carEntity, "OnHitByTank", tempString);
    Format(tempString, sizeof(tempString), "%s,Kill,,0,-1", timerName);
    DispatchKeyValue(carEntity, "OnCarAlarmEnd", tempString);
    DispatchKeyValue(carEntity, "OnHitByTank", tempString);
    Format(tempString, sizeof(tempString), "%s,Kill,,0,-1", alarmSoundName);
    DispatchKeyValue(carEntity, "OnCarAlarmEnd", tempString);
    DispatchKeyValue(carEntity, "OnHitByTank", tempString);
    Format(tempString, sizeof(tempString), "%s,Kill,,0,-1", chirpSoundName);
    DispatchKeyValue(carEntity, "OnCarAlarmEnd", tempString);
    DispatchKeyValue(carEntity, "OnHitByTank", tempString);
    Format(tempString, sizeof(tempString), "%s,Kill,,0,-1", lightsName);
    DispatchKeyValue(carEntity, "OnCarAlarmEnd", tempString);
    DispatchKeyValue(carEntity, "OnHitByTank", tempString);
    Format(tempString, sizeof(tempString), "%s,Kill,,0,-1", headlightsName);
    DispatchKeyValue(carEntity, "OnCarAlarmEnd", tempString);
    DispatchKeyValue(carEntity, "OnHitByTank", tempString);
    Format(tempString, sizeof(tempString), "%s,Kill,,0,-1", remarkName);
    DispatchKeyValue(carEntity, "OnCarAlarmEnd", tempString);
    DispatchKeyValue(carEntity, "OnHitByTank", tempString);
    Format(tempString, sizeof(tempString), "%s,Kill,,0,-1", gameEventName);
    DispatchKeyValue(carEntity, "OnCarAlarmEnd", tempString);
    DispatchKeyValue(carEntity, "OnHitByTank", tempString);
    DispatchKeyValueVector(carEntity, "origin", vPos);
    DispatchKeyValueVector(carEntity, "angles", vAng);
    DispatchSpawn(carEntity);

    // create glasses
    strcopy(tempString, sizeof(tempString), model);
    ReplaceString(tempString, sizeof(tempString), ".mdl", "_glass.mdl");
    if(PrecacheModel(tempString))
        CreateGlass(tempString, glassOnName, false, vPos, vAng, carName);
    // CreateGlass(glassOffName, true, vPos, vAng, carName);

    CreateSound(alarmSoundName, "16", "Car.Alarm", vPos, carName);
    CreateSound(chirpSoundName, "48", "Car.Alarm.Chirp2", vPos, carName);

    CreateLights(lightsName, vPos, vAng, carName);

    CreateHeadlights(headlightsName, vPos, vAng, carName);

    CreateLogicTimer(timerName, lightsName, headlightsName, vPos, carName);

    CreateRemark(remarkName, vPos, vAng, carName);

    CreateGameEvent(gameEventName, vPos, vAng, carName);

    return carEntity;
}

/****************************************************************************************************/

void CreateGlass(const char[] model, char[] targetName, bool startDisabled, float vPos[3], float vAng[3], char[] carName)
{
    int entity = CreateEntityByName("prop_car_glass");

    DispatchKeyValue(entity, "targetname", targetName);
    DispatchKeyValue(entity, "model", model);
    DispatchKeyValue(entity, "StartDisabled", startDisabled ? "1" : "0");
    DispatchKeyValueVector(entity, "origin", vPos);
    DispatchKeyValueVector(entity, "angles", vAng);
    DispatchSpawn(entity);

    SetVariantString(carName);
    AcceptEntityInput(entity, "SetParent", entity, entity, 0);
}

/****************************************************************************************************/

void CreateSound(char[] targetName, char[] spawnFlags, char[] messageName, float vPos[3], char[] carName)
{
    int entity = CreateEntityByName("ambient_generic");

    float newPos[3];
    newPos = vPos;
    newPos[2] += 80.0;

    DispatchKeyValue(entity, "targetname", targetName);
    DispatchKeyValue(entity, "spawnflags", spawnFlags);
    DispatchKeyValue(entity, "message", messageName);
    DispatchKeyValue(entity, "SourceEntityName", carName);
    DispatchKeyValue(entity, "radius", "4000");
    DispatchKeyValueVector(entity, "origin", newPos);
    DispatchSpawn(entity);
    ActivateEntity(entity); // Don't work without it

    SetVariantString(carName);
    AcceptEntityInput(entity, "SetParent", entity, entity, 0);
}

/****************************************************************************************************/

void CreateLights(char[] lightsName, float vPos[3], float vAng[3], char[] carName)
{
    float distance[6] = {DISTANCE_FRONT, DISTANCE_SIDETURN, DISTANCE_UPFRONT, DISTANCE_BACK, DISTANCE_SIDE, DISTANCE_UPBACK};
    float newPos[3];
    float lightDistance[3];

    newPos = vPos;
    lightDistance[0] = distance[0];
    lightDistance[1] = distance[1]*-1.0;
    lightDistance[2] = distance[2];
    MoveVectorvPos3D(newPos, vAng, lightDistance); // front left
    CreateVehicleLight(lightsName, COLOR_YELLOWLIGHT, newPos, carName);

    newPos = vPos;
    lightDistance[1] = distance[1];
    MoveVectorvPos3D(newPos, vAng, lightDistance); // front right
    CreateVehicleLight(lightsName, COLOR_YELLOWLIGHT, newPos, carName);

    newPos = vPos;
    lightDistance[0] = distance[3]*-1.0;
    lightDistance[1] = distance[4]*-1.0;
    lightDistance[2] = distance[5];
    MoveVectorvPos3D(newPos, vAng, lightDistance); // back left
    CreateVehicleLight(lightsName, COLOR_REDLIGHT, newPos, carName);

    newPos = vPos;
    lightDistance[1] = distance[4];
    MoveVectorvPos3D(newPos, vAng, lightDistance); // back right
    CreateVehicleLight(lightsName, COLOR_REDLIGHT, newPos, carName);
}

/****************************************************************************************************/

static void CreateVehicleLight(char[] targetName, char[] renderColor, float vPos[3], char[] carName)
{
    int entity = CreateEntityByName("env_sprite");

    DispatchKeyValue(entity, "targetname", targetName);
    DispatchKeyValue(entity, "rendercolor", renderColor);
    DispatchKeyValue(entity, "model", ALARMCAR_GLOW_SPRITE);
    DispatchKeyValue(entity, "scale", "0.5");
    DispatchKeyValue(entity, "rendermode", "9");
    DispatchKeyValue(entity, "renderamt", "255");
    DispatchKeyValue(entity, "HDRColorScale", "0.7");
    DispatchKeyValue(entity, "GlowProxySize", "5");
    DispatchKeyValueVector(entity, "origin", vPos);
    DispatchSpawn(entity);

    SetVariantString(carName);
    AcceptEntityInput(entity, "SetParent", entity, entity, 0);
}

/****************************************************************************************************/

void CreateHeadlights(char[] headlightsName, float vPos[3], float vAng[3], char[] carName)
{
    float distance[3] = {DISTANCE_FRONT, DISTANCE_SIDE, DISTANCE_UPFRONT};
    float newPos[3];
    float headlightDistance[3];

    newPos = vPos;
    headlightDistance[0] = distance[0];
    headlightDistance[1] = distance[1]*-1.0;
    headlightDistance[2] = distance[2];
    MoveVectorvPos3D(newPos, vAng, headlightDistance); // front left
    CreateHeadlight(headlightsName, newPos, vAng, carName);

    newPos = vPos;
    headlightDistance[1] = distance[1];
    MoveVectorvPos3D(newPos, vAng, headlightDistance); // front right
    CreateHeadlight(headlightsName, newPos, vAng, carName);
}

/****************************************************************************************************/

void CreateHeadlight(char[] targetName, float vPos[3], float vAng[3], char[] carName)
{
    int entity = CreateEntityByName("beam_spotlight");

    DispatchKeyValue(entity, "targetname", targetName);
    DispatchKeyValue(entity, "rendercolor", COLOR_WHITELIGHT);
    DispatchKeyValue(entity, "spotlightwidth", "32");
    DispatchKeyValue(entity, "spotlightlength", "256");
    DispatchKeyValue(entity, "spawnflags", "2");
    DispatchKeyValue(entity, "rendermode", "5");
    DispatchKeyValue(entity, "renderamt", "150");
    DispatchKeyValue(entity, "maxspeed", "100");
    DispatchKeyValue(entity, "HDRColorScale", "0.5");
    DispatchKeyValueVector(entity, "origin", vPos);
    DispatchKeyValueVector(entity, "angles", vAng);
    DispatchSpawn(entity);

    SetVariantString(carName);
    AcceptEntityInput(entity, "SetParent", entity, entity, 0);
}

/****************************************************************************************************/

void CreateLogicTimer(char[] targetName, char[] lightsName, char[] headlightsName, float vPos[3], char[] carName)
{
    int entity = CreateEntityByName("logic_timer");

    DispatchKeyValue(entity, "targetname", targetName);
    DispatchKeyValue(entity, "StartDisabled", "1");
    DispatchKeyValue(entity, "RefireTime", "0.75");

    char tempString[128];
    Format(tempString, sizeof(tempString), "%s,ShowSprite,,0,-1", lightsName);
    DispatchKeyValue(entity, "OnTimer", tempString);
    Format(tempString, sizeof(tempString), "%s,ShowSprite,,0,-1", lightsName);
    DispatchKeyValue(entity, "OnTimer", tempString);
    Format(tempString, sizeof(tempString), "%s,LightOn,,0,-1", headlightsName);
    DispatchKeyValue(entity, "OnTimer", tempString);
    Format(tempString, sizeof(tempString), "%s,HideSprite,,0.5,-1", lightsName);
    DispatchKeyValue(entity, "OnTimer", tempString);
    Format(tempString, sizeof(tempString), "%s,HideSprite,,0.5,-1", lightsName);
    DispatchKeyValue(entity, "OnTimer", tempString);
    Format(tempString, sizeof(tempString), "%s,LightOff,,0.5,-1", headlightsName);
    DispatchKeyValue(entity, "OnTimer", tempString);
    DispatchKeyValueVector(entity, "origin", vPos);
    DispatchSpawn(entity);

    SetVariantString(carName);
    AcceptEntityInput(entity, "SetParent", entity, entity, 0);
}

/****************************************************************************************************/

void CreateRemark(char[] targetName, float vPos[3], float vAng[3], char[] carName)
{
    int entity = CreateEntityByName("info_remarkable");

    DispatchKeyValue(entity, "targetname", targetName);
    DispatchKeyValue(entity, "contextsubject", "remark_caralarm");
    DispatchKeyValueVector(entity, "origin", vPos);
    DispatchKeyValueVector(entity, "angles", vAng);
    DispatchSpawn(entity);

    SetVariantString(carName);
    AcceptEntityInput(entity, "SetParent", entity, entity, 0);
}

/****************************************************************************************************/

void CreateGameEvent(char[] targetName, float vPos[3], float vAng[3], char[] carName)
{
    int entity = CreateEntityByName("info_game_event_proxy");

    DispatchKeyValue(entity, "targetname", targetName);
    DispatchKeyValue(entity, "spawnflags", "1");
    DispatchKeyValue(entity, "range", "100");
    DispatchKeyValue(entity, "event_name", "explain_disturbance");
    DispatchKeyValueVector(entity, "origin", vPos);
    DispatchKeyValueVector(entity, "angles", vAng);
    DispatchSpawn(entity);

    SetVariantString(carName);
    AcceptEntityInput(entity, "SetParent", entity, entity, 0);
}

/****************************************************************************************************/

void MoveVectorvPos3D(float vPos[3], float constvAng[3], float constDistance[3])
{
    float vAng[3], dirFw[3], dirRi[3], dirUp[3], distance[3];
    distance = constDistance;

    vAng[0] = DegToRad(constvAng[0]);
    vAng[1] = DegToRad(constvAng[1]);
    vAng[2] = DegToRad(constvAng[2]);

    // roll (rotation over x)
    dirFw[0] = 1.0;
    dirFw[1] = 0.0;
    dirFw[2] = 0.0;
    dirRi[0] = 0.0;
    dirRi[1] = Cosine(vAng[2]);
    dirRi[2] = Sine(vAng[2])*-1;
    dirUp[0] = 0.0;
    dirUp[1] = Sine(vAng[2]);
    dirUp[2] = Cosine(vAng[2]);
    MatrixMulti(dirFw, dirRi, dirUp, distance);

    // pitch (rotation over y)
    dirFw[0] = Cosine(vAng[0]);
    dirFw[1] = 0.0;
    dirFw[2] = Sine(vAng[0]);
    dirRi[0] = 0.0;
    dirRi[1] = 1.0;
    dirRi[2] = 0.0;
    dirUp[0] = Sine(vAng[0])*-1;
    dirUp[1] = 0.0;
    dirUp[2] = Cosine(vAng[0]);
    MatrixMulti(dirFw, dirRi, dirUp, distance);

    // yaw (rotation over z)
    dirFw[0] = Cosine(vAng[1]);
    dirFw[1] = Sine(vAng[1])*-1;
    dirFw[2] = 0.0;
    dirRi[0] = Sine(vAng[1]);
    dirRi[1] = Cosine(vAng[1]);
    dirRi[2] = 0.0;
    dirUp[0] = 0.0;
    dirUp[1] = 0.0;
    dirUp[2] = 1.0;
    MatrixMulti(dirFw, dirRi, dirUp, distance);

    // addition
    for (int i = 0; i < 3; i++) vPos[i] += distance[i];
}

/****************************************************************************************************/

void MatrixMulti(float matA[3], float matB[3], float matC[3], float vec[3])
{
    float res[3];
    for (int i = 0; i < 3; i++) res[0] += matA[i]*vec[i];
    for (int i = 0; i < 3; i++) res[1] += matB[i]*vec[i];
    for (int i = 0; i < 3; i++) res[2] += matC[i]*vec[i];
    vec = res;
}

/**
// ====================================================================================================
:::END::: -> Source Code from DieTeetasse - [L4D1&2] Spawn Alarmcars plugin https://forums.alliedmods.net/showthread.php?t=139352
// ====================================================================================================
*/