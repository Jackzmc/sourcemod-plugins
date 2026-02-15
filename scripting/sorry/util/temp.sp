Handle TempSetModel(int entity, float duration, const char[] model) {
	char orgModel[128];
	GetEntPropString(entity, Prop_Data, "m_ModelName", orgModel, sizeof(orgModel));
	int survivorType = - 1;
	if(entity <= MaxClients && GetClientTeam(entity) == 2) survivorType = GetEntProp(entity, Prop_Send, "m_survivorCharacter");
	SetEntityModel(entity, model);

	DataPack pack;
	Handle handle = CreateDataTimer(duration, _timer_ClearTempModel, pack);
	pack.WriteCell(EntIndexToEntRef(entity));
	pack.WriteCell(survivorType);
	pack.WriteString(orgModel);
	return handle;
}
static Action _timer_ClearTempModel(Handle h, DataPack pack) {
	pack.Reset();
	int entity = EntRefToEntIndex(pack.ReadCell());
	if(entity > 0) {
		int survivorType = pack.ReadCell();

		char model[128];
		pack.ReadString(model, sizeof(model));
		SetEntityModel(entity, model);

		if(entity < MaxClients) {
			DataPack pack2 = new DataPack();
			pack2.WriteCell(GetClientUserId(entity));
			float nullPos[3];
			bool dualWield = false;
			for(int slot = 0; slot <= 4; slot++) {
				int weapon = _AddWeaponSlot(entity, slot, pack2);
				if(weapon > 0) {
					if(slot == 1 && HasEntProp(weapon, Prop_Send, "m_isDualWielding")) {
						dualWield = GetEntProp(weapon, Prop_Send, "m_isDualWielding") == 1;
						SetEntProp(weapon, Prop_Send, "m_isDualWielding", 0); 
					}
					SDKHooks_DropWeapon(entity, weapon, NULL_VECTOR);
					TeleportEntity(weapon, nullPos);
				}
			}
			pack2.WriteCell(dualWield);
			CreateTimer(0.1, _timer_RequipWeapon, pack2);
		}

		if(survivorType != -1) {
			SetEntProp(entity, Prop_Send, "m_survivorCharacter", survivorType);
		}
	}
	return Plugin_Continue;
}
static int _AddWeaponSlot(int target, int slot, DataPack pack) {
	int weapon = GetPlayerWeaponSlot(target, slot);
	if( weapon > 0 ) {
		pack.WriteCell(EntIndexToEntRef(weapon)); // Save last held weapon to switch back
		return weapon;
	} else {
		pack.WriteCell(INVALID_ENT_REFERENCE); // Save last held weapon to switch back
		return -1;
	}
}

static Action _timer_RequipWeapon(Handle hdl, DataPack pack) {
	pack.Reset();
	int client = GetClientOfUserId(pack.ReadCell());
	if(client == 0) return Plugin_Handled;

	int weapon, pistolSlotItem = -1;

	for(int slot = 0; slot <= 4; slot++) {
		weapon = pack.ReadCell();
		if(EntRefToEntIndex(weapon) != INVALID_ENT_REFERENCE) {
			if(slot == 1) {
				pistolSlotItem = weapon;
			}
			EquipPlayerWeapon(client, weapon);
		}
	}
	bool isDualWield = pack.ReadCell() == 1;
	if(isDualWield && pistolSlotItem != -1 && HasEntProp(pistolSlotItem, Prop_Send, "m_isDualWielding")) {
		SetEntProp(pistolSlotItem, Prop_Send, "m_isDualWielding", 1);
	}
	return Plugin_Handled;
}


// Sets color temp, does not set entity to support alpha, but does change value
Handle TempSetColor(int entity, float duration, int color[4], bool reset = false) {
	int originalColor[4];
	if(reset) {
		originalColor[0] = originalColor[1] = originalColor[2] = originalColor[3] = 255;
	} else {
		GetEntityRenderColor(entity, originalColor[0], originalColor[1], originalColor[2], originalColor[3]);
	}
	SetEntityRenderColor(entity, color[0], color[1], color[2], color[3]);

	DataPack pack;
	Handle handle = CreateDataTimer(duration, _timer_ClearTempColor, pack);
	pack.WriteCell(EntIndexToEntRef(entity));
	pack.WriteCellArray(originalColor, 4);
	return handle;
}
static Action _timer_ClearTempColor(Handle h, DataPack pack) {
	pack.Reset();
	int entity = EntRefToEntIndex(pack.ReadCell());
	if(entity > 0) {
		int color[4];
		pack.ReadCellArray(color, 4);
		SetEntityRenderColor(entity, color[0], color[1], color[2], color[3]);
	}
	return Plugin_Continue;
}


Handle TempSetSpeed(int client, float duration, float speed) {
	float originalSpeed = GetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue");
	SetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue", speed);

	DataPack pack;
	Handle handle = CreateDataTimer(duration, _timer_ClearTempSetSpeed, pack);
	pack.WriteCell(GetClientUserId(client));
	pack.WriteFloat(originalSpeed);
	return handle;
}
static Action _timer_ClearTempSetSpeed(Handle h, DataPack pack) {
	pack.Reset();
	int client = GetClientOfUserId(pack.ReadCell());
	float speed = pack.ReadFloat();
	SetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue", speed);
	return Plugin_Continue;
}


Handle TempSetGravity(int client, float duration, float gravity) {
	// TOOD: impl
	SetEntityGravity(client, 0.4);

	DataPack pack;
	Handle handle = CreateDataTimer(duration, _timer_ClearTempSetGravity, pack);
	pack.WriteCell(GetClientUserId(client));
	pack.WriteFloat(gravity);
	return handle;
}
static Action _timer_ClearTempSetGravity(Handle h, DataPack pack) {
	pack.Reset();
	int client = GetClientOfUserId(pack.ReadCell());
	float gravity = pack.ReadFloat();
	SetEntityGravity(client, gravity);
	return Plugin_Continue;
}


stock Handle TempSetClipAmmo(int client, float duration, int amount, int slot = 0) {
	int weapon = GetPlayerWeaponSlot(client, slot);
	if(weapon == -1) return INVALID_HANDLE;
	int originalAmmo = GetEntProp(weapon, Prop_Send, "m_iClip1");
	SetEntProp(weapon, Prop_Send, "m_iClip1", amount);
	PrintToServer("%d %d", weapon, originalAmmo);

	DataPack pack;
	Handle handle = CreateDataTimer(duration, _timer_ClearTempAmmo, pack);
	pack.WriteCell(originalAmmo);
	pack.WriteCell(EntIndexToEntRef(weapon));
	return handle;
}
static stock Action _timer_ClearTempAmmo(Handle h, DataPack pack) {
	pack.Reset();
	int amount = pack.ReadCell();
	int weapon = EntRefToEntIndex(pack.ReadCell());
	if(weapon > 0) {
		SetEntProp(weapon, Prop_Send, "m_iClip1", amount);
	}
	return Plugin_Continue;
}
