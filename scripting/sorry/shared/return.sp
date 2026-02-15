Action Timer_RevertTimeout(Handle h, DataPack pack) {
	pack.Reset();
	int client = GetClientOfUserId(pack.ReadCell());
	if(client > 0) {
		float pos[3];
		pack.ReadFloatArray(pos, 3);
		TeleportEntity(client, pos, NULL_VECTOR, NULL_VECTOR);
		PrintToChat(client, "jk");
	}
	return Plugin_Handled;
}

/**
 * Returns a player to their current position after N seconds
 */
void ReturnPlayerTimeout(float timeout, int client) {
    float orgPos[3];
    GetClientAbsOrigin(client, orgPos);
    DelayedTeleportTo(timeout, client, orgPos);
}

/**
 * Teleports player to given position after N seconds
 */
void DelayedTeleportTo(float timeout, int client, const float pos[3]) {
    DataPack pack;
    CreateDataTimer(timeout, Timer_RevertTimeout, pack);
    pack.WriteCell(GetClientUserId(client));
    pack.WriteFloatArray(pos, 3);
}