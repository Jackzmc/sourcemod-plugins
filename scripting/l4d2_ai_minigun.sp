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

public void OnPluginStart() {
	EngineVersion g_Game = GetEngineVersion();
	if(g_Game != Engine_Left4Dead2) {
		SetFailState("This plugin is for L4D2 only.");	
	}

	RegAdminCmd("sm_ai_holdout", Command_SpawnHoldoutBot, ADMFLAG_ROOT);
	RegAdminCmd("sm_ai_minigun", Command_SpawnMinigunBot, ADMFLAG_ROOT);
	RegAdminCmd("sm_ai_remove_far", Command_RemoveFar,	ADMFLAG_ROOT);
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

public Action Command_RemoveFar(int client, int args) {
	for(int bot = 1; bot < MaxClients; bot++)  {
		if(IsClientConnected(bot) && IsClientInGame(bot) && GetClientTeam(bot) == 4 && IsFakeClient(bot)) {
			char name[64];
			GetClientName(bot, name, sizeof(name));
			//Only work on <Holdout/Minigun>Bot's 
			if(StrContains(name, "HoldoutBot", true) || StrContains(name, "MinigunBot", true)) {
				float botPos[3];
				GetClientAbsOrigin(bot, botPos);
				bool isClose = false;
				//Loop all players, if distance is less than 750, break out of loop
				for(int i = 1; i < MaxClients; i++)  {
					if(IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2 && !IsFakeClient(i)) {
						float playerPos[3];
						GetClientAbsOrigin(i, playerPos);

						float distance = GetVectorDistance(playerPos, botPos);
						if(distance <= 750) {
							isClose = true;
							break;
						}
					}
				}
				if(!isClose) {
					KickClient(bot);
					ReplyToCommand(client, "Removed %N", bot);
				}
			}
		}
	}
}

public Action Command_SpawnMinigunBot(int client, int args) {
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

		int survivor = GetClientOfUserId(SpawnSurvivor(vPos, vAng, model, true));
		if(survivor > 0) {
			GiveClientWeapon(survivor, "rifle_ak47", true);
		}else{
			ReplyToCommand(client, "Failed to spawn survivor.");
		}
	}else{
		ReplyToCommand(client, "Usage: sm_spawn_minigun_bot <4=Bill, 5=Zoey, 6=Francis, 7=Louis>");
	}
	return Plugin_Handled;
}

public Action Command_SpawnHoldoutBot(int client, int args) {
	char arg1[16];
	if(args > 0) {
		GetCmdArg(1, arg1, sizeof(arg1));
		char model[64];
		int survivorId = GetSurvivorId(arg1);
		if(survivorId == -1) {
			ReplyToCommand(client, "That is not a valid survivor.");
			return Plugin_Handled;
		}
		if(!GetSurvivorModel(survivorId, model, sizeof(model))) {
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

		char wpn[64];
		if(args > 1) {
			GetCmdArg(2, wpn, sizeof(wpn));
		}else {
			wpn = "rifle_ak47";
		}

		int survivor = SpawnSurvivor(vPos, vAng, model, false);
		if(survivor > 0) {
			GiveClientWeapon(survivor, wpn, true);
			SetEntProp(survivor, Prop_Send, "m_survivorCharacter", survivorId);
		}else{
			ReplyToCommand(client, "Failed to spawn survivor.");
		}
	}else{
		ReplyToCommand(client, "Usage: sm_spawn_minigun_bot <4=Bill, 5=Zoey, 6=Francis, 7=Louis> [weapon]");
	}
	return Plugin_Handled;
}

///////////////////////////////////////////
//
//STOCKS
//
///////////////////////////////////////////

//Taken from https://forums.alliedmods.net/showthread.php?p=1741099 and modified slightly (and documented)
stock int SpawnSurvivor(const float vPos[3], const float vAng[3], const char[] model, bool spawn_minigun) {
	int entity = CreateEntityByName("info_l4d1_survivor_spawn");
	if( entity == -1 ) {
		LogError("Failed to create \"info_l4d1_survivor_spawn\"");
		return -1;
	}
	//on spawn, to kill spawner
	//AcceptEntityInput(entity, "AddOutput");
	DispatchKeyValue(entity, "character", "7");
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
		return -1;
	}
	if(spawn_minigun && !SpawnMinigun(vPos, vAng)) {
		LogError("Failed to spawn minigun for client #%d", bot_client_id);
		KickClient(bot_client_id, "AIMinigun:MinigunSpawnFailure");
		return -1;
	}
	SetClientName(bot_client_id, spawn_minigun ? "MinigunBot" : "HoldoutBot");
	
	TeleportEntity(bot_client_id, vPos, NULL_VECTOR, NULL_VECTOR);
	SetEntityModel(bot_client_id, model); //set entity model to custom survivor model
	return bot_user_id;
}
void AvoidCharacter(int type, bool avoid) {
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
					case 6: set = 1;	// Francis
					case 7: set = 0;	// Louis
					default: return;
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

	if(!avoid) {
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
