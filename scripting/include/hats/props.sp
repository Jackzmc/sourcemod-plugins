TopMenuObject g_propSpawnerCategory;
public void OnAdminMenuReady(Handle topMenuHandle) {
	TopMenu topMenu = TopMenu.FromHandle(topMenuHandle);
	if(topMenu != g_topMenu) { 
		g_propSpawnerCategory = topMenu.AddCategory("hats_editor", Category_Handler);
		if(g_propSpawnerCategory != INVALID_TOPMENUOBJECT) {
			topMenu.AddItem("editor_spawn", AdminMenu_Spawn, g_propSpawnerCategory, "sm_prop");
			topMenu.AddItem("editor_edit", AdminMenu_Edit, g_propSpawnerCategory, "sm_prop");
			topMenu.AddItem("editor_delete", AdminMenu_Delete, g_propSpawnerCategory, "sm_prop");
			topMenu.AddItem("editor_saveload", AdminMenu_SaveLoad, g_propSpawnerCategory, "sm_prop");
		}
	}
	g_topMenu = topMenu;
}


enum struct CategoryData {
	char name[64];
	bool hasItems;
	ArrayList items;
}
enum struct ItemData {
	char model[128];
	char name[64];
}
enum struct SaveData {
	char model[128];
	buildType type;
	float origin[3];
	float angles[3];
	int color[4];

	void FromEntity(int entity) {
		// Use this.model as a buffer:
		GetEntityClassname(entity, this.model, sizeof(this.model));
		if(StrEqual(this.model, "prop_physics")) this.type = Build_Physics;
		else if(StrEqual(this.model, "prop_dynamic")) {
			if(GetEntProp(entity, Prop_Send, "m_nSolidType") == 0) {
				this.type = Build_NonSolid;
			} else {
				this.type = Build_Solid;
			}
		}
		
		GetEntPropString(entity, Prop_Data, "m_ModelName", this.model, sizeof(this.model));
		GetEntPropVector(entity, Prop_Send, "m_vecOrigin", this.origin);
		GetEntPropVector(entity, Prop_Send, "m_angRotation", this.angles);
		GetEntityRenderColor(entity, this.color[0],this.color[1],this.color[2],this.color[3]);
	}

	void Serialize(char[] output, int maxlen) {
		Format(
			output, maxlen, "%s,%d,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%d,%d,%d,%d", 
			this.model, this.type, this.origin[0], this.origin[1], this.origin[2],
			this.angles[0], this.angles[1], this.angles[2],
			this.color[0], this.color[1], this.color[2], this.color[3]
		);
	}

	void Deserialize(const char[] output) {
		char buffer[32];
		int index = SplitString(output, ",", this.model, sizeof(this.model));
		index = SplitString(output[index], ",", buffer, sizeof(buffer));
		this.type = view_as<buildType>(StringToInt(buffer));
		for(int i = 0; i < 3; i++) {
			index = SplitString(output[index], ",", buffer, sizeof(buffer));
			this.origin[i] = StringToFloat(buffer);
		}
		for(int i = 0; i < 3; i++) {
			index = SplitString(output[index], ",", buffer, sizeof(buffer));
			this.angles[i] = StringToFloat(buffer);
		}
		for(int i = 0; i < 4; i++) {
			index = SplitString(output[index], ",", buffer, sizeof(buffer));
			this.color[i] = StringToInt(buffer);
		}
	}

}
ArrayList g_categories;
ArrayList g_spawnedItems;
ArrayList g_savedItems;

bool LoadSaves(ArrayList saves) {
	saves = new ArrayList(ByteCountToCells(64));
	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "data/prop_spawner/saves/%s", g_currentMap);
	FileType fileType;
	DirectoryListing listing = OpenDirectory(path);
	if(listing == null) return false;
	char buffer[64];
	while(listing.GetNext(buffer, sizeof(buffer), fileType)) {
		saves.PushString(buffer);
	}
	delete listing;
	return true;
}

public bool LoadSave(const char[] save) {
	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "data/prop_spawner/saves/%s/%s", g_currentMap, save);
	// ArrayList savedItems = new ArrayList(sizeof(SaveData));
	File file = OpenFile(path, "r");
	if(file == null) return false;
	char buffer[256];
	SaveData data;
	while(file.ReadLine(buffer, sizeof(buffer))) {
		data.Deserialize(buffer);
		int entity = -1;
		if(data.type == Build_Physics)
			entity = CreateEntityByName("prop_physics");
		else
			entity = CreateEntityByName("prop_dynamic");
		if(entity == -1) continue;
		PrecacheModel(data.model);
		DispatchKeyValue(entity, "model", data.model);
		DispatchKeyValue(entity, "targetname", "saved_prop");
		DispatchKeyValue(entity, "solid", data.type == Build_NonSolid ? "0" : "6");
		TeleportEntity(entity, data.origin, data.angles, NULL_VECTOR);
		if(!DispatchSpawn(entity)) continue;
		// TODO: Setrendertype?
		SetEntityRenderColor(entity, data.color[0], data.color[1], data.color[2], data.color[3]);
		// TODO: previews?
		// g_savedItems.PushArray(data);
	}
	delete file;
	// delete savedItems;
	return true;
}

bool CreateSave(const char[] name) {
	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "data/prop_spawner/saves/%s/%s.txt", g_currentMap, name);
	File file = OpenFile(name, "w");
	if(file == null) return false;
	char buffer[132];
	SaveData data;
	for(int i = 0; i < g_spawnedItems.Length; i++) {
		int ref = g_spawnedItems.Get(i);
		data.FromEntity(ref);
		data.Serialize(buffer, sizeof(buffer));
		file.WriteLine("%s", buffer);
	}
	file.Flush();
	delete file;
	return true;
}

void UnloadSave() {
	if(g_savedItems != null) {
		delete g_savedItems;
	}
}

public void LoadCategories() {
	if(g_categories != null) return;
	g_categories = new ArrayList(sizeof(CategoryData));
	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "data/prop_spawner/models");
	LoadFolder(g_categories, path);
}
public void UnloadCategories() {
	if(g_categories == null) return;
	_UnloadCategories(g_categories);
	delete g_categories;
}
void _UnloadCategories(ArrayList list) {
	CategoryData cat;
	for(int i = 0; i < list.Length; i++) {
		list.GetArray(i, cat);
		_UnloadCategory(cat);
	}
}
void _UnloadCategory(CategoryData cat) {
	// Is a sub-category:
	if(!cat.hasItems) {
		_UnloadCategories(cat.items);
	}
	delete cat.items;
}

void LoadFolder(ArrayList parent, const char[] rootPath) {
	char buffer[PLATFORM_MAX_PATH];
	FileType fileType;
	DirectoryListing listing = OpenDirectory(rootPath);
	if(listing == null) {
		LogError("Cannot open \"%s\"", rootPath);
	}
	while(listing.GetNext(buffer, sizeof(buffer), fileType)) {
		if(fileType == FileType_Directory) {
			// TODO: support subcategory
			if(buffer[0] == '.') continue;
			CategoryData data;
			Format(data.name, sizeof(data.name), "%s>>", buffer);
			data.items = new ArrayList();

			Format(buffer, sizeof(buffer), "%s/%s", rootPath, buffer);
			LoadFolder(data.items, buffer);
			parent.PushArray(data);
		} else if(fileType == FileType_File) {
			Format(buffer, sizeof(buffer), "%s/%s", rootPath, buffer);
			LoadProps(parent, buffer);
		}
	}
	delete listing;
}

void LoadProps(ArrayList parent, const char[] filePath) {
	File file = OpenFile(filePath, "r");
	if(file == null) {
		PrintToServer("[Props] Cannot open file \"%s\"", filePath);
		return;
	}
	CategoryData category;
	category.items = new ArrayList(sizeof(ItemData));
	category.hasItems = true;
	char buffer[128];
	if(!file.ReadLine(buffer, sizeof(buffer))) {
		delete file;
		return;
	}
	ReplaceString(buffer, sizeof(buffer), "\n", "");
	ReplaceString(buffer, sizeof(buffer), "\r", "");
	Format(category.name, sizeof(category.name), "%s>", buffer);
	while(file.ReadLine(buffer, sizeof(buffer))) {
		ItemData item;
		int index = SplitString(buffer, " ", item.model, sizeof(item.model));
		if(index == -1) {
			strcopy(item.name, sizeof(item.name), buffer);
		} else {
			strcopy(item.name, sizeof(item.name), buffer[index]);
		}
		category.items.PushArray(item);
	}
	parent.PushArray(category);
	delete file;
}
public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs) {
	if(!g_isSearchActive[client]) {
		return Plugin_Continue;
	}
	ArrayList results = SearchItems(sArgs);
	if(results.Length == 0) {
		CPrintToChat(client, "\x04[Editor]\x01 No results found. :(");
	} else {
		ShowItemMenuAny(client, results);
	}
	delete results;
	return Plugin_Handled;
}
#define MAX_SEARCH_RESULTS 30
ArrayList SearchItems(const char[] query) {
	// TODO: search
	ArrayList results = new ArrayList(sizeof(ItemData));
	_searchCategory(results, g_categories, query);
	return results;
}

void _searchCategory(ArrayList results, ArrayList categories, const char[] query) {
	CategoryData cat;
	for(int i = 0; i < categories.Length; i++) {
		categories.GetArray(i, cat);
		if(cat.hasItems) {
			_searchItems(results, cat.items, query);
		} else {
			_searchCategory(results, cat.items, query);
		}
		if(results.Length > MAX_SEARCH_RESULTS) return;
	}
}
void _searchItems(ArrayList results, ArrayList items, const char[] query) {
	ItemData item;
	for(int i = 0; i < items.Length; i++) {
		items.GetArray(i, item);
		if(StrContains(item.name, query, false)) {
			results.PushArray(item);
		}
		if(results.Length > MAX_SEARCH_RESULTS) return;
	}
}

void Category_Handler(TopMenu topmenu, TopMenuAction action, TopMenuObject topobj_id, int param, char[] buffer, int maxlength) {
	if(action == TopMenuAction_DisplayTitle) {
		Format(buffer, maxlength, "Select a task:");
	} else if(action == TopMenuAction_DisplayOption) {
		Format(buffer, maxlength, "Spawn Props (Beta)");
	}
}

void AdminMenu_Spawn(TopMenu topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength) {
	if(action == TopMenuAction_DisplayOption) {
		Format(buffer, maxlength, "Spawn Props");
	} else if(action == TopMenuAction_SelectOption) {
		if(!FindConVar("sm_cheats").BoolValue) {
			CReplyToCommand(param, "\x04[Editor] \x01Set \x05sm_cheats\x01 to \x051\x01 to use the prop spawner");
			return;
		}
		Menu menu = new Menu(Spawn_RootHandler);
		menu.SetTitle("Choose list:");
		menu.AddItem("f", "Favorites");
		menu.AddItem("r", "Recents");
		menu.AddItem("s", "Search");
		menu.AddItem("n", "Prop List");
		menu.ExitBackButton = true;
		menu.ExitButton = true;
		menu.Display(param, MENU_TIME_FOREVER);
	}
}

int Spawn_RootHandler(Menu menu, MenuAction action, int client, int param2) {
	if (action == MenuAction_Select) {
		char info[2];
		menu.GetItem(param2, info, sizeof(info));
		switch(info[0]) {
			case 'f': Spawn_ShowFavorites(client);
			case 'r': Spawn_ShowRecents(client);
			case 's': Spawn_ShowSearch(client);
			case 'n': ShowCategoryList(client);
		}
		// TODO: handle back (to top menu)
	} else if (action == MenuAction_End)	
		delete menu;
	return 0;
}
Spawn_ShowFavorites(int client) {
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
Spawn_ShowRecents(int client) {
	Menu menu = new Menu(SpawnItemHandler);
	menu.SetTitle("Recent Props:");
	char model[128];
	for(int i = 0; i <= g_spawnedItems.Length; i++) {
		int ref = g_spawnedItems.Get(i);
		if(IsValidEntity(ref)) {
			GetEntPropString(ref, Prop_Data, "m_ModelName", model, sizeof(model));
			menu.AddItem(model, model);
		}
	}
	menu.ExitBackButton = true;
	menu.ExitButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}
Spawn_ShowSearch(int client) {
	g_isSearchActive[client] = true;
	CReplyToCommand(client, "\x04[Editor] \x01Please enter search query in chat:");
}
void AdminMenu_Edit(TopMenu topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength) {
	if(action == TopMenuAction_DisplayOption) {
		Format(buffer, maxlength, "Edit Props");
	} else if(action == TopMenuAction_SelectOption) {
		ShowEditList(param);
	}
}
void ShowDeleteList(int client, int index) {
	Menu menu = new Menu(DeleteHandler);
	menu.SetTitle("Delete Props");

	menu.AddItem("-1", "Delete All");
	menu.AddItem("-2", "Delete All (Mine Only)");
	char info[8];
	char buffer[128];
	for(int i = 0; i < g_spawnedItems.Length; i++) {
		int ref = g_spawnedItems.Get(i);
		IntToString(i, info, sizeof(info));
		GetEntPropString(ref, Prop_Data, "m_ModelName", buffer, sizeof(buffer));
		index = FindCharInString(buffer, '/', true);
		if(index != -1)
			menu.AddItem(info, buffer[index + 1]);
	}

	menu.ExitBackButton = true;
	menu.ExitButton = true;
	// Add +2 to the index for the two "Delete ..." buttons
	menu.DisplayAt(client, index + 2, MENU_TIME_FOREVER);
}
void ShowEditList(int client, int index = 0) {
	Menu menu = new Menu(EditHandler);
	menu.SetTitle("Edit Prop");

	char info[8];
	char buffer[32];
	for(int i = 0; i < g_spawnedItems.Length; i++) {
		int ref = g_spawnedItems.Get(i);
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

void AdminMenu_Delete(TopMenu topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength) {
	if(action == TopMenuAction_DisplayOption) {
		Format(buffer, maxlength, "Delete Props");
	} else if(action == TopMenuAction_SelectOption) {
		ShowDeleteList(param, -2);
	}
}

void AdminMenu_SaveLoad(TopMenu topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength) {
	if(action == TopMenuAction_DisplayOption) {
		Format(buffer, maxlength, "Save / Load");
	} else if(action == TopMenuAction_SelectOption) {

		ArrayList saves;
		LoadSaves(saves);
		Menu menu = new Menu(SaveLoadHandler);
		menu.SetTitle("Save / Load");
		char name[64];
		menu.AddItem("", "[New Save]");
		for(int i = 0; i < saves.Length; i++) {
			saves.GetString(i, name, sizeof(name));
			menu.AddItem(name, name);
		}
		menu.ExitBackButton = true;
		menu.ExitButton = true;
		menu.Display(param, MENU_TIME_FOREVER);
		delete saves;
	}
}

void ShowCategoryList(int client) {
	LoadCategories();
	Menu menu = new Menu(SpawnCategoryHandler);
	menu.SetTitle("Choose a category");
	CategoryData cat;
	char info[4];
	for(int i = 0; i < g_categories.Length; i++) {
		g_categories.GetArray(i, cat);
		Format(info, sizeof(info), "%d", i);
		// TODO: add support for nested
		if(cat.hasItems)
			menu.AddItem(info, cat.name);
	}
	menu.ExitBackButton = true;
	menu.ExitButton = true;
	menu.DisplayAt(client, g_lastCategoryIndex[client], MENU_TIME_FOREVER);
}

int SpawnCategoryHandler(Menu menu, MenuAction action, int client, int param2) {
	if (action == MenuAction_Select) {
		char info[8];
		menu.GetItem(param2, info, sizeof(info));
		int index = StringToInt(info);
		if(index > 0) {
			ShowItemMenu(client, index);
		}
	} else if (action == MenuAction_End)	
		delete menu;
	return 0;
}

int SaveLoadHandler(Menu menu, MenuAction action, int client, int param2) {
	if (action == MenuAction_Select) {
		char saveName[64];
		menu.GetItem(param2, saveName, sizeof(saveName));
		if(saveName[0] == '\0') {
			// Save new
			FormatTime(saveName, sizeof(saveName), "%Y-%m-%d %X");
			if(CreateSave(saveName)) {
				PrintToChat(client, "\x04[Editor]\x01 Created save \x05%s.txt", saveName);
			} else {
				PrintToChat(client, "\x04[Editor]\x01 Error creating save file");
			}
		} else if(LoadSave(saveName)) {
			PrintToChat(client, "\x04[Editor]\x01 Loaded save \x05%s", saveName);
		} else {
			PrintToChat(client, "\x04[Editor]\x01 Error loading save file");
		}
	} else if (action == MenuAction_Cancel) {
		if(param2 == MenuCancel_ExitBack) {
			DisplayTopMenuCategory(g_topMenu, g_propSpawnerCategory, client);
		} 
	} else if (action == MenuAction_End)	
		delete menu;
	return 0;
}

int DeleteHandler(Menu menu, MenuAction action, int client, int param2) {
	if (action == MenuAction_Select) {
		char info[8];
		menu.GetItem(param2, info, sizeof(info));
		int index = StringToInt(info);
		if(index == -1) {
			// Delete all (everyone)
			int count = DeleteAll();
			PrintToChat(client, "\x04[Editor]\x01 Deleted \x05%d\x01 items", count);
			ShowDeleteList(client, index);
		} else if(index == -2) {
			// Delete all (mine only)
			int count = DeleteAll(client);
			PrintToChat(client, "\x04[Editor]\x01 Deleted \x05%d\x01 items", count);
			ShowDeleteList(client, index);
		} else {
			int ref = g_spawnedItems.Get(index);
			// TODO: add delete confirm
			if(IsValidEntity(ref)) {
				RemoveEntity(ref);
			}
			g_spawnedItems.Erase(index);
			if(index > 0) {
				index--;
			}
			ShowDeleteList(client, index);
		}
	} else if (action == MenuAction_Cancel) {
		if(param2 == MenuCancel_ExitBack) {
			DisplayTopMenuCategory(g_topMenu, g_propSpawnerCategory, client);
		} 
	} else if (action == MenuAction_End)	
		delete menu;
	return 0;
}

void 

int DeleteAll(int onlyPlayer = 0) {
	int userid = onlyPlayer > 0 ? GetClientUserId(onlyPlayer) : 0;
	int count;
	for(int i = 0; i < g_spawnedItems.Length; i++) {
		int ref = g_spawnedItems.Get(i);
		int spawnedBy = g_spawnedItems.Get(i, 1);
		// Skip if wishing to only delete certain items:
		if(onlyPlayer != 0 && spawnedBy != userid) continue;
		if(IsValidEntity(ref)) {
			RemoveEntity(ref);
		}
		g_spawnedItems.Erase(i);
		count++;
	}
	return count;
}

int EditHandler(Menu menu, MenuAction action, int client, int param2) {
	if (action == MenuAction_Select) {
		char info[8];
		menu.GetItem(param2, info, sizeof(info));
		int index = StringToInt(info);
		int ref = g_spawnedItems.Get(index);
		int entity = EntRefToEntIndex(ref);
		if(entity > 0) {
			WallBuilder[client].Import(entity, false);
			PrintToChat(client, "\x04[Editor]\x01 Editing entity \x05%d", entity);
		} else {
			PrintToChat(client, "\x04[Editor]\x01 Entity disappeared.");
			g_spawnedItems.Erase(index);
			index--;
		}
		ShowEditList(client, index);
	} else if (action == MenuAction_Cancel) {
		if(param2 == MenuCancel_ExitBack) {
			DisplayTopMenuCategory(g_topMenu, g_propSpawnerCategory, client);
		} 
	} else if (action == MenuAction_End)	
		delete menu;
	return 0;
}


void ShowItemMenuAny(int client, ArrayList items, const char[] title = "") {
	Menu itemMenu = new Menu(SpawnItemHandler);
	if(title[0] != '\0')
		itemMenu.SetTitle(title);
	ItemData item;
	char info[132];
	for(int i = 0; i < items.Length; i++) {
		items.GetArray(i, item);
		Format(info, sizeof(info), "%d|%s", i, item.model);
		itemMenu.AddItem(info, item.name);
	}
	itemMenu.ExitBackButton = true;
	itemMenu.ExitButton = true;
	itemMenu.DisplayAt(client, g_lastItemIndex[client], MENU_TIME_FOREVER);
}

void ShowItemMenu(int client, int index) {
	if(g_lastCategoryIndex[client] != index) {
		g_lastCategoryIndex[client] = index;
		g_lastItemIndex[client] = 0; //Reset
	}
	CategoryData category;
	g_categories.GetArray(index, category);
	ShowItemMenuAny(client, category.items, category.name);
}

int SpawnItemHandler(Menu menu, MenuAction action, int client, int param2) {
	if (action == MenuAction_Select) {
		char info[132];
		menu.GetItem(param2, info, sizeof(info));
		char index[4];
		int modelIndex = SplitString(info, "|", index, sizeof(index));
		g_lastItemIndex[client] = StringToInt(index);

		if(WallBuilder[client].PreviewModel(info[modelIndex])) {
			PrintToChat(client, "\x04[Editor]\x01 Spawning: \x04%s\x01", info[modelIndex+7]);
			ShowHint(client);
		} else {
			PrintToChat(client, "\x04[Editor]\x01 Error spawning model \x01(%s)");
		}
		
		ShowItemMenu(client, g_lastCategoryIndex[client]);
	} else if(action == MenuAction_Cancel) {
		if(param2 == MenuCancel_ExitBack) {
			ShowCategoryList(client);
		}	
	} else if (action == MenuAction_End) {
		delete menu;
	}
	return 0;
}

#define SHOW_HINT_MIN_DURATION 600 // 600 s (10min)
void ShowHint(int client) {
	int time = GetTime();
	if(time - g_lastShowedHint[client] < SHOW_HINT_MIN_DURATION) return;
	PrintToChat(client, "\x05R: \x01Change Mode");
	PrintToChat(client, "\x05Middle Click: \x01Cancel Placement  \x05Shift + Middle Click: \x01Place  \x05Ctrl + Middle Click: \x01Change Type");
	PrintToChat(client, "\x05E: \x01Rotate (hold, use mouse)  \x05Left Click: \x01Rotate Axis  \x05Right Click: \x01Snap Angle");

	g_lastShowedHint[client] = time;
}

Action Command_Props(int client, int args) {
	PrintToChat(client, "\x05Not implemented");
	return Plugin_Handled;
}