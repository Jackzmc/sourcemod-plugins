TopMenuObject g_propSpawnerCategory;
public void OnAdminMenuReady(Handle topMenuHandle) {
	TopMenu topMenu = TopMenu.FromHandle(topMenuHandle);
	if(g_topMenu != topMenuHandle) { 
		g_propSpawnerCategory = topMenu.AddCategory("hats_editor", Category_Handler);
		if(g_propSpawnerCategory != INVALID_TOPMENUOBJECT) {
			topMenu.AddItem("editor_spawn", AdminMenu_Spawn, g_propSpawnerCategory, "sm_prop");
			topMenu.AddItem("editor_edit", AdminMenu_Edit, g_propSpawnerCategory, "sm_prop");
			topMenu.AddItem("editor_delete", AdminMenu_Delete, g_propSpawnerCategory, "sm_prop");
			topMenu.AddItem("editor_saveload", AdminMenu_SaveLoad, g_propSpawnerCategory, "sm_prop");
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
		Format(buffer, maxlength, "Spawn Props (Beta)");
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
			case 'n': ShowCategoryList(client);
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
void AdminMenu_Edit(TopMenu topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength) {
	if(action == TopMenuAction_DisplayOption) {
		Format(buffer, maxlength, "Edit Props");
	} else if(action == TopMenuAction_SelectOption) {
		ShowEditList(param);
	}
}
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
		Menu menu = new Menu(SaveLoadHandler);
		menu.SetTitle("Save / Load");
		char name[64];
		menu.AddItem("", "[New Save]");
		ArrayList saves = LoadSaves();
		if(saves != null) {
			for(int i = 0; i < saves.Length; i++) {
				saves.GetString(i, name, sizeof(name));
				menu.AddItem(name, name);
			}
			delete saves;
		}
		menu.ExitBackButton = true;
		menu.ExitButton = true;
		menu.Display(param, MENU_TIME_FOREVER);
	}
}

int SpawnCategoryHandler(Menu menu, MenuAction action, int client, int param2) {
	if (action == MenuAction_Select) {
		char info[8];
		menu.GetItem(param2, info, sizeof(info));
		int index = StringToInt(info);
		PrintToServer("Item in category list selected: #%d", index);
		// Use g_categories, but if this is nested, then when a nested is selected, we need to use that list
		ShowItemMenu(client, index);
	} else if (action == MenuAction_Cancel) {
		if(param2 == MenuCancel_ExitBack) {
			ShowSpawnRoot(client);
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
			FormatTime(saveName, sizeof(saveName), "%Y-%m-%d_%H-%I-%M");
			if(CreateSave(saveName)) {
				PrintToChat(client, "\x04[Editor]\x01 Saved as \x05%s/%s.txt", g_currentMap, saveName);
			} else {
				PrintToChat(client, "\x04[Editor]\x01 Error creating save file");
			}
		} else if(LoadSave(saveName, true)) {
			strcopy(g_pendingSaveName, sizeof(g_pendingSaveName), saveName); 
			g_pendingSaveClient = client;
			PrintToChat(client, "\x04[Editor]\x01 Previewing save \x05%s", saveName);
			PrintToChat(client, "\x04[Editor]\x01 Press \x05Shift + Middle Mouse\x01 to spawn, \x05Middle Mouse\x01 to cancel");
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
			ShowDeleteList(client);
		} else if(index == -2) {
			// Delete all (mine only)
			int count = DeleteAll(client);
			PrintToChat(client, "\x04[Editor]\x01 Deleted \x05%d\x01 items", count);
			ShowDeleteList(client);
		} else if(index == -3) {
			if(g_PropData[client].markedProps != null) {
				EndDeleteTool(client, false);
			} else {
				g_PropData[client].markedProps = new ArrayList();
				PrintToChat(client, "\x04[Editor]\x01 Delete tool active. Press \x05E (Interact)\x01 to mark props.");
			}
			ShowDeleteList(client);
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
			Editor[client].SetData(info[nameIndex]);
			PrintHintText(client, "%s\n%s", info[nameIndex], model);
			ShowHint(client);
		} else {
			PrintToChat(client, "\x04[Editor]\x01 Error spawning preview \x01(%s)", model);
		}
		
		ShowItemMenuAny(client, null); // Use last menu
		// ShowItemMenu(client, g_PropData[client].lastCategoryIndex);
	} else if(action == MenuAction_Cancel) {
		if(param2 == MenuCancel_ExitBack) {
			ShowCategoryList(client, g_PropData[client].listBuffer);
		}
		g_PropData[client].CleanupBuffer();
		
	} else if (action == MenuAction_End) {
		delete menu;
	}
	return 0;
}

int EditHandler(Menu menu, MenuAction action, int client, int param2) {
	if (action == MenuAction_Select) {
		char info[8];
		menu.GetItem(param2, info, sizeof(info));
		int index = StringToInt(info);
		int ref = g_spawnedItems.Get(index);
		int entity = EntRefToEntIndex(ref);
		if(entity > 0) {
			Editor[client].Import(entity, false);
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
