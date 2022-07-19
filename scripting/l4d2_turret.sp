#pragma semicolon 1
#pragma newdecls required

//#define DEBUG

#define TURRET_MAX_RANGE_SPECIALS 1700.0 // Max range of specials (including tanks, not witches)
#define TURRET_MAX_RANGE_INFECTED 1500.0 // Max range of infected commons

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
// #define SOUND_LASER_FIRE "level/puck_impact.wav"
#include <gamemodes/ents>

int g_iLaserIndex;
int g_iBeamSprite;
int g_iHaloSprite;


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
	CreateTimer(0.1, Timer_Think, _, TIMER_REPEAT);
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i)) {
			SDKHook(i, SDKHook_OnTakeDamageAlive, OnTakeDamageAlive);
		}
	}
}

public void OnPluginEnd() {
	OnMapEnd();
}

enum TurretState {
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

void SetupTurret(int turret) {
	float pos[3];
	GetEntPropVector(turret, Prop_Send, "m_vecOrigin", pos);
	turretState[turret] = Turret_Idle;
	turretActivatorParticle[turret] = INVALID_ENT_REFERENCE;
	char targetName[32];
	Format(targetName, sizeof(targetName), "laser_target_%d", turret);


	turretCount++;
}

void DeactivateTurret(int turret) {
	int particle = EntRefToEntIndex(turretActivatorParticle[turret]);
	if(IsValidEntity(particle))
		AcceptEntityInput(particle, "Kill");
	turretActivatorParticle[turret] = INVALID_ENT_REFERENCE;
	turretState[turret] = Turret_Idle;
	turretActiveEntity[turret] = 0;
}

int ClearTurrets() {
	int entity = INVALID_ENT_REFERENCE;
	int count;
	char targetname[32];
	while ((entity = FindEntityByClassname(entity, "info_particle_system")) != INVALID_ENT_REFERENCE) {
		GetEntPropString(entity, Prop_Data, "m_iName", targetname, sizeof(targetname));
		if(view_as<int>(turretState[entity]) > 0) {
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
	while ((entity = FindEntityByClassname(entity, "env_laser")) != INVALID_ENT_REFERENCE) {
		if(turretIsActiveLaser[entity]) {
			AcceptEntityInput(entity, "TurnOff");
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
	SDKHook(client, SDKHook_OnTakeDamageAlive, OnTakeDamageAlive);
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

/*public void OnPluginEnd() {
	int entity = INVALID_ENT_REFERENCE;
	char targetname[32];
	while ((entity = FindEntityByClassname(entity, "info_particle_system")) != INVALID_ENT_REFERENCE) {
		GetEntPropString(entity, Prop_Data, "m_iName", targetname, sizeof(targetname));
		if(isTurret[entity]) {
			AcceptEntityInput(entity, "Kill");
			if(IsValidEntity(turretInfoTarget[turret])) {
				AcceptEntityInput(turretInfoTarget[turret], "Kill"); 
			}
		}
		if(StrEqual(targetname, "turret_activate")) {
			AcceptEntityInput(entity, "Kill");
		}
	}
	entity = INVALID_ENT_REFERENCE;
	while ((entity = FindEntityByClassname(entity, "env_laser")) != INVALID_ENT_REFERENCE) {
		GetEntPropString(entity, Prop_Data, "m_iName", targetname, sizeof(targetname));
		if(StrContains(targetname, "sm_laser") > -1) {
			AcceptEntityInput(entity, "Kill");
		}
	}
	entity = INVALID_ENT_REFERENCE;
	while ((entity = FindEntityByClassname(entity, "info_target")) != INVALID_ENT_REFERENCE) {
		GetEntPropString(entity, Prop_Data, "m_iName", targetname, sizeof(targetname));
		if(StrContains(targetname, "sm_laser") > -1) {
			AcceptEntityInput(entity, "Kill");
		}
	}
}*/

public Action Command_SpawnTurret(int client, int args) {
	float pos[3];
	GetClientEyePosition(client, pos);
	int base = CreateParticleNamed(ENT_PORTAL_NAME, PARTICLE_ELMOS, pos, NULL_VECTOR);
	SetupTurret(base);
	ReplyToCommand(client, "Created turret");
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
	if(turretCount == 0) return Plugin_Continue;
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
						FireTurret(pos, target, turretDamage[entity]);
						continue;
					}
					entityActiveTurret[target] = 0;
				}
				DeactivateTurret(entity);
				turretState[entity] = Turret_Idle;
			}
			/*int particle = EntRefToEntIndex(turretActivatorParticle[entity]);
			if(IsValidEntity(particle)) {
				AcceptEntityInput(particle, "Kill");
				turretActivatorParticle[entity] = 0;
			}*/

			float damage = 100.0;
			target = FindNearestVisibleEntity("tank_rock", pos, TURRET_MAX_RANGE_SPECIALS_OPTIMIZED, entity);
			if(target > 0) damage = 1000.0;
			if(target == -1) target = FindNearestVisibleSpecial(pos, TURRET_MAX_RANGE_SPECIALS_OPTIMIZED);
			if(target == -1) target = FindNearestVisibleEntity("infected", pos, TURRET_MAX_RANGE_INFECTED_OPTIMIZED, entity); 
			if(target > 0) {
				turretDamage[entity] = damage;
				entityActiveTurret[target] = entity;
				turretActiveEntity[entity] = EntIndexToEntRef(target);
				turretActivatorParticle[entity] = EntIndexToEntRef(CreateParticleNamed("turret_activate", PARTICLE_TES1, pos, NULL_VECTOR));
				// AcceptEntityInput(turretActivatorParticle[entity], "Start");
				FireTurret(pos, target, turretDamage[entity]);
				turretState[entity] = Turret_Active;
			}
			if(++count > turretCount) {
				count = 0;
				break;
			}
		}
	}
	

	return Plugin_Continue;
}

static float TURRET_LASER_COLOR[3] = { 0.0, 255.0, 255.0 };

void FireTurret(const float origin[3], int target, float damage = 105.0) {
	int laser = CreateLaser(origin, target, TURRET_LASER_COLOR, damage, 1.0, 0.2);
	EmitSoundToAll(SOUND_LASER_FIRE, laser, SNDCHAN_WEAPON, .flags = SND_CHANGEPITCH, .pitch = 150);
	turretIsActiveLaser[laser] = true;
}

stock int CreateLaser(const float origin[3], int targetEnt, float color[3], float damage = 0.0, float width, float duration = 5.0) {
	int laser = CreateEntityByName("env_laser");
	DataPack pack;
	CreateDataTimer(duration, Timer_ClearEnts, pack);
	if(laser > 0) {
		DispatchKeyValue(laser, "targetname", "sm_laser");

		static char targetName[32];
		Format(targetName, sizeof(targetName), "laser_target_%d", targetEnt);

		static float pos[3];
		GetEntPropVector(targetEnt, Prop_Send, "m_vecOrigin", pos);
		pos[2] += 40.0;
		int target = CreateTarget(pos, targetName);
		SetParent(target, targetEnt);
		pack.WriteCell(target);

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

		pack.WriteCell(laser);
	}
	return laser;
}

int CreateTarget(const float origin[3], const char[] targetName) {
	int target = CreateEntityByName("info_target");
	DispatchKeyValue(target, "targetname", targetName);

	TeleportEntity(target, origin, NULL_VECTOR, NULL_VECTOR);
	DispatchSpawn(target);
	return target;
}

public Action Timer_ClearEnts(Handle h, DataPack pack) {
	pack.Reset();
	while(pack.IsReadable()) {
		int ent = pack.ReadCell();
		if(IsValidEntity(ent)) {
			AcceptEntityInput(ent, "Kill");
		}
		turretIsActiveLaser[ent] = false;
	}
	return Plugin_Handled;
}

public void SetEntitySelfDestruct(int entity, float duration) {
	char output[64]; 
	Format(output, sizeof(output), "OnUser1 !self:kill::%.1f:1", duration);
	SetVariantString(output);
	AcceptEntityInput(entity, "AddOutput"); 
	AcceptEntityInput(entity, "FireUser1");
}

stock int FindNearestSurvivor(const float origin[3], float maxRange = 0.0) {
	int client = -1;
	float closestDist, pos[3];
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i)) {
			GetClientAbsOrigin(i, pos);
			float distance = GetVectorDistance(origin, pos);
			if(maxRange > 0.0 && distance > maxRange) continue;
			if(client == -1 || distance <= closestDist) {
				client = i;
				closestDist = distance;
			}
		}
	}
	return client;
}

stock int FindNearestSpecial(const float origin[3], float maxRange = 0.0) {
	int client = -1;
	float closestDist, pos[3];
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 3 && !pendingDeletion[i]) {
			GetClientAbsOrigin(i, pos);
			float distance = GetVectorDistance(origin, pos);
			if(maxRange > 0.0 && distance > maxRange) continue;
			if(client == -1 || distance <= closestDist) {
				client = i;
				closestDist = distance;
			}
		}
	}
	return client;
}

stock int FindNearestVisibleSpecial(const float origin[3], float maxRange = 0.0) {
	int client = -1;
	static float closestDist;
	static float pos[3];
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 3 && !pendingDeletion[i]) {
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


stock int FindNearestInfected(const float origin[3], float maxRange = 0.0) {
	int infected = -1;
	float closestDist, pos[3];
	int entity = INVALID_ENT_REFERENCE;
	while ((entity = FindEntityByClassname(entity, "infected")) != INVALID_ENT_REFERENCE) {
		if(GetEntProp(entity, Prop_Send, "m_iHealth") <= 0) continue;
		GetEntPropVector(entity, Prop_Send, "m_vecOrigin", pos);
		float distance = GetVectorDistance(origin, pos);
		if(maxRange > 0.0 && distance > maxRange) continue;
		if(infected == -1 || distance <= closestDist) {
			infected = entity;
			closestDist = distance;
		}
	}
	return infected;
}

stock bool CanSeePoint(const float origin[3], const float point[3]) {
	TR_TraceRay(origin, point, MASK_ALL, RayType_EndPoint);
	if(!TR_DidHit() ) {
		return true;
	}
	return false;
}

stock bool CanSeeEntity(const float origin[3], int entity) {
	static float point[3];
	GetEntPropVector(entity, Prop_Send, "m_vecOrigin", point);
	return CanSeePoint(origin, point);
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


stock int CreateParticleNamed(const char[] targetname, const char[] sParticle, const float vPos[3], const float vAng[3], int client = 0)
{
	int entity = CreateEntityByName("info_particle_system");

	if( entity != -1 )
	{
		DispatchKeyValue(entity, "effect_name", sParticle);
		DispatchKeyValue(entity, "targetname", targetname);
		DispatchSpawn(entity);
		ActivateEntity(entity);
		AcceptEntityInput(entity, "start");

		if( client )
		{
			// Attach to survivor
			SetVariantString("!activator"); 
			AcceptEntityInput(entity, "SetParent", client);
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

	return 0;
}

stock void SetParent(int child, int parent) {
	SetVariantString("!activator");
	AcceptEntityInput(child, "SetParent", parent);
}