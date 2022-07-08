#if !defined ENT_PROP_NAME
	#define ENT_PROP_NAME "cprop"
#endif
#if !defined ENT_BLOCKER_NAME
	#define ENT_BLOCKER_NAME "cblocker"
#endif
#if !defined ENT_PORTAL_NAME
	#define ENT_PORTAL_NAME "cportal"
#endif
#if !defined ENT_ENV_NAME
	#define ENT_ENV_NAME "cenv"
#endif

void DeleteCustomEnts() {
	EntFire(ENT_PROP_NAME, "Kill");
	EntFire(ENT_BLOCKER_NAME, "Kill");
	EntFire(ENT_PORTAL_NAME, "Kill");
	EntFire(ENT_ENV_NAME, "Kill");
}

stock int CreateEnvBlockerScaled(const char[] entClass, const float pos[3], const float scale[3] = { 5.0, 5.0, 5.0 }, bool enabled = true) {
	int entity = CreateEntityByName(entClass);
	DispatchKeyValue(entity, "targetname", ENT_BLOCKER_NAME);
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
	} else {
		#if defined DEBUG_LOG_MAPSTART
			PrintToServer("FAILED: spawn blocker scaled %.1f %.1f %.1f scale [%.0f %.0f %.0f]", pos[0], pos[1], pos[2], scale[0], scale[1], scale[2]);
		#endif
	}
	return -1;
}

enum PortalType {
	Portal_Relative,
	Portal_Teleport
}
enum struct EntData {
	PortalType portalType;
	float portalOffsets[3];
}
EntData entData[2048];

stock int CreatePortal(PortalType type, const char model[64], const float pos[3], const float offset[3] = { 40.0, 40.0, 0.0 }, const float scale[3] = { 5.0, 5.0, 5.0 }) {
	int entity = CreateEntityByName("trigger_multiple");
	if(entity == -1) return -1;
	DispatchKeyValue(entity, "spawnflags", "513");
	DispatchKeyValue(entity, "solid", "6");
	DispatchKeyValue(entity, "targetname", ENT_PORTAL_NAME);
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

		entData[entity].portalOffsets = NULL_VECTOR;

		// Convert relative offset to one based off full scale:
		entData[entity].portalType = type;
		if(type == Portal_Relative) {
			if(offset[0] != 0.0) entData[entity].portalOffsets[0] = (scale[0] * 2) + offset[0];
			if(offset[1] != 0.0) entData[entity].portalOffsets[1] = (scale[1] * 2) + offset[1];
			if(offset[2] != 0.0) entData[entity].portalOffsets[2] = (scale[2] * 2) + offset[2];
		} else {
			entData[entity].portalOffsets = offset;
		}

		return entity;
	}
	return -1;
}

void OnPortalTouch(const char[] output, int caller, int activator, float delay) { 
	if(entData[caller].portalType == Portal_Relative) {
		float pos[3];
		GetClientAbsOrigin(activator, pos);
		float ang[3];
		GetClientAbsAngles(activator, ang);
		if(ang[0] < 0) pos[0] -= entData[caller].portalOffsets[0];
		else pos[0] += entData[caller].portalOffsets[0];
		if(ang[1] < 0) pos[1] -= entData[caller].portalOffsets[1];
		else pos[1] += entData[caller].portalOffsets[1];
		if(ang[2] < 0) pos[2] -= entData[caller].portalOffsets[2];
		else pos[2] += entData[caller].portalOffsets[2];
		TeleportEntity(activator, pos, NULL_VECTOR, NULL_VECTOR);
	} else {
		TeleportEntity(activator, entData[caller].portalOffsets, NULL_VECTOR, NULL_VECTOR);
	}
}

stock int StartPropCreate(const char[] entClass, const char[] model, const float pos[3], const float ang[3]) {
	int entity = CreateEntityByName(entClass);
	if(entity == -1) return -1;
	DispatchKeyValue(entity, "model", model);
	DispatchKeyValue(entity, "solid", "6");
	DispatchKeyValue(entity, "targetname", ENT_PROP_NAME);
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
	DispatchKeyValue(entity, "targetname", ENT_PROP_NAME);
	DispatchKeyValue(entity, "LookAtPlayers", "Yes");
	DispatchKeyValue(entity, "StartingWeapons", "weapon_rifle_ak47");
	DispatchKeyValue(entity, "StartingAnim", anim); //idle_calm_rifle
	DispatchKeyValueFloat(entity, "LookAtPlayers", 40.0);
	DispatchSpawn(entity);
	return entity;
}

stock int CreateFire(const float pos[3], float damage = 10.0, float size = 256.0, float attack = 4.0) {
	int entity = CreateEntityByName("env_fire");
	if(entity == -1) return -1;
	DispatchKeyValue(entity, "spawnflags", "13");
	DispatchKeyValue(entity, "targetname", ENT_ENV_NAME);
	DispatchKeyValueFloat(entity, "firesize", size);
	DispatchKeyValueFloat(entity, "fireattack", attack);
	DispatchKeyValueFloat(entity, "damagescale", damage);
	TeleportEntity(entity, pos, NULL_VECTOR, NULL_VECTOR);
	DispatchSpawn(entity);
	AcceptEntityInput(entity, "Enable");
	AcceptEntityInput(entity, "StartFire");
	#if defined DEBUG_LOG_MAPSTART

		PrintToServer("spawn env_fire at %.1f %.1f %.1f", pos[0], pos[1], pos[2]);
	#endif
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
	DispatchKeyValue(entity, "targetname", ENT_ENV_NAME);
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


int GetHammerId(int entity) {
	return HasEntProp(entity, Prop_Data, "m_iHammerID") ? GetEntProp(entity, Prop_Data, "m_iHammerID") : -1;
}