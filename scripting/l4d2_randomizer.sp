#pragma semicolon 1
#pragma newdecls required

//#define DEBUG

#define PLUGIN_VERSION "1.0"
#define DEBUG_SCENE_PARSE 1

#include <sourcemod>
#include <sdktools>
//#include <sdkhooks>
#include <profiler>
#include <json>
#include <jutils>
#define ENT_PROP_NAME "l4d2_randomizer"
#include <gamemodes/ents>

public Plugin myinfo = 
{
	name =  "L4D2 Randomizer", 
	author = "jackzmc", 
	description = "", 
	version = PLUGIN_VERSION, 
	url = "https://github.com/Jackzmc/sourcemod-plugins"
};

ConVar cvarEnabled;

public void OnPluginStart() {
	EngineVersion g_Game = GetEngineVersion();
	if(g_Game != Engine_Left4Dead && g_Game != Engine_Left4Dead2) {
		SetFailState("This plugin is for L4D/L4D2 only.");	
	}

	RegAdminCmd("sm_rcycle", Command_CycleRandom, ADMFLAG_CHEATS);
	RegAdminCmd("sm_expent", Command_ExportEnt, ADMFLAG_GENERIC);

	cvarEnabled = CreateConVar("sm_randomizer_enabled", "0");
}

public void OnMapEnd() {
	DeleteCustomEnts();
}

int GetLookingEntity(int client, TraceEntityFilter filter) {
	static float pos[3], ang[3];
	GetClientEyePosition(client, pos);
	GetClientEyeAngles(client, ang);
	TR_TraceRayFilter(pos, ang, MASK_SOLID, RayType_Infinite, filter, client);
	if(TR_DidHit()) {
		return TR_GetEntityIndex();
	}
	return -1;
}

public Action Command_CycleRandom(int client, int args) {
	DeleteCustomEnts();
	char map[64];
	GetCurrentMap(map, sizeof(map));
	LoadMap(map);
	ReplyToCommand(client, "Done.");
	return Plugin_Handled;
}

public Action Command_ExportEnt(int client, int args) {
	int entity = GetLookingEntity(client, Filter_IgnorePlayer);
	if(entity > 0) {
		float origin[3];
		float angles[3];
		float size[3];
		GetEntPropVector(entity, Prop_Send, "m_vecOrigin", origin);
		GetEntPropVector(entity, Prop_Send, "m_angRotation", angles);
		GetEntPropVector(entity, Prop_Send, "m_vecMaxs", size);

		char model[64];
		GetEntPropString(entity, Prop_Data, "m_ModelName", model, sizeof(model));

		ReplyToCommand(client, "{");
		ReplyToCommand(client, "\t\"model\": \"%s\",", model);
		ReplyToCommand(client, "\t\"origin\": [%.2f, %.2f, %.2f],", origin[0], origin[1], origin[2]);
		ReplyToCommand(client, "\t\"angles\": [%.2f, %.2f, %.2f],", angles[0], angles[1], angles[2]);
		ReplyToCommand(client, "\t\"size\": [%.2f, %.2f, %.2f]", size[0], size[1], size[2]);
		ReplyToCommand(client, "}");
	} else {
		PrintCenterText(client, "No entity found");
	}
	return Plugin_Handled;
}

public void OnMapStart() {
	if(cvarEnabled.BoolValue) {
		char map[64];
		GetCurrentMap(map, sizeof(map));
		LoadMap(map);
	}
}

#define MAX_SCENE_NAME_LENGTH 32
enum struct SceneData {
	char name[MAX_SCENE_NAME_LENGTH];
	float chance;
	ArrayList exclusions;
	ArrayList variants;

	void Cleanup() {
		delete this.exclusions;
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
	ArrayList entities;

	void Cleanup() {
		delete this.entities;
	}
}

enum struct VariantEntityData {
	char type[16];
	char model[64];
	float origin[3];
	float angles[3];
	float scale[3];
}

ArrayList scenes;

// Parses (mapname).json and runs chances
public bool LoadMap(const char[] map) {

	char filePath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, filePath, sizeof(filePath), "data/randomizer/%s.json", map);
	if(!FileExists(filePath)) {
		Log("[Randomizer] No map config file (data/randomizer/%s.json), not loading", map);
		return false;
	}

	char buffer[65536];
	File file = OpenFile(filePath, "r");
	if(file == null) {
		LogError("[Randomizer] Could not open map config file (data/randomizer/%s.json)", map);
		return false;
	}
	file.ReadString(buffer, sizeof(buffer));
	JSON_Object data = json_decode(buffer);
	if(data == null) {
		json_get_last_error(buffer, sizeof(buffer));
		LogError("[Randomizer] Could not parse map config file (data/randomizer/%s.json): %s", map, buffer);
		delete file;
		return false;
	}
	Cleanup();
	scenes = new ArrayList(sizeof(SceneData));

	Profiler profiler = new Profiler();
	profiler.Start();

	int length = data.Length;
	char key[32];
	for (int i = 0; i < length; i += 1) {
		data.GetKey(i, key, sizeof(key));
		if(data.GetType(key) != JSON_Type_Object) continue;

		JSON_Object scene = data.GetObject(key);
		// Parses scene data and inserts to scenes
		loadGroup(key, scene);
	}

	profiler.Stop();
	Log("Loaded %d scenes in %.1f seconds", scenes.Length, profiler.Time);
	profiler.Start();

	processGroups();

	profiler.Stop();
	Log("Done processing in %.1f seconds", scenes.Length, profiler.Time);

	json_cleanup_and_delete(data);

	delete profiler;
	delete file;
	return true;
}

void loadGroup(const char key[MAX_SCENE_NAME_LENGTH], JSON_Object sceneData) {
	SceneData scene;
	scene.name = key;
	scene.chance = sceneData.GetFloat("chance");
	if(scene.chance < 0.0 || scene.chance > 1.0) {
		LogError("Scene \"%s\" has invalid chance (%f)", scene.name, scene.chance);
		return;
	}
	scene.exclusions = new ArrayList(ByteCountToCells(MAX_SCENE_NAME_LENGTH));
	JSON_Array exclusions = view_as<JSON_Array>(sceneData.GetObject("exclusions"));
	if(exclusions != null) {
		char id[MAX_SCENE_NAME_LENGTH];
		for(int i = 0; i < exclusions.Length; i ++) {
			exclusions.GetString(i, id, sizeof(id));
			scene.exclusions.PushString(id);
		}
	}
	scene.variants = new ArrayList(sizeof(SceneVariantData));
	JSON_Array variants = view_as<JSON_Array>(sceneData.GetObject("variants"));
	for(int i = 0; i < variants.Length; i++) {
		// Parses choice and loads to scene.choices
		loadChoice(scene, variants.GetObject(i));
	}
	scenes.PushArray(scene);
}

void loadChoice(SceneData scene, JSON_Object choiceData) {
	SceneVariantData choice;
	choice.weight = choiceData.GetInt("weight", 1);
	choice.entities = new ArrayList(sizeof(VariantEntityData));
	JSON_Array entities = view_as<JSON_Array>(choiceData.GetObject("entities"));
	for(int i = 0; i < entities.Length; i++) {
		// Parses entities and loads to choice.entities
		loadChoiceEntity(choice, entities.GetObject(i));
	}
	scene.variants.PushArray(choice);
}

void loadChoiceEntity(SceneVariantData choice, JSON_Object entityData) {
	VariantEntityData entity;
	entityData.GetString("model", entity.model, sizeof(entity.model));
	if(!entityData.GetString("type", entity.type, sizeof(entity.type))) {
		entity.type = "prop_dynamic";
	}
	GetVector(entityData, "origin", entity.origin);
	GetVector(entityData, "angles", entity.angles);
	GetVector(entityData, "scale", entity.scale);
	choice.entities.PushArray(entity);
}

void GetVector(JSON_Object obj, const char[] key, float out[3]) {
	JSON_Array vecArray = view_as<JSON_Array>(obj.GetObject(key));
	if(vecArray != null) {
		out[0] = vecArray.GetFloat(0);
		out[1] = vecArray.GetFloat(1);
		out[2] = vecArray.GetFloat(2);
	}
}

void processGroups() {
	SceneData scene;
	for(int i = 0; i < scenes.Length; i++) {
		scenes.GetArray(i, scene);
		// TODO: Exclusions
		if(GetURandomFloat() < scene.chance) {
			selectScene(scene);
		}
	}
}

void selectScene(SceneData scene) {
	// TODO: Weight
	if(scene.variants.Length == 0) {
		LogError("Warn: No variants were found for scene \"%s\"", scene.name);
		return;
	}
	Debug("Selected scene: \"%s\"", scene.name);

	ArrayList choices = new ArrayList();
	SceneVariantData choice;
	// Weighted random: Push N times dependent on weight
	for(int i = 0; i < scene.variants.Length; i++) {
		scene.variants.GetArray(i, choice);
		for(int c = 0; c < choice.weight; c++) {
			choices.Push(i);
		}
		
	}
	int index = GetURandomInt() % choices.Length;
	index = choices.Get(index);
	delete choices;
	Debug("Selected variant: #%d", index);
	scene.variants.GetArray(index, choice);
	spawnVariant(choice);
}

void spawnVariant(SceneVariantData choice) {
	VariantEntityData entity;
	// Weighted random: Push N times dependent on weight
	for(int i = 0; i < choice.entities.Length; i++) {
		choice.entities.GetArray(i, entity);
		spawnEntity(entity);
	}
}

void spawnEntity(VariantEntityData entity) {
	Debug("spawning \"%s\" at (%.1f %.1f %.1f) rot (%.0f %.0f %.0f)", entity.model, entity.origin[0], entity.origin[1], entity.origin[2], entity.angles[0], entity.angles[1], entity.angles[2]);
	PrecacheModel(entity.model);
	CreateProp(entity.type, entity.model, entity.origin, entity.angles);
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
	if(scenes != null) {
		SceneData scene;
		for(int i = 0; i < scenes.Length; i++) {
			scenes.GetArray(i, scene);
			scene.Cleanup();
		}
		delete scenes;
	}
}