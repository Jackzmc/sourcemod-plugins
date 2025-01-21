public bool LoadGlobalMapData(const char[] map, int flags) {
	Cleanup();
	return ParseMapData(g_MapData, map, flags);
}

public JSONObject LoadMapJson(const char[] map) {
	Debug("Loading config for %s", map);
	char filePath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, filePath, sizeof(filePath), "data/randomizer/%s.json", map);
	if(!FileExists(filePath)) {
		Log("No map config file (data/randomizer/%s.json), not loading", map);
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

/// Parses map data into first parameter, bool for success
public bool ParseMapData(MapData data, const char[] map, int flags) {
    JSONObject json = LoadMapJson(map);
	if(json == null) {
		return false;
	}

    Debug("Starting parsing json data");

	data.scenes = new ArrayList(sizeof(SceneData));
	data.scenesKv = new StringMap();
	data.lumpEdits = new ArrayList(sizeof(LumpEditData));

	Profiler profiler = new Profiler();
	profiler.Start();

	JSONObjectKeys iterator = json.Keys();
	char key[32];
	while(iterator.ReadKey(key, sizeof(key))) {
		if(key[0] == '_') {
			if(StrEqual(key, "_lumps")) {
				JSONArray lumpsList = view_as<JSONArray>(json.Get(key));
				if(lumpsList != null) {
					for(int l = 0; l < lumpsList.Length; l++) {
						loadLumpData(data.lumpEdits, view_as<JSONObject>(lumpsList.Get(l)));
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
			JSONObject scene = view_as<JSONObject>(json.Get(key));
			// Parses scene data and inserts to scenes
			loadScene(data, key, scene);
		}
	}
	delete json;

	data.groups = new StringMap();
	getSceneGroups(data, data.groups);

	profiler.Stop();
	Log("Parsed map %s(%d) in %.4f seconds (%d scenes)", map, flags, profiler.Time, data.scenes.Length);
	delete profiler;
	return true;
}

void getSceneGroups(MapData data, StringMap groups) {
    ArrayList groupList;
	SceneData scene;
	for(int i = 0; i < data.scenes.Length; i++) {
		data.scenes.GetArray(i, scene);
		if(scene.group[0] != '\0') {
			// Load it into group list
			if(!groups.GetValue(scene.group, groupList)) {
				groupList = new ArrayList();
			}
			groupList.Push(i);
			groups.SetValue(scene.group, groupList);
		}
	}
}

void loadScene(MapData data, const char key[MAX_SCENE_NAME_LENGTH], JSONObject sceneData) {
	SceneData scene;
	scene.name = key;
	scene.chance = sceneData.GetFloat("chance");
	if(scene.chance < 0.0 || scene.chance > 1.0) {
		LogError("Scene \"%s\" has invalid chance (%f)", scene.name, scene.chance);
		return;
	} else if(!sceneData.HasKey("variants")) {
		ThrowError("Failed to load: Scene \"%s\" has missing \"variants\" array", scene.name);
		return;
	}
	// TODO: load "entities", merge with choice.entities
	sceneData.GetString("group", scene.group, sizeof(scene.group));
	scene.variants = new ArrayList(sizeof(SceneVariantData));

	JSONArray entities;
	if(sceneData.HasKey("entities")) {
		entities = view_as<JSONArray>(sceneData.Get("entities"));
	}

    // Load all variants
	JSONArray variants = view_as<JSONArray>(sceneData.Get("variants"));
	for(int i = 0; i < variants.Length; i++) {
		// Parses choice and loads to scene.choices
		loadChoice(scene, view_as<JSONObject>(variants.Get(i)), entities);
	}

	data.scenes.PushArray(scene);
	data.scenesKv.SetArray(scene.name, scene, sizeof(scene));
}

void loadChoice(SceneData scene, JSONObject choiceData, JSONArray extraEntities) {
	SceneVariantData choice;
    choice.weight = choiceData.HasKey("weight") ? choiceData.GetInt("weight") : 1;
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
		// delete extraEntities;
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
			Debug("scene %s: require %s", scene.name, sceneId);
		}
		delete scenes;
	}
	scene.variants.PushArray(choice);
}

void loadChoiceInput(ArrayList list, JSONObject inputData) {
	VariantInputData input;
	input.type = Input_Classname;
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
	if(entityData.GetString("targetname", entity.targetname, sizeof(entity.targetname))) {
		Format(entity.targetname, sizeof(entity.targetname), "randomizer_%s", entity.targetname);
	}
	if(!entityData.GetString("type", entity.type, sizeof(entity.type))) {
		entity.type = "prop_dynamic";
	} /*else if(entity.type[0] == '_') { 
		LogError("Invalid custom entity type \"%s\"", entity.type);
		return;
	}*/

	if(StrEqual(entity.type, "move_rope")) {
		if(!entityData.HasKey("keyframes")) {
			LogError("move_rope entity is missing keyframes: Vec[] property");
			return;
		}
		entity.keyframes = new ArrayList(3);
		JSONArray keyframesData = view_as<JSONArray>(entityData.Get("keyframes"));
		float vec[3];
		for(int i = 0 ; i < keyframesData.Length; i++) {
			JSONArray vecArray = view_as<JSONArray>(keyframesData.Get(i));
			vec[0] = vecArray.GetFloat(0);
			vec[1] = vecArray.GetFloat(1);
			vec[2] = vecArray.GetFloat(2);
			entity.keyframes.PushArray(vec);
		}
	}
	GetVector(entityData, "origin", entity.origin);
	GetVector(entityData, "angles", entity.angles);
	GetVector(entityData, "scale", entity.scale);
	GetColor(entityData, "color", entity.color, DEFAULT_COLOR);
	list.PushArray(entity);
}