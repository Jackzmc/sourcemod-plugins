Action Timer_UltimateSacrifice(Handle h, DataPack pack) {
	pack.Reset();
	int client = GetClientOfUserId(pack.ReadCell());
	int sacrificer = GetClientOfUserId(pack.ReadCell());

	for(int slot = 0; slot < 5; slot++) {
		int sacWeapon = GetPlayerWeaponSlot(sacrificer, slot);
		int curWeapon = GetPlayerWeaponSlot(client, slot);
		if(curWeapon == -1 && sacWeapon != -1) {
			SDKHooks_DropWeapon(sacrificer, sacWeapon, NULL_VECTOR);
			EquipPlayerWeapon(client, sacWeapon);
		}
	}
	
	int permHealth = GetEntProp(sacrificer, Prop_Send, "m_iHealth");
	int tempHealth = L4D_GetPlayerTempHealth(sacrificer);

	L4D_SetPlayerTempHealth(sacrificer, 0);
	SDKHooks_TakeDamage(sacrificer, sacrificer, sacrificer, float(permHealth) - 1.0, DMG_GENERIC, -1, NULL_VECTOR);

	SetEntityHealth(client, GetEntProp(client, Prop_Send, "m_iHealth") + permHealth);
	L4D_SetPlayerTempHealth(client, L4D_GetPlayerTempHealth(client) + tempHealth);
	
	return Plugin_Handled;
}