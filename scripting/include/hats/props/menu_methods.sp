/////////////
// METHODS
/////////////
void ShowSpawnRoot(int client) {
	Menu menu = new Menu(Spawn_RootHandler);
	menu.SetTitle("Choose list:");
	menu.AddItem("f", "Favorites (WIP)");
	menu.AddItem("r", "Recents");
	menu.AddItem("s", "Search");
	menu.AddItem("n", "Prop List");
	menu.ExitBackButton = true;
	menu.ExitButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}
void Spawn_ShowRecents(int client) {
	if(g_recentItems == null) LoadRecents();
	ArrayList items = GetRecentsItemList();
	if(items.Length == 0) {
		CReplyToCommand(client, "\x04[Editor] \x01No recent props spawned.");
		return;
	}
	ShowTempItemMenu(client, items, "Recents");
}
void Spawn_ShowSearch(int client) {
	g_PropData[client].chatPrompt = Prompt_Search;
	CReplyToCommand(client, "\x04[Editor] \x01Please enter search query in chat:");
}
void ShowDeleteList(int client, int index = -3) {
	Menu menu = new Menu(DeleteHandler);
	menu.SetTitle("Delete Props");

	menu.AddItem("-1", "Delete All");
	menu.AddItem("-2", "Delete All (Mine Only)");
	menu.AddItem("-3", "Delete Tool");
	// menu.AddItem("-4", "Delete Last Save");
	char info[8];
	char buffer[128];
	for(int i = 0; i < g_spawnedItems.Length; i++) {
		int ref = GetSpawnedItem(i);
		if(ref == -1) continue;
		IntToString(i, info, sizeof(info));
		GetEntPropString(ref, Prop_Data, "m_ModelName", buffer, sizeof(buffer));
		index = FindCharInString(buffer, '/', true);
		if(index != -1)
			menu.AddItem(info, buffer[index + 1]);
	}

	menu.ExitBackButton = true;
	menu.ExitButton = true;
	// Add +3 to the index for the 3 "Delete ..." buttons
	// TODO: restore the delete index issue, use /7*7
	menu.DisplayAt(client, 0, MENU_TIME_FOREVER);
}
void ShowEditList(int client, int index = 0) {
	Menu menu = new Menu(EditHandler);
	menu.SetTitle("Edit Prop");

	char info[8];
	char buffer[32];
	for(int i = 0; i < g_spawnedItems.Length; i++) {
		int ref = GetSpawnedItem(i);
		if(ref == -1) continue;
		IntToString(i, info, sizeof(info));
		GetEntPropString(ref, Prop_Data, "m_ModelName", buffer, sizeof(buffer));
		index = FindCharInString(buffer, '/', true);
		if(index != -1)
			menu.AddItem(info, buffer[index + 1]);
	}

	menu.ExitBackButton = true;
	menu.ExitButton = true;
	// Add +2 to the index for the two "Delete ..." buttons
	menu.DisplayAt(client, index, MENU_TIME_FOREVER);
}
void ShowCategoryList(int client, CategoryData category) {
	LoadCategories();
	char info[4];
	// No category list provided, use the global one.
	g_PropData[client].PushCategory(category);
	Menu menu = new Menu(SpawnCategoryHandler);
	char title[32];
	g_PropData[client].GetCategoryTitle(title, sizeof(title));
	menu.SetTitle(title);
	CategoryData cat;
	for(int i = 0; i < category.items.Length; i++) {
		category.items.GetArray(i, cat);
		Format(info, sizeof(info), "%d", i);
		if(cat.hasItems)
			menu.AddItem(info, cat.name);
		else {
			Format(title, sizeof(title), "[%s]", cat.name);
			menu.AddItem(info, title);
		}
	}
	menu.ExitBackButton = true;
	menu.ExitButton = true;
	// Round to page instead of index (int division)
	int index =  g_PropData[client].lastCategoryIndex / 7 * 7;
	menu.DisplayAt(client, index, MENU_TIME_FOREVER);
}
void _showItemMenu(int client, ArrayList items, const char[] title = "", bool clearArray = false, const char[] classnameOverride = "") {
	if(items == null) {
		// Use previous list buffer
		items = g_PropData[client].itemBuffer;
		if(items == null) {
			LogError("Previous list does not exist and no new list was provided ShowItemMenu(%N)", client);
		}
	} else {
		// Populate the buffer with this list
		g_PropData[client].SetItemBuffer(items, clearArray);
		// Reset the index, so we start on the first item
		g_PropData[client].lastItemIndex = 0;
		strcopy(g_PropData[client].classnameOverride, 32, classnameOverride);
	}
	if(items.Length == 0) {
		PrintToChat(client, "\x04[Editor]\x01 No items to show.");
		return;
	}
	Menu itemMenu = new Menu(SpawnItemHandler);
	if(title[0] != '\0')
		itemMenu.SetTitle(title);
	ItemData item;
	char info[8+128+64]; //i[8] + item.model[128] + item.name[64]
	for(int i = 0; i < items.Length; i++) {
		items.GetArray(i, item);
		// Sadly need to duplicate item.name, for recents to work
		Format(info, sizeof(info), "%d|%s|%s", i, item.model, item.name);
		itemMenu.AddItem(info, item.name);
	}
	itemMenu.ExitBackButton = true;
	itemMenu.ExitButton = true;
	// We don't want to start at the index but the page of the index
	int index = (g_PropData[client].lastItemIndex / 7) * 7;
	itemMenu.DisplayAt(client, index, MENU_TIME_FOREVER);
}
/**
 * Show a list of a category's items to spawn to the client
 *
 * @param client               client to show menu to
 * @param category 			   the category to show items of
 */
void ShowCategoryItemMenu(int client, CategoryData category) {
	char title[32];
	g_PropData[client].GetCategoryTitle(title, sizeof(title));
	Format(title, sizeof(title), "%s>%s", title, category.name);
	_showItemMenu(client, category.items, title, false, category.classnameOverride);
}
/**
 * Show a list of items to spawn to the client
 *
 * @param client               client to show menu to
 * @param items                A list of ItemData. Optional, null to reuse last list
 * @param title                An optional title to show
 * @param clearArray           Should the items array be destroyed when menu is closed?
 * @param classnameOverride    Override the classname to spawn as
 */
void ShowItemMenu(int client, ArrayList items = null, const char[] title = "", const char[] classnameOverride = "") {
	_showItemMenu(client, items, title, false, classnameOverride);
}
/**
 * Show a list of items, deleting the arraylist on completion
 * @param client               client to show menu to
 * @param items                A list of ItemData
 * @param title                An optional title to show
 * @param classnameOverride    Override the classname to spawn as
 */
void ShowTempItemMenu(int client, ArrayList items, const char[] title = "", const char[] classnameOverride = "") {
	if(items == null) {
		LogError("ShowTempItemMenu: Given null item list");
	}
	_showItemMenu(client, items, title, true, classnameOverride);
}

void Spawn_ShowFavorites(int client) {
	if(g_db == null) {
		PrintToChat(client, "\x04[Editor]\x01 Cannot connect to database.");
		return;
	}
	PrintCenterText(client, "Loading favorites...\nPlease wait");
	char query[256];
	GetClientAuthId(client, AuthId_Steam2, query, sizeof(query));
	g_db.Format(query, sizeof(query), "SELECT model, name FROM editor_favorites WHERE steamid = '%s' ORDER BY position DESC", query);
	g_db.Query(DB_GetFavoritesCallback, query, GetClientUserId(client));
}

void Spawn_ShowSaveLoadMainMenu(int client) {
	Menu menu = new Menu(SaveLoadMainMenuHandler);
	menu.SetTitle("Save / Load");
	// Id is SaveType
	menu.AddItem("1", "Map Scenes");
	menu.AddItem("2", "Schematics");
	menu.ExitBackButton = true;
	menu.ExitButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

void ShowSaves(int client, SaveType type) {
	ArrayList saves;
	Menu newMenu;
	if(type == Save_Scene) {
		newMenu = new Menu(SaveLoadSceneHandler);
		newMenu.SetTitle("Save & Load > Map Scenes");
		newMenu.AddItem("", "[Save New Scene]");
		saves = LoadScenes();
	} else if(type == Save_Schematic) {
		newMenu = new Menu(SaveLoadSchematicHandler);
		newMenu.SetTitle("Save & Load > Schematics");
		if(g_PropData[client].pendingSaveType == Save_Schematic) {
			newMenu.AddItem("", "[Save Schematic]");
		} else {
			newMenu.AddItem("", "[Start New Schematic]");
			// Don't load saves when in middle of creating schematic
			saves = LoadSchematics();
		}
	}
	if(saves != null) {
		char name[64];
		for(int i = 0; i < saves.Length; i++) {
			saves.GetString(i, name, sizeof(name));
			newMenu.AddItem(name, name);
		}
		delete saves;
	}
	newMenu.ExitBackButton = true;
	newMenu.ExitButton = true;
	newMenu.Display(client, MENU_TIME_FOREVER);
}