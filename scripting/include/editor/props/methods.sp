
ArrayList LoadScenes() {
	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "data/prop_spawner/saves/%s", g_currentMap);
	FileType fileType;
	DirectoryListing listing = OpenDirectory(path);
	if(listing == null) return null;
	char buffer[64];
	ArrayList saves = new ArrayList(ByteCountToCells(64));
	while(listing.GetNext(buffer, sizeof(buffer), fileType)) {
		if(buffer[0] == '.') continue;
		saves.PushString(buffer);
	}
	delete listing;
	return saves;
}

ArrayList LoadSchematics() {
	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "data/prop_spawner/schematics");
	FileType fileType;
	DirectoryListing listing = OpenDirectory(path);
	if(listing == null) return null;
	char buffer[64];
	ArrayList saves = new ArrayList(ByteCountToCells(64));
	while(listing.GetNext(buffer, sizeof(buffer), fileType) && fileType == FileType_File) {
		if(buffer[0] == '.') continue;
		saves.PushString(buffer);
	}
	delete listing;
	return saves;
}

bool LoadScene(const char[] save, bool asPreview = false) {
	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "data/prop_spawner/saves/%s/%s", g_currentMap, save);
	// ArrayList savedItems = new ArrayList(sizeof(SaveData));
	File file = OpenFile(path, "r");
	if(file == null) return false;
	char buffer[256];
	if(asPreview) {
		// Kill any previous preview
		if(g_previewItems != null) ClearSavePreview();
		g_previewItems = new ArrayList();
	}
	SaveData data;
	while(file.ReadLine(buffer, sizeof(buffer))) {
		if(buffer[0] == '#') continue;
		data.Deserialize(buffer);
		int entity = data.ToEntity(NULL_VECTOR, asPreview);
		if(entity == -1) {
			PrintToServer("[Editor] LoadScene(\"%s\", %b): failed to create %s", save, asPreview, buffer);
			continue;
		}
	}
	delete file;
	return true;
}

void ConfirmSave(int client, const char[] name) {
	Menu newMenu = new Menu(SaveLoadConfirmHandler);
	newMenu.AddItem(name, "Spawn");
	newMenu.AddItem("", "Cancel");
	newMenu.ExitBackButton = false;
	newMenu.ExitButton = false;
	newMenu.Display(client, 0);
}
void ClearSavePreview() {
	if(g_previewItems != null) {
		for(int i = 0; i < g_previewItems.Length; i++) {
			int ref = g_previewItems.Get(i);
			if(IsValidEntity(ref)) {
				RemoveEntity(ref);
			}
		}
		delete g_previewItems;
	}
	g_pendingSaveClient = 0;
}

void AddSpawnedItem(int entity, int client = 0) {
	if(client > 0 && g_PropData[client].pendingSaveType == Save_Schematic) {
		g_PropData[client].schematic.AddEntity(entity, client);
	} 
	// TODO: confirm if we want it to be in list, otherwise we need to clean manually
	int userid = client > 0 ? GetClientUserId(client) : 0;
	int index = g_spawnedItems.Push(EntIndexToEntRef(entity));
	g_spawnedItems.Set(index, userid, 1);
}

bool CreateCollection(const char[] folder, const char[] name, ArrayList entities, int client = 0) {
	char path[PLATFORM_MAX_PATH], pathTemp[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "data/prop_spawner/collections", folder);
	CreateDirectory(path, 509);
	Format(path, sizeof(path), "%s/%s", path, folder);
	CreateDirectory(path, 509);
	Format(pathTemp, sizeof(pathTemp), "%s/%s.json.tmp", path, name);
	Format(path, sizeof(path), "%s/%s.json", path, name);
	char buffer[132];
	JSONObject root = new JSONObject();
	FormatTime(buffer, sizeof(buffer), "%Y-%m-%dT%H:%M:%S.%f");
	root.SetString("created", buffer);

	if(client > 0) {
		GetClientAuthId(client, AuthId_Steam2, buffer, sizeof(buffer));
		root.SetString("creator_steamid", buffer);
		float vec[3];
		GetClientAbsOrigin(client, vec);
		JSONObject origin = view_as<JSONObject>(Coordinates.FromVec(vec));
		root.Set("origin", origin);

		GetClientEyeAngles(client, vec);
		JSONObject angles = view_as<JSONObject>(Coordinates.FromVec(vec));
		root.Set("angles", angles);
	}
	JSONArray entArr = new JSONArray();
	for(int i = 0; i < entities.Length; i++) {
		int ref = entities.Get(i);
		if(IsValidEntity(ref)) {
			SpawnerEntity ent = SpawnerEntity.FromEntity(EntRefToEntIndex(ref));
			entArr.Push(ent);
		}
	}
	root.Set("entities", entArr);
	root.ToFile(pathTemp, JSON_INDENT(4));
	RenameFile(path, pathTemp);
	SetFilePermissions(path, FPERM_U_WRITE | FPERM_U_READ | FPERM_G_WRITE | FPERM_G_READ | FPERM_O_READ);
	LogAction(client, -1, "created collection \"%s\" in \"%s\"", name, path);
	return true;
}

bool CreateSceneSave(const char[] name, ArrayList items = null, int client = 0) {
	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "data/prop_spawner/saves/%s", g_currentMap);
	CreateDirectory(path, 509);
	Format(path, sizeof(path), "%s/%s.txt", path, name);
	File file = OpenFile(path, "w");
	if(file == null) {
		PrintToServer("[Editor] Could not save: %s", path);
		return false;
	}
	// TODO: switch to json
	char buffer[132];
	SaveData data;
	if(items == null) items = g_spawnedItems;
	for(int i = 0; i < items.Length; i++) {
		int ref = items.Get(i);
		if(IsValidEntity(ref)) {
			data.FromEntity(ref);
			data.Serialize(buffer, sizeof(buffer));
			file.WriteLine("%s", buffer);
		}
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
	if(ROOT_CATEGORY.items != null) return;
	ROOT_CATEGORY.items = new ArrayList(sizeof(CategoryData));
	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "data/prop_spawner/models");
	LoadFolder(ROOT_CATEGORY.items, path);
	ROOT_CATEGORY.items.SortCustom(SortCategories);
}
int SortCategories(int index1, int index2, ArrayList array, Handle hndl) {
	CategoryData cat1;
	array.GetArray(index1, cat1);
	CategoryData cat2;
	array.GetArray(index2, cat2);
	return strcmp(cat1.name, cat2.name);
}
public void UnloadCategories() {
	if(ROOT_CATEGORY.items == null) return;
	_UnloadCategories(ROOT_CATEGORY.items);
	delete ROOT_CATEGORY.items;
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
		return;
	}
	while(listing.GetNext(buffer, sizeof(buffer), fileType)) {
		if(fileType == FileType_Directory) {
			// TODO: support subcategory
			if(buffer[0] == '.') continue;
			CategoryData data;
			Format(data.name, sizeof(data.name), "%s", buffer);
			data.items = new ArrayList(sizeof(CategoryData));

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
	Format(category.name, sizeof(category.name), "%s", buffer);
	while(file.ReadLine(buffer, sizeof(buffer))) {
		if(buffer[0] == '#') continue;
		ReplaceString(buffer, sizeof(buffer), "\n", "");
		ReplaceString(buffer, sizeof(buffer), "\r", "");
		ItemData item;
		int index = SplitString(buffer, ":", item.model, sizeof(item.model));
		if(index == -1) {
			index = SplitString(buffer, " ", item.model, sizeof(item.model));
			if(index == -1) {
				// No name provided, use the model's filename
				index = FindCharInString(buffer, '/', true);
				strcopy(item.name, sizeof(item.name), item.model[index + 1]);
			} else {
				strcopy(item.name, sizeof(item.name), buffer[index]);
			}
			category.items.PushArray(item);
		} else if(StrEqual(item.model, "Classname")) {
			strcopy(category.classnameOverride, sizeof(category.classnameOverride), buffer[index]);
		} else if(StrEqual(item.model, "Type")) {
			Format(category.classnameOverride, sizeof(category.classnameOverride), "_%s", buffer[index]);
		}
	}
	parent.PushArray(category);
	delete file;
}
bool recentsChanged = false;
bool SaveRecents() {
	if(!recentsChanged) return true; // Nothing to do, nothing changed
	if(g_recentItems == null) return false;
	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "data/prop_spawner/recents_cache.csv");
	File file = OpenFile(path, "w");
	if(file == null) {
		PrintToServer("[Editor] Could not write to %s", path);
		return false;
	}
	StringMapSnapshot snapshot = g_recentItems.Snapshot();
	char model[128];
	RecentEntry entry;
	for(int i = 0; i < snapshot.Length; i++) {
		snapshot.GetKey(i, model, sizeof(model));
		g_recentItems.GetArray(model, entry, sizeof(entry));
		file.WriteLine("%s,%s,%d", model, entry.name, entry.count);
	}
	file.Flush();
	delete file;
	delete snapshot;
	recentsChanged = false;
	return true;
}
bool LoadRecents() {
	if(g_recentItems != null) delete g_recentItems;
	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "data/prop_spawner/recents_cache.csv");
	File file = OpenFile(path, "r");
	if(file == null) return false;
	g_recentItems = new StringMap();
	char buffer[128+64+16];
	char model[128];
	RecentEntry entry;
	while(file.ReadLine(buffer, sizeof(buffer))) {
		int index = SplitString(buffer, ",", model, sizeof(model));
		index += SplitString(buffer[index], ",", entry.name, sizeof(entry.name));
		entry.count = StringToInt(buffer[index]);
		g_recentItems.SetArray(model, entry, sizeof(entry));
	}
	delete file;
	return true;
}

// Returns an ArrayList<ItemData> of all the recents
ArrayList GetRecentsItemList() {
	ArrayList items = new ArrayList(sizeof(ItemData));
	StringMapSnapshot snapshot = g_recentItems.Snapshot();
	char model[128];
	RecentEntry entry;
	ItemData item;
	for(int i = 0; i < snapshot.Length; i++) {
		snapshot.GetKey(i, model, sizeof(model));
		g_recentItems.GetArray(model, entry, sizeof(entry));
		strcopy(item.model, sizeof(item.model), model);
		strcopy(item.name, sizeof(item.name), entry.name);
	}
	// This is pretty expensive in terms of allocations but shrug
	items.SortCustom(SortRecents);
	delete snapshot;
	return items;
}

int SortRecents(int index1, int index2, ArrayList array, Handle handle) {
	ItemData data1;
	array.GetArray(index1, data1);
	ItemData data2;
	array.GetArray(index2, data2);

	int count1, count2;
	RecentEntry entry;
	if(g_recentItems.GetArray(data1.model, entry, sizeof(entry))) return 0; //skip if somehow no entry
	count1 = entry.count;
	if(g_recentItems.GetArray(data2.model, entry, sizeof(entry))) return 0; //skip if somehow no entry
	count2 = entry.count;
	return count2 - count1; // desc
}

void AddRecent(const char[] model, const char[] name) {
	if(g_recentItems == null) {
		if(!LoadRecents()) return;
	}
	RecentEntry entry;
	if(!g_recentItems.GetArray(model, entry, sizeof(entry))) {
		entry.count = 0;
		strcopy(entry.name, sizeof(entry.name), name);
	}
	entry.count++;
	recentsChanged = true;
	g_recentItems.SetArray(model, entry, sizeof(entry));
}
public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs) {
	if(g_PropData[client].chatPrompt == Prompt_None) {
		return Plugin_Continue;
	}
	switch(g_PropData[client].chatPrompt) {
		case Prompt_Search: DoSearch(client, sArgs);
		case Prompt_SaveScene: {
			if(CreateSceneSave(sArgs, g_PropData[client].itemBuffer, client)) {
				PrintToChat(client, "\x04[Editor]\x01 Saved as \x05%s/%s.txt", g_currentMap, sArgs);
			} else {
				PrintToChat(client, "\x04[Editor]\x01 Unable to save. Sorry.");
			}
		}
		case Prompt_SaveCollection: {
			if(CreateCollection("global", sArgs, g_PropData[client].itemBuffer, client)) {
				SendEditorMessage(client, "Saved \x05%s/%s.json\x04 successfully.", "global", sArgs);
			} else {
				SendEditorMessage(client, "Failed to save collection.");
			}
			// TODO: figure out how to know which way to return
			ShowManagerSelectorMenu(client);
		}
		default: 
			PrintToChat(client, "\x04[Editor]\x01 Not implemented.");
	}
	g_PropData[client].chatPrompt = Prompt_None;
	return Plugin_Handled;
}
void DoSearch(int client, const char[] query) {
	ArrayList results = SearchItems(query);
	if(results.Length == 0) {
		CPrintToChat(client, "\x04[Editor]\x01 No results found. :(");
	} else {
		char title[64];
		Format(title, sizeof(title), "Results for \"%s\"", query);
		ShowTempItemMenu(client, results, title);
	}
}
// Gets the index of the spawned item, starting at index. negative to go from back
int GetSpawnedIndex(int client, int index) {
	int userid = GetClientUserId(client);
	if(index >= 0) {
		for(int i = index; i < g_spawnedItems.Length; i++) {
			int spawnedBy = g_spawnedItems.Get(i, 1);
			if(spawnedBy == userid) {
				return i;
			}
		}
	} else {
		for(int i = g_spawnedItems.Length + index; i >= 0; i--) {
			int spawnedBy = g_spawnedItems.Get(i, 1);
			if(spawnedBy == userid) {
				return i;
			}
		}
	}
	return -1;
}
#define MAX_SEARCH_RESULTS 30
ArrayList SearchItems(const char[] query) {
	// We have to put it into SearchData enum struct, then convert it back to ItemResult
	LoadCategories();
	ArrayList results = new ArrayList(sizeof(SearchData));
	_searchCategory(results, ROOT_CATEGORY.items, query);
	results.SortCustom(SortSearch);
	ArrayList items = new ArrayList(sizeof(ItemData));
	ItemData item; 
	SearchData data;
	for(int i = 0; i < results.Length; i++) {
		results.GetArray(i, data);
		item.FromSearchData(data);
		items.PushArray(item);
	}
	delete results;
	return items;
}

int SortSearch(int index1, int index2, ArrayList array, Handle handle) {
	SearchData data1;
	array.GetArray(index1, data1);
	SearchData data2;
	array.GetArray(index2, data2);
	return data1.index - data2.index;
}

void _searchCategory(ArrayList results, ArrayList categories, const char[] query) {
	CategoryData cat;
	if(categories == null) return;
	for(int i = 0; i < categories.Length; i++) {
		categories.GetArray(i, cat);
		if(cat.hasItems) {
			//cat.items is of CatetoryData
			if(!_searchItems(results, cat.items, query)) return;
		} else {
			//cat.items is of ItemData
			_searchCategory(results, cat.items, query);
		}
	}
}
bool _searchItems(ArrayList results, ArrayList items, const char[] query) {
	ItemData item;
	SearchData search;
	if(items == null) return false;
	for(int i = 0; i < items.Length; i++) {
		items.GetArray(i, item);
		int searchIndex = StrContains(item.name, query, false);
		if(searchIndex > -1) {
			search.FromItemData(item);
			search.index = searchIndex;
			results.PushArray(search);
			if(results.Length > MAX_SEARCH_RESULTS) return false;
		}
	}
	return true;
}

int GetSpawnedItem(int index) {
	if(index < 0 || index >= g_spawnedItems.Length) return -1;
	int ref = g_spawnedItems.Get(index);
	if(!IsValidEntity(ref)) {
		g_spawnedItems.Erase(index);
		return -1;
	}
	return ref;
}

bool RemoveSpawnedProp(int ref) {
	// int ref = EntIndexToEntRef(entity);
	int index = g_spawnedItems.FindValue(ref);
	if(index > -1) {
		g_spawnedItems.Erase(index);
		return true;
	}
	return false;
}

void OnDeleteToolEnd(int client, ArrayList entities) {
	int count;
	for(int i = 0; i < entities.Length; i++) {
		int ref = entities.Get(i);
		if(IsValidEntity(ref)) {
			count++;
			RemoveSpawnedProp(ref);
			RemoveEntity(ref);
		}
	}
	delete entities;
	PrintToChat(client, "\x04[Editor]\x01 \x05%d\x01 entities deleted", count);
}

void OnManagerSelectorEnd(int client, ArrayList entities) {
	// TODO: implement manager selector cb
	ReplyToCommand(client, "Not Implemented");
	Spawn_ShowManagerMainMenu(client);
	if(entities != null) {
		delete entities;
	}
}
void OnManagerSelectorSelect(int client, int entity) {
	// update entity count
	// ShowManagerSelectorMenu(client);
}

int DeleteAll(int onlyPlayer = 0) {
	int userid = onlyPlayer > 0 ? GetClientUserId(onlyPlayer) : 0;
	int count;
	for(int i = 0; i < g_spawnedItems.Length; i++) {
		int ref = g_spawnedItems.Get(i);
		int spawnedBy = g_spawnedItems.Get(i, 1);
		// Skip if wishing to only delete certain items:
		if(onlyPlayer == 0 || spawnedBy == userid) {
			if(IsValidEntity(ref)) {
				RemoveEntity(ref);
			}
			// TODO: erasing while removing
			g_spawnedItems.Erase(i);
			i--; // go back up one
			count++;
		}
	}
	return count;
}

#define SHOW_HINT_MIN_DURATION 600 // 600 s (10min)
void ShowHint(int client) {
	int time = GetTime();
	int lastActive = g_PropData[client].lastActiveTime; 
	g_PropData[client].lastActiveTime = time;
	if(time - lastActive < SHOW_HINT_MIN_DURATION) return;
	PrintToChat(client, "\x01Change Mode: \x05ZOOM");
	PrintToChat(client, "\x01Place: \x05USE(E)  \x01Cancel: \x05WALK(SHIFT) + USE(E)");
	PrintToChat(client, "\x01Rotate: \x05Hold RELOAD(R) + MOVE MOUSE\x01  Change Axis: \x05Left Click  \x01Snap Angle: \x05Right Click");
	PrintToChat(client, "\x01Type \x05/prop favorite\x01 to (un)favorite.");
	PrintToChat(client, "\x01More information & cheatsheat: \x05%s", "https://admin.jackz.me/docs/props");
}

void ToggleFavorite(int client, const char[] model, const char[] name = "") {
	char query[256];
	GetClientAuthId(client, AuthId_Steam2, query, sizeof(query));
	DataPack pack;
	pack.WriteCell(GetClientUserId(client));
	pack.WriteString(model);
	pack.WriteString(name);
	g_db.Format(query, sizeof(query), "SELECT name FROM editor_favorites WHERE steamid = '%s' AND model = '%s'", query, model);
	g_db.Query(DB_ToggleFavoriteCallback, query, pack);
}