static char STORE_RAINBOW_INDEX[] = "BecomeRandomPeanut.index";
static char STORE_RAINBOW_TIMER[] = "BecomeRandomPeanut.handle";

// apologizer: is apologizing to target
// target: the one that picked this response outcome for the apologizer
// eventId: id of event or blank string
// Use SorryStore[apologizer] to record data
void BecomeRandomPeanut_OnActivate(int apologizer, int target, const char[] eventId) {
	int type = GetRandomInt(0, 3);
	float time = GetRandomFloat(10.0, 60.0);
	PrecacheModel(MODEL_PEANUT);
	TempSetModel(apologizer, time, MODEL_PEANUT);
	PrintToConsoleAll("reject peanut time=%f type=%d", time, type);
	if(type == 0) {
		float hsv[3];
		hsv[0] = GetRandomFloat(0.0, 360.0);
		hsv[1] = 100.0; // 100%
		hsv[2] = 50.0; 	// 50%

		int rgb[3];
		FloatArrayToIntArray(hsv, rgb, 3);

		TempSetColor(apologizer, time, rgb, true);
		PrintToChat(apologizer, "Random colored peanut! ");
	} else if(type == 1) {
		int color[4];
		color[3] = GetRandomInt(10, 128);
		TempSetColorAlpha(apologizer, time, color, true);
		PrintToChat(apologizer, "Ghostly peanut! ");
	} else if(type == 2) {
		TempSetSpeed(apologizer, time, 0.4);
		PrintToChat(apologizer, "Sloooow peanut! ");
	} else if(type == 3) {
		TempSetGravity(apologizer, time, 0.2);
		PrintToChat(apologizer, "Low gravity peanut! ");
	} else if(type == 4) {
		// TODO: fix
		// pick random start point to make it look bit more random
		int rainbowIndex = GetRandomInt(0, RAINBOW_INDEX_MAX);
		SorryStore[apologizer].SetValue(STORE_RAINBOW_INDEX, rainbowIndex);

		int userid = GetClientUserId(apologizer);
		Handle timer = CreateTimer(0.1, Timer_RainbowCycle, userid, TIMER_REPEAT);
		SorryStore[apologizer].SetValue(STORE_RAINBOW_TIMER, timer);

		CreateTimer(time, Timer_StopRainbow, userid);
		PrintToChat(apologizer, "rainbow peanut! ");
	}
}

Action Timer_RainbowCycle(Handle h, int userid) {
	int client = GetClientOfUserId(userid);
	if(client > 0) {
		int rainbowIndex;
		SorryStore[client].GetValue(STORE_RAINBOW_INDEX, rainbowIndex);
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
			rainbowIndex += 1;
			if(rainbowIndex >= RAINBOW_INDEX_MAX) {
				rainbowIndex = 0;
			}
			SorryStore[client].SetValue(STORE_RAINBOW_INDEX, rainbowIndex);
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
