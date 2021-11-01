#pragma semicolon 1
#pragma newdecls required

//#define DEBUG

#define PLUGIN_VERSION "1.0"
// #define FORCE_ENABLED 1
//TODO: Preload models

#include <sourcemod>
#include <sdktools>
#include <left4dhooks>
//#include <sdkhooks>

public Plugin myinfo = 
{
	name =  "L4D2 Hide & Seek", 
	author = "jackzmc", 
	description = "", 
	version = PLUGIN_VERSION, 
	url = ""
};

#define PROP_DUMPSTER "models/props_junk/dumpster.mdl"
#define PROP_DOCK "models/props_swamp/boardwalk_384.mdl"
#define PROP_SHELF "models/props/cs_office/shelves_metal.mdl"
#define PROP_SIGN "models/props_swamp/river_sign01.mdl"

static char gamemode[32];
static bool isEnabled, lateLoaded;

static bool isPendingPlay[MAXPLAYERS+1];
static bool isNavBlockersEnabled = true;
static bool hasFiredRoundStart = false;

static const float C8M3_SEWERS_A[3] = { 13265.965820, 8547.057617, -250.7 };
static const float C8M3_SEWERS_A_PROP[3] = { 13265.965820, 8497.057617, -240.7 };
static const float C8M3_SEWERS_B[3] = { 14130.535156, 8026.46386, -254.7 };

static const float C3M4_PLANTATION_A[3] = { 2122.044189, -588.200195, 470.435608};
static const float C3M4_PLANTATION_A2[3] = {2000.802612, -426.686829, 402.803497};

static const float C1M3_MALL_A[3] = { 1714.133179, -1023.777527, 347.735168};
static const float C1M3_MALL_A_PROP[3] = { 1581.286865, -1029.394043, 280.079254};
 

static const float SCALE_FLAT_MEDIUM[3] = { 50.0, 50.00, 1.0 };
static const float SCALE_FLAT_LARGE[3] = { 150.0, 150.00, 1.0 };
static const float SCALE_TALL_MEDIUM[3] = { 25.0, 25.00, 100.0 };

static const float ROT_H_90[3] = { 0.0, 90.0, 0.0 };
static const float ROT_V_90_H_90[3] = { 90.0, 90.0, 0.0 };
static const float ROT_V_90[3] = { 90.0, 00.0, 0.0 };
static const float DEFAULT_SCALE[3] = { 5.0, 5.0, 5.0 };

static ArrayList entities;
static char currentMapConfig[32];

static KeyValues kv;
static StringMap mapConfigs;
enum struct EntityConfig {
	float origin[3];
	float rotation[3];
	char type[16];
	char model[64];
	float scale[3];

	bool toggleable;
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
	lateLoaded = late;
	return APLRes_Success;
}

public void OnPluginStart() {
	EngineVersion g_Game = GetEngineVersion();
	if(g_Game != Engine_Left4Dead2) {
		SetFailState("This plugin is for L4D2 only.");	
	}

	kv = new KeyValues("EntityConfig");

	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "data/hideandseek.cfg");

	if(!FileExists(sPath) || !kv.ImportFromFile(sPath)) {
		delete kv;
		SetFailState("Could not load entity config from data/hideandseek.cfg");
	}

	mapConfigs = new StringMap();

	ConVar hGamemode = FindConVar("mp_gamemode"); 
	hGamemode.GetString(gamemode, sizeof(gamemode));
	hGamemode.AddChangeHook(Event_GamemodeChange);
	Event_GamemodeChange(hGamemode, gamemode, gamemode);

	lateLoaded = false;

	RegConsoleCmd("sm_joingame", Command_Join, "Joins or joins someone else");
	RegAdminCmd("sm_hs_toggle", Command_ToggleBlockers, ADMFLAG_KICK, "Toggle nav blockers");
}

ArrayList LoadConfigForMap(const char[] map) {
	if (kv.JumpToKey(map)) {
		strcopy(currentMapConfig, sizeof(currentMapConfig), map);
		ArrayList configs = new ArrayList(sizeof(EntityConfig));
		if(kv.JumpToKey("blockers")) {
			kv.GotoFirstSubKey();
			do {
				EntityConfig config;
				kv.GetVector("origin", config.origin, NULL_VECTOR);
				kv.GetVector("rotation", config.rotation, NULL_VECTOR);
				kv.GetString("type", config.type, sizeof(config.type), "env_physics_blocker");
				kv.GetString("model", config.model, sizeof(config.model), "");
				kv.GetVector("scale", config.scale, DEFAULT_SCALE);

				config.toggleable = true;

				configs.PushArray(config);
			} while (kv.GotoNextKey());
		}
		if(kv.JumpToKey("props")) {
			do {
				EntityConfig config;
				kv.GetVector("origin", config.origin, NULL_VECTOR);
				kv.GetVector("rotation", config.rotation, NULL_VECTOR);
				kv.GetString("type", config.type, sizeof(config.type), "env_physics_blocker");
				kv.GetString("model", config.model, sizeof(config.model), "");
				kv.GetVector("scale", config.scale, DEFAULT_SCALE);

				configs.PushArray(config);
			} while (kv.GotoNextKey());
		}
		kv.GoBack();
		// Store ArrayList<EntityConfig> handle
		mapConfigs.SetValue(map, configs);
		return configs;
    } else {
		return null;
	}
}

public Action Command_ToggleBlockers(int client, int args) {
	static char targetname[32];
	int entity = INVALID_ENT_REFERENCE;
	while ((entity = FindEntityByClassname(entity, "env_physics_blocker")) != INVALID_ENT_REFERENCE) {
		GetEntPropString(entity, Prop_Data, "m_iName", targetname, sizeof(targetname));
		if(StrEqual(targetname, "hsblocker")) {
			if(isNavBlockersEnabled)
				AcceptEntityInput(entity, "Disable");
			else
				AcceptEntityInput(entity, "Enable");
		}
	}

	if(isNavBlockersEnabled) {
		ReplyToCommand(client, "Disabled all custom nav blockers");
	} else {
		ReplyToCommand(client, "Enabled all custom nav blockers");
	}
	isNavBlockersEnabled = !isNavBlockersEnabled;
	return Plugin_Handled;
}

public Action Command_Join(int client, int args) {
	static float tpLoc[3];
	if(args == 1) {
		GetClientAbsOrigin(client, tpLoc);
		static char arg1[32];
		GetCmdArg(1, arg1, sizeof(arg1));
		char target_name[MAX_TARGET_LENGTH];
		int target_list[MAXPLAYERS], target_count;
		bool tn_is_ml;
		if ((target_count = ProcessTargetString(
				arg1,
				client,
				target_list,
				MAXPLAYERS,
				COMMAND_FILTER_ALIVE,
				target_name,
				sizeof(target_name),
				tn_is_ml)) <= 0)
		{
			/* This function replies to the admin with a failure message */
			ReplyToTargetError(client, target_count);
			return Plugin_Handled;
		}
		for (int i = 0; i < target_count; i++) {
			int target = target_list[i];
			if(GetClientTeam(target) != 2) {
				ChangeClientTeam(target, 2);
				L4D_RespawnPlayer(target);
				TeleportEntity(target, tpLoc, NULL_VECTOR, NULL_VECTOR);
				isPendingPlay[client] = false;
			}
		}
		ReplyToCommand(client, "Joined %s", target_name);
	} else {
		for(int i = 1; i <= MaxClients; i++) {
			if(IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i)) {
				GetClientAbsOrigin(i, tpLoc);
				break;
			}
		}
		isPendingPlay[client] = false;
		ChangeClientTeam(client, 2);
		L4D_RespawnPlayer(client);
		TeleportEntity(client, tpLoc, NULL_VECTOR, NULL_VECTOR);
	}
	return Plugin_Handled;
}

public void OnMapStart() {
	static char map[16];
	GetCurrentMap(map, sizeof(map));

	ArrayList configs;
	if(!mapConfigs.GetValue(map, configs)) {
		configs = LoadConfigForMap(map);
		PrintToServer("H&S: Fetching config for map %s", map);
	}
	if(isEnabled) {
		for(int i = 0; i < configs.Length; i++) {
			EntityConfig config;
			configs.GetArray(i, config);
			if(config.model[0] != '\0')
				PrecacheModel(config.model);
			bool isEnabled = true;
			if(config.toggleable && !isNavBlockersEnabled) {
				isEnabled = false;
			}
			if(StrEqual(config.type, "env_physics_blocker")) {
				CreateEnvBlockerBoxScaled(config.origin, config.scale, isEnabled);
			} else {
				CreateProp(config.model, config.origin, config.rotation);
			}
		}
		// 
		// if(StrEqual(map, "c8m3_sewers")) {
		// 	if(isNavBlockersEnabled) {
		// 		CreateEnvBlockerBox(C8M3_SEWERS_A, isNavBlockersEnabled);
		// 		CreateEnvBlockerBox(C8M3_SEWERS_B, isNavBlockersEnabled);
		// 		CreateProp(PROP_SHELF, C8M3_SEWERS_A_PROP, ROT_V_90_H_90);
		// 		CreateProp(PROP_SIGN, C8M3_SEWERS_B, ROT_V_90);
		// 	}
		// } else if(StrEqual(map, "c3m4_plantation")) {
		// 	if(isNavBlockersEnabled) {
		// 		CreateEnvBlockerBoxScaled(C3M4_PLANTATION_A2, SCALE_FLAT_LARGE);
		// 		CreateProp(PROP_DOCK, C3M4_PLANTATION_A2, ROT_H_90);
		// 	}
		// 	// CreateEnvBlockerBoxScaled(C3M4_PLANTATION_A, SCALE_FLAT_LARGE);
		// } else if(StrEqual(map, "c1m3_mall")) {
		// 	CreateProp(PROP_DUMPSTER, C1M3_MALL_A_PROP, ROT_H_90);
		// 	if(isNavBlockersEnabled) {
		// 		CreateEnvBlockerBoxScaled(C1M3_MALL_A, SCALE_TALL_MEDIUM);
		// 	}
		// }
	}
}

stock int CreateEnvBlockerBox(const float pos[3], bool enabled = true) {
	int entity = CreateEntityByName("env_physics_blocker");
	DispatchKeyValue(entity, "targetname", "hsblocker");
	DispatchKeyValue(entity, "initialstate", "1");
	DispatchKeyValue(entity, "BlockType", "0");
	TeleportEntity(entity, pos, NULL_VECTOR, NULL_VECTOR);
	DispatchSpawn(entity);
	if(enabled)
		AcceptEntityInput(entity, "Enable");
	PrintToServer("spawn blocker %f %f %f", pos[0], pos[1], pos[2]);
	return entity;
}

stock int CreateEnvBlockerBoxScaled(const float pos[3], const float scale[3], bool enabled = true) {
	int entity = CreateEntityByName("env_physics_blocker");
	DispatchKeyValue(entity, "targetname", "hsblocker");
	DispatchKeyValue(entity, "initialstate", "1");
	DispatchKeyValue(entity, "BlockType", "0");
	static float mins[3];
	mins = scale;
	NegateVector(mins);
	DispatchKeyValueVector(entity, "boxmins", mins);
	DispatchKeyValueVector(entity, "boxmaxs", scale);
	DispatchKeyValueVector(entity, "mins", mins);
	DispatchKeyValueVector(entity, "maxs", scale);

	TeleportEntity(entity, pos, NULL_VECTOR, NULL_VECTOR);
	DispatchSpawn(entity);
	SetEntPropVector(entity, Prop_Send, "m_vecMaxs", scale);
	SetEntPropVector(entity, Prop_Send, "m_vecMins", mins);
	if(enabled)
		AcceptEntityInput(entity, "Enable");
	PrintToServer("spawn blocker scaled %f %f %f scale [%f %f %f]", pos[0], pos[1], pos[2], scale[0], scale[1], scale[2]);
	return entity;
}

stock int CreateProp(const char[] model, const float pos[3], const float ang[3]) {
	int entity = CreateEntityByName("prop_dynamic");
	DispatchKeyValue(entity, "model", model);
	DispatchKeyValue(entity, "solid", "6");
	DispatchKeyValue(entity, "targetname", "hsprop");
	DispatchKeyValue(entity, "disableshadows", "1");
	TeleportEntity(entity, pos, ang, NULL_VECTOR);
	DispatchSpawn(entity);
	PrintToServer("spawn prop %f %f %f", pos[0], pos[1], pos[2]);
	return entity;
}

public void Event_GamemodeChange(ConVar cvar, const char[] oldValue, const char[] newValue) {
	cvar.GetString(gamemode, sizeof(gamemode));
	#if defined FORCE_ENABLED
		isEnabled = true;
	#else
		isEnabled = StrEqual(gamemode, "hideandseek");
	#endif
	if(isEnabled) {
		HookEvent("player_first_spawn", Event_PlayerFirstSpawn);
		HookEvent("round_end", Event_RoundEnd);
		HookEvent("round_start", Event_RoundStart);
	} else if(!lateLoaded) {
		UnhookEvent("player_first_spawn", Event_PlayerFirstSpawn);
		UnhookEvent("round_end", Event_RoundEnd);
		UnhookEvent("round_start", Event_RoundStart);
	}
}

public Action Event_PlayerFirstSpawn(Event event, const char[] name, bool dontBroadcast) { 
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(client && GetClientTeam(client) != 2 && !isPendingPlay[client]) {
		PrintToChat(client, "You will be put in game next round.");
		isPendingPlay[client] = true;
	}
}

public Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast) {
	CreateTimer(10.0, Timer_CheckItems);
}

public Action Event_RoundEnd(Event event, const char[] name, bool dontBroadcast) {
	static float tpLoc[3];
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i)) {
			GetClientAbsOrigin(i, tpLoc);
			break;
		}
	}

	for(int i = 1; i <= MaxClients; i++) {
		if(isPendingPlay[i]) {
			isPendingPlay[i] = false;
			ChangeClientTeam(i, 2);
			L4D_RespawnPlayer(i);
			TeleportEntity(i, tpLoc, NULL_VECTOR, NULL_VECTOR);
		}
	}
}

///
public Action Timer_CheckItems(Handle h) {
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i)) {
			// Check if has no melee:
			if(GetPlayerWeaponSlot(i, 1) == -1) {
				GiveClientWeapon(i, "knife", false);
			}
			int item = GetPlayerWeaponSlot(i, 0);
			if(item != -1) AcceptEntityInput(item, "Kill");
		}
	}
	PrintToServer("H&S: Pressing buttons");
	int entity = INVALID_ENT_REFERENCE;
	while ((entity = FindEntityByClassname(entity, "func_button")) != INVALID_ENT_REFERENCE) {
		AcceptEntityInput(entity, "Press");
	}
}

stock bool GiveClientWeapon(int client, const char[] wpnName, bool lasers) {
	char sTemp[64];
	float pos[3];
	GetClientAbsOrigin(client, pos);
	Format(sTemp, sizeof(sTemp), "weapon_%s", wpnName);

	int entity = CreateEntityByName(sTemp);
	if( entity != -1 ) {
		DispatchSpawn(entity);
		TeleportEntity(entity, pos, NULL_VECTOR, NULL_VECTOR);

		if(lasers) SetEntProp(entity, Prop_Send, "m_upgradeBitVec", 4);

		EquipPlayerWeapon(client, entity);
		return true;
	}else{
		return false;
	}
}