void Event_InfectedDeath(Event event, const char[] name, bool dontBroadcast) {
	int attackerUserid = event.GetInt("attacker");
	int attacker = GetClientOfUserId(attackerUserid);
	int infected = event.GetInt("entityid");
	if(attacker > 0 && attacker <= MaxClients && infected > 0 && !IsFakeClient(attacker)) {
		int honker;
		if(clownLastHonked.GetValue(infected, honker)) {
			if(honker != attackerUserid) {
				SorryData sorry;
				sorry.eventId = "clown";
				sorry.victimUserid = honker;
				Format(sorry.hurtType, sizeof(sorry.hurtType), "I killed your clown");
				PushSorry(attacker, sorry);
			}
		}
	}
	clownLastHonked.Remove(infected);
}
public void L4D2_OnEntityShoved_Post(int client, int entity, int weapon, const float vecDir[3], bool bIsHighPounce) {
	if(entity >= MaxClients) {
		int honker;
		if(!clownLastHonked.GetValue(entity, honker) || GetClientOfUserId(honker) != client) {
			char model[64];
			GetEntPropString(entity, Prop_Data, "m_ModelName", model, sizeof(model));
			if(StrContains(model, "clown") > -1) {
				clownLastHonked.SetValue(entity, GetClientUserId(client));
				return;
			}
		} 
	}
}
