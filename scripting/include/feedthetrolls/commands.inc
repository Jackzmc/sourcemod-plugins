Action Command_InstaSpecial(int client, int args) {
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
		
		SpecialType specialType = GetSpecialType(arg2);
		if(specialType == Special_Invalid) {
			ReplyToCommand(client, "Unknown special \"%s\"", arg2);
			return Plugin_Handled;
		}

		int successes = 0;
		for (int i = 0; i < target_count; i++) {
			int target = target_list[i];
			if(GetClientTeam(target) == 2) {
				if(SpawnSpecialForTarget(specialType, target, view_as<int>(Special_AlwaysTarget))) {
					LogAction(client, target, "\"%L\" spawned Insta-%s™ nearby \"%L\"", client, arg2, target);
					successes++;
				} else {
					ReplyToCommand(client, "[FTT] Could not spawn %s near %s", arg2, target_name);
				}
			} else {
				ReplyToTargetError(client, target_count);
			}
		}
		if(successes > 0)
			CShowActivityEx(client, "[FTT] ", "spawned {green}Insta-%s™{default} near {green}%s", arg2, target_name);
	}


	return Plugin_Handled;
}

Action Command_InstaSpecialFace(int client, int args) {
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

		SpecialType specialType = GetSpecialType(arg2);
		if(specialType == Special_Invalid) {
			ReplyToCommand(client, "Unknown special \"%s\"", arg2);
			return Plugin_Handled;
		}

		int successes = 0;
		for (int i = 0; i < target_count; i++) {
			int target = target_list[i];
			if(GetClientTeam(target) == 2) {
				if(SpawnSpecialForTarget(specialType, target, view_as<int>(Special_OnTarget) | view_as<int>(Special_AlwaysTarget))) {
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
			CShowActivityEx(client, "[FTT] ", "spawned {olive}Insta-%s™{default} on {olive}%s", arg2, target_name);
	}
	return Plugin_Handled;
}


Action Command_WitchAttack(int client, int args) {
	if(!g_actionsAvailable) {
		ReplyToCommand(client, "Unavailable: Missing \"actions\"");
		return Plugin_Handled;
	} else if(args < 1) {
		ReplyToCommand(client, "Usage: sm_witch_attack <user> [# of witches or 0 for all]");
	} else{
		char arg1[32];
		GetCmdArg(1, arg1, sizeof(arg1));
		char target_name[MAX_TARGET_LENGTH];
		int target_list[1], target_count;
		bool tn_is_ml;
		if ((target_count = ProcessTargetString(
				arg1,
				client,
				target_list,
				1,
				COMMAND_FILTER_ALIVE, /* Only allow alive players */
				target_name,
				sizeof(target_name),
				tn_is_ml)) <= 0)
		{
			/* This function replies to the admin with a failure message */
			ReplyToTargetError(client, target_count);
			return Plugin_Handled;
		}

		int target = target_list[0];
		if(GetClientTeam(target) == 2) {
			GetCmdArg(2, arg1, sizeof(arg1));

			int maxCount = StringToInt(arg1);
			if(maxCount < 0) maxCount = 0;
			int count;

			int witch = INVALID_ENT_REFERENCE;
			while ((witch = FindEntityByClassname(witch, "witch")) != INVALID_ENT_REFERENCE) {
				if(SetWitchTarget(witch, target)) {
					++count;
				}
				if(maxCount > 0 && count >= maxCount) break;
			}
			ShowActivity(client, "set %d witches to target %s", count, target_name);
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
			COMMAND_FILTER_CONNECTED | COMMAND_FILTER_NO_IMMUNITY, /* Only allow alive players */
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
			}
			ResetClient(target_list[i], true);
		}
		ShowActivityEx(client, "[FTT] ", "reset troll effects for %s.",target_name);
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
			COMMAND_FILTER_NO_MULTI | COMMAND_FILTER_NO_IMMUNITY, 
			target_name,
			sizeof(target_name),
			tn_is_ml)) <= 0
		&& target_list[0] == 0) {
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
		} else if(args == 1) {
			SetupCategoryMenu(client, GetClientUserId(target_list[0]));
		}
		
		SilentMenuSelected[client] = false;
		SetupCategoryMenu(client, GetClientUserId(target_list[0]));
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
		ShowTrollCombosMenu(client, GetClientUserId(target_list[0]));
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
		SetupCategoryMenu(client, GetClientUserId(target_list[0]));
	}
	return Plugin_Handled;
}

public Action Command_ListModes(int client, int args) {
	for(int i = 0; i <= MAX_TROLLS; i++) {
		if(Trolls[i].hidden) continue;
		ReplyToCommand(client, "%d. %s - %s", i, Trolls[i].name, Trolls[i].description);
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
		
		char buffer[50];
		for(int p = 0; p < target_count; p++) {
			int target = target_list[p];
			CReplyToCommand(client, "> Active Trolls for {olive}%N:", target);

			if(IsFakeClient(target)) {
				int player = GetRealClient(target);
				if(player != -1) target = player;
			}
			
			for(int j = 1; j < MAX_TROLLS; j++) {
				Troll troll = Troll(j);
				if(troll.Hidden) continue;
				if(troll.IsActive(target)) {
					int flags = troll.GetFlags(target);
					if(flags > 0) {
						buffer[0] = '\0';
						troll.GetFlagNames(target, flags, buffer, sizeof(buffer));
						CReplyToCommand(client, "\t{green}%s:{default} %s", Trolls[troll.Id].name, buffer);
					} else
						CReplyToCommand(client, "\t{green}%s", Trolls[troll.Id].name);
				}
			}
		}
		return Plugin_Handled;
	}

	int count = 0;
	char[][] bufferList = new char[MAX_TROLLS+1][MAX_TROLL_NAME_LENGTH];
	char buffer[255];
	for(int player = 1; player <= MaxClients; player++) {
		if(IsClientConnected(player) && IsClientInGame(player) && GetClientTeam(player) > 1 && IsAnyTrollActive(player)) {
			if(IsFakeClient(player)) {
				int realPlayer = GetRealClient(player);
				if(realPlayer != -1) player = realPlayer;
			}
			int trollCount = 0;
			for(int j = 1; j < MAX_TROLLS; j++) {
				Troll troll = Troll(j);
				if(troll.IsActive(player)) {
					int flags = troll.GetFlags(player);
					if(flags > 0)
						Format(bufferList[trollCount], MAX_TROLL_NAME_LENGTH, "%s(%d)", Trolls[j].name,  flags);
					else
						strcopy(bufferList[trollCount], MAX_TROLL_NAME_LENGTH, Trolls[j].name);
					trollCount++;
				}
			}

			ImplodeStrings(bufferList, trollCount, ", ", buffer, sizeof(buffer));
			ReplyToCommand(client, "%N | %s", player, buffer);
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
			if(IsClientConnected(i) && IsClientInGame(i) && IsPlayerAlive(i)) {
				if(GetUserAdmin(i) == INVALID_ADMIN_ID) {
					Format(userid, sizeof(userid), "%d", GetClientUserId(i));
					GetClientName(i, display, sizeof(display));
					menu.AddItem(userid, display);
				} else {
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
		int target_list[1], target_count;
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
		if (GetClientTeam(target) == 2) {
			ToggleMarkPlayer(client, target);
		} else {
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

		int target_list[1], target_count;
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

public Action Command_Stagger(int client, int args) {
	if(args > 0) {
		static char arg1[32];
		GetCmdArg(1, arg1, sizeof(arg1));

		int target_list[MAXPLAYERS], target_count;
		static char target_name[MAX_TARGET_LENGTH];
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

		for(int i = 0; i < target_count; i++) {
			L4D_StaggerPlayer(target_list[i], target_list[i], NULL_VECTOR);
		}
	} else {
		ReplyToCommand(client, "syntax: sm_stagger <target player>");
	}
	return Plugin_Handled;
}

public Action Command_SmartCharge(int client, int args) {
	if(args > 0) {
		static char arg1[32], arg2[8];
		GetCmdArg(1, arg1, sizeof(arg1));
		GetCmdArg(2, arg2, sizeof(arg2));
		int timeout = StringToInt(arg2);
		if(timeout == 0) timeout = 15;

		int target_list[1], target_count;
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
		
		if(pdata[target_list[0]].smartChargeActivator > 0) {
			ReplyToCommand(client, "Target already has auto smart charge enabled");
		} else {
			pdata[target_list[0]].smartChargeAttempts = 0;
			pdata[target_list[0]].smartChargeMaxAttempts = timeout;
			pdata[target_list[0]].smartChargeActivator = GetClientUserId(client);
			CreateTimer(1.0, Timer_CheckForChargerOpportunity, GetClientUserId(target_list[0]), TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
			ShowActivity(client, "Enabling smart auto-charge on %N for %d seconds", target_list[0], timeout);
		}
	} else {
		ReplyToCommand(client, "syntax: sm_smartcharge <target player> [timeout or default 10s]");
	}
	return Plugin_Handled;
}

Action Command_HealTarget(int client, int args) {
	if(args > 0) {
		char arg1[32], arg2[4];
		GetCmdArg(1, arg1, sizeof(arg1));
		GetCmdArg(2, arg2, sizeof(arg2));
		int target_list[1], target_count;
		static char target_name[MAX_TARGET_LENGTH];
		bool tn_is_ml;
		if ((target_count = ProcessTargetString(
			arg1,
			client,
			target_list,
			1,
			COMMAND_FILTER_ALIVE | COMMAND_FILTER_NO_MULTI | COMMAND_FILTER_NO_IMMUNITY,
			target_name,
			sizeof(target_name),
			tn_is_ml)) <= 0
		) {
			/* This function replies to the admin with a failure message */
			ReplyToTargetError(client, target_count);
			return Plugin_Handled;
		}

		int target = target_list[0];
		int targetUserId = GetClientUserId(target);
		if(targetUserId == healTargetPlayer) {
			ShowActivity(client, "cleared bots healing for %N", target);
			StopHealingBots();
		} else {
			healTargetPlayer = targetUserId;
			CreateTimer(2.0, Timer_UpdateHealTargetPos, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);

			int limit = StringToInt(arg2);
			bool addBots = limit < 0;
			if(limit < 0) limit = -limit;
			else if(limit == 0) limit = MaxClients;
			for(int i = 1; i <= MaxClients; i++) {
				if(IsClientConnected(i) && IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == 2 && IsFakeClient(i)) {
					int kit = GetPlayerWeaponSlot(i, 3);
					if(kit > 0) {
						GetEntityClassname(kit, arg1, sizeof(arg1));
						if(StrEqual(arg1, "weapon_first_aid_kit")) {
							pdata[i].flags |= view_as<int>(Flag_IsTargettingHealer);

							if(--limit == 0) {
								break;
							}
						}
					}
				}
			}
			if(addBots && limit > 0) {
				wasAbmAutoHard = hAbmAutoHard.IntValue;
				hAbmAutoHard.IntValue = 0;
				CreateTimer(0.2, Timer_SpawnHealBots, limit, TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT);
			}
			ShowActivity(client, "made all bots heal %N", target);
			wasSbFixEnabled = hSbFixEnabled.BoolValue;
			hSbFixEnabled.BoolValue = false;
		}
	} else {
		ReplyToCommand(client, "Usage: /healbots <player> [# of bots or 0 for all]");
	}
	return Plugin_Handled;
}
Action Command_SetReverseFF(int client, int args) {
	if(args < 2) {
		ReplyToCommand(client, "Usage: sm_rff <target> <amount> [fire/explosion]*");
		return Plugin_Handled;
	}
	char arg[32];
	GetCmdArg(1, arg, sizeof(arg));
	int target = GetSinglePlayer(client, arg, COMMAND_FILTER_NO_BOTS);
	if(target <= 0) {
		return Plugin_Handled;
	}
	GetCmdArg(1, arg, sizeof(arg));
	GetCmdArg(2, arg, sizeof(arg));
	int flag = -1;
	if(StrEqual(arg, "0") || StrEqual(arg, "0.0")) {
		flag = 8;
	} else if(StrEqual(arg, "2")) {
		flag = 2;
	} else if(StrEqual(arg, "0.5") || StrEqual(arg, ".5")) {
		flag = 4;
	} else if(StrEqual(arg, "3")) {
		flag = 8;
	} else if(StrEqual(arg, "1")) {
		flag = 1;
	} else {
		ReplyToCommand(client, "Unsupported amount. Possible values: 0.5, 1, 2, 3");
		return Plugin_Handled;
	}
	// args are 1-indexed so <=
	for(int i = 3; i <= args; i++) {
		GetCmdArg(i, arg, sizeof(arg));
		if(arg[0] == 'f') { // [f]ire
			flag |= 32;
		} else if(arg[0] == 'e' || arg[0] == 'b') { //[]blast or [e]xplode
			flag |= 64;
		} else {
			ReplyToCommand(client, "Unknown arg: %s", arg);
		}

	}
	ApplyTroll(target, Troll.FromName("Reverse FF"), client, TrollMod_Constant, flag);
	return Plugin_Handled;
}

Action Command_SetMagnetShortcut(int client, int args) {
	if(args < 1) {
		ReplyToCommand(client, "Usage: sm_magnet <target>");
		return Plugin_Handled;
	}
	char arg[32];
	GetCmdArg(1, arg, sizeof(arg));
	int target = GetSinglePlayer(client, arg, COMMAND_FILTER_NO_BOTS);
	if(target <= 0) {
		return Plugin_Handled;
	}
	ShowTrollsForCategory(client, GetClientUserId(target), 0);
	return Plugin_Handled;
}
Action Command_CarSplat(int client, int args) {
	if(args < 1) {
		ReplyToCommand(client, "Usage: sm_carsplat <target> [top/front/back]");
		return Plugin_Handled;
	}
	char arg[32];
	GetCmdArg(1, arg, sizeof(arg));
	int target = GetSinglePlayer(client, arg, COMMAND_FILTER_ALIVE);
	if(target <= 0) {
		return Plugin_Handled;
	}
	if(args == 2) {
		GetCmdArg(2, arg, sizeof(arg));
		float speed = 450.0;
		if(args == 3) {
			GetCmdArg(3, arg, sizeof(arg));
			speed = StringToFloat(arg);
			if(speed <= 0.0) speed = 450.0;
		}
		if(StrEqual(arg, "top")) {
			SpawnCarOnPlayer(target);
		} else if(StrEqual(arg, "front")) {
			SpawnCarToPlayer(target, speed);
		} else if(StrEqual(arg, "back")) {
			SpawnCarToPlayer(target, -speed);
		} else {
			ReplyToCommand(client, "Invalid direction: top/front/back or blank for menu");
			return Plugin_Handled;
		}
		LogAction(client, target, "spawned car on/in %s of \"%L\"", arg, target);
		ShowActivity(client, "spawned car (%s) of %N", arg, target);
	} else {
		Troll troll = Troll.FromName("Car Splat");
		ShowSelectFlagMenu(client, GetClientUserId(target), view_as<int>(TrollMod_Instant), troll);
	}
	return Plugin_Handled;
}

Action Command_AddTypo(int client, int args) {
	if(args == 2) {
		char src[32], replacement[32];
		GetCmdArg(1, src, sizeof(src));
		GetCmdArg(2, replacement, sizeof(replacement));
		AddTypo(src, replacement, true);
		ShowActivity(client, "added typo \"%s\" -> \"%s\"", src, replacement);
	} else {
		ReplyToCommand(client, "Syntax: /typo <source> <typo>");
	}
	return Plugin_Handled;
}