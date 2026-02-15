Action Timer_CarAlarmFlash(Handle h, int userid) {
	int client = GetClientOfUserId(userid);
	if(client > 0) {
		int r, g, b, a;
		GetEntityRenderColor(client, r, g, b, a);
		if(b == 0) {
			SetEntityRenderColor(client, 255, 255, 255);
			L4D2_SetEntityGlow(client, L4D2Glow_Constant, 0, 0, { 255, 255, 255 }, true);
		} else {
			SetEntityRenderColor(client, 255, 255, 0);
			L4D2_SetEntityGlow(client, L4D2Glow_Constant, 0, 0, { 255, 255, 0 }, true);

		}

	}
	return Plugin_Continue;
}

Action Timer_StopAlarm(Handle h, DataPack pack) {
	pack.Reset();
	int client = GetClientOfUserId(pack.ReadCell());
	if(client > 0) {
		StopSound(client, SNDCHAN_USER_BASE, SOUND_CAR_ALARM);
		SetEntityRenderColor(client, 255, 255, 255);
		SetEntityRenderMode(client, RENDER_NORMAL);
		L4D2_RemoveEntityGlow(client);
	}
	Handle timer = pack.ReadCell();
	if(timer != null)
		delete timer;
	return Plugin_Handled;
}
