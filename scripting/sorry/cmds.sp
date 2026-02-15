// sm_sorry
Action Command_Apologize(int client, int args) {
	if(args == 0) {
		SorryData sorry;
		if(PopSorry(client, sorry)) {
			int victim = sorry.GetVictim();
			if(victim > 0) {
				SendApology(client, victim, sorry.hurtType, sorry.eventId);
			} else if(StrEqual(sorry.eventId, "car_alarm")) {
				for(int i = 1; i <= MaxClients; i++) {
					if(IsClientInGame(i) && GetClientTeam(i) == 2 && !IsFakeClient(i) && IsPlayerAlive(i)) {
						SendApology(client, i, sorry.hurtType, sorry.eventId);
					}
				}
			} else {
				ReplyToCommand(client, "You have not caused physical or emotional damage to another player recently. You can always do /sorry <player> [optional reason]");
				return Plugin_Handled;
			}

			int remaining = GetSorrysCount(client);
			if(remaining > 0) {
				ReplyToCommand(client, "You have %d sorry(s) left.", remaining);
				return Plugin_Handled;
			}
		} else {
			ReplyToCommand(client, "You have not caused physical or emotional damage to another player recently. You can always do /sorry <player> [optional reason]");
		}
		return Plugin_Handled;
	} else if(!IsPlayerAlive(client)) {
		ReplyToCommand(client, "You are dead.");
		return Plugin_Handled;
	}

	char target_name[MAX_TARGET_LENGTH];
	GetCmdArg(1, target_name, sizeof(target_name));

	int target_list[MAXPLAYERS], target_count;
	bool tn_is_ml;
	if ((target_count = ProcessTargetString(
		target_name,
		client,
		target_list,
		MaxClients,
		COMMAND_FILTER_NO_IMMUNITY,
		target_name,
		sizeof(target_name),
		tn_is_ml)) <= 0
	) {
		ReplyToTargetError(client, target_count);
		return Plugin_Handled;
	}
	
	char reason[128];
	if(args >= 2) {
		char buffer[32];
		GetCmdArg(2, reason, sizeof(reason));
		// Add missing 'I' if not included:
		if(!StrEqual(reason, "i", false) && !StrEqual(reason, "that") && !StrEqual(reason, "for") && !StrEqual(reason, "you") && !StrEqual(reason, "my")) {
			buffer[0] = '\0';
			Format(reason, sizeof(reason), "I %s", reason);
		}
		for(int i = 3; i <= args; i++) {
			GetCmdArg(i, buffer, sizeof(buffer));
			Format(reason, sizeof(reason), "%s %s", reason, buffer);
		}
	} else {
		reason = "I shot you";
	}
	for(int i = 0; i < target_count; i++) {
		SendApology(client, target_list[i], reason);
	}
	return Plugin_Handled;
}

// sm_sorrymenu
Action Command_ApologizeMenu(int client, int args) {
	Menu menu = new Menu(ApologizePlayerHandler);
	char info[16], display[32];
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2) {
			Format(info, sizeof(info), "%d", GetClientUserId(i));
			GetMenuDisplayName(i, display, sizeof(display));
			menu.AddItem(info, display);
		}
	}
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 3) {
			Format(info, sizeof(info), "%d", GetClientUserId(i));
			GetMenuDisplayName(i, display, sizeof(display));
			menu.AddItem(info, display);
		}
	}
	menu.Display(client, 0);
	return Plugin_Handled;
}
//////////////////////
// DEBUG COMMANDS
//////////////////////


// sm_sorryh (if DEBUG_SORRY)
Action Command_Debug_SorryHandler(int client, int args) {
	if(args > 0) {
		int sorryId = GetCmdArgInt(1);
		char eventId[32];
		GetCmdArg(2, eventId, sizeof(eventId));
		int target = client;
		if(args >= 3) {
			char buffer[64];
			GetCmdArg(3, buffer, sizeof(buffer));
			target = GetSinglePlayer(client, buffer);
		}	
		if(sorryId > sorryBounds[1] || sorryId < sorryBounds[0]) {
			ReplyToCommand(client, "Out of bounds. Invalid ID");
			return Plugin_Handled;
		}
		HandleApologyResponse(client, target, eventId, view_as<sorryResponseValues>(sorryId));
	} else {
		ReplyToCommand(client, "Usage: sm_sorryh <sorry id> [event string] [target = self]");
	}
	return Plugin_Handled;
}


#if defined DEBUG_SORRY
Action Command_Debug_Store(int client, int args) {
	int player = client;
	if(args > 0) {
		char arg[32];
		GetCmdArg(1, arg, sizeof(arg));
		player = GetSinglePlayer(client, arg, COMMAND_FILTER_NO_BOTS);
		if(player <= 0) {
			ReplyToCommand(client, "Provide player");
			return Plugin_Handled;
		}
	}

	StringMapSnapshot snapshot = SorryStore[player].Snapshot();
	char key[64];
	char buffer[256];
	for(int i = 0; i < snapshot.Length; i++) {
		snapshot.GetKey(i, key, sizeof(key));
		any value;
		if(SorryStore[client].GetValue(key, value)) {
			ReplyToCommand(client, " %s: %d %f", key, value, value);
		} else if(SorryStore[client].GetString(key, buffer, sizeof(buffer))) {
			ReplyToCommand(client, " %s: %s", key, buffer);
		} else {
			ReplyToCommand(client, " %s: [ARRAY]", key);
		}
	}
	delete snapshot;
	return Plugin_Handled;
}

Action Command_Debug_List(int client, int args) {
	AnyMapSnapshot snapshot = g_sorryResponses2.Snapshot();
	SorryHandlerData data;
	char buffer[64];
	for(int i = 0; i < snapshot.Length; i++) {
		sorryResponseValues id = view_as<sorryResponseValues>(snapshot.GetKey(i));
		if(!g_sorryResponses2.GetArray(id, data, sizeof(data))) {
			ThrowError("array missing elem i=%d id=%d", i, id);
		}
		Format(buffer, sizeof(buffer), "  #%d. \"%d\"", i, id);
		if(data.OnPlayerRunCmd != null) {
			g_onPlayerRunCmdForwards.Push(data.OnPlayerRunCmd);
			Format(buffer, sizeof(buffer), "%s OnPlayerRunCmd", buffer);
		}
		if(data.OnClientSayCommand != null) {
			g_onClientSayCommandForwards.Push(data.OnClientSayCommand);
			Format(buffer, sizeof(buffer), "%s OnClientSayCommand", buffer);
		}
		ReplyToCommand(client, "%s", buffer);
	}
	delete snapshot;
	return Plugin_Handled;
}
#endif 

