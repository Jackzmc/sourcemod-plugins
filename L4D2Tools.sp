#pragma semicolon 1
#pragma newdecls required

#define DEBUG

#define PLUGIN_NAME "Misc Tools"
#define PLUGIN_DESCRIPTION "Includes: Notice on laser use, Timer for gauntlet runs"
#define PLUGIN_AUTHOR "jackzmc"
#define PLUGIN_VERSION "1.0"
#define PLUGIN_URL ""

#include <sourcemod>
#include <sdktools>
//#include <sdkhooks>

#pragma newdecls required

bool bLasersUsed[2048];
ConVar hLaserNotice, hFinaleTimer;
int iFinaleStartTime;

public Plugin myinfo = 
{
	name = PLUGIN_NAME, 
	author = PLUGIN_AUTHOR, 
	description = PLUGIN_DESCRIPTION, 
	version = PLUGIN_VERSION, 
	url = PLUGIN_URL
};

public void OnPluginStart()
{
	EngineVersion g_Game = GetEngineVersion();
	if(g_Game != Engine_Left4Dead && g_Game != Engine_Left4Dead2)
	{
		SetFailState("This plugin is for L4D/L4D2 only.");	
	}
	hLaserNotice = CreateConVar("sm_laser_use_notice", "1.0", "Enable notification of a laser box being used", FCVAR_NONE, true, 0.0, true, 1.0);
	hFinaleTimer = CreateConVar("sm_time_finale", "2.0", "Record the time it takes to complete finale. 0 -> OFF, 1 -> Gauntlets Only, 2 -> All finales", FCVAR_NONE, true, 0.0, true, 2.0);

	HookEvent("player_use", Event_PlayerUse);
	HookEvent("round_end", Event_RoundEnd);
	HookEvent("gauntlet_finale_start", Event_GauntletStart);
	HookEvent("finale_start", Event_FinaleStart);
	HookEvent("finale_vehicle_leaving", Event_FinaleEnd);
}

#if 1 
//laserNotice
public void Event_PlayerUse(Event event, const char[] name, bool dontBroadcast) {
	if(hLaserNotice.BoolValue) {
		char player_name[32];
		char entity_name[64];
		int player_id = GetClientOfUserId(event.GetInt("userid"));
		int target_id = event.GetInt("targetid");
	
		GetClientName(player_id, player_name, sizeof(player_name));
		GetEntityClassname(target_id, entity_name, sizeof(entity_name));
		
		if(StrEqual(entity_name,"upgrade_laser_sight")) {
			if(!bLasersUsed[target_id]) {
				bLasersUsed[target_id] = true;
				PrintToChatAll("%s picked up laser sights",player_name);
			}
		}	
	}
}
public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast) {
	for (int i = 1; i < sizeof(bLasersUsed) ;i++) {
		bLasersUsed[i] = false;
	}
}
#endif


#if 1 
//finaletimer
public void Event_GauntletStart(Event event, const char[] name, bool dontBroadcast) {
	if(hFinaleTimer.IntValue > 0) {
		iFinaleStartTime = GetTime();
		PrintToChatAll("The finale timer has been started");
	}
}
public void Event_FinaleStart(Event event, const char[] name, bool dontBroadcast) {
	if(hFinaleTimer.IntValue == 2) {
		iFinaleStartTime = GetTime();
		PrintToChatAll("The finale timer has been started");
	}
}
public void Event_FinaleEnd(Event event, const char[] name, bool dontBroadcast) {
	if(hFinaleTimer.IntValue != 0) {
		int difference = GetTime() - iFinaleStartTime;
		iFinaleStartTime = 0;
		
		char time[32];
		FormatMs(difference, time, sizeof(time));
		PrintToChatAll("Finale took %s to complete", time);
	}
}
#endif
/**
 * Prints human readable duration from milliseconds
 *
 * @param ms		The duration in milliseconds
 * @param str		The char array to use for text
 * @param strSize   The size of the string
 */
stock void FormatMs(int ms, char[] str, int strSize) {
	int sec = ms / 1000;
	int h = sec / 3600; 
	int m = (sec -(3600*h))/60;
	int s = (sec -(3600*h)-(m*60));
	if(h >= 1) {
		Format(str, strSize, "%d hour, %d.%d minutes", h, m, s);
	}else if(m >= 1) {
		Format(str, strSize, "%d minutes and %d seconds", m, s);
	}else {
		float raw_seconds = float(ms) / 1000;
		Format(str, strSize, "%0.1f seconds", raw_seconds);
	}
	
}
stock void ShowHintToAll(const char[] format, any ...) {
	char buffer[254];
	VFormat(buffer, sizeof(buffer), format, 2);
	static int hintInt = 0;
	if(hintInt >= 10) {
		PrintHintTextToAll("%s",buffer);
		hintInt = 0;
	}
	hintInt++;
}
stock void ShowHint(int client, const char[] format, any ...) {
	char buffer[254];
	VFormat(buffer, sizeof(buffer), format, 2);
	static int hintInt = 0;
	if(hintInt >= 10) {
		PrintHintText(client, "%s",buffer);
		hintInt = 0;
	}
	hintInt++;
}