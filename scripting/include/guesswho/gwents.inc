#define ENT_PROP_NAME "gwprop"
#define ENT_BLOCKER_NAME "gwblocker"
#define ENT_PORTAL_NAME "gwportal"
#define ENT_ENV_NAME "gwenv"
#include <gamemodes/ents>

stock void CheatCommand(int client, const char[] command, const char[] argument1) {
	int userFlags = GetUserFlagBits(client);
	SetUserFlagBits(client, ADMFLAG_ROOT);
	int flags = GetCommandFlags(command);
	SetCommandFlags(command, flags & ~FCVAR_CHEAT);
	FakeClientCommand(client, "%s %s", command, argument1);
	SetCommandFlags(command, flags);
	SetUserFlagBits(client, userFlags);
} 


stock void EntFire(const char[] name, const char[] input) {
	static char targetname[64];
	static char cmd[32];
	#if defined DEBUG_LOG_MAPSTART
	PrintToServer("EntFire: %s \"%s\"", name, input);
	#endif
	int len = SplitString(input, " ", cmd, sizeof(cmd));
	if(len > -1) SetVariantString(input[len]);

	int hammerId = name[0] == '!' ? StringToInt(name[1]) : 0;
	for(int i = MaxClients + 1; i <= 4096; i++) {
		if(IsValidEntity(i) && (IsValidEdict(i) || EntIndexToEntRef(i) != -1)) {
			if(hammerId > 0) {
				if(hammerId == Entity_GetHammerId(i)) {
					if(len > -1) AcceptEntityInput(i, cmd);
					else AcceptEntityInput(i, input);
				}
			} else {
				GetEntPropString(i, Prop_Data, "m_iName", targetname, sizeof(targetname));
				if(StrEqual(targetname, name, false)) {
					if(len > -1) AcceptEntityInput(i, cmd);
					else AcceptEntityInput(i, input);
					
				}  else { 
					GetEntityClassname(i, targetname, sizeof(targetname));
					if(StrEqual(targetname, name, false)) {
						if(len > -1) AcceptEntityInput(i, cmd);
						else AcceptEntityInput(i, input);
					}
				}
			}
		}
	}
}

void CreateCoinEntity(float pos[3]) {
	// int ent = CreateProp("prop_dynamic", "")
}

void SetupEntities(bool blockers = true, bool props = true, bool portals = true) {
	#if defined DEBUG_BLOCKERS
	if(mapConfig.hasSpawnpoint) {
		PrecacheModel("survivors/survivor_teenangst.mdl", true);
		int dummy = CreateDummy("models/survivors/survivor_teenangst.mdl", "idle", mapConfig.spawnpoint, NULL_VECTOR);
		SetEntProp(dummy, Prop_Data, "m_nSolidType", 0);
		SetEntProp(dummy, Prop_Send, "m_CollisionGroup", 0);
		SetEntProp(dummy, Prop_Send, "movetype", MOVETYPE_NONE);
	}
	EntFire("info_changelevel", "Kill");
	#endif
	if(mapConfig.entities != null) {
		PrintToServer("[GuessWho] Deploying %d custom entities (Set: %s) (blockers:%b props:%b portals:%b)", mapConfig.entities.Length, g_currentSet, blockers, props, portals);
		for(int i = 0; i < mapConfig.entities.Length; i++) {
			EntityConfig config;
			mapConfig.entities.GetArray(i, config);

			if(config.model[0] != '\0') PrecacheModel(config.model);

			if(StrEqual(config.type, "env_physics_blocker")) {
				if(blockers && CreateEnvBlockerScaled(config.type, config.origin, config.scale, isNavBlockersEnabled) == -1) { 
					Game.Warn("Failed to spawn blocker [type=%s] at (%.1f,%.1f, %.1f)", config.type, config.origin[0], config.origin[1], config.origin[2]);
				}
			} else if(StrEqual(config.type, "_relportal")) {
				if(portals && CreatePortal(Portal_Relative, config.model, config.origin, config.offset, config.scale) == -1) {
					Game.Warn("Failed to spawn rel portal at (%.1f,%.1f, %.1f)", config.origin[0], config.origin[1], config.origin[2]);
				}
			} else if(StrEqual(config.type, "_portal")) {
				if(portals && CreatePortal(Portal_Teleport, config.model, config.origin, config.offset, config.scale) == -1) {
					Game.Warn("Failed to spawn portal at (%.1f,%.1f, %.1f)", config.origin[0], config.origin[1], config.origin[2]);
				}
			} else if(StrEqual(config.type, "_lantern")) {
				int parent = CreateProp("prop_dynamic", config.model, config.origin, config.rotation);
				if(parent == -1) { 
					Game.Warn("Failed to spawn prop [type=%s] [model=%s] at (%.1f,%.1f, %.1f)", config.type, config.model, config.origin[0], config.origin[1], config.origin[2]);
				} else {
					float pos[3];
					pos = config.origin;
					pos[2] += 15.0;
					int child = CreateDynamicLight(pos, config.rotation, GetColorInt(255, 255, 242), 80.0, 11);
					if(child == -1) { 
						Game.Warn("Failed to spawn light source for _lantern");
					} else {
						SetParent(child, parent);
						TeleportEntity(parent, config.origin, NULL_VECTOR, NULL_VECTOR);
					}
				}
			} else if(StrEqual(config.type, "_dummy")) {
				if(CreateDummy(config.model, "hitby_tankpunch", config.origin, config.rotation) == -1) { 
					Game.Warn("Failed to spawn dummy [model=%s] at (%.1f,%.1f, %.1f)", config.model, config.origin[0], config.origin[1], config.origin[2]);
				}
			} else if(StrEqual(config.type, "env_fire")) {
				if(props && CreateFire(config.origin, config.scale[0], config.scale[1], config.scale[2]) == -1) { 
					Game.Warn("Failed to spawn env_fire at (%.1f,%.1f, %.1f)", config.origin[0], config.origin[1], config.origin[2]);
				}
			} else if(props) {
				if(CreateProp(config.type, config.model, config.origin, config.rotation) == -1) { 
					Game.Warn("Failed to spawn prop [type=%s] [model=%s] at (%.1f,%.1f, %.1f)", config.type, config.model, config.origin[0], config.origin[1], config.origin[2]);
				}
			}
		}

		static char key[64];
		static char value[64];
		if(mapConfig.inputs != null) {
			for(int i = 0; i < mapConfig.inputs.Length - 1; i += 2) {
				mapConfig.inputs.GetString(i, key, sizeof(key));
				mapConfig.inputs.GetString(i + 1, value, sizeof(value));
				EntFire(key, value);
			}
		}
	}
}

