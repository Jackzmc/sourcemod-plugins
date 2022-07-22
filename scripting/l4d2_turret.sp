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

#define PLUGIN_VERSION "1.0"

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <left4dhooks>
// #include <profiler>


#define PARTICLE_ELMOS			"st_elmos_fire_cp0"
#define PARTICLE_TES1			"electrical_arc_01_system"
#define ENT_PORTAL_NAME "turret"
#define SOUND_LASER_FIRE "custom/xen_teleport.mp3"
#define TEAM_SPECIALS 3
#define TEAM_SURVIVORS 2
// #define SOUND_LASER_FIRE "level/puck_impact.wav"
#include <gamemodes/ents>

int g_iLaserIndex;
int g_iBeamSprite;
int g_iHaloSprite;

int manualTargetter;


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

	FindTurrets();

	HookEvent("player_death", Event_PlayerDeath);

	RegAdminCmd("sm_turret", Command_SpawnTurret, ADMFLAG_CHEATS);
	RegAdminCmd("sm_rmturrets", Command_RemoveTurrets, ADMFLAG_CHEATS);
	RegAdminCmd("sm_rmturret", Command_RemoveTurrets, ADMFLAG_CHEATS);
	RegAdminCmd("sm_manturret", Command_ManualTarget, ADMFLAG_CHEATS);
	CreateTimer(0.1, Timer_Think, _, TIMER_REPEAT);
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
int turretActiveEntity[2048];
bool turretIsActiveLaser[2048];
bool pendingDeletion[2048];
float turretDamage[2048];

int turretCount;

void FindTurrets() {
	int entity = INVALID_ENT_REFERENCE;
	char targetname[32];
	while ((entity = FindEntityByClassname(entity, "info_particle_system")) != INVALID_ENT_REFERENCE) {
		GetEntPropString(entity, Prop_Data, "m_iName", targetname, sizeof(targetname));
		if(StrEqual(targetname, "turret")) {
			SetupTurret(entity);
			PrintToServer("Found existing turret: %d", entity);
		}
	}
}

void SetupTurret(int turret, float time = 0.0) {
	float pos[3];
	GetEntPropVector(turret, Prop_Send, "m_vecOrigin", pos);
	turretState[turret] = Turret_Disabled;
	turretActivatorParticle[turret] = INVALID_ENT_REFERENCE;
	char targetName[32];
	Format(targetName, sizeof(targetName), "laser_target_%d", turret);
	CreateTimer(time, Timer_ActivateTurret, turret);
	turretCount++;
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
	int entity = INVALID_ENT_REFERENCE;
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
		entity = INVALID_ENT_REFERENCE;
	}
	while ((entity = FindEntityByClassname(entity, "env_laser")) != INVALID_ENT_REFERENCE) {
		if(turretIsActiveLaser[entity]) {
			AcceptEntityInput(entity, "TurnOff");
			AcceptEntityInput(entity, "Kill");
		}
	}
	entity = INVALID_ENT_REFERENCE;
	while ((entity = FindEntityByClassname(entity, "info_target")) != INVALID_ENT_REFERENCE) {
		GetEntPropString(entity, Prop_Data, "m_iName", targetname, sizeof(targetname));
		if(StrContains(targetname, "turret_target_") > -1) {
			AcceptEntityInput(entity, "Kill");
		}
	}

	for(int i = 1; i < 2048; i++) {
		entityActiveTurret[i] = 0;
		pendingDeletion[i] = false;
	}
	turretCount = 0;
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
	if(attacker > MaxClients && attacker < 2048 && turretIsActiveLaser[attacker] && GetClientTeam(victim) != 3) {
		int health = L4D_GetPlayerTempHealth(victim);
		L4D_SetPlayerTempHealth(victim, health);
		damage = 0.0;
		return Plugin_Stop;
	}
	return Plugin_Continue;
}

public void OnMapEnd() {
	ClearTurrets();
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	int index = event.GetInt("entindex");
	int turret = entityActiveTurret[client];
	if(turret > 0) {
		pendingDeletion[client] = true;
		DeactivateTurret(turret);
	}
	entityActiveTurret[index] = 0;
	entityActiveTurret[client] = 0;
}

public void OnEntityDestroyed(int entity) {
	if(entity > 0 && entity <= 2048) {
		pendingDeletion[entity] = false;
		int turret = entityActiveTurret[entity];
		if(turret > 0) {
			DeactivateTurret(turret);
		}
		entityActiveTurret[entity] = 0;
	}
}


public Action Command_SpawnTurret(int client, int args) {
	float pos[3];
	GetClientEyePosition(client, pos);
	pos[2] += 20.0;
	int base = CreateParticleNamed(ENT_PORTAL_NAME, PARTICLE_ELMOS, pos, NULL_VECTOR);
	SetupTurret(base, TURRET_ACTIVATION_TIME);
	ReplyToCommand(client, "New turret (%d) will activate in %.0f seconds", base, TURRET_ACTIVATION_TIME);
	return Plugin_Handled;
}

public Action Command_ManualTarget(int client, int args) {
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

public Action Command_RemoveTurrets(int client, int args) {
	int count = ClearTurrets();
	/*int entity = INVALID_ENT_REFERENCE;
	char targetname[32];
	int count;
	while ((entity = FindEntityByClassname(entity, "info_particle_system")) != INVALID_ENT_REFERENCE) {
		GetEntPropString(entity, Prop_Data, "m_iName", targetname, sizeof(targetname));
		if(StrEqual(targetname, ENT_PORTAL_NAME)) {
			AcceptEntityInput(entity, "Kill");
			count++;
		} else if(StrEqual(targetname, "turret_activate")) {
			AcceptEntityInput(entity, "Kill");
		}
	}*/
	ReplyToCommand(client, "Removed %d turrets", count);
	return Plugin_Handled;
}

public Action Timer_Think(Handle h) {
	if(turretCount == 0 || manualTargetter > 0) return Plugin_Continue;
	// Probably better to just store from CreateParticle
	static int entity = INVALID_ENT_REFERENCE;
	// static char targetname[32];
	static float pos[3];
	static int count, target;

	while ((entity = FindEntityByClassname(entity, "info_particle_system")) != INVALID_ENT_REFERENCE) {
		// GetEntPropString(entity, Prop_Data, "m_iName", targetname, sizeof(targetname));
		// if(StrEqual(targetname, ENT_PORTAL_NAME)) {
		if(view_as<int>(turretState[entity]) > 0) {
			GetEntPropVector(entity, Prop_Send, "m_vecOrigin", pos);
			if(turretState[entity] == Turret_Active) {
				// Keep targetting if can view
				target = EntRefToEntIndex(turretActiveEntity[entity]);
				if(target > 0 && IsValidEntity(target)) {
					bool ragdoll = GetEntProp(target, Prop_Data, "m_bClientSideRagdoll") == 1;
					if(!ragdoll && CanSeeEntity(pos, target)) {
						FireTurretAuto(pos, target, turretDamage[entity]);
						continue;
					}
					entityActiveTurret[target] = 0;
				}
				DeactivateTurret(entity);
				turretState[entity] = Turret_Idle;
			}
			// Skip activation if a survivor is too close
			if(FindNearestClient(TEAM_SURVIVORS, pos, TURRET_MAX_RANGE_HUMANS_OPTIMIZED) > 0) {
				continue;
			}

			float damage = 100.0;
			target = FindNearestVisibleEntity("tank_rock", pos, TURRET_MAX_RANGE_SPECIALS_OPTIMIZED, entity);
			if(target > 0) damage = 1000.0;
			if(target == -1) target = FindNearestVisibleClient(TEAM_SPECIALS, pos, TURRET_MAX_RANGE_SPECIALS_OPTIMIZED);
			if(target == -1) target = FindNearestVisibleEntity("infected", pos, TURRET_MAX_RANGE_INFECTED_OPTIMIZED, entity); 
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
	

	return Plugin_Continue;
}

static float TURRET_LASER_COLOR[3] = { 0.0, 255.0, 255.0 };

void FireTurretAuto(const float origin[3], int targetEntity, float damage = 105.0) {
	int laser = CreateLaserAuto(origin, targetEntity, TURRET_LASER_COLOR, damage, 1.0, 0.2);
	EmitSoundToAll(SOUND_LASER_FIRE, laser, SNDCHAN_WEAPON, .flags = SND_CHANGEPITCH, .pitch = 150);
	turretIsActiveLaser[laser] = true;
}

void FireTurret(const float origin[3], const char[] targetName, float damage = 105.0, bool emitSound = true) {
	int laser = CreateLaser(origin, targetName, TURRET_LASER_COLOR, damage, 1.0, 0.2);
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
		DispatchKeyValue(laser, "dissolvetype", "2");
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
		DispatchKeyValue(laser, "dissolvetype", "2");
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
	pos[2] += 40.0;
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
		if(IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == team && !pendingDeletion[i]) {
			GetClientAbsOrigin(i, pos);
			float distance = GetVectorDistance(origin, pos, true);
			if(maxRange > 0.0 && distance > maxRange) continue;
			if(client == -1 || distance <= closestDist) {
				if(CanSeePoint(origin, pos)) {
					client = i;
					closestDist = distance;
				}
			}
		}
	}
	return client;
}

stock int FindNearestVisibleEntity(const char[] classname, const float origin[3], float maxRange = 0.0, int turretIndex) {
	int entity = INVALID_ENT_REFERENCE;
	static float pos[3];
	while ((entity = FindEntityByClassname(entity, classname)) != INVALID_ENT_REFERENCE) {
		if(entityActiveTurret[entity] > 0) continue;
		bool ragdoll = GetEntProp(entity, Prop_Data, "m_bClientSideRagdoll") == 1;
		if(ragdoll) continue;
		// if(GetEntProp(entity, Prop_Send, "m_iHealth") <= 0) continue;
		GetEntPropVector(entity, Prop_Send, "m_vecOrigin", pos);
		if(maxRange > 0.0 && GetVectorDistance(origin, pos, true) > maxRange) continue;
		pos[2] += 40.0;
		if(CanSeePoint(origin, pos)) {
			return entity;
		}
	}
	return -1;
}

stock bool CanSeePoint(const float origin[3], const float point[3]) {
	TR_TraceRay(origin, point, MASK_ALL, RayType_EndPoint);
	
	return !TR_DidHit(); // Can see point if no collisions
}

stock bool CanSeeEntity(const float origin[3], int entity) {
	static float point[3];
	GetEntPropVector(entity, Prop_Send, "m_vecOrigin", point);
	TR_TraceRayFilter(origin, point, MASK_ALL, RayType_EndPoint, Filter_CanSeeEntity, entity);

	return TR_GetEntityIndex() == entity; // Can see point if no collisions
}

bool Filter_CanSeeEntity(int entity, int contentsMask, int data) {
	return entity != data;
}


public void OnMapStart() {
	PrecacheParticle(PARTICLE_ELMOS);
	PrecacheParticle(PARTICLE_TES1);
	g_iBeamSprite = PrecacheModel("sprites/laser.vmt", true);
	g_iLaserIndex = PrecacheModel("materials/sprites/laserbeam.vmt", true);
	PrecacheSound(SOUND_LASER_FIRE);
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

stock void SetParent(int child, int parent) {
	SetVariantString("!activator");
	AcceptEntityInput(child, "SetParent", parent);
}

/*#define MAX_IGNORE_TRACE 2
static char IGNORE_TRACE[MAX_IGNORE_TRACE][] = {
	"env_physics_blocker",
	"env_player_blocker"
};*/

static int COLOR_RED[4] = { 255, 0, 0, 200 };
int manualTarget = -1;
#define MANUAL_TARGETNAME "turret_target_manual"

bool Filter_ManualTarget(int entity, int contentsMask) {
	if(entity == 0) return true;
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

#define MAX_WHITELISTED_AUTO_AIM_TARGETS 2
static char WHITELISTED_AUTO_AIM_TARGETS[MAX_WHITELISTED_AUTO_AIM_TARGETS][] = {
	"infected",
	"witch"
};


public Action OnPlayerRunCmd(int client, int& buttons, int& impulse, float vel[3], float angles[3], int& weapon, int& subtype, int& cmdnum, int& tickcount, int& seed, int mouse[2]) {
	if(client == manualTargetter && turretCount > 0) {
		static float pos[3], ang[3];
		static char classname[32];
		GetClientEyePosition(client, pos);
		GetClientEyeAngles(client, ang);

		// Run a ray trace to find a suitable position
		// TODO: Possibly run per-turret for more accurate preview
		TR_TraceRayFilter(pos, ang, MASK_SHOT, RayType_Infinite, Filter_ManualTarget);
		if(!IsValidEntity(manualTarget)) manualTarget = CreateTarget(ang, MANUAL_TARGETNAME);
		// Disable aim snapping if player is holding WALK (which is apparently IN_SPEED)
		bool aimSnapping = ~buttons & IN_SPEED > 0;
		int targetEntity = TR_GetEntityIndex();
		TR_GetEndPosition(ang);

		if(aimSnapping && targetEntity > 0) {
			if(targetEntity > MaxClients) {
				// Check if aimed non-player entity is an entity to be auto aimed at 
				GetEntityClassname(targetEntity, classname, sizeof(classname));
				for(int i = 0; i < MAX_WHITELISTED_AUTO_AIM_TARGETS; i++) {
					if(StrEqual(WHITELISTED_AUTO_AIM_TARGETS[i], classname)) {
						GetEntPropVector(targetEntity, Prop_Send, "m_vecOrigin", ang);
						ang[2] += 40.0;
						break;
					}
				}
			} else if(GetClientTeam(targetEntity) == 3) {
				// Target is an infected player, auto aim
				GetClientEyePosition(targetEntity, ang);
				ang[2] -= 10.0;
			}
		}
		TeleportEntity(manualTarget, ang, NULL_VECTOR, NULL_VECTOR);

		if(buttons & IN_ATTACK) {
			PhysicsExplode(ang, 100, 20.0, true);
			TE_SetupExplodeForce(ang, 20.0, 10.0);
		}

		// Activate all turrets
		int entity = INVALID_ENT_REFERENCE;
		while ((entity = FindEntityByClassname(entity, "info_particle_system")) != INVALID_ENT_REFERENCE) {
			if(view_as<int>(turretState[entity]) > 0) {
				GetEntPropVector(entity, Prop_Send, "m_vecOrigin", pos);
				TE_SetupBeamPoints(pos, ang, g_iLaserIndex, 0, 0, 1, 0.1, 0.1, 0.1, 0, 0.0, COLOR_RED, 1);
				TE_SendToAll();
				if(buttons & IN_ATTACK) {
					FireTurret(pos, MANUAL_TARGETNAME, 50.0, tickcount % 10 > 0);
				}
			}
		}

		buttons &= ~IN_ATTACK;
		SetEntPropFloat(client, Prop_Send, "m_flNextAttack", GetGameTime() + 1.0);
		return Plugin_Changed;
	}
	return Plugin_Continue;
}

public Action Timer_Kill(Handle h, int target) {
	if(IsValidEntity(target))
		AcceptEntityInput(target, "Kill");
	return Plugin_Handled;
}

stock void GetHorizontalPositionFromOrigin(const float pos[3], const float ang[3], float units, float finalPosition[3]) {
	float theta = DegToRad(ang[1]);
	finalPosition[0] = units * Cosine(theta) + pos[0];
	finalPosition[1] = units * Sine(theta) + pos[1];
	finalPosition[2] = pos[2];
}