enum PZDamage_Type {
	PZDamage_Killed, //0
	PZDamage_Incapped,
	PZDamage_Killed2, //2
	PZDamage_Revived,
	PZDamage_Progress,
	PZDamage_DestroyedCan,
	PZDamage_AssistedAgainst,
	PZDamage_HitAssisted,
	PZDamage_Hit,
	PZDamage_PushedAssisted,
	PZDamage_Pushed,
	PZDamage_Pounced,
	PZDamage_Incapped2,
	PZDamage_Saved,
	PZDamage_GaveHealth,
	PZDamage_GaveAdrendaline,
	PZDamage_Protected,
	PZDamage_Rescued,
	PZDamage_Healed,
	PZDamage_EarnedBronze,
	PZDamage_EarnedSilver,
	PZDamage_EarnedGold
}

GlobalForward PlayersConnectedForward;
public void InitalizeUserMessageForwards() {
	PlayersConnectedForward = CreateGlobalForward("GameStartedAllReady", ET_Ignore);
	HookUserMessage(GetUserMessageId("PlayersConnectedForward"), Hook_GameStartedAllReady, false);

}

Action Hook_GameStartedAllReady(UserMsg msg_id, BfRead msg, const int[] players, int playersNum, bool reliable, bool init) {
	Call_StartForward(PlayersConnectedForward);
	Call_Finish();
	return Plugin_Continue;
}

stock void SendPZDamage(int reciever, PZDamage_Type type, int client, int target = -1) {
	Handle msg = StartMessageOne("PZDmgMsg", reciever);
	BfWriteByte(msg, view_as<int>(type));
	BfWriteShort(msg, client);
	BfWriteShort(msg, target);
	BfWriteShort(msg, 0);
	BfWriteShort(msg, 0);
	EndMessage();
}

stock void SendPZDamageToAll(PZDamage_Type type, int client, int target = -1) {
	Handle msg = StartMessageAll("PZDmgMsg");
	BfWriteByte(msg, view_as<int>(type));
	BfWriteShort(msg, client);
	BfWriteShort(msg, target);
	BfWriteShort(msg, 0);
	BfWriteShort(msg, 0);
	EndMessage();
}