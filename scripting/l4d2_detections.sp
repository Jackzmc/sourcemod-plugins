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

enum KitDetectionState {
	KDS_None,
	KDS_NoKitEnteringSaferoom,
	KDS_Healed
}

enum struct PlayerDetections {
	int kitPickupsSaferoom;
	int saferoomLastOpen;
	int saferoomOpenCount;
	// Do not reset normally; need to keep track during level transitions
	KitDetectionState saferoomKitState;

	// Called on PlayerDisconnect, which includes map changes
	void Reset() {
		this.kitPickupsSaferoom = 0;
		this.saferoomLastOpen = 0;
		this.saferoomOpenCount = 0;
	}
	// Called on normal intentional disconnect, ignoring map changes
	void FullReset() {
		this.saferoomKitState = KDS_None;
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
	return GetEntPropFloat(client, Prop_Send, "m_vomitStart") + 20.1 > GetGameTime();
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

stock int GetEntityCountNear(const float srcPos[3], float radius = 50000.0) {
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

PlayerDetections detections[MAXPLAYERS+1];
bool checkpointReached;

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
	HookEvent("player_disconnect", Event_PlayerDisconnect);
	HookEvent("heal_success", Event_HealSuccess);
}

public void OnClientPutInServer(int client) {
	CreateTimer(20.0, Timer_ClearDoubleKitDetection, GetClientUserId(client));
}

// Called on map changes too, we want this:
public void OnClientDisconnect(int client) {
	detections[client].Reset();
}

public void Event_PlayerDisconnect(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(client) {
		detections[client].FullReset();
	}
}

public void OnMapStart() {
	checkpointReached = false;
	HookEntityOutput("info_changelevel", "OnStartTouch", EntityOutput_OnStartTouchSaferoom);
	HookEntityOutput("trigger_changelevel", "OnStartTouch", EntityOutput_OnStartTouchSaferoom);
}

// TODO: Check when player enters saferoom, and has no kit and heals and pickup another
public void Event_ItemPickup(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(client && L4D_IsInLastCheckpoint(client)) {
		static char itmName[32];
		event.GetString("item", itmName, sizeof(itmName));
		if(StrEqual(itmName, "first_aid_kit")) {
			if(detections[client].saferoomKitState == KDS_NoKitEnteringSaferoom) {
				// Player had no kit entering saferoom and has healed
				detections[client].saferoomKitState = KDS_Healed;
			} else if(detections[client].saferoomKitState == KDS_Healed) {
				// Player has healed. Double kit detected	
				InternalDebugLog("DOUBLE_KIT", client);
				Call_StartForward(fwd_PlayerDoubleKit);
				Call_PushCell(client);
				Call_Finish();
			}
			if(++detections[client].kitPickupsSaferoom == 2) {
				InternalDebugLog("DOUBLE_KIT_LEGACY", client);
				Call_StartForward(fwd_PlayerDoubleKit);
				Call_PushCell(client);
				Call_Finish();
			}
		}
	}
}

public void EntityOutput_OnStartTouchSaferoom(const char[] output, int caller, int client, float time) {
	if(!checkpointReached && client > 0 && client <= MaxClients && GetClientTeam(client) == 2) {
		checkpointReached = true;
		char itemName[32];
		if(GetClientWeaponName(client, 3, itemName, sizeof(itemName))) {
			if(StrEqual(itemName, "weapon_first_aid_kit")) {
				detections[client].saferoomKitState = KDS_NoKitEnteringSaferoom;
			}
		}
	}
}

Action Timer_ClearDoubleKitDetection(Handle h, int userid) {
	int client = GetClientOfUserId(userid);
	if(client) {
		detections[client].saferoomKitState = KDS_None;
	}
	return Plugin_Continue;
}

public void Event_HealSuccess(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(client) {
		int target = GetClientOfUserId(event.GetInt("subject"));
		int amount = event.GetInt("health_restored");
		int orgHealth = GetClientHealth(target) - amount;
		PrintToConsoleAll("[Debug] %N healed %N (+%d health, was perm. %d)", client, target, amount, orgHealth);
	}
}

public void Event_DoorClose(Event event, const char[] name, bool dontBroadcast) {
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