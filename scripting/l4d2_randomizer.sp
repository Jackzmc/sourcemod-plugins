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
#include <json>
#include <left4dhooks>
#include <jutils>
#include <entitylump>

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

public Plugin myinfo = 
{
	name =  "L4D2 Randomizer", 
	author = "jackzmc", 
	description = "", 
	version = PLUGIN_VERSION, 
	url = "https://github.com/Jackzmc/sourcemod-plugins"
};

ConVar cvarEnabled;
enum struct ActiveSceneData {
	char name[MAX_SCENE_NAME_LENGTH];
	int variantIndex;
}
MapData g_MapData;

public void OnPluginStart() {
	EngineVersion g_Game = GetEngineVersion();
	if(g_Game != Engine_Left4Dead && g_Game != Engine_Left4Dead2) {
		SetFailState("This plugin is for L4D/L4D2 only.");	
	}

	RegAdminCmd("sm_rcycle", Command_CycleRandom, ADMFLAG_CHEATS);
	RegAdminCmd("sm_expent", Command_ExportEnt, ADMFLAG_GENERIC);

	cvarEnabled = CreateConVar("sm_randomizer_enabled", "0");

	g_MapData.activeScenes = new ArrayList(sizeof(ActiveSceneData));
}

char currentMap[64];

// TODO: on round start
public void OnMapStart() {
	g_iLaserIndex = PrecacheModel("materials/sprites/laserbeam.vmt", true);
	GetCurrentMap(currentMap, sizeof(currentMap));
}

public void OnMapEnd() {
	Cleanup();
}

bool hasRan;
public void OnMapInit(const char[] map) {
	if(cvarEnabled.BoolValue) {
		if(LoadMapData(currentMap, FLAG_NONE) && g_MapData.lumpEdits.Length > 0) {
			Log("Found %d lump edits, running...", g_MapData.lumpEdits.Length);
			LumpEditData lump;
			for(int i = 0; i < g_MapData.lumpEdits.Length; i++) {
				g_MapData.lumpEdits.GetArray(i, lump);
				lump.Trigger();
			}
		}
	}
	hasRan = false;
}

public void OnClientPutInServer(int client) {
	if(!hasRan) {
		hasRan = true;
		if(cvarEnabled.BoolValue)
			RunMap(currentMap, FLAG_NONE);
	}
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

		char arg1[8];
		GetCmdArg(1, arg1, sizeof(arg1));
		int flags = StringToInt(arg1) | view_as<int>(FLAG_REFRESH);
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

public Action Command_ExportEnt(int client, int args) {
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

	void Cleanup() {
		delete this.inputsList;
		delete this.entities;
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
	ArrayList scenes;
	ArrayList lumpEdits;
	ArrayList activeScenes;
}

enum loadFlags {
	FLAG_NONE = 0,
	FLAG_ALL_SCENES = 1, // Pick all scenes, no random chance
	FLAG_ALL_VARIANTS = 2, // Pick all variants (for debug purposes),
	FLAG_REFRESH = 4, // Load data bypassing cache
}

// Reads (mapname).json file and parses it
public bool LoadMapData(const char[] map, int flags) {
	Debug("Loading config for %s", map);
	char filePath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, filePath, sizeof(filePath), "data/randomizer/%s.json", map);
	if(!FileExists(filePath)) {
		Log("[Randomizer] No map config file (data/randomizer/%s.json), not loading", map);
		return false;
	}

	char buffer[65536];
	File file = OpenFile(filePath, "r");
	if(file == null) {
		LogError("Could not open map config file (data/randomizer/%s.json)", map);
		return false;
	}
	file.ReadString(buffer, sizeof(buffer));
	JSON_Object data = json_decode(buffer);
	if(data == null) {
		json_get_last_error(buffer, sizeof(buffer));
		LogError("Could not parse map config file (data/randomizer/%s.json): %s", map, buffer);
		delete file;
		return false;
	}

	Debug("Starting parsing json data");

	Cleanup();
	g_MapData.scenes = new ArrayList(sizeof(SceneData));
	g_MapData.lumpEdits = new ArrayList(sizeof(LumpEditData));
	g_MapData.activeScenes.Clear();

	Profiler profiler = new Profiler();
	profiler.Start();

	int length = data.Length;
	char key[32];
	for (int i = 0; i < length; i += 1) {
		data.GetKey(i, key, sizeof(key));

		if(key[0] == '_') {
			if(StrEqual(key, "_lumps")) {
				JSON_Array lumpsList = view_as<JSON_Array>(data.GetObject(key));
				if(lumpsList != null) {
					for(int l = 0; l < lumpsList.Length; l++) {
						loadLumpData(g_MapData.lumpEdits, lumpsList.GetObject(l));
					}
				}
			} else {
				Debug("Unknown special entry \"%s\", skipping", key);
			}
		} else {
			if(data.GetType(key) != JSON_Type_Object) {
				Debug("Invalid normal entry \"%s\" (not an object), skipping", key);
				continue;
			}
			JSON_Object scene = data.GetObject(key);
			// Parses scene data and inserts to scenes
			loadScene(key, scene);
		}
	}

	json_cleanup_and_delete(data);
	profiler.Stop();
	Log("Parsed map file and found %d scenes in %.4f seconds", g_MapData.scenes.Length, profiler.Time);
	delete profiler;
	delete file;
	return true;
}

// Calls LoadMapData (read&parse (mapname).json) then select scenes
public bool RunMap(const char[] map, int flags) {
	if(g_MapData.scenes == null || flags & view_as<int>(FLAG_REFRESH)) {
		LoadMapData(map, flags);
	}
	Profiler profiler = new Profiler();

	profiler.Start();
	selectScenes(flags);
	profiler.Stop();

	Log("Done processing in %.4f seconds", g_MapData.scenes.Length, profiler.Time);
	return true;
}

void loadScene(const char key[MAX_SCENE_NAME_LENGTH], JSON_Object sceneData) {
	SceneData scene;
	scene.name = key;
	scene.chance = sceneData.GetFloat("chance");
	if(scene.chance < 0.0 || scene.chance > 1.0) {
		LogError("Scene \"%s\" has invalid chance (%f)", scene.name, scene.chance);
		return;
	}
	sceneData.GetString("group", scene.group, sizeof(scene.group));
	scene.variants = new ArrayList(sizeof(SceneVariantData));
	JSON_Array variants = view_as<JSON_Array>(sceneData.GetObject("variants"));
	for(int i = 0; i < variants.Length; i++) {
		// Parses choice and loads to scene.choices
		loadChoice(scene, variants.GetObject(i));
	}
	g_MapData.scenes.PushArray(scene);
}

void loadChoice(SceneData scene, JSON_Object choiceData) {
	SceneVariantData choice;
	choice.weight = choiceData.GetInt("weight", 1);
	choice.entities = new ArrayList(sizeof(VariantEntityData));
	choice.inputsList = new ArrayList(sizeof(VariantInputData));
	JSON_Array entities = view_as<JSON_Array>(choiceData.GetObject("entities"));
	if(entities != null) {
		for(int i = 0; i < entities.Length; i++) {
			// Parses entities and loads to choice.entities
			loadChoiceEntity(choice.entities, entities.GetObject(i));
		}
	}
	JSON_Array inputsList = view_as<JSON_Array>(choiceData.GetObject("inputs"));
	if(inputsList != null) {
		for(int i = 0; i < inputsList.Length; i++) {
			loadChoiceInput(choice.inputsList, inputsList.GetObject(i));
		}
	}
	scene.variants.PushArray(choice);
}

void loadChoiceInput(ArrayList list, JSON_Object inputData) {
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

void loadLumpData(ArrayList list, JSON_Object inputData) {
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

void loadChoiceEntity(ArrayList list, JSON_Object entityData) {
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

void GetVector(JSON_Object obj, const char[] key, float out[3]) {
	JSON_Array vecArray = view_as<JSON_Array>(obj.GetObject(key));
	if(vecArray != null) {
		out[0] = vecArray.GetFloat(0);
		out[1] = vecArray.GetFloat(1);
		out[2] = vecArray.GetFloat(2);
	}
}

void GetColor(JSON_Object obj, const char[] key, int out[4]) {
	JSON_Array vecArray = view_as<JSON_Array>(obj.GetObject(key));
	if(vecArray != null) {
		out[0] = vecArray.GetInt(0);
		out[1] = vecArray.GetInt(1);
		out[2] = vecArray.GetInt(2);
		if(vecArray.Length == 4)
			out[3] = vecArray.GetInt(3);
		else
			out[3] = 255;
	} else {
		out[0] = 255;
		out[1] = 255;
		out[2] = 255;
		out[3] = 255;
	}
}

void selectScenes(int flags = 0) {
	SceneData scene;
	StringMap groups = new StringMap();
	ArrayList list;
	for(int i = 0; i < g_MapData.scenes.Length; i++) {
		g_MapData.scenes.GetArray(i, scene);
		// TODO: Exclusions
		// Select scene if not in group, or add to list of groups
		if(scene.group[0] == '\0') {
			selectScene(scene, flags);
		} else {
			if(!groups.GetValue(scene.group, list)) {
				list = new ArrayList();
			}
			list.Push(i);
			groups.SetValue(scene.group, list);
		}
	}

	StringMapSnapshot snapshot = groups.Snapshot();
	char key[MAX_SCENE_NAME_LENGTH];
	for(int i = 0; i < snapshot.Length; i++) {
		snapshot.GetKey(i, key, sizeof(key));
		groups.GetValue(key, list);
		int index = GetURandomInt() % list.Length;
		index = list.Get(index);
		g_MapData.scenes.GetArray(index, scene);
		Debug("Selected scene \"%s\" for group %s (%d members)", scene.name, key, list.Length);
		selectScene(scene, flags);
		delete list;
	}
	delete snapshot;
	delete groups;
}

void selectScene(SceneData scene, int flags) {
	// Use the .chance field  unless FLAG_ALL_SCENES is set
	if(~flags & view_as<int>(FLAG_ALL_SCENES) && GetURandomFloat() > scene.chance) {
		return;
	}

	if(scene.variants.Length == 0) {
		LogError("Warn: No variants were found for scene \"%s\"", scene.name);
		return;
	}

	ArrayList choices = new ArrayList();
	SceneVariantData choice;
	int index;
	// Weighted random: Push N times dependent on weight
	for(int i = 0; i < scene.variants.Length; i++) {
		scene.variants.GetArray(i, choice);
		if(flags & view_as<int>(FLAG_ALL_VARIANTS)) {
			spawnVariant(choice);
		} else {
			for(int c = 0; c < choice.weight; c++) {
				choices.Push(i);
			}
		}
	}
	if(flags & view_as<int>(FLAG_ALL_VARIANTS)) {
		delete choices;
	} else {
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