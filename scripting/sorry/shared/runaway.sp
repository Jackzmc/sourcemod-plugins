Action Timer_ZombieRunAwayItem(Handle h, DataPack pack) {
	pack.Reset();
	int activator = pack.ReadCell();
	int wpn = pack.ReadCell();
	SpawnZombieRunAway(activator, wpn);
	return Plugin_Handled;
}

/**
 * Spawns a random special that runs away with entity for given survivor
 */
void SpawnZombieRunAway(int survivor, int entityToRunWith) {
	float pos[3];
	int zombie = GetRandomZombie(survivor, pos);
	if(zombie <= 0) {
		PrintToServer("[Custom] SpawnZombieRunAway: failed to get zombie");
		PrintHintText(survivor, "You got lucky...");
		return;
	}
	SetEntPropFloat(zombie, Prop_Send, "m_flLaggedMovementValue", 0.5);
	PrintToChat(survivor, "%N has your melee/secondary weapon... better chase them", zombie);
	GlowEntity(zombie, 0.0, { 255, 255, 255 }, false);
	int entityRef = EntIndexToEntRef(entityToRunWith);
	g_runAwayParents.SetValue(zombie, entityRef);

	DataPack pack;
	CreateDataTimer(0.1, Timer_RunAwayPostSpawn, pack);
	pack.WriteCell(EntIndexToEntRef(zombie));
	pack.WriteCell(entityRef);
	pack.WriteFloatArray(pos, 3);
}

Action Timer_RunAwayChangeDest(Handle h, int zombieRef) {
	int zombie = EntRefToEntIndex(zombieRef);
	if(IsValidEntity(zombie) && g_runAwayParents.ContainsKey(zombie)) {
		float pos[3];
		L4D_GetRandomPZSpawnPosition(0, 1, 3, pos);
		L4D2_CommandABot(zombie, 0, BOT_CMD_MOVE, pos);
		return Plugin_Continue;
	}
	return Plugin_Handled;

}

Action Timer_RunAwayPostSpawn(Handle h, DataPack pack) {
	pack.Reset();
	int zombieRef = pack.ReadCell();
	int entityToRunWithRef = pack.ReadCell();

	// Attach as hat
	float pos[3];
	pack.ReadFloatArray(pos, 3);
	TeleportEntity(zombieRef, pos, NULL_VECTOR, NULL_VECTOR);
	pos[2] += 70.0;
	TeleportEntity(entityToRunWithRef, pos, NULL_VECTOR, NULL_VECTOR);
	SetParent(entityToRunWithRef, zombieRef);

	// Make zombie run away
	L4D_GetRandomPZSpawnPosition(0, 1, 3, pos);
	L4D2_CommandABot(zombieRef, 0, BOT_CMD_MOVE, pos);
	CreateTimer(6.0, Timer_RunAwayChangeDest, zombieRef, TIMER_REPEAT);
	return Plugin_Handled;
}

void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) {
	int victim = GetClientOfUserId(event.GetInt("userid"));
	if(victim > 0) {
		ClearRunAwayProp(victim);
	}
}

public void OnEntityDestroyed(int entity) {
	ClearRunAwayProp(entity);
}

void ClearRunAwayProp(int entity) {
	int propRef;
	if(g_runAwayParents.GetValue(entity, propRef)) {
		float pos[3];
		GetEntPropVector(entity, Prop_Send, "m_vecOrigin", pos);
		int prop = EntRefToEntIndex(propRef);
		ClearParent(prop);
		pos[2] += 50.0;
		GlowEntity(prop, 5.0, { 255, 0, 0}, true);
		TeleportEntity(propRef, pos, NULL_VECTOR, NULL_VECTOR);
		L4D2_RemoveEntityGlow(entity);
		g_runAwayParents.Remove(entity);
	}
}
