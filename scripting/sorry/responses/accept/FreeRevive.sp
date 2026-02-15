bool g_freeRevive[MAXPLAYERS+1];

Action Timer_FreeRevive(Handle h, DataPack pack) {
	pack.Reset();
	int victim = GetClientOfUserId(pack.ReadCell());
	if(victim > 0) {
		L4D_SetPlayerIncapacitatedState(victim, false);
		int reviveCount = pack.ReadCell();
		int health = pack.ReadCell();
		int temp = pack.ReadCell();
		SetEntityHealth(victim, health);
		L4D_SetPlayerTempHealth(victim, temp);
		L4D_SetPlayerReviveCount(victim, reviveCount);
		PrintToChat(victim, "Free revive!");
	}
	return Plugin_Handled;
}

void Event_PlayerIncap(Event event, const char[] name, bool dontBroadcast) {
	int userid = event.GetInt("userid");
	int victim = GetClientOfUserId(userid);
	if(victim && g_freeRevive[victim]) {
		int health = GetClientHealth(victim);
		int temp = L4D_GetPlayerTempHealth(victim);
		DataPack pack;
		CreateDataTimer(1.0, Timer_FreeRevive, pack);
		pack.WriteCell(userid);
		pack.WriteCell(L4D_GetPlayerReviveCount(victim));
		pack.WriteCell(health);
		pack.WriteCell(temp);
	}
}