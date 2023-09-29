#define MODEL_LENGTH 64
char SURVIVOR_NAMES[8][] = { "nick", "rochelle", "coach", "ellis", "bill", "zoey", "francis", "louis"};

enum struct PresetLocation {
	int survivorSet;
	float offset[3];
	float angles[3];
}

enum struct HatPreset {
	float offset[3];
	float angles[3];
	char model[MODEL_LENGTH];
	char type[32];
	float size;

	ArrayList locations;

	int Spawn() {
		PrecacheModel(this.model);
		int entity = CreateEntityByName(this.type);
		DispatchKeyValue(entity, "model", this.model);
		if(HasEntProp(entity, Prop_Send, "m_flModelScale"))
			SetEntPropFloat(entity, Prop_Send, "m_flModelScale", this.size);
		if(!DispatchSpawn(entity)) {
			LogError("Could not spawn entity of type %s model \"%s\"", this.type, this.model);
		}
		return entity;
	}

	int Apply(int client) {
		int entity = this.Spawn();
		float offset[3], angles[3];
		EquipHat(client, entity, this.type, HAT_PRESET);
		this.GetLocation(client, offset, angles);
		hatData[client].offset = offset;
		hatData[client].angles = angles;
		CreateTimer(0.1, Timer_RemountSimple, GetClientUserId(client));
		return entity;
	}

	void GetLocation(int client, float offset[3], float angles[3]) {
		if(this.locations != null) { 
			int survivorSet = GetEntProp(client, Prop_Send, "m_survivorCharacter");
			if(survivorSet < 0 || survivorSet > 7) survivorSet = 0;
			PresetLocation location;
			for(int i = 0; i < this.locations.Length; i++) {
				this.locations.GetArray(i, location, sizeof(location));
				if(location.survivorSet == survivorSet) {
					offset = location.offset;
					angles = location.angles;
					return;
				}
			}
		}
		offset = this.offset;
		angles = this.angles;
	}

}

Action Timer_RemountSimple(Handle h, int userid) {
	int client = GetClientOfUserId(userid);
	if(client > 0) {
		int entity = GetHat(client);
		if(entity > 0)
			TeleportEntity(entity, hatData[client].offset, hatData[client].angles, NULL_VECTOR);
	}
	return Plugin_Handled;
}

void LoadPresets() {
	KeyValues kv = new KeyValues("Presets");

	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "data/hat_presets.cfg");

	if(!FileExists(sPath) || !kv.ImportFromFile(sPath)) {
		PrintToServer("[Hats] Missing presets list");
		delete kv;
	}
	StringMap presets = new StringMap();
	
	kv.GotoFirstSubKey();
	// char type[32];
	int count = 0;
	char name[32];
	do {
		kv.GetSectionName(name, sizeof(name));
		HatPreset preset;
		// kv.GetString("type", entCfg.type, sizeof(entCfg.type), "prop_physics");
		kv.GetString("model", preset.model, sizeof(preset.model), "");
		kv.GetString("type", preset.type, sizeof(preset.type), "prop_dynamic");
		preset.size = kv.GetFloat("size", 1.0);
		if(preset.model[0] == '\0') {
			PrintToServer("[Hats] Warn: Skipping %s, no model", name);
			continue;
		}

		if(kv.JumpToKey("default")) {
			kv.GetVector("offset", preset.offset, NULL_VECTOR);
			kv.GetVector("angles", preset.angles, NULL_VECTOR);
			kv.GoBack();
		} else {
			PrintToServer("[Hats] Warn: Missing default for %s", name);
			continue;
		}

		for(int i = 0; i < 7; i++) {
			if(kv.JumpToKey(SURVIVOR_NAMES[i])) {
				if(preset.locations == null) {
					preset.locations = new ArrayList(sizeof(PresetLocation));
				}
				PresetLocation location;
				location.survivorSet = i; // TODO: confirm with l4d/l4d2 modes?
				kv.GetVector("offset", location.offset, NULL_VECTOR);
				kv.GetVector("angles", location.angles, NULL_VECTOR);
				preset.locations.PushArray(location);
				kv.GoBack();
			}
		}

		count++;
		presets.SetArray(name, preset, sizeof(preset));
	} while(kv.GotoNextKey(true));
	kv.GoBack();

	PrintToServer("[Hats] Loaded %d presets", count);


	if(g_HatPresets != null) {
		HatPreset preset;
		StringMapSnapshot snapshot = g_HatPresets.Snapshot();
		for(int i = 0; i <= snapshot.Length; i++) {
			snapshot.GetKey(i, name, sizeof(name));
			g_HatPresets.GetArray(name, preset, sizeof(preset));
			if(preset.locations != null) {
				delete preset.locations;
			}
		}
		delete g_HatPresets;
	}
	g_HatPresets = presets;
}


Action Command_DoAHatPreset(int client, int args) {
	AdminId adminId = GetUserAdmin(client);
	if(cvar_sm_hats_enabled.IntValue == 1) {
		if(adminId == INVALID_ADMIN_ID) {
			PrintToChat(client, "[Hats] Hats are for admins only");
			return Plugin_Handled;
		} else if(!adminId.HasFlag(Admin_Cheats)) {
			PrintToChat(client, "[Hats] You do not have permission");
			return Plugin_Handled;
		}
	} else if(cvar_sm_hats_enabled.IntValue == 0) {
		ReplyToCommand(client, "[Hats] Hats are disabled");
		return Plugin_Handled;
	} else if(GetClientTeam(client) != 2 && ~cvar_sm_hats_flags.IntValue & view_as<int>(HatConfig_InfectedHats)) {
		PrintToChat(client, "[Hats] Hats are only available for survivors.");
		return Plugin_Handled;
	}


	int entity = GetHat(client);
	if(entity > 0) {
		if(args > 0) {
			char arg[64];
			GetCmdArg(1, arg, sizeof(arg));
			if(arg[0] == 'v') {
				ReplyToCommand(client, "\t{");
				GetEntPropString(entity, Prop_Data, "m_ModelName", arg, sizeof(arg));
				ReplyToCommand(client, "\t\t\"model\"\t\"%s\"", arg);
				ReplyToCommand(client, "\t\t\"default\"\n\t\t{");
				ReplyToCommand(client, "\t\t\t\"origin\"\t\"%f %f %f\"", hatData[client].offset[0], hatData[client].offset[1], hatData[client].offset[2]);
				ReplyToCommand(client, "\t\t\t\"angles\"\t\"%f %f %f\"", hatData[client].angles[0], hatData[client].angles[1], hatData[client].angles[2]);
				ReplyToCommand(client, "\t\t}");
				ReplyToCommand(client, "\t\t\"size\"\t\"%.1f\"", GetEntPropFloat(entity, Prop_Send, "m_flModelScale"));
				GetEntityClassname(entity, arg, sizeof(arg));
				ReplyToCommand(client, "\t\t\"type\"\t\"%.1f\"", arg);
				ReplyToCommand(client, "\t}");
				ReplyToCommand(client, "Flags: %d", hatData[client].flags);
			} else {
				ReplyToCommand(client, "Unknown option");
			}
			// ReplyToCommand(client, "CurOffset: %f %f %f", );
			return Plugin_Handled;
		}
		if(HasFlag(client, HAT_PRESET)) {
			ClearHat(client);
			RemoveEntity(entity);
			PrintToChat(client, "[Hats] Cleared your hat preset");
			hatPresetCookie.Set(client, "");
			ActivePreset[client][0] = '\0';

		} else {
			PrintToChat(client, "[Hats] You already have a hat. Clear your hat to apply a preset.");
		}
	} else {
		Menu menu = new Menu(HatPresetHandler);
		menu.SetTitle("Choose a Hat", client);
		char id[32];
		StringMapSnapshot snapshot = g_HatPresets.Snapshot();
		if(snapshot.Length == 0) {
			PrintToChat(client, "[Hats] Seems there is no presets...");
			delete snapshot;
			return Plugin_Handled;
		}
		for(int i = 0; i < snapshot.Length; i++) {
			snapshot.GetKey(i, id, sizeof(id));
			menu.AddItem(id, id);
		}
		menu.Display(client, 0);
		delete snapshot;
	}
	return Plugin_Handled;
}


int HatPresetHandler(Menu menu, MenuAction action, int param1, int param2) {
	if (action == MenuAction_Select) {
		static char info[32];
		menu.GetItem(param2, info, sizeof(info));
		HatPreset preset;
		if(g_HatPresets.GetArray(info, preset, sizeof(preset))) {
			strcopy(ActivePreset[param1], 32, info);
			hatPresetCookie.Set(param1, info);
			preset.Apply(param1);
			ReplyToCommand(param1, "[Hats] Hat preset \"%s\" applied, enjoy!", info);
		} else {
			ReplyToCommand(param1, "Unknown hat preset \"%s\"", info);
		}
	} else if (action == MenuAction_End)	
		delete menu;
	return 0;
}

void RestoreActivePreset(int client) {
	if(ActivePreset[client][0] != '\0') {
		HatPreset preset;
		g_HatPresets.GetArray(ActivePreset[client], preset, sizeof(preset));
		preset.Apply(client);
	}
}