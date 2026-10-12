void KillPlayerAndRevert(int activator, float delay) {
	float vel[3] = { 10000.0, 10000.0, 1000.0 };
	DataPack pack1;
	CreateDataTimer(delay, Timer_RevertKill, pack1);
	pack1.WriteCell(GetClientUserId(activator));
	float pos[3];
	GetClientAbsOrigin(activator, pos);
	pack1.WriteFloatArray(pos, 3);
	float nullPos[3];

	int ent;
	for(int slot = 0; slot <= 5; slot++) {
		ent = GetPlayerWeaponSlot(activator, slot);
		if(ent > 0) {
			DropWeapon(activator, ent, nullPos);
			TeleportEntity(ent, nullPos, NULL_VECTOR, NULL_VECTOR);
			pack1.WriteCell(EntIndexToEntRef(ent));
		} else {
			pack1.WriteCell(0);
		}
	}

	// Record perm + temp health
	pack1.WriteCell(GetEntProp(activator, Prop_Send, "m_iHealth"));
	pack1.WriteCell(L4D_GetPlayerTempHealth(activator));

	// Ensure they die
	SDKHooks_TakeDamage(activator, activator, activator, 1000.0, DMG_BLAST, -1, vel);
	SDKHooks_TakeDamage(activator, activator, activator, 1000.0, DMG_BLAST, -1, vel);
}



Action Timer_RevertKill(Handle h, DataPack pack1) {
	pack1.Reset();
	int userid = pack1.ReadCell();
	int client = GetClientOfUserId(userid);
	if(client == 0) return Plugin_Handled;
	float pos[3];
	pack1.ReadFloatArray(pos, 3);

	PrintToServer("debug fakekill: respawning player (stage 1) for %N", client);

	if(client > 0) {
		L4D_RespawnPlayer(client);
		DataPack pack2;
		CreateDataTimer(1.0, Timer_RevertKillItems, pack2);
		pack2.WriteCell(userid);
		TeleportEntity(client, pos, NULL_VECTOR, NULL_VECTOR);
		pack2.WriteFloatArray(pos, 3);
		for(int slot = 0; slot <= 5; slot++) {
			int ref = pack1.ReadCell();
			pack2.WriteCell(ref);
		}
		// Health:
		pack2.WriteCell(pack1.ReadCell());
		pack2.WriteCell(pack1.ReadCell());

	}
	return Plugin_Handled;
}
Action Timer_RevertKillItems(Handle h, DataPack pack2) {
	pack2.Reset();
	int client = GetClientOfUserId(pack2.ReadCell());
	if(client == 0) return Plugin_Handled;
	float pos[3];
	pack2.ReadFloatArray(pos, 3);
	TeleportEntity(client, pos, NULL_VECTOR, NULL_VECTOR);

	PrintToServer("debug fakekill: restoring items (stage 2) for %N", client);

	int ent, ref;
	for(int slot = 0; slot <= 5; slot++) {
		ref = pack2.ReadCell();
		if(ref == 0) continue; 
		ent = EntRefToEntIndex(ref);
		if(ent > 0) {
			EquipWeapon(client, ent);
		}
	}

	SetEntProp(client, Prop_Send, "m_iHealth", pack2.ReadCell());
	L4D_SetPlayerTempHealth(client, pack2.ReadCell());
	return Plugin_Handled;
}
