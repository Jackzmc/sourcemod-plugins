static char STORE_RAINBOW_HUE[] = "BecomeRandomPeanut.hue";
static char STORE_RAINBOW_DIR[] = "BecomeRandomPeanut.increment";
static char STORE_RAINBOW_TIMER[] = "BecomeRandomPeanut.timer";

// apologizer: is apologizing to target
// target: the one that picked this response outcome for the apologizer
// eventId: id of event or blank string
// Use SorryStore[apologizer] to record data
void BecomeRandomPeanut_OnActivate(int apologizer, int target, const char[] eventId) {
	int type = GetRandomInt(0, 4);
	float time = GetRandomFloat(10.0, 60.0);
	PrecacheModel(MODEL_PEANUT);
	TempSetModel(apologizer, time, MODEL_PEANUT);
	PrintToConsoleAll("reject peanut time=%f type=%d", time, type);
	if(type == 0) {
		float hsv[3];
		hsv[0] = GetRandomFloat(0.0, 360.0);
		hsv[1] = 100.0; // 100%
		hsv[2] = 100.0; 
		
		int rgb[3];
		HSVToRGBInt(hsv, rgb);

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
		float startingHue = GetRandomFloat(0.0, 360.0);
		SorryStore[apologizer].SetValue(STORE_RAINBOW_HUE, startingHue);
		SorryStore[apologizer].SetValue(STORE_RAINBOW_DIR, GetRandomFloat() > 0.5 ? 1.0 : -1.0);

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
		float hsv[3];
		SorryStore[client].GetValue(STORE_RAINBOW_HUE, hsv[0]); // hue
		hsv[1] = 100.0; // 100% sat
		hsv[2] = 50.0; 	//50% val

		float increment;
		SorryStore[client].GetValue(STORE_RAINBOW_DIR, increment);

		hsv[0] += increment;
		// Reverse the order when hit bounds
		if(hsv[0] >= 360.0 || hsv[0] <= 0.0) {
			increment *= -1;
			SorryStore[client].SetValue(STORE_RAINBOW_DIR, increment);
		}
		SorryStore[client].SetValue(STORE_RAINBOW_HUE, hsv[0]);

		int rgb[3];
		HSVToRGBInt(hsv, rgb);
		SetEntityRenderColor(client, rgb[0], rgb[1], rgb[2], 255);

	}
	return Plugin_Handled;
}

Action Timer_StopRainbow(Handle h, int userid) {
	int client = GetClientOfUserId(userid);
	if(client > 0) {
		Handle timer;
		if(SorryStore[client].GetValue(STORE_RAINBOW_TIMER, timer)) {
			KillTimer(timer);
		}

		SorryStore[client].Remove(STORE_RAINBOW_HUE);
		SorryStore[client].Remove(STORE_RAINBOW_DIR);
		SorryStore[client].Remove(STORE_RAINBOW_TIMER);
	}
	return Plugin_Handled;
}
