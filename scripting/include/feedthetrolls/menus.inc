public int Insta_PlayerHandler(Menu menu, MenuAction action, int client, int param2) {
	/* If an option was selected, tell the client about the item. */
	if (action == MenuAction_Select) {
		static char info[16];
		menu.GetItem(param2, info, sizeof(info));

		static char str[2][8];
		ExplodeString(info, "|", str, 2, 8, false);

		int userid = StringToInt(str[0]);
		int instaMode = StringToInt(str[1]);
		ShowInstaSpecialChooser(client, userid, instaMode);
	} else if (action == MenuAction_End)
		delete menu;
	return 0;
}

void ShowInstaSpecialChooser(int activator, int userid, int instaMode) {
	Menu menu = new Menu(Insta_SpecialHandler);
	menu.SetTitle("Choose a Insta-Special™");
	char data[16];
	for(int i = 1; i <= 8; i++) {
		Format(data, sizeof(data), "%d|%d|%d", userid, instaMode, i);
		menu.AddItem(data, SPECIAL_NAMES[i-1]);
	}
	menu.ExitButton = true;
	menu.Display(activator, 0);
}

public int Insta_SpecialHandler(Menu menu, MenuAction action, int client, int param2) {
	/* If an option was selected, tell the client about the item. */
	if (action == MenuAction_Select) {
		static char info[16];
		menu.GetItem(param2, info, sizeof(info));
		static char str[3][8];
		ExplodeString(info, "|", str, 3, 8, false);
		int userid = StringToInt(str[0]);
		int target = GetClientOfUserId(userid);
		bool inFace = StrEqual(str[1], "1");
		int specialInt = StringToInt(str[2]);
		if(specialInt < 0 || specialInt > 8) {
			ReplyToCommand(client, "Invalid special id");
			return 0;
		}
		SpecialType special = view_as<SpecialType>(specialInt);
		if(inFace) {
			if(SpawnSpecialForTarget(special, target, view_as<int>(Special_OnTarget) | view_as<int>(Special_SpawnDirectOnFailure) | view_as<int>(Special_AlwaysTarget))) {
				LogAction(client, target, "\"%L\" spawned Insta-%s™ on \"%L\"", client, SPECIAL_NAMES[specialInt-1], target);
				CShowActivityEx(client, "[FTT] ", "spawned {olive}Insta-%s™{default} on {olive}%N", SPECIAL_NAMES[specialInt-1], target);
			} else {
				ReplyToCommand(client, "Could not spawn special.");
			}
		} else {
			if(SpawnSpecialForTarget(special, target, view_as<int>(Special_AlwaysTarget))) {
				CShowActivityEx(client, "[FTT] ", "spawned {green}Insta-%s™{default} near {green}%N", SPECIAL_NAMES[specialInt-1], target);
				LogAction(client, target, "\"%L\" spawned Insta-%s™ near \"%L\"", client, SPECIAL_NAMES[specialInt-1], target);
			} else {
				ReplyToCommand(client, "Could not spawn special.");
			}
		}
		ShowInstaSpecialChooser(client, userid, inFace);
	} else if (action == MenuAction_End)
		delete menu;
	return 0;
}


public int ChooseMarkedTroll(Menu menu, MenuAction action, int activator, int param2) {
	if (action == MenuAction_Select) {
		static char info[16];
		menu.GetItem(param2, info, sizeof(info));
		int target = GetClientOfUserId(StringToInt(info));
		ToggleMarkPlayer(activator, target);
	} else if (action == MenuAction_End)
		delete menu;
	return 0;
}

public int ChoosePlayerHandler(Menu menu, MenuAction action, int param1, int param2) {
	/* If an option was selected, tell the client about the item. */
	if (action == MenuAction_Select) {
		static char info[8];
		menu.GetItem(param2, info, sizeof(info));
		int userid = StringToInt(info);
		int victim = GetClientOfUserId(userid);

		if(victim == 0) {
			ReplyToCommand(param1, "FTT: Could not acquire player");
			return 0;
		}
		
		SetupCategoryMenu(param1, userid);
	} else if (action == MenuAction_End) {
		delete menu;
	}
	return 0;
}

public int ChoosePlayerHandlerForCombos(Menu menu, MenuAction action, int client, int param2) {
	if (action == MenuAction_Select) {
		static char info[8];
		menu.GetItem(param2, info, sizeof(info));
		int userid = StringToInt(info);
		int victim = GetClientOfUserId(userid);

		if(victim == 0) {
			ReplyToCommand(victim, "FTT: Could not acquire player");
			return 0;
		}
		
		ShowTrollCombosMenu(client, userid);
	} else if (action == MenuAction_End)
		delete menu;
	return 0;
}

public int ChooseComboHandler(Menu menu, MenuAction action, int client, int param2) {
	if (action == MenuAction_Select) {
		static char info[16];
		menu.GetItem(param2, info, sizeof(info));
		static char str[2][8];
		ExplodeString(info, "|", str, 2, 8, false);
		int userid = StringToInt(str[0]);
		int victim = GetClientOfUserId(userid);
		int comboID = StringToInt(str[1]);

		if(victim == 0) {
			ReplyToCommand(client, "FTT: Could not acquire player");
			return 0;
		}
		
		static TrollComboData combo;
		combos.GetArray(comboID, combo, sizeof(combo));
		combo.Activate(client, victim);
	} else if (action == MenuAction_End)
		delete menu;
	return 0;
}

static int iMenuVictimID[MAXPLAYERS+1];
public int ChooseCategoryHandler(Menu menu, MenuAction action, int param1, int param2) {
	if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
		ShowTrollMenu(param1, false);
	else if (action == MenuAction_Select) {
		static char info[32];
		menu.GetItem(param2, info, sizeof(info));
		static char str[2][8];
		ExplodeString(info, "|", str, 2, 8, false);
		int userid = StringToInt(str[0]);
		int victim = GetClientOfUserId(userid);
		if(victim == 0) {
			ReplyToCommand(param1, "FTT/ChooseCategoryHandler: Could not acquire player");
			return 0;
		}
		
		iMenuVictimID[param1] = userid;
		int category = StringToInt(str[1]);

		// Reset troll:
		if(category == -1) {
			Troll.FromName("Reset User").Activate(param1, victim, TrollMod_Instant);
			return 0;
		}
		
		ShowTrollsForCategory(param1, userid, category);
	} else if (action == MenuAction_End)
		delete menu;
	return 0;
}

public int ChooseModeMenuHandler(Menu menu, MenuAction action, int param1, int param2) {
	if (action == MenuAction_Cancel) {
		if(param2 == MenuCancel_ExitBack) {
			if(iMenuVictimID[param1] == 0) {
				ReplyToCommand(param1, "FTT/ChooseModeMenuHandler: Could not acquire player");
			}
			SetupCategoryMenu(param1, iMenuVictimID[param1]);
		}
	} else if (action == MenuAction_Select) {
		static char info[32];
		menu.GetItem(param2, info, sizeof(info));
		static char str[2][8];
		ExplodeString(info, "|", str, 2, 8, false);
		int userid = StringToInt(str[0]);
		int victim = GetClientOfUserId(userid);
		if(victim == 0) {
			ReplyToCommand(param1, "FTT: Could not acquire player");
			return 0;
		}

		int keyIndex = StringToInt(str[1]);
		Troll troll = Troll(keyIndex);
		//If troll has multiple flags, prompt:
		if(troll == t_throwItAll) {
			// Setup menu to call itself, but with an extra data point
			ShowThrowItAllMenu(param1, userid);
		} else if(!troll.IsActive(victim) && troll.HasMod(TrollMod_Instant) && troll.HasMod(TrollMod_Constant)) {
			Menu modiferMenu = new Menu(ChooseTrollModiferHandler); 
			// sadly cannot use methodmap easily to return name
			Format(info, sizeof(info), "%s: Choose Modifier", Trolls[troll.Id].name);
			modiferMenu.SetTitle(info);

			Format(info, sizeof(info), "%d|%d|1", userid, keyIndex);
			modiferMenu.AddItem(info, "Activate Once");
			Format(info, sizeof(info), "%d|%d|2", userid, keyIndex);
			modiferMenu.AddItem(info, "Activate Periodically");
			Format(info, sizeof(info), "%d|%d|3", userid, keyIndex);
			modiferMenu.AddItem(info, "Activate Periodically & Instantly");

			modiferMenu.ExitButton = true;
			modiferMenu.Display(param1, 0);
		} else if(!troll.IsActive(victim) && troll.HasOptions) {
 			ShowSelectFlagMenu(param1, userid, -1, troll);
		} else {
			TrollEffectResponse response = troll.Activate(param1, victim);
			// Only show menu if success or error, not TE_Menu
			if(response != TE_Menu)
				ShowTrollsForCategory(param1, userid, troll.CategoryId);
		}
		
	} else if (action == MenuAction_End)
		delete menu;
	return 0;
}

public int ChooseClumsySlotHandler(Menu menu, MenuAction action, int param1, int param2) {
	if (action == MenuAction_Select) {
		char info[32];
		menu.GetItem(param2, info, sizeof(info));
		static char str[2][8];
		ExplodeString(info, "|", str, 2, 8, false);
		int userid = StringToInt(str[0]);
		int client = GetClientOfUserId(userid);
		int slot = StringToInt(str[1]);
		if(client == 0) {
			ReplyToCommand(param1, "FTT: Could not acquire player");
			return 0;
		}else if(slot == -1) {
			for(int i = 0; i <= 4; i++) {
				ThrowItemToPlayer(client, param1, i);
			}
		} else if(slot == -2) {
			ShowThrowItAllMenu(param1, userid);
		} else {
			if(!GetClientWeaponNameSmart(client, slot, info, sizeof(info))) {
				strcopy(info, sizeof(info), "-unk-");
			}
			CShowActivityEx(param1, "[FTT] ", "activated troll {yellow}Throw It All{default} ({olive}%s|%d{default}) for \"%N\"", info, slot, client);
			LogAction(param1, client, "\"%L\" activated troll \"Throw It All\" (%s) for \"%L\". ", param1, info, client);
			ThrowItemToPlayer(client, param1, slot);
		}
		
		ShowThrowItAllMenu(param1, userid);
	} else if (action == MenuAction_End)	
		delete menu;
	return 0;
}

public int ChooseTrollModiferHandler(Menu menu, MenuAction action, int param1, int param2) {
	if (action == MenuAction_Select) {
		static char info[16];
		menu.GetItem(param2, info, sizeof(info));
		static char str[3][8];
		ExplodeString(info, "|", str, 3, 8, false);
		int userid = StringToInt(str[0]);
		int victim = GetClientOfUserId(userid);
		int keyIndex = StringToInt(str[1]);
		int modifiers = StringToInt(str[2]);

		if(victim == 0) {
			ReplyToCommand(param1, "FTT: Could not acquire player");
			return 0;
		}

		Troll troll = Troll(keyIndex);
		if(!troll.IsActive(victim) && troll.HasOptions) {
			// Show flag selection if troll is not enabled already
 			ShowSelectFlagMenu(param1, userid, modifiers, troll);
		} else {
			TrollEffectResponse response;
			if(modifiers == 1 || modifiers == 3)
				response = troll.Activate(param1, victim, TrollMod_Instant);
			if(modifiers == 2 || modifiers == 3)
				response = troll.Activate(param1, victim, TrollMod_Constant);	
			if(response != TE_Menu)
				ShowTrollsForCategory(param1, userid, troll.CategoryId);
		}
		
	} else if (action == MenuAction_End)	
		delete menu;
	return 0;
}

public int ChooseTrollFlagHandler(Menu menu, MenuAction action, int param1, int param2) {
	if (action == MenuAction_Select) {
		static char info[32];
		menu.GetItem(param2, info, sizeof(info));
		static char str[6][8];
		ExplodeString(info, "|", str, 6, 8, false);
		int userid = StringToInt(str[0]);
		int victim = GetClientOfUserId(userid);
		int keyIndex = StringToInt(str[1]);
		int modifiers = StringToInt(str[2]);
		int flags = StringToInt(str[3]);
		int index = StringToInt(str[4]);
		bool isDone = StringToInt(str[5]) == 1; // 0 = cont, 1 = done

		if(victim == 0) {
			ReplyToCommand(param1, "FTT: Could not acquire player");
			return 0;
		}

		Troll troll = Troll(keyIndex);

		// If told to go to next prompt, find the next VALID prompt
		// Valid prompt is one where the required flags for it, are active

		if(isDone || index == -1) {
			int nextIndex = GetNextPrompt(troll, flags, index);
			// If there is a prompt available, show it, else fall down 
			if(nextIndex >= 0) {
				ShowSelectFlagMenu(param1, userid, modifiers, troll, flags, nextIndex);
				return 0;
			}
			// else fall through & apply
		} else {
			ShowSelectFlagMenu(param1, userid, modifiers, troll, flags, index);
			return 0;
		}

		TrollEffectResponse response;
		// Done with prompts, apply flags & modifiers
		if(modifiers > 0) {
			if(modifiers & view_as<int>(TrollMod_Instant))
				response = troll.Activate(param1, victim, TrollMod_Instant, flags);
			if(modifiers & view_as<int>(TrollMod_Constant))
				response = troll.Activate(param1, victim, TrollMod_Constant, flags);
		} else {
			response = troll.Activate(param1, victim, TrollMod_Invalid, flags);
		}
		// Jump back to selection screen
		if(response != TE_Menu)
			ShowTrollsForCategory(param1, userid, troll.CategoryId);
	} else if (action == MenuAction_End)	
		delete menu;
	return 0;	
}


public void StopItemGive(int client) {
	pdata[client].flags &= ~view_as<int>(Flag_PendingItemGive);
}

void SetupCategoryMenu(int client, int victimUserID) {
	iMenuVictimID[client] = victimUserID;
	Menu categoryMenu = new Menu(ChooseCategoryHandler);
	static char category[64], id[16];
	// Title with [ in name cause failure
	Format(category, sizeof(category), "Choose troll category");
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

void ShowTrollCombosMenu(int client, int victimUserID) {
	Menu comboMenu = new Menu(ChooseComboHandler);
	static char id[32];
	Format(id, sizeof(id), "Choose troll combo");
	comboMenu.SetTitle(id);

	static TrollComboData combo;

	if(combos.Length == 0) {
		ReplyToCommand(client, "FTT: No troll combos available");
		return;
	} 

	for(int i = 0; i < combos.Length; i++) {
		combos.GetArray(i, combo, sizeof(combo));
		Format(id, sizeof(id), "%d|%d", victimUserID, i);
		comboMenu.AddItem(id, combo.name);
	}

	comboMenu.ExitButton = true;
	comboMenu.ExitBackButton = true;
	comboMenu.Display(client, 0);
}

void ShowTrollMenu(int client, bool isComboList) {
	Menu menu = isComboList ? new Menu(ChoosePlayerHandlerForCombos) : new Menu(ChoosePlayerHandler);
	menu.SetTitle("Choose a player to troll");
	// If player idle, say they are survivor
	int clientTeam = GetClientTeam(client);
	if(clientTeam < 2) {
		if(L4D_IsPlayerIdle(client)) clientTeam = 2;
	}

	static char userid[8], display[64];
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && (hAllowEnemyTeam.BoolValue || GetClientTeam(i) == clientTeam)) {
			IntToString(GetClientUserId(i), userid, sizeof(userid));
			GetMenuDisplayName(i, display, sizeof(display));
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
	
	int victim = GetClientOfUserId(userid);

	// Add all menus that have same category ID to list
	char name[MAX_TROLL_NAME_LENGTH+8];
	for(int i = 0; i < trollKV.Size; i++) {
		Troll troll = Troll(i);
		// If troll is hidden and using normal menu, do not show
		if(troll.Hidden && !SilentMenuSelected[client]) continue;
		if(troll.CategoryId == category) {
			Format(info, sizeof(info), "%d|%d", userid, i);
			if(troll.IsActive(victim)) {
				Format(name, sizeof(name), "%s (Active)", Trolls[i].name);
				trollMenu.AddItem(info, name);
			} else
				trollMenu.AddItem(info, Trolls[i].name);
		}
	}
	trollMenu.ExitButton = true;
	trollMenu.ExitBackButton = true;
	trollMenu.Display(client, 0);
}

// Called with defaults on start, then recalled by ChooseTrollFlagHandler until prompt selection finished
void ShowSelectFlagMenu(int activator, int victimUserID, int modifiers, Troll troll, int prevFlags = -1, int promptIndex = 0) {
	char info[MAX_TROLL_NAME_LENGTH+16]; //victimUSERID|trollID|modifiers|flags||flagIndex
	char name[32];

	Menu flagMenu = new Menu(ChooseTrollFlagHandler);

	TrollFlagPrompt prompt;
	troll.GetPrompt(promptIndex, prompt);
	prompt.GetPromptText(info, sizeof(info));
	flagMenu.SetTitle("%s", info);

	if(prevFlags == -1 && prompt.multiselect) prevFlags = prompt.defaults;

	
	Format(info, sizeof(info), "%d|%d|%d|%d|%d|1", victimUserID, troll.Id, modifiers, prevFlags, promptIndex);

	if(prompt.multiselect) {
		Format(info, sizeof(info), "%d|%d|%d|%d|%d|1", victimUserID, troll.Id, modifiers, prevFlags, promptIndex);
		flagMenu.AddItem(info, "Apply / Next Prompt");
	} else {
		if(prevFlags == -1) prevFlags = 0;
	}
	for(int i = 0; i < troll.TotalOptionsCount; i++) {
		int bit = 1 << i;
		// Does prompt have bit
		if(prompt.flags & bit) {
			troll.GetOptionName(i, name, sizeof(name));
			// If flag is enabled, show indication (On)
			int newFlags;
			if(prompt.multiselect) {
				if(prevFlags & bit)
					Format(name, sizeof(name), "%s ✓", name);
				newFlags = prevFlags ^ bit; //Toggle the flag instead of setting like below, as it's toggleable here
			} else {
				if(prompt.defaults & bit)
					Format(name, sizeof(name), "%s (default)", name);
				newFlags = prevFlags | bit;
			}
			Format(info, sizeof(info), "%d|%d|%d|%d|%d|%b", victimUserID, troll.Id, modifiers, newFlags, promptIndex, !prompt.multiselect);
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
	Format(info, sizeof(info), "%d|-2", userid);
	itmMenu.AddItem(info, "Refresh");

	Format(info, sizeof(info), "%d|-1", userid);
	itmMenu.AddItem(info, "All Items");

	int victim = GetClientOfUserId(userid);
	if(victim == 0) {
		ReplyToCommand(client, "FTT: Could not acquire player");
		return;
	}
	
	// Grab all the items the player has, add to menu
	for(int slot = 0; slot <= 5; slot++) {
		int item = GetClientWeaponNameSmart2(victim, slot, itmName, sizeof(itmName));
		if(item > -1) {
			Format(info, sizeof(info), "%d|%d", userid, slot);
			itmMenu.AddItem(info, itmName);
		}
	}

	itmMenu.ExitButton = true;
	itmMenu.Display(client, 0);
}

int GetNextPrompt(Troll troll, int flags, int currentPrompt = 0) {
	TrollFlagPrompt prompt;
	// Check if we at the end of all possible prompts:
	if(currentPrompt + 1 == troll.PromptCount) return -2;
	//If this prompt requires flags but they don't exist, skip to next that is valid or be done:
	for(int i = currentPrompt + 1; i < troll.PromptCount; i++) {
		troll.GetPrompt(i, prompt);
		if(flags & prompt.requireFlags == prompt.requireFlags) {
			return i;
		}
	}
	// No suitable prompts found, mark it as done:
	return -1;
}