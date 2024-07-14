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

int g_iLaserIndex;
#if defined DEBUG_BLOCKERS
#include <smlib/effects>
#endif
#define ENT_PROP_NAME "l4d2_randomizer"
#define ENT_ENV_NAME "l4d2_randomizer"
#define ENT_BLOCKER_NAME "l4d2_randomizer"
#include <gamemodes/ents>

#define MAX_SCENE_NAME_LENGTH 32
#define MAX_INPUTS_CLASSNAME_LENGTH 64


ConVar cvarEnabled;
enum struct ActiveSceneData {
	char name[MAX_SCENE_NAME_LENGTH];
	int variantIndex;
}
MapData g_MapData;
BuilderData g_builder;
char currentMap[64];

enum struct BuilderData {
	JSONObject mapData;

	JSONObject selectedSceneData;
	char selectedSceneId[64];

	JSONObject selectedVariantData;
	int selectedVariantIndex;

	void Cleanup() {
		this.selectedSceneData = null;
		this.selectedVariantData = null;
		this.selectedVariantIndex = -1;
		this.selectedSceneId[0] = '\0';
		if(this.mapData != null)
			delete this.mapData;
			// JSONcleanup_and_delete(this.mapData);
	}

	bool SelectScene(const char[] group) {
		if(!g_builder.mapData.HasKey(group)) return false;
		this.selectedSceneData = view_as<JSONObject>(g_builder.mapData.Get(group));
		strcopy(this.selectedSceneId, sizeof(this.selectedSceneId), group);
		return true;
	}

	/**
	 * Select a variant, enter -1 to not select any (scene's entities)
	 */
	bool SelectVariant(int index = -1) {
		if(this.selectedSceneData == null) LogError("SelectVariant called, but no group selected");
		JSONArray variants = view_as<JSONArray>(this.selectedSceneData.Get("variants"));
		if(index >= variants.Length) return false;
		else if(index < -1) return false;
		else if(index > -1) {
			this.selectedVariantData = view_as<JSONObject>(variants.Get(index));
		} else {
			this.selectedVariantData = null;
		}
		this.selectedVariantIndex = index;
		return true;
	}

	void AddEntity(int entity, ExportType exportType = Export_Model) {
		JSONArray entities;
		if(g_builder.selectedVariantData == null) {
			// Create <scene>.entities if doesn't exist:
			if(!g_builder.selectedSceneData.HasKey("entities")) {
				g_builder.selectedSceneData.Set("entities", new JSONArray());
			} 
			entities = view_as<JSONArray>(g_builder.selectedSceneData.Get("entities")); 
		} else {
			entities = view_as<JSONArray>(g_builder.selectedVariantData.Get("entities"));
		}
		JSONObject entityData = ExportEntity(entity, Export_Model);
		entities.Push(entityData);
	}
}

#include <randomizer/rbuild.sp>

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

	cvarEnabled = CreateConVar("sm_randomizer_enabled", "0");

	g_MapData.activeScenes = new ArrayList(sizeof(ActiveSceneData));
}


// TODO: on round start
public void OnMapStart() {
	g_iLaserIndex = PrecacheModel("materials/sprites/laserbeam.vmt", true);
	GetCurrentMap(currentMap, sizeof(currentMap));
	if(cvarEnabled.BoolValue)
		CreateTimer(5.0, Timer_Run);
}

public void OnMapEnd() {
	g_builder.Cleanup();
	Cleanup();
}

public void OnMapInit(const char[] map) {
	// if(cvarEnabled.BoolValue) {
	// 	if(LoadMapData(currentMap, FLAG_NONE) && g_MapData.lumpEdits.Length > 0) {
	// 		Log("Found %d lump edits, running...", g_MapData.lumpEdits.Length);
	// 		LumpEditData lump;
	// 		for(int i = 0; i < g_MapData.lumpEdits.Length; i++) {
	// 			g_MapData.lumpEdits.GetArray(i, lump);
	// 			lump.Trigger();
	// 		}
	// 		hasRan = true;
	// 	}
	// }
}

public void OnConfigsExecuted() {

}

Action Timer_Run(Handle h) {
	if(cvarEnabled.BoolValue)
		RunMap(currentMap, FLAG_NONE);
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


public Action Command_CycleRandom(int client, int args) {
	if(args > 0) {
		DeleteCustomEnts();

		int flags = GetCmdArgInt(1) | view_as<int>(FLAG_REFRESH);
		RunMap(currentMap, flags);
		if(client > 0)
			PrintCenterText(client, "Cycled flags=%d", flags);
	} else {
		ReplyToCommand(client, "Active Scenes:");
		ActiveSceneData scene;
		for(int i = 0; i < g_MapData.activeScenes.Length; i++) {
			g_MapData.activeScenes.GetArray(i, scene);
			ReplyToCommand(client, "\t%s: variant #%d", scene.name, scene.variantIndex);
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

		char model[64];
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
		if(g_builder.mapData != null) {
			ReplyToCommand(client, "Loaded map data for %s", arg);
		} else {
			ReplyToCommand(client, "No map data found for %s", arg);
		}
	} else if(StrEqual(arg, "menu")) {
		OpenMainMenu(client);	
	} else if(g_builder.mapData == null) {
		ReplyToCommand(client, "No map data for %s, either load with /rbuild load, or start new /rbuild new", currentMap);
		return Plugin_Handled;
	} else if(StrEqual(arg, "save")) {
		SaveMapJson(currentMap, g_builder.mapData);
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
		GetCmdArg(2, arg1, sizeof(arg1));
		ExportType exportType = Export_Model;
		if(StrEqual(arg1, "hammerid")) {
			exportType = Export_HammerId;
		} else if(StrEqual(arg1, "targetname")) {
			exportType = Export_TargetName;
		}
		if(entity > 0) {
			g_builder.AddEntity(entity, exportType);
			ReplyToCommand(client, "Added entity #%d to variant #%d", entity, g_builder.selectedVariantIndex);
		} else {
			ReplyToCommand(client, "No entity found");
		}
	} else if(StrEqual(arg, "entityid")) {
		char arg1[32];
		int entity = GetCmdArgInt(2);
		GetCmdArg(3, arg1, sizeof(arg));
		ExportType exportType = Export_Model;
		if(StrEqual(arg1, "hammerid")) {
			exportType = Export_HammerId;
		} else if(StrEqual(arg1, "targetname")) {
			exportType = Export_TargetName;
		}
		if(entity > 0) {
			g_builder.AddEntity(entity, exportType);
			ReplyToCommand(client, "Added entity #%d to variant #%d", entity, g_builder.selectedVariantIndex);
		} else {
			ReplyToCommand(client, "No entity found");
		}
	} else {
		ReplyToCommand(client, "Unknown arg. Try: new, load, save, scenes, cursor");
	}
	return Plugin_Handled;
}

enum ExportType {
	Export_HammerId,
	Export_TargetName,
	Export_Model
}
JSONObject ExportEntity(int entity, ExportType exportType = Export_Model) {
	float origin[3], angles[3], size[3];
	GetEntPropVector(entity, Prop_Send, "m_vecOrigin", origin);
	GetEntPropVector(entity, Prop_Send, "m_angRotation", angles);
	GetEntPropVector(entity, Prop_Send, "m_vecMaxs", size);

	char model[64];
	JSONObject entityData = new JSONObject();
	GetEntityClassname(entity, model, sizeof(model));
	if(StrContains(model, "prop_") == -1) {
		entityData.Set("scale", VecToArray(size));
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
		entityData.SetString("model", model);
	}
	entityData.Set("origin", VecToArray(origin));
	entityData.Set("angles", VecToArray(angles));
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
	if(entities != null) {
		JSONObject entityData;
		for(int i = 0; i < entities.Length; i++) {
			int ref = entities.Get(i);
			entityData = ExportEntity(ref, Export_Model);
			entArray.Push(entityData);
			delete entityData; //?
			RemoveEntity(ref);
		}
		PrintToChat(client, "Added %d entities to variant", entities.Length);
		delete entities;
	}
}

JSONArray VecToArray(float vec[3]) {
	JSONArray arr = new JSONArray();
	arr.PushFloat(vec[0]);
	arr.PushFloat(vec[1]);
	arr.PushFloat(vec[2]);
	return arr;
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


enum struct SceneData {
	char name[MAX_SCENE_NAME_LENGTH];
	float chance;
	char group[MAX_SCENE_NAME_LENGTH];
	ArrayList variants;

	void Cleanup() {
		g_MapData.activeScenes.Clear();
		SceneVariantData choice;
		for(int i = 0; i < this.variants.Length; i++) {
			this.variants.GetArray(i, choice);
			choice.Cleanup();
		}
		delete this.variants;
	}
}

enum struct SceneVariantData {
	int weight;
	ArrayList inputsList;
	ArrayList entities;
	ArrayList forcedScenes;

	void Cleanup() {
		delete this.inputsList;
		delete this.entities;
		delete this.forcedScenes;
	}
}

enum struct VariantEntityData {
	char type[32];
	char model[64];
	float origin[3];
	float angles[3];
	float scale[3];
	int color[4];
}

enum InputType {
	Input_Classname,
	Input_Targetname,
	Input_HammerId
}
enum struct VariantInputData {
	char name[MAX_INPUTS_CLASSNAME_LENGTH];
	InputType type; 
	char input[32];

	void Trigger() {
		int entity = -1;
		switch(this.type) {
			case Input_Classname: {
				entity = FindEntityByClassname(entity, this.name);
				this._trigger(entity);
			}
			case Input_Targetname: {
				char targetname[32];
				while((entity = FindEntityByClassname(entity, "*")) != INVALID_ENT_REFERENCE) {
					GetEntPropString(entity, Prop_Data, "m_iName", targetname, sizeof(targetname));
					if(StrEqual(targetname, this.name)) {
						this._trigger(entity);
					}
				}
			}
			case Input_HammerId: {
				int targetId = StringToInt(this.name);
				while((entity = FindEntityByClassname(entity, "*")) != INVALID_ENT_REFERENCE) {
					int hammerId = GetEntProp(entity, Prop_Data, "m_iHammerID");
					if(hammerId == targetId ) {
						this._trigger(entity);
						break;
					}
				}
			}
		}
	}

	void _trigger(int entity) {
		if(entity > 0 && IsValidEntity(entity)) {
			if(StrEqual(this.input, "_allow_ladder")) {
				if(HasEntProp(entity, Prop_Send, "m_iTeamNum")) {
					SetEntProp(entity, Prop_Send, "m_iTeamNum", 0);
				} else {
					Log("Warn: Entity (%d) with id \"%s\" has no teamnum for \"_allow_ladder\"", entity, this.name);
				}
			} else if(StrEqual(this.input, "_lock")) {
				AcceptEntityInput(entity, "Close");
				AcceptEntityInput(entity, "Lock");
			} else if(StrEqual(this.input, "_lock_nobreak")) {
				AcceptEntityInput(entity, "Close");
				AcceptEntityInput(entity, "Lock");
				AcceptEntityInput(entity, "SetUnbreakable");
			}else {
				char cmd[32];
				// Split input "a b" to a with variant "b"
				int len = SplitString(this.input, " ", cmd, sizeof(cmd));
				if(len > -1) SetVariantString(this.input[len]);
				
				Debug("_trigger(%d): %s (v=%s)", entity, this.input, cmd);
				AcceptEntityInput(entity, this.input);
			}
		}
	}
}

enum struct LumpEditData {
	char name[MAX_INPUTS_CLASSNAME_LENGTH];
	InputType type; 
	char action[32];
	char value[64];

	int _findLumpIndex(int startIndex = 0, EntityLumpEntry entry) {
		int length = EntityLump.Length();
		char val[64];
		Debug("Scanning for \"%s\" (type=%d)", this.name, this.type);
		for(int i = startIndex; i < length; i++) {
			entry = EntityLump.Get(i);
			int index = entry.FindKey("hammerid");
			if(index != -1) {
				entry.Get(index, "", 0, val, sizeof(val));
				if(StrEqual(val, this.name)) {
					return i;
				}
			}

			index = entry.FindKey("classname");
			if(index != -1) {
				entry.Get(index, "", 0, val, sizeof(val));
				Debug("%s vs %s", val, this.name);
				if(StrEqual(val, this.name)) {
					return i;
				}
			}

			index = entry.FindKey("targetname");
			if(index != -1) {
				entry.Get(index, "", 0, val, sizeof(val));
				if(StrEqual(val, this.name)) {
					return i;
				}
			}
			delete entry;
		}
		Log("Warn: Could not find any matching lump for \"%s\" (type=%d)", this.name, this.type);
		return -1;
	}

	void Trigger() {
		int index = 0;
		EntityLumpEntry entry;
		while((index = this._findLumpIndex(index, entry) != -1)) {
			// for(int i = 0; i < entry.Length; i++) {
			// 	entry.Get(i, a, sizeof(a), v, sizeof(v));
			// 	Debug("%s=%s", a, v);
			// }
			this._trigger(entry);
		}
	}

	void _updateKey(EntityLumpEntry entry, const char[] key, const char[] value) {
		int index = entry.FindKey(key);
		if(index != -1) {
			Debug("update key %s = %s", key, value);
			entry.Update(index, key, value);
		}
	}

	void _trigger(EntityLumpEntry entry) {
		if(StrEqual(this.action, "setclassname")) {
			this._updateKey(entry, "classname", this.value);
		}

		delete entry;
	}
}

enum struct MapData {
	StringMap scenesKv;
	ArrayList scenes;
	ArrayList lumpEdits;
	ArrayList activeScenes;
}

enum loadFlags {
	FLAG_NONE = 0,
	FLAG_ALL_SCENES = 1, // Pick all scenes, no random chance
	FLAG_ALL_VARIANTS = 2, // Pick all variants (for debug purposes),
	FLAG_REFRESH = 4, // Load data bypassing cache
	FLAG_FORCE_ACTIVE = 8 // Similar to ALL_SCENES, bypasses % chance
}

// Reads (mapname).json file and parses it
public JSONObject LoadMapJson(const char[] map) {
	Debug("Loading config for %s", map);
	char filePath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, filePath, sizeof(filePath), "data/randomizer/%s.json", map);
	if(!FileExists(filePath)) {
		Log("[Randomizer] No map config file (data/randomizer/%s.json), not loading", map);
		return null;
	}

	JSONObject data = JSONObject.FromFile(filePath);
	if(data == null) {
		LogError("Could not parse map config file (data/randomizer/%s.json)", map);
		return null;
	}
	return data;
}
public void SaveMapJson(const char[] map, JSONObject json) {
	Debug("Saving config for %s", map);
	char filePath[PLATFORM_MAX_PATH], filePathTemp[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, filePathTemp, sizeof(filePath), "data/randomizer/%s.json.tmp", map);
	BuildPath(Path_SM, filePath, sizeof(filePath), "data/randomizer/%s.json", map);

	json.ToFile(filePathTemp, JSON_INDENT(4));
	RenameFile(filePath, filePathTemp);
	SetFilePermissions(filePath, FPERM_U_WRITE | FPERM_U_READ | FPERM_G_WRITE | FPERM_G_READ | FPERM_O_READ);
}

public bool LoadMapData(const char[] map, int flags) {
	JSONObject data = LoadMapJson(map);
	if(data == null) {
		return false;
	}

	Debug("Starting parsing json data");

	Cleanup();
	g_MapData.scenes = new ArrayList(sizeof(SceneData));
	g_MapData.scenesKv = new StringMap();
	g_MapData.lumpEdits = new ArrayList(sizeof(LumpEditData));
	g_MapData.activeScenes.Clear();

	Profiler profiler = new Profiler();
	profiler.Start();

	JSONObjectKeys iterator = data.Keys();
	char key[32];
	while(iterator.ReadKey(key, sizeof(key))) {
		if(key[0] == '_') {
			if(StrEqual(key, "_lumps")) {
				JSONArray lumpsList = view_as<JSONArray>(data.Get(key));
				if(lumpsList != null) {
					for(int l = 0; l < lumpsList.Length; l++) {
						loadLumpData(g_MapData.lumpEdits, view_as<JSONObject>(lumpsList.Get(l)));
					}
				}
			} else {
				Debug("Unknown special entry \"%s\", skipping", key);
			}
		} else {
			// if(data.GetType(key) != JSONType_Object) {
			// 	Debug("Invalid normal entry \"%s\" (not an object), skipping", key);
			// 	continue;
			// }
			JSONObject scene = view_as<JSONObject>(data.Get(key));
			// Parses scene data and inserts to scenes
			loadScene(key, scene);
		}
	}

	delete data;
	profiler.Stop();
	Log("Parsed map file for %s(%d) and found %d scenes in %.4f seconds", map, flags, g_MapData.scenes.Length, profiler.Time);
	delete profiler;
	return true;
}

// Calls LoadMapData (read&parse (mapname).json) then select scenes
public bool RunMap(const char[] map, int flags) {
	if(g_MapData.scenes == null || flags & view_as<int>(FLAG_REFRESH)) {
		if(!LoadMapData(map, flags)) {
			return false;
		}
	}
	Profiler profiler = new Profiler();

	profiler.Start();
	selectScenes(flags);
	profiler.Stop();

	Log("Done processing in %.4f seconds", g_MapData.scenes.Length, profiler.Time);
	return true;
}

void loadScene(const char key[MAX_SCENE_NAME_LENGTH], JSONObject sceneData) {
	SceneData scene;
	scene.name = key;
	scene.chance = sceneData.GetFloat("chance");
	if(scene.chance < 0.0 || scene.chance > 1.0) {
		LogError("Scene \"%s\" has invalid chance (%f)", scene.name, scene.chance);
		return;
	}
	// TODO: load "entities", merge with choice.entities
	sceneData.GetString("group", scene.group, sizeof(scene.group));
	scene.variants = new ArrayList(sizeof(SceneVariantData));
	if(!sceneData.HasKey("variants")) {
		ThrowError("Failed to load: Scene \"%s\" has missing \"variants\" array", scene.name);
		return;
	}
	JSONArray entities;
	if(sceneData.HasKey("entities")) {
		entities = view_as<JSONArray>(sceneData.Get("entities"));
	}

	JSONArray variants = view_as<JSONArray>(sceneData.Get("variants"));
	for(int i = 0; i < variants.Length; i++) {
		// Parses choice and loads to scene.choices
		loadChoice(scene, view_as<JSONObject>(variants.Get(i)), entities);
	}
	g_MapData.scenes.PushArray(scene);
	g_MapData.scenesKv.SetArray(scene.name, scene, sizeof(scene));
}

void loadChoice(SceneData scene, JSONObject choiceData, JSONArray extraEntities) {
	SceneVariantData choice;
	choice.weight = 1;
	if(choiceData.HasKey("weight"))
		choice.weight = choiceData.GetInt("weight");
	choice.entities = new ArrayList(sizeof(VariantEntityData));
	choice.inputsList = new ArrayList(sizeof(VariantInputData));
	choice.forcedScenes = new ArrayList(ByteCountToCells(MAX_SCENE_NAME_LENGTH));
	// Load in any variant-based entities
	if(choiceData.HasKey("entities")) {
		JSONArray entities = view_as<JSONArray>(choiceData.Get("entities"));
		for(int i = 0; i < entities.Length; i++) {
			// Parses entities and loads to choice.entities
			loadChoiceEntity(choice.entities, view_as<JSONObject>(entities.Get(i)));
		}
		delete entities;
	}
	// Load in any entities that the scene has
	if(extraEntities != null) {
		for(int i = 0; i < extraEntities.Length; i++) {
			// Parses entities and loads to choice.entities
			loadChoiceEntity(choice.entities, view_as<JSONObject>(extraEntities.Get(i)));
		}
		delete extraEntities;
	}
	// Load all inputs
	if(choiceData.HasKey("inputs")) {
		JSONArray inputsList = view_as<JSONArray>(choiceData.Get("inputs"));
		for(int i = 0; i < inputsList.Length; i++) {
			loadChoiceInput(choice.inputsList, view_as<JSONObject>(inputsList.Get(i)));
		}
		delete inputsList;
	}
	if(choiceData.HasKey("force_scenes")) {
		JSONArray scenes = view_as<JSONArray>(choiceData.Get("force_scenes"));
		char sceneId[32];
		for(int i = 0; i < scenes.Length; i++) {
			scenes.GetString(i, sceneId, sizeof(sceneId));
			choice.forcedScenes.PushString(sceneId);
		}
		delete scenes;
	}
	scene.variants.PushArray(choice);
}

void loadChoiceInput(ArrayList list, JSONObject inputData) {
	VariantInputData input;
	// Check classname -> targetname -> hammerid
	if(!inputData.GetString("classname", input.name, sizeof(input.name))) {
		if(inputData.GetString("targetname", input.name, sizeof(input.name))) {
			input.type = Input_Targetname;
		} else {
			if(inputData.GetString("hammerid", input.name, sizeof(input.name))) {
				input.type = Input_HammerId;
			} else {
				int id = inputData.GetInt("hammerid");
				if(id > 0) {
					input.type = Input_HammerId;
					IntToString(id, input.name, sizeof(input.name));
				} else {
					LogError("Missing valid input specification (hammerid, classname, targetname)");
					return;
				}
			}
		}
	}
	inputData.GetString("input", input.input, sizeof(input.input));
	list.PushArray(input);
}

void loadLumpData(ArrayList list, JSONObject inputData) {
	LumpEditData input;
	// Check classname -> targetname -> hammerid
	if(!inputData.GetString("classname", input.name, sizeof(input.name))) {
		if(inputData.GetString("targetname", input.name, sizeof(input.name))) {
			input.type = Input_Targetname;
		} else {
			if(inputData.GetString("hammerid", input.name, sizeof(input.name))) {
				input.type = Input_HammerId;
			} else {
				int id = inputData.GetInt("hammerid");
				if(id > 0) {
					input.type = Input_HammerId;
					IntToString(id, input.name, sizeof(input.name));
				} else {
					LogError("Missing valid input specification (hammerid, classname, targetname)");
					return;
				}
			}
		}
	}
	inputData.GetString("action", input.action, sizeof(input.action));
	inputData.GetString("value", input.value, sizeof(input.value));
	list.PushArray(input);
}

void loadChoiceEntity(ArrayList list, JSONObject entityData) {
	VariantEntityData entity;
	entityData.GetString("model", entity.model, sizeof(entity.model));
	if(!entityData.GetString("type", entity.type, sizeof(entity.type))) {
		entity.type = "prop_dynamic";
	} else if(entity.type[0] == '_') { 
		LogError("Invalid custom entity type \"%s\"", entity.type);
		return;
	}
	GetVector(entityData, "origin", entity.origin);
	GetVector(entityData, "angles", entity.angles);
	GetVector(entityData, "scale", entity.scale);
	GetColor(entityData, "color", entity.color);
	list.PushArray(entity);
}

bool GetVector(JSONObject obj, const char[] key, float out[3]) {
	if(!obj.HasKey(key)) return false;
	JSONArray vecArray = view_as<JSONArray>(obj.Get(key));
	if(vecArray != null) {
		out[0] = vecArray.GetFloat(0);
		out[1] = vecArray.GetFloat(1);
		out[2] = vecArray.GetFloat(2);
	}
	return true;
}

void GetColor(JSONObject obj, const char[] key, int out[4], int defaultColor[4] = { 255, 255, 255, 255 }) {
	if(obj.HasKey(key)) {
		JSONArray vecArray = view_as<JSONArray>(obj.Get(key));
		out[0] = vecArray.GetInt(0);
		out[1] = vecArray.GetInt(1);
		out[2] = vecArray.GetInt(2);
		if(vecArray.Length == 4)
			out[3] = vecArray.GetInt(3);
		else
			out[3] = 255;
	} else {
		out = defaultColor;
	}
}

void selectScenes(int flags = 0) {
	SceneData scene;
	StringMap groups = new StringMap();
	ArrayList list;
	// Select and spawn non-group scenes
	// TODO: refactor to use .scenesKv
	for(int i = 0; i < g_MapData.scenes.Length; i++) {
		g_MapData.scenes.GetArray(i, scene);
		// TODO: Exclusions
		// Select scene if not in group, or add to list of groups
		if(scene.group[0] == '\0') {
			selectScene(scene, flags);
		} else {
			// Load it into group list
			if(!groups.GetValue(scene.group, list)) {
				list = new ArrayList();
			}
			list.Push(i);
			groups.SetValue(scene.group, list);
		}
	}

	// Iterate through groups and select a random scene:
	StringMapSnapshot snapshot = groups.Snapshot();
	char key[MAX_SCENE_NAME_LENGTH];
	for(int i = 0; i < snapshot.Length; i++) {
		snapshot.GetKey(i, key, sizeof(key));
		groups.GetValue(key, list);
		// Select a random scene from the group:
		int index = GetURandomInt() % list.Length;
		index = list.Get(index);
		g_MapData.scenes.GetArray(index, scene);

		Debug("Selected scene \"%s\" for group %s (%d members)", scene.name, key, list.Length);
		selectScene(scene, flags);
		delete list;
	}
	// Traverse active scenes, loading any other scene it requires (via .force_scenes)
	ActiveSceneData aScene;
	SceneVariantData choice;
	ArrayList forcedScenes = new ArrayList(ByteCountToCells(MAX_SCENE_NAME_LENGTH));
	for(int i = 0; i < g_MapData.activeScenes.Length; i++) {
		g_MapData.activeScenes.GetArray(i, aScene);
		g_MapData.scenes.GetArray(i, scene);
		scene.variants.GetArray(aScene.variantIndex, choice);
		if(choice.forcedScenes != null) {
			for(int j = 0; j < choice.forcedScenes.Length; j++) {
				choice.forcedScenes.GetString(j, key, sizeof(key));
				forcedScenes.PushString(key);
			}
		}
	}
	// Iterate and activate any forced scenes
	for(int i = 0; i < forcedScenes.Length; i++) {
		forcedScenes.GetString(i, key, sizeof(key));
		// Check if scene was already loaded
		bool isSceneAlreadyLoaded = false;
		for(int j = 0; j < g_MapData.activeScenes.Length; i++) {
			g_MapData.activeScenes.GetArray(j, aScene);
			if(StrEqual(aScene.name, key)) {
				isSceneAlreadyLoaded = true;
				break;
			}
		}
		if(isSceneAlreadyLoaded) continue;
		g_MapData.scenesKv.GetArray(key, scene, sizeof(scene));
		selectScene(scene, flags | view_as<int>(FLAG_FORCE_ACTIVE));
	}

	delete forcedScenes;
	delete snapshot;
	delete groups;
}

void selectScene(SceneData scene, int flags) {
	// Use the .chance field  unless FLAG_ALL_SCENES or FLAG_FORCE_ACTIVE is set
	if(~flags & view_as<int>(FLAG_ALL_SCENES) && ~flags & view_as<int>(FLAG_FORCE_ACTIVE) && GetURandomFloat() > scene.chance) {
		return;
	}

	if(scene.variants.Length == 0) {
		LogError("Warn: No variants were found for scene \"%s\"", scene.name);
		return;
	}

	ArrayList choices = new ArrayList();
	SceneVariantData choice;
	int index;
	Debug("Scene %s has %d variants", scene.name, scene.variants.Length);
	// Weighted random: Push N times dependent on weight
	for(int i = 0; i < scene.variants.Length; i++) {
		scene.variants.GetArray(i, choice);
		if(flags & view_as<int>(FLAG_ALL_VARIANTS)) {
			spawnVariant(choice);
		} else {
			if(choice.weight <= 0) {
				PrintToServer("Warn: Variant %d in scene %s has invalid weight", i, scene.name);
				continue;
			}
			for(int c = 0; c < choice.weight; c++) {
				choices.Push(i);
			}
		}
	}
	Debug("Total choices: %d", choices.Length);
	if(flags & view_as<int>(FLAG_ALL_VARIANTS)) {
		delete choices;
	} else if(choices.Length > 0) {
		index = GetURandomInt() % choices.Length;
		index = choices.Get(index);
		delete choices;
		Log("Spawned scene \"%s\" with variant #%d", scene.name, index);
		scene.variants.GetArray(index, choice);
		spawnVariant(choice);
	}
	ActiveSceneData aScene;
	strcopy(aScene.name, sizeof(aScene.name), scene.name);
	aScene.variantIndex = index;
	g_MapData.activeScenes.PushArray(aScene);
}

void spawnVariant(SceneVariantData choice) {
	VariantEntityData entity;
	for(int i = 0; i < choice.entities.Length; i++) {
		choice.entities.GetArray(i, entity);
		spawnEntity(entity);
	}

	if(choice.inputsList.Length > 0) {
		VariantInputData input;
		for(int i = 0; i < choice.inputsList.Length; i++) {
			choice.inputsList.GetArray(i, input);
			input.Trigger();
		}
	}
}

void spawnEntity(VariantEntityData entity) {
	if(StrEqual(entity.type, "env_fire")) {
		Debug("spawning \"%s\" at (%.1f %.1f %.1f) rot (%.0f %.0f %.0f)", entity.type, entity.origin[0], entity.origin[1], entity.origin[2], entity.angles[0], entity.angles[1], entity.angles[2]);
		CreateFire(entity.origin, 20.0, 100.0, 0.0);
	} else if(StrEqual(entity.type, "env_physics_blocker") || StrEqual(entity.type, "env_player_blocker")) {
		CreateEnvBlockerScaled(entity.type, entity.origin, entity.scale);
	} else if(StrEqual(entity.type, "infodecal")) {
		CreateDecal(entity.model, entity.origin);
	} else if(StrContains(entity.type, "prop_") == 0) {
		if(entity.model[0] == '\0') {
			LogError("Missing model for entity with type \"%s\"", entity.type);
			return;
		}
		PrecacheModel(entity.model);
		int prop = CreateProp(entity.type, entity.model, entity.origin, entity.angles);
		SetEntityRenderColor(prop, entity.color[0], entity.color[1], entity.color[2], entity.color[3]);
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
	} else {
		LogError("Unknown entity type \"%s\"", entity.type);
	}
}

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

void Cleanup() {
	if(g_MapData.scenes != null) {
		SceneData scene;
		for(int i = 0; i < g_MapData.scenes.Length; i++) {
			g_MapData.scenes.GetArray(i, scene);
			scene.Cleanup();
		}
		delete g_MapData.scenes;
	}
	delete g_MapData.lumpEdits;

	DeleteCustomEnts();
	g_MapData.activeScenes.Clear();
}