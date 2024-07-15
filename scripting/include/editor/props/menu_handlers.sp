TopMenuObject g_propSpawnerCategory;
public void OnAdminMenuReady(Handle topMenuHandle) {
	TopMenu topMenu = TopMenu.FromHandle(topMenuHandle);
	if(g_topMenu != topMenuHandle) { 
		g_propSpawnerCategory = topMenu.AddCategory("hats_editor", Category_Handler, "sm_prop");
		if(g_propSpawnerCategory != INVALID_TOPMENUOBJECT) {
			topMenu.AddItem("editor_spawn", AdminMenu_Spawn, g_propSpawnerCategory, "sm_prop");
			// topMenu.AddItem("editor_edit", AdminMenu_Edit, g_propSpawnerCategory, "sm_prop");
			topMenu.AddItem("editor_delete", AdminMenu_Delete, g_propSpawnerCategory, "sm_prop");
			topMenu.AddItem("editor_saveload", AdminMenu_SaveLoad, g_propSpawnerCategory, "sm_prop");
			topMenu.AddItem("editor_manager", AdminMenu_Manager, g_propSpawnerCategory, "sm_prop");
			topMenu.AddItem("editor_selector", AdminMenu_Selector, g_propSpawnerCategory, "sm_prop");
		}
		g_topMenu = topMenu;
	}
}

/////////////
// HANDLERS
/////////////
void Category_Handler(TopMenu topmenu, TopMenuAction action, TopMenuObject topobj_id, int param, char[] buffer, int maxlength) {
	if(action == TopMenuAction_DisplayTitle) {
		Format(buffer, maxlength, "Select a task:");
	} else if(action == TopMenuAction_DisplayOption) {
		Format(buffer, maxlength, "Spawn Props");
	}
}

void AdminMenu_Selector(TopMenu topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength) {
	if(action == TopMenuAction_DisplayOption) {
		Format(buffer, maxlength, "Selector");
	} else if(action == TopMenuAction_SelectOption) {
		ShowManagerSelectorMenu(param);
	}
}


void AdminMenu_Spawn(TopMenu topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength) {
	if(action == TopMenuAction_DisplayOption) {
		Format(buffer, maxlength, "Spawn Props");
	} else if(action == TopMenuAction_SelectOption) {
		ConVar cheats = FindConVar("sm_cheats");
		if(cheats != null && !cheats.BoolValue) {
			CReplyToCommand(param, "\x04[Editor] \x01Set \x05sm_cheats\x01 to \x051\x01 to use the prop spawner");
			return;
		}
		ShowSpawnRoot(param);
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
			case 'n': ShowCategoryList(client, ROOT_CATEGORY); 
		}
		// TODO: handle back (to top menu)
	} else if (action == MenuAction_Cancel) {
		if(param2 == MenuCancel_ExitBack) {
			DisplayTopMenuCategory(g_topMenu, g_propSpawnerCategory, client);
		} 
	} else if (action == MenuAction_End)	
		delete menu;
	return 0;
}
// void AdminMenu_Edit(TopMenu topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength) {
// 	if(action == TopMenuAction_DisplayOption) {
// 		Format(buffer, maxlength, "Edit Props");
// 	} else if(action == TopMenuAction_SelectOption) {
// 		ShowEditList(param);
// 	}
// }
void AdminMenu_Delete(TopMenu topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength) {
	if(action == TopMenuAction_DisplayOption) {
		Format(buffer, maxlength, "Delete Props");
	} else if(action == TopMenuAction_SelectOption) {
		ShowDeleteList(param);
	}
}

void AdminMenu_SaveLoad(TopMenu topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength) {
	if(action == TopMenuAction_DisplayOption) {
		Format(buffer, maxlength, "Save / Load");
	} else if(action == TopMenuAction_SelectOption) {
		Spawn_ShowSaveLoadMainMenu(param);
	}
}

void AdminMenu_Manager(TopMenu topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength) {
	if(action == TopMenuAction_DisplayOption) {
		Format(buffer, maxlength, "Manage Props");
	} else if(action == TopMenuAction_SelectOption) {
		Spawn_ShowManagerMainMenu(param);
	}
}

int SaveLoadMainMenuHandler(Menu menu, MenuAction action, int client, int param2) {
	if (action == MenuAction_Select) {
		char info[2];
		menu.GetItem(param2, info, sizeof(info));
		SaveType type = view_as<SaveType>(StringToInt(info));
		ShowSaves(client, type);
	} else if (action == MenuAction_Cancel) {
		if(param2 == MenuCancel_ExitBack) {
			DisplayTopMenuCategory(g_topMenu, g_propSpawnerCategory, client);
		} 
	} else if (action == MenuAction_End)	
		delete menu;
	return 0;
}

int SaveLoadSceneHandler(Menu menu, MenuAction action, int client, int param2) {
	if (action == MenuAction_Select) {
		char saveName[64];
		menu.GetItem(param2, saveName, sizeof(saveName));
		if(saveName[0] == '\0') {
			// Save new
			FormatTime(saveName, sizeof(saveName), "%Y-%m-%d_%H-%I-%M");
			if(CreateSceneSave(saveName)) {
				PrintToChat(client, "\x04[Editor]\x01 Saved as \x05%s/%s.txt", g_currentMap, saveName);
			} else {
				PrintToChat(client, "\x04[Editor]\x01 Unable to save. Sorry.");
			}
		} else if(g_pendingSaveClient != 0 && g_pendingSaveClient != client) {
			PrintToChat(client, "\x04[Editor]\x01 Another user is currently loading a save.");
		} else if(g_PropData[client].pendingSaveType == Save_Schematic) {
			PrintToChat(client, "\x04[Editor]\x01 Please complete or cancel current schematic to continue.");
		} else if(LoadScene(saveName, true)) {
			ConfirmSave(client, saveName);
			g_pendingSaveClient = client;
			PrintToChat(client, "\x04[Editor]\x01 Previewing save \x05%s", saveName);
			PrintToChat(client, "\x04[Editor]\x01 Press \x05Shift + Middle Mouse\x01 to spawn, \x05Middle Mouse\x01 to cancel");
		} else {
			PrintToChat(client, "\x04[Editor]\x01 Could not load save file.");
		}
	} else if (action == MenuAction_Cancel) {
		if(param2 == MenuCancel_ExitBack) {
			Spawn_ShowSaveLoadMainMenu(client);
		} 
	} else if (action == MenuAction_End)	
		delete menu;
	return 0;
}


int SaveLoadSchematicHandler(Menu menu, MenuAction action, int client, int param2) {
	if (action == MenuAction_Select) {
		char saveName[64];
		menu.GetItem(param2, saveName, sizeof(saveName));
		Schematic schem;
		if(saveName[0] == '\0') {
			if(g_PropData[client].pendingSaveType == Save_Schematic) {
				if(g_PropData[client].schematic.Save()) {
					PrintToChat(client, "\x04[Editor]\x01 Saved schematic as \x05%s", g_PropData[client].schematic.name);
				} else {
					PrintToChat(client, "\x04[Editor]\x01 Failed to save schematic.");
				}
				g_PropData[client].schematic.Reset();
				g_PropData[client].pendingSaveType = Save_None;
			} else {
				g_PropData[client].chatPrompt = Prompt_SaveSchematic;
				PrintToChat(client, "\x04[Editor]\x01 Enter in chat a name for schematic");
			}
		} else if(schem.Import(saveName)) {
			float pos[3];
			GetCursorLocation(client, pos);
			ArrayList list = schem.SpawnEntities(pos, true);
			SaveData save;
			int parent = list.GetArray(0, save);
			delete list;
			Editor[client].Import(parent);
			if(g_pendingSaveClient != 0 && g_pendingSaveClient != client) {
				PrintToChat(client, "\x04[Editor]\x01 Another user is currently loading a scene.");
			} else {
				g_pendingSaveClient = client;
				PrintToChat(client, "\x04[Editor]\x01 Previewing schematic \x05%s", saveName);
				PrintToChat(client, "\x04[Editor]\x01 Press \x05Shift + Middle Mouse\x01 to spawn, \x05Middle Mouse\x01 to cancel");
			}
		} else {
			PrintToChat(client, "\x04[Editor]\x01 Could not load save file.");
		}
	} else if (action == MenuAction_Cancel) {
		if(param2 == MenuCancel_ExitBack) {
			Spawn_ShowSaveLoadMainMenu(client);
		} 
	} else if (action == MenuAction_End)	
		delete menu;
	return 0;
}

int SaveLoadConfirmHandler(Menu menu, MenuAction action, int client, int param2) {
	if (action == MenuAction_Select) {
		ClearSavePreview();
		char info[64];
		menu.GetItem(param2, info, sizeof(info));
		if(info[0] != '\0') {
			PrintToChat(client, "\x04[Editor]\x01 Loaded scene \x05%s", info);
			LoadScene(info, false);
		}
	} else if (action == MenuAction_Cancel) {
		if(param2 == MenuCancel_ExitBack) {
			Spawn_ShowSaveLoadMainMenu(client);
		} 
	} else if (action == MenuAction_End)	
		delete menu;
	return 0;
}
int ManagerHandler(Menu menu, MenuAction action, int client, int param2) {
	if (action == MenuAction_Select) {
		char info[8];
		menu.GetItem(param2, info, sizeof(info));
		if(info[0] != '\0') {
			int index = StringToInt(info);
			int ref = g_spawnedItems.Get(index);
			// TODO: add delete confirm
			if(!IsValidEntity(ref)) {
				SendEditorMessage(client, "Entity has disappeared");
			} else {
				int entity = EntRefToEntIndex(ref);
				g_PropData[client].managerEntityRef = ref;
				g_PropData[client].StartHighlight(entity);
				ShowManagerEntityMenu(client, entity);
			}
		}
	} else if (action == MenuAction_Cancel) {
		if(param2 == MenuCancel_ExitBack) {
			DisplayTopMenuCategory(g_topMenu, g_propSpawnerCategory, client);
		} 
	} else if (action == MenuAction_End)	
		delete menu;
	return 0;
}
int ManagerEntityHandler(Menu menu, MenuAction action, int client, int param2) {
	if (action == MenuAction_Select) {
		g_PropData[client].StopHighlight();
		char info[32];
		menu.GetItem(param2, info, sizeof(info));
		int ref = g_PropData[client].managerEntityRef;
		if(!IsValidEntity(ref)) {
			SendEditorMessage(client, "Entity disappeared");
		} else if(StrEqual(info, "edit")) {
			Editor[client].ImportEntity(EntRefToEntIndex(ref), Edit_Manager);
			return 0;
		} else if(StrEqual(info, "delete")) {
			for(int i = 0; i < g_spawnedItems.Length; i++) {
				int spawnedRef = g_spawnedItems.Get(i);
				if(spawnedRef == ref) {
					g_spawnedItems.Erase(i);
					break;
				}
			}
			if(IsValidEntity(ref)) {
				RemoveEntity(ref);
			}
			return 0;
		} else if(StrEqual(info, "view")) {
			ReplyToCommand(client, "Maybe soon.");
		} else if(StrEqual(info, "select")) {
			int entity = EntRefToEntIndex(ref);
			g_PropData[client].Selector.AddEntity(entity);
		} else {
			SendEditorMessage(client, "Unknown option / not implemented");
		}
		ShowManagerSelectorMenu(client);
	} else if (action == MenuAction_Cancel) {
		g_PropData[client].StopHighlight();
		if(param2 == MenuCancel_ExitBack) {
			Spawn_ShowManagerMainMenu(client);
		} 
	} else if (action == MenuAction_End)	
		delete menu;
	return 0;
}
int ManagerSelectorMainMenuHandler(Menu menu, MenuAction action, int client, int param2) {
	if (action == MenuAction_Select) {
		EntitySelector sel = EntitySelector.FromClient(client);
		if(!sel.Active) {
			return 0;
		}
		char info[32];
		menu.GetItem(param2, info, sizeof(info));
		if(StrEqual(info, "list")) {
			SendEditorMessage(client, "Not implemented");
		} else if(StrEqual(info, "actions")) {
			ShowManagerSelectorActionsMenu(client);
		} else if(StrEqual(info, "add-self")) {
			int userid = GetClientUserId(client);
			int count;
			for(int i = 0; i < g_spawnedItems.Length; i++) {
				int ref = g_spawnedItems.Get(i);
				int spawnedBy = g_spawnedItems.Get(i, 1);
				if(spawnedBy == userid) {
					sel.AddEntity(EntRefToEntIndex(ref));
					count++;
				}
			}
			ReplyToCommand(client, "Added %d entities", count);
			ShowManagerSelectorMenu(client);
		} else if(StrEqual(info, "add-all")) {
			int count;
			for(int i = 0; i < g_spawnedItems.Length; i++) {
				int ref = g_spawnedItems.Get(i);
				sel.AddEntity(EntRefToEntIndex(ref));
				count++;
			}
			ReplyToCommand(client, "Added %d entities", count);
			ShowManagerSelectorMenu(client);
		} else if(StrEqual(info, "cancel")) {
			g_PropData[client].Selector.Cancel();
		}
	} else if (action == MenuAction_Cancel) {
		g_PropData[client].Selector.Cancel();
	} else if (action == MenuAction_End)	
		delete menu;
	return 0;
}
int ManagerSelectorActionHandler(Menu menu, MenuAction action, int client, int param2) {
	if (action == MenuAction_Select) {
		if(!g_PropData[client].Selector.IsActive()) {
			return 0;
		}
		char info[32];
		menu.GetItem(param2, info, sizeof(info));
		if(StrEqual(info, "delete")) {
			int count;
			for(int i = 0; i < g_PropData[client].Selector.list.Length; i++) {
				int ref = g_PropData[client].Selector.list.Get(i);
				if(IsValidEntity(ref)) {
					RemoveEntity(ref);
					count++;
				}
			}
			ArrayList list = g_PropData[client].Selector.End();
			delete list;
			SendEditorMessage(client, "Deleted %d entities", count);
			Spawn_ShowManagerMainMenu(client);
		} else if(StrEqual(info, "clear")) {
			g_PropData[client].Selector.Clear();
			SendEditorMessage(client, "Cleared selection.");
			Spawn_ShowManagerMainMenu(client);
		} else if(StrEqual(info, "save_scene")) {
			ArrayList items = g_PropData[client].Selector.End();
			g_PropData[client].SetItemBuffer(items, true);
			g_PropData[client].chatPrompt = Prompt_SaveScene;
			SendEditorMessage(client, "Enter name for scene:");
		} else if(StrEqual(info, "save_collection")) {
			ArrayList items = g_PropData[client].Selector.End();
			g_PropData[client].SetItemBuffer(items, true);
			g_PropData[client].chatPrompt = Prompt_SaveCollection;
			SendEditorMessage(client, "Enter name for collection:");
		} else {
			SendEditorMessage(client, "Unknown option / not implemented");
		}
	} else if (action == MenuAction_Cancel) {
		if(param2 == MenuCancel_ExitBack) {
			ShowManagerSelectorMenu(client);
		} 
	} else if (action == MenuAction_End)	
		delete menu;
	return 0;
}
int COLOR_DELETE[3] = { 255, 0, 0 }

int DeleteHandler(Menu menu, MenuAction action, int client, int param2) {
	if (action == MenuAction_Select) {
		char info[128];
		menu.GetItem(param2, info, sizeof(info));
		int ref = StringToInt(info[2]);
		int option = StringToInt(info);
		if(option == -1) {
			// Delete all (everyone)
			int count = DeleteAll();
			PrintToChat(client, "\x04[Editor]\x01 Deleted \x05%d\x01 items", count);
			ShowDeleteList(client);
		} else if(option == -2) {
			// Delete all (mine only)
			int count = DeleteAll(client);
			PrintToChat(client, "\x04[Editor]\x01 Deleted \x05%d\x01 items", count);
			ShowDeleteList(client);
		} else if(option == -3) {
			if(g_PropData[client].Selector.IsActive()) {
				g_PropData[client].Selector.End();
				PrintToChat(client, "\x04[Editor]\x01 Delete tool cancelled");
			} else {
				g_PropData[client].Selector.StartDirect(COLOR_DELETE, OnDeleteToolEnd);
				PrintToChat(client, "\x04[Editor]\x01 Delete tool active. Press \x05Left Mouse\x01 to mark props, \x05Right Mouse\x01 to undo. SHIFT+USE to spawn, CTRL+USE to cancel");
			}
			ShowDeleteList(client);
		} else {
			int index = g_spawnedItems.FindValue(ref);
			if(IsValidEntity(ref)) {
				RemoveEntity(ref);
			}
			if(index > -1) {
				g_spawnedItems.Erase(index);
				index--;
			} else { index = 0; }
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

int SpawnCategoryHandler(Menu menu, MenuAction action, int client, int param2) {
	if (action == MenuAction_Select) {
		char info[8];
		menu.GetItem(param2, info, sizeof(info));
		int index = StringToInt(info);
		// Reset item index when selecting new category
		if(g_PropData[client].lastCategoryIndex != index) {
			g_PropData[client].lastCategoryIndex = index;
			g_PropData[client].lastItemIndex = 0;
		}
		CategoryData category;
		g_PropData[client].PeekCategory(category); // Just need to get the category.items[index], don't want to pop
		category.items.GetArray(index, category);
		if(category.items == null) {
			LogError("Category %s has null items array (index=%d)", category.name, index);
		} else if(category.hasItems) {
			ShowCategoryItemMenu(client, category);
		} else {
			// Reset the category index for nested
			g_PropData[client].lastCategoryIndex = 0;
			// Make the list now be the selected category's list.
			ShowCategoryList(client, category);
		}
	} else if (action == MenuAction_Cancel) {
		if(param2 == MenuCancel_ExitBack) {
			CategoryData category;
			// Double pop
			if(g_PropData[client].PopCategory(category) && g_PropData[client].PopCategory(category)) {
				// Use the last category (go back one)
				ShowCategoryList(client, category);
			} else {
				ShowSpawnRoot(client);
			}
		} else {
			g_PropData[client].CleanupBuffers();
		}
	} else if (action == MenuAction_End)	
		delete menu;
	return 0;
}

int SpawnItemHandler(Menu menu, MenuAction action, int client, int param2) {
	if (action == MenuAction_Select) {
		char info[132];
		menu.GetItem(param2, info, sizeof(info));
		char index[4];
		char model[128];
		int nameIndex = SplitString(info, "|", index, sizeof(index));
		nameIndex += SplitString(info[nameIndex], "|", model, sizeof(model));
		g_PropData[client].lastItemIndex = StringToInt(index);
		if(Editor[client].PreviewModel(model, g_PropData[client].classnameOverride)) {
			Editor[client].SetName(info[nameIndex]);
			PrintHintText(client, "%s\n%s", info[nameIndex], model);
			ShowHint(client);
		} else {
			PrintToChat(client, "\x04[Editor]\x01 Error spawning preview \x01(%s)", model);
		}
		// Use same item menu again:
		ShowItemMenu(client);
	} else if(action == MenuAction_Cancel) {
		g_PropData[client].ClearItemBuffer();
		if(param2 == MenuCancel_ExitBack) {
			CategoryData category;
			if(g_PropData[client].PopCategory(category)) {
				// Use the last category (go back one)
				ShowCategoryList(client, category);
			} else {
				// If there is no categories, it means we are in a temp menu (search / recents / favorites)
				ShowSpawnRoot(client);
			}
		} else {
			g_PropData[client].CleanupBuffers();
		}
	} else if (action == MenuAction_End) {
		delete menu;
	}
	return 0;
}

// int EditHandler(Menu menu, MenuAction action, int client, int param2) {
// 	if (action == MenuAction_Select) {
// 		char info[8];
// 		menu.GetItem(param2, info, sizeof(info));
// 		int ref = StringToInt(info);
// 		int index = g_spawnedItems.FindValue(ref);
// 		int entity = EntRefToEntIndex(ref);
// 		if(entity > 0) {
// 			Editor[client].Import(entity, false);
// 			PrintToChat(client, "\x04[Editor]\x01 Editing entity \x05%d", entity);
// 		} else {
// 			PrintToChat(client, "\x04[Editor]\x01 Entity disappeared.");
// 			if(index > -1) {
// 				g_spawnedItems.Erase(index);
// 				index--;
// 			} else { index = 0; }
// 		}
// 		ShowEditList(client, index);
// 	} else if (action == MenuAction_Cancel) {
// 		if(param2 == MenuCancel_ExitBack) {
// 			DisplayTopMenuCategory(g_topMenu, g_propSpawnerCategory, client);
// 		} 
// 	} else if (action == MenuAction_End)	
// 		delete menu;
// 	return 0;
// }
