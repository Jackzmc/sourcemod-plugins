enum struct GascanSpawnerData {
	float origin[3];
	float angles[3];
}

public void L4D2_CGasCan_EventKilled_Post(int gascan, int inflictor, int attacker) {
	GascanSpawnerData spawner;
	// If Gascan was destroyed, and was from a spawner
	if(g_gascanSpawners.GetArray(gascan, spawner, sizeof(spawner))) {
		g_gascanSpawners.Remove(gascan);
		// Push to queue, so when it respawns it can respawn in same place:
		if(g_gascanRespawnQueue == null) {
			g_gascanRespawnQueue = new ArrayList(sizeof(GascanSpawnerData));
		}
		g_gascanRespawnQueue.PushArray(spawner, sizeof(spawner));
		Debug("gascan %d destroyed. queue size=%d", gascan, g_gascanRespawnQueue.Length);
	}
}

/// Assign gascan to a spawner
void AssignGascan(int gascan, GascanSpawnerData spawner) {
	g_gascanSpawners.SetArray(gascan, spawner, sizeof(spawner));
	TeleportEntity(gascan, spawner.origin, spawner.angles, NULL_VECTOR);
	Debug("Assigning gascan %d to spawner at %.0f %.0f %.0f", gascan, spawner.origin[0], spawner.origin[1], spawner.origin[2]);
}


void AddGascanSpawner(VariantEntityData data) {
	if(g_MapData.gascanSpawners == null) {
		g_MapData.gascanSpawners = new ArrayList(sizeof(GascanSpawnerData));
	}
	GascanSpawnerData spawner;
	spawner.origin = data.origin;
	spawner.angles = data.angles;
	
	g_MapData.gascanSpawners.PushArray(spawner);
	// Debug("Added gascan spawner at %.0f %.0f %.0f", spawner.origin[0], spawner.origin[1], spawner.origin[2]);
}

void Frame_RandomizeGascan(int gascan) {
	if(!IsValidEntity(gascan)) return;
	if(g_gascanRespawnQueue == null || g_gascanRespawnQueue.Length == 0) return;

	// Grab spawner data (incl. position) from respawn queue & assign
	GascanSpawnerData spawner;
	g_gascanRespawnQueue.GetArray(0, spawner);
	g_gascanRespawnQueue.Erase(0);

	AssignGascan(gascan, spawner);
}