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

void Spawn_ShowFavorites(int client) {
	PrintToChat(client, "In development");
	return;
	// Menu menu = new Menu(SpawnItemHandler);
	// char model[128];
	// for(int i = 0; i <= g_spawnedItems.Length; i++) {
	// 	int ref = g_spawnedItems.Get(i);
	// 	if(IsValidEntity(ref)) {
	// 		GetEntPropString(ref, Prop_Data, "m_ModelName", model, sizeof(model));
	// 		menu.AddItem(model, model);
	// 	}
	// }
	// menu.ExitBackButton = true;
	// menu.ExitButton = true;
	// menu.Display(client, MENU_TIME_FOREVER);
}
void Spawn_ShowRecents(int client) {
	CReplyToCommand(client, "\x04[Editor] \x01Disabled due to crash issues :D");
	return;
	if(g_recentItems == null) LoadRecents();
	ArrayList items = GetRecentsItemList();
	if(items.Length == 0) {
		CReplyToCommand(client, "\x04[Editor] \x01No recent props spawned.");
		return;
	}
	ShowItemMenuAny(client, items, "Recents", true);
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
void ShowCategoryList(int client, ArrayList categoryList = null) {
	LoadCategories();
	Menu menu = new Menu(SpawnCategoryHandler);
	menu.SetTitle("Choose a category");
	CategoryData cat;
	char info[4];
	// No category list provided, use the global one.
	PrintToServer("ShowCategoryList (root = %b)", categoryList == null);
	if(categoryList == null) {
		categoryList = g_categories;
	}
	g_PropData[client].SetList(categoryList, false);
	for(int i = 0; i < categoryList.Length; i++) {
		categoryList.GetArray(i, cat);
		Format(info, sizeof(info), "%d", i);
		// TODO: maybe add > folder indicator
		menu.AddItem(info, cat.name);
	}
	menu.ExitBackButton = true;
	menu.ExitButton = true;
	// Round to page instead of index (int division)
	int index =  g_PropData[client].lastCategoryIndex / 7 * 7;
	menu.DisplayAt(client, index, MENU_TIME_FOREVER);
}
void ShowItemMenuAny(int client, ArrayList items, const char[] title = "", bool clearArray = false, const char[] classnameOverride = "") {
	if(items == null) {
		items = g_PropData[client].listBuffer;
		if(items == null) {
			LogError("Items is null and listBuffer is null as well");
		}
	} else {
		g_PropData[client].SetList(items, clearArray);
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
	char info[128+64+8];
	for(int i = 0; i < items.Length; i++) {
		items.GetArray(i, item);
		// Sadly need to duplicate item.name.
		Format(info, sizeof(info), "%d|%s|%s", i, item.model, item.name);
		itemMenu.AddItem(info, item.name);
	}
	itemMenu.ExitBackButton = true;
	itemMenu.ExitButton = true;
	// We don't want to start at the index but the page of the index
	int index = (g_PropData[client].lastItemIndex / 7) * 7;
	itemMenu.DisplayAt(client, index, MENU_TIME_FOREVER);
}

// Calls ShowItemMenuAny with the correct category automatically
bool ShowItemMenu(int client, int index) {
	if(g_PropData[client].lastCategoryIndex != index) {
		g_PropData[client].lastCategoryIndex = index;
		g_PropData[client].lastItemIndex = 0; //Reset
	}
	CategoryData category;
	// Use the list in the buffer
	g_PropData[client].listBuffer.GetArray(index, category);
	if(category.items == null) {
		LogError("Category %s has null items array (index=%d)", category.name, index);
	} else if(category.hasItems) {
		PrintToServer("Selected category has item entries, showing item menu");
		ShowItemMenuAny(client, category.items, category.name, false, category.classnameOverride);
	} else {
		PrintToServer("Selected category has nested categories, showing");
		// Has nested categories
		// Reset the category index for nested
		g_PropData[client].lastCategoryIndex = 0;
		g_PropData[client].SetList(category.items); 
		ShowCategoryList(client, g_PropData[client].listBuffer);
	}
	return true;
}