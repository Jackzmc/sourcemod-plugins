enum hatFlags {
	HAT_NONE = 0,
	HAT_POCKET = 1,
	HAT_REVERSED = 2,
	HAT_COMMANDABLE = 4,
	HAT_RAINBOW = 8,
	HAT_PRESET = 16
}
enum struct HatInstance {
	int entity; // The entity REFERENCE
	int visibleEntity; // Thee visible entity REF
	Handle yeetGroundTimer;
	
	// Original data for entity
	float orgPos[3];
	float orgAng[3];
	float offset[3];
	float angles[3];
	int collisionGroup;
	int solidType;
	int moveType;
	
	float scale;
	int flags;
	float rainbowColor[3];
	int rainbowTicks;
	bool rainbowReverse;
	char attachPoint[32];
}
enum hatFeatures {
	HatConfig_None = 0,
	HatConfig_PlayerHats = 1,
	HatConfig_RespectAdminImmunity = 2,
	HatConfig_FakeHat = 4,
	HatConfig_NoSaferoomHats = 8,
	HatConfig_PlayerHatConsent = 16,
	HatConfig_InfectedHats = 32,
	HatConfig_ReversedHats = 64,
	HatConfig_DeleteThrownHats = 128
}
char ActivePreset[MAXPLAYERS+1][32];
int lastHatRequestTime[MAXPLAYERS+1];
HatInstance hatData[MAXPLAYERS+1];
StringMap g_HatPresets;

#define MAX_FORBIDDEN_CLASSNAMES 14
char FORBIDDEN_CLASSNAMES[MAX_FORBIDDEN_CLASSNAMES][] = {
	"prop_door_rotating_checkpoint",
	"env_physics_blocker",
	"env_player_blocker",
	"func_brush",
	"func_simpleladder",
	"prop_door_rotating",
	"func_button",
	"func_elevator",
	"func_button_timed",
	"func_tracktrain",
	"func_movelinear",
	// "infected",
	"func_lod",
	"func_door",
	"prop_ragdoll"
};

#define MAX_FORBIDDEN_MODELS 1
char FORBIDDEN_MODELS[MAX_FORBIDDEN_MODELS][] = {
	"models/props_vehicles/c130.mdl",
};

#define MAX_REVERSE_CLASSNAMES 2
// Classnames that should automatically trigger reverse infected
static char REVERSE_CLASSNAMES[MAX_REVERSE_CLASSNAMES][] = {
	"infected",
	"func_movelinear"
};

Action Command_DoAHat(int client, int args) {
	int hatter = GetHatter(client);
	if(hatter > 0) {
		ClearHat(hatter, HasFlag(hatter, HAT_REVERSED));
		PrintToChat(hatter, "[Hats] %N has unhatted themselves", client);
		return Plugin_Handled;
	}

	static char cmdName[8];
	GetCmdArg(0, cmdName, sizeof(cmdName));
	AdminId adminId = GetUserAdmin(client);
	bool isForced = adminId != INVALID_ADMIN_ID && StrEqual(cmdName, "sm_hatf");
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
		if(HasFlag(client, HAT_PRESET)) {
			PrintToChat(client, "[Hats] Your hat is a preset, use /hatp to remove it.");
			return Plugin_Handled;
		}
		char arg[4];
		GetCmdArg(1, arg, sizeof(arg));
		if(arg[0] == 'e') {
			ReplyToCommand(client, "\t\t\"origin\"\t\"%f %f %f\"", hatData[client].offset[0], hatData[client].offset[1], hatData[client].offset[2]);
			ReplyToCommand(client, "\t\t\"angles\"\t\"%f %f %f\"", hatData[client].angles[0], hatData[client].angles[1], hatData[client].angles[2]);
			return Plugin_Handled;
		} else if(arg[0] == 'v') {
			ReplyToCommand(client, "Flags: %d", hatData[client].flags);
			// ReplyToCommand(client, "CurOffset: %f %f %f", );
			return Plugin_Handled;
		} else if(arg[0] == 'a') {
			ShowAttachPointMenu(client);
			return Plugin_Handled;
		}
		// int orgEntity = entity;
		if(HasFlag(client, HAT_REVERSED)) {
			entity = client;
		}
		ClearParent(entity);

		if(arg[0] == 's') {
			char sizeStr[4];
			GetCmdArg(2, sizeStr, sizeof(sizeStr));
			float size = StringToFloat(sizeStr);
			if(size == 0.0) {
				ReplyToCommand(client, "[Hats] Invalid size");
				return Plugin_Handled;
			}
			if(HasEntProp(entity, Prop_Send, "m_flModelScale"))
				SetEntPropFloat(entity, Prop_Send, "m_flModelScale", size);
			else
				PrintHintText(client, "Hat does not support scaling");
			// Change the size of it's parent instead
			int child = -1;
			while((child = FindEntityByClassname(child, "*")) != INVALID_ENT_REFERENCE )
			{
				int parent = GetEntPropEnt(child, Prop_Data, "m_pParent");
				if(parent == entity) {
					if(HasEntProp(child, Prop_Send, "m_flModelScale")) {
						PrintToConsole(client, "found child %d for %d", child, entity);
						SetEntPropFloat(child, Prop_Send, "m_flModelScale", size);
					} else {
						PrintToChat(client, "Child %d for %d cannot be scaled", child, entity);
					}
					break;
				}
			}
			// Reattach entity:
			EquipHat(client, entity);
			return Plugin_Handled;
		} else if(arg[0] == 'r' && arg[1] == 'a') {
			SetFlag(client, HAT_RAINBOW);
			hatData[client].rainbowTicks = 0;
			hatData[client].rainbowReverse = false;
			hatData[client].rainbowColor[0] = 0.0;
			hatData[client].rainbowColor[1] = 255.0;
			hatData[client].rainbowColor[2] = 255.0;
			EquipHat(client, entity);
			ReplyToCommand(client, "Rainbow hats enabled");
			return Plugin_Handled;
		}

		// Re-enable physics and restore collision/solidity
		AcceptEntityInput(entity, "EnableMotion");
		SetEntProp(entity, Prop_Send, "m_CollisionGroup", hatData[client].collisionGroup);
		SetEntProp(entity, Prop_Send, "m_nSolidType", hatData[client].solidType);

		// Remove frozen flag (only "infected" and "witch" are frozen, but just incase:)
		int flags = GetEntityFlags(entity) & ~FL_FROZEN;
		SetEntityFlags(entity, flags);

		// Clear visible hats (HatConfig_FakeHat is enabled)
		int visibleEntity = EntRefToEntIndex(hatData[client].visibleEntity);
		SDKUnhook(entity, SDKHook_SetTransmit, OnRealTransmit);
		if(visibleEntity > 0) {
			SDKUnhook(visibleEntity, SDKHook_SetTransmit, OnVisibleTransmit);
			RemoveEntity(visibleEntity);
			hatData[client].visibleEntity = INVALID_ENT_REFERENCE;
		}
		// Grant temp god & remove after time
		tempGod[client] = true;
		if(client <= MaxClients) {
			SDKHook(client, SDKHook_OnTakeDamageAlive, OnTakeDamageAlive);
			CreateTimer(2.0, Timer_RemoveGod, GetClientUserId(client));
		}
		if(entity <= MaxClients) {
			SDKHook(entity, SDKHook_OnTakeDamageAlive, OnTakeDamageAlive);
			CreateTimer(2.0, Timer_RemoveGod, GetClientUserId(entity));
		}

		// Restore movement:
		if(entity <= MaxClients) {
			// If player, remove roll & and just default to WALK movetype
			hatData[client].orgAng[2] = 0.0;
			SetEntityMoveType(entity, MOVETYPE_WALK);
		} else {
			// If not player, then just use whatever they were pre-hat
			SetEntProp(entity, Prop_Send, "movetype", hatData[client].moveType);
		}

		if(arg[0] == 'y') { // Hat yeeting:
			char classname[16];
			GetEntityClassname(entity, classname, sizeof(classname));
			if(StrEqual(classname, "prop_dynamic")) {
				ReplyToCommand(client, "You cannot yeet this prop (it has no physics)");
				return Plugin_Handled;
			}
			GetClientEyeAngles(client, hatData[client].orgAng);
			GetClientAbsOrigin(client, hatData[client].orgPos);
			hatData[client].orgPos[2] += 45.0;
			float ang[3], vel[3];
			
			// Calculate the angle to throw at
			GetClientEyeAngles(client, ang);
			ang[2] = 0.0;
			if(ang[0] > 0.0) ang[0] = -ang[0];
			// ang[0] = -45.0;

			// Calculate velocity to throw based on direction
			vel[0] = Cosine(DegToRad(ang[1])) * GetRandomFloat(1300.0, 1700.0);
			vel[1] = Sine(DegToRad(ang[1])) * GetRandomFloat(1300.0, 1700.0);
			vel[2] = GetRandomFloat(700.0, 900.0);
			if(entity <= MaxClients) {
				// For players, use the built in fling function
				TeleportEntity(entity, hatData[client].orgPos, hatData[client].orgAng, NULL_VECTOR);
				L4D2_CTerrorPlayer_Fling(entity, client, vel);
			} /*else if(visibleEntity > 0) {
				PrintToChat(client, "Yeeting fake car...");
				ClearParent(visibleEntity);

				SetEntProp(visibleEntity, Prop_Send, "movetype", 6);

				AcceptEntityInput(visibleEntity, "EnableMotion");

				TeleportEntity(entity, OUT_OF_BOUNDS, hatData[client].orgAng, NULL_VECTOR);
				TeleportEntity(visibleEntity, hatData[client].orgPos, hatData[client].orgAng, vel);
				DataPack pack;
				CreateDataTimer(4.0, Timer_PropYeetEnd, pack);
				pack.WriteCell(hatData[client].entity);
				pack.WriteCell(hatData[client].visibleEntity);
				pack.WriteCell(hatData[client].collisionGroup);
				pack.WriteCell(hatData[client].solidType);
				pack.WriteCell(hatData[client].moveType);
				hatData[client].visibleEntity = INVALID_ENT_REFERENCE;
				hatData[client].entity = INVALID_ENT_REFERENCE;
			} */ else {
				// For actual props, offset it 35 units above and 80 units infront to reduce collision-incaps and then throw
				GetHorizontalPositionFromClient(client, 80.0, hatData[client].orgPos);
				hatData[client].orgPos[2] += 35.0;
				TeleportEntity(entity, hatData[client].orgPos, hatData[client].orgAng, vel);
				// Sleep the physics after enoug time for it to most likely have landed
				if(hatData[client].yeetGroundTimer != null) {
					// TODO: FIX null issue
					delete hatData[client].yeetGroundTimer;
				}
				DataPack pack1;
				hatData[client].yeetGroundTimer = CreateDataTimer(0.5, Timer_GroundKill, pack1, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
				pack1.WriteCell(hatData[client].entity);
				pack1.WriteCell(GetClientUserId(client));
				DataPack pack2;
				CreateDataTimer(7.7, Timer_PropSleep, pack2);
				pack2.WriteCell(hatData[client].entity);
				pack2.WriteCell(GetClientUserId(client));
			}
			PrintToChat(client, "[Hats] Yeeted hat");
			hatData[client].entity = INVALID_ENT_REFERENCE;
			return Plugin_Handled;
		} else if(arg[0] == 'c') {
			float pos[3];
			// Grabs a cursor position with some checks to prevent placing into (in)visible walls
			if(GetSmartCursorLocation(client, pos)) {
				if(CanHatBePlaced(client, pos)) {
					if(entity <= MaxClients)
						L4D_WarpToValidPositionIfStuck(entity);
					hatData[client].orgPos = pos;
					TeleportEntity(entity, hatData[client].orgPos, hatData[client].orgAng, NULL_VECTOR);
					PrintToChat(client, "[Hats] Placed hat on cursor.");
				}
			} else {
				PrintToChat(client, "[Hats] Could not find cursor position.");
			}
		} else if(arg[0] == 'p' || (entity <= MaxClients && arg[0] != 'r')) {
			// Place the hat down on the cursor if specified OR if entity is hat
			float pos[3], ang[3];
			if(HasFlag(client, HAT_REVERSED)) {
				// If we are reversed, then place ourselves where our "hatter" is
				GetClientEyePosition(entity, hatData[client].orgPos);
				GetClientEyeAngles(entity, hatData[client].orgAng);
				TeleportEntity(client, hatData[client].orgPos, hatData[client].orgAng, NULL_VECTOR);
				PrintToChat(entity, "[Hats] Placed hat in front of you.");
			} else {
				// If we are normal, then get position infront of us, offset by model size
				GetClientEyePosition(client, pos);
				GetClientEyeAngles(client, ang);
				GetHorizontalPositionFromOrigin(pos, ang, 80.0, pos);
				ang[0] = 0.0;
				float mins[3];
				GetEntPropVector(entity, Prop_Data, "m_vecMins", mins);
				pos[2] += mins[2]; 
				// Find the nearest ground (raytrace bottom->up)
				FindGround(pos, pos);
				// Check if the destination is acceptable (not saferooms if enabled)
				if(CanHatBePlaced(client, pos)) {
					hatData[client].orgPos = pos;
					hatData[client].orgAng = ang;
					TeleportEntity(entity, hatData[client].orgPos, hatData[client].orgAng, NULL_VECTOR);
					PrintToChat(client, "[Hats] Placed hat in front of you.");
				}
			}
		} else if(arg[0] == 'd') {
			// Use the new wall editor
			Editor[client].Reset();
			Editor[client].entity = EntIndexToEntRef(entity);
			Editor[client].SetMode(MOVE_ORIGIN);
			PrintToChat(client, "\x04[Hats] \x01Beta Prop Mover active for \x04%d", entity);
		} else {
			PrintToChat(client, "[Hats] Restored hat to its original position.");
		}

		// Restore the scale pre-hat
		if(hatData[client].scale > 0 && HasEntProp(entity, Prop_Send, "m_flModelScale"))
			SetEntPropFloat(entity, Prop_Send, "m_flModelScale", hatData[client].scale);

		// If no other options performed, then restore to original position and remove our reference
		AcceptEntityInput(entity, "Sleep");
		TeleportEntity(entity, hatData[client].orgPos, hatData[client].orgAng, NULL_VECTOR);
		hatData[client].entity = INVALID_ENT_REFERENCE;
	} else {
		// Find a new hatable entity
		int flags = 0;
		entity = GetLookingEntity(client, Filter_ValidHats);
		if(entity <= 0) {
			PrintCenterText(client, "[Hats] No entity found");
			return Plugin_Handled;
		} else if(entity == EntRefToEntIndex(Editor[client].entity)) {
			// Prevent making an entity you editing a hat
			return Plugin_Handled;
		} else if(!isForced && cvar_sm_hats_max_distance.FloatValue > 0.0 && entity >= MaxClients) {
			float posP[3], posE[3];
			GetClientEyePosition(client, posP);
			GetEntPropVector(entity, Prop_Data, "m_vecOrigin", posE);
			if(GetVectorDistance(posP, posE) > cvar_sm_hats_max_distance.FloatValue) {
				PrintCenterText(client, "[Hats] Entity too far away");
				return Plugin_Handled;
			}
		}

		// Make hat reversed if 'r' passed in
		char arg[4];
		if(args > 0) {
			GetCmdArg(1, arg, sizeof(arg));
			if(arg[0] == 'r') {
				flags |= view_as<int>(HAT_REVERSED);
			}
		}

		int parent = GetEntPropEnt(entity, Prop_Data, "m_hParent");
		if(parent > 0 && entity > MaxClients) {
			PrintToConsole(client, "[Hats] Selected a child entity, selecting parent (child %d -> parent %d)", entity, parent);
			entity = parent;
		} else if(entity <= MaxClients) { // Checks for hatting a player entity
			if(IsFakeClient(entity) && L4D_GetIdlePlayerOfBot(entity) > 0) {
				PrintToChat(client, "[Hats] Cannot hat idle bots");
				return Plugin_Handled;
			} else if(!isForced && GetClientTeam(entity) != 2 && ~cvar_sm_hats_flags.IntValue & view_as<int>(HatConfig_InfectedHats)) {
				PrintToChat(client, "[Hats] Cannot make enemy a hat... it's dangerous");
				return Plugin_Handled;
			} else if(entity == EntRefToEntIndex(Editor[client].entity)) {
				// Old check left in in case you hatting child entity
				PrintToChat(client, "[Hats] You are currently editing this entity");
				return Plugin_Handled;
			} else if(inSaferoom[client] && cvar_sm_hats_flags.IntValue & view_as<int>(HatConfig_NoSaferoomHats)) {
				PrintToChat(client, "[Hats] Hats are not allowed in the saferoom");
				return Plugin_Handled;
			} else if(!IsPlayerAlive(entity) || GetEntProp(entity, Prop_Send, "m_isHangingFromLedge") || L4D_IsPlayerCapped(entity)) {
				PrintToChat(client, "[Hats] Player is either dead, hanging, or in the process of dying.");
				return Plugin_Handled;
			} else if(EntRefToEntIndex(hatData[entity].entity) == entity || EntRefToEntIndex(hatData[entity].entity) == client) {
				PrintToChat(client, "[Hats] Woah you can't be making a black hole, jesus be careful.");
				return Plugin_Handled;
			} else if(~cvar_sm_hats_flags.IntValue & view_as<int>(HatConfig_PlayerHats)) {
				PrintToChat(client, "[Hats] Player hats are disabled");
				return Plugin_Handled;
			} else if(!CanTarget(entity)) {
				PrintToChat(client, "[Hats] Player has disabled player hats for themselves.");
				return Plugin_Handled;
			} else if(!CanTarget(client)) {
				PrintToChat(client, "[Hats] Cannot hat a player when you have player hats turned off");
				return Plugin_Handled;
			} else if(cvar_sm_hats_flags.IntValue & view_as<int>(HatConfig_RespectAdminImmunity)) {
				AdminId targetAdmin = GetUserAdmin(entity);
				AdminId clientAdmin = GetUserAdmin(client);
				if(targetAdmin != INVALID_ADMIN_ID && clientAdmin == INVALID_ADMIN_ID) {
					PrintToChat(client, "[Hats] Cannot target an admin");
					return Plugin_Handled;
				} else if(targetAdmin != INVALID_ADMIN_ID && targetAdmin.ImmunityLevel > clientAdmin.ImmunityLevel) {
					PrintToChat(client, "[Hats] Cannot target %N, they are immune to you", entity);
					return Plugin_Handled;
				}
			}
			if(!isForced &&
				!IsFakeClient(entity) && 
				cvar_sm_hats_flags.IntValue & view_as<int>(HatConfig_PlayerHatConsent) && 
				~flags & view_as<int>(HAT_REVERSED)
			) {
				int lastRequestDiff = GetTime() - lastHatRequestTime[client];
				if(lastRequestDiff < PLAYER_HAT_REQUEST_COOLDOWN) {
					PrintToChat(client, "[Hats] Player hat under %d seconds cooldown", PLAYER_HAT_REQUEST_COOLDOWN - lastRequestDiff);
					return Plugin_Handled;
				}

				Menu menu = new Menu(HatConsentHandler);
				menu.SetTitle("%N: Requests to hat you", client);
				char id[8];
				Format(id, sizeof(id), "%d|1", GetClientUserId(client));
				menu.AddItem(id, "Accept");
				Format(id, sizeof(id), "%d|0", GetClientUserId(client));
				menu.AddItem(id, "Reject");
				menu.Display(entity, 12);
				PrintHintText(client, "Sent hat request to %N", entity);
				PrintToChat(entity, "[Hats] %N requests to hat you, 1 to Accept, 2 to Reject. Expires in 12 seconds.", client);
				return Plugin_Handled;
			}
		}


		char classname[64];
		GetEntityClassname(entity, classname, sizeof(classname));

		// Check for any class that should always be reversed
		if(~flags & view_as<int>(HAT_REVERSED)) {
			for(int i = 0; i < MAX_REVERSE_CLASSNAMES; i++) {
				if(StrEqual(REVERSE_CLASSNAMES[i], classname)) {
					flags |= view_as<int>(HAT_REVERSED);
					break;
				}
			}
		}

		EquipHat(client, entity, classname, flags);
	}
	return Plugin_Handled;
}


#define MAX_ATTACHMENT_POINTS 20
char ATTACHMENT_POINTS[MAX_ATTACHMENT_POINTS][] = {
	"eyes",
	"molotov",
	"pills",
	"grenade",
	"primary",
	"medkit",
	"melee",
	"survivor_light",
	"bleedout",
	"forward",
	"survivor_neck",
	"muzzle_flash",
	"spine",
	"legL",
	"legR",
	"thighL",
	"thighR",
	"lfoot",
	"rfoot",
	"mouth",
};

void ShowAttachPointMenu(int client) { 
	Menu menu = new Menu(AttachPointHandler);
	menu.SetTitle("Choose an attach point");
	for(int i = 0; i < MAX_ATTACHMENT_POINTS; i++) {
		menu.AddItem(ATTACHMENT_POINTS[i], ATTACHMENT_POINTS[i]);
	}
	menu.Display(client, 0);
}

int AttachPointHandler(Menu menu, MenuAction action, int client, int param2) {
	if (action == MenuAction_Select) {
		char attachPoint[32];
		menu.GetItem(param2, attachPoint, sizeof(attachPoint));
		if(!HasHat(client)) {
			ReplyToCommand(client, "No hat is equipped");
		} else { 
			int hat = GetHat(client);
			char classname[32];
			GetEntityClassname(hat, classname, sizeof(classname));
			EquipHat(client, hat, classname, hatData[client].flags, attachPoint);
			CReplyToCommand(client, "Attachment point set to {olive}%s", attachPoint);
		}
	} else if (action == MenuAction_End)	
		delete menu;
	return 0;
}

// Handles consent that a person to be hatted by another player
int HatConsentHandler(Menu menu, MenuAction action, int target, int param2) {
	if (action == MenuAction_Select) {
		char info[8];
		menu.GetItem(param2, info, sizeof(info));
		char str[2][8];
		ExplodeString(info, "|", str, 2, 8, false);
		int activator = GetClientOfUserId(StringToInt(str[0]));
		int hatAction = StringToInt(str[1]);
		if(activator == 0) {
			ReplyToCommand(target, "Player has disconnected");
			return 0;
		} else if(hatAction == 1) {
			if(EntRefToEntIndex(hatData[target].entity) == activator )
				PrintToChat(activator, "[Hats] Woah you can't be making a black hole, jesus be careful.");
			else
				EquipHat(activator, target, "player", 0);
		} else {
			ClientCommand(activator, "play player/orch_hit_csharp_short.wav");
			PrintHintText(activator, "%N refused your request", target);
			lastHatRequestTime[activator] = GetTime();
		}
	} else if (action == MenuAction_End)	
		delete menu;
	return 0;
}

bool IsHatsEnabled(int client) {
	return (cvar_sm_hats_enabled.IntValue == 1 && GetUserAdmin(client) != INVALID_ADMIN_ID) || cvar_sm_hats_enabled.IntValue == 2
}

void ClearHats() {
	for(int i = 1; i <= MaxClients; i++) {
		if(HasHat(i)) {
			ClearHat(i, false);
		}
		if(IsClientConnected(i) && IsClientInGame(i)) SetEntityMoveType(i, MOVETYPE_WALK);
	}
}
void ClearHat(int i, bool restore = false) {
	
	int entity = EntRefToEntIndex(hatData[i].entity);
	int visibleEntity = EntRefToEntIndex(hatData[i].visibleEntity);
	int modifyEntity = HasFlag(i, HAT_REVERSED) ? i : entity;
	
	if(visibleEntity > 0) {
		SDKUnhook(visibleEntity, SDKHook_SetTransmit, OnVisibleTransmit);
		RemoveEntity(visibleEntity);
	}
	if(modifyEntity > 0) {
		SDKUnhook(modifyEntity, SDKHook_SetTransmit, OnRealTransmit);
		ClearParent(modifyEntity);
	} else {
		return;
	}
	
	int flags = GetEntityFlags(entity) & ~FL_FROZEN;
	SetEntityFlags(entity, flags);
	// if(HasEntProp(entity, Prop_Send, "m_flModelScale"))
		// SetEntPropFloat(entity, Prop_Send, "m_flModelScale", 1.0);
	SetEntProp(modifyEntity, Prop_Send, "m_CollisionGroup", hatData[i].collisionGroup);
	// SetEntProp(modifyEntity, Prop_Send, "m_nSolidType", hatData[i].solidType);
	SetEntProp(modifyEntity, Prop_Send, "movetype", hatData[i].moveType);

	hatData[i].entity = INVALID_ENT_REFERENCE;
	hatData[i].visibleEntity = INVALID_ENT_REFERENCE;

	if(HasFlag(i, HAT_REVERSED)) {
		entity = i;
		i = modifyEntity;
	}

	if(entity <= MAXPLAYERS) {
		AcceptEntityInput(entity, "EnableLedgeHang");
	}
	if(restore) {
		// If hat is a player, override original position to hat wearer's
		if(entity <= MAXPLAYERS && HasEntProp(i, Prop_Send, "m_vecOrigin")) {
			GetEntPropVector(i, Prop_Send, "m_vecOrigin", hatData[i].orgPos);
		}
		// Restore to original position
		if(HasFlag(i, HAT_REVERSED)) {
			TeleportEntity(i, hatData[i].orgPos, hatData[i].orgAng, NULL_VECTOR);
		} else {
			TeleportEntity(entity, hatData[i].orgPos, hatData[i].orgAng, NULL_VECTOR);
		}
	}
}

bool HasHat(int client) {
	return GetHat(client) > 0;
}

int GetHat(int client) {
	if(hatData[client].entity == INVALID_ENT_REFERENCE) return -1;
	int index = EntRefToEntIndex(hatData[client].entity);
	if(index <= 0) return -1;
	if(!IsValidEntity(index)) return -1;
	return index; 
}

int GetHatter(int client) {
	for(int i = 1; i <= MaxClients; i++) {
		if(EntRefToEntIndex(hatData[i].entity) == client) {
			return i;
		}
	}
	return -1;
}

bool CanTarget(int victim) {
	static char buf[2];
	noHatVictimCookie.Get(victim, buf, sizeof(buf));
	return StringToInt(buf) == 0;
}

bool IsHatAllowedInSaferoom(int client) {
	if(L4D_IsMissionFinalMap()) return true;
	if(HasFlag(client, HAT_PRESET)) return true;
	char name[32];
	GetEntityClassname(hatData[client].entity, name, sizeof(name));
	// Don't allow non-weapons in saferoom
	if(StrEqual(name, "prop_physics") || StrEqual(name, "prop_dynamic")) {
		GetEntPropString(hatData[client].entity, Prop_Data, "m_ModelName", name, sizeof(name));
		if(StrContains(name, "gnome") != -1 || StrContains(name, "propanecanist") != -1) {
			return true;
		}
		float mins[3], maxs[3];
		GetEntPropVector(hatData[client].entity, Prop_Data, "m_vecMins", mins);
		GetEntPropVector(hatData[client].entity, Prop_Data, "m_vecMaxs", maxs);
		PrintToConsoleAll("Dropping hat for %N: prop_something (%s) (min %.0f,%.0f,%.0f) (max %.0f,%.0f,%.0f)", client, name, mins[0], mins[1], mins[2], maxs[0], maxs[1], maxs[2]);
		return false;
	} else if(StrEqual(name, "player") || StrContains(name, "weapon_") > -1 || StrContains(name, "upgrade_") > -1) {
		return true;
	}
	PrintToConsole(client, "Dropping hat: %s", name);
	return false;
}

bool IsHatAllowed(int client) {
	char name[32];
	GetEntityClassname(hatData[client].entity, name, sizeof(name));
	if(StrEqual(name, "prop_physics") || StrEqual(name, "prop_dynamic")) {
		GetEntPropString(hatData[client].entity, Prop_Data, "m_ModelName", name, sizeof(name));
		if(StrContains(name, "models/props_vehicles/c130.mdl") != -1) {
			return false;
		}
	}
	return true;
}

bool CanHatBePlaced(int client, const float pos[3]) {
	if(cvar_sm_hats_flags.IntValue & view_as<int>(HatConfig_NoSaferoomHats)) {
		if(IsHatAllowedInSaferoom(client)) return true;
		Address nav = L4D_GetNearestNavArea(pos, 200.0);
		if(nav != Address_Null) {
			int spawnFlags = L4D_GetNavArea_SpawnAttributes(nav) ;
			if(spawnFlags & NAV_SPAWN_CHECKPOINT) {
				PrintToServer("\"%L\" tried to place hat in saferoom, denied.", client);
				PrintToChat(client, "[Hats] Hat is not allowed in saferoom and has been returned.");
				return false;
			}
		}
	}
	return true;
}

void SetFlag(int client, hatFlags flag) {
	hatData[client].flags |= view_as<int>(flag);
}

bool HasFlag(int client, hatFlags flag) {
	return hatData[client].flags & view_as<int>(flag) != 0;
}

void EquipHat(int client, int entity, const char[] classname = "", int flags = HAT_NONE, const char[] attachPoint = "eyes") {
	if(HasHat(client))
		ClearHat(client, true);

	// Player specific tweaks
	int visibleEntity;
	if(entity == 0) {
		ThrowError("Attempted to equip world (client = %d)", client);
		return;
	}

	hatData[client].entity = EntIndexToEntRef(entity);
	int modifyEntity = HasFlag(client, HAT_REVERSED) ? client : entity;
	hatData[client].collisionGroup = GetEntProp(modifyEntity, Prop_Send, "m_CollisionGroup");
	hatData[client].solidType = GetEntProp(modifyEntity, Prop_Send, "m_nSolidType");
	hatData[client].moveType = GetEntProp(modifyEntity, Prop_Send, "movetype");
	strcopy(hatData[client].attachPoint, 32, attachPoint);

	if(client <= MaxClients) SDKHook(client, SDKHook_OnTakeDamageAlive, OnTakeDamageAlive);
	if(entity <= MaxClients) SDKHook(entity, SDKHook_OnTakeDamageAlive, OnTakeDamageAlive);
	
	if(modifyEntity <= MaxClients) {
		AcceptEntityInput(modifyEntity, "DisableLedgeHang");
	} else if(cvar_sm_hats_flags.IntValue & view_as<int>(HatConfig_FakeHat)) {
		return;
		// char model[64];
		// GetEntPropString(entity, Prop_Data, "m_ModelName", model, sizeof(model));
		// visibleEntity = CreateEntityByName("prop_dynamic");
		// DispatchKeyValue(visibleEntity, "model", model);
		// DispatchKeyValue(visibleEntity, "disableshadows", "1");
		// DispatchSpawn(visibleEntity);
		// SetEntProp(visibleEntity, Prop_Send, "m_CollisionGroup", 1);
		// hatData[client].visibleEntity = EntIndexToEntRef(visibleEntity);
		// SDKHook(visibleEntity, SDKHook_SetTransmit, OnVisibleTransmit);
		// SDKHook(entity, SDKHook_SetTransmit, OnRealTransmit);
	}
	SDKHook(client, SDKHook_OnTakeDamageAlive, OnTakeDamageAlive);
	// Temp remove the hat to be yoinked by another player
	for(int i = 1; i <= MaxClients; i++) {
		if(i != client && EntRefToEntIndex(hatData[i].entity) == entity) {
			ClearHat(i);
		}
	}

	// Called on initial hat
	if(classname[0] != '\0') {
		if(entity <= MaxClients && !IsFakeClient(entity)) {
			PrintToChat(entity, "[Hats] %N has hatted you, type /hat to dismount at any time", client);
		}
		
		// Reset things:
		hatData[client].flags = 0;
		hatData[client].offset[0] = hatData[client].offset[1] = hatData[client].offset[2] = 0.0;
		hatData[client].angles[0] = hatData[client].angles[1] = hatData[client].angles[2] = 0.0;

		if(flags & view_as<int>(HAT_PRESET)) {
			hatData[client].flags |= view_as<int>(HAT_PRESET);
		}

		if(modifyEntity <= MaxClients) {
			if(HasFlag(client, HAT_REVERSED)) {
				hatData[client].offset[2] += 7.2;
			} else {
				hatData[client].offset[2] += 4.2;
			}
		} else {
			float mins[3], maxs[3];
			GetEntPropVector(modifyEntity, Prop_Send, "m_vecMaxs", maxs);
			GetEntPropVector(modifyEntity, Prop_Send, "m_vecMins", mins);
			PrintToServer("%s mins: %f height:%f", classname, mins[2], maxs[2] - mins[2]);
			if(StrContains(classname, "weapon_molotov") > -1 || StrContains(classname, "weapon_pipe_bomb") > -1 || StrContains(classname, "weapon_vomitjar") > -1) {
				hatData[client].offset[2] += 10.0 + 1.0;
			} else {
				hatData[client].offset[2] += 10.0 + mins[2];
			}
		}

		if(cvar_sm_hats_flags.IntValue & view_as<int>(HatConfig_ReversedHats) && flags & view_as<int>(HAT_REVERSED)) {
			SetFlag(client, HAT_REVERSED);
			if(StrEqual(classname, "infected") || (entity <= MaxClients && IsFakeClient(entity))) {
				SetFlag(client, HAT_COMMANDABLE);
			}
			PrintToChat(client, "[Hats] Set yourself as %s (%d)'s hat", classname, entity);
			if(entity <= MaxClients) {
				LogAction(client, entity, "\"%L\" made themselves \"%L\" (%s)'s hat (%d, %d)", client, entity, classname, entity, visibleEntity);
				PrintToChat(entity, "[Hats] %N has set themselves as your hat", client);
			}
		} else {
			// TODO: freeze tank
			if(StrEqual(classname, "infected") || StrEqual(classname, "witch") || (entity <= MaxClients && GetClientTeam(entity) == 3 && L4D2_GetPlayerZombieClass(entity) == L4D2ZombieClass_Tank)) {
				int eflags = GetEntityFlags(entity) | FL_FROZEN;
				SetEntityFlags(entity, eflags);
				hatData[client].offset[2] = 36.0;
			}
			if(entity <= MaxClients)
				PrintToChat(client, "[Hats] Set %N (%d) as a hat", entity, entity);
			else
				PrintToChat(client, "[Hats] Set %s (%d) as a hat", classname, entity);
			if(entity <= MaxClients)
				LogAction(client, entity, "\"%L\" picked up \"%L\" (%s) as a hat (%d, %d)", client, entity, classname, entity, visibleEntity);
			else
				LogAction(client, -1, "\"%L\" picked up %s as a hat (%d, %d)", client, classname, entity, visibleEntity);
		}
		hatData[client].scale = -1.0;

	}
	AcceptEntityInput(modifyEntity, "DisableMotion");

	// Get the data (position, angle, movement shit)

	GetEntPropVector(modifyEntity, Prop_Send, "m_vecOrigin", hatData[client].orgPos);
	GetEntPropVector(modifyEntity, Prop_Send, "m_angRotation", hatData[client].orgAng);
	hatData[client].collisionGroup = GetEntProp(modifyEntity, Prop_Send, "m_CollisionGroup");
	hatData[client].solidType = GetEntProp(modifyEntity, Prop_Send, "m_nSolidType");
	hatData[client].moveType = GetEntProp(modifyEntity, Prop_Send, "movetype");
	

	if(!HasFlag(client, HAT_POCKET)) {
		// TeleportEntity(entity, EMPTY_ANG, EMPTY_ANG, NULL_VECTOR);
		if(HasFlag(client, HAT_REVERSED)) {
			SetParent(client, entity);
			if(StrEqual(classname, "infected")) {
				SetParentAttachment(modifyEntity, "head", true);
				TeleportEntity(modifyEntity, hatData[client].offset, hatData[client].angles, NULL_VECTOR);
				SetParentAttachment(modifyEntity, "head", true);
			} else {
				SetParentAttachment(modifyEntity, attachPoint, true);
				TeleportEntity(modifyEntity, hatData[client].offset, hatData[client].angles, NULL_VECTOR);
				SetParentAttachment(modifyEntity, attachPoint, true);
			}
			
			if(HasFlag(client, HAT_COMMANDABLE)) {
				ChooseRandomPosition(hatData[client].offset);
				L4D2_CommandABot(entity, client, BOT_CMD_MOVE, hatData[client].offset);
			}
		} else {
			SetParent(entity, client);
			SetParentAttachment(modifyEntity, attachPoint, true);
			TeleportEntity(modifyEntity, hatData[client].offset, hatData[client].angles, NULL_VECTOR);
			SetParentAttachment(modifyEntity, attachPoint, true);
		}

		if(visibleEntity > 0) {
			SetParent(visibleEntity, client);
			SetParentAttachment(visibleEntity, attachPoint, true);
			hatData[client].offset[2] += 10.0;
			TeleportEntity(visibleEntity, hatData[client].offset, hatData[client].angles, NULL_VECTOR);
			SetParentAttachment(visibleEntity, attachPoint, true);
			#if defined DEBUG_HAT_SHOW_FAKE
			L4D2_SetEntityGlow(visibleEntity, L4D2Glow_Constant, 0, 0, color2, false);
			#endif
		}

		#if defined DEBUG_HAT_SHOW_FAKE
		L4D2_SetEntityGlow(modifyEntity, L4D2Glow_Constant, 0, 0, color, false);
		#endif

		// SetEntProp(modifyEntity, Prop_Send, "m_nSolidType", 0);
		SetEntProp(modifyEntity, Prop_Send, "m_CollisionGroup", 1);
		SetEntProp(modifyEntity, Prop_Send, "movetype", MOVETYPE_NONE);
	}
}
