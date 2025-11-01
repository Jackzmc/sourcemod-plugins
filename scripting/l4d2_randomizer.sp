#pragma semicolon 1
#pragma newdecls required

//#define DEBUG

#define PLUGIN_VERSION "1.0"
#define DEBUG_SCENE_PARSE 1
#define DEBUG_BLOCKERS 1

#include <sourcemod>
#include <sdktools>
//#include <sdkhooks>
#include <profiler>
// #include <json>
#include <ripext>
#include <jutils>
#include <entitylump>
#undef REQUIRE_PLUGIN
#include <editor>

#include <randomizer/defs.sp>

#if defined DEBUG_BLOCKERS
#include <smlib/effects>
#endif
#include <smlib/strings>
#define ENT_PROP_NAME "randomizer"
#define ENT_ENV_NAME "randomizer"
#define ENT_BLOCKER_NAME "randomizer"
#include <gamemodes/ents>

ConVar cvarEnabled; // is map enabled

char currentMap[64];

bool randomizerRan = false;


#include <randomizer/util.sp>
#include <randomizer/gascans.sp> 
#include <randomizer/loader_functions.sp>
#include <randomizer/select_functions.sp>
#include <randomizer/spawn_functions.sp>
#include <randomizer/rbuild.sp>
#include <randomizer/caralarm.sp>

public Plugin myinfo = 
{
	name =  "L4D2 Randomizer", 
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


	RegAdminCmd("sm_rcycle", Command_CycleRandom, ADMFLAG_CHEATS);
	RegAdminCmd("sm_expent", Command_ExportEnt, ADMFLAG_GENERIC);
	RegAdminCmd("sm_rbuild", Command_RandomizerBuild, ADMFLAG_CHEATS);
	RegAdminCmd("sm_randomizer", Command_Debug, ADMFLAG_GENERIC);

	cvarEnabled = CreateConVar("sm_randomizer_enabled", "0");

	HookEvent("player_first_spawn", Event_PlayerFirstSpawn);
	HookEvent("game_end", Event_GameEnd);

	InitGlobals();
}

void Event_GameEnd(Event event, const char[] name ,bool dontBroadcast) {
	// Purge the traverse stack after a campaign is played
	ClearTraverseStack();
}


void Event_PlayerFirstSpawn(Event event, const char[] name ,bool dontBroadcast) {
	if(!randomizerRan) {
		CreateTimer(0.1, Timer_Run);
		randomizerRan = true;
	}
}

public void OnMapStart() {
	g_iLaserIndex = PrecacheModel("materials/sprites/laserbeam.vmt", true);
	GetCurrentMap(currentMap, sizeof(currentMap));

	// We wait a while before running to prevent some edge cases i don't remember
}

public void OnMapEnd() {
	randomizerRan = false;
	g_builder.Cleanup();

	// For maps that players traverse backwards, like hard rain (c4m1_milltown_a -> c4m3_milltown_b )
	// We store the selection of the _a map, to later be loaded for _b maps
	// This is done at end of map just in case a user re-runs the cycle and generates a different selection
	if(g_selection != null) {
		if(IsTraverseMapA(currentMap)) {
			Log("Storing %s in map traversal store", currentMap);
			StoreTraverseSelection(currentMap, g_selection);
		} 
		// We want to store milltown_a twice, so the c4m5_milltown_escape can also pop it off 
		if(StrEqual(currentMap, "c4m1_milltown_a")) {
			StoreTraverseSelection(currentMap, g_selection);
		}
	}
	// don't clear entities because they will be deleted anyway (and errors if you tryq)
	Cleanup(false);
}

public void OnEntityCreated(int entity, const char[] classname) {
	// When a gascan respawns, assign it again
	if(StrEqual(classname, "weapon_gascan")) {
		RequestFrame(Frame_RandomizeGascan, entity);
	}
}

// Runs randomizer with slight delay on start
Action Timer_Run(Handle h) {
	if(cvarEnabled.BoolValue) {
		LoadRunGlobalMap(currentMap, FLAG_NONE);
	}
	return Plugin_Handled;
}

stock int GetLookingEntity(int client, TraceEntityFilter filter) {
	float pos[3], ang[3];
	GetClientEyePosition(client, pos);
	GetClientEyeAngles(client, ang);
	TR_TraceRayFilter(pos, ang, MASK_SOLID, RayType_Infinite, filter, client);
	if(TR_DidHit()) {
		return TR_GetEntityIndex();
	}
	return -1;
}

stock int GetLookingPosition(int client, TraceEntityFilter filter, float pos[3]) {
	float ang[3];
	GetClientEyePosition(client, pos);
	GetClientEyeAngles(client, ang);
	TR_TraceRayFilter(pos, ang, MASK_SOLID, RayType_Infinite, filter, client);
	if(TR_DidHit()) {
		TR_GetEndPosition(pos);
		return TR_GetEntityIndex();
	}
	return -1;
}
Action Command_Debug(int client, int args) {
	// TODO is builder active, selection active, list of traverse pool, can pool
	if(args > 0) {
		char arg[32];
		GetCmdArg(1, arg, sizeof(arg));
		if(StrEqual(arg, "id")) {
			if(g_MapData.IsLoaded()) {
				float origin[3];
				int entity = GetLookingPosition(client, Filter_IgnorePlayer, origin);
				if(entity == 0) {
					ReplyToCommand(client, "No entity found");
					return Plugin_Handled;
				}
				IdentifyEntityScene(client, entity);
			} else {
				ReplyToCommand(client, "No map data loaded");
			}
		} else if(StrEqual(arg, "scenes")) {
			if(g_MapData.IsLoaded()) {
				StringMapSnapshot snapshot = g_MapData.scenesKv.Snapshot();
				char buffer[MAX_SCENE_NAME_LENGTH];
				for(int i = 0; i < snapshot.Length; i++) {
					snapshot.GetKey(i, buffer, sizeof(buffer));
					ReplyToCommand(client, "%d. %s", i, buffer);
				}
				delete snapshot;
			} else {
				ReplyToCommand(client, "No map data loaded");
			}
		} else if(StrEqual(arg, "traverse")) {
			TraverseData trav;
			for(int i = 0; i < g_mapTraverseSelectionStack.Length; i++) {
				g_mapTraverseSelectionStack.GetArray(i, trav, sizeof(trav));
				if(trav.selection == null) {
					ReplyToCommand(client, "  #%d - %s: ERROR", i, trav.map);
				} else {
					ReplyToCommand(client, "  #%d - %s: %d scenes", i, trav.map, trav.selection.Length);
				}
			}
		} else if(StrEqual(arg, "store")) {
			char buffer[64];
			if(args == 1) {
				strcopy(buffer, sizeof(buffer), currentMap);
			} else {
				GetCmdArg(2, buffer, sizeof(buffer));
			}
			StoreTraverseSelection(buffer, g_selection);
			ReplyToCommand(client, "Stored current selection as %s", buffer);
		} else {
			ReplyToCommand(client, "unknown subcommand");
		}
		return Plugin_Handled;
	}
	ReplyToCommand(client, "Enabled: %b", cvarEnabled.BoolValue);
	ReplyToCommand(client, "Map Data: %s", g_MapData.IsLoaded() ? "Loaded" : "-");
	if(g_selection != null) {
		ReplyToCommand(client, "Scene Selection: %d selected", g_selection.Count);
	} else {
		ReplyToCommand(client, "Scene Selection: -");
	}
	ReplyToCommand(client, "Builder Data: %s", g_builder.IsLoaded() ? "Loaded" : "-");
	ReplyToCommand(client, "Traverse Store: count=%d", g_mapTraverseSelectionStack.Length);
	if(g_gascanRespawnQueue != null) {
		ReplyToCommand(client, "Gascan Spawners: count=%d queue_size=%d", g_gascanSpawners.Size, g_gascanRespawnQueue.Length);
	} else {
		ReplyToCommand(client, "Gascan Spawners: count=%d queue_size=-", g_gascanSpawners.Size);
	}
	return Plugin_Handled;
}

public Action Command_CycleRandom(int client, int args) {
	if(args > 0) {
		DeleteCustomEnts();
		int flags = GetCmdArgInt(1);
		if(flags < 0) {
			ReplyToCommand(client, "Invalid flags");
		} else {
			if(args > 1) {
				char buffer[64];
				GetCmdArg(2, buffer, sizeof(buffer));
				LoadRunGlobalMap(buffer, flags | view_as<int>(FLAG_REFRESH));
				PrintCenterText(client, "Cycled %s flags=%d", buffer, flags);
			} else {
				LoadRunGlobalMap(currentMap, flags | view_as<int>(FLAG_REFRESH));
			}
			if(client > 0)
				PrintCenterText(client, "Cycled flags=%d", flags);
		}
	} else {
		if(g_selection == null) {
			ReplyToCommand(client, "No map selection active");
			return Plugin_Handled;
		}
		ReplyToCommand(client, "Active Scenes (%d/%d):", g_selection.Count, g_MapData.scenes.Length);
		SelectedSceneData aScene;
		char buffer[32];
		for(int i = 0; i < g_selection.Count; i++) {
			g_selection.Get(i, aScene);
			buffer[0] = '\0';
			for(int v = 0; v < aScene.selectedVariantIndexes.Length; v++) {
				int index = aScene.selectedVariantIndexes.Get(v);
				Format(buffer, sizeof(buffer), "#%d ", index);
			}
			ReplyToCommand(client, "\t%s: variants %s", aScene.name, buffer);
		}
	}
	return Plugin_Handled;
}

Action Command_ExportEnt(int client, int args) {
	float origin[3];
	int entity = GetLookingPosition(client, Filter_IgnorePlayer, origin);
	float angles[3];
	float size[3];
	char arg1[32];
	GetCmdArg(1, arg1, sizeof(arg1));
	if(entity > 0) {

		GetEntPropVector(entity, Prop_Send, "m_vecOrigin", origin);
		GetEntPropVector(entity, Prop_Send, "m_angRotation", angles);
		GetEntPropVector(entity, Prop_Send, "m_vecMaxs", size);

		char model[128];
		ReplyToCommand(client, "{");
		GetEntityClassname(entity, model, sizeof(model));
		if(StrContains(model, "prop_") == -1) {
			ReplyToCommand(client, "\t\"scale\": [%.2f, %.2f, %.2f],", size[0], size[1], size[2]);
		}
		if(StrEqual(arg1, "hammerid")) {
			int hammerid = GetEntProp(entity, Prop_Data, "m_iHammerID");
			ReplyToCommand(client, "\t\"type\": \"hammerid\",");
			ReplyToCommand(client, "\t\"model\": \"%d\",", hammerid);
		} else if(StrEqual(arg1, "targetname")) {
			GetEntPropString(entity, Prop_Data, "m_iName", model, sizeof(model));
			ReplyToCommand(client, "\t\"type\": \"targetname\",");
			ReplyToCommand(client, "\t\"model\": \"%s\",", model);
		} else {
			GetEntPropString(entity, Prop_Data, "m_ModelName", model, sizeof(model));
			ReplyToCommand(client, "\t\"model\": \"%s\",", model);
		}
		ReplyToCommand(client, "\t\"origin\": [%.2f, %.2f, %.2f],", origin[0], origin[1], origin[2]);
		ReplyToCommand(client, "\t\"angles\": [%.2f, %.2f, %.2f]", angles[0], angles[1], angles[2]);
		ReplyToCommand(client, "}");
	} else {
		if(!StrEqual(arg1, "cursor"))
			GetEntPropVector(client, Prop_Send, "m_vecOrigin", origin);
		GetEntPropVector(client, Prop_Send, "m_angRotation", angles);
		ReplyToCommand(client, "{");
		ReplyToCommand(client, "\t\"type\": \"%s\",", arg1);
		ReplyToCommand(client, "\t\"scale\": [%.2f, %.2f, %.2f],", size[0], size[1], size[2]);
		ReplyToCommand(client, "\t\"origin\": [%.2f, %.2f, %.2f],", origin[0], origin[1], origin[2]);
		ReplyToCommand(client, "\t\"angles\": [%.2f, %.2f, %.2f]", angles[0], angles[1], angles[2]);
		ReplyToCommand(client, "}");
	}
	return Plugin_Handled;
}
Action Command_RandomizerBuild(int client, int args) {
	char arg[64];
	GetCmdArg(1, arg, sizeof(arg));
	if(StrEqual(arg, "new")) {
		JSONObject temp = LoadMapJson(currentMap);
		GetCmdArg(2, arg, sizeof(arg));
		if(temp != null && !StrEqual(arg, "confirm")) {
			delete temp;
			ReplyToCommand(client, "Existing map data found, enter /rbuild new confirm to overwrite.");
			return Plugin_Handled;
		}
		g_builder.Cleanup();
		g_builder.mapData = new JSONObject();
		SaveMapJson(currentMap, g_builder.mapData);
		ReplyToCommand(client, "Started new map data for %s", currentMap);
	} else if(StrEqual(arg, "load")) {
		if(args >= 2) {
			GetCmdArg(2, arg, sizeof(arg));
		} else {
			strcopy(arg, sizeof(arg), currentMap);
		}
		g_builder.Cleanup();
		g_builder.mapData = LoadMapJson(arg);
		strcopy(g_builder.saveAsName, sizeof(g_builder.saveAsName), arg); 
		if(g_builder.mapData != null) {
			ReplyToCommand(client, "Loaded map data for %s", arg);
		} else {
			ReplyToCommand(client, "No map data found for %s", arg);
		}
	} else if(StrEqual(arg, "menu")) {
		OpenMainMenu(client);	
	} else if(g_builder.mapData == null) {
		ReplyToCommand(client, "No map data loaded for %s, either load with /rbuild load, or start new /rbuild new", currentMap);
		return Plugin_Handled;
	} else if(StrEqual(arg, "save")) {
		SaveMapJson(g_builder.saveAsName[0] != '\0' ? g_builder.saveAsName : currentMap, g_builder.mapData);
		ReplyToCommand(client, "Saved %s", currentMap);
	} else if(StrEqual(arg, "scenes")) {
		Command_RandomizerBuild_Scenes(client, args);
	} else if(StrEqual(arg, "sel") || StrEqual(arg, "selector")) {
		if(g_builder.selectedVariantData == null) {
			ReplyToCommand(client, "Please load map data, select a scene and a variant.");
			return Plugin_Handled;
		}
		StartSelector(client, OnSelectorDone);
	} else if(StrEqual(arg, "spawner")) {
		if(g_builder.selectedVariantData == null) {
			ReplyToCommand(client, "Please load map data, select a scene and a variant.");
			return Plugin_Handled;
		}
		StartSpawner(client, OnSpawnerDone);
		ReplyToCommand(client, "Spawn props to add to variant");	
	} else if(StrEqual(arg, "cursor")) {
		if(g_builder.selectedVariantData == null) {
			ReplyToCommand(client, "Please load map data, select a scene and a variant.");
			return Plugin_Handled;
		}
		float origin[3];
		char arg1[32];
		int entity = GetLookingPosition(client, Filter_IgnorePlayer, origin);
		if(entity == 0) {
			ReplyToCommand(client, "No entity found");
			return Plugin_Handled;
		}
		GetCmdArg(2, arg1, sizeof(arg1));
		ExportType exportType = Export_Model;
		if(StrEqual(arg1, "hammerid")) {
			exportType = Export_HammerId;
			ReplyToCommand(client, "Added entity's hammerid to variant #%d", g_builder.selectedVariantIndex);
		} else if(StrEqual(arg1, "targetname")) {
			ReplyToCommand(client, "Added entity's targetname to variant #%d",  g_builder.selectedVariantIndex);
			exportType = Export_TargetName;
		} else {
			ReplyToCommand(client, "Added entity #%d to variant #%d", entity, g_builder.selectedVariantIndex);
		}
		g_builder.AddEntity(entity, exportType);
	} else if(StrEqual(arg, "entityid")) {
		if(g_builder.selectedVariantData == null) {
			ReplyToCommand(client, "Please load map data, select a scene and a variant.");
			return Plugin_Handled;
		}
		char arg1[32];
		int entity = GetCmdArgInt(2);
		if(entity <= 0 && !IsValidEntity(entity)) {
			ReplyToCommand(client, "No entity found");
			return Plugin_Handled;
		}
		GetCmdArg(2, arg1, sizeof(arg1));
		ExportType exportType = Export_Model;
		if(StrEqual(arg1, "hammerid")) {
			exportType = Export_HammerId;
			ReplyToCommand(client, "Added entity's hammerid to variant #%d", g_builder.selectedVariantIndex);
		} else if(StrEqual(arg1, "targetname")) {
			ReplyToCommand(client, "Added entity's targetname to variant #%d",  g_builder.selectedVariantIndex);
			exportType = Export_TargetName;
		} else {
			ReplyToCommand(client, "Added entity #%d to variant #%d", entity, g_builder.selectedVariantIndex);
		}
		g_builder.AddEntity(entity, exportType);
	} else if(StrEqual(arg, "decal")) {
		if(g_builder.selectedVariantData == null) {
			ReplyToCommand(client, "Please load map data, select a scene and a variant.");
			return Plugin_Handled;
		}
		float pos[3];
		GetLookingPosition(client, Filter_IgnorePlayer, pos);
		Effect_DrawBeamBoxRotatableToAll(pos, { -5.0, -5.0, -5.0}, { 5.0, 5.0, 5.0}, NULL_VECTOR, g_iLaserIndex, 0, 0, 0, 40.0, 0.1, 0.1, 0, 0.0, {73, 0, 130, 255}, 0);
		JSONObject obj = new JSONObject();
		obj.SetString("type", "infodecal");
		obj.Set("origin", FromFloatArray(pos, 3));
		obj.SetString("model", "decals/checkpointarrow01_black.vmt");
		g_builder.AddEntityData(obj);
		ReplyToCommand(client, "Added sprite to variant #%d", g_builder.selectedVariantIndex);
	} else if(StrEqual(arg, "fire")) {
		if(g_builder.selectedVariantData == null) {
			ReplyToCommand(client, "Please load map data, select a scene and a variant.");
			return Plugin_Handled;
		}
		float pos[3];
		GetLookingPosition(client, Filter_IgnorePlayer, pos);
		JSONObject obj = new JSONObject();
		obj.SetString("type", "env_fire");
		obj.Set("origin", FromFloatArray(pos, 3));
		g_builder.AddEntityData(obj);
		ReplyToCommand(client, "Added fire to variant #%d", g_builder.selectedVariantIndex);
	} else if(StrEqual(arg, "light")) {
		if(g_builder.selectedVariantData == null) {
			ReplyToCommand(client, "Please load map data, select a scene and a variant.");
			return Plugin_Handled;
		}
		float pos[3];
		int defaultColor[4] = { 255, 255, 255, 255};
		float empty[3];
		float scale[3] = { 100.0, -1.0, -1.0 };
		GetLookingPosition(client, Filter_IgnorePlayer, pos);
		JSONObject obj = new JSONObject();
		obj.SetString("type", "light_dynamic");
		obj.Set("origin", FromFloatArray(pos, 3));
		obj.Set("color", FromIntArray(defaultColor, 4));
		obj.Set("angles", FromFloatArray(empty, 3));
		obj.Set("scale", FromFloatArray(scale, 3));
		g_builder.AddEntityData(obj);
		ReplyToCommand(client, "Added light to variant #%d", g_builder.selectedVariantIndex);
	} else if(StrEqual(arg, "wall")) {
		if(g_builder.selectedVariantData == null) {
			ReplyToCommand(client, "Please load map data, select a scene and a variant.");
			return Plugin_Handled;
		}
		float pos[3];
		float scale[3] = { 15.0, 30.0, 100.0 };
		GetClientAbsOrigin(client, pos);
		JSONObject obj = new JSONObject();
		obj.SetString("type", "env_player_blocker");
		obj.Set("origin", FromFloatArray(pos, 3));
		obj.Set("scale", FromFloatArray(scale, 3));
		g_builder.AddEntityData(obj);
		ReplyToCommand(client, "Added wall to variant #%d", g_builder.selectedVariantIndex);
	} else if(StrEqual(arg, "gascan")) {
		if(g_builder.selectedVariantData == null) {
			ReplyToCommand(client, "Please load map data, select a scene and a variant.");
			return Plugin_Handled;
		}
		float pos[3];
		float ang[3];
		int entity = GetLookingPosition(client, Filter_IgnorePlayer, pos);
		if(entity == 0) {
			GetClientAbsOrigin(client, pos);
			pos[2] += 10.0;
			GetClientEyeAngles(client, ang);
		} else {
			GetEntPropVector(entity, Prop_Send, "m_vecOrigin", pos);
			GetEntPropVector(entity, Prop_Send, "m_angRotation", ang);
		}
		JSONObject obj = new JSONObject();
		obj.SetString("type", "_gascan");
		obj.Set("origin", FromFloatArray(pos, 3));
		obj.Set("angles", FromFloatArray(ang, 3));
		g_builder.AddEntityData(obj);
		ReplyToCommand(client, "Added gascan (%d) to variant #%d", entity, g_builder.selectedVariantIndex);
	} else {
		ReplyToCommand(client, "Unknown arg. Try: new, load, save, scenes, cursor");
	}
	return Plugin_Handled;
}

enum ExportType {
	Export_HammerId,
	Export_TargetName,
	Export_Model,
}
JSONObject ExportEntity(int entity, ExportType exportType = Export_Model) {
	float origin[3], angles[3], size[3];
	GetEntPropVector(entity, Prop_Send, "m_vecOrigin", origin);
	GetEntPropVector(entity, Prop_Send, "m_angRotation", angles);
	GetEntPropVector(entity, Prop_Send, "m_vecMaxs", size);

	char classname[128], model[128];
	JSONObject entityData = new JSONObject();
	GetEntityClassname(entity, classname, sizeof(classname));
	if(StrContains(classname, "prop_") == -1) {
		entityData.Set("scale", FromFloatArray(size, 3));
	}
	if(exportType == Export_HammerId) {
		int hammerid = GetEntProp(entity, Prop_Data, "m_iHammerID");
		entityData.SetString("type", "hammerid");
		char id[16];
		IntToString(hammerid, id, sizeof(id));
		entityData.SetString("model", id);
	} else if(exportType == Export_TargetName) {
		GetEntPropString(entity, Prop_Data, "m_iName", model, sizeof(model));
		entityData.SetString("type", "targetname");
		entityData.SetString("model", model);
	} else {
		GetEntPropString(entity, Prop_Data, "m_ModelName", model, sizeof(model));
		entityData.SetString("type", classname);
		entityData.SetString("model", model);
	}
	entityData.Set("origin", FromFloatArray(origin, 3));
	entityData.Set("angles", FromFloatArray(angles, 3));
	return entityData;
}
JSONObject ExportEntityInput(int entity, const char[] input) {
	char classname[128];
	JSONObject entityData = new JSONObject();
	GetEntityClassname(entity, classname, sizeof(classname));

	int hammerid = GetEntProp(entity, Prop_Data, "m_iHammerID");
	if(hammerid != 0) {
		entityData.SetInt("hammerid", hammerid);
	} else {
		char targetname[128];
		GetEntPropString(entity, Prop_Data, "m_iName", targetname, sizeof(targetname));
		if(targetname[0] != '\0') {
			entityData.SetString("targetname", targetname);
		} else {
			entityData.SetString("classname", classname);
		}
	}
	entityData.SetString("input", input);
	return entityData;
}

bool OnSpawnerDone(int client, int entity, CompleteType result) {
	PrintToServer("Randomizer OnSpawnerDone");
	if(result == Complete_PropSpawned && entity > 0) {
		JSONObject entityData = ExportEntity(entity, Export_Model);
		JSONArray entities = view_as<JSONArray>(g_builder.selectedVariantData.Get("entities"));
		entities.Push(entityData);
		ReplyToCommand(client, "Added entity to variant");
		RemoveEntity(entity);
	} 
	return result == Complete_PropSpawned;
}
void OnSelectorDone(int client, ArrayList entities) {
	JSONArray entArray = view_as<JSONArray>(g_builder.selectedVariantData.Get("entities"));
	JSONArray inputArray = g_builder.selectedVariantData.HasKey("inputs") ? view_as<JSONArray>(g_builder.selectedVariantData.Get("inputs")) : null;
	if(entities != null) {
		JSONObject entityData;
		char classname[128];
		for(int i = 0; i < entities.Length; i++) {
			int ref = entities.Get(i);
			GetEntityClassname(ref, classname, sizeof(classname));
			if(StrEqual(classname, "func_simpleladder")) {
				if(inputArray == null) {
					inputArray = new JSONArray();
					g_builder.selectedVariantData.Set("inputs", inputArray);
				}
				entityData = ExportEntityInput(ref, "_allow_ladder");
				inputArray.Push(entityData);
			} else {
				// If there is a hammerid (> 0), then it's built on the map - we don't want to delete it
				// If it is 0, it was spawned, probably by prop spawner, so we remove it 
				int hammerId = GetEntProp(ref, Prop_Data, "m_iHammerID");
				entityData = ExportEntity(ref, hammerId > 0 ? Export_HammerId : Export_Model);
				entArray.Push(entityData);
				if(hammerId == 0)
					RemoveEntity(ref);
			}
			delete entityData; //?
		}
		PrintToChat(client, "Added %d entities to variant", entities.Length);
		delete entities;
	}
}



void Command_RandomizerBuild_Scenes(int client, int args) {
	char arg[16];
	GetCmdArg(2, arg, sizeof(arg));
	if(StrEqual(arg, "new")) {
		if(args < 4) {
			ReplyToCommand(client, "Syntax: /rbuild scenes new <name> <chance 0.0-1.0>");
		} else {
			char name[64];
			GetCmdArg(3, name, sizeof(name));
			GetCmdArg(4, arg, sizeof(arg));
			float chance = StringToFloat(arg);
			JSONObject scene = new JSONObject();
			scene.SetFloat("chance", chance);
			scene.Set("variants", new JSONArray());
			g_builder.mapData.Set(name, scene);
			g_builder.SelectScene(name);
			JSONArray variants = view_as<JSONArray>(g_builder.selectedSceneData.Get("variants"));

			JSONObject variantObj = new JSONObject();
			variantObj.SetInt("weight", 1);
			variantObj.Set("entities", new JSONArray());
			variants.Push(variantObj);
			g_builder.SelectVariant(0);
			ReplyToCommand(client, "Created & selected scene & variant %s#0", name);
			StartSelector(client, OnSelectorDone);
		}
	} else if(StrEqual(arg, "select") || StrEqual(arg, "load") || StrEqual(arg, "choose")) {
		GetCmdArg(3, arg, sizeof(arg));
		if(g_builder.SelectScene(arg)) {
			int variantIndex;
			if(GetCmdArgIntEx(4, variantIndex)) {
				if(g_builder.SelectVariant(variantIndex)) {
					ReplyToCommand(client, "Selected scene: %s#%d", arg, variantIndex);
				} else {
					ReplyToCommand(client, "Unknown variant for scene");
				}
			} else {
				ReplyToCommand(client, "Selected scene: %s", arg);
			}
		} else {
			ReplyToCommand(client, "No scene found");
		}
	} else if(StrEqual(arg, "variants")) {
		Command_RandomizerBuild_Variants(client, args);
	} else if(args > 1) {
		ReplyToCommand(client, "Unknown argument, try: new, select, variants");
	} else {
		ReplyToCommand(client, "Scenes:");
		JSONObjectKeys iterator = g_builder.mapData.Keys();
		while(iterator.ReadKey(arg, sizeof(arg))) {
			if(StrEqual(arg, g_builder.selectedSceneId)) {
				ReplyToCommand(client, "\t%s (selected)", arg);
			} else {
				ReplyToCommand(client, "\t%s", arg);
			}
		}
	}
}

void Command_RandomizerBuild_Variants(int client, int args) {
	#pragma unused args
	if(g_builder.selectedSceneId[0] == '\0') {
		ReplyToCommand(client, "No scene selected, select with /rbuild groups select <group>");
		return;
	}
	char arg[16];
	GetCmdArg(3, arg, sizeof(arg));
	if(StrEqual(arg, "new")) {
		// /rbuild group variants new [weight]
		int weight;
		if(!GetCmdArgIntEx(4, weight)) {
			weight = 1;
		}
		JSONArray variants = view_as<JSONArray>(g_builder.selectedSceneData.Get("variants"));
		JSONObject variantObj = new JSONObject();
		variantObj.SetInt("weight", weight);
		variantObj.Set("entities", new JSONArray());
		int index = variants.Push(variantObj);
		g_builder.SelectVariant(index);
		ReplyToCommand(client, "Created variant #%d", index);
	} else if(StrEqual(arg, "select")) {
		int index = GetCmdArgInt(4);
		if(g_builder.SelectVariant(index)) {
			ReplyToCommand(client, "Selected variant: %s#%d", g_builder.selectedSceneId, index);
		} else {
			ReplyToCommand(client, "No variant found");
		}
	} else {
		ReplyToCommand(client, "Variants:");
		JSONObject variantObj;
		JSONArray variants = view_as<JSONArray>(g_builder.selectedSceneData.Get("variants"));
		for(int i = 0; i < variants.Length; i++) {
			variantObj = view_as<JSONObject>(variants.Get(i));
			int weight = 1;
			if(variantObj.HasKey("weight"))
				weight = variantObj.GetInt("weight");
			JSONArray entities = view_as<JSONArray>(variantObj.Get("entities"));
			ReplyToCommand(client, "  #%d. [W:%d] [#E:%d]", i, weight, entities.Length);
		}
	}
}

void spawnEntity(VariantEntityData entity) {
	if(entity.type[0] == '_') {
		if(StrEqual(entity.type, "_gascan")) {
			AddGascanSpawner(entity);
		} else if(StrContains(entity.type, "_car") != -1) {
			SpawnCar(entity);
		} else {
			Log("WARN: Unknown custom entity type \"%s\", skipped", entity.type);
		}
	} else if(StrEqual(entity.type, "hammerid")) {
		int targetId = StringToInt(entity.model);
		if(targetId > 0) {
			int ent = -1;
			while((ent = FindEntityByClassname(ent, "*")) != INVALID_ENT_REFERENCE) {
				int hammerId = GetEntProp(ent, Prop_Data, "m_iHammerID");
				if(hammerId == targetId) {
					Debug("moved entity (hammerid=%d) to %.0f %.0f %.0f rot %.0f %.0f %.0f", targetId, entity.origin[0], entity.origin[1], entity.origin[2], entity.angles[0], entity.angles[1], entity.angles[2]);
					TeleportEntity(ent, entity.origin, entity.angles, NULL_VECTOR);
					return;
				}
			}
		}
		Debug("Warn: Could not find entity (hammerid=%d) (model=%s)", targetId, entity.model);
	} else if(StrEqual(entity.type, "targetname")) {
		int ent = -1;
		char targetname[64];
		bool found = false;
		while((ent = FindEntityByClassname(ent, "*")) != INVALID_ENT_REFERENCE) {
			GetEntPropString(ent, Prop_Data, "m_iName", targetname, sizeof(targetname));
			if(StrEqual(entity.model, targetname)) {
				Debug("moved entity (targetname=%s) to %.0f %.0f %.0f rot %.0f %.0f %.0f", entity.model, entity.origin[0], entity.origin[1], entity.origin[2], entity.angles[0], entity.angles[1], entity.angles[2]);
				TeleportEntity(ent, entity.origin, entity.angles, NULL_VECTOR);
				found = true;
			}
		}
		if(!found)
			Debug("Warn: Could not find entity (targetname=%s)", entity.model);
	} else if(StrEqual(entity.type, "classname")) {
		int ent = -1;
		char classname[64];
		bool found;
		while((ent = FindEntityByClassname(ent, classname)) != INVALID_ENT_REFERENCE) {
			Debug("moved entity (classname=%s) to %.0f %.0f %.0f rot %.0f %.0f %.0f", entity.model, entity.origin[0], entity.origin[1], entity.origin[2], entity.angles[0], entity.angles[1], entity.angles[2]);
			TeleportEntity(ent, entity.origin, entity.angles, NULL_VECTOR);
			found = true;
		}
		if(!found)
			Debug("Warn: Could not find entity (classname=%s)", entity.model);
	}  else if(StrEqual(entity.type, "env_fire")) {
		Debug("spawning \"%s\" at (%.1f %.1f %.1f) rot (%.0f %.0f %.0f)", entity.type, entity.origin[0], entity.origin[1], entity.origin[2], entity.angles[0], entity.angles[1], entity.angles[2]);
		R_CreateFire(entity);
	} else if(StrEqual(entity.type, "light_dynamic")) {
		R_CreateLight(entity);	
		Effect_DrawBeamBoxRotatableToAll(entity.origin, { -5.0, -5.0, -5.0}, { 5.0, 5.0, 5.0}, NULL_VECTOR, g_iLaserIndex, 0, 0, 0, 40.0, 0.1, 0.1, 0, 0.0, {255, 255, 0, 255}, 0);
	} else if(StrEqual(entity.type, "env_physics_blocker") || StrEqual(entity.type, "env_player_blocker")) {
		R_CreateEnvBlockerScaled(entity);
	} else if(StrEqual(entity.type, "infodecal")) {
		Effect_DrawBeamBoxRotatableToAll(entity.origin, { -1.0, -5.0, -5.0}, { 1.0, 5.0, 5.0}, NULL_VECTOR, g_iLaserIndex, 0, 0, 0, 40.0, 0.1, 0.1, 0, 0.0, {73, 0, 130, 255}, 0);
		R_CreateDecal(entity);
	} else if(StrContains(entity.type, "weapon_") == 0 || StrContains(entity.type, "prop_") == 0 || StrEqual(entity.type, "prop_fuel_barrel")) {
		if(entity.model[0] == '\0') {
			LogError("Missing model for entity with type \"%s\"", entity.type);
			return;
		} else if(!PrecacheModel(entity.model)) {
			LogError("Precache of entity model \"%s\" with type \"%s\" failed", entity.model, entity.type);
			return;
		}
		R_CreateProp(entity);
	} else if(StrEqual(entity.type, "move_rope")) {
		if(!PrecacheModel(entity.model)) {
			LogError("Precache of entity model \"%s\" with type \"%s\" failed", entity.model, entity.type);
			return;
		} else if(entity.keyframes == null) {
			// should not happen
			LogError("rope entity has no keyframes", entity.keyframes);
			return;
		}
		CreateRope(entity);
	} else if(StrEqual(entity.type, "script_nav_blocker")) {
		Randomizer_CreateNavBlocker(entity);
	} else {
		LogError("Unsupported entity type \"%s\"", entity.type);
	}
}

int Randomizer_CreateNavBlocker(VariantEntityData entity) {
	int blocker = CreateNavBlocker(entity.targetname, entity.origin, entity.angles, entity.scale, -1, false);
	entity.ApplyProperties(blocker);
	return blocker;
}
int CreateNavBlocker(const char[] targetname, const float origin[3], const float angles[3], const float size[3], int teamToBlock, bool affectsFlow) {
	int entity = CreateEntityByName("script_nav_blocker");
	DispatchKeyValue(entity, "targetname", targetname);
	DispatchKeyValueVector(entity, "extent", size);
	DispatchKeyValueVector(entity, "origin", origin);
	DispatchKeyValueVector(entity, "angles", angles);
	DispatchKeyValueInt(entity, "teamToBlock", teamToBlock);
	DispatchKeyValueInt(entity, "affectsFlow", affectsFlow ? 1 : 0);
	DispatchSpawn(entity);
	return entity;
}	

int CreateRope(VariantEntityData data) {
	char targetName[32], nextKey[32];
	Format(targetName, sizeof(targetName), "randomizer_rope%d", g_ropeIndex);
	Format(nextKey, sizeof(nextKey), "randomizer_rope%d_0", g_ropeIndex);
	int entity = _CreateRope("move_rope", targetName, nextKey, data.model, data.origin);
	float pos[3];
	for(int i = 0; i < data.keyframes.Length; i++) {
		nextKey[0] = '\0';
		Format(targetName, sizeof(targetName), "randomizer_rope%d_%d", g_ropeIndex, i);
		if(i < data.keyframes.Length - 1) {
			Format(nextKey, sizeof(nextKey), "randomizer_rope%d_%d", g_ropeIndex, i + 1);
		}
		data.keyframes.GetArray(i, pos, sizeof(pos));
		_CreateRope("move_rope", targetName, nextKey, data.model, pos);
	}
	Debug("created rope #%d with %d keyframes. entid:%d", g_ropeIndex, data.keyframes.Length, entity);
	g_ropeIndex++;
	return entity;
}
int _CreateRope(const char[] type, const char[] targetname, const char[] nextKey, const char[] texture, const float origin[3]) {
	int entity = CreateEntityByName(type);
	if(entity == -1) return -1;
	Debug("_createRope(\"%s\", \"%s\", \"%s\", \"%s\", %.0f %.0f %.0f", type, targetname, nextKey, texture, origin[0], origin[1], origin[2]);
	DispatchKeyValue(entity, "targetname", targetname);
	DispatchKeyValue(entity, "NextKey", nextKey);
	DispatchKeyValue(entity, "RopeMaterial", texture);
	DispatchKeyValueInt(entity, "Type", 0);
	DispatchKeyValueFloat(entity, "Width", 2.0);
	DispatchKeyValueInt(entity, "Breakable", 0); 
	DispatchKeyValueInt(entity, "Slack", 0);
	DispatchKeyValueInt(entity, "Type", 0);
	DispatchKeyValueInt(entity, "TextureScale", 2);
	DispatchKeyValueInt(entity, "Subdiv", 2); 
	DispatchKeyValueInt(entity, "MoveSpeed", 0);
	DispatchKeyValueInt(entity, "Dangling", 0);
	DispatchKeyValueInt(entity, "Collide", 0);
	DispatchKeyValueInt(entity, "Barbed", 0); 
	DispatchKeyValue(entity, "PositionInterpolator", "2");
	// DispatchKeyValueFloat( entity, "m_RopeLength", 10.0 ); 
	TeleportEntity(entity, origin, NULL_VECTOR, NULL_VECTOR);
	if(!DispatchSpawn(entity)) {
		return -1;
	}
	return entity;
}

// void DebugBox(const float origin[3], const float scale[3], int color[4]) {
// 	Effect_DrawBeamBoxRotatableToAll(entity.origin, { -5.0, -5.0, -5.0}, { 5.0, 5.0, 5.0}, NULL_VECTOR, g_iLaserIndex, 0, 0, 0, 40.0, 0.1, 0.1, 0, 0.0, {255, 255, 0, 255}, 0);
// }
		
void Debug(const char[] format, any ...) {
    #if defined DEBUG_SCENE_PARSE
	char buffer[192];
	
	VFormat(buffer, sizeof(buffer), format, 2);
	
	PrintToServer("[Randomizer::Debug] %s", buffer);
	PrintToConsoleAll("[Randomizer::Debug] %s", buffer);
	
    #endif
}

void Log(const char[] format, any ...) {
	char buffer[192];
	
	VFormat(buffer, sizeof(buffer), format, 2);
	
	PrintToServer("[Randomizer] %s", buffer);
}

void Cleanup(bool clearEntities = true) {
	if(g_MapData.scenes != null) {
		g_MapData.Cleanup();
	}
	delete g_MapData.lumpEdits;
	delete g_MapData.gascanSpawners;

	// Cleanup all alarm car entities:
	if(clearEntities) {
		int entity = -1;
		char targetname[128];
		while((entity = FindEntityByClassname(entity, "*")) != INVALID_ENT_REFERENCE) {
			if(!IsValidEntity(entity)) continue;
			GetEntPropString(entity, Prop_Data, "m_iName", targetname, sizeof(targetname));
			if(StrContains(targetname, "randomizer_") != -1) {
				RemoveEntity(entity);
			}
		}
		DeleteCustomEnts();
	}
	// TODO: delete car alarms

	g_gascanSpawners.Clear();
	delete g_gascanRespawnQueue;
}