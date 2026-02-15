#define STORE_KEY "gnome"

void Gnome_OnActivate(int activator, int target, const char[] eventId) {
    ShowSorryAcceptMenu(activator, target, eventId);
    int gnome = CreateEntityByName("weapon_gnome");
    float pos[3];
    GetClientAbsOrigin(activator, pos);
    TeleportEntity(gnome, pos, NULL_VECTOR, NULL_VECTOR);
    DispatchSpawn(gnome);
    EquipPlayerWeapon(activator, gnome);

    SorryStore[target].SetValue(STORE_KEY, true);

    PrintToChat(activator, "One day your gnome will grow up, you better take care of it and give it a name.");
}

void Gnome_OnClientDisconnect(int client) {

}

Action Gnome_OnPlayerRunCmd(int client, int& buttons, int& impulse, float vel[3], float angles[3], int& weapon, int& subtype, int& cmdnum, int& tickcount, int& seed, int mouse[2]) {
	// RejectGnome handler
    if(SorryStore[client].ContainsKey(STORE_KEY)) {
		if(weapon != 0) {
			// Prevent weapon switch
			weapon = 0;
			return Plugin_Changed;
		} else if(buttons & IN_ATTACK) {
			// Prevent gnome drop
			PrintHintText(client, "You cannot drop your gnome until you give it a name! Say it's name in chat.");
			ClientCommand(client, "play player/orch_hit_csharp_short.wav");
			buttons &= ~IN_ATTACK;
			SetEntPropFloat(client, Prop_Send, "m_flNextAttack", GetGameTime() + 1.0);
			return Plugin_Continue;
		}
	}
	return Plugin_Continue;
}

Action Gnome_OnClientSayCommand(int client, const char[] command, const char[] sArgs) {
    // RejectGnome
	if(SorryStore[client].ContainsKey(STORE_KEY)) {
		CPrintToChatAll("{blue}%N{default} : I love my gnome friend, I name him %s!", client, sArgs);
		LogAction(client, -1, "\"%L\" named their gnome \"%s\"", client, sArgs);
		SorryStore[client].Remove(STORE_KEY);
		// SDKUnhook(client, SDKHook_WeaponSwitch, Hook_NoGnomeDrop);
		return Plugin_Stop;
	}
    return Plugin_Continue;
}