int StealItemMenuHandler(Menu menu, MenuAction action, int target, int param2) {
	// target here is the target of the sorry
	// the activator is from within
	if (action == MenuAction_Select) {
		static char info[32];
		menu.GetItem(param2, info, sizeof(info));
		static char str[3][8];
		ExplodeString(info, "|", str, 3, 8, false);
		int activator = GetClientOfUserId(StringToInt(str[0]));
		int itemid = StringToInt(str[1]);
		int slot = StringToInt(str[2]);
		if(itemid == -1) {
			// Grab a random item
			ArrayList seq = CreateRandomSequence(0, 4);
			for(int i = 0; i < seq.Length; i++) {
				slot = seq.Get(i);
				itemid = GetPlayerWeaponSlot(activator, slot);
				if(itemid > 0) break;
			}
			delete seq;
		}
		if(itemid > 0 && IsValidEntity(itemid)) {
			float pos[3];
			GetClientAbsOrigin(target, pos);
			int existingItem = GetPlayerWeaponSlot(activator, slot);
			// Drop item (throw to player) if they already have item, otherwise equip it direct
			if(existingItem > 0)
				SDKHooks_DropWeapon(activator, existingItem, pos);
			else
				EquipPlayerWeapon(target, itemid);
		} else {
			PrintToChat(target, "Item does not exist anymore.");
			ShowSorryAcceptMenu(activator, target);
		}
	} else if (action == MenuAction_End)	
		delete menu;
	return 0;
}