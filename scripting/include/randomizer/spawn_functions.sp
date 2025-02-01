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

int R_CreateEnvBlockerScaled(VariantEntityData data) {
	int entity = CreateEntityByName(data.type);
	DispatchKeyValue(entity, "targetname", ENT_BLOCKER_NAME);
	DispatchKeyValue(entity, "initialstate", "1");
	DispatchKeyValueInt(entity, "BlockType", StrEqual(data.type, "env_physics_blocker") ? 4 : 0);
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
			Effect_DrawBeamBoxRotatableToAll(data.origin, mins, data.scale, NULL_VECTOR, g_iLaserIndex, 0, 0, 0, 150.0, 0.1, 0.1, 0, 0.0, {255, 0, 0, 255}, 0);
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