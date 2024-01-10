Action Command_Props(int client, int args) {
	char arg[32];
	GetCmdArg(1, arg, sizeof(arg));
	if(args == 0 || StrEqual(arg, "help")) {
		PrintToChat(client, "See console for available sub-commands");
		PrintToConsole(client, "help - this");
		PrintToConsole(client, "search <search query>");
		PrintToConsole(client, "edit <last/#index>");
		PrintToConsole(client, "del <last/#index/tool>");
		PrintToConsole(client, "add <cursor/tool>");
		PrintToConsole(client, "controls - list all the controls");
	} else if(StrEqual(arg, "search")) {
		if(args == 1) {
			PrintToChat(client, "\x04[Editor]\x01 Enter your search query:");
			g_PropData[client].isSearchActive = true;
		} else {
			char query[32];
			GetCmdArg(2, query, sizeof(query));
			DoSearch(client, query);
		}
	} else if(StrEqual(arg, "edit")) {
		char arg2[32];
		GetCmdArg(2, arg2, sizeof(arg2));
		int index;
		if(StrEqual(arg2, "last")) {
			// Get last one
			index = GetSpawnedIndex(client, -1);
		} else {
			index = StringToInt(arg2);
		}
		if(index >= 0 && index < g_spawnedItems.Length) {
			int entity = EntRefToEntIndex(g_spawnedItems.Get(index));
			Editor[client].Import(entity);
			PrintToChat(client, "\x04[Editor]\x01 Editing entity \x05%d", entity);
		} else {
			PrintToChat(client, "\x04[Editor]\x01 Invalid index, out of bounds. Enter a value between [0, %d]", g_spawnedItems.Length - 1);
		}
	} else if(StrEqual(arg, "del")) {
		char arg2[32];
		GetCmdArg(2, arg2, sizeof(arg2));
		int index;
		if(StrEqual(arg2, "last")) {
			// Get last one
			index = GetSpawnedIndex(client, -1);
		} else {
			index = StringToInt(arg2);
		}

		if(index >= 0 && index < g_spawnedItems.Length) {
			int entity = EntRefToEntIndex(g_spawnedItems.Get(index));
			if(entity > 0 && IsValidEntity(entity)) {
				RemoveEntity(entity);
			}
			g_spawnedItems.Erase(index);
			PrintToChat(client, "\x04[Editor]\x01 Deleted entity \x05%d", entity);
		} else {
			PrintToChat(client, "\x04[Editor]\x01 Invalid index, out of bounds. Enter a value between [0, %d]", g_spawnedItems.Length - 1);
		}
	}else {
		PrintToChat(client, "\x05Not implemented");
	}
	return Plugin_Handled;
}