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
		for(int i = 1; i <= 8; i++) {
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
			if(SpawnSpecialInFace(target, special)) {
				LogAction(client, target, "\"%L\" spawned Insta-%s™ on \"%L\"", client, SPECIAL_NAMES[special-1], target);
				ShowActivityEx(client, "[FTT] ", "spawned Insta-%s™ on %N", SPECIAL_NAMES[special-1], target);
			} else {
				ReplyToCommand(client, "Could not spawn special.");
			}
		} else {
			if(SpawnSpecialNear(target, special)) {
				LogAction(client, target, "\"%L\" spawned Insta-%s™ near \"%L\"", client, SPECIAL_NAMES[special-1], target);
				ShowActivityEx(client, "[FTT] ", "spawned Insta-%s™ near %N", SPECIAL_NAMES[special-1], target);
			} else {
				ReplyToCommand(client, "Could not spawn special.");
			}
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
		int client = GetClientOfUserId(userid);

		if(client == 0) {
			ReplyToCommand(param1, "FTT: Could not acquire player");
			return;
		}
		
		SetupCategoryMenu(param1, userid);
	} else if (action == MenuAction_End)
		delete menu;
}

static int iMenuVictimID[MAXPLAYERS+1];
public int ChooseCategoryHandler(Menu menu, MenuAction action, int param1, int param2) {
	if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
		ShowTrollMenu(param1);
	else if (action == MenuAction_Select) {
		static char info[32];
		menu.GetItem(param2, info, sizeof(info));
		static char str[2][8];
		ExplodeString(info, "|", str, 2, 8, false);
		int userid = StringToInt(str[0]);
		int client = GetClientOfUserId(userid);
		if(client == 0) {
			ReplyToCommand(param1, "FTT: Could not acquire player");
			return;
		}
		
		iMenuVictimID[param1] = userid;
		int category = StringToInt(str[1]);

		// Reset troll:
		if(category == -1) {
			ApplyTroll(GetClientOfUserId(userid), "Reset User", param1, TrollMod_Instant);
			return;
		}
		
		ShowTrollsForCategory(param1, userid, category);
	} else if (action == MenuAction_End)
		delete menu;
}

public int ChooseModeMenuHandler(Menu menu, MenuAction action, int param1, int param2) {
	if (action == MenuAction_Cancel) {
		if(param2 == MenuCancel_ExitBack) {
			if(iMenuVictimID[param1] == 0) {
				ReplyToCommand(param1, "FTT: Could not acquire player");
			}
			SetupCategoryMenu(param1, iMenuVictimID[param1]);
		}
	} else if (action == MenuAction_Select) {
		static char info[32];
		menu.GetItem(param2, info, sizeof(info));
		static char str[2][8];
		ExplodeString(info, "|", str, 2, 8, false);
		int userid = StringToInt(str[0]);
		int client = GetClientOfUserId(userid);
		if(client == 0) {
			ReplyToCommand(param1, "FTT: Could not acquire player");
			return;
		}

		int keyIndex = StringToInt(str[1]);
		static Troll troll;
		GetTrollByKeyIndex(keyIndex, troll);
		//If troll has multiple flags, prompt:
		if(StrEqual(troll.name, "Throw It All")) {
			// Setup menu to call itself, but with an extra data point
			ShowThrowItAllMenu(param1, userid);
		} else if(troll.HasMod(TrollMod_Instant) && troll.HasMod(TrollMod_Constant)) {
			Menu modiferMenu = new Menu(ChooseTrollModiferHandler); 
			Format(info, sizeof(info), "%s: Choose Modifier", troll.name);
			modiferMenu.SetTitle(info);

			Format(info, sizeof(info), "%d|%d|1", userid, keyIndex);
			modiferMenu.AddItem(info, "Activate Once");
			Format(info, sizeof(info), "%d|%d|2", userid, keyIndex);
			modiferMenu.AddItem(info, "Activate Periodically");
			Format(info, sizeof(info), "%d|%d|3", userid, keyIndex);
			modiferMenu.AddItem(info, "Activate Periodically & Instantly");

			modiferMenu.ExitButton = true;
			modiferMenu.Display(param1, 0);
		} else if(troll.HasFlags() && !troll.IsActive(client)) {
 			ShowSelectFlagMenu(param1, userid, 0, troll);
		} else {
			troll.Activate(client, param1);
			ShowTrollsForCategory(param1, userid, troll.categoryID);
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
		int userid = StringToInt(str[0]);
		int client = GetClientOfUserId(userid);
		int slot = StringToInt(str[1]);
		if(client == 0) {
			ReplyToCommand(param1, "FTT: Could not acquire player");
			return;
		}else if(slot == -1) {
			for(int i = 0; i <= 4; i++) {
				ThrowItemToClosestPlayer(client, i);
			}
		} else {
			ThrowItemToClosestPlayer(client, slot);
		}
		LogAction(param1, client, "\"%L\" activated troll \"Throw It all\" for \"%L\"", param1, client);
		ShowActivityEx(param1, "[FTT] ", "activated troll \"Throw It All\" for %N. ", client);

		ShowThrowItAllMenu(param1, userid);
	} else if (action == MenuAction_End)	
		delete menu;
}

public int ChooseTrollModiferHandler(Menu menu, MenuAction action, int param1, int param2) {
	if (action == MenuAction_Select) {
		static char info[16];
		menu.GetItem(param2, info, sizeof(info));
		static char str[3][8];
		ExplodeString(info, "|", str, 3, 8, false);
		int userid = StringToInt(str[0]);
		int client = GetClientOfUserId(userid);
		int keyIndex = StringToInt(str[1]);
		int modifiers = StringToInt(str[2]);

		if(client == 0) {
			ReplyToCommand(param1, "FTT: Could not acquire player");
			return;
		}

		static Troll troll;
		GetTrollByKeyIndex(keyIndex, troll);

		if(troll.HasFlags() && !troll.IsActive(client)) {
 			ShowSelectFlagMenu(param1, userid, modifiers, troll);
		} else {
			if(modifiers == 1 || modifiers == 3)
				troll.Activate(client, param1, TrollMod_Instant);
			if(modifiers == 2 || modifiers == 3)
				troll.Activate(client, param1, TrollMod_Constant);	
			ShowTrollsForCategory(param1, userid, troll.categoryID);
		}
		
	} else if (action == MenuAction_End)	
		delete menu;
}

public int ChooseTrollFlagHandler(Menu menu, MenuAction action, int param1, int param2) {
	if (action == MenuAction_Select) {
		static char info[32];
		menu.GetItem(param2, info, sizeof(info));
		static char str[5][8];
		ExplodeString(info, "|", str, 5, 8, false);
		int userid = StringToInt(str[0]);
		int client = GetClientOfUserId(userid);
		int keyIndex = StringToInt(str[1]);
		int modifiers = StringToInt(str[2]);
		int flags = StringToInt(str[3]);
		bool done = StringToInt(str[4]) == 1;

		if(client == 0) {
			ReplyToCommand(param1, "FTT: Could not acquire player");
			return;
		}

		static Troll troll;
		GetTrollByKeyIndex(keyIndex, troll);

		if(done || !troll.flagsMultiselectable) {
			if(modifiers > 0) {
				if(modifiers == 1 || modifiers == 3)
					troll.Activate(client, param1, TrollMod_Instant, flags);
				if(modifiers == 2 || modifiers == 3)
					troll.Activate(client, param1, TrollMod_Constant, flags);
			} else {
				troll.Activate(client, param1, TrollMod_Invalid, flags);
			}
			ShowTrollsForCategory(param1, userid, troll.categoryID);
		} else {
			ShowSelectFlagMenu(param1, userid, modifiers, troll, flags);
		}

	} else if (action == MenuAction_End)	
		delete menu;
}


public void StopItemGive(int client) {
	g_bPendingItemGive[client] = false;
}

void SetupCategoryMenu(int client, int victimUserID) {
	Menu categoryMenu = new Menu(ChooseCategoryHandler);
	static char category[64], id[8];
	Format(category, sizeof(category), "%N: Choose troll category", GetClientOfUserId(victimUserID));
	categoryMenu.SetTitle(category);

	Format(id, sizeof(id), "%d|-1", victimUserID);
	categoryMenu.AddItem(id, "Reset User");
	for(int i = 0; i < categories.Length; i++) {
		categories.GetString(i, category, sizeof(category));
		Format(id, sizeof(id), "%d|%d", victimUserID, i);
		categoryMenu.AddItem(id, category);
	}
	categoryMenu.ExitButton = true;
	categoryMenu.ExitBackButton = true;
	categoryMenu.Display(client, 0);
}

void ShowTrollMenu(int client) {
	Menu menu = new Menu(ChoosePlayerHandler);
	menu.SetTitle("Choose a player to troll");
	static char userid[8], display[32];
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == 2) {
			IntToString(GetClientUserId(i), userid, sizeof(userid));
			int specClient = GetSpectatorClient(i);
			if(specClient > 0) 
				Format(display, sizeof(display), "%N (Idle)", specClient);
			else
				GetClientName(i, display, sizeof(display));
			menu.AddItem(userid, display);
		}
	}
	menu.ExitButton = true;
	menu.Display(client, 0);
}

void ShowTrollsForCategory(int client, int userid, int category) {
	static char info[32];
	Menu trollMenu = new Menu(ChooseModeMenuHandler);
	GetCategory(category, info, sizeof(info));
	Format(info, sizeof(info), "Category: %s", info);
	trollMenu.SetTitle(info);
	
	static Troll troll;

	int victim = GetClientOfUserId(userid);

	// Add all menus that have same category
	static char name[MAX_TROLL_NAME_LENGTH+8];
	for(int i = 0; i < trollKV.Size; i++) {
		GetTrollByKeyIndex(i, troll);
		if(troll.categoryID == category) {
			Format(info, sizeof(info), "%d|%d", userid, i);
			if(troll.IsActive(victim)) {
				Format(name, sizeof(name), "%s (Active)", troll.name);
				trollMenu.AddItem(info, name);
			} else
				trollMenu.AddItem(info, troll.name);
		}
	}
	trollMenu.ExitButton = true;
	trollMenu.ExitBackButton = true;
	trollMenu.Display(client, 0);
}

void ShowSelectFlagMenu(int activator, int victimUserID, int modifiers, Troll troll, int prevFlags = 0) {
	static char info[MAX_TROLL_NAME_LENGTH+16];
	static char name[32];


	Menu flagMenu = new Menu(ChooseTrollFlagHandler);
	if(troll.flagsMultiselectable) {
		if(prevFlags == 0) prevFlags = troll.defaultFlags;
		Format(info, sizeof(info), "%s: Choose flags (Multiple)", troll.name);
		flagMenu.SetTitle(info);

		Format(info, sizeof(info), "%d|%d|%d|%d|1", victimUserID, troll.id, modifiers, prevFlags);
		flagMenu.AddItem(info, "Apply Troll / Finish");

		for(int i = 0; i < troll.flagNames.Length; i++) {
			troll.flagNames.GetString(i, name, sizeof(name));
			int a = 1 << i;
			if(prevFlags > 0 && prevFlags & a == a)
				Format(name, sizeof(name), "%s (On)", name);
			int newFlags = prevFlags ^ a;
			Format(info, sizeof(info), "%d|%d|%d|%d|0", victimUserID, troll.id, modifiers, newFlags);
			flagMenu.AddItem(info, name);
		}
	} else {
		Format(info, sizeof(info), "%s: Choose flags", troll.name);
		flagMenu.SetTitle(info);

		for(int i = 0; i < troll.flagNames.Length; i++) {
			troll.flagNames.GetString(i, name, sizeof(name));
			Format(info, sizeof(info), "%d|%d|%d|%d|0", victimUserID, troll.id, modifiers, 1 << i);
			flagMenu.AddItem(info, name);
		}
	}
	flagMenu.ExitButton = true;
	flagMenu.Display(activator, 0);
}

void ShowThrowItAllMenu(int client, int userid) {
	static char info[32];
	Menu itmMenu = new Menu(ChooseClumsySlotHandler); 
	itmMenu.SetTitle("Choose Item To Throw");

	static char itmName[32];
	Format(info, sizeof(info), "%d|-1", userid);
	itmMenu.AddItem(info, "All Items");
	for(int slot = 0; slot <= 4; slot++) {
		int item = GetPlayerWeaponSlot(client, slot);
		if(item > -1) {
			GetEdictClassname(item, itmName, sizeof(itmName));
			Format(info, sizeof(info), "%d|%d", userid, slot);
			itmMenu.AddItem(info, itmName[7]);
		}
	}
	itmMenu.ExitButton = true;
	itmMenu.Display(client, 0);
}