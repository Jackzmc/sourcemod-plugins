///////////////////////////////////////////////////////////////////////////////
// Special Infected Events 
//   To detect if under attack by special
///////////////////////////////////////////////////////////////////////////////
void _checkUnderAttack(Event event, const char[] name, const char[] eventNameToCheck) {
    int userid = event.GetInt("victim");
	int victim = GetClientOfUserId(userid);
	if(victim) {
		if(StrEqual(name, eventNameToCheck)) {
			isUnderAttack[victim] = true;
		} else {
			CreateTimer(1.0, Timer_StopSpecialAttackImmunity, userid);
		}
	}
}
void Event_ChargerCarry(Event event, const char[] name, bool dontBroadcast) {
    _checkUnderAttack(event, name, "charger_carry_start");
}
void Event_HunterPounce(Event event, const char[] name, bool dontBroadcast) {
    _checkUnderAttack(event, name, "lunge_pounce");
}
void Event_SmokerChoke(Event event, const char[] name, bool dontBroadcast) {
    _checkUnderAttack(event, name, "choke_start");
}
void Event_JockeyRide(Event event, const char[] name, bool dontBroadcast) {
    _checkUnderAttack(event, name, "jockey_ride");
}
Action Timer_StopSpecialAttackImmunity(Handle h, int userid) {
	int client = GetClientOfUserId(userid);
	if(client > 0) {
		isUnderAttack[client] = false;
	}
	return Plugin_Continue;
}
///////////////////////////////////////////////////////////////////////////////
/**
 * Generic hook to prevent all damage. Damage event handled and amount is changed to 0
 */
// TODO: move to shared/
Action Hook_Godmode(int victim, int& attacker, int& inflictor, float& damage, int& damagetype) {
	damage = 0.0;
	return Plugin_Handled;
}
Action Timer_RevertGod(Handle h, int userid) {
	int client = GetClientOfUserId(userid);
	if(client > 0) {
		SDKUnhook(client, SDKHook_OnTakeDamage, Hook_Godmode);
	}
	return Plugin_Handled;
}