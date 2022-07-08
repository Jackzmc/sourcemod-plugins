
Action Timer_RecordPoints(Handle h, int i) {
	if(GetEntityFlags(i) & FL_ONGROUND && IsPlayerAlive(i)) {
		LocationMeta meta;
		GetClientAbsOrigin(i, meta.pos);
		GetClientEyeAngles(i, meta.ang);
		if(meta.pos[0] != vecLastLocation[i][0] || meta.pos[1] != vecLastLocation[i][1] || meta.pos[2] != vecLastLocation[i][2]) {
			if(movePoints.AddPoint(meta)) {
				recordTimer = null;
				return Plugin_Stop;
			}
			Effect_DrawBeamBoxRotatableToClient(i, meta.pos, DEBUG_POINT_VIEW_MIN, DEBUG_POINT_VIEW_MAX, NULL_VECTOR, g_iLaserIndex, 0, 0, 0, 150.0, 0.1, 0.1, 0, 0.0, {0, 0, 255, 64}, 0);
			vecLastLocation[i] = meta.pos;
		}
	}
	PrintHintText(i, "Points: %d / %d", movePoints.Length, MAX_VALID_LOCATIONS);
	return Plugin_Continue;
}

bool firstCheckDone = false;
Action Timer_WaitForPlayers(Handle h) {
	if(!isEnabled) return Plugin_Stop;
	if(!ArePlayersJoining()) {
		Game.Debug("No players pending, ready to go");
		if(!firstCheckDone) {
			// Wait one more iteration
			firstCheckDone = true;
		} else {
			firstCheckDone = false;
			InitGamemode();
			return Plugin_Stop;
		}
	}
	Game.Debug("Waiting for players");
	return Plugin_Continue;
}


Action Timer_CheckHiders(Handle h) {
	static float pos[3];
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i)) {
			GetClientAbsOrigin(i, pos);
			distQueue[i].AddPos(pos);
			distQueue[i].Check(i);
		}
	}

	return Plugin_Continue;
}

Action Timer_ResetAll(Handle h) {
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2) {
			ForcePlayerSuicide(i);
		}
	}
	return Plugin_Handled;
}