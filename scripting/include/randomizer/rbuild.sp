/// MENUS
public void OpenMainMenu(int client) {
	Menu menu = new Menu(BuilderHandler_MainMenu);
	menu.SetTitle("Randomizer Builder");
	if(g_builder.mapData == null) {
		menu.AddItem("load", "Load Map Data");
		menu.AddItem("new", "New Map Data");
	} else {
		menu.AddItem("save", "Save Map Data");
		menu.AddItem("selector", "Start Selector");
		menu.AddItem("spawner", "Start Spawner");
		menu.AddItem("cursor", "Add Entity At Cursor");
		menu.AddItem("scenes", "Scenes");
	}
	menu.Display(client, 0);
}

void OpenScenesMenu(int client) {
	Menu menu = new Menu(BuilderHandler_ScenesMenu);
	menu.SetTitle("Select a scene");
	char id[64], display[32];
	JSONObjectKeys iterator = g_builder.mapData.Keys();
	while(iterator.ReadKey(id, sizeof(id))) {
		if(StrEqual(id, g_builder.selectedSceneId)) {
			Format(display, sizeof(display), "%s (selected)", id);
		} else {
			Format(display, sizeof(display), "%s", id);
		}
		menu.AddItem(id, display);
	}
	menu.Display(client, 0);
}

void OpenVariantsMenu(int client) {
	Menu menu = new Menu(BuilderHandler_VariantsMenu);
	menu.SetTitle("%s > Variants", g_builder.selectedSceneId);
	char id[8], display[32];
	menu.AddItem("new", "New Variant");
	menu.AddItem("-1", "Global Scene Variant");

	JSONArray variants = view_as<JSONArray>(g_builder.selectedSceneData.Get("variants"));
	JSONObject varObj;
	JSONArray entities;
	for(int i = 0; i < variants.Length; i++) {
		varObj = view_as<JSONObject>(variants.Get(i));
		entities = varObj.HasKey("entities") ? view_as<JSONArray>(varObj.Get("entities")) : new JSONArray();
		if(i == g_builder.selectedVariantIndex) {
			Format(display, sizeof(display), "#%d - %d entities (✔)", i, entities.Length);
		} else {
			Format(display, sizeof(display), "#%d - %d entities", i, entities.Length);
		}
		IntToString(i, id, sizeof(id));
		menu.AddItem(id, display);
	}
	menu.Display(client, 0);
}

/// HANDLERS

int BuilderHandler_MainMenu(Menu menu, MenuAction action, int client, int param2) {
	if (action == MenuAction_Select) {
		char info[32];
		menu.GetItem(param2, info, sizeof(info));
		if(StrEqual(info, "new")) {
			JSONObject temp = LoadMapJson(currentMap);
			GetCmdArg(2, info, sizeof(info));
			if(temp != null) {
				Menu nMenu = new Menu(BuilderHandler_MainMenu);
				nMenu.SetTitle("Existing map data exists");
				nMenu.AddItem("new_confirm", "Overwrite");
				nMenu.Display(client, 0);
				delete temp;
				return 0;
			} else {
				FakeClientCommand(client, "sm_rbuild new");
			}
		} else if(StrEqual(info, "new_confirm")) {
			FakeClientCommand(client, "sm_rbuild new confirm");
		} else if(StrEqual(info, "scenes")) {
			OpenScenesMenu(client);  
			return 0;
		} else {
			FakeClientCommand(client, "sm_rbuild %s", info);
		} /*else if(StrEqual(info, "cursor")) {
			Menu menu = new Menu(BuilderHandler_)
		}*/
		OpenMainMenu(client);
	} else if(action == MenuAction_Cancel) {
		if(param2 == MenuCancel_ExitBack) {
		}
	} else if (action == MenuAction_End) {
		delete menu;
	}
	return 0;
}

int BuilderHandler_ScenesMenu(Menu menu, MenuAction action, int client, int param2) {
	if (action == MenuAction_Select) {
		char info[64];
		menu.GetItem(param2, info, sizeof(info));
		if(StrEqual(info, "new")) {
			FakeClientCommand(client, "sm_rbuild scenes new");
			OpenScenesMenu(client);
		} else {
			FakeClientCommand(client, "sm_rbuild scenes select %s", info);
			OpenVariantsMenu(client);
		}
	} else if(action == MenuAction_Cancel) {
		if(param2 == MenuCancel_ExitBack) {
		}
	} else if (action == MenuAction_End) {
		delete menu;
	}
	return 0;
}

int BuilderHandler_VariantsMenu(Menu menu, MenuAction action, int client, int param2) {
	if (action == MenuAction_Select) {
		char info[64];
		menu.GetItem(param2, info, sizeof(info));
		if(StrEqual(info, "new")) {
			FakeClientCommand(client, "sm_rbuild scenes variants new");
		} else {
			FakeClientCommand(client, "sm_rbuild scenes variants select %s", info);
		}
		OpenVariantsMenu(client);
	} else if(action == MenuAction_Cancel) {
		if(param2 == MenuCancel_ExitBack) {
		}
	} else if (action == MenuAction_End) {
		delete menu;
	}
	return 0;
}

