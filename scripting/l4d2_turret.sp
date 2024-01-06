#pragma semicolon 1
#pragma newdecls required

//#define DEBUG

#define TURRET_MAX_RANGE_HUMANS 140.0 // Max range to find humans near. Does not activate if found
#define TURRET_MAX_RANGE_SPECIALS 1700.0 // Max range of specials (including tanks, not witches)
#define TURRET_MAX_RANGE_INFECTED 1500.0 // Max range of infected commons
#define TURRET_ACTIVATION_TIME 5.0 // The time for a new turret to activate

#define TURRET_MAX_RANGE_HUMANS_OPTIMIZED TURRET_MAX_RANGE_HUMANS * TURRET_MAX_RANGE_HUMANS
#define TURRET_MAX_RANGE_SPECIALS_OPTIMIZED TURRET_MAX_RANGE_SPECIALS * TURRET_MAX_RANGE_SPECIALS
#define TURRET_MAX_RANGE_INFECTED_OPTIMIZED TURRET_MAX_RANGE_INFECTED * TURRET_MAX_RANGE_INFECTED

#define TURRET_NORMAL_PHASE_TICKS 15 // The number of ticks to be in normal operation
#define TURRET_COMMON_PHASE_TICKS 5 // The number of ticks to clear out commons exclusively

#define _TURRET_PHASE_TICKS TURRET_NORMAL_PHASE_TICKS + TURRET_COMMON_PHASE_TICKS

// Taken from l4d_machine, thanks
#define SOUND_IMPACT_HIT		"physics/flesh/flesh_impact_bullet1.wav"  
#define SOUND_IMPACT_MISS		"physics/concrete/concrete_impact_bullet1.wav"  
#define SOUND_FIRE				"weapons/50cal/50cal_shoot.wav"  
#define PARTICLE_WEAPON_TRACER  "weapon_tracers_50cal"

#define PLUGIN_VERSION "2.0"

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <left4dhooks>
#include <jutils>
// #include <profiler>


#define PARTICLE_ELMOS			"st_elmos_fire_cp0"
#define PARTICLE_TES1			"electrical_arc_01_system"
#define ENT_PORTAL_NAME "turret"
#define SOUND_LASER_FIRE "custom/xen_teleport.mp3"
#define TEAM_SPECIALS 3
#define TEAM_SURVIVORS 2
// #define SOUND_LASER_FIRE "level/puck_impact.wav"
#include <gamemodes/ents>

enum MountedGun {
	MountedGun_Minigun,
	MountedGun_50Cal
}
char MountedGunClassname[2][32] = { "prop_minigun_l4d1", "prop_minigun" };
char MountedGunModel[2][64] = { "models/w_models/weapons/w_minigun.mdl", "models/w_models/weapons/50cal.mdl" };
float MOUNTED_HEAT_MIN[2] = { 0.01, 0.0 };
float MOUNTED_HEAT_INCREASE_RATE[2] = { 0.0003333333, 0.0075};
float MOUNTED_DAMAGE[2] = { 10.0, 100.0 };
float MOUNTED_FIRE_RATE[2] = { 0.0, 0.25 }; // Only can fire every value game ticks
enum struct MountedTurret {
	MountedGun type;
	int entity;
	float heat;
	int target;
	bool cooling;
	float nextFire;
	int poseParamYaw;
	int poseParamPitch;
	int poseController; //TODO: kill
}
#define MAX_MOUNTED_TURRETS 6
MountedTurret MTurret[MAX_MOUNTED_TURRETS];
int MTurretCount;
#define HEAT_DECREASE_RATE 0.01

int g_iLaserIndex;
int g_iBeamSprite;
int g_iHaloSprite;
int g_iTracerIndex;

int manualTargetter;
int g_debugTracer;
Handle thinkTimer;

ConVar cv_autoBaseDamage;
ConVar cv_manualBaseDamage;

static int COLOR_RED[4] = { 255, 0, 0, 200 };
static int COLOR_RED_LIGHT[4] = { 150, 0, 0, 150 };
int manualTarget = -1;
#define MANUAL_TARGETNAME "turret_target_manual"

ArrayList turretIds;
Handle SDKCall_LookupPoseParameter;
Handle SDKCall_LoadModel, SDKCall_DeleteModel;
int Animating_StudioHdr;

/* TODO: 
Entity_ChangeOverTime`

	acquire all turrets on plugin start, then go through list

	laser charge up 
	- yellow to red
	- thick to thin
	- sound
	--- or possibly weak damage to higher?

	on death: kill info_target? keep ref of info_target, or just find via targetname?
	
	clear all perm props (info_target, env_laser?) on round end

	dont constantly wipe info_target, just teleport

	keep data if ent is being targetted?

	dont target last ent? incase stuck

	optimize by keeping turret pos?
	
*/
public Plugin myinfo = 
{
	name =  "l4d2 turret", 
	author = "jackzmc", 
	description = "", 
	version = PLUGIN_VERSION, 
	url = "https://github.com/Jackzmc/sourcemod-plugins"
};

public void OnPluginStart() {
	EngineVersion g_Game = GetEngineVersion();
	if(g_Game != Engine_Left4Dead && g_Game != Engine_Left4Dead2) {
		SetFailState("This plugin is for L4D/L4D2 only.");	
	}

	GameData gameData = LoadGameConfigFile("l4d2_turret");
	if(!gameData) {
		LogError("Missing gamedata l4d2_turret.txt, mounted turret disabled");
	} else {
		//  = 
		StartPrepSDKCall(SDKCall_Entity); 
		// CBaseAnimating::LookupPoseParameter(CStudioHdr*, char const*)
		PrepSDKCall_SetFromConf(gameData, SDKConf_Signature, "CBaseAnimating::LookupPoseParameter"); 
		PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
		PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);  
		PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain); 
		SDKCall_LookupPoseParameter = EndPrepSDKCall();
		if(SDKCall_LookupPoseParameter == null) {
			SetFailState("Failed to load SDK call \"CBaseAnimating::LookupPoseParameter\". Update signature in \"plugin.turret\"");
		}
		
		// Taken from https://github.com/Natanel-Shitrit/StudioHdr/blob/d95e93134729361e06a0381a163de8b0b5625bc4/include/studio_hdr.inc#L4722
		// CStudioHdr *ModelSoundsCache_LoadModel( const char *filename )
		StartPrepSDKCall(SDKCall_Static);
		PrepSDKCall_SetFromConf(gameData, SDKConf_Signature, "ModelSoundsCache_LoadModel");
		PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
		PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
		if (!(SDKCall_LoadModel = EndPrepSDKCall())) {
			SetFailState("Missing signature 'ModelSoundsCache_LoadModel'");
		}
		
		// void ModelSoundsCache_FinishModel( CStudioHdr *hdr )
		StartPrepSDKCall(SDKCall_Static);
		PrepSDKCall_SetFromConf(gameData, SDKConf_Signature, "ModelSoundsCache_FinishModel");
		PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
		if (!(SDKCall_DeleteModel = EndPrepSDKCall())) {
			SetFailState("Missing signature 'ModelSoundsCache_FinishModel'");
		}

		// TODO: REMOVE
		Animating_StudioHdr = gameData.GetOffset("CBaseAnimating::StudioHdr");
		if(Animating_StudioHdr == -1)
			SetFailState("Failed to get offset: \"CBaseAnimating::StudioHdr\""); 
		int iOffset_hLightingOrigin = FindSendPropInfo("CBaseAnimating", "m_hLightingOrigin");
		if (iOffset_hLightingOrigin < 1) 
			SetFailState("Failed to find send prop: \"m_hLightingOrigin\"");
		Animating_StudioHdr += iOffset_hLightingOrigin;

		delete gameData;
	}

	turretIds = new ArrayList();

	FindTurrets();

	HookEvent("player_death", Event_PlayerDeath);
	HookEvent("tank_killed", Event_PlayerDeath);

	cv_autoBaseDamage = CreateConVar("turret_auto_damage", "50.0", "The base damage the automatic turret deals", FCVAR_NONE, true, 0.0);
	cv_manualBaseDamage = CreateConVar("turret_manual_damage", "70.0", "The base damage the manual turret deals", FCVAR_NONE, true, 0.0);

	RegAdminCmd("sm_turret", Command_SpawnTurret, ADMFLAG_CHEATS);
	RegAdminCmd("sm_rmturrets", Command_RemoveTurrets, ADMFLAG_CHEATS);
	RegAdminCmd("sm_rmlaser", Command_RemoveLaserTurret, ADMFLAG_CHEATS);
	RegAdminCmd("sm_rmturret", Command_RemoveTurret, ADMFLAG_CHEATS);
	RegAdminCmd("sm_manturret", Command_ManualTarget, ADMFLAG_CHEATS);
	RegAdminCmd("sm_turret_debug", Command_Debug, ADMFLAG_CHEATS);
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i)) {
			SDKHook(i, SDKHook_OnTakeDamageAlive, OnTakeDamageAlive);
		}
	}
}

public void OnPluginEnd() {
	ClearTurrets(false);
}

enum TurretState {
	Turret_Disabled = -1,
	Turret_Invalid = 0,
	Turret_Idle,
	Turret_Active
}

TurretState turretState[2048];
int turretActivatorParticle[2048];
int entityActiveTurret[2048]; // mapping the turret thats active on victim. [victim] = turret
int entityActiveMounted[2048];
int turretActiveEntity[2048];
int turretPhaseOffset[2048]; // slight of offset so they dont all enter the same phase at same time
bool turretIsActiveLaser[2048];
bool pendingDeletion[2048];
float turretDamage[2048];

int turretCount;

void FindTurrets() {
	int entity = -1;
	char targetname[32];
	while ((entity = FindEntityByClassname(entity, "info_particle_system")) != INVALID_ENT_REFERENCE) {
		GetEntPropString(entity, Prop_Data, "m_iName", targetname, sizeof(targetname));
		if(StrEqual(targetname, "turret")) {
			SetupLaserTurret(entity);
			PrintToServer("Found existing laser turret: %d", entity);
		}
	}
	entity = -1;
	while ((entity = FindEntityByClassname(entity, "prop_minigun")) != INVALID_ENT_REFERENCE) {
		GetEntPropString(entity, Prop_Data, "m_iName", targetname, sizeof(targetname));
		if(StrContains(targetname, "turret_") > -1)
			AddMountedGun(entity, MountedGun_50Cal);
	}
	entity = -1;
	while ((entity = FindEntityByClassname(entity, "prop_minigun_l4d1")) != INVALID_ENT_REFERENCE) {
		GetEntPropString(entity, Prop_Data, "m_iName", targetname, sizeof(targetname));
		if(StrContains(targetname, "turret_") > -1)
			AddMountedGun(entity, MountedGun_Minigun);
	}
}

int AddMountedGun(int entity, MountedGun type) {
	MTurret[MTurretCount].entity = EntIndexToEntRef(entity);
	MTurret[MTurretCount].type = type;
	MTurret[MTurretCount].target = INVALID_ENT_REFERENCE;
	MTurret[MTurretCount].heat = 0.0;
	MTurret[MTurretCount].cooling = false;
	MTurret[MTurretCount].nextFire = GetGameTime();

	char buffer[64];
	Format(buffer, sizeof(buffer), "turret_%d", entity);
	SetEntPropString(entity, Prop_Data, "m_iName", buffer);

	int poseCtrl = CreateEntityByName("point_posecontroller");
	DispatchKeyValue(poseCtrl, "PropName", buffer);
	Format(buffer, sizeof(buffer), "turret_%d_posectrl", entity);
	DispatchKeyValue(poseCtrl, "targetname", buffer);
	DispatchKeyValue(poseCtrl, "PoseParameterName", "MiniGun_Horizontal");
	DispatchKeyValue(poseCtrl, "CycleFrequency", "0");
	DispatchSpawn(poseCtrl);
	SetParent(poseCtrl, entity);
	MTurret[MTurretCount].poseController = EntIndexToEntRef(poseCtrl);

	// TODO: do on start
	// char buffer[PLATFORM_MAX_PATH];
	// GetEntPropString(entity, Prop_Data, "m_ModelName", buffer, sizeof(buffer));


	// Address pStudioHdrClass = view_as<Address>(GetEntData(entity,  0x13E0));
	// // Address pStudioHdrClass = //GetStudioHdr(buffer);
	// PrintToServer("MG%d '%s' pStudioHdrClass=%d", MTurretCount, buffer, pStudioHdrClass);
	// MTurret[MTurretCount].poseParamYaw = SDKCall(SDKCall_LookupPoseParameter, entity, pStudioHdrClass, "MiniGun_Horizontal");
	// // MTurret[MTurretCount].poseParamPitch = SDKCall(SDKCall_LookupPoseParameter, entity, pStudioHdrClass, "MiniGun_Vertical");
	PrintToServer("MG%d poseParamYaw=%d poseParamPitch=%d", MTurretCount, MTurret[MTurretCount].poseParamYaw, MTurret[MTurretCount].poseParamPitch);

	MTurretCount++;
	PrintToServer("Added mounted gun #%d (type=%d)", MTurretCount, type);
	if(thinkTimer == null) {
		PrintToServer("Created turret think timer");
		thinkTimer = CreateTimer(0.1, Timer_Think, _, TIMER_REPEAT);
	}
	return MTurretCount;
}

void RemoveMounted(int index) {
	// Shift everything from [index, MTurretCount] down
	for(int i = index; i < MTurretCount; i++) {
		if(!IsValidEntity(MTurret[i+1].entity)) {
			break;
		}
		MTurret[i].entity = MTurret[i+1].entity;
		MTurret[i].type = MTurret[i+1].type;
		MTurret[i].target = MTurret[i+1].target;
		MTurret[i].heat = MTurret[i+1].heat;
		MTurret[i].cooling = MTurret[i+1].cooling;
		MTurret[i].nextFire = MTurret[i+1].nextFire;
	}
	MTurretCount--;
}

void SetupLaserTurret(int turret, float time = 0.0) {
	float pos[3];
	GetEntPropVector(turret, Prop_Send, "m_vecOrigin", pos);
	turretState[turret] = Turret_Disabled;
	turretActivatorParticle[turret] = INVALID_ENT_REFERENCE;
	char targetName[32];
	Format(targetName, sizeof(targetName), "laser_target_%d", turret);
	CreateTimer(time, Timer_ActivateTurret, turret);
	turretCount++;
	if(thinkTimer == null) {
		PrintToServer("Created turret think timer");
		thinkTimer = CreateTimer(0.1, Timer_Think, _, TIMER_REPEAT);
	}
	// Clamp to 0 -> _TURRET_PHASE_TICKS - 1
	turretPhaseOffset[turret] = (turretIds.Length + 1) % (_TURRET_PHASE_TICKS - 1);
	turretIds.Push(turret);
}
Action Timer_ActivateTurret(Handle h, int turret) {
	turretState[turret] = Turret_Idle;
	return Plugin_Handled;
}

void DeactivateTurret(int turret) {
	int particle = EntRefToEntIndex(turretActivatorParticle[turret]);
	if(IsValidEntity(particle))
		AcceptEntityInput(particle, "Kill");
	turretActivatorParticle[turret] = INVALID_ENT_REFERENCE;
	turretState[turret] = Turret_Idle;
	turretActiveEntity[turret] = 0;
}

int ClearTurrets(bool fullClear = true) {
	turretIds.Clear();
	int entity = -1;
	int count;
	char targetname[32];
	if(fullClear) {
		while ((entity = FindEntityByClassname(entity, "info_particle_system")) != INVALID_ENT_REFERENCE) {
			GetEntPropString(entity, Prop_Data, "m_iName", targetname, sizeof(targetname));
			if(turretState[entity] != Turret_Invalid) {
				count++;
				AcceptEntityInput(entity, "Kill");
				int particle = EntRefToEntIndex(turretActivatorParticle[entity]);
				if(IsValidEntity(particle))
					AcceptEntityInput(particle, "Kill");

				turretState[entity] = Turret_Invalid;
				turretActivatorParticle[entity] = 0;
			} else if(StrEqual(targetname, "turret_activate")) {
				AcceptEntityInput(entity, "Kill");
			}
		}
		entity = -1;
		while ((entity = FindEntityByClassname(entity, "prop_minigun*")) != INVALID_ENT_REFERENCE) {
			GetEntPropString(entity, Prop_Data, "m_iName", targetname, sizeof(targetname));
			if(StrContains(targetname, "turret_") > -1) {
				RemoveEntity(entity);
				count++;
			}
		}
		MTurretCount = 0;
	}
	entity = -1;
	while ((entity = FindEntityByClassname(entity, "env_laser")) != INVALID_ENT_REFERENCE) {
		if(turretIsActiveLaser[entity]) {
			AcceptEntityInput(entity, "TurnOff");
			AcceptEntityInput(entity, "Kill");
		}
	}
	entity = -1;
	while ((entity = FindEntityByClassname(entity, "point_posecontroller")) != INVALID_ENT_REFERENCE) {
		GetEntPropString(entity, Prop_Data, "m_iName", targetname, sizeof(targetname));
		if(StrContains(targetname, "turret_") > -1) {
			RemoveEntity(entity);
		}
	}
	
	entity = -1;
	while ((entity = FindEntityByClassname(entity, "info_target")) != INVALID_ENT_REFERENCE) {
		GetEntPropString(entity, Prop_Data, "m_iName", targetname, sizeof(targetname));
		if(StrContains(targetname, "turret_target_") > -1 || StrEqual(targetname, MANUAL_TARGETNAME)) {
			RemoveEntity(entity);
		}
	}


	for(int i = 1; i < 2048; i++) {
		entityActiveTurret[i] = 0;
		entityActiveMounted[i] = 0;
		pendingDeletion[i] = false;
	}
	turretCount = 0;
	if(thinkTimer != null) {
		delete thinkTimer;
	}
	return count;
}

public void OnClientPutInServer(int client) {
	pendingDeletion[client] = false;
	SDKHook(client, SDKHook_OnTakeDamageAlive, OnTakeDamageAlive);
}

public void OnClientDisconnect(int client) {
	if(manualTargetter == client)
		manualTargetter = 0;
}

public Action OnTakeDamageAlive(int victim, int& attacker, int& inflictor, float& damage, int& damagetype) {
	// TODO: see if DMG_ENERGYBEAM
	if(attacker > MaxClients && attacker < 2048 && turretIsActiveLaser[attacker] && GetClientTeam(victim) != 3) {
		int health = L4D_GetPlayerTempHealth(victim);
		L4D_SetPlayerTempHealth(victim, health + 1.0);
		damage = 0.0;
		return Plugin_Stop;
	}
	return Plugin_Continue;
}

public void OnMapEnd() {
	manualTarget = -1;
	ClearTurrets();
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	int index = event.GetInt("entindex", 0);
	int turret = entityActiveTurret[client];
	if(turret > 0) {
		pendingDeletion[client] = true;
		turretActiveEntity[turret] = 0;
		DeactivateTurret(turret);
	}
	entityActiveTurret[index] = 0;
	entityActiveTurret[client] = 0;
	entityActiveMounted[index] = 0;
	entityActiveMounted[client] = 0;
}

public void OnEntityDestroyed(int entity) {
	if(entity > 0 && entity <= 2048) {
		pendingDeletion[entity] = false;
		int turret = entityActiveTurret[entity];
		if(turret > 0) {
			DeactivateTurret(turret);
		}
		entityActiveTurret[entity] = 0;
		entityActiveMounted[entity] = 0;
	}
}


public Action Command_SpawnTurret(int client, int args) {
	if(args == 0) {
		ReplyToCommand(client, "Usage: /mkturret <laser/minigun/50cal>");
		return Plugin_Handled;
	}
	char arg[16];
	GetCmdArg(1, arg, sizeof(arg));

	float pos[3];
	GetClientEyePosition(client, pos);
	float ang[3];
	GetClientEyeAngles(client, ang);
	ang[0] = 0.0;
	ang[2] = 0.0;
	// pos[2] += 10.0;
	if(StrEqual(arg, "laser")) {
		int base = CreateParticleNamed(ENT_PORTAL_NAME, PARTICLE_ELMOS, pos, NULL_VECTOR);
		SetupLaserTurret(base, TURRET_ACTIVATION_TIME);
		ReplyToCommand(client, "New laser turret (%d) will activate in %.0f seconds", base, TURRET_ACTIVATION_TIME);
	} else {
		GetCursorLocation(client, pos);
		MountedGun type = MountedGun_Minigun;
		if(StrEqual(arg, "minigun")) {
			type = MountedGun_Minigun;
		} else if(StrEqual(arg, "50cal", false)) {
			type = MountedGun_50Cal;
		} else {
			ReplyToCommand(client, "Unknown turret type. Usage: /mkturret <laser/minigun/50cal>");
			return Plugin_Handled;
		}
		// TODO: create minigun
		int gun = CreateEntityByName(MountedGunClassname[type]);
		DispatchKeyValue(gun, "targetname", "turret");
		DispatchKeyValue(gun, "model", MountedGunModel[type]);
		TeleportEntity(gun, pos, ang, NULL_VECTOR);
		DispatchSpawn(gun);
		AddMountedGun(gun, type);
		ReplyToCommand(client, "New mounted gun spawned.");
		return Plugin_Handled;
	}

	return Plugin_Handled;
}

public Action Command_ManualTarget(int client, int args) {
	// Remove the activator particles
	int entity = INVALID_ENT_REFERENCE;
	while ((entity = FindEntityByClassname(entity, "info_particle_system")) != INVALID_ENT_REFERENCE) {
		if(view_as<int>(turretState[entity]) > 0) {
			DeactivateTurret(entity);
		}
	}

	if(manualTargetter == client) {
		manualTargetter = 0;
		ReplyToCommand(client, "No longer manually targetting");
		return Plugin_Handled;
	} else if(manualTargetter > 0) {
		ReplyToCommand(manualTargetter, "%N is now manually targetting", client);
	}
	if(turretCount == 0) {
		ReplyToCommand(client, "There are no turrets to manually target");
	} else {
		manualTargetter = client;
		ReplyToCommand(client, "Now manually targetting");
	}
	return Plugin_Handled;
}

Action Command_RemoveTurrets(int client, int args) {
	int count = ClearTurrets(true);
	ReplyToCommand(client, "Removed %d turrets", count);
	return Plugin_Handled;
}

Action Command_Debug(int client, int args) {
	if(g_debugTracer == client) {
		g_debugTracer = 0;
		ReplyToCommand(client, "Debug mode off");
	} else {
		g_debugTracer = client;
		ReplyToCommand(client, "Debug mode on");
	}
}

Action Command_RemoveLaserTurret(int client, int args) {
	if(turretIds.Length == 0) {
		ReplyToCommand(client, "No turrets to remove");
	} else {
		int lastTurret = turretIds.Get(turretIds.Length - 1);
		ReplyToCommand(client, "Removed last turret %d", lastTurret);
	}
	return Plugin_Handled;
}

Action Command_RemoveTurret(int client, int args) {
	int target = GetClientAimTarget(client, false);
	if(target >= MaxClients) {
		int targetRef = EntIndexToEntRef(target);
		for(int i = 0; i < MTurretCount; i++) {
			if(MTurret[i].entity == targetRef) {
				RemoveMounted(i);
				ReplyToCommand(client, "Removed mounted turret #%d", i);
				return Plugin_Handled;
			}
		}
		ReplyToCommand(client, "Not a valid turret");
	} else {
		ReplyToCommand(client, "You are not looking at a turret");
	}
	return Plugin_Handled;
}


bool IsTargetValid(int targetRef) {
	if(!IsValidEntity(targetRef)) return false;
	return GetEntProp(targetRef, Prop_Data, "m_iHealth") > 0;
}

void GetAngles(const float pos[3], const float endPos[3], float angles[3]) {
	float result[3];
	MakeVectorFromPoints(endPos, pos, result);
	GetVectorAngles(result, angles);
	if(angles[0] >= 270){
		angles[0] -= 270;
		angles[0] = (90-angles[0]);
	}else{
		if(angles[0] <= 90){
			angles[0] *= -1;
		}
	}
	angles[1] -= 180;
}

void ShowTracer(float pos[3], float endPos[3]) {  
	TE_SetupParticle(g_iTracerIndex, pos, endPos);
	TE_SendToAll();
}

Address GetStudioHdr(const char[] model) {
	if (!model[0]) {
		LogError("empty model path");
	}
	// Create a new CStudioHdr variable based on the model path.
	Address CStudioHdr = SDKCall(SDKCall_LoadModel, model);
	if (!CStudioHdr) {
		return Address_Null;
	}
	// Load 'studiohdr_t *m_pStudioHdr' from 'CStudioHdr' pointer. (can be treated as if it was a studiohdr_t **)
	Address m_pStudioHdr = view_as<Address>(LoadFromAddress(CStudioHdr, NumberType_Int32));
	// Delete the CStudioHdr variable to not leak memory.
	SDKCall(SDKCall_DeleteModel, CStudioHdr);
	return m_pStudioHdr;
}

void SetPoseParameter(int entity, int iParameter, float flStart, float flEnd, float flValue)    {
	float ctlValue = (flValue - flStart) / (flEnd - flStart);
	if (ctlValue < 0) ctlValue = 0.0;
	if (ctlValue > 1) ctlValue = 1.0;
	
	SetEntPropFloat(entity, Prop_Send, "m_flPoseParameter", ctlValue, iParameter);
}


void SetPoseControllerParameter(int entity, const char[] parameter, float flStart, float flEnd, float flValue)    {
	float ctlValue = (flValue - flStart) / (flEnd - flStart);
	if (ctlValue < 0) ctlValue = 0.0;
	if (ctlValue > 1) ctlValue = 1.0;
	
	SetVariantString(parameter);
	AcceptEntityInput(entity, "SetPoseParameterName");
	SetVariantFloat(ctlValue);
	AcceptEntityInput(entity, "SetPoseValue");
	PrintToServer("SetPoseControllerParameter: ent=%d param=%s value=%f", entity, parameter, ctlValue);
}


public Action Timer_Think(Handle h) {
	if( manualTargetter > 0) return Plugin_Continue;
	// Probably better to just store from CreateParticle
	static int entity; 
	entity = -1;
	// static char targetname[32];
	static float pos[3], targetPos[3], angles[3], turretAngles[3];
	static int count, target, tick;
	for(int i = 0; i < MTurretCount; i++) {
		GetEntPropVector(MTurret[i].entity, Prop_Send, "m_vecOrigin", pos);
		GetEntPropVector(MTurret[i].entity, Prop_Send, "m_angRotation", turretAngles);
		if(!IsTargetValid(MTurret[i].target)) {
			MTurret[i].target = FindNearestVisibleEntity("infected", pos, TURRET_MAX_RANGE_INFECTED_OPTIMIZED, MTurret[i].entity);
		}

		if(MTurret[i].target > 0 && !MTurret[i].cooling) {
			// Map to a bogus value:
			entityActiveMounted[MTurret[i].target] = i;
			MTurret[i].heat += MOUNTED_HEAT_INCREASE_RATE[MTurret[i].type];
			// PrintToServer("mg%d warming - heat:%f min:%f", i, MTurret[i].heat, MOUNTED_HEAT_MIN[MTurret[i].type]);
			if(MTurret[i].heat >= 1.0) {
				MTurret[i].heat = 1.0;
				MTurret[i].cooling = true;
				SetEntProp(MTurret[i].entity, Prop_Send, "m_firing", 0);
				SetEntProp(MTurret[i].entity, Prop_Send, "m_overheated", 1);
			}
			else if(MTurret[i].heat >= MOUNTED_HEAT_MIN[MTurret[i].type] && GetGameTime() >= MTurret[i].nextFire) {
				// Can fire now
				SetEntProp(MTurret[i].entity, Prop_Send, "m_firing", 1);
				// TODO: look at
				if(MTurret[i].type == MountedGun_50Cal)
					EmitSoundToAll(SOUND_FIRE, 0,  SNDCHAN_WEAPON, SNDLEVEL_NORMAL, SND_NOFLAGS, 1.0, SNDPITCH_NORMAL, -1, pos, NULL_VECTOR, true, 0.0);
				GetEntPropVector(MTurret[i].target, Prop_Send, "m_vecOrigin", targetPos);
				targetPos[2] += 40.0; // hit infected better
				GetAngles(pos, targetPos, angles);
				float angle = 0.5 + (angles[1] - turretAngles[1]) / FLOAT_PI;
				SetPoseControllerParameter(MTurret[i].poseController, "MiniGun_Vertical", -90.0, 90.0, angle);
				angle = 0.5 + (angles[0] - turretAngles[0]) / FLOAT_PI;
				SetPoseControllerParameter(MTurret[i].poseController, "MiniGun_Horizontal", -90.0, 90.0, angle);
				// SetPoseParameter(MTurret[i].entity, 0, -90.0, 90.0, angles[0]);
				// SetPoseParameter(MTurret[i].entity, 1, -90.0, 90.0, angles[1]);
				TR_TraceRay(pos, targetPos, 0, RayType_EndPoint);
				if(TR_DidHit()) {
					// Obstacle
					TR_GetEndPosition(targetPos);
					EmitSoundToAll(SOUND_IMPACT_MISS, 0, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, 1.0, SNDPITCH_NORMAL, -1, targetPos, NULL_VECTOR, true, 0.0);
				} else {
					EmitSoundToAll(SOUND_IMPACT_HIT, 0, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, 1.0, SNDPITCH_NORMAL, -1, targetPos, NULL_VECTOR, true, 0.0);
					// TODO: improve damage
					SDKHooks_TakeDamage(MTurret[i].target, MTurret[i].entity, MTurret[i].entity, MOUNTED_DAMAGE[MTurret[i].type], DMG_BLAST);
				}
				TE_SetupTracerSound(pos, targetPos);
				TE_SendToAll();
				// Get the end of the barrel
				GetHorizontalPositionFromOrigin(pos, turretAngles, 10.0, pos);
				pos[2] += 45.0;
				ShowTracer(pos, targetPos);
				TE_SetupMuzzleFlash(pos, turretAngles, 1.0, 1);
				TE_SendToAll();
				// For now, make 50 cal swap target (for commons)
				if(MTurret[i].type == MountedGun_50Cal) {
					MTurret[i].target = INVALID_ENT_REFERENCE;
				}
				MTurret[i].nextFire = GetGameTime() + MOUNTED_FIRE_RATE[MTurret[i].type];
			}
		} else {
			MTurret[i].heat -= HEAT_DECREASE_RATE;
			SetEntProp(MTurret[i].entity, Prop_Send, "m_firing", 0);
			if(MTurret[i].heat < 0.0) {
				MTurret[i].heat = 0.0;
				MTurret[i].cooling = false;
				SetEntProp(MTurret[i].entity, Prop_Send, "m_overheated", 0);
			}
		}
		SetEntPropFloat(MTurret[i].entity, Prop_Send, "m_heat", MTurret[i].heat);
	}
	if(turretCount > 0) {
		entity = -1;
		while ((entity = FindEntityByClassname(entity, "info_particle_system")) != INVALID_ENT_REFERENCE) {
			// GetEntPropString(entity, Prop_Data, "m_iName", targetname, sizeof(targetname));
			// if(StrEqual(targetname, ENT_PORTAL_NAME)) {
			if(view_as<int>(turretState[entity]) > 0) {
				GetEntPropVector(entity, Prop_Send, "m_vecOrigin", pos);
				if(turretState[entity] == Turret_Active) {
					// Keep targetting if can view
					target = EntRefToEntIndex(turretActiveEntity[entity]);
					if(target > 0 && IsValidEntity(target)) {
						if(target <= MaxClients) {
							if(IsPlayerAlive(target) && GetEntProp(target, Prop_Data, "m_bClientSideRagdoll") == 0 && CanSeeEntity(pos, target)) {
								FireTurretAuto(pos, target, turretDamage[entity]);
								continue;
							}
						} else if(CanSeeEntity(pos, target)) {
							FireTurretAuto(pos, target, turretDamage[entity]);
							continue;
						}
					}
					DeactivateTurret(entity);
				}
				// Skip activation if a survivor is too close
				if(FindNearestClient(TEAM_SURVIVORS, pos, TURRET_MAX_RANGE_HUMANS_OPTIMIZED) > 0) {
					continue;
				}

				bool inNormalPhase = ((tick + turretPhaseOffset[entity]) % _TURRET_PHASE_TICKS) <= TURRET_NORMAL_PHASE_TICKS;

				// Find a target, in this order: Tank Rock -> Specials -> Infected
				float damage = cv_autoBaseDamage.FloatValue;
				target = -1;
				if(inNormalPhase) {
					target = FindNearestVisibleEntity("tank_rock", pos, TURRET_MAX_RANGE_SPECIALS_OPTIMIZED, entity);
					if(target > 0) {
						CreateTimer(1.2, Timer_KillRock, EntIndexToEntRef(target));
						damage = 1000.0;
					}
					if(target <= 0) target = FindNearestVisibleClient(TEAM_SPECIALS, pos, TURRET_MAX_RANGE_SPECIALS_OPTIMIZED);
				}
				if(target <= 0) target = FindNearestVisibleEntity("infected", pos, TURRET_MAX_RANGE_INFECTED_OPTIMIZED, entity); 
				if(target > 0) {
					turretDamage[entity] = damage;
					entityActiveTurret[target] = entity;
					turretActiveEntity[entity] = EntIndexToEntRef(target);
					turretActivatorParticle[entity] = EntIndexToEntRef(CreateParticleNamed("turret_activate", PARTICLE_TES1, pos, NULL_VECTOR));
					// AcceptEntityInput(turretActivatorParticle[entity], "Start");
					FireTurretAuto(pos, target, turretDamage[entity]);
					turretState[entity] = Turret_Active;
				}
				// Optimization incase there's multiple info_particle_system
				if(++count > turretCount) {
					count = 0;
					break;
				}
			}
		}
		if(++tick >= _TURRET_PHASE_TICKS) {
			tick = 0;
		}
	}
	return Plugin_Continue;
}


public Action Timer_KillRock(Handle h, int ref) {
	int rock = EntRefToEntIndex(ref);
	if(rock != INVALID_ENT_REFERENCE) {
		L4D_DetonateProjectile(rock);
	}
	return Plugin_Handled;
}

static float TURRET_LASER_COLOR[3] = { 0.0, 255.0, 255.0 };

void FireTurretAuto(const float origin[3], int targetEntity, float damage = 105.0) {
	int laser = CreateLaserAuto(origin, targetEntity, TURRET_LASER_COLOR, damage, 1.0, 0.2);
	EmitSoundToAll(SOUND_LASER_FIRE, laser, SNDCHAN_WEAPON, .flags = SND_CHANGEPITCH, .pitch = 150);
	turretIsActiveLaser[laser] = true;
}

void FireTurret(const float origin[3], const char[] targetName, float damage = 105.0, bool emitSound = true) {
	int laser = CreateLaser(origin, targetName, TURRET_LASER_COLOR, damage, 1.0, 0.1);
	if(emitSound)
		EmitSoundToAll(SOUND_LASER_FIRE, laser, SNDCHAN_WEAPON, .flags = SND_CHANGEPITCH, .pitch = 150);
	turretIsActiveLaser[laser] = true;
}

stock int CreateLaser(const float origin[3], const char[] targetName, float color[3], float damage, float width, float duration) {
	int laser = CreateEntityByName("env_laser");
	if(laser > 0) {
		DispatchKeyValue(laser, "targetname", "sm_laser");
		DispatchKeyValue(laser, "LaserTarget", targetName);
		DispatchKeyValue(laser, "spawnflags", "1");
		// DispatchKeyValue(laser, "dissolvetype", "2");
		DispatchKeyValue(laser, "NoiseAmplitude", "1");
		DispatchKeyValueFloat(laser, "damage", damage);
		DispatchKeyValueFloat(laser, "life", duration); 
		DispatchKeyValueVector(laser, "rendercolor", color);
		DispatchKeyValue(laser, "texture", "sprites/laserbeam.spr");

		TeleportEntity(laser, origin);
		SetEntPropFloat(laser, Prop_Data, "m_fWidth", width);

		DispatchSpawn(laser);

		if(duration > 0) 
			CreateTimer(duration, Timer_Kill, laser);
	}
	return laser;
}

// Creates a beam from beginTarget to endTarget. If target name starts with NUL, then will not be set. See env_beam on wiki
stock int CreateBeam(const char[] beginTarget, const float center[3], const char[] endTarget, float color[3], float damage, float width, float duration) {
	int laser = CreateEntityByName("env_beam");
	if(laser > 0) {
		DispatchKeyValue(laser, "targetname", "sm_laserbeam");
		if(beginTarget[0] != '\0')
			DispatchKeyValue(laser, "LightningStart", beginTarget);
		if(endTarget[0] != '\0')
			DispatchKeyValue(laser, "LightningEnd", endTarget);
		DispatchKeyValue(laser, "spawnflags", "1");
		// DispatchKeyValue(laser, "dissolvetype", "2");
		DispatchKeyValue(laser, "NoiseAmplitude", "1");
		DispatchKeyValueFloat(laser, "damage", damage);
		DispatchKeyValueFloat(laser, "life", duration); 
		DispatchKeyValueVector(laser, "rendercolor", color);
		DispatchKeyValue(laser, "texture", "sprites/laserbeam.spr");

		TeleportEntity(laser, center);
		DispatchKeyValueFloat(laser, "BoltWidth", width);

		DispatchSpawn(laser);

		if(duration > 0) 
			CreateTimer(duration, Timer_Kill, laser);
	}
	return laser;
}


stock int CreateLaserAuto(const float origin[3], int targetEnt, float color[3], float damage = 0.0, float width, float duration = 5.0, bool createInfoTarget = true) {
	static char targetName[32];
	Format(targetName, sizeof(targetName), "laser_target_%d", targetEnt);

	static float pos[3];
	GetEntPropVector(targetEnt, Prop_Send, "m_vecOrigin", pos);
	pos[2] += 30.0;
	int target = CreateTarget(pos, targetName, duration);
	SetParent(target, targetEnt);

	return CreateLaser(origin, targetName, color, damage, width, duration);
}

int CreateTarget(const float origin[3], const char[] targetName, float duration = 0.0) {
	int target = CreateEntityByName("info_target");
	DispatchKeyValue(target, "targetname", targetName);

	TeleportEntity(target, origin, NULL_VECTOR, NULL_VECTOR);
	DispatchSpawn(target);
	if(duration > 0.0) {
		CreateTimer(duration, Timer_Kill, target);
	}
	return target;
}


stock int FindNearestClient(int team, const float origin[3], float maxRange = 0.0) {
	int client = -1;
	float closestDist, pos[3];
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == team && !pendingDeletion[i]) {
			GetClientAbsOrigin(i, pos);
			float distance = GetVectorDistance(origin, pos, true);
			if(maxRange > 0.0 && distance > maxRange) continue;
			if(client == -1 || distance <= closestDist) {
				client = i;
				closestDist = distance;
			}
		}
	}
	return client;
}

stock int FindNearestVisibleClient(int team, const float origin[3], float maxRange = 0.0) {
	int client = -1;
	float closestDist, pos[3];
	for(int i = 1; i <= MaxClients; i++) {
		if(!pendingDeletion[i] && IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == team) {
			GetClientAbsOrigin(i, pos);
			float distance = GetVectorDistance(origin, pos, true);
			if(maxRange > 0.0 && distance > maxRange) continue;
			if(distance <= closestDist || client == -1) {
				if(CanSeePoint(origin, pos)) {
					// Priority: Pinned survivors
					if(L4D_GetPinnedSurvivor(i) > 0) {
						return i;
					}
					client = i;
					closestDist = distance;
				}
			}
		}
	}
	return client;
}

stock int FindNearVisibleEntityCone(const char[] classname, const float origin[3], const float angles[3], float maxAngles, float maxRange, int ignoreEntity) {
	int entity = -1;
	static float pos[3];
	while ((entity = FindEntityByClassname(entity, classname)) != INVALID_ENT_REFERENCE) {
		// Skip entity, it's already being targetted
		if(entityActiveTurret[entity] > 0 || entityActiveMounted[entity] > 0) continue;
		bool ragdolled = GetEntProp(entity, Prop_Data, "m_bClientSideRagdoll") == 1;
		if(ragdolled) continue;
		GetEntPropVector(entity, Prop_Send, "m_vecOrigin", pos);
		if(maxRange > 0.0 && GetVectorDistance(origin, pos, true) > maxRange) continue;
		pos[2] += 40.0;
		// TODO: fail if the computed angles to reach 'pos' are > angles + maxAngles
		if(CanSeePoint(origin, pos, ignoreEntity)) {
			return entity;
		}
		return entity;
	}
	return -1;
}

stock int FindNearestVisibleEntity(const char[] classname, const float origin[3], float maxRange = 0.0, int ignoreEntity = 0) {
	int entity = -1;
	static float pos[3];
	while ((entity = FindEntityByClassname(entity, classname)) != INVALID_ENT_REFERENCE) {
		// Skip entity, it's already being targetted
		if(entityActiveTurret[entity] > 0 || entityActiveMounted[entity] > 0) continue;
		bool ragdolled = GetEntProp(entity, Prop_Data, "m_bClientSideRagdoll") == 1;
		if(ragdolled) continue;
		GetEntPropVector(entity, Prop_Send, "m_vecOrigin", pos);
		if(maxRange > 0.0 && GetVectorDistance(origin, pos, true) > maxRange) continue;
		pos[2] += 40.0;
		if(CanSeePoint(origin, pos, ignoreEntity)) {
			return entity;
		}
		return entity;
	}
	return -1;
}

stock bool CanSeePoint(const float origin[3], const float point[3], int ignoreEntity = 0) {
	TR_TraceRayFilter(origin, point, MASK_SHOT, RayType_EndPoint, Filter_CanSeeEntity, ignoreEntity);
	
	return !TR_DidHit(); // Can see point if no collisions
}

stock bool CanSeeEntity(const float origin[3], int entity) {
	static float point[3];
	GetEntPropVector(entity, Prop_Send, "m_vecOrigin", point);
	TR_TraceRayFilter(origin, point, MASK_SHOT, RayType_EndPoint, Filter_CanSeeEntity, entity);

	return TR_GetEntityIndex() == entity; // Can see point if no collisions
}

bool Filter_CanSeeEntity(int entity, int contentsMask, int data) {
	return entity != data;
}

bool Filter_IgnoreEntityWorld(int entity, int contentsMask, int data) {
	return entity != data && entity != 0;
}


public void OnMapStart() {
	PrecacheParticle(PARTICLE_ELMOS);
	PrecacheParticle(PARTICLE_TES1);
	g_iTracerIndex = GetParticleIndex(PARTICLE_WEAPON_TRACER);
	g_iBeamSprite = PrecacheModel("sprites/laser.vmt", true);
	g_iLaserIndex = PrecacheModel("materials/sprites/laserbeam.vmt", true);
	PrecacheSound(SOUND_LASER_FIRE);
	PrecacheSound(SOUND_FIRE);
	PrecacheSound(SOUND_IMPACT_HIT);	
	PrecacheSound(SOUND_IMPACT_MISS);
	PrecacheModel(MountedGunModel[0]);
	PrecacheModel(MountedGunModel[1]);
	if(g_iLaserIndex == 0) {
		LogError("g_iLaserIndex failed");
	}
}


stock int CreateParticleNamed(const char[] targetname, const char[] sParticle, const float vPos[3], const float vAng[3], int parent = 0) {
	int entity = CreateEntityByName("info_particle_system");
	if( entity != -1 ) {
		DispatchKeyValue(entity, "effect_name", sParticle);
		DispatchKeyValue(entity, "targetname", targetname);
		DispatchSpawn(entity);
		ActivateEntity(entity);
		AcceptEntityInput(entity, "start");

		if(parent){
			SetParent(entity, parent);
		}

		TeleportEntity(entity, vPos, vAng, NULL_VECTOR);

		// Refire
		float refire = 0.2;
		static char sTemp[64];
		Format(sTemp, sizeof(sTemp), "OnUser1 !self:Stop::%f:-1", refire - 0.05);
		SetVariantString(sTemp);
		AcceptEntityInput(entity, "AddOutput");
		Format(sTemp, sizeof(sTemp), "OnUser1 !self:FireUser2::%f:-1", refire);
		SetVariantString(sTemp);
		AcceptEntityInput(entity, "AddOutput");
		AcceptEntityInput(entity, "FireUser1");

		SetVariantString("OnUser2 !self:Start::0:-1");
		AcceptEntityInput(entity, "AddOutput");
		SetVariantString("OnUser2 !self:FireUser1::0:-1");
		AcceptEntityInput(entity, "AddOutput");

		return entity;
	}
	return -1;
}
/*#define MAX_IGNORE_TRACE 2
static char IGNORE_TRACE[MAX_IGNORE_TRACE][] = {
	"env_physics_blocker",
	"env_player_blocker"
};*/
#define MAX_WHITELISTED_AUTO_AIM_TARGETS 3
static char WHITELISTED_AUTO_AIM_TARGETS[MAX_WHITELISTED_AUTO_AIM_TARGETS][] = {
	"tank_rock",
	"infected",
	"witch"
};


bool Filter_ManualTarget(int entity, int contentsMask, int data) {
	if(entity == 0 || entity == data) return true;
	if(entity == manualTarget || entity == manualTargetter) return false;
	return true;
	/*static char classname[32];
	GetEntityClassname(entity, classname, sizeof(classname));
	for(int i = 0; i < MAX_IGNORE_TRACE; i++) {
		if(StrEqual(IGNORE_TRACE[i], classname)) {
			return false;
		}
	}
	return true;*/
}

bool Filter_ManualTargetSights(int entity, int contentsMask, int data) {
	if(entity == 0 || entity == data) return true;
	if(entity == manualTarget || entity == manualTargetter) return false;
	if(entity <= MaxClients) return GetClientTeam(entity) == 3;
	static char classname[32];
	GetEntityClassname(entity, classname, sizeof(classname));
	for(int i = 0; i < MAX_WHITELISTED_AUTO_AIM_TARGETS; i++) {
		if(StrEqual(WHITELISTED_AUTO_AIM_TARGETS[i], classname)) {
			return false;
		}
	}
	return true;
}

float HULL_DEBUG_MIN[3] = { -50.0, -50.0, -20.0 };
float HULL_DEBUG_MAX[3] = { 50.0, 50.0, 20.0 };

bool DebugEnumerator(int entity, int data) { 
	if(entity == 0 || entity == data) return false;
	GlowEntity(entity, 3.0);
	return false;
}

public Action OnPlayerRunCmd(int client, int& buttons, int& impulse, float vel[3], float angles[3], int& weapon, int& subtype, int& cmdnum, int& tickcount, int& seed, int mouse[2]) {
	if(client == g_debugTracer) {
		float pos[3];
		float ang[3];
		GetClientEyePosition(client, pos);
		GetClientEyeAngles(client, ang);
		TR_EnumerateEntitiesSphere(pos, 100.0, PARTITION_NON_STATIC_EDICTS, DebugEnumerator, client);
		// TR_TraceHullFilter(pos, ang, HULL_DEBUG_MIN, HULL_DEBUG_MAX, MASK_SOLID, Filter_IgnoreEntityWorld, client);
		// if(TR_DidHit()) {
		// 	TR_GetEndPosition(pos);

		// 	// TODO: use enumerator
		// 	int ent = TR_GetEntityIndex();
		// 	PrintCenterText(client, "HIT %d - %.0f %.0f %.0f", ent, pos[0], pos[1], pos[2]);
		// 	if(ent > 0) {
		// 		GlowEntity(ent, 3.0);
		// 	}
		// } else {
		// 	PrintCenterText(client, "MISS");
		// }
	}
	if(client == manualTargetter && turretCount > 0 && tickcount % 3 == 0) {
		static float pos[3], aimPos[3], orgPos[3];
		GetClientEyePosition(client, orgPos);

		// Run a ray trace to find a suitable position
		// TODO: Possibly run per-turret for more accurate preview... but it's already lag fest
		TR_TraceRayFilter(orgPos, angles, MASK_SHOT, RayType_Infinite, Filter_ManualTarget);
		if(manualTarget <= 0 || !IsValidEntity(manualTarget)) manualTarget = CreateTarget(aimPos, MANUAL_TARGETNAME);

		// Disable aim snapping if player is holding WALK (which is apparently IN_SPEED)
		bool aimSnapping = ~buttons & IN_SPEED > 0;
		int targetEntity = TR_GetEntityIndex();
		TR_GetEndPosition(aimPos);

		if(aimSnapping)
			ComputeAutoAim(targetEntity, aimPos);
		
		TeleportEntity(manualTarget, aimPos, NULL_VECTOR, NULL_VECTOR);

		if(buttons & IN_ATTACK) {
			PhysicsExplode(aimPos, 20, 20.0, true);
			TE_SetupExplodeForce(aimPos, 20.0, 20.0);
		}

		// Activate all turrets
		int entity = INVALID_ENT_REFERENCE;
		while ((entity = FindEntityByClassname(entity, "info_particle_system")) != INVALID_ENT_REFERENCE) {
			if(view_as<int>(turretState[entity]) > 0) {
				GetEntPropVector(entity, Prop_Send, "m_vecOrigin", orgPos);
				if(buttons & IN_ATTACK) {
					FireTurret(orgPos, MANUAL_TARGETNAME, cv_manualBaseDamage.FloatValue, tickcount % 6 == 0);
				} else {
					TR_TraceRayFilter(orgPos, aimPos, MASK_SOLID, RayType_EndPoint, Filter_ManualTargetSights, targetEntity);
					pos = aimPos;
					if(TR_DidHit()) {
						TR_GetEndPosition(pos);
						TE_SetupBeamPoints(orgPos, pos, g_iLaserIndex, 0, 0, 1, 0.1, 0.1, 0.1, 0, 0.0, COLOR_RED_LIGHT, 1);
					} else {
						TE_SetupBeamPoints(orgPos, aimPos, g_iLaserIndex, 0, 0, 1, 0.1, 0.1, 0.1, 0, 0.0, COLOR_RED, 2);
					}
					// if(aimSnapping) ComputeAutoAim(TR_GetEntityIndex(), pos);
					TE_SendToAll();
				}
			}
		}

		buttons &= ~IN_ATTACK;
		SetEntPropFloat(client, Prop_Send, "m_flNextAttack", GetGameTime() + 1.0);
		return Plugin_Changed;
	}
	return Plugin_Continue;
}

bool ComputeAutoAim(int possibleTarget, float pos[3]) {

	static char classname[64];

	if(possibleTarget > 0) {
		if(possibleTarget > MaxClients) {
			// Check if aimed non-player entity is an entity to be auto aimed at 
			GetEntityClassname(possibleTarget, classname, sizeof(classname));
			for(int i = 0; i < MAX_WHITELISTED_AUTO_AIM_TARGETS; i++) {
				if(StrEqual(WHITELISTED_AUTO_AIM_TARGETS[i], classname)) {
					GetEntPropVector(possibleTarget, Prop_Send, "m_vecOrigin", pos);
					pos[2] += 40.0;
					return true;
				}
			}
		} else if(GetClientTeam(possibleTarget) == 3) {
			// Target is an infected player, auto aim
			GetClientEyePosition(possibleTarget, pos);
			pos[2] -= 15.0;
			return true;
		}
	}
	return false;
}

public Action Timer_Kill(Handle h, int target) {
	if(IsValidEntity(target)) // TODO: See if necessary
		AcceptEntityInput(target, "Kill");
	return Plugin_Handled;
}

