bool IsTraverseMapA(const char[] map) {
    return String_EndsWith(map, "_a");
}
bool IsTraverseMapB(const char[] map) {
    // c4m1_milltown_a was added twice so _escape can pop it off and re-use
    return StrEqual(map, "c4m5_milltown_escape") || String_EndsWith(map, "_b");
}

public bool LoadRunGlobalMap(const char[] map, int flags) {
    // Unless FLAG_IGNORE_TRAVERSE_STORE, if the map is the _b variant, then load the stored _a value 
    SceneSelection selection;
    // Only load map data if we don't already have it
    if(g_MapData.scenes == null || g_selection == null || flags & view_as<int>(FLAG_REFRESH)) {
        if(~flags & view_as<int>(FLAG_IGNORE_TRAVERSE_STORE) && IsTraverseMapB(map) ) {
            Log("LoadRunGlobal: Trying to load traverse selection");
            TraverseData traverse;
            if(PopTraverseSelection(traverse)) {
                Debug("traverse map: %s", traverse.map);
                // Try Load the A variant
                if(LoadGlobalMapData(traverse.map, flags)) {
                    selection = view_as<SceneSelection>(traverse.selection);
                }
            }
        }
        if(selection == null) {
            // This is called if not traverse map or previous data not found
            Log("LoadRunGlobal: Loading & generating selection");
            if(!LoadGlobalMapData(map, flags)) {
                return false;
            }
            selection = selectScenes(g_MapData, flags);
        }
    }
    if(selection == null) {
        LogError("LoadRunGlobalMap: No selection was loaded");
    }

    g_selection = selection;
    
    return g_MapData.ApplySelection(selection, flags);
}

void trySelectScene(SceneSelection selection, SceneData scene, int flags) {
	// Use the .chance field  unless FLAG_ALL_SCENES or FLAG_FORCE_ACTIVE is set
	if(~flags & view_as<int>(FLAG_ALL_SCENES) && ~flags & view_as<int>(FLAG_FORCE_ACTIVE) && GetURandomFloat() > scene.chance) {
		return;
	}

	if(scene.variants.Length == 0) {
		LogError("Warn: No variants were found for scene \"%s\"", scene.name);
		return;
	}

    // TODO: select variant...  
    SelectedSceneData aScene;
    aScene.name = scene.name;
    aScene.selectedVariantIndexes = new ArrayList();

    ArrayList choices = new ArrayList();
	SceneVariantData choice;
	int chosenIndex;
	// Weighted random: Push N times dependent on weight
	for(int i = 0; i < scene.variants.Length; i++) {
		scene.variants.GetArray(i, choice);
		if(flags & view_as<int>(FLAG_ALL_VARIANTS)) {
            aScene.selectedVariantIndexes.Push(i);
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

	if(flags & view_as<int>(FLAG_ALL_VARIANTS)) {

	} else if(choices.Length > 0) {
        // Pick a random variant from list
		chosenIndex = GetURandomInt() % choices.Length;
		chosenIndex = choices.Get(chosenIndex);
		Log("Chosen scene \"%s\" with variant #%d", scene.name, chosenIndex);
        aScene.selectedVariantIndexes.Push(chosenIndex);
	}
    delete choices;

    selection.AddScene(aScene);
}

void selectGroups(SceneSelection selection, MapData data, int flags) {
    StringMapSnapshot snapshot = data.groups.Snapshot();
	char key[MAX_SCENE_NAME_LENGTH];
    ArrayList groupList;
    SceneData scene;
	for(int i = 0; i < snapshot.Length; i++) {
		snapshot.GetKey(i, key, sizeof(key));
		data.groups.GetValue(key, groupList);

		// Select a random scene from the group:
		int index = GetURandomInt() % groupList.Length;
		index = groupList.Get(index);
		data.scenes.GetArray(index, scene);

		Debug("Selected scene \"%s\" for group %s (%d members)", scene.name, key, groupList.Length);
		trySelectScene(selection, scene, flags);
		delete groupList;
	}
    delete snapshot;
}

void selectForcedScenes(SceneSelection selection, MapData data, int flags) {
    // Traverse active scenes, loading any other scene it requires (via .force_scenes)
	SelectedSceneData aScene;
	SceneVariantData choice;
    SceneData scene;
	// list of scenes that will need to be forced if not already:
	// (concat of all choice's .forcedScenes)
	ArrayList forcedScenes = new ArrayList(ByteCountToCells(MAX_SCENE_NAME_LENGTH));
    char key[MAX_SCENE_NAME_LENGTH];
	for(int i = 0; i < selection.Count; i++) {
		selection.Get(i, aScene);
		// Load scene from active scene entry
		if(!data.scenesKv.GetArray(aScene.name, scene, sizeof(scene))) {
            // this shouldn't happen
            Log("WARN: scene \"%s\" not found in scene selection", aScene.name);
			// can't find scene, ignore
			continue;
		}
		// Check all it's variants for any forced/required scenes
        for(int v = 0; v < aScene.selectedVariantIndexes.Length; v++) {
			// Load the variant from its index
			int variantIndex = aScene.selectedVariantIndexes.Get(v);
            scene.variants.GetArray(variantIndex, choice);
			
            // If the choice has forced scenes
            if(choice.forcedScenes != null) {
				Debug("scene#%d \"%s\" has forced scenes (%d)", aScene.name, v, choice.forcedScenes.Length);
                // Add each scene to the list to be added
				for(int j = 0; j < choice.forcedScenes.Length; j++) {
					choice.forcedScenes.GetString(j, key, sizeof(key));
					forcedScenes.PushString(key);
				}
			}
        }
	}

	if(forcedScenes.Length > 0) {
		Debug("Loading %d forced scenes", forcedScenes.Length);
	}
	// Iterate and activate any forced scenes
	for(int i = 0; i < forcedScenes.Length; i++) {
		forcedScenes.GetString(i, key, sizeof(key));
		// Check if scene was already loaded
		if(!selection.HasScene(key)) {
			data.scenesKv.GetArray(key, scene, sizeof(scene));
			trySelectScene(selection, scene, flags | view_as<int>(FLAG_FORCE_ACTIVE));
		}
	}
	delete forcedScenes;
}

// Selects what scenes and its variants to apply and returns list - does not activate
SceneSelection selectScenes(MapData data, int flags = 0) {
	SceneData scene;
    SceneSelection selection = new SceneSelection();

    Profiler profiler = new Profiler();
	profiler.Start();

    for(int i = 0; i < data.scenes.Length; i++) {
        data.scenes.GetArray(i, scene);
        if(scene.group[0] == '\0') {
            trySelectScene(selection, scene, flags);
        }
    }
    selectGroups(selection, data, flags);
    selectForcedScenes(selection, data, flags);
    
    profiler.Stop();
    Log("Done generating selection in %.4f seconds", profiler.Time);
    return selection;
}

void spawnGascans(MapData data) {
	if(data.gascanSpawners != null && data.gascanSpawners.Length > 0) {
		// Iterate through every gascan until we run out - picking a random spawner each time
		int entity = -1;
		char targetname[9];
		GascanSpawnerData spawner;
		int spawnerCount = data.gascanSpawners.Length;
		int count;
		while((entity = FindEntityByClassname(entity, "weapon_gascan")) != INVALID_ENT_REFERENCE) {
			GetEntPropString(entity, Prop_Data, "m_iName", targetname, sizeof(targetname));
			int hammerid = GetEntProp(entity, Prop_Data, "m_iHammerID");
			int glowColor = GetEntProp(entity, Prop_Send, "m_glowColorOverride"); // check if white
			if(hammerid == 0 && glowColor == 16777215 && targetname[0] == '\0' && !g_gascanSpawners.ContainsKey(entity)) {
				// Found a valid gascan, apply a random spawner
				int spawnerIndex = GetRandomInt(0, data.gascanSpawners.Length - 1);
				data.gascanSpawners.GetArray(spawnerIndex, spawner);
				data.gascanSpawners.Erase(spawnerIndex); // only want one can to use this spawner

				AssignGascan(entity, spawner);
				count++;
			}
		}
		Debug("Assigned %d gascans to %d spawners", count, spawnerCount);
	}
}

void activateVariant(SceneVariantData choice, int flags) {
    #pragma unused flags
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
