public int Insta_PlayerHandler(Menu menu, MenuAction action, int client, int param2) {
	/* If an option was selected, tell the client about the item. */
	if (action == MenuAction_Select) {
		static char info[16];
		menu.GetItem(param2, info, sizeof(info));

		static char str[2][8];
		ExplodeString(info, "|", str, 2, 8, false);

		int userid = StringToInt(str[0]);
		int instaMode = StringToInt(str[1]);

		Menu spMenu = new Menu(Insta_SpecialHandler);
		spMenu.SetTitle("Choose a Insta-Special™");
		for(int i = 1; i <= 6; i++) {
			static char id[8];
			Format(id, sizeof(id), "%d|%d|%d", userid, instaMode, i);
			spMenu.AddItem(id, SPECIAL_NAMES[i-1]);
		}
		spMenu.ExitButton = true;
		spMenu.Display(client, 0);
	} else if (action == MenuAction_End)
		delete menu;
}

public int Insta_SpecialHandler(Menu menu, MenuAction action, int client, int param2) {
	/* If an option was selected, tell the client about the item. */
	if (action == MenuAction_Select) {
		static char info[16];
		menu.GetItem(param2, info, sizeof(info));
		static char str[3][8];
		ExplodeString(info, "|", str, 3, 8, false);
		int target = GetClientOfUserId(StringToInt(str[0]));
		bool inFace = StrEqual(str[1], "1");
		int special = StringToInt(str[2]);
		if(inFace) {
			SpawnSpecialInFace(target, special);
			ShowActivity(client, "spawned Insta-%s™ near %N", SPECIAL_NAMES[special-1], target);
		} else {
			SpawnSpecialNear(target, special);
			ShowActivity(client, "spawned Insta-%s™ near %N", SPECIAL_NAMES[special-1], target);
		}
	} else if (action == MenuAction_End)
		delete menu;
}


public int ChooseMarkedTroll(Menu menu, MenuAction action, int activator, int param2) {
	if (action == MenuAction_Select) {
		static char info[16];
		menu.GetItem(param2, info, sizeof(info));
		int target = GetClientOfUserId(StringToInt(info));
		ToggleMarkPlayer(activator, target);
	} else if (action == MenuAction_End)
		delete menu;
}

public int ChoosePlayerHandler(Menu menu, MenuAction action, int param1, int param2) {
	/* If an option was selected, tell the client about the item. */
	if (action == MenuAction_Select) {
		static char info[16];
		menu.GetItem(param2, info, sizeof(info));
		int userid = StringToInt(info);
		
		Menu trollMenu = new Menu(ChooseModeMenuHandler);
		trollMenu.SetTitle("Choose a troll mode");
		//TODO: Update
		static char id[8];
		static char name[MAX_TROLL_NAME_LENGTH];
		for(int i = 0; i <= MAX_TROLLS; i++) {
			GetTrollID(i, name);
			// int trollIndex = GetTrollByKeyIndex(i, troll);
			// Pass key index
			Format(id, sizeof(id), "%d|%d", userid, i);
			trollMenu.AddItem(id, name);
		}
		trollMenu.ExitButton = true;
		trollMenu.Display(param1, 0);
	} else if (action == MenuAction_End)
		delete menu;
}

public int ChooseModeMenuHandler(Menu menu, MenuAction action, int param1, int param2) {
	/* If an option was selected, tell the client about the item. */
	if (action == MenuAction_Select) {
		static char info[16];
		menu.GetItem(param2, info, sizeof(info));
		static char str[2][8];
		ExplodeString(info, "|", str, 2, 8, false);
		int userid = StringToInt(str[0]);
		int client = GetClientOfUserId(userid);
		int keyIndex = StringToInt(str[1]);
		static Troll troll;
		static char trollID[MAX_TROLL_NAME_LENGTH];
		GetTrollByKeyIndex(keyIndex, troll);
		troll.GetID(trollID, MAX_TROLL_NAME_LENGTH);
		//If troll has multiple flags, prompt:
		if(troll.HasMod(TrollMod_Instant) && troll.HasMod(TrollMod_Constant)) {
			Menu modiferMenu = new Menu(ChooseTrollModiferHandler); 
			modiferMenu.SetTitle("Choose Troll Modifer Option");
			static char singleUse[16], multiUse[16], bothUse[16];
			Format(singleUse, sizeof(singleUse), "%d|%d|1", userid, keyIndex);
			Format(multiUse,   sizeof(multiUse), "%d|%d|2", userid, keyIndex);
			Format(bothUse,     sizeof(bothUse), "%d|%d|3", userid, keyIndex);
			modiferMenu.AddItem(singleUse, "Activate once");
			modiferMenu.AddItem(multiUse, "Activate Periodically");
			modiferMenu.AddItem(bothUse, "Activate Periodically & Instantly");
			modiferMenu.ExitButton = true;
			modiferMenu.Display(param1, 0);
		} else {
			ApplyTroll(client, trollID, param1, troll.GetDefaultMod());
		}
	} else if (action == MenuAction_End)
		delete menu;
}

public int ChooseTrollModiferHandler(Menu menu, MenuAction action, int param1, int param2) {
	if (action == MenuAction_Select) {
		static char info[16];
		menu.GetItem(param2, info, sizeof(info));
		static char str[3][8];
		ExplodeString(info, "|", str, 3, 8, false);
		int client = GetClientOfUserId(StringToInt(str[0]));
		int keyIndex = StringToInt(str[1]);
		static Troll troll;
		static char trollID[MAX_TROLL_NAME_LENGTH];
		GetTrollByKeyIndex(keyIndex, troll);
		troll.GetID(trollID, MAX_TROLL_NAME_LENGTH);
		int flags = StringToInt(str[2]);
		if(flags == 1 || flags == 3)
			ApplyTroll(client, trollID, param1, TrollMod_Instant);
		if(flags == 2 || flags == 3)
			ApplyTroll(client, trollID, param1, TrollMod_Constant);
	} else if (action == MenuAction_End)	
		delete menu;
}

public void StopItemGive(int client) {
	g_bPendingItemGive[client] = false;
}