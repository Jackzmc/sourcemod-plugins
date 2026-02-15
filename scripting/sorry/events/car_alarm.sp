void Event_CarAlarm(Event event, const char[] name, bool dontBroadcast) {
	int user = event.GetInt("userid");
	int client = GetClientOfUserId(user);
	if(client > 0) {
		SorryData sorry;
		sorry.SetEvent("car_alarm");
		sorry.hurtType = "I shot the car";
		PushSorry(client, sorry);
	}
}