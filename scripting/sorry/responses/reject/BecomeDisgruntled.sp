static char STORE_KEY[] = "BecomeDisgruntled";

void BecomeDisgruntled_OnActivate(int activator, int target, const char[] eventId) {
	// Store old name
	char buffer[64+12]; // name maxlength 64? + "Disgruntled "
    GetClientName(activator, buffer, sizeof(buffer));
	SorryStore[target].SetString(STORE_KEY, buffer, sizeof(buffer));
	
	Format(buffer, sizeof(buffer), "Disgruntled %s", buffer);
	SetClientName(activator, buffer);

	CreateTimer(45.0, Timer_RemoveDisgruntled, GetClientUserId(activator));
}

Action BecomeDisgruntled_OnClientSayCommand(int client, const char[] command, const char[] sArgs) {
    if(StrEqual(command, "say") && SorryStore[client].ContainsKey(STORE_KEY)) {
		CPrintToChatAll("{blue}%N{default} : I hate %s", client, sArgs);
		return Plugin_Stop;
	}
    return Plugin_Continue;
}

Action Timer_RemoveDisgruntled(Handle h, int userid) {
	int client = GetClientOfUserId(userid);
	if(client > 0) {
		char buffer[64];
		SorryStore[client].GetString(STORE_KEY, buffer, sizeof(buffer));

		SetClientName(client, buffer);
		SorryStore[client].Remove(buffer);
	}
	return Plugin_Handled;
}

