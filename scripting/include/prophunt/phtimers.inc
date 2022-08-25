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


Action Timer_StartGame(Handle h) {
	Game.State = State_Active;
	Game.MapTime = DEFAULT_GAME_TIME;
	Game.Tick = 0;
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i)) {
			if(Game.IsSeeker(i)) {
				Game.SetupSeeker(i);
			}
			SetPlayerBlind(i, 0);
			SetEntPropFloat(i, Prop_Send, "m_flLaggedMovementValue", 1.0);
		}
	}
	Game.Broadcast("Get ready here they come");
	return Plugin_Continue;
}

Action Timer_TimesUp(Handle h) {
	Game.End(State_PropsWin);
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