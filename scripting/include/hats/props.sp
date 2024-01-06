public void OnAdminMenuReady(Handle topMenuHandle) {
	TopMenu topMenu = TopMenu.FromHandle(topMenuHandle);
	if(topMenu != g_topMenu) { 
		TopMenuObject propSpawner = topMenu.AddCategory("Prop Spawner (Alpha)", Category_Handler);
		if(propSpawner != INVALID_TOPMENUOBJECT) {
			topMenu.AddItem("Spawn Prop", AdminMenu_Spawn, propSpawner, "sm_prop");
			topMenu.AddItem("Edit Props", AdminMenu_Edit, propSpawner, "sm_prop");
			topMenu.AddItem("Delete Props", AdminMenu_Delete, propSpawner, "sm_prop");
			topMenu.AddItem("Save / Load", AdminMenu_SaveLoad, propSpawner, "sm_prop");

		}
	}
	g_topMenu = topMenu;
	
}

void Category_Handler(TopMenu topmenu, TopMenuAction action, TopMenuObject topobj_id, int param, char[] buffer, int maxlength) {
	if(action == TopMenuAction_DisplayTitle) {
		Format(buffer, maxlength, "Select a task:");
	} else if(action == TopMenuAction_DisplayOption) {
		Format(buffer, maxlength, "Spawn Props");
	}
}
void AdminMenu_Spawn(TopMenu topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength) {
    if(action == TopMenuAction_SelectOption) {
		if(!FindConVar("sv_cheats").BoolValue) {
			ReplyToCommand(param, "[Props] Enable cheats to use the prop spawner");
			return;
		}
        // TODO:
        /*
        Flow:
         1. /admin -> Prop Spawner -> Spawn -> [category] -> [prop] 
         2. ghost spawner active (press '?somekey?' to switch spawn mode)
         3. continue on place. press button to press?
        */
    //     Menu menu = new Menu(Handler_Spawn);
	//     menu.SetTitle("Spawn Method:");

	// 	menu.AddItem("p", "Physics");
	// 	menu.AddItem("s", "Solid");
	// 	menu.AddItem("n", "Non Solid");

	// 	menu.ExitBackButton = true;
	//     menu.ExitButton = true;
	//     menu.Display(param, MENU_TIME_FOREVER);
	}
}
void AdminMenu_Edit(TopMenu topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength) {
    
}
void AdminMenu_Delete(TopMenu topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength) {
    
}
void AdminMenu_SaveLoad(TopMenu topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength) {
    
}

int Handler_Spawn(Menu menu, MenuAction action, int client, int param2) {
	if (action == MenuAction_Select) {
		static char info[2];
        if(info[0] == 'p') {

        }
		
	} else if (action == MenuAction_End)	
		delete menu;
	return 0;
}