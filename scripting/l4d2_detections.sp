#pragma semicolon 1
#pragma newdecls required

//#define DEBUG

#define PLUGIN_VERSION "1.0"
#define BILE_NO_HORDE_THRESHOLD 5
#define DOOR_CLOSE_THRESHOLD 5000.0

#include <sourcemod>
#include <sdktools>
#include <left4dhooks>
#include <jutils>
//#include <sdkhooks>

enum struct PlayerDetections {
	int kitPickupsSaferoom;
	int saferoomLastOpen;
	int saferoomOpenCount;

	void Reset() {
		this.kitPickupsSaferoom = 0;
		this.saferoomLastOpen = 0;
		this.saferoomOpenCount = 0;
	}
	
}

/*
Bile Detections:
1. No commons around entowner or bile
2. Bile already exists
3. Player is currently vomitted on (check time?)
4. Bile on tank (common count near tank)
*/

stock bool IsPlayerBoomed(int client) {
	return GetEntPropFloat(%0, Prop_Send, "m_vomitStart") + 20.1 > GetGameTime();
}
stock bool IsAnyPlayerBoomed() {
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2 && IsPlayerBoomed(i)) {
			return true;
		}
	}
	return false;
}

stock bool AnyRecentBileInPlay(int ignore) {
	return false;
}

stock int GetEntityCountNear(const float[3] srcPos, float radius = 50000.0) {
	float pos[3];
	int count;
	int entity = -1;
	while( (entity = FindEntityByClassname(entity, "infected")) != INVALID_ENT_REFERENCE ) {
		GetEntPropVector(entity, Prop_Send, "m_vecOrigin", pos);
		if(GetEntProp(entity, Prop_Send, "m_clientLookatTarget") != -1 && GetVectorDistance(pos, srcPos) <= radius) {
			count++;
		}
	}
	return count;
}
stock int L4D_SpawnCommonInfected2(const float vPos[3], const float vAng[3] = { 0.0, 0.0, 0.0 })
{
	int entity = CreateEntityByName("infected");
	if( entity != -1 )
	{
		DispatchSpawn(entity);
		TeleportEntity(entity, vPos, vAng, NULL_VECTOR);
	}

	return entity;
}

PlayerDetections[MAXPLAYERS+1] detections;

GlobalForward fwd_PlayerDoubleKit, fwd_NoHordeBileWaste, fwd_DoorFaceCloser, fwd_CheckpointDoorFaceCloser;

public Plugin myinfo = 
{
	name =  "L4D2 Detections", 
	author = "jackzmc", 
	description = "", 
	version = PLUGIN_VERSION, 
	url = ""
};

public void OnPluginStart() {
	EngineVersion g_Game = GetEngineVersion();
	if(g_Game != Engine_Left4Dead && g_Game != Engine_Left4Dead2) {
		SetFailState("This plugin is for L4D/L4D2 only.");	
	}

	fwd_PlayerDoubleKit = new GlobalForward("OnDoubleKit", ET_Hook, Param_Cell);
	fwd_NoHordeBileWaste = new GlobalForward("OnNoHordeBileWaste", ET_Event, Param_Cell, Param_Cell);
	fwd_DoorFaceCloser = new GlobalForward("OnDoorCloseInFace", ET_Hook, Param_Cell);
	fwd_CheckpointDoorFaceCloser = new GlobalForward("OnDoorCloseInFaceSaferoom", ET_Hook, Param_Cell, Param_Cell);

	HookEvent("item_pickup", Event_ItemPickup);
	HookEvent("door_close", Event_DoorClose);
}

// Called on map changes too, we want this:
public void OnClientDisconnect(int client) {
	detections[client].Reset();
}

public Action Event_ItemPickup(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(client && L4D_IsInLastCheckpoint(client)) {
		static char itmName[32];
		event.GetString("item", itmName, sizeof(itmName));
		if(StrEqual(itmName, "first_aid_kit")) {
			if(++detections[client].kitPickupsSaferoom == 2) {
				InternalDebugLog("DOUBLE_KIT", client);
				Call_StartForward(fwd_PlayerDoubleKit);
				Call_PushCell(client);
				Call_Finish();
			}
		}
	}
}

public Action Event_DoorClose(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(fwd_DoorFaceCloser.FunctionCount > 0 && client) {
		bool isCheckpoint = event.GetBool("checkpoint");
		DataPack pack = GetNearestClient(client);
		pack.Reset();
		int victim = pack.ReadCell();
		float dist = pack.ReadFloat();
		if(victim) {
			if(dist < DOOR_CLOSE_THRESHOLD) {
				if(isCheckpoint) {
					if(detections[client].saferoomLastOpen > 0 && GetTime() - detections[client].saferoomLastOpen > 30000) {
						detections[client].saferoomLastOpen = 0;
						detections[client].saferoomOpenCount = 0;
					}
					Call_StartForward(fwd_CheckpointDoorFaceCloser);
					Call_PushCell(client);
					Call_PushCell(victim);
					Call_PushCell(++detections[client].saferoomOpenCount);
					Call_Finish();
					detections[client].saferoomLastOpen = GetTime();
					PrintToServer("[Detections] DOOR_SAFEROOM: %N victim -> %N %d times", client, victim, detections[client].saferoomOpenCount);
					//TODO: Find way to reset, timer?
				} else {
					Call_StartForward(fwd_DoorFaceCloser);
					Call_PushCell(client);
					Call_PushCell(victim);
					Call_Finish();
					PrintToServer("[Detections] DOOR=: %N victim -> %N", client, victim);
				}
			}
		}
	}
}

public void OnEntityDestroyed(int entity) {
	static char classname[16];
	if(IsValidEntity(entity) && entity <= 4096) {
		GetEntityClassname(entity, classname, sizeof(classname));
		if(StrEqual(classname, "vomitjar_projec")) { //t cut off by classname size
			int thrower = GetEntPropEnt(entity, Prop_Send, "m_hThrower");
			if(thrower > 0 && thrower <= MaxClients && IsClientConnected(thrower) && IsClientInGame(thrower)) {
				static float src[3];
				float tmp[3];
				GetClientAbsOrigin(thrower, tmp);
				// TODO: Get source when lands
				GetEntPropVector(entity, Prop_Send, "m_vecOrigin", src);
				
				int commons = GetEntityCountNear(src, 50000.0);
				PrintToConsoleAll("[Debug] Bile Thrown By %N, Commons: %d", thrower, commons);
				if(commons < BILE_NO_HORDE_THRESHOLD) {
					InternalDebugLog("BILE_NO_HORDE", thrower);
					Action result;
					Call_StartForward(fwd_NoHordeBileWaste);
					Call_PushCell(thrower);
					Call_PushCell(commons);
					Call_Finish(result);

					if(result == Plugin_Stop) { 
						AcceptEntityInput(entity, "kill");
						// GiveClientWeapon(thrower, "vomitjar");
					}
				}
			}
		}
	}
}

// TODO: Door close

void InternalDebugLog(const char[] name, int client) {
	PrintToConsoleAll("[Detection] %s: Client %N", name, client);
}

stock DataPack GetNearestClient(int client) {
	int victim;
	float pos[3], pos2[3], distance;
	GetClientAbsOrigin(client, pos);
	for(int i = 1; i <= MaxClients; i++) {
		if(i != client && IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2) {
			GetClientAbsOrigin(i, pos2);
			float dist = GetVectorDistance(pos, pos2, false);
			if(victim == 0 || dist < distance) {
				distance = dist;
				victim = i;
			}
		}
	}
	DataPack pack = new DataPack();
	pack.WriteCell(victim);
	pack.WriteFloat(distance);
	return pack;
}