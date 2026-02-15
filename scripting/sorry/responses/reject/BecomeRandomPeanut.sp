Action Timer_RainbowCycle(Handle h, int userid) {
	int client = GetClientOfUserId(userid);
	if(client > 0) {
		int rainbowIndex = rainbowData[client].index;
		int color[4];
		GetEntityRenderColor(client, color[0], color[1], color[2], color[3]);
		if(color[0] != RAINBOW_TABLE[rainbowIndex][0] 
			&& color[1] != RAINBOW_TABLE[rainbowIndex][1] 
			&& color[2] != RAINBOW_TABLE[rainbowIndex][2]
		) {
			for(int i = 0; i < 3; i++) {
				if(color[i] < RAINBOW_TABLE[rainbowIndex][i]) color[i]++;
				if(color[i] > RAINBOW_TABLE[rainbowIndex][i]) color[i]--;
			}
			SetEntityRenderColor(client, color[0], color[1], color[2], color[3]);
		} else {
			// Advance to next index, cycling back to 0
			rainbowData[client].index += 1;
			if(rainbowData[client].index >= RAINBOW_INDEX_MAX) {
				rainbowData[client].index = 0;
			}
		}
	}
	return Plugin_Handled;
}

Action Timer_StopRainbow(Handle h, int userid) {
	int client = GetClientOfUserId(userid);
	if(client > 0) {
		if(rainbowData[client].timer != null) {
			delete rainbowData[client].timer;
		}
	}
	return Plugin_Handled;
}
