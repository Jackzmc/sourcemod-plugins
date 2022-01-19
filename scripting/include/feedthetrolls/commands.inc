public Action Command_InstaSpecial(int client, int args) {
	if(args < 1) {
		Menu menu = new Menu(Insta_PlayerHandler);
		menu.SetTitle("InstaSpecial: Choose a player");
		for(int i = 1; i < MaxClients; i++) {
			if(IsClientConnected(i) && IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == 2) {
				static char userid[8], display[16];
				Format(userid, sizeof(userid), "%d|0", GetClientUserId(i));
				GetClientName(i, display, sizeof(display));
				menu.AddItem(userid, display);
			}
		}
		menu.ExitButton = true;
		menu.Display(client, 0);
	} else {
		if(gInstaSpecialType > -1) {
			ReplyToCommand(client, "Please wait for last Insta to spawn.");
			return Plugin_Handled;
		}
		char arg1[32], arg2[32] = "jockey";
		GetCmdArg(1, arg1, sizeof(arg1));
		if(args >= 2) {
			GetCmdArg(2, arg2, sizeof(arg2));
		}
		char target_name[MAX_TARGET_LENGTH];
		int target_list[MAXPLAYERS], target_count;
		bool tn_is_ml;
		if ((target_count = ProcessTargetString(
			arg1,
			client,
			target_list,
			MaxClients,
			COMMAND_FILTER_ALIVE,
			target_name,
			sizeof(target_name),
			tn_is_ml)) <= 0
		) {
			/* This function replies to the admin with a failure message */
			ReplyToTargetError(client, target_count);
			return Plugin_Handled;
		}
		int specialType = GetSpecialType(arg2);
		static float pos[3];
		if(specialType == -1) {
			ReplyToCommand(client, "Unknown special \"%s\"", arg2);
			return Plugin_Handled;
		}
		int successes = 0;
		for (int i = 0; i < target_count; i++) {
			int target = target_list[i];
			if(GetClientTeam(target) == 2) {
				if(SpawnSpecialNear(target, specialType)) {
					LogAction(client, target, "\"%L\" spawned Insta-%s™ nearby \"%L\"", client, arg2, target);
					successes++;
				} else {
					ReplyToCommand(client, "[FTT] Could not spawn %s near %s", arg2, target_name);
				}
			}else{
				ReplyToTargetError(client, target_count);
			}
		}
		if(successes > 0)
			ShowActivityEx(client, "[FTT] ", "spawned Insta-%s™ near %s", arg2, target_name);
	}


	return Plugin_Handled;
}

public Action Command_InstaSpecialFace(int client, int args) {
	if(args < 1) {
		Menu menu = new Menu(Insta_PlayerHandler);
		menu.SetTitle("Inface: Choose a player");
		for(int i = 1; i < MaxClients; i++) {
			if(IsClientConnected(i) && IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == 2) {
				static char userid[8], display[16];
				Format(userid, sizeof(userid), "%d|1", GetClientUserId(i));
				GetClientName(i, display, sizeof(display));
				menu.AddItem(userid, display);
			}
		}
		menu.ExitButton = true;
		menu.Display(client, 0);
	} else {
		if(gInstaSpecialType > -1) {
			ReplyToCommand(client, "Please wait for last Insta to spawn.");
			return Plugin_Handled;
		}
		char arg1[32], arg2[32] = "jockey";
		GetCmdArg(1, arg1, sizeof(arg1));
		if(args >= 2) {
			GetCmdArg(2, arg2, sizeof(arg2));
		}
		char target_name[MAX_TARGET_LENGTH];
		int target_list[MAXPLAYERS], target_count;
		bool tn_is_ml;
		if ((target_count = ProcessTargetString(
			arg1,
			client,
			target_list,
			MaxClients,
			COMMAND_FILTER_ALIVE,
			target_name,
			sizeof(target_name),
			tn_is_ml)) <= 0
		) {
			/* This function replies to the admin with a failure message */
			ReplyToTargetError(client, target_count);
			return Plugin_Handled;
		}
		int specialType = GetSpecialType(arg2);
		static float pos[3];
		if(specialType == -1) {
			ReplyToCommand(client, "Unknown special \"%s\"", arg2);
			return Plugin_Handled;
		}
		int successes = 0;
		for (int i = 0; i < target_count; i++) {
			int target = target_list[i];
			if(GetClientTeam(target) == 2) {
				if(SpawnSpecialInFace(target, specialType)) {
					LogAction(client, target, "\"%L\" spawned Insta-%s™ at player \"%L\"", client, arg2, target);
					successes++;
				} else {
					ReplyToCommand(client, "[FTT] Could not spawn %s on %s", arg2, target_name);
				}
			}else{
				ReplyToTargetError(client, target_count);
			}
		}
		if(successes > 0)
			ShowActivityEx(client, "[FTT] ", "spawned Insta-%s™ on %s", arg2, target_name);
	}
	return Plugin_Handled;
}


public Action Command_WitchAttack(int client, int args) {
	if(args < 1) {
		ReplyToCommand(client, "Usage: sm_witch_attack <user>");
	} else {
		char arg1[32];
		GetCmdArg(1, arg1, sizeof(arg1));
		char target_name[MAX_TARGET_LENGTH];
		int target_list[MAXPLAYERS], target_count;
		bool tn_is_ml;
		if ((target_count = ProcessTargetString(
			arg1,
			client,
			target_list,
			1,
			COMMAND_FILTER_ALIVE | COMMAND_FILTER_NO_MULTI, /* Only allow alive players */
			target_name,
			sizeof(target_name),
			tn_is_ml)) <= 0
		) {
			/* This function replies to the admin with a failure message */
			ReplyToTargetError(client, target_count);
			return Plugin_Handled;
		}

		int target = target_list[0];
		if(GetClientTeam(target) == 2) {
			int witch = INVALID_ENT_REFERENCE;
			while ((witch = FindEntityByClassname(witch, "witch")) != INVALID_ENT_REFERENCE) {
				SetWitchTarget(witch, target);

				ShowActivityEx(client, "[FTT] ", "set all witches to target %s", target_name);
				LogAction(client, target, "\"%L\" set all witches to attack \"%L\"", client, target);
			}
		}else{
			ReplyToTargetError(client, target_count);
		}
	}

	return Plugin_Handled;
}

public Action Command_FeedTheCrescendoTroll(int client, int args) {
	if(lastCrescendoUser > -1) {
		ActivateAutoPunish(lastCrescendoUser);
		ReplyToCommand(client, "Activated auto punish on %N", lastCrescendoUser);
		LogAction(client, lastCrescendoUser, "\"%L\" autopunished crescendo rusher \"%L\"", client, lastCrescendoUser);
		ShowActivityEx(client, "[FTT] ", "activated autopunish for crescendo activator %N",lastCrescendoUser);
	}else{
		ReplyToCommand(client, "No player could be found to autopunish.");
	}
	return Plugin_Handled;
}

public Action Command_ResetUser(int client, int args) {
	if(args < 1) {
		ReplyToCommand(client, "Usage: sm_ftr <user(s)>");
	}else{
		char arg1[32];
		GetCmdArg(1, arg1, sizeof(arg1));
		char target_name[MAX_TARGET_LENGTH];
		int target_list[MAXPLAYERS], target_count;
		bool tn_is_ml;
		if ((target_count = ProcessTargetString(
			arg1,
			client,
			target_list,
			MAXPLAYERS,
			COMMAND_FILTER_CONNECTED, /* Only allow alive players */
			target_name,
			sizeof(target_name),
			tn_is_ml)) <= 0
		) {
			/* This function replies to the admin with a failure message */
			ReplyToTargetError(client, target_count);
			return Plugin_Handled;
		}

		for (int i = 0; i < target_count; i++) {
			if(IsAnyTrollActive(target_list[i])) {
				LogAction(client, target_list[i], "\"%L\" reset all troll effects for \"%L\"", client, target_list[i]);
				ShowActivityEx(client, "[FTT] ", "reset troll effects for \"%N\". ", target_list[i]);
			}
			ResetClient(target_list[i], true);
		}
	}
	return Plugin_Handled;
}

public Action Command_ApplyUser(int client, int args) {
	if(args < 1) {
		SilentMenuSelected[client] = false;
		ShowTrollMenu(client, false);
	}else{
		char arg1[32], arg2[16];
		GetCmdArg(1, arg1, sizeof(arg1));
		GetCmdArg(2, arg2, sizeof(arg2));
		StringToLower(arg2);

		static char target_name[MAX_TARGET_LENGTH];
		int target_list[1], target_count;
		bool tn_is_ml;
		if ((target_count = ProcessTargetString(
			arg1,
			client,
			target_list,
			1,
			COMMAND_FILTER_NO_MULTI, 
			target_name,
			sizeof(target_name),
			tn_is_ml)) <= 0
		&& target_list[0] > 0) {
			/* This function replies to the admin with a failure message */
			ReplyToTargetError(client, target_count);
			return Plugin_Handled;
		}
		if(args == 2) {
			static char key[32];
			for(int i = 0; i < categories.Length; i++) {
				categories.GetString(i, key, sizeof(key));
				if(StrEqual(key, arg2, false)) {
					SilentMenuSelected[client] = false;
					ShowTrollsForCategory(client, GetClientUserId(target_list[0]), i);
					return Plugin_Handled;
				}
			} 
			ReplyToCommand(client, "[FTT] Unknown category: '%s'", arg2);
		}
		SilentMenuSelected[client] = false;
		SetupCategoryMenu(client, target_list[0]);
	}
	return Plugin_Handled;
}

public Action Command_ApplyComboTrolls(int client, int args) {
	if(args < 1) {
		ShowTrollMenu(client, true);
	}else{
		char arg1[32];
		GetCmdArg(1, arg1, sizeof(arg1));

		static char target_name[MAX_TARGET_LENGTH];
		int target_list[1], target_count;
		bool tn_is_ml;
		if ((target_count = ProcessTargetString(
			arg1,
			client,
			target_list,
			1,
			COMMAND_FILTER_NO_MULTI, 
			target_name,
			sizeof(target_name),
			tn_is_ml)) <= 0
		&& target_list[0] > 0) {
			/* This function replies to the admin with a failure message */
			ReplyToTargetError(client, target_count);
			return Plugin_Handled;
		}
		ShowTrollCombosMenu(client, target_list[0]);
	}
	return Plugin_Handled;	
}

public Action Command_ApplyUserSilent(int client, int args) {
	if(args < 1) {
		SilentMenuSelected[client] = true;
		ShowTrollMenu(client, false);
	}else{
		char arg1[32], arg2[16];
		GetCmdArg(1, arg1, sizeof(arg1));
		GetCmdArg(2, arg2, sizeof(arg2));
		StringToLower(arg2);

		static char target_name[MAX_TARGET_LENGTH];
		int target_list[1], target_count;
		bool tn_is_ml;
		if ((target_count = ProcessTargetString(
			arg1,
			client,
			target_list,
			1,
			COMMAND_FILTER_NO_MULTI, 
			target_name,
			sizeof(target_name),
			tn_is_ml)) <= 0
		&& target_list[0] > 0) {
			/* This function replies to the admin with a failure message */
			ReplyToTargetError(client, target_count);
			return Plugin_Handled;
		}
		SilentMenuSelected[client] = true;
		if(args == 2) {
			static char key[32];
			for(int i = 0; i < categories.Length; i++) {
				categories.GetString(i, key, sizeof(key));
				if(StrEqual(key, arg2, false)) {
					ShowTrollsForCategory(client, GetClientUserId(target_list[0]), i);
					return Plugin_Handled;
				}
			} 
			ReplyToCommand(client, "[FTT] Unknown category: '%s'", arg2);
		}
		SetupCategoryMenu(client, target_list[0]);
	}
	return Plugin_Handled;
}

public Action Command_ListModes(int client, int args) {
	static char name[MAX_TROLL_NAME_LENGTH];
	static Troll troll;
	for(int i = 0; i <= MAX_TROLLS; i++) {
		GetTrollByKeyIndex(i, troll);
		if(troll.hidden) continue;
		ReplyToCommand(client, "%d. %s - %s", i, troll.name, troll.description);
	}
	return Plugin_Handled;
}

public Action Command_ListTheTrolls(int client, int args) {
	// View more info about a user
	if(args == 1) {
		char arg1[32];
		GetCmdArg(1, arg1, sizeof(arg1));

		static char target_name[MAX_TARGET_LENGTH];
		int target_list[MAXPLAYERS], target_count;
		bool tn_is_ml;
		if ((target_count = ProcessTargetString(
			arg1,
			client,
			target_list,
			MAXPLAYERS,
			0, 
			target_name,
			sizeof(target_name),
			tn_is_ml)) <= 0
		|| target_list[0] == 0) {
			/* This function replies to the admin with a failure message */
			ReplyToTargetError(client, target_count);
			return Plugin_Handled;
		}
		
		for(int p = 0; p < target_count; p++) {
			int target = target_list[p];
			if(IsPlayerAlive(target))
				ReplyToCommand(client, "> Active Trolls for %N:", target);
			else
				ReplyToCommand(client, "> Active Trolls for %N:  (Paused)", target);

			if(IsFakeClient(target)) {
				int player = GetRealClient(target);
				if(player != -1) target = player;
			}

			for(int j = 1; j <= MAX_TROLLS; j++) {
				if(Trolls[j].hidden) continue;
				if(trollIds[j][0] != '\0' && IsTrollActive(target, trollIds[j])) {
					if(Trolls[j].activeFlagClients[target] > 0) {
						static char list[MAX_TROLL_FLAG_LENGTH*8]; //May in future need to up magic number 8 (supports 8 active flags )
						static char buffer[MAX_TROLL_FLAG_LENGTH];
						for(int i = 0; i < Trolls[j].flagNames.Length; i++) {
							int a = (1 << i);
							if(Trolls[j].activeFlagClients[target] & a) {
								Trolls[j].flagNames.GetString(i, buffer, sizeof(buffer));
								Format(list, sizeof(list), "%s%s;", list, buffer);
							} else {
								Trolls[j].flagNames.GetString(i, buffer, sizeof(buffer));
							}
						}
						ReplyToCommand(client, "\"%s\" Flags: %s", trollIds[j], list);
					} else
						ReplyToCommand(client, trollIds[j]);
				}
			}
		}
		return Plugin_Handled;
	}

	int count = 0;
	char[][] modeListArr = new char[MAX_TROLLS+1][MAX_TROLL_NAME_LENGTH];
	static char modeList[255];
	static char name[MAX_TROLL_NAME_LENGTH];
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) > 1 && IsAnyTrollActive(i)) {
			if(IsFakeClient(i)) {
				int player = GetRealClient(i);
				if(player != -1) i = player;
			}
			int modeCount = 0;
			for(int j = 1; j <= MAX_TROLLS; j++) {
				if(trollIds[j][0] != '\0' && IsTrollActive(i, trollIds[j])) {
					if(Trolls[j].activeFlagClients[i] > 0)
						Format(modeListArr[modeCount], MAX_TROLL_NAME_LENGTH, "%s(%d)", trollIds[j], Trolls[j].activeFlagClients[i]);
					else
						strcopy(modeListArr[modeCount], MAX_TROLL_NAME_LENGTH, trollIds[j]);
					modeCount++;
				}
			}

			ImplodeStrings(modeListArr, modeCount, ", ", modeList, sizeof(modeList));
			if(IsPlayerAlive(i))
				ReplyToCommand(client, "%N | %s", i, modeList);
			else
				ReplyToCommand(client, "%N (Paused) | %s", i, modeList);
			count++;
		}
	}
	if(count == 0) {
		ReplyToCommand(client, "No clients have a mode applied.");
	}
	return Plugin_Handled;
}

public Action Command_MarkPendingTroll(int client, int args) {
	if(args == 0) {
		Menu menu = new Menu(ChooseMarkedTroll);
		menu.SetTitle("Choose a troll to mark");
		static char userid[8], display[16];
		for(int i = 1; i < MaxClients; i++) {
			if(IsClientConnected(i) && IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == 2) {
				AdminId admin = GetUserAdmin(i);
				if(admin == INVALID_ADMIN_ID) {
					Format(userid, sizeof(userid), "%d", GetClientUserId(i));
					GetClientName(i, display, sizeof(display));
					menu.AddItem(userid, display);
				}else{
					ReplyToCommand(client, "%N is an admin cannot be marked.", i);
				}
			}
		}
		menu.ExitButton = true;
		menu.Display(client, 0);
	} else {
		static char arg1[32];
		GetCmdArg(1, arg1, sizeof(arg1));
		char target_name[MAX_TARGET_LENGTH];
		int target_list[MAXPLAYERS], target_count;
		bool tn_is_ml;
		if ((target_count = ProcessTargetString(
			arg1,
			client,
			target_list,
			1,
			COMMAND_FILTER_NO_MULTI , /* Only allow alive players */
			target_name,
			sizeof(target_name),
			tn_is_ml)) <= 0
		) {
			/* This function replies to the admin with a failure message */
			ReplyToTargetError(client, target_count);
			return Plugin_Handled;
		}
		int target = target_list[0];
		if(GetClientTeam(target) == 2) {
			ToggleMarkPlayer(client, target);
		}else{
			ReplyToCommand(client, "Player does not exist or is not a survivor.");
		}
	}
	return Plugin_Handled;
}

public Action Command_FeedTheTrollMenu(int client, int args) {
	ReplyToCommand(client, "sm_ftl [player(s)] - Lists all the active trolls on players. Will show flag names if a player is specified.");
	ReplyToCommand(client, "sm_ftm - Lists all available trolls & descriptions");
	ReplyToCommand(client, "sm_ftr <player(s)> - Resets target users' of any active trolls");
	ReplyToCommand(client, "sm_fta [player] [category] - Apply a troll on a player, with optional shortcut to player and/or category");
	ReplyToCommand(client, "sm_ftt - Shows this text");
	ReplyToCommand(client, "sm_ftc - Will apply a punishment to the last crescendo/event activator");
	ReplyToCommand(client, "sm_mark - Marks the user to be banned on disconnect, prevents their FF.");
	return Plugin_Handled;
}

public Action Command_BotsAttack(int client, int args) {
	if(args > 0) {
		static char arg1[32], arg2[4];
		GetCmdArg(1, arg1, sizeof(arg1));
		GetCmdArg(2, arg2, sizeof(arg2));

		int targetHP;
		if(StringToIntEx(arg2, targetHP) == 0 || targetHP < 0 || targetHP > 100) {
			ReplyToCommand(client, "Invalid target HP value. Must be between 0 and 100");
			return Plugin_Handled;
		}

		int target_list[MAXPLAYERS], target_count;
		static char target_name[MAX_TARGET_LENGTH];
		bool tn_is_ml;
		if ((target_count = ProcessTargetString(
			arg1,
			client,
			target_list,
			1,
			COMMAND_FILTER_ALIVE | COMMAND_FILTER_NO_MULTI,
			target_name,
			sizeof(target_name),
			tn_is_ml)) <= 0
		) {
			/* This function replies to the admin with a failure message */
			ReplyToTargetError(client, target_count);
			return Plugin_Handled;
		}
		int target = target_list[0];
		for(int i = 1; i <= MaxClients; i++) {
			if(IsClientConnected(i) && IsClientInGame(i) && IsFakeClient(i) && GetClientTeam(i) == 2) {
				if(!SetBotTarget(target, i, targetHP, 80)) {
					ReplyToCommand(client, "%N could not target %s", i, target_name);
				}
			}
		}
		ShowActivity(client, "set all bots to attack %s", target_name);
	} else {
		ReplyToCommand(client, "syntax: sm_bots_attack <target player> [target-hp]");
	}
	return Plugin_Handled;
}