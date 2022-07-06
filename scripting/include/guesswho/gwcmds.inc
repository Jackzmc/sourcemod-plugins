#define GAMEMODE_PROP_NAME "gwprop"
#define GAMEMODE_BLOCKER_NAME "gwblocker"



public Action Command_GuessWho(int client, int args) {
	if(!isEnabled) ReplyToCommand(client, "Warn: Guess Who is not active");
	if(args > 0) {
		char subcmd[32];
		GetCmdArg(1, subcmd, sizeof(subcmd));
		if(StrEqual(subcmd, "points")) {
			GetCmdArg(2, subcmd, sizeof(subcmd));
			if(StrEqual(subcmd, "clear")) {
				movePoints.Clear();
				ReplyToCommand(client, "Movement locations have been cleared");
			} else if(StrEqual(subcmd, "save")) {
				if(args == 3) {
					GetCmdArg(2, subcmd, sizeof(subcmd));
				} else {
					subcmd = currentSet;
				}
				if(SaveMapData(currentMap, subcmd)) {
					ReplyToCommand(client, "Saved movement data for %s/%s", currentMap, subcmd);
				} else {
					ReplyToCommand(client, "Failed to save map data");
				}
			} else if(StrEqual(subcmd, "load")) {
				if(LoadMapData(currentMap, currentSet)) {
					ReplyToCommand(client, "Loaded movement data for %s/%s", currentMap, currentSet);
				} else {
					ReplyToCommand(client, "Failed to load map data");
				}
			} else if(StrEqual(subcmd, "record")) {
				float recordInterval = 0.5;
				if(args == 3) {
					GetCmdArg(3, subcmd, sizeof(subcmd));
					recordInterval = StringToFloat(subcmd);
					if(recordInterval <= 0.0) {
						ReplyToCommand(client, "Invalid record interval (%f)", recordInterval);
						return Plugin_Handled;
					}
				}

				if(recordTimer != null) {
					ReplyToCommand(client, "Stopped recording. %d ready to save. \"/guesswho points save\" to save", movePoints.Length);
					delete recordTimer;
				} else {
					// Assume recorder doesn't leav
					recordTimer = CreateTimer(recordInterval, Timer_RecordPoints, client, TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT);
					ReplyToCommand(client, "Recording movement points every %.2f seconds. Type command again to stop", recordInterval);
				}
			} else {
				ReplyToCommand(client, "Unknown option. Valid options: 'clear', 'save', 'load'");
			}
		} else if(StrEqual(subcmd, "r") || StrEqual(subcmd, "reload", false)) {
			GetCurrentMap(currentMap, sizeof(currentMap));
			char arg[4];
			GetCmdArg(2, arg, sizeof(arg));
			if(ReloadMapDB()) {
				if(!LoadConfigForMap(currentMap)) {
					ReplyToCommand(client, "Warn: Map has no config file");
				}
				Game.Cleanup(true);
				if(arg[0] == 'f') {
					InitGamemode();
				}
				SetupEntities(isNavBlockersEnabled, isPropsEnabled, isPortalsEnabled);
				ReplyToCommand(client, "Reloaded map from config");
			} else {
				ReplyToCommand(client, "Error occurred while reloading map file");
			}
		} else if(StrEqual(subcmd, "set", false)) {
			char set[16];
			if(args == 1) {
				ReplyToCommand(client, "Current Map Set: \"%s\" (Specify with /gw set <set>)", currentSet);
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
							ReplyToCommand(client, "Warn: No config entry for %s", currentMap);
						}
						if(!LoadMapData(currentMap, currentSet)) {
							ReplyToCommand(client, "Warn: No map data found for %s/%s", currentMap, currentSet);
						} else if(movePoints.Length == 0) {
							ReplyToCommand(client, "Warn: %s/%s has 0 saved movement locations", currentMap, currentSet);
						}
						Game.Cleanup();
						SetupEntities(isNavBlockersEnabled, isPropsEnabled, isPortalsEnabled);
						PrintToChatAll("[GuessWho] Map set has been changed to \"%s\"", currentSet);
						return Plugin_Handled;
					}
				}
				ReplyToCommand(client, "Warning: Set was not found, use /gw r to force load.");
			}
		} else if(StrEqual(subcmd, "toggle")) {
			char type[32];
			GetCmdArg(2, type, sizeof(type));
			bool doAll = StrEqual(type, "all");
			bool isUnknown = true;

			if(doAll || StrEqual(type, "blockers", false)) {
				if(isNavBlockersEnabled) {
					EntFire(GAMEMODE_BLOCKER_NAME, "Disable");
					ReplyToCommand(client, "Disabled all custom gamemode blockers");
				} else {
					EntFire(GAMEMODE_BLOCKER_NAME, "Enable");
					ReplyToCommand(client, "Enabled all custom gamemode blockers");
				}
				isNavBlockersEnabled = !isNavBlockersEnabled;
				isUnknown = false;
			} 
			if(doAll || StrEqual(type, "props", false)) {
				if(isPropsEnabled) {
					EntFire(GAMEMODE_PROP_NAME, "Disable");
					EntFire(GAMEMODE_PROP_NAME, "DisableCollision");
					ReplyToCommand(client, "Disabled all custom gamemode props");
				} else {
					EntFire(GAMEMODE_PROP_NAME, "Enable");
					EntFire(GAMEMODE_PROP_NAME, "EnableCollision");
					ReplyToCommand(client, "Enabled all custom gamemode props");
				}
				isPropsEnabled = !isPropsEnabled;
				isUnknown = false;
			}
			if(isUnknown) ReplyToCommand(client, "Specify the type to affect: 'blockers', 'props', 'portals', or 'all'");
		} else if(StrEqual(subcmd, "clear", false)) {
			static char arg[16];
			GetCmdArg(2, arg, sizeof(arg));
			if(StrEqual(arg, "all")) {
				Game.Cleanup();
				ReplyToCommand(client, "Cleaned up everything.");
			} else if(StrEqual(arg, "props")) {
				EntFire(GAMEMODE_PROP_NAME, "kill");
				ReplyToCommand(client, "Removed all custom gamemode props");
			} else if(StrEqual(arg, "blockers")) {
				EntFire(GAMEMODE_BLOCKER_NAME, "kill");
				ReplyToCommand(client, "Removed all custom gamemode blockers");
			} else ReplyToCommand(client, "Specify the type to affect: 'blockers', 'props', 'portals', or 'all'");
		} else if(StrEqual(subcmd, "settime")) {
			int prev = Game.MapTime;
			static char arg[16];
			GetCmdArg(2, arg, sizeof(arg));
			int time = StringToInt(arg);
			mapConfig.mapTime = time;
			Game.MapTime = time;
			ReplyToCommand(client, "Map's time is temporarily set to %d seconds (was %d)", time, prev);
		} else if(StrEqual(subcmd, "settick")) {
			static char arg[16];
			GetCmdArg(2, arg, sizeof(arg));
			int tick = -StringToInt(arg);
			Game.Tick = tick;
			ReplyToCommand(client, "Set tick time to %d", tick);
		} else if(StrContains(subcmd, "map") >= 0) {
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
				PrintToChatAll("[GuessWho] Switching map to %s", map);
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
		} else if(StrEqual(subcmd, "peekfix")) {
			if(!PeekCam.Exists()) {
				PeekCam.Target = client;
			}

			for(int i = 1; i <= MaxClients; i++) {
				if(IsClientConnected(i) && IsClientInGame(i)) {
					PeekCam.SetViewing(client, true);
					PeekCam.SetViewing(client, false);
				}
			}
			PeekCam.Destroy();
			ReplyToCommand(client, "Killing active camera");
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
				Game.ForceSetSeeker(target_list[0]);
				ReplyToCommand(client, "Set the current seeker to %N", target_list[0]);
			} else {
				ReplyToCommand(client, "The current seeker is: %N", Game.Seeker);
			}
		} else if(StrEqual(subcmd, "debug")) {
			ReplyToCommand(client, "- Game Info -");
			ReplyToCommand(client, "Current seeker: %N(%d)", Game.Seeker, Game.Seeker);
			ReplyToCommand(client, "State: %d | Tick: %d", view_as<int>(Game.State), Game.Tick);

			ReplyToCommand(client, "- Map Info -");
			ReplyToCommand(client, "Map: %s (set %s)", currentMap, currentSet);
			if(mapConfig.hasSpawnpoint)
				ReplyToCommand(client, "Has Spawnpoint: yes (%f %f %f)", mapConfig.spawnpoint[0], mapConfig.spawnpoint[1], mapConfig.spawnpoint[2]);
			else
				ReplyToCommand(client, "Has Spawnpoint: no (possibly map spawn %f %f %f)", mapConfig.spawnpoint[0], mapConfig.spawnpoint[1], mapConfig.spawnpoint[2]);
			ReplyToCommand(client, "Map Time: %d", mapConfig.mapTime);
			ReplyToCommand(client, "Flow Bounds: (%f, %f)", flowMin, flowMax);
		} else {
			ReplyToCommand(client, "Unknown option. Leave blank for help");
		}
		return Plugin_Handled;
	}
	ReplyToCommand(client, " === [ Guess Who Commands ] ===");
	if(GetUserAdmin(client) != INVALID_ADMIN_ID) {
		ReplyToCommand(client, "- Dev Commands -");
		ReplyToCommand(client, "points:");
		ReplyToCommand(client, "\tsave [set]: Save all movement data for map, and a optional set (defaults to current set)");
		ReplyToCommand(client, "\tload: Loads movement data for current map & set");
		ReplyToCommand(client, "\tclear: Removes all active movement data");
		ReplyToCommand(client, "r/reload [force]: Reloads map config from file");
		ReplyToCommand(client, "toggle <blockers/props/all>: Toggles all specified entities");
		ReplyToCommand(client, "clear <props/blockers/all>: Clear all specified");
		ReplyToCommand(client, "settime [seconds]: Sets the time override for the map");
		ReplyToCommand(client, "settick [tick]: Sets the current tick timer value");
		ReplyToCommand(client, "- Admin Commands -");
		ReplyToCommand(client, "set [new set]: Change the prop set or view current");
		ReplyToCommand(client, "setspawn: Sets the temporary spawnpoint for the map");
		ReplyToCommand(client, "peekfix - Clear peek camera from all players");
		ReplyToCommand(client, "seeker [new seeker]: Get the active seeker, or set a new one.");
		ReplyToCommand(client, "- User Commands -");
	}
	ReplyToCommand(client, "stuck: Teleports you to spawn to unstuck yourself");
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
	if(!isEnabled) return Plugin_Continue;
	static float tpLoc[3];
	FindSpawnPosition(tpLoc);
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
		CheatCommand(client, "give", "gnome");
	}
	return Plugin_Handled;
}
