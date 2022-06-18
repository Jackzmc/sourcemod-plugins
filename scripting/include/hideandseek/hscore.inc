#include <hideandseek/hsgame>
#include <hideandseek/hscmds>
#include <hideandseek/hsents>

static KeyValues kv;
StringMap mapConfigs;

bool ReloadMapDB() {
	if(kv != null) {
		delete kv;
	}
	kv = new KeyValues("hideandseek");

	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "data/hideandseek.cfg");


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


bool LoadConfigForMap(const char[] map) {
	kv.Rewind();
	if (kv.JumpToKey(map)) {
		MapConfig config;
		config.entities = new ArrayList(sizeof(EntityConfig));
		config.inputs = new ArrayList(ByteCountToCells(64));
		validSets.Clear();

		static char buffer[64];
		if(StrEqual(currentSet, "default") && kv.GetString("defaultset", buffer, sizeof(buffer))) {
			strcopy(currentSet, sizeof(currentSet), buffer);
		}
		PrintToServer("[H&S] Loading config data for set %s on %s", currentSet, map);

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
						PrintToServer("[H&S] Using provided custom spawnpoint for set %s at %0.1f, %0.1f, %0.1f", currentSet, config.spawnpoint[0], config.spawnpoint[1], config.spawnpoint[2]);
						config.hasSpawnpoint = true;
					} 
					char buf[8];
					kv.GetString("climbing", buf, sizeof(buf));
					config.canClimb = !StrEqual(buf, "off");
					kv.GetString("buttons", buf, sizeof(buf));
					config.pressButtons = !StrEqual(buf, "no");
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
				PrintToServer("[H&S] Using provided custom spawnpoint at %0.1f, %0.1f, %0.1f", config.spawnpoint[0], config.spawnpoint[1], config.spawnpoint[2]);
				config.hasSpawnpoint = true;
			} else if (GetSpawnPosition(config.spawnpoint, false)) {
				PrintToServer("[H&S] Using map spawnpoint at %0.1f, %0.1f, %0.1f", config.spawnpoint[0], config.spawnpoint[1], config.spawnpoint[2]);
				config.hasSpawnpoint = true;
			} else {
				PrintToServer("[H&S] Could not find any spawnpoints, using default spawn");
				config.hasSpawnpoint = false;
			}
		}

		// Use default maptime if exists
		if(mapTime == 0)
			mapTime = kv.GetNum("maptime", 0);
		if(mapTime > 0) {
			config.mapTime = mapTime;
			PrintToServer("[H&S] Map time overwritten to %d seconds", mapTime);
		}

		char buf[8];
		if(config.canClimb) {
			kv.GetString("climbing", buf, sizeof(buf));
			config.canClimb = !StrEqual(buf, "off");
		}
		if(config.pressButtons) {
			kv.GetString("buttons", buf, sizeof(buf));
			config.pressButtons = !StrEqual(buf, "no");
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
		PrintToServer("[H&S] No map config exists for %s", map);
		return false;
	}
}

int COLOR_GREY[4] = { 194, 197, 204, 255 };
int COLOR_GREEN[4] = { 0, 128, 0, 255 };

void ShowBeacon(int target, float radius = 100.0) {
	float vec[3];
	GetClientAbsOrigin(target, vec);
	vec[2] += 10;

	if (g_BeamSprite > -1 && g_HaloSprite > -1) {
		TE_SetupBeamRingPoint(vec, 10.0, radius, g_BeamSprite, g_HaloSprite, 0, 15, 0.5, 5.0, 0.0, COLOR_GREY, 10, 0);
		TE_SendToAll();
		TE_SetupBeamRingPoint(vec, 10.0, radius, g_BeamSprite, g_HaloSprite, 0, 10, 0.6, 10.0, 0.5, COLOR_GREEN, 10, 0);
		TE_SendToAll();
	}
	
	GetClientEyePosition(target, vec);
	EmitAmbientSound("buttons/button17.wav", vec, target, SNDLEVEL_RAIDSIREN);	
}