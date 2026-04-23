void spawnEntity(VariantEntityData entity) {
	if(entity.type[0] == '_') {
		if(StrEqual(entity.type, "_gascan")) {
			AddGascanSpawner(entity);
		} else if(StrContains(entity.type, "_car") != -1) {
			SpawnCar(entity);
		} else {
			Log("WARN: Unknown custom entity type \"%s\", skipped", entity.type);
		}
	} else if(StrEqual(entity.type, "hammerid")) {
		int targetId = StringToInt(entity.model);
		if(targetId > 0) {
			int ent = -1;
			while((ent = FindEntityByClassname(ent, "*")) != INVALID_ENT_REFERENCE) {
				int hammerId = GetEntProp(ent, Prop_Data, "m_iHammerID");
				if(hammerId == targetId) {
					Debug("moved entity (hammerid=%d) to %.0f %.0f %.0f rot %.0f %.0f %.0f", targetId, entity.origin[0], entity.origin[1], entity.origin[2], entity.angles[0], entity.angles[1], entity.angles[2]);
					TeleportEntity(ent, entity.origin, entity.angles, NULL_VECTOR);
					return;
				}
			}
		}
		Debug("Warn: Could not find entity (hammerid=%d) (model=%s)", targetId, entity.model);
	} else if(StrEqual(entity.type, "targetname")) {
		int ent = -1;
		char targetname[64];
		bool found = false;
		while((ent = FindEntityByClassname(ent, "*")) != INVALID_ENT_REFERENCE) {
			GetEntPropString(ent, Prop_Data, "m_iName", targetname, sizeof(targetname));
			if(StrEqual(entity.model, targetname)) {
				Debug("moved entity (targetname=%s) to %.0f %.0f %.0f rot %.0f %.0f %.0f", entity.model, entity.origin[0], entity.origin[1], entity.origin[2], entity.angles[0], entity.angles[1], entity.angles[2]);
				TeleportEntity(ent, entity.origin, entity.angles, NULL_VECTOR);
				found = true;
			}
		}
		if(!found)
			Debug("Warn: Could not find entity (targetname=%s)", entity.model);
	} else if(StrEqual(entity.type, "classname")) {
		int ent = -1;
		char classname[64];
		bool found;
		while((ent = FindEntityByClassname(ent, classname)) != INVALID_ENT_REFERENCE) {
			Debug("moved entity (classname=%s) to %.0f %.0f %.0f rot %.0f %.0f %.0f", entity.model, entity.origin[0], entity.origin[1], entity.origin[2], entity.angles[0], entity.angles[1], entity.angles[2]);
			TeleportEntity(ent, entity.origin, entity.angles, NULL_VECTOR);
			found = true;
		}
		if(!found)
			Debug("Warn: Could not find entity (classname=%s)", entity.model);
	}  else if(StrEqual(entity.type, "env_fire")) {
		Debug("spawning \"%s\" at (%.1f %.1f %.1f) rot (%.0f %.0f %.0f)", entity.type, entity.origin[0], entity.origin[1], entity.origin[2], entity.angles[0], entity.angles[1], entity.angles[2]);
		R_CreateFire(entity);
	} else if(StrEqual(entity.type, "light_dynamic")) {
		R_CreateLight(entity);	
		Effect_DrawBeamBoxRotatableToAll(entity.origin, { -5.0, -5.0, -5.0}, { 5.0, 5.0, 5.0}, NULL_VECTOR, g_iLaserIndex, 0, 0, 0, 40.0, 0.1, 0.1, 0, 0.0, {255, 255, 0, 255}, 0);
	} else if(StrEqual(entity.type, "env_physics_blocker") || StrEqual(entity.type, "env_player_blocker")) {
		R_CreateEnvBlockerScaled(entity);
	} else if(StrEqual(entity.type, "infodecal")) {
		Effect_DrawBeamBoxRotatableToAll(entity.origin, { -1.0, -5.0, -5.0}, { 1.0, 5.0, 5.0}, NULL_VECTOR, g_iLaserIndex, 0, 0, 0, 40.0, 0.1, 0.1, 0, 0.0, {73, 0, 130, 255}, 0);
		R_CreateDecal(entity);
	} else if(StrContains(entity.type, "weapon_") == 0 || StrContains(entity.type, "prop_") == 0 || StrEqual(entity.type, "prop_fuel_barrel")) {
		if(entity.model[0] == '\0') {
			LogError("Missing model for entity with type \"%s\"", entity.type);
			return;
		} else if(!PrecacheModel(entity.model)) {
			LogError("Precache of entity model \"%s\" with type \"%s\" failed", entity.model, entity.type);
			return;
		}
		R_CreateProp(entity);
	} else if(StrEqual(entity.type, "move_rope")) {
		if(!PrecacheModel(entity.model)) {
			LogError("Precache of entity model \"%s\" with type \"%s\" failed", entity.model, entity.type);
			return;
		} else if(entity.keyframes == null) {
			// should not happen
			LogError("rope entity has no keyframes", entity.keyframes);
			return;
		}
		CreateRope(entity);
	} else if(StrEqual(entity.type, "script_nav_blocker")) {
		R_CreateNavBlocker(entity);
		float mins[3];
		mins = entity.scale;
		NegateVector(mins);
		Effect_DrawBeamBoxRotatableToAll(entity.origin, mins, entity.scale, NULL_VECTOR, g_iLaserIndex, 0, 0, 0, 40.0, 0.1, 0.1, 0, 0.0, {0, 255, 0, 255}, 0);
	} else {
		LogError("Unsupported entity type \"%s\"", entity.type);
	}
}

int R_CreateFire(VariantEntityData data) {
	int entity = CreateEntityByName("env_fire");
	if(entity == -1) return -1;
	DispatchKeyValue(entity, "spawnflags", "13");
	DispatchKeyValue(entity, "targetname", ENT_ENV_NAME);
	DispatchKeyValueFloat(entity, "firesize", 20.0);
	DispatchKeyValueFloat(entity, "fireattack", 100.0);
	DispatchKeyValueFloat(entity, "damagescale", 1.0);
	TeleportEntity(entity, data.origin, NULL_VECTOR, NULL_VECTOR);
    data.ApplyProperties(entity);
	DispatchSpawn(entity);
	AcceptEntityInput(entity, "Enable");
	AcceptEntityInput(entity, "StartFire");
	#if defined DEBUG_LOG_MAPSTART

		PrintToServer("spawn env_fire at %.1f %.1f %.1f", pos[0], pos[1], pos[2]);
	#endif
	return entity;
}

int R_CreateLight(VariantEntityData data) {
	int entity = CreateEntityByName("light_dynamic");
	if(entity == -1) return -1; 
	DispatchKeyValue(entity, "targetname", ENT_PROP_NAME);
	DispatchKeyValueInt(entity, "brightness", data.color[3]);
	DispatchKeyValueFloat(entity, "distance", data.scale[0]);
	DispatchKeyValueFloat(entity, "_inner_cone", data.angles[0]);
	DispatchKeyValueFloat(entity, "_cone", data.angles[1]);
	DispatchKeyValueFloat(entity, "pitch", data.angles[2]);
	// DispatchKeyValueInt()
	TeleportEntity(entity, data.origin, NULL_VECTOR, NULL_VECTOR);
    data.ApplyProperties(entity);
	if(!DispatchSpawn(entity)) return -1;
	SetEntityRenderColor(entity, data.color[0], data.color[1], data.color[2], data.color[3]);
	SetEntityRenderMode(entity, RENDER_TRANSCOLOR);
	AcceptEntityInput(entity, "TurnOn");
	return entity;
}

int DCOLOR_PHYS_WALL[4] = { 255, 0, 0, 255 };
int DCOLOR_NAV_WALL[4] = { 64, 0, 205, 255 };

int R_CreateEnvBlockerScaled(VariantEntityData data) {
	int entity = CreateEntityByName(data.type);
	DispatchKeyValue(entity, "targetname", ENT_BLOCKER_NAME);
	DispatchKeyValue(entity, "initialstate", "1");
	static float mins[3];
	mins = data.scale;
	NegateVector(mins);
	DispatchKeyValueVector(entity, "boxmins", mins);
	DispatchKeyValueVector(entity, "boxmaxs", data.scale);
	DispatchKeyValueVector(entity, "mins", mins);
	DispatchKeyValueVector(entity, "maxs", data.scale);

	TeleportEntity(entity, data.origin, NULL_VECTOR, NULL_VECTOR);
    data.ApplyProperties(entity);
	if(DispatchSpawn(entity)) {
		#if defined DEBUG_LOG_MAPSTART
			PrintToServer("spawn blocker scaled %.1f %.1f %.1f scale [%.0f %.0f %.0f]", pos[0], pos[1], pos[2], scale[0], scale[1], scale[2]);
		#endif
		SetEntPropVector(entity, Prop_Send, "m_vecMaxs", data.scale);
		SetEntPropVector(entity, Prop_Send, "m_vecMins", mins);
        AcceptEntityInput(entity, "Enable");
		#if defined DEBUG_BLOCKERS
			if(StrEqual(data.type, "func_nav_blocker")) {
				Effect_DrawBeamBoxRotatableToAll(data.origin, mins, data.scale, NULL_VECTOR, g_iLaserIndex, 0, 0, 0, 300.0, 0.4, 0.4, 0, 0.0, DCOLOR_NAV_WALL, 0);
			} else {
				Effect_DrawBeamBoxRotatableToAll(data.origin, mins, data.scale, NULL_VECTOR, g_iLaserIndex, 0, 0, 0, 150.0, 0.1, 0.1, 0, 0.0, DCOLOR_PHYS_WALL, 0);
			}
		#endif
		return entity;
	}
	return -1;
}

void R_CreateDecal(VariantEntityData data) {
	CreateDecal(data.model, data.origin);
}

int R_CreateProp(VariantEntityData data) {
	int entity = StartPropCreate(data.type, data.model, data.origin, data.angles, NULL_VECTOR);
	if(entity == -1) return -1;
    data.ApplyProperties(entity);
	if(DispatchSpawn(entity)) {
		return entity;
	}
	return -1;
}

int R_CreateNavBlocker(VariantEntityData entity) {
	int blocker = CreateNavBlocker(entity.targetname, entity.origin, entity.angles, entity.scale, -1, false);
	DispatchKeyValueInt(blocker, "BlockType", -1); // default to Everyone
	DispatchKeyValueInt(blocker, "affectsFlow", 0); // default to not blocking flow
	entity.ApplyProperties(blocker);
	AcceptEntityInput(blocker, "BlockNav"); // doesn't default on; activate
	return blocker;
}