#define FOLDER_PERMS ( FPERM_U_READ |  FPERM_U_WRITE |  FPERM_U_EXEC |  FPERM_G_EXEC | FPERM_G_WRITE | FPERM_G_READ | FPERM_O_EXEC )

#include <prophunt/phgame>
#include <prophunt/phcmds>
#include <prophunt/phents>
#include <prophunt/phtimers>


static KeyValues mapsKv;
StringMap mapConfigs;

bool ReloadMapDB() {
	if(mapsKv != null) {
		delete mapsKv;
	}
	mapsKv = new KeyValues("prophunt");

	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "data/prophunt");
	CreateDirectory(sPath, FOLDER_PERMS);
	Format(sPath, sizeof(sPath), "%s/maps.cfg", sPath);

	if(!FileExists(sPath) || !mapsKv.ImportFromFile(sPath)) {
		delete mapsKv;
		return false;
	}

	validMaps.Clear();

	char map[64];
	mapsKv.GotoFirstSubKey(true);
	do {
		mapsKv.GetSectionName(map, sizeof(map));
		validMaps.PushString(map);
	} while(mapsKv.GotoNextKey(true));
	mapsKv.GoBack();

	PrintToServer("[PropHunt] Loaded %d map configs", validMaps.Length);
	return true;
}

bool ReloadPropDB() {
	if(propHealths != null)
		delete propHealths;
	propHealths = new StringMap();
	KeyValues propKv = new KeyValues("props");

	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "data/prophunt");
	CreateDirectory(sPath, FOLDER_PERMS);
	Format(sPath, sizeof(sPath), "%s/props.cfg", sPath);

	if(!FileExists(sPath) || !propKv.ImportFromFile(sPath)) {
		delete propKv;
		return false;
	}

	char model[64];
	propKv.GotoFirstSubKey(false);
	do {
		propKv.GetSectionName(model, sizeof(model));
		propHealths.SetValue(model, propKv.GetNum(NULL_STRING));
	} while(propKv.GotoNextKey(false));

	PrintToServer("[PropHunt] Loaded %d models", propHealths.Size);

	delete propKv;
	return true;
}

static float DEFAULT_SCALE[3] = { 5.0, 5.0, 5.0 };

bool LoadConfigForMap(const char[] map) {
	mapsKv.Rewind();
	if (mapsKv.JumpToKey(map)) {
		MapConfig config;
		config.entities = new ArrayList(sizeof(EntityConfig));
		config.inputs = new ArrayList(ByteCountToCells(64));
		validSets.Clear();

		static char buffer[64];
		buffer[0] = '\0';
		if(StrEqual(g_currentSet, "default") && mapsKv.GetString("defaultset", buffer, sizeof(buffer)) && buffer[0] != '\0') {
			strcopy(g_currentSet, sizeof(g_currentSet), buffer);
		}
		PrintToServer("[PropHunt] Loading config data for set %s on %s", g_currentSet, map);

		if(mapsKv.JumpToKey("props")) {
			mapsKv.GotoFirstSubKey();
			do {
				EntityConfig entCfg;
				mapsKv.GetVector("origin", entCfg.origin, NULL_VECTOR);
				mapsKv.GetVector("rotation", entCfg.rotation, NULL_VECTOR);
				mapsKv.GetString("type", entCfg.type, sizeof(entCfg.type), "prop_dynamic");
				mapsKv.GetString("model", entCfg.model, sizeof(entCfg.model), "");
				if(entCfg.model[0] != '\0')
					Format(entCfg.model, sizeof(entCfg.model), "models/%s", entCfg.model);
				mapsKv.GetVector("scale", entCfg.scale, DEFAULT_SCALE);
				mapsKv.GetVector("offset", entCfg.offset, NULL_VECTOR);
				mapsKv.GetString("set", buffer, sizeof(buffer), "default");
				if(validSets.FindString(buffer) == -1) {
					validSets.PushString(buffer);
				}
				if(StrEqual(buffer, "default") || StrEqual(g_currentSet, buffer, false)) {
					
					config.entities.PushArray(entCfg);
				} else {
					mapsKv.GetSectionName(buffer, sizeof(buffer));
					PrintToServer("Skipping %s", buffer);
				}
			} while (mapsKv.GotoNextKey());
			// JumpToKey and GotoFirstSubKey both traverse, i guess, go back
			mapsKv.GoBack();
			mapsKv.GoBack();
		}
		if(mapsKv.JumpToKey("inputs")) {
			mapsKv.GotoFirstSubKey(false);
			do {
				mapsKv.GetSectionName(buffer, sizeof(buffer));
				config.inputs.PushString(buffer);

				mapsKv.GetString(NULL_STRING, buffer, sizeof(buffer));
				config.inputs.PushString(buffer);
			} while (mapsKv.GotoNextKey(false));
			mapsKv.GoBack();
			mapsKv.GoBack();
		}
		int mapTime;

		config.hasSpawnpoint = false;
		config.canClimb = true;
		config.pressButtons = true;
		if(!StrEqual(g_currentSet, "default") && mapsKv.JumpToKey("sets")) {
			char set[16];
			mapsKv.GotoFirstSubKey(true);
			do {
				mapsKv.GetSectionName(set, sizeof(set));
				if(validSets.FindString(set) == -1) {
					validSets.PushString(set);
				}
				if(StrEqual(g_currentSet, set, false)) {
					mapsKv.GetVector("spawnpoint", config.spawnpoint);
					if(config.spawnpoint[0] != 0.0 && config.spawnpoint[1] != 0.0 && config.spawnpoint[2] != 0.0) {
						PrintToServer("[PropHunt] Using provided custom spawnpoint for set %s at %0.1f, %0.1f, %0.1f", g_currentSet, config.spawnpoint[0], config.spawnpoint[1], config.spawnpoint[2]);
						config.hasSpawnpoint = true;
					} 
					mapTime = mapsKv.GetNum("maptime", 0);
					if(mapsKv.JumpToKey("inputs")) {
						mapsKv.GotoFirstSubKey(false);
						do {
							mapsKv.GetSectionName(buffer, sizeof(buffer));
							config.inputs.PushString(buffer);

							mapsKv.GetString(NULL_STRING, buffer, sizeof(buffer));
							config.inputs.PushString(buffer);
						} while (mapsKv.GotoNextKey(false));
						mapsKv.GoBack();
						mapsKv.GoBack();
					}
					break;
				}
				
			} while(mapsKv.GotoNextKey(true));
			mapsKv.GoBack();
			mapsKv.GoBack();
		}
		
		if(!config.hasSpawnpoint) {
			mapsKv.GetVector("spawnpoint", config.spawnpoint);
			if(config.spawnpoint[0] != 0.0 && config.spawnpoint[1] != 0.0 && config.spawnpoint[2] != 0.0) {
				PrintToServer("[PropHunt] Using provided custom spawnpoint at %0.1f, %0.1f, %0.1f", config.spawnpoint[0], config.spawnpoint[1], config.spawnpoint[2]);
				config.hasSpawnpoint = true;
			} else if (FindSpawnPosition(config.spawnpoint, false)) {
				PrintToServer("[PropHunt] Using map spawnpoint at %0.1f, %0.1f, %0.1f", config.spawnpoint[0], config.spawnpoint[1], config.spawnpoint[2]);
				config.hasSpawnpoint = true;
			} else {
				PrintToServer("[PropHunt] Could not find any spawnpoints, using default spawn");
				config.hasSpawnpoint = false;
			}
		}

		// Use default maptime if exists
		if(mapTime == 0)
			mapTime = mapsKv.GetNum("maptime", 0);
		if(mapTime > 0) {
			config.mapTime = mapTime;
			PrintToServer("[PropHunt] Map time overwritten to %d seconds", mapTime);
		}

		mapConfigs.SetArray(map, config, sizeof(MapConfig));
		// Discard entInputs if unused
		if(config.inputs.Length == 0) {
			delete config.inputs;
		}
		mapConfig = config;
		return true;
	} else {
		mapConfig.hasSpawnpoint = false;
		PrintToServer("[PropHunt] %s has no config entry", map);
		return false;
	}
}