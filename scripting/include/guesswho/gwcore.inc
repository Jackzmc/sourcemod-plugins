#include <guesswho/gwpoints>
#include <guesswho/gwgame>
#include <guesswho/gwcmds>
#include <guesswho/gwents>
#include <guesswho/gwtimers>

#define FOLDER_PERMS ( FPERM_U_READ |  FPERM_U_WRITE |  FPERM_U_EXEC |  FPERM_G_EXEC | FPERM_G_WRITE | FPERM_G_READ | FPERM_O_EXEC )

static KeyValues kv;
StringMap mapConfigs;

bool ReloadMapDB() {
	if(kv != null) {
		delete kv;
	}
	kv = new KeyValues("guesswho");

	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "data/guesswho");
	CreateDirectory(sPath, FOLDER_PERMS);
	Format(sPath, sizeof(sPath), "%s/config.cfg", sPath);

	if(!FileExists(sPath) || !kv.ImportFromFile(sPath)) {
		delete kv;
		return false;
	}

	validMaps.Clear();

	char map[64];
	kv.GotoFirstSubKey(true);
	do {
		kv.GetSectionName(map, sizeof(map));
		validMaps.PushString(map);
	} while(kv.GotoNextKey(true));
	kv.GoBack();
	return true;
}

static float DEFAULT_SCALE[3] = { 5.0, 5.0, 5.0 };

bool LoadConfigForMap(const char[] map) {
	kv.Rewind();
	if (kv.JumpToKey(map)) {
		MapConfig config;
		config.entities = new ArrayList(sizeof(EntityConfig));
		config.inputs = new ArrayList(ByteCountToCells(64));
		validSets.Clear();

		static char buffer[64];
		buffer[0] = '\0';
		if(StrEqual(currentSet, "default") && kv.GetString("defaultset", buffer, sizeof(buffer)) && buffer[0] != '\0') {
			strcopy(currentSet, sizeof(currentSet), buffer);
		}
		PrintToServer("[GuessWho] Loading config data for set %s on %s", currentSet, map);

		if(kv.JumpToKey("ents")) {
			kv.GotoFirstSubKey();
			do {
				EntityConfig entCfg;
				kv.GetVector("origin", entCfg.origin, NULL_VECTOR);
				kv.GetVector("rotation", entCfg.rotation, NULL_VECTOR);
				kv.GetString("type", entCfg.type, sizeof(entCfg.type), "env_physics_blocker");
				kv.GetString("model", entCfg.model, sizeof(entCfg.model), "");
				if(entCfg.model[0] != '\0')
					Format(entCfg.model, sizeof(entCfg.model), "models/%s", entCfg.model);
				kv.GetVector("scale", entCfg.scale, DEFAULT_SCALE);
				kv.GetVector("offset", entCfg.offset, NULL_VECTOR);
				kv.GetString("set", buffer, sizeof(buffer), "default");
				if(validSets.FindString(buffer) == -1) {
					validSets.PushString(buffer);
				}
				if(StrEqual(buffer, "default") || StrEqual(currentSet, buffer, false)) {
					
					config.entities.PushArray(entCfg);
				} else {
					kv.GetSectionName(buffer, sizeof(buffer));
					PrintToServer("Skipping %s", buffer);
				}
			} while (kv.GotoNextKey());
			// JumpToKey and GotoFirstSubKey both traverse, i guess, go back
			kv.GoBack();
			kv.GoBack();
		}
		if(kv.JumpToKey("inputs")) {
			kv.GotoFirstSubKey(false);
			do {
				kv.GetSectionName(buffer, sizeof(buffer));
				config.inputs.PushString(buffer);

				kv.GetString(NULL_STRING, buffer, sizeof(buffer));
				config.inputs.PushString(buffer);
			} while (kv.GotoNextKey(false));
			kv.GoBack();
			kv.GoBack();
		}
		int mapTime;

		config.hasSpawnpoint = false;
		config.canClimb = true;
		config.pressButtons = true;
		if(!StrEqual(currentSet, "default") && kv.JumpToKey("sets")) {
			char set[16];
			kv.GotoFirstSubKey(true);
			do {
				kv.GetSectionName(set, sizeof(set));
				if(validSets.FindString(set) == -1) {
					validSets.PushString(set);
				}
				if(StrEqual(currentSet, set, false)) {
					kv.GetVector("spawnpoint", config.spawnpoint);
					if(config.spawnpoint[0] != 0.0 && config.spawnpoint[1] != 0.0 && config.spawnpoint[2] != 0.0) {
						PrintToServer("[GuessWho] Using provided custom spawnpoint for set %s at %0.1f, %0.1f, %0.1f", currentSet, config.spawnpoint[0], config.spawnpoint[1], config.spawnpoint[2]);
						config.hasSpawnpoint = true;
					} 
					mapTime = kv.GetNum("maptime", 0);
					if(kv.JumpToKey("inputs")) {
						kv.GotoFirstSubKey(false);
						do {
							kv.GetSectionName(buffer, sizeof(buffer));
							config.inputs.PushString(buffer);

							kv.GetString(NULL_STRING, buffer, sizeof(buffer));
							config.inputs.PushString(buffer);
						} while (kv.GotoNextKey(false));
						kv.GoBack();
						kv.GoBack();
					}
					break;
				}
				
			} while(kv.GotoNextKey(true));
			kv.GoBack();
			kv.GoBack();
		}
		
		if(!config.hasSpawnpoint) {
			kv.GetVector("spawnpoint", config.spawnpoint);
			if(config.spawnpoint[0] != 0.0 && config.spawnpoint[1] != 0.0 && config.spawnpoint[2] != 0.0) {
				PrintToServer("[GuessWho] Using provided custom spawnpoint at %0.1f, %0.1f, %0.1f", config.spawnpoint[0], config.spawnpoint[1], config.spawnpoint[2]);
				config.hasSpawnpoint = true;
			} else if (FindSpawnPosition(config.spawnpoint, false)) {
				PrintToServer("[GuessWho] Using map spawnpoint at %0.1f, %0.1f, %0.1f", config.spawnpoint[0], config.spawnpoint[1], config.spawnpoint[2]);
				config.hasSpawnpoint = true;
			} else {
				PrintToServer("[GuessWho] Could not find any spawnpoints, using default spawn");
				config.hasSpawnpoint = false;
			}
		}

		// Use default maptime if exists
		if(mapTime == 0)
			mapTime = kv.GetNum("maptime", 0);
		if(mapTime > 0) {
			config.mapTime = mapTime;
			PrintToServer("[GuessWho] Map time overwritten to %d seconds", mapTime);
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
		PrintToServer("[GuessWho] %s has no config entry", map);
		return false;
	}
}