#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#define HIT_1 "weapons/golf_club/wpn_golf_club_melee_01.wav"
#define HIT_2 "weapons/golf_club/wpn_golf_club_melee_02.wav"

ConVar sv_melee_force_projectile, sv_melee_radius_projectile, sv_melee_force_boost_projectile_up;
int g_iLaser, g_iGlow;

public Plugin myinfo =
{
    name = "[L4D2] Baseball",
    author = "BHaType",
    description = "Melee weapons can now deflect projectile",
    version = "0.0",
    url = ""
}

public void OnPluginStart()
{
	sv_melee_force_projectile = CreateConVar("sv_melee_force_projectile", "0.6");
	sv_melee_force_boost_projectile_up = CreateConVar("sv_melee_force_boost_projectile_up", "250.0");
	sv_melee_radius_projectile = CreateConVar("sv_melee_radius_projectile", "75.0");
	
	AutoExecConfig(true, "l4d2_baseball");
	
	HookEvent("weapon_fire", weapon_fire);
	HookEvent("entity_shoved", entity_shoved);
}

public void OnMapStart()
{
	PrecacheSound(HIT_1, true);
	PrecacheSound(HIT_2, true);
	
	g_iLaser = PrecacheModel("materials/sprites/laserbeam.vmt");    
	g_iGlow = PrecacheModel("materials/sprites/glow.vmt");  	
}

public void entity_shoved (Event event, const char[] name, bool dontbroadcast)
{
	int entity = event.GetInt("entityid");
	
	static char szName[36];
	GetEntityClassname(entity, szName, sizeof szName);
	
	if ( StrContains(szName, "_projectile") != -1 )
	{
		float vVelocity[3];
		vVelocity = CalculateBaseForce(entity);
		vVelocity[2] += sv_melee_force_boost_projectile_up.FloatValue;
		
		TeleportEntity(entity, NULL_VECTOR, NULL_VECTOR, vVelocity);
	}
}

public void weapon_fire (Event event, const char[] name, bool dontbroadcast)
{
	static char szName[36];
	event.GetString("weapon", szName, sizeof szName);
	
	if ( strcmp(szName, "melee") != 0 )
		return;
	
	int client = event.GetInt("userid");
	timer (CreateTimer(0.1, timer, client, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE), client);
}

public Action timer (Handle timer, int client)
{
	client = GetClientOfUserId(client);
	
	if ( !client )
		return Plugin_Stop;
	
	int weapon = GetPlayerWeaponSlot(client, 1);

	if ( weapon == -1 || GetEntPropFloat(weapon, Prop_Send, "m_flNextPrimaryAttack") <= GetGameTime())
		return Plugin_Stop;
	
	float vAngles[3], vOrigin[3], vVector[3], vEnd[3];
	
	GetClientEyePosition(client, vOrigin);
	
	GetClientEyeAngles(client, vAngles);
	GetAngleVectors(vAngles, vVector, NULL_VECTOR, NULL_VECTOR);
	ScaleVector(vVector, sv_melee_radius_projectile.FloatValue);
	AddVectors(vOrigin, vVector, vEnd);
	
	GetClientEyePosition(client, vOrigin);
	
	#define hull 10.0
	static const float vMaxs[3] = { hull, hull, hull }; 
	static const float vMins[3] = { -hull, -hull, -hull };
	
	TR_TraceHullFilter(vOrigin, vEnd, vMins, vMaxs, MASK_SOLID, TraceFilter, client);
	float vHit[3];
	TR_GetEndPosition(vHit); 
	
	if ( TR_DidHit () )
	{
		int entity = TR_GetEntityIndex();
		
		if ( entity != 0 )
		{
			static char szName[36];
			GetEntityClassname(entity, szName, sizeof szName);
			
			if ( StrContains(szName, "_projectile") != -1 )
			{
				float vVelocity[3], vVec[3];
	
				vVelocity = CalculateBaseForce(entity, client);
				GetEntPropVector(entity, Prop_Send, "m_vecOrigin", vOrigin);
				
				MakeVectorFromPoints(vHit, vOrigin, vVec);
				ScaleVector(vVec, 1.0 - sv_melee_force_projectile.FloatValue * sv_melee_radius_projectile.FloatValue);
				AddVectors(vVec, vVector, vVec);
				AddVectors(vVec, vVelocity, vVelocity);
				
				TE_SetupSparks(vHit, vVelocity, 1, 1);
				TE_SendToAll();
				
				NegateVector(vVelocity);		
				
				vVelocity[2] += sv_melee_force_boost_projectile_up.FloatValue;
				TeleportEntity(entity, NULL_VECTOR, NULL_VECTOR, vVelocity);
				
				int color[4] = { 255, ... };
				for (int i; i <= 2; i++)
					color[i] = GetRandomInt(0, 255);
					
				TE_SetupBeamFollow(entity, g_iLaser, g_iGlow, 4.6, 0.8, 0.8, 1, color);
				TE_SendToAll();
				
				EmitSoundToAll((GetRandomInt(0, 1) == 0 ? HIT_1 : HIT_2), SOUND_FROM_WORLD, .origin = vHit);
				
				// PrintToChatAll("\x04%N \x03baseballed projectile for \x04%.2f \x03velocity!", client, GetVectorLength(vVelocity));
				return Plugin_Stop;
			}
		}
	}
	
	return Plugin_Continue;
}

float[] CalculateBaseForce (int victim, int attacker = 0)
{	
	float m_vecBaseVelocity[3], m_vecVelocity[3], vAngles[3];
	
	if ( attacker )
	{
		GetEntPropVector(attacker, Prop_Send, "m_vecBaseVelocity", m_vecBaseVelocity);
		GetClientEyeAngles(attacker, vAngles);
	}
	
	GetEntPropVector(victim, Prop_Data, "m_vecVelocity", m_vecVelocity);
	AddVectors(m_vecBaseVelocity, m_vecVelocity, m_vecVelocity);
	
	ScaleVector(m_vecVelocity, sv_melee_force_projectile.FloatValue);
	
	return m_vecVelocity;
}

public bool TraceFilter (int entity, int mask, int data)
{
	return entity != data;
}