#define MAX_SCENE_NAME_LENGTH 32
#define MAX_INPUTS_CLASSNAME_LENGTH 64

int DEFAULT_COLOR[4] = { 255, 255, 255, 255 };

MapData g_MapData; // The global map data
SceneSelection g_selection; // The selected scenes from the global map data
BuilderData g_builder; // The global instance of the builder
ArrayList g_mapTraverseSelectionStack; // For maps that traverse backwards, holds record of the selected scenes so they can be re-applied

int g_ropeIndex; // Unique id for ropes on spawn, is reset to 0 for every new spawn attempt
ArrayList g_gascanRespawnQueue; // Queue that gascan respawns pop from to respawn to
AnyMap g_gascanSpawners; // Mapping of <entity index, GascanSpawnerData>, for when a can is destroyed it can be respawned in position

int g_iLaserIndex;

public void InitGlobals() {
	g_gascanSpawners = new AnyMap();
    g_mapTraverseSelectionStack = new ArrayList(sizeof(TraverseData));
}

enum struct TraverseData {
    char map[64];
    ArrayList selection;
}

methodmap SceneSelection < ArrayList {
    public SceneSelection() {
        ArrayList selectedScenes = new ArrayList(sizeof(SelectedSceneData));
        return view_as<SceneSelection>(selectedScenes);
    }

    property int Count {
        public get() {
            return (view_as<ArrayList>(this)).Length;
        }
    }

    public void Cleanup() {
        delete this;
    }

    public void Activate(MapData data, int flags = 0) {
        g_ropeIndex = 0;
        SelectedSceneData aScene;
        SceneData scene;
        SceneVariantData choice;
        ArrayList list = view_as<ArrayList>(this);
        for(int i = 0; i < list.Length; i++) {
            list.GetArray(i, aScene);
            Log("Activating scene \"%s\" with %d variants", aScene.name, aScene.selectedVariantIndexes.Length);

            // Fetch the scene that aScene marks
            if(!data.scenesKv.GetArray(aScene.name, scene, sizeof(scene))) {
                Log("WARN: Selected scene \"%s\" not found, skipping", aScene.name);
                continue;
            }

            for(int v = 0; v <  aScene.selectedVariantIndexes.Length; v++) {
                int variantIndex = aScene.selectedVariantIndexes.Get(v);


                scene.variants.GetArray(variantIndex, choice);
                activateVariant(choice, flags);
            }
        }
    }

    public void Get(int sceneIndex, SelectedSceneData scene) {
        (view_as<ArrayList>(this)).GetArray(sceneIndex, scene);
    }

    property ArrayList List {
        public get() {
            return view_as<ArrayList>(this);
        }
    } 

    public void AddScene(SelectedSceneData aScene) {
        view_as<ArrayList>(this).PushArray(aScene);
    }
}

void StoreTraverseSelection(const char[] name, SceneSelection selection) {
    // Pushes selection and map to the stack
    TraverseData data;
    strcopy(data.map, sizeof(data.map), name);
    data.selection = selection.List.Clone();
    g_mapTraverseSelectionStack.PushArray(data);
}

bool PopTraverseSelection(TraverseData data) {
    if(g_mapTraverseSelectionStack.Length == 0) {
        Log("WARN: PopTraverseSelection() called but stack is empty");
        return false;
    }
    int index = g_mapTraverseSelectionStack.Length - 1;
    g_mapTraverseSelectionStack.GetArray(index, data);
    g_mapTraverseSelectionStack.Erase(index);
    return true;
}

void ClearTraverseStack() {
    TraverseData trav;
    for(int i = 0; i < g_mapTraverseSelectionStack.Length; i++) {
        g_mapTraverseSelectionStack.GetArray(i, trav, sizeof(trav));
        delete trav.selection;
    }
    g_mapTraverseSelectionStack.Clear();
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
		VariantEntityData entity;
		for(int i = 0; i < this.entities.Length; i++) {
			this.entities.GetArray(i, entity, sizeof(entity));
			entity.Cleanup();
		}
		delete this.entities;
		delete this.forcedScenes;
	}
}

enum propertyType {
	PROPERTY_NONE = -1,
	PROPERTY_STRING,
	PROPERTY_INTEGER,
	PROPERTY_FLOAT
}

// This is horrible but we need a way to know what the type of the netprop to set is
enum struct PropertyStore {
	JSONObject intKv;
	JSONObject stringKv;
	JSONObject floatKv;

	void Cleanup() {
		if(this.intKv != null) delete this.intKv;
		if(this.stringKv != null) delete this.stringKv;
		if(this.floatKv != null) delete this.floatKv;
	}

	bool GetInt(const char[] name, int &value) {
		if(this.intKv == null) return false;
		if(!this.intKv.HasKey(name)) return false;
		value = this.intKv.GetInt(name);
		return true;
	}

	bool GetString(const char[] name, char[] buffer, int maxlen) {
		if(this.stringKv == null) return false;
		if(!this.stringKv.HasKey(name)) return false;
		this.stringKv.GetString(name, buffer, maxlen);
		return true;
	}

	bool GetFloat(const char[] name, float &value) {
		if(this.floatKv == null) return false;
		if(!this.floatKv.HasKey(name)) return false;
		value = this.floatKv.GetFloat(name);
		return true;
	}

	propertyType GetPropertyType(const char[] key) {
		if(this.intKv != null && this.intKv.HasKey(key)) return PROPERTY_INTEGER;
		if(this.floatKv != null && this.floatKv.HasKey(key)) return PROPERTY_FLOAT;
		if(this.stringKv != null && this.stringKv.HasKey(key)) return PROPERTY_STRING;
		return PROPERTY_NONE;
	}

	bool HasAny() {
		return this.intKv != null || this.floatKv != null || this.stringKv != null;
	}

	ArrayList Keys() {
		char key[128];
		ArrayList list = new ArrayList(ByteCountToCells(128));
		JSONObjectKeys keys;
		if(this.stringKv != null) {
			keys = this.stringKv.Keys()
			while(keys.ReadKey(key, sizeof(key))) {
				list.PushString(key);
			}
			delete keys;
		}
		if(this.intKv != null) {
			keys = this.intKv.Keys()
			while(keys.ReadKey(key, sizeof(key))) {
				list.PushString(key);
			}
			delete keys;
		}
		if(this.floatKv != null) {
			keys = this.floatKv.Keys()
			while(keys.ReadKey(key, sizeof(key))) {
				list.PushString(key);
			}
			delete keys;
		}
		return list;
	}

	StringMap Entries() {
		char key[128];
		StringMap kv = new StringMap();
		JSONObjectKeys keys;
		if(this.stringKv != null) {
			keys = this.stringKv.Keys()
			while(keys.ReadKey(key, sizeof(key))) {
				kv.SetValue(key, PROPERTY_STRING);
			}
			delete keys;
		}
		if(this.intKv != null) {
			keys = this.intKv.Keys()
			while(keys.ReadKey(key, sizeof(key))) {
				kv.SetValue(key, PROPERTY_INTEGER);
			}
			delete keys;
		}
		if(this.floatKv != null) {
			keys = this.floatKv.Keys()
			while(keys.ReadKey(key, sizeof(key))) {
				kv.SetValue(key, PROPERTY_FLOAT);
			}
			delete keys;
		}
		return kv;
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
	PropertyStore properties;
	JSONObject propertiesInt;
	JSONObject propertiesString;
	JSONObject propertiesFloat;

	void Cleanup() {
		if(this.keyframes != null) {
			delete this.keyframes;
		}
		this.properties.Cleanup();
	}

	void ApplyProperties(int entity) {
		if(!this.properties.HasAny()) return;
		char key[64], buffer[128];
		ArrayList keys = this.properties.Keys();
		for(int i = 0; i < keys.Length; i++) {
			keys.GetString(i, key, sizeof(key));
			// Only want to apply netprops (m_ prefix)
			if(key[0] == 'm' && key[1] == '_') {
				propertyType type = this.properties.GetPropertyType(key);
				Debug("netprop %s type %d", key, type);
				switch(type) {
					case PROPERTY_STRING: {
						this.properties.GetString(key, buffer, sizeof(buffer));
						Debug("Applying netprop %s (val=%s) on %d", key, buffer, entity);
						SetEntPropString(entity, Prop_Send, key, buffer);
						break;
					}
					case PROPERTY_INTEGER: {
						int val;
						this.properties.GetInt(key, val);
						Debug("Applying netprop %s (val=%d) on %d", key, val, entity);
						SetEntProp(entity, Prop_Send, key, val);
						break;
					}
					case PROPERTY_FLOAT: {
						float val;
						this.properties.GetFloat(key, val);
						Debug("Applying netprop %s (val=%f) on %d", key, val, entity);
						SetEntPropFloat(entity, Prop_Send, key, val);
						break;
					}
				}
			}
		}
		delete keys;
	}
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