#define MAX_SCENE_NAME_LENGTH 32
#define MAX_INPUTS_CLASSNAME_LENGTH 64

int DEFAULT_COLOR[4] = { 255, 255, 255, 255 };

MapData g_MapData; // The global map data
SceneSelection g_selection; // The selected scenes from the global map data
BuilderData g_builder; // The global instance of the builder
StringMap g_mapTraverseSelections; // For maps that traverse backwards, holds record of the selected scenes so they can be re-applied

int g_ropeIndex; // Unique id for ropes on spawn, is reset to 0 for every new spawn attempt
ArrayList g_gascanRespawnQueue; // Queue that gascan respawns pop from to respawn to
AnyMap g_gascanSpawners; // Mapping of <entity index, GascanSpawnerData>, for when a can is destroyed it can be respawned in position

int g_iLaserIndex;

public void InitGlobals() {
	g_gascanSpawners = new AnyMap();
    g_mapTraverseSelections = new StringMap();
}

enum struct SelectedSceneData {
	char name[MAX_SCENE_NAME_LENGTH];
	ArrayList selectedVariantIndexes;
}

enum struct GascanSpawnerData {
	float origin[3];
	float angles[3];
}

enum struct MapData {
	StringMap scenesKv;
	ArrayList scenes;
	ArrayList lumpEdits;
	ArrayList activeScenes;
	ArrayList gascanSpawners;
	StringMap groups;

	void Cleanup() {
		SceneData scene;
		for(int i = 0; i < this.scenes.Length; i++) {
			this.scenes.GetArray(i, scene);
			scene.Cleanup();
		}
		delete this.scenes;
		delete this.scenesKv;
		delete this.lumpEdits;
		delete this.activeScenes;
		delete this.gascanSpawners;
		delete this.groups;
	}
	
	SceneSelection GenerateSelection(int flags) {
        return selectScenes(this, flags);
    }

    bool ApplySelection(SceneSelection selection, int flags) {
        Profiler profiler = new Profiler();

        profiler.Start();
        selection.Activate(this, flags);
        spawnGascans(this);
        profiler.Stop();

        // _ropeIndex = 0;

        Log("Done applying selection in %.4f seconds", profiler.Time);
        return true;
    }

    bool IsLoaded() {
        return this.scenes != null;
    }
}

enum loadFlags {
	FLAG_NONE = 0,
	FLAG_ALL_SCENES = 1, // Pick all scenes, no random chance
	FLAG_ALL_VARIANTS = 2, // Pick all variants (for debug purposes),
	FLAG_REFRESH = 4, // Load data bypassing cache
	FLAG_FORCE_ACTIVE = 8, // Similar to ALL_SCENES, bypasses % chance
	FLAG_IGNORE_TRAVERSE_STORE = 16 // Do not load stored selection from the g_mapTraverseSelections
}

enum struct BuilderData {
	JSONObject mapData;

	JSONObject selectedSceneData;
	char selectedSceneId[64];

	JSONObject selectedVariantData;
	int selectedVariantIndex;

    bool IsLoaded() {
        return this.mapData != null;
    }

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
		JSONObject entityData = ExportEntity(entity, exportType);
		this.AddEntityData(entityData);
	}

	void AddEntityData(JSONObject entityData) {
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
		entities.Push(entityData);
	}
}



enum struct SceneData {
	char name[MAX_SCENE_NAME_LENGTH];
	float chance;
	char group[MAX_SCENE_NAME_LENGTH];
	ArrayList variants;

	void Cleanup() {
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
	char model[128];
	char targetname[128];
	float origin[3];
	float angles[3];
	float scale[3];
	int color[4];

	ArrayList keyframes;
}

enum InputType {
	Input_Classname,
	Input_Targetname,
	Input_HammerId
}
enum struct VariantInputData {
	char name[MAX_INPUTS_CLASSNAME_LENGTH];
	InputType type; 
	char input[64];

	void Trigger() {
		int entity = -1;
		switch(this.type) {
			case Input_Classname: {
				while((entity = FindEntityByClassname(entity, this.name)) != INVALID_ENT_REFERENCE) {
					this._trigger(entity);
				}
			}
			case Input_Targetname: {
				char targetname[64];
				int count = 0;
				while((entity = FindEntityByClassname(entity, "*")) != INVALID_ENT_REFERENCE) {
					GetEntPropString(entity, Prop_Data, "m_iName", targetname, sizeof(targetname));
					if(StrEqual(targetname, this.name)) {
						this._trigger(entity);
						count++;
					}
				}
				if(count == 0) {
					PrintToServer("[Randomizer::WARN] Input TargetName=\"%s\" matched 0 entties", this.name);
				}
			}
			case Input_HammerId: {
				int targetId = StringToInt(this.name);
				int count = 0;
				while((entity = FindEntityByClassname(entity, "*")) != INVALID_ENT_REFERENCE) {
					int hammerId = GetEntProp(entity, Prop_Data, "m_iHammerID");
					if(hammerId == targetId ) {
						this._trigger(entity);
						count++;
						break;
					}
				}
				if(count == 0) {
					PrintToServer("[Randomizer::WARN] Input HammerId=%d matched 0 entties", targetId);
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
			} else {
				char cmd[32];
				// Split input "a b" to a with variant "b"
				int len = SplitString(this.input, " ", cmd, sizeof(cmd));
				if(len > -1) {
					SetVariantString(this.input[len]);
					AcceptEntityInput(entity, cmd);
					Debug("_trigger(%d): %s (v=%s)", entity, cmd, this.input[len]);
				} else {
					Debug("_trigger(%d): %s", entity, this.input);
					AcceptEntityInput(entity, this.input);
				}
				
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