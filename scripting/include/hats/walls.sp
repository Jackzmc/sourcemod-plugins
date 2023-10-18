int BUILDER_COLOR[4] = { 0, 255, 0, 235 };
int WALL_COLOR[4] = { 255, 0, 0, 235 };
float ORIGIN_SIZE[3] = { 2.0, 2.0, 2.0 };

enum wallMode {
	INACTIVE = 0,
	MOVE_ORIGIN,
	SCALE,
	FREELOOK
}

ArrayList createdWalls;

enum struct WallBuilderData {
	float origin[3];
	float mins[3];
	float angles[3];
	float size[3];
	wallMode mode;
	int axis;
	int snapAngle;
	int moveSpeed;
	float moveDistance;
	int entity;
	bool canScale;
	bool hasCollision;
	bool isCopy;

	void Reset(bool initial = false) {
		this.isCopy = false;
		this.size[0] = this.size[1] = this.size[2] = 5.0;
		this.angles[0] = this.angles[1] = this.angles[2] = 0.0;
		this.axis = 1;
		this.canScale = true;
		this.moveDistance = 200.0;
		this.entity = INVALID_ENT_REFERENCE;
		this.hasCollision = true;
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
		if(!this.canScale && this.entity != INVALID_ENT_REFERENCE) {
			TeleportEntity(this.entity, this.origin, this.angles, NULL_VECTOR);
		} else {
			Effect_DrawBeamBoxRotatableToAll(this.origin, this.mins, this.size, this.angles, g_iLaserIndex, 0, 0, 30, lifetime, 0.4, 0.4, 0, amplitude, color, 0);
		}
		Effect_DrawAxisOfRotationToAll(this.origin, this.angles, ORIGIN_SIZE, g_iLaserIndex, 0, 0, 30, 0.2, 0.1, 0.1, 0, 0.0, 0);
	}

	bool CheckEntity(int client) {
		if(this.entity != INVALID_ENT_REFERENCE) {
			if(!IsValidEntity(this.entity)) {
				PrintToChat(client, "\x04[Hats]\x01 Entity has vanished, editing cancelled.");
				this.Reset();
				return false;
			}
		}
		return true;
	}

	bool IsActive() {
		return this.mode != INACTIVE;
	}

	void SetMode(wallMode mode) {
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
				if(this.canScale) {
					this.mode = SCALE;
					PrintToChat(client, "\x04[Hats]\x01 Mode: \x05Scale\x01 (Press \x04RELOAD\x01 to change mode)");
				} else {
					this.mode = FREELOOK;
					PrintToChat(client, "\x04[Hats]\x01 Mode: \x05Freelook\x01 (Press \x04RELOAD\x01 to change mode)");
				}
			}
			case SCALE: {
				this.mode = FREELOOK;
				PrintToChat(client, "\x04[Hats]\x01 Mode: \x05Freelook\x01 (Press \x04RELOAD\x01 to change mode)");
			}
			case FREELOOK: {
				this.mode = MOVE_ORIGIN;
				PrintToChat(client, "\x04[Hats]\x01 Mode: \x05Move & Rotate\x01 (Press \x04RELOAD\x01 to change mode)");
				// PrintToChat(client, "Hold \x04USE (E)\x01 to rotate, \x04WALK (SHIFT)\x01 to change speed");
			}
		}
		cmdThrottle[client] = tick;
	}

	void ToggleCollision(int client, float tick) {
		if(tick - cmdThrottle[client] <= 0.15) return;
		this.hasCollision = !this.hasCollision
		if(this.hasCollision)
			PrintToChat(client, "\x04[Hats]\x01 Collision: \x05ON\x01");
		else
			PrintToChat(client, "\x04[Hats]\x01 Collision: \x04OFF\x01");
		cmdThrottle[client] = tick;
	}

	void CycleAxis(int client, float tick) {
		if(tick - cmdThrottle[client] <= 0.15) return;
		if(this.axis == 0) {
			this.axis = 1;
			PrintToChat(client, "\x04[Hats]\x01 Rotate Axis: \x05HEADING (Y)\x01");
		} else if(this.axis == 1) {
			this.axis = 2;
			PrintToChat(client, "\x04[Hats]\x01 Rotate Axis: \x05PITCH (X)\x01");
		} else {
			this.axis = 0;
			PrintToChat(client, "\x04[Hats]\x01 Rotate Axis: \x05ROLL (Z)\x01");
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
			PrintToChat(client, "\x04[Hats]\x01 Rotate Snap Degrees: \x04(OFF)\x01", this.snapAngle);
		else
			PrintToChat(client, "\x04[Hats]\x01 Rotate Snap Degrees: \x05%d\x01", this.snapAngle);
		cmdThrottle[client] = tick;
	}

	void CycleSpeed(int client, float tick) {
		if(tick - cmdThrottle[client] <= 0.25) return;
		this.moveSpeed++;
		if(this.moveSpeed > 10) this.moveSpeed = 1;
		PrintToChat(client, "\x04[Hats]\x01 Scale Speed: \x05%d\x01", this.moveSpeed);
		// if(this.movetype == 0) {
		// 	this.movetype = 1;
		// 	PrintToChat(client, "\x04[SM]\x01 Move Type: \x05HEADING (Y)\x01");
		// } else {
		// 	this.movetype = 0;
		// 	PrintToChat(client, "\x04[SM]\x01 Rotate Axis: \x05PITCH (X)\x01");
		// }
		cmdThrottle[client] = tick;
	}

	int Build() {
		if(!this.canScale) {
			this.Reset();
			return -3;
		}
		// Don't need to build a new one if we editing:
		int blocker = this.entity;
		bool isEdit = false;
		if(blocker != INVALID_ENT_REFERENCE) {
			RemoveEntity(this.entity);
			isEdit = true;
		}
		blocker = CreateEntityByName("func_brush");
		if(blocker == -1) return -1;
		DispatchKeyValueVector(blocker, "mins", this.mins);
		DispatchKeyValueVector(blocker, "maxs", this.size);
		DispatchKeyValueVector(blocker, "boxmins", this.mins);
		DispatchKeyValueVector(blocker, "boxmaxs", this.size);

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
		if(!DispatchSpawn(blocker)) return -1;
		SetEntPropVector(blocker, Prop_Send, "m_vecMins", this.mins);
		SetEntPropVector(blocker, Prop_Send, "m_vecMaxs", this.size);
		SetEntProp(blocker, Prop_Send, "m_nSolidType", 2);
		int enteffects = GetEntProp(blocker, Prop_Send, "m_fEffects");
		enteffects |= 32; //EF_NODRAW
		SetEntProp(blocker, Prop_Send, "m_fEffects", enteffects); 
		AcceptEntityInput(blocker, "Enable");

		this.Draw(WALL_COLOR, 5.0, 1.0);
		this.Reset();
		return isEdit ? -2 : createdWalls.Push(EntIndexToEntRef(blocker));
	}

	int Copy() {
		if(this.entity == INVALID_ENT_REFERENCE) return -1;
		char classname[64];
		GetEntityClassname(this.entity, classname, sizeof(classname));

		int entity = CreateEntityByName(classname);
		PrintToServer("Created %s: %d", classname, entity);
		if(entity == -1) return -1;
		GetEntPropString(this.entity, Prop_Data, "m_ModelName", classname, sizeof(classname));
		DispatchKeyValueVector(entity, "origin", this.origin);
		DispatchKeyValue(entity, "solid", "6");
		DispatchKeyValue(entity, "model", classname);
		PrintToServer("Set model %s: %d", classname, entity);
		DispatchSpawn(entity);
		TeleportEntity(entity, this.origin, this.angles, NULL_VECTOR);
		this.entity = entity;
		this.isCopy = true;
		SetEntProp(entity, Prop_Send, "m_nSolidType", 2);
		return entity;
	}

	void Import(int entity, bool makeCopy = false, wallMode mode = SCALE) {
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
		if(this.isCopy) {
			RemoveEntity(this.entity);
		}
		this.SetMode(INACTIVE);
	}
}

WallBuilderData WallBuilder[MAXPLAYERS+1];


// TODO: Stacker, copy tool, new command?
public Action Command_MakeWall(int client, int args) {
	if(WallBuilder[client].IsActive()) {
		ReplyToCommand(client, "\x04[Hats]\x01 You are currently editing an entity. Finish editing your current entity with with \x05/edit done\x01 or cancel with \x04/edit cancel\x01");
	} else {
		WallBuilder[client].Reset();
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
		PrintToChat(client, "\x04[Hats]\x01 New Wall Started. End with \x05/wall build\x01 or \x04/wall cancel\x01");
		PrintToChat(client, "\x04[Hats]\x01 Mode: \x05Scale\x01");
	}
	return Plugin_Handled;
}

public Action Command_ManageWalls(int client, int args) {
	if(args == 0) {
		PrintToChat(client, "\x04[Hats]\x01 Created Walls: \x05%d\x01", createdWalls.Length);
		for(int i = 1; i <= createdWalls.Length; i++) {
			GlowWall(i, 20.0);
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

		int id = WallBuilder[client].Build();
		if(id == -1) {
			PrintToChat(client, "\x04[Hats]\x01 Wall Creation: \x04Error\x01");
		} else if(id == -2) {
			PrintToChat(client, "\x04[Hats]\x01 Wall Edit: \x04Complete\x01");
		} else if(id == -3) {
			PrintToChat(client, "\x04[Hats]\x01 Entity Edit: \x04Complete\x01");
		} else {
			PrintToChat(client, "\x04[Hats]\x01 Wall Creation: \x05Wall #%d Created\x01", id + 1);
		}
	} else if(StrEqual(arg1, "cancel")) {
		int flags = GetEntityFlags(client) & ~FL_FROZEN;
		SetEntityFlags(client, flags);
		WallBuilder[client].Cancel();
		PrintToChat(client, "\x04[Hats]\x01 Wall Creation: \x04Cancelled\x01");
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
				PrintToChat(client, "\x04[Hats]\x01 You are not editing any existing entity, use \x05/wall cancel\x01 to stop or \x05/wall delete <id/all>");
			} else if(entity > MaxClients) {
				RemoveEntity(entity);
				WallBuilder[client].Reset();
				PrintToChat(client, "\x04[Hats]\x01 Deleted current entity");
			} else {
				PrintToChat(client, "\x04[Hats]\x01 Cannot delete player entities.");
			}
		} else if(StrEqual(arg2, "all")) {
			int walls = createdWalls.Length;
			for(int i = 1; i <= createdWalls.Length; i++) {
				DeleteWall(i);
			}
			PrintToChat(client, "\x04[Hats]\x01 Deleted \x05%d\x01 Walls", walls);
		} else {
			int id = GetWallId(client, arg2);
			if(id > -1) {
				DeleteWall(id);
				PrintToChat(client, "\x04[Hats]\x01 Deleted Wall: \x05#%d\x01", id);
			}
		}
	} else if(StrEqual(arg1, "create")) {
		ReplyToCommand(client, "\x04[Hats]\x01 Syntax: /mkwall [size x] [size y] [size z]");
	} else if(StrEqual(arg1, "toggle")) {
		if(StrEqual(arg2, "all")) {
			int walls = createdWalls.Length;
			for(int i = 1; i <= createdWalls.Length; i++) {
				int entity = GetWallEntity(i);
				AcceptEntityInput(entity, "Toggle");
				GlowWall(i);
			}
			PrintToChat(client, "\x04[Hats]\x01 Toggled \x05%d\x01 walls", walls);
		} else {
			int id = GetWallId(client, arg2);
			if(id > -1) {
				int entity = GetWallEntity(id);
				AcceptEntityInput(entity, "Toggle");
				GlowWall(id);
				PrintToChat(client, "\x04[Hats]\x01 Toggled Wall: \x05#%d\x01", id);
			}
		}
	} else if(StrEqual(arg1, "filter")) {
		if(args < 3) {
			ReplyToCommand(client, "\x04[Hats]\x01 Syntax: \x05/walls filter <id/all> <filter type>\x04");
			ReplyToCommand(client, "\x04[Hats]\x01 Valid filters: \x05player");
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
			PrintToChat(client, "\x04[Hats]\x01 Set %d walls' filter to \x05%s\x01", walls, arg3);
		} else {
			int id = GetWallId(client, arg2);
			if(id > -1) {
				int entity = GetWallEntity(id);
				AcceptEntityInput(entity, "SetExcluded");
				PrintToChat(client, "\x04[Hats]\x01 Set wall #%d filter to \x05%s\x01", id, arg3);
			}
		}
	} else if(StrEqual(arg1, "edit")) {
		int id = GetWallId(client, arg2);
		if(id > -1) {
			int entity = GetWallEntity(id);
			WallBuilder[client].Import(entity);
			PrintToChat(client, "\x04[Hats]\x01 Editing wall \x05%d\x01. End with \x05/wall done\x01 or \x04/wall cancel\x01", id);
			PrintToChat(client, "\x04[Hats]\x01 Mode: \x05Scale\x01");
		}
	} else if(StrEqual(arg1, "edite") || (arg1[0] == 'c' && arg1[1] == 'u')) {
		int index = GetLookingEntity(client, Filter_ValidHats); //GetClientAimTarget(client, false);
		if(index > 0) {
			WallBuilder[client].Import(index, false, MOVE_ORIGIN);
			WallBuilder[client].canScale = false;	
			char classname[32];
			char targetname[32];
			GetEntityClassname(index, classname, sizeof(classname));
			GetEntPropString(index, Prop_Data, "m_target", targetname, sizeof(targetname));
			PrintToChat(client, "\x04[Hats]\x01 Editing entity \x05%d (%s) [%s]\x01. End with \x05/wall done\x01", index, classname, targetname);
			PrintToChat(client, "\x04[Hats]\x01 Mode: \x05Move & Rotate\x01");
		} else {
			ReplyToCommand(client, "\x04[Hats]\x01 Invalid or non existent entity");
		}
	} else if(StrEqual(arg1, "copy")) {
		if(WallBuilder[client].IsActive()) {
			int oldEntity = WallBuilder[client].entity;
			if(oldEntity == INVALID_ENT_REFERENCE) {
				PrintToChat(client, "\x04[Hats]\x01 Finish editing your wall first: \x05/wall done\x01 or \x04/wall cancel\x01");
			} else { 
				int entity = WallBuilder[client].Copy();
				PrintToChat(client, "\x04[Hats]\x01 Editing copy \x05%d\x01 of entity \x05%d\x01. End with \x05/edit done\x01 or \x04/edit cancel\x01", entity, oldEntity);
			}
		} else {
			int id = GetWallId(client, arg2);
			if(id > -1) {
				int entity = GetWallEntity(id);
				WallBuilder[client].Import(entity, true);
				GetCursorLimited(client, 100.0, WallBuilder[client].origin, Filter_IgnorePlayer);
				PrintToChat(client, "\x04[Hats]\x01 Editing copy of wall \x05%d\x01. End with \x05/wall build\x01 or \x04/wall cancel\x01", id);
				PrintToChat(client, "\x04[Hats]\x01 Mode: \x05Scale\x01");
			}
		}
	} else if(StrEqual(arg1, "list")) {
		for(int i = 1; i <= createdWalls.Length; i++) {
			int entity = GetWallEntity(i);
			ReplyToCommand(client, "Wall #%d - EntIndex: %d", i, EntRefToEntIndex(entity));
		}
	} else {
		ReplyToCommand(client, "\x04[Hats]\x01 See console for list of commands");
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
			ReplyToCommand(client, "\x04[Hats]\x01 The wall with specified id no longer exists.");
			createdWalls.Erase(id);
			return -2;
		}
		return id;
	} else {
		ReplyToCommand(client, "\x04[Hats]\x01 Invalid wall id, must be between 0 - %d", createdWalls.Length - 1 );
		return -1;
	}
}

int GetWallEntity(int id) {
	if(id <= 0 || id > createdWalls.Length) {
		ThrowError("Invalid wall id (%d)", id);
	}
	return createdWalls.Get(id - 1);
}

void GlowWall(int id, float lifetime = 5.0) {
	int ref = GetWallEntity(id);
	if(IsValidEntity(ref)) {
		float pos[3], mins[3], maxs[3], angles[3];
		GetEntPropVector(ref, Prop_Send, "m_angRotation", angles);
		GetEntPropVector(ref, Prop_Send, "m_vecOrigin", pos);
		GetEntPropVector(ref, Prop_Send, "m_vecMins", mins);
		GetEntPropVector(ref, Prop_Send, "m_vecMaxs", maxs);
		Effect_DrawBeamBoxRotatableToAll(pos, mins, maxs, angles, g_iLaserIndex, 0, 0, 30, lifetime, 0.4, 0.4, 0, 1.0, WALL_COLOR, 0);
	}
}

void DeleteWall(int id) {
	GlowWall(id);
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
		PrintToServer("[Hats] Export: Cannot open \"%s\", cant write", sPath);
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

enum struct WallModelSizeEntry {
	char name[32];
	char model[64]; 
}
enum struct WallModelEntry {
	char name[32];
	
	WallModelSizeEntry size1;
	WallModelSizeEntry size2;
	WallModelSizeEntry size3;
}
ArrayList wallModels;

void LoadModels() {
	if(wallModels != null) delete wallModels;
	wallModels = new ArrayList(sizeof(WallModelEntry));
	KeyValues kv = new KeyValues("WallData");

	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "data/walls_data.cfg");

	if(!FileExists(sPath) || !kv.ImportFromFile(sPath)) {
		delete kv;
		PrintToServer("[FTT] Could not load phrase list from data/walls_data.cfg");
		return;
	}
	// TODO: implement models to spawn
	// char name[32];
	// Go through all the words:
	// kv.GotoFirstSubKey();
	// int i = 0;
	// char buffer[4];
	// do {
	// 	kv.GetSectionName(name, sizeof(name));
	// 	for(;;) {
	// 		IntToString(++i, buffer, sizeof(buffer));
	// 		kv.GetString(buffer, phrase, MAX_PHRASE_LENGTH, "_null");
	// 		if(strcmp(phrase, "_null") == 0) break;
	// 		phrases.PushString(phrase);
	// 	}
	// 	i = 0;
	// 	if(StrEqual(word, "_full message phrases")) {
	// 		fullMessagePhraseList = phrases.Clone();
	// 		continue;
	// 	}
	// 	#if defined DEBUG_PHRASE_LOAD
	// 		PrintToServer("Loaded %d phrases for word \"%s\"", phrases.Length, word);
	// 	#endif
	// 	REPLACEMENT_PHRASES.SetValue(word, phrases.Clone(), true);
	// } while (kv.GotoNextKey(false));

	delete kv;
}
	   