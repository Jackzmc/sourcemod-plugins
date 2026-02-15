
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
	if(disgruntledPhrases == null) return;
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientInGame(i) && disgruntledOldName[i][0] != '\0') {
			// Player is still disgruntled
			return;
		}
	}
	delete disgruntledPhrases;
}