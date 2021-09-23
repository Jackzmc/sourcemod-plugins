public Action Command_InstaSpecial(int client, int args) {
	if(args < 1) {
		Menu menu = new Menu(Insta_PlayerHandler);
		menu.SetTitle("Choose a player");
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
		int specialType = GetSpecialType(arg2);
		static float pos[3];
		if(specialType == -1) {
			ReplyToCommand(client, "Unknown special \"%s\"", arg2);
			return Plugin_Handled;
		}
		for (int i = 0; i < target_count; i++) {
			int target = target_list[i];
			if(GetClientTeam(target) == 2) {
				SpawnSpecialNear(target, specialType);
			}else{
				ReplyToTargetError(client, target_count);
			}
		}
		ShowActivity(client, "spawned Insta-%s™ near %s", arg2, target_name);
	}


	return Plugin_Handled;
}

public Action Command_InstaSpecialFace(int client, int args) {
	if(args < 1) {
		Menu menu = new Menu(Insta_PlayerHandler);
		menu.SetTitle("Choose a player");
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
		int specialType = GetSpecialType(arg2);
		static float pos[3];
		if(specialType == -1) {
			ReplyToCommand(client, "Unknown special \"%s\"", arg2);
			return Plugin_Handled;
		}
		for (int i = 0; i < target_count; i++) {
			int target = target_list[i];
			if(GetClientTeam(target) == 2) {
				SpawnSpecialInFace(target, specialType);
			}else{
				ReplyToTargetError(client, target_count);
			}
		}
		ShowActivity(client, "spawned Insta-%s™ on %s", arg2, target_name);
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

				ShowActivity(client, "all witches target %s", target_name);
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
		ShowActivity(client, "activated autopunish for crescendo activator %N",lastCrescendoUser);
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
			if(ActiveTrolls[target_list[i]] > 0) {
				ResetClient(target_list[i], true);
				ShowActivity(client, "reset troll effects on \"%N\". ", target_list[i]);
			}
		}
	}
	return Plugin_Handled;
}

public Action Command_ApplyUser(int client, int args) {
	if(args < 2) {
		Menu menu = new Menu(ChoosePlayerHandler);
		menu.SetTitle("Choose a player");
		for(int i = 1; i < MaxClients; i++) {
			if(IsClientConnected(i) && IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == 2) {
				static char userid[8], display[16];
				Format(userid, sizeof(userid), "%d", GetClientUserId(i));
				GetClientName(i, display, sizeof(display));
				menu.AddItem(userid, display);
			}
		}
		menu.ExitButton = true;
		menu.Display(client, 0);
	}else{
		char arg1[32], arg2[32], arg3[8];
		GetCmdArg(1, arg1, sizeof(arg1));
		GetCmdArg(2, arg2, sizeof(arg2));
		GetCmdArg(3, arg3, sizeof(arg3));

		bool silent = StrEqual(arg3, "silent") || StrEqual(arg3, "quiet") || StrEqual(arg3, "mute");
		static char name[MAX_TROLL_NAME_LENGTH];
		if(!GetTrollID(StringToInt(arg2), name)) {
			ReplyToCommand(client, "Not a valid mode. Must be greater than 0. Usage: sm_fta [player] [mode]. Use sm_ftr <player> to reset.");
		}else{
			char target_name[MAX_TARGET_LENGTH];
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
			) {
				/* This function replies to the admin with a failure message */
				ReplyToTargetError(client, target_count);
				return Plugin_Handled;
			}
			for (int i = 0; i < target_count; i++) {
				if(IsClientInGame(target_list[i]) && GetClientTeam(target_list[i]) == 2)
					ApplyTroll(target_list[i], name, client, TrollMod_Instant, silent);
			}
		}
	}
	return Plugin_Handled;
}

public Action Command_ListModes(int client, int args) {
	static char name[MAX_TROLL_NAME_LENGTH];
	static Troll troll;
	for(int i = 0; i <= MAX_TROLLS; i++) {
		GetTrollByKeyIndex(i, troll);
		ReplyToCommand(client, "%d. %s - %s", i, troll.name, troll.description);
	}
	return Plugin_Handled;
}

public Action Command_ListTheTrolls(int client, int args) {
	int count = 0;
	//TODO: Update
	char[][] modeListArr = new char[MAX_TROLLS+1][MAX_TROLL_NAME_LENGTH];
	static char modeList[255];
	for(int i = 1; i < MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && IsPlayerAlive(i) && ActiveTrolls[i] > 0) {
			int modeCount = 0;
			static char name[MAX_TROLL_NAME_LENGTH];
			for(int j = 1; j <= MAX_TROLLS; j++) {
				GetTrollID(j, name);
				if(IsTrollActive(i, name)) {
					strcopy(modeListArr[modeCount], MAX_TROLL_NAME_LENGTH, name);
					modeCount++;
				}
			}

			ImplodeStrings(modeListArr, modeCount, ", ", modeList, sizeof(modeList));
			ReplyToCommand(client, "%N | %s", i, modeList);
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
	ReplyToCommand(client, "sm_ftl - Lists all the active trolls on players");
	ReplyToCommand(client, "sm_ftm - Lists all available troll modes & descriptions");
	ReplyToCommand(client, "sm_ftr - Resets target users' of their trolls");
	ReplyToCommand(client, "sm_fta - Applies a troll mode on targets");
	ReplyToCommand(client, "sm_ftt - Opens this menu");
	ReplyToCommand(client, "sm_ftc - Will apply a punishment to last crescendo activator");
	ReplyToCommand(client, "sm_mark - Marks the user to be banned on disconnect, prevents their FF.");
	return Plugin_Handled;
}