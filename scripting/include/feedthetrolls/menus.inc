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
			Format(info, sizeof(info), "%d|%d|%d", userid, instaMode, i);
			spMenu.AddItem(info, SPECIAL_NAMES[i-1]);
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
		static char info[8];
		menu.GetItem(param2, info, sizeof(info));
		int userid = StringToInt(info);
		
		SetupCategoryMenu(param1, userid);
	} else if (action == MenuAction_End)
		delete menu;
}

public int ChooseCategoryHandler(Menu menu, MenuAction action, int param1, int param2) {
	if (action == MenuAction_Select) {
		static char info[32];
		menu.GetItem(param2, info, sizeof(info));
		static char str[2][8];
		ExplodeString(info, "|", str, 2, 8, false);
		int userid = StringToInt(str[0]);
		int category = StringToInt(str[1]);
		
		Menu trollMenu = new Menu(ChooseModeMenuHandler);
		GetCategory(category, info, sizeof(info));
		Format(info, sizeof(info), "Category: %s", info);
		trollMenu.SetTitle(info);
		//TODO: Update
		static Troll troll;

		// add 'return' btn
		Format(info, sizeof(info), "%d|-1", userid);
		trollMenu.AddItem(info, "<= Go Back");

		// Add all menus that have same category
		for(int i = 0; i < trollKV.Size; i++) {
			GetTrollByKeyIndex(i, troll);
			if(troll.categoryID == category) {
				Format(info, sizeof(info), "%d|%d", userid, i);
				trollMenu.AddItem(info, troll.name);
			}
		}
		trollMenu.ExitButton = true;
		trollMenu.Display(param1, 0);
	} else if (action == MenuAction_End)
		delete menu;
}

public int ChooseModeMenuHandler(Menu menu, MenuAction action, int param1, int param2) {
	if (action == MenuAction_Select) {
		static char info[16];
		menu.GetItem(param2, info, sizeof(info));
		static char str[2][8];
		ExplodeString(info, "|", str, 2, 8, false);
		int userid = StringToInt(str[0]);
		int client = GetClientOfUserId(userid);
		int keyIndex = StringToInt(str[1]);
		if(keyIndex == -1) {
			SetupCategoryMenu(param1, userid);
			return;
		}
		static Troll troll;
		static char trollID[MAX_TROLL_NAME_LENGTH];
		GetTrollByKeyIndex(keyIndex, troll);
		troll.GetID(trollID);
		//If troll has multiple flags, prompt:
		if(StrEqual(trollID, "ThrowItAll")) {
			// Setup menu to call itself, but with an extra data point
			Menu itmMenu = new Menu(ChooseClumsySlotHandler); 
			itmMenu.SetTitle("Choose Item To Throw");

			static char itmName[32];
			Format(info, sizeof(info), "%d|-1", userid);
			itmMenu.AddItem(info, "All Items");
			for(int slot = 0; slot <= 4; slot++) {
				int item = GetPlayerWeaponSlot(client, slot);
				if(item > -1) {
					GetEdictClassname(item, itmName, sizeof(itmName));
					Format(info, sizeof(info), "%d|%d", userid,  slot);
					itmMenu.AddItem(info, itmName[7]);
				}
			}
			itmMenu.ExitButton = true;
			itmMenu.Display(param1, 0);
		} else if(troll.HasMod(TrollMod_Instant) && troll.HasMod(TrollMod_Constant)) {
			Menu modiferMenu = new Menu(ChooseTrollModiferHandler); 
			modiferMenu.SetTitle("Choose Troll Modifer Option");

			Format(info, sizeof(info), "%d|%d|1", userid, keyIndex);
			modiferMenu.AddItem(info, "Activate once");
			Format(info, sizeof(info), "%d|%d|2", userid, keyIndex);
			modiferMenu.AddItem(info, "Activate Periodically");
			Format(info, sizeof(info), "%d|%d|3", userid, keyIndex);
			modiferMenu.AddItem(info, "Activate Periodically & Instantly");

			modiferMenu.ExitButton = true;
			modiferMenu.Display(param1, 0);
		} else {
			ApplyTroll(client, trollID, param1, troll.GetDefaultMod());
		}
	} else if (action == MenuAction_End)
		delete menu;
}

public int ChooseClumsySlotHandler(Menu menu, MenuAction action, int param1, int param2) {
	if (action == MenuAction_Select) {
		static char info[8];
		menu.GetItem(param2, info, sizeof(info));
		static char str[2][8];
		ExplodeString(info, "|", str, 2, 8, false);
		int client = GetClientOfUserId(StringToInt(str[0]));
		int slot = StringToInt(str[1]);
		PrintToChatAll("%d", slot);
		if(slot == -1) {
			for(int i = 0; i <= 4; i++) {
				ThrowItemToClosestPlayer(client, i);
			}
		} else {
			ThrowItemToClosestPlayer(client, slot);
		}
		ShowActivity(param1, "activated troll \"Throw It All\" for %N. ", client);
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
		int flags = StringToInt(str[2]);

		static Troll troll;
		GetTrollByKeyIndex(keyIndex, troll);

		if(flags == 1 || flags == 3)
			troll.Activate(client, param1, TrollMod_Instant);
			// ApplyTroll(client, trollID, param1, TrollMod_Instant);
		if(flags == 2 || flags == 3)
			troll.Activate(client, param1, TrollMod_Constant);
			// ApplyTroll(client, trollID, param1, TrollMod_Constant);
	} else if (action == MenuAction_End)	
		delete menu;
}

public void StopItemGive(int client) {
	g_bPendingItemGive[client] = false;
}

void SetupCategoryMenu(int client, int victimUserID) {
	Menu categoryMenu = new Menu(ChooseCategoryHandler);
	categoryMenu.SetTitle("Choose a troll category");
	static char category[16], id[8];
	for(int i = 0; i < categories.Length; i++) {
		categories.GetString(i, category, sizeof(category));
		Format(id, sizeof(id), "%d|%d", victimUserID, i);
		categoryMenu.AddItem(id, category);
	}
	categoryMenu.ExitButton = true;
	categoryMenu.Display(client, 0);
}