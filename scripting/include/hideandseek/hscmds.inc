public Action Command_HideAndSeek(int client, int args) {
	if(args > 0) {
		char subcmd[16];
		GetCmdArg(1, subcmd, sizeof(subcmd));
		if(StrEqual(subcmd, "r") || StrEqual(subcmd, "reload", false)) {
			GetCurrentMap(currentMap, sizeof(currentMap));
			char arg[16];
			GetCmdArg(2, arg, sizeof(arg));
			if(ReloadMapDB()) {
				if(!LoadConfigForMap(currentMap)) {
					ReplyToCommand(client, "Warn: Map has no config file");
				}
				Cleanup();
				if(arg[0] == 'f') {
					CreateTimer(0.1, Timer_RoundStart);
				}
				SetupEntities(isNavBlockersEnabled, isPropsEnabled, isPortalsEnabled);
				ReplyToCommand(client, "Reloaded map from config");
			} else {
				ReplyToCommand(client, "Error occurred while reloading map file");
			}
		} else if(StrEqual(subcmd, "set", false)) {
			char set[16];
			if(args == 1) {
				ReplyToCommand(client, "Current Map Set: \"%s\" (Specify with /hs set <set>)", currentSet);
				if(validSets.Length == 0) ReplyToCommand(client, "Available Sets: (no map config found)");
				else { 
					ReplyToCommand(client, "Available Sets: ");
					for(int i = 0; i < validSets.Length; i++) {
						validSets.GetString(i, set, sizeof(set));
						ReplyToCommand(client, "%d.  %s", i + 1, set);
					}
				}
			} else {
				GetCmdArg(2, currentSet, sizeof(currentSet));
				for(int i = 0; i < validSets.Length; i++) {
					validSets.GetString(i, set, sizeof(set));
					if(StrEqual(set, currentSet)) {
						if(!LoadConfigForMap(currentMap)) {
							ReplyToCommand(client, "Warn: Map has no config file");
						}
						Cleanup();
						SetupEntities(isNavBlockersEnabled, isPropsEnabled, isPortalsEnabled);
						ReplyToCommand(client, "Set the current set to \"%s\"", currentSet);
						return Plugin_Handled;
					}
				}
				ReplyToCommand(client, "Warning: Set was not found, if this is an error use /hs r to load.");
			}
		} else if(StrEqual(subcmd, "toggle")) {
			char type[32];
			GetCmdArg(2, type, sizeof(type));
			bool doAll = StrEqual(type, "all");
			bool isUnknown = true;

			if(doAll || StrEqual(type, "blockers", false)) {
				if(isNavBlockersEnabled) {
					EntFire("hsblocker", "Disable");
					ReplyToCommand(client, "Disabled all custom gamemode blockers");
				} else {
					EntFire("hsblocker", "Enable");
					ReplyToCommand(client, "Enabled all custom gamemode blockers");
				}
				isNavBlockersEnabled = !isNavBlockersEnabled;
				isUnknown = false;
			} 
			if(doAll || StrEqual(type, "props", false)) {
				if(isPropsEnabled) {
					EntFire("hsprop", "Disable");
					EntFire("hsprop", "DisableCollision");
					ReplyToCommand(client, "Disabled all custom gamemode props");
				} else {
					EntFire("hsprop", "Enable");
					EntFire("hsprop", "EnableCollision");
					ReplyToCommand(client, "Enabled all custom gamemode props");
				}
				isPropsEnabled = !isPropsEnabled;
				isUnknown = false;
			}
			if(doAll || StrEqual(type, "portals", false)) {
				if(isPortalsEnabled) {
					EntFire("hsportal", "Disable");
					ReplyToCommand(client, "Disabled all custom gamemode portals");
				} else {
					EntFire("hsportal", "Enable");
					ReplyToCommand(client, "Enabled all custom gamemode portals");
				}
				isPortalsEnabled = !isPortalsEnabled;
				isUnknown = false;
			}
			if(isUnknown) ReplyToCommand(client, "Specify the type to affect: 'blockers', 'props', 'portals', or 'all'");
		} else if(StrEqual(subcmd, "clear", false)) {
			static char arg[16];
			GetCmdArg(2, arg, sizeof(arg));
			if(StrEqual(arg, "all")) {
				Cleanup();
				ReplyToCommand(client, "Cleaned up everything.");
			} else if(StrEqual(arg, "props")) {
				EntFire("hsprop", "kill");
				ReplyToCommand(client, "Removed all custom gamemode props");
			} else if(StrEqual(arg, "blockers")) {
				EntFire("hsblocker", "kill");
				ReplyToCommand(client, "Removed all custom gamemode blockers");
			} else if(StrEqual(arg, "portals")) {
				EntFire("hsportal", "kill");
				ReplyToCommand(client, "Removed all custom gamemode portals");
			} else ReplyToCommand(client, "Specify the type to affect: 'blockers', 'props', 'portals', or 'all'");
		} else if(StrEqual(subcmd, "settime")) {
			int prev = GetMapTime();
			static char arg[16];
			GetCmdArg(2, arg, sizeof(arg));
			int time = StringToInt(arg);
			mapConfig.mapTime = time;
			SetMapTime(time);
			ReplyToCommand(client, "Map's time is temporarily set to %d seconds (was %d)", time, prev);
		} else if(StrEqual(subcmd, "settick")) {
			static char arg[16];
			GetCmdArg(2, arg, sizeof(arg));
			int tick = -StringToInt(arg);
			SetTick(tick);
			ReplyToCommand(client, "Set tick time to %d", tick);
		} else if(StrEqual(subcmd, "map")) {
			static char arg[16];
			GetCmdArg(2, arg, sizeof(arg));
			if(StrEqual(arg, "list")) {
				ReplyToCommand(client, "See the console for available maps");
				char map[64];
				for(int i = 0; i < validMaps.Length; i++) {
					validMaps.GetString(i, map, sizeof(map));
					PrintToConsole(client, "%d. %s", i + 1, map);
				}
			} else if(StrEqual(arg, "random")) {
				bool foundMap;
				char map[64];
				do {
					int mapIndex = GetURandomInt() % validMaps.Length;
					validMaps.GetString(mapIndex, map, sizeof(map));
					if(!StrEqual(currentMap, map, false)) {
						foundMap = true;
					}
				} while(!foundMap);
				PrintToChatAll("[H&S] Switching map to %s", map);
				ChangeMap(map);
			} else if(StrEqual(arg, "next", false)) {
				if(args == 1) {
					ReplyToCommand(client, "Specify the map to change on the next round: 'next <map>'");
				} else {
					char arg2[64];
					GetCmdArg(3, arg2, sizeof(arg2));
					if(IsMapValid(arg2)) { 
						strcopy(nextRoundMap, sizeof(nextRoundMap), arg2);
						PrintToChatAll("[H&S] Switching map next round to %s", arg2);
						ForceChangeLevel(arg, "SetMapSelect");
					} else {
						ReplyToCommand(client, "Map is not valid");
					}
				}
			} else if(StrEqual(arg, "force", false)) {
				if(args == 1) {
					ReplyToCommand(client, "Specify the map to change to: 'force <map>'");
				} else {
					char arg2[64];
					GetCmdArg(3, arg2, sizeof(arg2));
					if(IsMapValid(arg2)) { 
						PrintToChatAll("[H&S] Switching map to %s", arg2);
						ChangeMap(arg2);
					} else {
						ReplyToCommand(client, "Map is not valid");
					}
				}
			} else {
				ReplyToCommand(client, "Syntax: 'map <list/random/force <mapname>/next <mapname>>");
			}
			return Plugin_Handled;
		} else if(StrEqual(subcmd, "pos", false)) {
			float pos[3];
			GetAbsOrigin(client, pos);
			ReplyToCommand(client, "\"origin\" \"%f %f %f\"", pos[0], pos[1], pos[2]);
			GetClientEyeAngles(client, pos);
			ReplyToCommand(client, "\"rotation\" \"%f %f %f\"", pos[0], pos[1], pos[2]);
		} else if(StrEqual(subcmd, "prop", false)) {
			float pos[3];
			GetAbsOrigin(client, pos);
			ReplyToCommand(client, "\"MYPROP\"");
			ReplyToCommand(client, "{");
			ReplyToCommand(client, "\t\"origin\" \"%f %f %f\"", pos[0], pos[1], pos[2]);
			GetClientAbsAngles(client, pos);
			ReplyToCommand(client, "\t\"rotation\" \"%f %f %f\"", pos[0], pos[1], pos[2]);
			ReplyToCommand(client, "\t\"type\" \"prop_dynamic\"");
			ReplyToCommand(client, "\t\"model\" \"props_junk/dumpster_2.mdl\"");
			ReplyToCommand(client, "}");
		} else if(StrEqual(subcmd, "setspawn", false)) {
			GetClientAbsOrigin(client, mapConfig.spawnpoint);
			ReplyToCommand(client, "Set map's temporarily spawnpoint to your location.");
		} else if(StrEqual(subcmd, "stuck")) {
			TeleportEntity(client, mapConfig.spawnpoint, NULL_VECTOR, NULL_VECTOR);
		} else if(StrEqual(subcmd, "bots")) {
			if(args == 2) {
				char arg[16];
				GetCmdArg(2, arg, sizeof(arg));
				if(StrEqual(arg, "toggle")) {
					bool newValue = !IsBotsEnabled();
					SetBotsEnabled(newValue);
					if(newValue) ReplyToCommand(client, "Bots are now enabled");
					else ReplyToCommand(client, "Bots are now disabled");
					return Plugin_Handled;
				} else if(StrEqual(arg, "on") || StrEqual(arg, "true")) {
					SetBotsEnabled(true);
					ReplyToCommand(client, "Bots are now enabled");
					return Plugin_Handled;
				} else if(StrEqual(arg, "off") || StrEqual(arg, "false")) {
					SetBotsEnabled(false);
					ReplyToCommand(client, "Bots are now disabled");
					return Plugin_Handled;
				}
			}
			if(IsBotsEnabled()) ReplyToCommand(client, "Bots are enabled");
			else ReplyToCommand(client, "Bots are disabled");
		} else if(StrEqual(subcmd, "peek")) {
			SetPeekCamTarget(client);
			SetPeekCamActive(client, !IsPeekCamActive(client));
		} else if(StrEqual(subcmd, "seeker")) {
			if(args == 2) {
				char arg1[32];
				GetCmdArg(2, arg1, sizeof(arg1));
				char target_name[MAX_TARGET_LENGTH];
				int target_list[1], target_count;
				bool tn_is_ml;
				if ((target_count = ProcessTargetString(
					arg1,
					client,
					target_list,
					1,
					0,
					target_name,
					sizeof(target_name),
					tn_is_ml)) <= 0
				|| target_list[0] == 0){
					/* This function replies to the admin with a failure message */
					ReplyToTargetError(client, target_count);
					return Plugin_Handled;
				}
			
				SetSlasher(target_list[0]);
				ReplyToCommand(client, "Set the current seeker to %N", target_list[0]);
			} else {
				ReplyToCommand(client, "The current seeker is: %N", GetSlasher());
			}
		} else if(StrEqual(subcmd, "debug")) {
			ReplyToCommand(client, "- Game Info -");
			int addSlasher = GetSlasher();
			ReplyToCommand(client, "Current seeker: %N(%d) (addon says %N(%d))", currentSeeker, currentSeeker, addSlasher, addSlasher);
			ReplyToCommand(client, "State: %d | Tick: %d", view_as<int>(GetState()), GetTick());

			ReplyToCommand(client, "- Map Info -");
			ReplyToCommand(client, "Map: %s (set %s)", currentMap, currentSet);
			if(mapConfig.hasSpawnpoint)
				ReplyToCommand(client, "Has Spawnpoint: yes (%f %f %f)", mapConfig.spawnpoint[0], mapConfig.spawnpoint[1], mapConfig.spawnpoint[2]);
			else
				ReplyToCommand(client, "Has Spawnpoint: no (possibly map spawn %f %f %f)", mapConfig.spawnpoint[0], mapConfig.spawnpoint[1], mapConfig.spawnpoint[2]);
			ReplyToCommand(client, "Climbing: %b", mapConfig.canClimb);
			ReplyToCommand(client, "Buttons Auto-press: %b", mapConfig.pressButtons);
			ReplyToCommand(client, "Map Time Override: %d", mapConfig.mapTime);
		}
		return Plugin_Handled;
	}
	ReplyToCommand(client, " - Hide & Seek Commands -");
	ReplyToCommand(client, "toggle <blockers/props/all>: Toggles all specified");
	ReplyToCommand(client, "set [new set]: Change the prop set or view current");
	ReplyToCommand(client, "clear <props/blockers/all>: Clear all specified");
	ReplyToCommand(client, "settime [seconds]: Sets the time override for the map");
	ReplyToCommand(client, "settick [tick]: Sets the current tick timer value");
	ReplyToCommand(client, "setspawn: Sets the temporary spawnpoint for the map");
	ReplyToCommand(client, "stuck: Teleports you to spawn to unstuck yourself");
	ReplyToCommand(client, "bots [toggle, [value]]: View if bots are enabled, or turn them on");
	ReplyToCommand(client, "seeker [new seeker]: Get the active seeker, or set a new one.");
	ReplyToCommand(client, "peek - debug cmd");
	return Plugin_Handled;
}

public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs) {
	if(isEnabled) {
		if(!StrEqual(command, "say")) { //Is team message
			if(currentSeeker <= 0 || currentSeeker == client) {
				return Plugin_Continue;
			}
			for(int i = 1; i <= MaxClients; i++) {
				if(IsClientConnected(i) && IsClientInGame(i) && i != currentSeeker)
					PrintToChat(i, "[Hiders] %N: %s", client, sArgs);
			}
			return Plugin_Handled;
		}
	}
	return Plugin_Continue;
}


public Action Command_Join(int client, int args) {
	static float tpLoc[3];
	GetSpawnPosition(tpLoc);
	if(args == 1) {
		static char arg1[32];
		GetCmdArg(1, arg1, sizeof(arg1));
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
				tn_is_ml)) <= 0)
		{
			/* This function replies to the admin with a failure message */
			ReplyToTargetError(client, target_count);
			return Plugin_Handled;
		}
		for (int i = 0; i < target_count; i++) {
			int target = target_list[i];
			if(GetClientTeam(target) != 2) {
				ChangeClientTeam(target, 2);
				L4D_RespawnPlayer(target);
				TeleportEntity(target, tpLoc, NULL_VECTOR, NULL_VECTOR);
				isPendingPlay[client] = false;
				CheatCommand(target, "give", "knife");
			}
		}
		ReplyToCommand(client, "Joined %s", target_name);
	} else {
		if(currentSeeker == client) {
			ReplyToCommand(client, "You are already in-game as a seeker.");
			return Plugin_Handled;
		}
		isPendingPlay[client] = false;
		ChangeClientTeam(client, 2);
		L4D_RespawnPlayer(client);
		TeleportEntity(client, tpLoc, NULL_VECTOR, NULL_VECTOR);
		CheatCommand(client, "give", "knife");
	}
	return Plugin_Handled;
}
