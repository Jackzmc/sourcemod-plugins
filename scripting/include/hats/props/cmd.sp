Action Command_Props(int client, int args) {
	char arg[32];
	GetCmdArg(1, arg, sizeof(arg));
	if(args == 0 || StrEqual(arg, "help")) {
		PrintToChat(client, "See console for available sub-commands");
		PrintToConsole(client, "help - this");
		PrintToConsole(client, "list <classname/index/owner> - lists all props and their distances");
		PrintToConsole(client, "search <search query>");
		PrintToConsole(client, "edit <last/#index>");
		PrintToConsole(client, "del <last/#index/tool>");
		PrintToConsole(client, "add <cursor/tool>");
		PrintToConsole(client, "favorite - favorites active editor entity");
		PrintToConsole(client, "controls - list all the controls");
		PrintToConsole(client, "reload - reload prop list");
	} else if(StrEqual(arg, "list")) {
		char arg2[16];
		GetCmdArg(2, arg2, sizeof(arg2));
		bool isClassname = StrEqual(arg2, "classname");
		bool isIndex = StrEqual(arg2, "index");
		bool isOwner = StrEqual(arg2, "owner");
		if(args == 1 || isClassname || isIndex || isOwner) {
			PrintToChat(client, "\x04[Editor]\x01 Please specify: \x05classname, index, owner. ");
			return Plugin_Handled;
		}
		float pos[3], propPos[3], dist;
		GetAbsOrigin(client, pos);
		for(int i = 0; i < g_spawnedItems.Length; i++) {
			int ref = GetSpawnedItem(i);
			if(ref > -1) {
				GetEntPropVector(ref, Prop_Send, "m_vecOrigin", propPos);
				dist = GetVectorDistance(pos, propPos, false);
				if(isIndex) {
					int entity = EntRefToEntIndex(ref);
					PrintToConsole(client, "%d. ent #%d - %.0fu away", i, entity, dist);
				} else if(isClassname) {
					char classname[32];
					GetEntityClassname(ref, classname, sizeof(classname));
					PrintToConsole(client, "%d. %s - %.0fu away", i, classname, dist);
				} else if(isOwner) {
					int spawner = g_spawnedItems.Get(i, 1);
					int player = GetClientOfUserId(spawner);
					if(player > 0) {
						PrintToConsole(client, "%d. %N - %.0fu away", i, player, dist);
					} else {
						PrintToConsole(client, "%d. (disconnected) - %.0fu away", i, dist);
					}
				}
			}
		}
		PrintToChat(client, "\x04[Editor]\x01 Check console");
	} else if(StrEqual(arg, "search")) {
		if(args == 1) {
			PrintToChat(client, "\x04[Editor]\x01 Enter your search query:");
			g_PropData[client].chatPrompt = Prompt_Search;
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
	} else if(StrEqual(arg, "controls")) {
		PrintToChat(client, "View controls at https://admin.jackz.me/docs/props");
	} else if(StrEqual(arg, "favorite")) {
		if(g_db == null) {
			PrintToChat(client, "\x04[Editor]\x01 Cannot connect to database.");
		} else if(Editor[client].IsActive()) {
			char model[128];
			GetEntPropString(Editor[client].entity, Prop_Data, "m_ModelName", model, sizeof(model));
			ToggleFavorite(client, model, Editor[client].data);
		} else {
			PrintToChat(client, "\x04[Editor]\x01 Edit a prop to use this command.");
		}
	} else if(StrEqual(arg, "reload")) {
		PrintHintText(client, "Reloading categories...");
		UnloadCategories();
		LoadCategories();	
	} else {
		PrintToChat(client, "\x05Not implemented");
	}
	return Plugin_Handled;
}