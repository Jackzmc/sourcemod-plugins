#pragma semicolon 1
#pragma newdecls required

//#define DEBUG

#define PLUGIN_NAME "l4d2 ai minigun"
#define PLUGIN_DESCRIPTION ""
#define PLUGIN_AUTHOR "jackzmc"
#define PLUGIN_VERSION "1.0"
#define PLUGIN_URL ""

#include <sourcemod>
#include <sdktools>
//#include <sdkhooks>

#define MODEL_MINIGUN		"models/w_models/weapons/w_minigun.mdl"
#define MODEL_FRANCIS		"models/survivors/survivor_biker.mdl"
#define MODEL_LOUIS			"models/survivors/survivor_manager.mdl"
#define MODEL_ZOEY			"models/survivors/survivor_teenangst.mdl"
#define MODEL_BILL			"models/survivors/survivor_namvet.mdl"
#define MODEL_NICK			"models/survivors/survivor_gambler.mdl"
#define MODEL_COACH			"models/survivors/survivor_coach.mdl"
#define MODEL_ELLIS			"models/survivors/survivor_mechanic.mdl"
#define MODEL_ROCHELLE		"models/survivors/survivor_producer.mdl"

public Plugin myinfo = 
{
	name = PLUGIN_NAME, 
	author = PLUGIN_AUTHOR, 
	description = PLUGIN_DESCRIPTION, 
	version = PLUGIN_VERSION, 
	url = PLUGIN_URL
};

int g_iSurvivors[MAXPLAYERS+1], g_iLastSpawnClient;

public void OnPluginStart()
{
	EngineVersion g_Game = GetEngineVersion();
	if(g_Game != Engine_Left4Dead && g_Game != Engine_Left4Dead2)
	{
		SetFailState("This plugin is for L4D/L4D2 only.");	
	}

	RegAdminCmd("sm_spawn_minigun_bot", Command_SpawnAIBot, ADMFLAG_ROOT);
}
public void OnMapStart() {
	PrecacheModel(MODEL_MINIGUN);
	PrecacheModel(MODEL_LOUIS);
	PrecacheModel(MODEL_ZOEY);
	PrecacheModel(MODEL_BILL);
	PrecacheModel(MODEL_FRANCIS);
}
public void OnClientPutInServer(int client) {
	if( g_iLastSpawnClient == -1)
	{
		g_iSurvivors[client] = GetClientUserId(client);
		g_iLastSpawnClient = GetClientUserId(client);
	}
}
public Action Command_SpawnAIBot(int client, int args) {
	char arg1[16];
	if(args > 0) {
		GetCmdArg(1, arg1, sizeof(arg1));
		char model[64];
		if(!FindSurvivorModel(arg1, model, sizeof(model))) {
			LogError("Could not find a survivor model.");
			ReplyToCommand(client, "Could not find that survivor.");
			return Plugin_Handled;
		}

		//get ground:
		float vPos[3], vAng[3];
		if(!GetGround(client, vPos, vAng)) {
			LogError("Failed to find ground for survivor");
			ReplyToCommand(client, "Could not find a suitable ground location to spawn survivor.");
			return Plugin_Handled;
		}
		//make sure spawns a little above
		vPos[2] += 1.0;

		if(!SpawnSurvivor(vPos, vAng, model, true)) {
			ReplyToCommand(client, "Failed to spawn survivor.");
		}
	}else{
		ReplyToCommand(client, "Usage: sm_spawn_minigun_bot <4=Bill, 5=Zoey, 6=Francis, 7=Louis>");
	}
	return Plugin_Handled;
}

bool SpawnSurvivor(const float vPos[3], const float vAng[3], const char[] model, bool spawn_minigun) {
	int entity = CreateEntityByName("info_l4d1_survivor_spawn");
	if( entity == -1 ) {
		LogError("Failed to create \"info_l4d1_survivor_spawn\"");
		return false;
	}
	//set character type (7 = Louis)
	DispatchKeyValue(entity, "character", "7");
	//on spawn, to kill spawner
	//AcceptEntityInput(entity, "AddOutput");
	AcceptEntityInput(entity, "Kill");

	//teleport spawner to valid spot & spawn it
	TeleportEntity(entity, vPos, vAng, NULL_VECTOR);
	DispatchSpawn(entity);

	//Tell spawner to spawn survivor
	g_iLastSpawnClient = -1;
	AvoidCharacter(7, true);
	AcceptEntityInput(entity, "SpawnSurvivor");
	AvoidCharacter(7, false);
	
	//remove reference to last spawn id
	int bot_user_id = g_iLastSpawnClient, bot_client_id;
	g_iLastSpawnClient = -1;
	if( bot_user_id <= 0 || (bot_client_id = GetClientOfUserId(bot_user_id)) <= 0 )
	{
		LogError("Failed to match survivor, did they not spawn? [%d/%d]", bot_user_id, bot_client_id);
		return false;
	}
	SetClientName(bot_client_id, "MinigunBot");
	TeleportEntity(bot_client_id, vPos, NULL_VECTOR, NULL_VECTOR);

	if(spawn_minigun && !SpawnMinigun(vAng, vPos)) {
		LogError("Failed to spawn minigun for client #%d", bot_client_id);
		KickClient(bot_client_id, "AIMinigun:MinigunSpawnFailure");
		return false;
	}
	TeleportEntity(bot_client_id, vPos, NULL_VECTOR, NULL_VECTOR);
	SetEntityModel(bot_client_id, model);
	CreateTimer(1.5, TimerMove, bot_user_id);
	return true;
}

stock bool FindSurvivorModel(const char str[16], char[] model, int modelStrSize) {
	int possibleNumber = StringToInt(str, 10);
	if(modelStrSize == 1 && possibleNumber <= 7 && possibleNumber >= 0) {
		switch(possibleNumber) {
			case 0: {
				strcopy(model, modelStrSize, MODEL_NICK);
			} case 1: {
				strcopy(model, modelStrSize, MODEL_ELLIS);
			} case 2: {
				strcopy(model, modelStrSize, MODEL_COACH);
			} case 3: {
				strcopy(model, modelStrSize, MODEL_ROCHELLE);
			} case 4: {
				strcopy(model, modelStrSize, MODEL_BILL);
			} case 5: {
				strcopy(model, modelStrSize, MODEL_ZOEY);
			} case 6: {
				strcopy(model, modelStrSize, MODEL_FRANCIS);
			} case 7: {
				strcopy(model, modelStrSize, MODEL_LOUIS);
			}
			default:
				return false;
		}
		return true;
	}else{
		if(possibleNumber == 0) {
			//try to parse str
			if(StrEqual(str, "bill", false)) {
				strcopy(model, modelStrSize, MODEL_BILL);
			}else if(StrEqual(str, "zoey", false)) {
				strcopy(model, modelStrSize, MODEL_ZOEY);
			}else if(StrEqual(str, "francis", false)) {
				strcopy(model, modelStrSize, MODEL_FRANCIS);
			}else if(StrEqual(str, "louis", false)) {
				strcopy(model, modelStrSize, MODEL_LOUIS);
			}else if(StrEqual(str, "nick", false)) {
				strcopy(model, modelStrSize, MODEL_NICK);
			}else if(StrEqual(str, "ellis", false)) {
				strcopy(model, modelStrSize, MODEL_ELLIS);
			}else if(StrEqual(str, "rochelle", false)) {
				strcopy(model, modelStrSize, MODEL_ROCHELLE);
			}else if(StrEqual(str, "coach", false)) {
				strcopy(model, modelStrSize, MODEL_COACH);
			}else{
				return false;
			}
			return true;
		}
	}
	return false;
}

bool SpawnMinigun(const float vAng[3], const float vPos[3]) {
	float vDir[3], newPos[3];
	GetAngleVectors(vAng, vDir, NULL_VECTOR, NULL_VECTOR);
	vDir[0] = vPos[0] + (vDir[0] * 50);
	vDir[1] = vPos[1] + (vDir[1] * 50);
	vDir[2] = vPos[2] + 20.0;
	newPos = vDir;
	newPos[2] -= 40.0;

	Handle trace = TR_TraceRayFilterEx(vDir, newPos, MASK_SHOT, RayType_EndPoint, TraceFilter);
	if(TR_DidHit(trace)) {
		TR_GetEndPosition(vDir, trace);

		int minigun = CreateEntityByName("prop_mounted_machine_gun");
		minigun = EntIndexToEntRef(minigun);
		SetEntityModel(minigun, MODEL_MINIGUN);
		DispatchKeyValue(minigun, "targetname", "louis_holdout");
		DispatchKeyValueFloat(minigun, "MaxPitch", 360.00);
		DispatchKeyValueFloat(minigun, "MinPitch", -360.00);
		DispatchKeyValueFloat(minigun, "MaxYaw", 90.00);
		newPos[2] += 0.1;
		TeleportEntity(minigun, vDir, vAng, NULL_VECTOR);
		DispatchSpawn(minigun);
		delete trace;
		return true;
	}else{
		LogError("Spawn minigun trace failure");
		delete trace;
		return false;
	}
}

stock bool TraceFilter(int entity, int contentsMask) {
	if( entity <= MaxClients )
		return false;
	return true;
}
stock bool GetGround(int client, float[3] vPos, float[3] vAng) {
	GetClientAbsOrigin(client, vPos);
	vAng = vPos;
	vAng[2] += 5.0;
	vPos[2] -= 500.0;

	Handle trace = TR_TraceRayFilterEx(vAng, vPos, MASK_SHOT, RayType_EndPoint, TraceFilter);
	if(!TR_DidHit(trace))
	{
		delete trace;
		return false;
	}
	TR_GetEndPosition(vPos, trace);
	delete trace;

	GetClientAbsAngles(client, vAng);
	return true;
}

g_iAvoidChar[MAXPLAYERS+1] = {-1,...};
void AvoidCharacter(int type, bool avoid)
{
	for( int i = 1; i <= MaxClients; i++ )
	{
		if( IsClientInGame(i) && (GetClientTeam(i) == 2 || GetClientTeam(i) == 4) )
		{
			if( avoid )
			{
				// Save character type
				g_iAvoidChar[i] = GetEntProp(i, Prop_Send, "m_survivorCharacter");
				int set;
				switch( type )
				{
					case 4: set = 3;	// Bill
					case 5: set = 2;	// Zoey
					case 7: set = 1;	// Francis
					case 6: set = 0;	// Louis
				}
				SetEntProp(i, Prop_Send, "m_survivorCharacter", set);
			} else {
				// Restore player type
				if( g_iAvoidChar[i] != -1 )
				{
					SetEntProp(i, Prop_Send, "m_survivorCharacter", g_iAvoidChar[i]);
					g_iAvoidChar[i] = -1;
				}
			}
		}
	}

	if( !avoid )
	{
		for( int i = 1; i <= MAXPLAYERS; i++ )
			g_iAvoidChar[i] = -1;
	}
}

Action TimerMove(Handle timer, any client) {
	if((client = GetClientOfUserId(client))) {
		//PrintToServer("client %d %N",client,client);
		SetEntityMoveType(client, MOVETYPE_NONE);
		TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, view_as<float>({ 0.0, 0.0, 0.0 }));
	}
}