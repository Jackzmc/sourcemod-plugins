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
#include "jutils.inc"
//#include <sdkhooks>


public Plugin myinfo = 
{
	name = PLUGIN_NAME, 
	author = PLUGIN_AUTHOR, 
	description = PLUGIN_DESCRIPTION, 
	version = PLUGIN_VERSION, 
	url = PLUGIN_URL
};

int g_iSurvivors[MAXPLAYERS+1], g_iLastSpawnClient, g_iAvoidChar[MAXPLAYERS+1] = {-1,...};

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




stock bool SpawnSurvivor(const float vPos[3], const float vAng[3], const char[] model, bool spawn_minigun) {
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

	if(spawn_minigun && !SpawnMinigun(vPos, vAng)) {
		LogError("Failed to spawn minigun for client #%d", bot_client_id);
		KickClient(bot_client_id, "AIMinigun:MinigunSpawnFailure");
		return false;
	}
	TeleportEntity(bot_client_id, vPos, NULL_VECTOR, NULL_VECTOR);
	SetEntityModel(bot_client_id, model);
	CreateTimer(1.5, TimerMove, bot_user_id);
	return true;
}
stock bool TraceFilter(int entity, int contentsMask) {
	if( entity <= MaxClients )
		return false;
	return true;
}
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