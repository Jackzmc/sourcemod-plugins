stock int CreateEnvBlockerBox(const float pos[3], bool enabled = true) {
	int entity = CreateEntityByName("env_physics_blocker");
	if(entity == -1) return -1;
	DispatchKeyValue(entity, "targetname", "hsblocker");
	DispatchKeyValue(entity, "initialstate", "1");
	DispatchKeyValue(entity, "BlockType", "0");
	TeleportEntity(entity, pos, NULL_VECTOR, NULL_VECTOR);
	if(DispatchSpawn(entity)) {
		if(enabled)
			AcceptEntityInput(entity, "Enable");
		return entity;
	}
	return -1;
}

stock int CreateEnvBlockerScaled(const char[] entClass, const float pos[3], const float scale[3] = { 5.0, 5.0, 5.0 }, bool enabled = true) {
	int entity = CreateEntityByName(entClass);
	DispatchKeyValue(entity, "targetname", "hsblocker");
	DispatchKeyValue(entity, "initialstate", "1");
	DispatchKeyValue(entity, "BlockType", "0");
	static float mins[3];
	mins = scale;
	NegateVector(mins);
	DispatchKeyValueVector(entity, "boxmins", mins);
	DispatchKeyValueVector(entity, "boxmaxs", scale);
	DispatchKeyValueVector(entity, "mins", mins);
	DispatchKeyValueVector(entity, "maxs", scale);

	TeleportEntity(entity, pos, NULL_VECTOR, NULL_VECTOR);
	if(DispatchSpawn(entity)) {
		#if defined DEBUG_LOG_MAPSTART
			PrintToServer("spawn blocker scaled %.1f %.1f %.1f scale [%.0f %.0f %.0f]", pos[0], pos[1], pos[2], scale[0], scale[1], scale[2]);
		#endif
		SetEntPropVector(entity, Prop_Send, "m_vecMaxs", scale);
		SetEntPropVector(entity, Prop_Send, "m_vecMins", mins);
		if(enabled)
			AcceptEntityInput(entity, "Enable");
		#if defined DEBUG_BLOCKERS
			Effect_DrawBeamBoxRotatableToAll(pos, mins, scale, NULL_VECTOR, g_iLaserIndex, 0, 0, 0, 150.0, 0.1, 0.1, 0, 0.0, {255, 0, 0, 255}, 0);
		#endif
		return entity;
	}
	return -1;
}

enum PortalType {
	Portal_Relative,
	Portal_Teleport
}
PortalType  entityPortalType[2048];
float entityPortalOffsets[2048][3];

stock int CreatePortal(PortalType type, const char model[64], const float pos[3], const float offset[3] = { 40.0, 40.0, 0.0 }, const float scale[3] = { 5.0, 5.0, 5.0 }) {
	int entity = CreateEntityByName("trigger_multiple");
	if(entity == -1) return -1;
	DispatchKeyValue(entity, "spawnflags", "513");
	DispatchKeyValue(entity, "solid", "6");
	DispatchKeyValue(entity, "targetname", "hsportal");
	DispatchKeyValue(entity, "wait", "0");
	if(DispatchSpawn(entity)) {
		TeleportEntity(entity, pos, NULL_VECTOR, NULL_VECTOR);
		static float mins[3];
		mins = scale;
		NegateVector(mins);
		SetEntPropVector(entity, Prop_Send, "m_vecMaxs", scale);
		SetEntPropVector(entity, Prop_Send, "m_vecMins", mins);
		SetEntProp(entity, Prop_Send, "m_nSolidType", 2);

		HookSingleEntityOutput(entity, "OnStartTouch", OnPortalTouch, false);
		#if defined DEBUG_BLOCKERS
		Effect_DrawBeamBoxRotatableToAll(pos, mins, scale, NULL_VECTOR, g_iLaserIndex, 0, 0, 0, 150.0, 0.1, 0.1, 0, 0.0, {255, 0, 255, 255}, 0);
		#endif
		#if defined DEBUG_LOG_MAPSTART
		PrintToServer("spawn portal %d - pos %.1f %.1f %.1f - scale %.1f %.1f %.1f", entity, pos[0], pos[1], pos[2], scale[0], scale[1], scale[2]);
		#endif
		AcceptEntityInput(entity, "Enable");

		entityPortalOffsets[entity] = NULL_VECTOR;

		// Convert relative offset to one based off full scale:
		entityPortalType[entity] = type;
		if(type == Portal_Relative) {
			if(offset[0] != 0.0) entityPortalOffsets[entity][0] = (scale[0] * 2) + offset[0];
			if(offset[1] != 0.0) entityPortalOffsets[entity][1] = (scale[1] * 2) + offset[1];
			if(offset[2] != 0.0) entityPortalOffsets[entity][2] = (scale[2] * 2) + offset[2];
		} else {
			entityPortalOffsets[entity] = offset;
		}

		return entity;
	}
	return -1;
}

void OnPortalTouch(const char[] output, int caller, int activator, float delay) { 
	if(entityPortalType[caller] == Portal_Relative) {
		float pos[3];
		GetClientAbsOrigin(activator, pos);
		float ang[3];
		GetClientAbsAngles(activator, ang);
		if(ang[0] < 0) pos[0] -= entityPortalOffsets[caller][0];
		else pos[0] += entityPortalOffsets[caller][0];
		if(ang[1] < 0) pos[1] -= entityPortalOffsets[caller][1];
		else pos[1] += entityPortalOffsets[caller][1];
		if(ang[2] < 0) pos[2] -= entityPortalOffsets[caller][2];
		else pos[2] += entityPortalOffsets[caller][2];
		TeleportEntity(activator, pos, NULL_VECTOR, NULL_VECTOR);
	} else {
		TeleportEntity(activator, entityPortalOffsets[caller], NULL_VECTOR, NULL_VECTOR);
	}
}

stock int StartPropCreate(const char[] entClass, const char[] model, const float pos[3], const float ang[3]) {
	int entity = CreateEntityByName(entClass);
	if(entity == -1) return -1;
	DispatchKeyValue(entity, "model", model);
	DispatchKeyValue(entity, "solid", "6");
	DispatchKeyValue(entity, "targetname", "hsprop");
	DispatchKeyValue(entity, "disableshadows", "1");
	TeleportEntity(entity, pos, ang, NULL_VECTOR);
	return entity;
}

stock int CreateProp(const char[] entClass, const char[] model, const float pos[3], const float ang[3]) {
	int entity = StartPropCreate(entClass, model, pos, ang);
	if(DispatchSpawn(entity)) {
		#if defined DEBUG_LOG_MAPSTART
		PrintToServer("spawn prop %.1f %.1f %.1f model %s", pos[0], pos[1], pos[2], model[7]);
		#endif
		return entity;
	}
	return -1;
}

stock int CreateDummy(const char[] model, const char[] anim, const float pos[3], const float ang[3] = NULL_VECTOR) {
	int entity = StartPropCreate("commentary_dummy", model, pos, ang);
	if(entity == -1) return -1;
	DispatchKeyValue(entity, "LookAtPlayers", "Yes");
	DispatchKeyValue(entity, "StartingWeapons", "weapon_rifle_ak47");
	DispatchKeyValue(entity, "StartingAnim", anim); //idle_calm_rifle
	DispatchKeyValueFloat(entity, "LookAtPlayers", 40.0);
	DispatchSpawn(entity);
	return entity;
}

// Taken from silver's https://forums.alliedmods.net/showthread.php?p=1658873
stock int CreateDynamicLight(float vOrigin[3], float vAngles[3], int color, float brightness, int style = 0) {
	int entity = CreateEntityByName("light_dynamic");
	if( entity == -1)
		return -1;

	DispatchKeyValue(entity, "_light", "0 0 0 255");
	DispatchKeyValue(entity, "brightness", "1");
	DispatchKeyValueFloat(entity, "spotlight_radius", 32.0);
	DispatchKeyValueFloat(entity, "distance", brightness);
	DispatchKeyValue(entity, "targetname", "hslamp");
	DispatchKeyValueFloat(entity, "style", float(style));
	SetEntProp(entity, Prop_Send, "m_clrRender", color);
	if(DispatchSpawn(entity)) {
		TeleportEntity(entity, vOrigin, vAngles, NULL_VECTOR);
		AcceptEntityInput(entity, "TurnOn");
		#if defined DEBUG_LOG_MAPSTART
		PrintToServer("spawn dynamic light %.1f %.1f %.1f", vOrigin[0], vOrigin[1], vOrigin[2]);
		#endif
		return entity;
	}
	return -1;
}


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
	PrintToServer("[H&S] EntFire: %s \"%s\"", name, input);
	#endif
	int len = SplitString(input, " ", cmd, sizeof(cmd));
	if(len > -1) SetVariantString(input[len]);

	int hammerId = name[0] == '!' ? StringToInt(name[1]) : 0;
	bool setTeam = StrEqual(cmd, "_setteam");
	for(int i = MaxClients + 1; i <= 4096; i++) {
		if(IsValidEntity(i) && (IsValidEdict(i) || EntIndexToEntRef(i) != -1)) {
			if(hammerId > 0) {
				if(hammerId == GetHammerId(i)) {
					if(setTeam) {
						SDKHook(i, SDKHook_TraceAttackPost, Hook_OnAttackPost);
						SetEntProp(i, Prop_Send, "m_iTeamNum", 0);
					} else if(len > -1) AcceptEntityInput(i, cmd);
					else AcceptEntityInput(i, input);
				}
			} else {
				GetEntPropString(i, Prop_Data, "m_iName", targetname, sizeof(targetname));
				if(StrEqual(targetname, name, false)) {
					if(setTeam) {
						SDKHook(i, SDKHook_TraceAttackPost, Hook_OnAttackPost);
						SetEntProp(i, Prop_Send, "m_iTeamNum", 0);
					} else if(len > -1) AcceptEntityInput(i, cmd);
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

int GetHammerId(int entity) {
    return HasEntProp(entity, Prop_Data, "m_iHammerID") ? GetEntProp(entity, Prop_Data, "m_iHammerID") : -1;
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
	#endif
	if(mapConfig.entities != null) {
		PrintToServer("[H&S] Deploying %d custom entities (Set: %s) (blockers:%b props:%b portals:%b)", mapConfig.entities.Length, g_currentSet, blockers, props, portals);
		for(int i = 0; i < mapConfig.entities.Length; i++) {
			EntityConfig config;
			mapConfig.entities.GetArray(i, config);

			if(config.model[0] != '\0') PrecacheModel(config.model);

			if(StrEqual(config.type, "env_physics_blocker")) {
				if(blockers && CreateEnvBlockerScaled(config.type, config.origin, config.scale, isNavBlockersEnabled) == -1) { 
					PrintToServer("[H&S:WARN] Failed to spawn blocker [type=%s] at (%.1f,%.1f, %.1f)", config.type, config.origin[0], config.origin[1], config.origin[2]);
				}
			} else if(StrEqual(config.type, "_relportal")) {
				if(portals && CreatePortal(Portal_Relative, config.model, config.origin, config.offset, config.scale) == -1) {
					PrintToServer("[H&S:WARN] Failed to spawn rel portal at (%.1f,%.1f, %.1f)", config.origin[0], config.origin[1], config.origin[2]);
				}
			} else if(StrEqual(config.type, "_portal")) {
				if(portals && CreatePortal(Portal_Teleport, config.model, config.origin, config.offset, config.scale) == -1) {
					PrintToServer("[H&S:WARN] Failed to spawn portal at (%.1f,%.1f, %.1f)", config.origin[0], config.origin[1], config.origin[2]);
				}
			} else if(StrEqual(config.type, "_lantern")) {
				int parent = CreateProp("prop_dynamic", config.model, config.origin, config.rotation);
				if(parent == -1) { 
					PrintToServer("[H&S:WARN] Failed to spawn prop [type=%s] [model=%s] at (%.1f,%.1f, %.1f)", config.type, config.model, config.origin[0], config.origin[1], config.origin[2]);
				} else {
					float pos[3];
					pos = config.origin;
					pos[2] += 15.0;
					int child = CreateDynamicLight(pos, config.rotation, GetColorInt(255, 255, 242), 80.0, 11);
					if(child == -1) { 
						PrintToServer("[H&S] Failed to spawn light source for _lantern");
					} else {
						SetParent(child, parent);
						TeleportEntity(parent, config.origin, NULL_VECTOR, NULL_VECTOR);
					}
				}
			} else if(StrEqual(config.type, "_dummy")) {
				if(CreateDummy(config.model, "hitby_tankpunch", config.origin, config.rotation) == -1) { 
					PrintToServer("[H&S:WARN] Failed to spawn dummy [model=%s] at (%.1f,%.1f, %.1f)", config.model, config.origin[0], config.origin[1], config.origin[2]);
				}
			}else if(props) {
				if(CreateProp(config.type, config.model, config.origin, config.rotation) == -1) { 
					PrintToServer("[H&S:WARN] Failed to spawn prop [type=%s] [model=%s] at (%.1f,%.1f, %.1f)", config.type, config.model, config.origin[0], config.origin[1], config.origin[2]);
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

