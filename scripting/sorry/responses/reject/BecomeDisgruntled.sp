char disgruntledOldName[MAXPLAYERS+1][64];

void BecomeDisgruntled_OnActivate(int activator, int target, const char[] eventId) {
    GetClientName(activator, disgruntledOldName[activator], sizeof(disgruntledOldName[activator]));
	char buffer[64];
	Format(buffer, sizeof(buffer), "Disgruntled %s", disgruntledOldName[activator]);
	SetClientName(activator, buffer);
	CreateTimer(45.0, Timer_RemoveDisgruntled, GetClientUserId(activator));
}

Action BecomeDisgruntled_OnClientSayCommand(int client, const char[] command, const char[] sArgs) {
    if(disgruntledOldName[client][0] != '\0' && StrEqual(command, "say")) {
		CPrintToChatAll("{blue}%N{default} : I hate %s", client, sArgs);
		return Plugin_Stop;
	}
    return Plugin_Continue;
}

Action Timer_RemoveDisgruntled(Handle h, int userid) {
	int client = GetClientOfUserId(userid);
	if(client > 0) {
		SetClientName(client, disgruntledOldName[client]);
		disgruntledOldName[client][0] = '\0';
	}
	TryClearDisgruntled();
	return Plugin_Handled;
}

// Clear list if no player is disgruntled
void TryClearDisgruntled() {
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientInGame(i) && disgruntledOldName[i][0] != '\0') {
			// Player is still disgruntled
			return;
		}
	}
}

