int BUILDER_COLOR[4] = { 0, 255, 0, 235 };
int GLOW_BLUE[4] = { 3, 148, 252 };
int GLOW_RED[4] = { 255, 0, 0, 235 };
int GLOW_WHITE[4] = { 255, 255, 255, 255 };
int GLOW_GREEN[4] = { 3, 252, 53 };
float ORIGIN_SIZE[3] = { 2.0, 2.0, 2.0 };

enum editMode {
	INACTIVE = 0,
	MOVE_ORIGIN,
	SCALE,
	COLOR,
	FREELOOK,
}
char MODE_NAME[5][] = {
	"Error",
	"Move & Rotate",
	"Scale",
	"Color",
	"Freelook"
}

enum editFlag {
	Edit_None,
	Edit_Copy = 1,
	Edit_Preview = 2,
	Edit_WallCreator = 4
}

enum buildType {
	Build_Solid,
	Build_Physics,
	Build_NonSolid,
}

enum CompleteType {
	Complete_WallSuccess,
	Complete_WallError,
	Complete_PropSpawned,
	Complete_PropError,
	Complete_EditSuccess
}

char COLOR_INDEX[4] = "RGBA";

ArrayList createdWalls;

enum struct WallBuilderData {
	float origin[3];
	float mins[3];
	float angles[3];
	float size[3];
	int color[4];
	int colorIndex;
	int axis;
	int snapAngle;
	int moveSpeed;
	float moveDistance;
	int entity;
	bool hasCollision;

	editMode mode;
	buildType buildType;
	editFlag flags;

	void Reset(bool initial = false) {
		// Clear previews
		if(this.entity != INVALID_ENT_REFERENCE && this.flags & Edit_Preview) {
			if(IsValidEntity(this.entity))
				RemoveEntity(this.entity);
		}
		this.entity = INVALID_ENT_REFERENCE;
		this.size[0] = this.size[1] = this.size[2] = 5.0;
		this.angles[0] = this.angles[1] = this.angles[2] = 0.0;
		this.color[0] = this.color[1] = this.color[2] = this.color[3] = 255;
		this.colorIndex = 0;
		this.axis = 1;
		this.moveDistance = 200.0;
		this.hasCollision = true;
		this.flags = Edit_None;
		this.buildType = Build_Solid;
		this.CalculateMins();
		this.SetMode(INACTIVE);
		if(initial) {
			this.moveSpeed = 1;
			this.snapAngle = 30;
		}
	}

	void CalculateMins() {
		this.mins[0] = -this.size[0];
		this.mins[1] = -this.size[1];
		this.mins[2] = -this.size[2];
	}

	void Draw(int color[4], float lifetime, float amplitude = 0.1) {
		if(this.flags & Edit_WallCreator || this.entity == INVALID_ENT_REFERENCE) {
			Effect_DrawBeamBoxRotatableToAll(this.origin, this.mins, this.size, this.angles, g_iLaserIndex, 0, 0, 30, lifetime, 0.4, 0.4, 0, amplitude, color, 0);
		} else {
			TeleportEntity(this.entity, this.origin, this.angles, NULL_VECTOR);
		}
		Effect_DrawAxisOfRotationToAll(this.origin, this.angles, ORIGIN_SIZE, g_iLaserIndex, 0, 0, 30, 0.2, 0.1, 0.1, 0, 0.0, 0);
	}

	void UpdateEntity() {
		int alpha = this.color[3];
		// Keep previews transparent
		if(this.flags & Edit_Preview) {
			alpha = 200;
		}
		SetEntityRenderColor(this.entity, this.color[0], this.color[1], this.color[2], alpha);
	}

	bool CheckEntity(int client) {
		if(this.entity != INVALID_ENT_REFERENCE) {
			if(!IsValidEntity(this.entity)) {
				PrintToChat(client, "\x04[Editor]\x01 Entity has vanished, editing cancelled.");
				this.Reset();
				return false;
			}
		}
		return true;
	}

	bool IsActive() {
		return this.mode != INACTIVE;
	}

	void SetMode(editMode mode) {
		this.mode = mode;
	}

	void CycleMode(int client, float tick) {
		if(tick - cmdThrottle[client] <= 0.25) return;
		int flags = GetEntityFlags(client) & ~FL_FROZEN;
		SetEntityFlags(client, flags);
		switch(this.mode) {
			// MODES: 
			// - MOVE (cursor point)
			// - ROTATE
			// - SCALE
			// - FREECAM
			case MOVE_ORIGIN: {
				if(this.flags & Edit_WallCreator) {
					this.mode = SCALE;
				} else if(this.flags & Edit_Preview) {
					this.mode = COLOR;
				} else {
					this.mode = FREELOOK;
				}
			}
			case SCALE: {
				this.mode = FREELOOK;
			}
			case COLOR: {
				this.mode = FREELOOK;
			}
			case FREELOOK: {
				this.mode = MOVE_ORIGIN;
				// PrintToChat(client, "Hold \x04USE (E)\x01 to rotate, \x04WALK (SHIFT)\x01 to change speed");
			}
		}
		PrintToChat(client, "\x04[Editor]\x01 Mode: \x05%s\x01 (Press \x04RELOAD\x01 to change mode)", MODE_NAME[this.mode]);
		cmdThrottle[client] = tick;
	}

	void ToggleCollision(int client, float tick) {
		if(tick - cmdThrottle[client] <= 0.25) return;
		this.hasCollision = !this.hasCollision
		if(this.hasCollision)
			PrintToChat(client, "\x04[Editor]\x01 Collision: \x05ON\x01");
		else
			PrintToChat(client, "\x04[Editor]\x01 Collision: \x04OFF\x01");
		cmdThrottle[client] = tick;
	}

	void CycleAxis(int client, float tick) {
		if(tick - cmdThrottle[client] <= 0.15) return;
		if(this.axis == 0) {
			this.axis = 1;
			PrintToChat(client, "\x04[Editor]\x01 Rotate Axis: \x05HEADING (Y)\x01");
		} else if(this.axis == 1) {
			this.axis = 2;
			PrintToChat(client, "\x04[Editor]\x01 Rotate Axis: \x05PITCH (X)\x01");
		} else {
			this.axis = 0;
			PrintToChat(client, "\x04[Editor]\x01 Rotate Axis: \x05ROLL (Z)\x01");
		}
		cmdThrottle[client] = tick;
	}

	void CycleSnapAngle(int client, float tick) {
		if(tick - cmdThrottle[client] <= 0.15) return;
		switch(this.snapAngle) {
			case 1: this.snapAngle = 15;
			case 15: this.snapAngle = 30;
			case 30: this.snapAngle = 45;
			case 45: this.snapAngle = 90;
			case 90: this.snapAngle = 1;
		}

		this.angles[0] = SnapTo(this.angles[0], float(this.snapAngle));
		this.angles[1] = SnapTo(this.angles[1], float(this.snapAngle));
		this.angles[2] = SnapTo(this.angles[2], float(this.snapAngle));

		if(this.snapAngle == 1)
			PrintToChat(client, "\x04[Editor]\x01 Rotate Snap Degrees: \x04(OFF)\x01", this.snapAngle);
		else
			PrintToChat(client, "\x04[Editor]\x01 Rotate Snap Degrees: \x05%d\x01", this.snapAngle);
		cmdThrottle[client] = tick;
	}

	void CycleSpeed(int client, float tick) {
		if(tick - cmdThrottle[client] <= 0.25) return;
		this.moveSpeed++;
		if(this.moveSpeed > 10) this.moveSpeed = 1;
		PrintToChat(client, "\x04[Editor]\x01 Scale Speed: \x05%d\x01", this.moveSpeed);
		cmdThrottle[client] = tick;
	}

	void CycleBuildType(int client) {
		// No tick needed, is handled externally
		if(this.buildType == Build_Physics) {
			this.buildType = Build_Solid;
			PrintToChat(client, "\x04[Editor]\x01 Spawn as: \x05Solid\x01");
		} else if(this.buildType == Build_Solid) {
			this.buildType = Build_Physics;
			PrintToChat(client, "\x04[Editor]\x01 Spawn as: \x05Physics\x01");
		} else {
			this.buildType = Build_NonSolid;
			PrintToChat(client, "\x04[Editor]\x01 Spawn as: \x05Non Solid\x01");
		}
	}

	void CycleColorComponent(int client, float tick) {
		if(tick - cmdThrottle[client] <= 0.25) return;
		this.colorIndex++;
		if(this.colorIndex > 3) this.colorIndex = 0;
		PrintToChat(client, "\x04[Editor]\x01 Color Component: \x05%c\x01", COLOR_INDEX[this.colorIndex]);
		cmdThrottle[client] = tick;
	}


	CompleteType Create(int& entity) {
		if(this.flags & Edit_WallCreator) {
			return this._FinishWall(entity) ? Complete_WallSuccess : Complete_WallError;
		} else if(this.flags & Edit_Preview) {
			return this._FinishPreview(entity) ? Complete_PropSpawned : Complete_PropError;
		} else {
			// Is edit, do nothing, just reset
			this.Reset();
			entity = 0;
			return Complete_EditSuccess;
		}
	}

	bool _FinishWall(int& id) {
		if(~this.flags & Edit_WallCreator) {
			this.Reset();
			return false;
		}
		// Don't need to build a new one if we editing:
		int blocker = this.entity;
		bool isEdit = false;
		if(blocker != INVALID_ENT_REFERENCE) {
			RemoveEntity(this.entity);
			isEdit = true;
		}
		blocker = CreateEntityByName("func_brush");
		if(blocker == -1) return false;
		DispatchKeyValueVector(blocker, "mins", this.mins);
		DispatchKeyValueVector(blocker, "maxs", this.size);
		DispatchKeyValueVector(blocker, "boxmins", this.mins);
		DispatchKeyValueVector(blocker, "boxmaxs", this.size);
		DispatchKeyValue(blocker, "excludednpc", "player");

		DispatchKeyValueVector(blocker, "angles", this.angles);
		DispatchKeyValue(blocker, "model", DUMMY_MODEL);
		DispatchKeyValue(blocker, "intialstate", "1");
		// DispatchKeyValueVector(blocker, "angles", this.angles);
		DispatchKeyValue(blocker, "BlockType", "4");
		char name[32];
		Format(name, sizeof(name), "l4d2_hats_%d", createdWalls.Length);
		DispatchKeyValue(blocker, "targetname", name);
		// DispatchKeyValue(blocker, "excludednpc", "player");
		TeleportEntity(blocker, this.origin, this.angles, NULL_VECTOR);
		if(!DispatchSpawn(blocker)) return false;
		SetEntPropVector(blocker, Prop_Send, "m_vecMins", this.mins);
		SetEntPropVector(blocker, Prop_Send, "m_vecMaxs", this.size);
		SetEntProp(blocker, Prop_Send, "m_nSolidType", 2);
		int enteffects = GetEntProp(blocker, Prop_Send, "m_fEffects");
		enteffects |= 32; //EF_NODRAW
		SetEntProp(blocker, Prop_Send, "m_fEffects", enteffects); 
		AcceptEntityInput(blocker, "Enable");
		SDKHook(blocker, SDKHook_Use, OnWallClicked);

		this.Draw(GLOW_GREEN, 5.0, 1.0);
		this.Reset();
		if(!isEdit) {
			id = createdWalls.Push(EntIndexToEntRef(blocker));
		}
		return true;
	}

	bool _FinishPreview(int& entity) {
		entity = -1;
		if(this.buildType == Build_Physics)
			entity = CreateEntityByName("prop_physics");
		else
			entity = CreateEntityByName("prop_dynamic");
		if(entity == -1) return false;

		char model[128];
		GetEntPropString(this.entity, Prop_Data, "m_ModelName", model, sizeof(model));
		DispatchKeyValue(entity, "model", model);
		DispatchKeyValue(entity, "targetname", "prop_preview");
		if(this.buildType == Build_NonSolid)
			DispatchKeyValue(entity, "solid", "0");
		else
			DispatchKeyValue(entity, "solid", "6");
		TeleportEntity(entity, this.origin, this.angles, NULL_VECTOR);
		if(!DispatchSpawn(entity)) {
			return false;
		}
		SetEntityRenderColor(entity, this.color[0], this.color[1], this.color[2], this.color[3]);
		SetEntityRenderColor(this.entity, 255, 128, 255, 200); // reset ghost
		GlowEntity(entity, 1.4)

		if(this.mode == FREELOOK)
			this.SetMode(MOVE_ORIGIN);
		

		// Don't kill preview until cancel
		return true;
	}

	int Copy() {
		if(this.entity == INVALID_ENT_REFERENCE) return -1;
		char classname[64];
		GetEntityClassname(this.entity, classname, sizeof(classname));

		int entity = CreateEntityByName(classname);
		if(entity == -1) return -1;
		GetEntPropString(this.entity, Prop_Data, "m_ModelName", classname, sizeof(classname));
		DispatchKeyValue(entity, "model", classname);
		

		Format(classname, sizeof(classname), "hats_copy_%d", this.entity);
		DispatchKeyValue(entity, "targetname", classname);

		DispatchKeyValue(entity, "solid", "6");

		DispatchSpawn(entity);
		// SetEntProp(entity, Prop_Send, "m_CollisionGroup", 1);
		// SetEntProp(entity, Prop_Send, "m_nSolidType", 6);
		TeleportEntity(entity, this.origin, this.angles, NULL_VECTOR);
		this.entity = entity;
		this.flags |= Edit_Copy;
		return entity;
	}

	void StartWall() {
		this.Reset();
		this.flags |= Edit_WallCreator;
	}

	bool PreviewModel(const char[] model) {
		// If last entity was preview, kill it
		PrecacheModel(model);
		this.Reset();
		int entity = CreateEntityByName("prop_dynamic");
		if(entity == -1) return false;
		DispatchKeyValue(entity, "model", model);
		DispatchKeyValue(entity, "targetname", "prop_preview");
		DispatchKeyValue(entity, "solid", "0");
		DispatchKeyValue(entity, "rendercolor", "255 128 255");
		DispatchKeyValue(entity, "renderamt", "200");
		DispatchKeyValue(entity, "rendermode", "1");
		if(!DispatchSpawn(entity)) {
			return false;
		}
		this.entity = entity;
		this.flags |= (Edit_Copy | Edit_Preview);
		this.SetMode(MOVE_ORIGIN);
		// Seems some entities fail here:
		return IsValidEntity(entity);
	}

	void Import(int entity, bool makeCopy = false, editMode mode = SCALE) {
		this.Reset();
		GetEntPropVector(entity, Prop_Send, "m_vecOrigin", this.origin);
		GetEntPropVector(entity, Prop_Send, "m_angRotation", this.angles);
		GetEntPropVector(entity, Prop_Send, "m_vecMins", this.mins);
		GetEntPropVector(entity, Prop_Send, "m_vecMaxs", this.size);
		if(!makeCopy) {
			this.entity = entity;
		}
		this.SetMode(mode);
	}

	void Cancel() {
		// Delete any copies:
		if(this.flags & Edit_Copy || this.flags & Edit_Preview) {
			RemoveEntity(this.entity);
		}
		this.SetMode(INACTIVE);
	}

	// void OpenSettings(int client) {
	// 	Menu menu = new Menu(SettingsHandler);
	// 	menu.AddItem("color", "Change Color");
	// 	menu.AddItem("type", "Change Spawn Type");
	// 	// if(this.flags & Edit_Scale)
	// 	menu.ExitButton = true;
	// 	// Only show back if we are for a preview
	// 	menu.ExitBackButton = (this.flags & Edit_Preview) != 0;
	// 	menu.Display(client, MENU_TIME_FOREVER);
	// }
}

WallBuilderData WallBuilder[MAXPLAYERS+1];

// int SettingsHandler(Menu menu, MenuAction action, int client, int param2) {
// 	if (action == MenuAction_Select) {
// 		char info[8];
// 		menu.GetItem(param2, info, sizeof(info));
// 		if(StrEqual(info, "color")) {
// 			Menu newMenu = new Menu(ColorHandler);
// 			newMenu.AddItem()
// 		} else if(StrEqual(info, "type")) {

// 		} else {
// 			CPrintToChat(client, "\x04[Editor]\x01 Error: Unknown setting \x05%s", info);
// 		}
		
// 		// Re-open category list when done editing setting
// 		if(WallBuilder[client].flags & Edit_Preview) {
// 			ShowItemMenu(client, g_lastCategoryIndex[client]);
// 		}
// 	} else if(action == MenuAction_Cancel) {
// 		if(WallBuilder[client].flags & Edit_Preview) {
// 			ShowItemMenu(client, g_lastCategoryIndex[client]);
// 		}	
// 	} else if (action == MenuAction_End)	
// 		delete menu;
// 	return 0;
// }

// int ColorHandler(Menu menu, MenuAction action, int client, int param2) {
// 	if (action == MenuAction_Select) {
// 		char info[8];
		
// 	} else if(action == MenuAction_Cancel) {
// 		if(WallBuilder[client].flags & Edit_Preview) {
// 			ShowItemMenu(client, g_lastCategoryIndex[client]);
// 		}	
// 	} else if (action == MenuAction_End)	
// 		delete menu;
// 	return 0;
// }

Action OnWallClicked(int entity, int activator, int caller, UseType type, float value) {
	int wallId = FindWallId(entity);
	if(wallId > 0) {
		GlowWall(wallId, GLOW_BLUE);
		AcceptEntityInput(entity, "Toggle");
	} else {
		PrintHintText(activator, "Invalid wall entity (%d)", entity);
	}
	return Plugin_Continue;
}



// TODO: Stacker, copy tool, new command?
public Action Command_MakeWall(int client, int args) {
	if(WallBuilder[client].IsActive()) {
		ReplyToCommand(client, "\x04[Editor]\x01 You are currently editing an entity. Finish editing your current entity with with \x05/edit done\x01 or cancel with \x04/edit cancel\x01");
	} else {
		WallBuilder[client].StartWall();
		if(args > 0) {
			// Get values for X, Y and Z axis (defaulting to 1.0):
			char arg2[8];
			for(int i = 0; i < 3; i++) {
				GetCmdArg(i + 1, arg2, sizeof(arg2));
				float value;
				if(StringToFloatEx(arg2, value) == 0) {
					value = 1.0;
				}
				WallBuilder[client].size[i] = value;
			}

			float rot[3];
			GetClientEyeAngles(client, rot);
			// Flip X and Y depending on rotation
			// TODO: Validate
			if(rot[2] > 45 && rot[2] < 135 || rot[2] > -135 && rot[2] < -45) {
				float temp = WallBuilder[client].size[0];
				WallBuilder[client].size[0] = WallBuilder[client].size[1];
				WallBuilder[client].size[1] = temp;
			}
			
			WallBuilder[client].CalculateMins();
		}

		WallBuilder[client].SetMode(SCALE);
		GetCursorLimited(client, 100.0, WallBuilder[client].origin, Filter_IgnorePlayer);
		PrintToChat(client, "\x04[Editor]\x01 New Wall Started. End with \x05/wall build\x01 or \x04/wall cancel\x01");
		PrintToChat(client, "\x04[Editor]\x01 Mode: \x05Scale\x01");
	}
	return Plugin_Handled;
}

public Action Command_ManageWalls(int client, int args) {
	if(args == 0) {
		PrintToChat(client, "\x04[Editor]\x01 Created Walls: \x05%d\x01", createdWalls.Length);
		for(int i = 1; i <= createdWalls.Length; i++) {
			GlowWall(i, GLOW_WHITE, 20.0);
		}
		return Plugin_Handled;
	}
	char arg1[16], arg2[16];
	GetCmdArg(1, arg1, sizeof(arg1));
	GetCmdArg(2, arg2, sizeof(arg2));
	if(StrEqual(arg1, "build") || StrEqual(arg1, "done")) {
		// Remove frozen flag from user, as some modes use this
		int flags = GetEntityFlags(client) & ~FL_FROZEN;
		SetEntityFlags(client, flags);
		
		int entity;
		CompleteType result = WallBuilder[client].Create(entity);
		switch(result) {
			case Complete_WallSuccess: {
				if(entity > 0)
					PrintToChat(client, "\x04[Editor]\x01 Wall Creation: \x05Wall #%d Created\x01", entity + 1);
				else
					PrintToChat(client, "\x04[Editor]\x01 Wall Edit: \x04Complete\x01");
			}
			case Complete_PropSpawned: 
				PrintToChat(client, "\x04[Editor]\x01 Prop Spawned: \x04%d\x01", entity);
			
			case Complete_EditSuccess: 
				PrintToChat(client, "\x04[Editor]\x01 Entity Edited: \x04%d\x01", entity);
			
			default:
				PrintToChat(client, "\x04[Editor]\x01 Unknown result");
		}
	} else if(StrEqual(arg1, "cancel")) {
		int flags = GetEntityFlags(client) & ~FL_FROZEN;
		SetEntityFlags(client, flags);
		WallBuilder[client].Cancel();
		if(WallBuilder[client].flags & Edit_Preview)
			PrintToChat(client, "\x04[Editor]\x01 Prop Spawer: \x04Done\x01");
		else if(WallBuilder[client].flags & Edit_WallCreator) {
			PrintToChat(client, "\x04[Editor]\x01 Wall Creation: \x04Cancelled\x01");
		} else {
			PrintToChat(client, "\x04[Editor]\x01 Entity Edit: \x04Cancelled\x01");
		}
	} else if(StrEqual(arg1, "export")) {
		// TODO: support exp #id
		float origin[3], angles[3], size[3];
		if(WallBuilder[client].IsActive()) {
			origin = WallBuilder[client].origin;
			angles = WallBuilder[client].angles;
			size = WallBuilder[client].size;
			Export(client, arg2, WallBuilder[client].entity, origin, angles, size);
		} else {
			int id = GetWallId(client, arg2);
			if(id == -1) return Plugin_Handled;
			int entity = GetWallEntity(id);
			GetEntPropVector(entity, Prop_Send, "m_vecOrigin", origin);
			if(HasEntProp(entity, Prop_Send, "m_vecAngles"))
				GetEntPropVector(entity, Prop_Send, "m_vecAngles", angles);
			GetEntPropVector(entity, Prop_Send, "m_vecMaxs", size);
			Export(client, arg2, entity, origin, angles, size);
		}


	} else if(StrEqual(arg1, "delete")) {
		if(WallBuilder[client].IsActive() && args == 1) {
			int entity = WallBuilder[client].entity;
			if(IsValidEntity(entity)) {
				PrintToChat(client, "\x04[Editor]\x01 You are not editing any existing entity, use \x05/wall cancel\x01 to stop or \x05/wall delete <id/all>");
			} else if(entity > MaxClients) {
				RemoveEntity(entity);
				WallBuilder[client].Reset();
				PrintToChat(client, "\x04[Editor]\x01 Deleted current entity");
			} else {
				PrintToChat(client, "\x04[Editor]\x01 Cannot delete player entities.");
			}
		} else if(StrEqual(arg2, "all")) {
			int walls = createdWalls.Length;
			for(int i = 1; i <= createdWalls.Length; i++) {
				DeleteWall(i);
			}
			PrintToChat(client, "\x04[Editor]\x01 Deleted \x05%d\x01 Walls", walls);
		} else {
			int id = GetWallId(client, arg2);
			if(id > -1) {
				DeleteWall(id);
				PrintToChat(client, "\x04[Editor]\x01 Deleted Wall: \x05#%d\x01", id);
			}
		}
	} else if(StrEqual(arg1, "create")) {
		ReplyToCommand(client, "\x04[Editor]\x01 Syntax: /mkwall [size x] [size y] [size z]");
	} else if(StrEqual(arg1, "toggle")) {
		if(StrEqual(arg2, "all")) {
			int walls = createdWalls.Length;
			for(int i = 1; i <= createdWalls.Length; i++) {
				int entity = GetWallEntity(i);
				AcceptEntityInput(entity, "Toggle");
				GlowWall(i, GLOW_BLUE);
			}
			PrintToChat(client, "\x04[Editor]\x01 Toggled \x05%d\x01 walls", walls);
		} else {
			int id = GetWallId(client, arg2);
			if(id > -1) {
				int entity = GetWallEntity(id);
				AcceptEntityInput(entity, "Toggle");
				GlowWall(id, GLOW_BLUE);
				PrintToChat(client, "\x04[Editor]\x01 Toggled Wall: \x05#%d\x01", id);
			}
		}
	} else if(StrEqual(arg1, "filter")) {
		if(args < 3) {
			ReplyToCommand(client, "\x04[Editor]\x01 Syntax: \x05/walls filter <id/all> <filter type>\x04");
			ReplyToCommand(client, "\x04[Editor]\x01 Valid filters: \x05player");
			return Plugin_Handled;
		}

		char arg3[32];
		GetCmdArg(3, arg3, sizeof(arg3));

		SetVariantString(arg3);
		if(StrEqual(arg2, "all")) {
			int walls = createdWalls.Length;
			for(int i = 1; i <= createdWalls.Length; i++) {
				int entity = GetWallEntity(i);
				AcceptEntityInput(entity, "SetExcluded");
			}
			PrintToChat(client, "\x04[Editor]\x01 Set %d walls' filter to \x05%s\x01", walls, arg3);
		} else {
			int id = GetWallId(client, arg2);
			if(id > -1) {
				int entity = GetWallEntity(id);
				AcceptEntityInput(entity, "SetExcluded");
				PrintToChat(client, "\x04[Editor]\x01 Set wall #%d filter to \x05%s\x01", id, arg3);
			}
		}
	} else if(StrEqual(arg1, "edit")) {
		int id = GetWallId(client, arg2);
		if(id > -1) {
			int entity = GetWallEntity(id);
			WallBuilder[client].Import(entity);
			PrintToChat(client, "\x04[Editor]\x01 Editing wall \x05%d\x01. End with \x05/wall done\x01 or \x04/wall cancel\x01", id);
			PrintToChat(client, "\x04[Editor]\x01 Mode: \x05Scale\x01");
		}
	} else if(StrEqual(arg1, "edite") || (arg1[0] == 'c' && arg1[1] == 'u')) {
		int index = GetLookingEntity(client, Filter_ValidHats); //GetClientAimTarget(client, false);
		if(index > 0) {
			WallBuilder[client].Import(index, false, MOVE_ORIGIN);
			char classname[32];
			char targetname[32];
			GetEntityClassname(index, classname, sizeof(classname));
			GetEntPropString(index, Prop_Data, "m_target", targetname, sizeof(targetname));
			PrintToChat(client, "\x04[Editor]\x01 Editing entity \x05%d (%s) [%s]\x01. End with \x05/wall done\x01", index, classname, targetname);
			PrintToChat(client, "\x04[Editor]\x01 Mode: \x05Move & Rotate\x01");
		} else {
			ReplyToCommand(client, "\x04[Editor]\x01 Invalid or non existent entity");
		}
	} else if(StrEqual(arg1, "copy")) {
		if(WallBuilder[client].IsActive()) {
			int oldEntity = WallBuilder[client].entity;
			if(oldEntity == INVALID_ENT_REFERENCE) {
				PrintToChat(client, "\x04[Editor]\x01 Finish editing your wall first: \x05/wall done\x01 or \x04/wall cancel\x01");
			} else { 
				int entity = WallBuilder[client].Copy();
				PrintToChat(client, "\x04[Editor]\x01 Editing copy \x05%d\x01 of entity \x05%d\x01. End with \x05/edit done\x01 or \x04/edit cancel\x01", entity, oldEntity);
			}
		} else {
			int id = GetWallId(client, arg2);
			if(id > -1) {
				int entity = GetWallEntity(id);
				WallBuilder[client].Import(entity, true);
				GetCursorLimited(client, 100.0, WallBuilder[client].origin, Filter_IgnorePlayer);
				PrintToChat(client, "\x04[Editor]\x01 Editing copy of wall \x05%d\x01. End with \x05/wall build\x01 or \x04/wall cancel\x01", id);
				PrintToChat(client, "\x04[Editor]\x01 Mode: \x05Scale\x01");
			}
		}
	} else if(StrEqual(arg1, "list")) {
		for(int i = 1; i <= createdWalls.Length; i++) {
			int entity = GetWallEntity(i);
			ReplyToCommand(client, "Wall #%d - EntIndex: %d", i, EntRefToEntIndex(entity));
		}
	} else {
		ReplyToCommand(client, "\x04[Editor]\x01 See console for list of commands");
		GetCmdArg(0, arg1, sizeof(arg1));
		PrintToConsole(client, "%s done / build - Finishes editing, creates wall if making wall", arg1);
		PrintToConsole(client, "%s cancel - Cancels editing (for entity edits is same as done)", arg1);
		PrintToConsole(client, "%s list - Lists all walls", arg1);
		PrintToConsole(client, "%s filter <id/all> <filter type> - Sets classname filter for walls, doesnt really work", arg1);
		PrintToConsole(client, "%s toggle <id/all> - Toggles if wall is active (collides)", arg1);
		PrintToConsole(client, "%s delete <id/all> - Deletes the wall(s)", arg1);
		PrintToConsole(client, "%s edit <id> - Edits wall id", arg1);
		PrintToConsole(client, "%s copy [id] - If editing creates a new copy of wall/entity, else copies wall id", arg1);
		PrintToConsole(client, "%s cursor - Starts editing the entity you looking at", arg1);
	}
	return Plugin_Handled;
}

int GetWallId(int client, const char[] arg) {
	int id;
	if(StringToIntEx(arg, id) > 0 && id > 0 && id <= createdWalls.Length) {
		int entity = GetWallEntity(id);
		if(!IsValidEntity(entity)) {
			ReplyToCommand(client, "\x04[Editor]\x01 The wall with specified id no longer exists.");
			createdWalls.Erase(id - 1);
			return -2;
		}
		return id;
	} else {
		ReplyToCommand(client, "\x04[Editor]\x01 Invalid wall id, must be between 0 - %d", createdWalls.Length - 1 );
		return -1;
	}
}

int GetWallEntity(int id) {
	if(id <= 0 || id > createdWalls.Length) {
		ThrowError("Invalid wall id (%d)", id);
	}
	return createdWalls.Get(id - 1);
}

/// Tries to find the id of the  wall based off entity
int FindWallId(int entity) {
	for(int i = 1; i <= createdWalls.Length; i++) {
		int entRef = createdWalls.Get(i - 1);
		int ent = EntRefToEntIndex(entRef);
		if(ent == entity) {
			return i;
		}
	}
	return -1;
}

void GlowWall(int id, int glowColor[4], float lifetime = 5.0) {
	int ref = GetWallEntity(id);
	if(IsValidEntity(ref)) {
		float pos[3], mins[3], maxs[3], angles[3];
		GetEntPropVector(ref, Prop_Send, "m_angRotation", angles);
		GetEntPropVector(ref, Prop_Send, "m_vecOrigin", pos);
		GetEntPropVector(ref, Prop_Send, "m_vecMins", mins);
		GetEntPropVector(ref, Prop_Send, "m_vecMaxs", maxs);
		Effect_DrawBeamBoxRotatableToAll(pos, mins, maxs, angles, g_iLaserIndex, 0, 0, 30, lifetime, 0.4, 0.4, 0, 1.0, glowColor, 0);
	}
}

void DeleteWall(int id) {
	GlowWall(id, GLOW_RED);
	int ref = GetWallEntity(id);
	if(IsValidEntity(ref)) {
		RemoveEntity(ref);
	}
	createdWalls.Erase(id - 1);
}

 void Export(int client, const char[] expType, int entity, const float origin[3], const float angles[3], const float size[3]) {
	char sPath[PLATFORM_MAX_PATH];
	char currentMap[64];
	GetCurrentMap(currentMap, sizeof(currentMap));

	BuildPath(Path_SM, sPath, sizeof(sPath), "data/exports");
	CreateDirectory(sPath, 1406);
	BuildPath(Path_SM, sPath, sizeof(sPath), "data/exports/%s.cfg", currentMap);
	File file = OpenFile(sPath, "w");
	if(file == null) {
		PrintToServer("[Editor] Export: Cannot open \"%s\", cant write", sPath);
	}

	PrintWriteLine(client, file, "{");
	if(entity != INVALID_ENT_REFERENCE) {
		char model[64];
		GetEntPropString(entity, Prop_Data, "m_ModelName", model, sizeof(model));
		if(StrEqual(expType, "json")) {
			PrintWriteLine(client, file, "\t\"model\": \"%s\",", model);
		} else{
			PrintWriteLine(client, file, "\t\"model\"   \"%s\"", model);
		}
	}

	if(StrEqual(expType, "json")) {
		PrintWriteLine(client, file, "\t\"origin\": [%.2f, %.2f, %.2f],", origin[0], origin[1], origin[2]);
		PrintWriteLine(client, file, "\t\"angles\": [%.2f, %.2f, %.2f],", angles[0], angles[1], angles[2]);
		PrintWriteLine(client, file, "\t\"size\": [%.2f, %.2f, %.2f]", size[0], size[1], size[2]);
	} else {
		PrintWriteLine(client, file, "\t\"origin\" \"%.2f %.2f %.2f\"", origin[0], origin[1], origin[2]);
		PrintWriteLine(client, file, "\t\"angles\" \"%.2f %.2f %.2f\"", angles[0], angles[1], angles[2]);
		PrintWriteLine(client, file, "\t\"size\"   \"%.2f %.2f %.2f\"", size[0], size[1], size[2]);
	}
	PrintWriteLine(client, file, "}");
	delete file;
}

void PrintWriteLine(int client, File file, const char[] format, any ...) {
	char line[100];
	VFormat(line, sizeof(line), format, 4);	
	if(file != null)
		file.WriteLine(line);
	PrintToChat(client, line);
}