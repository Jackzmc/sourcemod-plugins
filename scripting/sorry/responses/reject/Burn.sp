Action Timer_BurnPlayer(Handle h, int client) {
	if(IsClientInGame(client)) {
		IgniteEntity(client, 2.0, false, 1.0);
		float damage = GetURandomFloat() > 0.75 ? 2.0 : 1.0;
		SDKHooks_TakeDamage(client, client, client, damage, DMG_BURN | DMG_SLOWBURN);
	}
	return Plugin_Handled;
}