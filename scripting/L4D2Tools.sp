#pragma semicolon 1
#pragma newdecls required

#define DEBUG

#define PLUGIN_NAME "L4D2 Misc Tools"
#define PLUGIN_DESCRIPTION "Includes: Notice on laser use, Timer for gauntlet runs"
#define PLUGIN_AUTHOR "jackzmc"
#define PLUGIN_VERSION "1.0"
#define PLUGIN_URL ""

#include <sourcemod>
#include <sdktools>
//#include <sdkhooks>


bool bLasersUsed[2048];
ConVar hLaserNotice, hFinaleTimer;
int iFinaleStartTime;

public Plugin myinfo = {
	name = PLUGIN_NAME, 
	author = PLUGIN_AUTHOR, 
	description = PLUGIN_DESCRIPTION, 
	version = PLUGIN_VERSION, 
	url = PLUGIN_URL
};

public void OnPluginStart() {
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
	
	//RegAdminCmd("sm_respawn", Command_SpawnSpecial, ADMFLAG_CHEATS, "Respawn a dead survivor right where they died.");
}

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


//finaletimer
public void Event_GauntletStart(Event event, const char[] name, bool dontBroadcast) {
	if(hFinaleTimer.IntValue > 0) {
		iFinaleStartTime = GetTime();
		PrintHintTextToAll("The finale timer has been started");
	}
}
public void Event_FinaleStart(Event event, const char[] name, bool dontBroadcast) {
	if(hFinaleTimer.IntValue == 2) {
		iFinaleStartTime = GetTime();
		PrintHintTextToAll("The finale timer has been started");
	}
}
public void Event_FinaleEnd(Event event, const char[] name, bool dontBroadcast) {
	if(hFinaleTimer.IntValue != 0) {
		int difference = GetTime() - iFinaleStartTime;
		
		char time[32];
		FormatSeconds(difference, time, sizeof(time));
		PrintToChatAll("Finale took %s to complete", time);
		iFinaleStartTime = 0;

	}
}



/**
 * Prints human readable duration from milliseconds
 *
 * @param ms		The duration in milliseconds
 * @param str		The char array to use for text
 * @param strSize   The size of the string
 */
stock void FormatSeconds(int raw_sec, char[] str, int strSize) {
	int hours = raw_sec / 3600; 
	int minutes = (raw_sec -(3600*hours))/60;
	int seconds = (raw_sec -(3600*hours)-(minutes*60));
	if(hours >= 1) {
		Format(str, strSize, "%d hours, %d.%d minutes", hours, minutes, seconds);
	}else if(minutes >= 1) {
		Format(str, strSize, "%d minutes and %d seconds", minutes, seconds);
	}else {
		Format(str, strSize, "%d seconds", seconds);
	}
	
}
stock void ShowDelayedHintToAll(const char[] format, any ...) {
	char buffer[254];
	VFormat(buffer, sizeof(buffer), format, 2);
	static int hintInt = 0;
	if(hintInt >= 10) {
		PrintHintTextToAll("%s",buffer);
		hintInt = 0;
	}
	hintInt++;
}
stock void ShowDelayedHint(int client, const char[] format, any ...) {
	char buffer[254];
	VFormat(buffer, sizeof(buffer), format, 2);
	static int hintInt = 0;
	if(hintInt >= 10) {
		PrintHintText(client, "%s",buffer);
		hintInt = 0;
	}
	hintInt++;
}
stock void CheatCommand(int client, const char[] command, const char[] argument1, const char[] argument2) {
	int userFlags = GetUserFlagBits(client);
	SetUserFlagBits(client, ADMFLAG_ROOT);
	int flags = GetCommandFlags(command);
	SetCommandFlags(command, flags & ~FCVAR_CHEAT);
	FakeClientCommand(client, "%s %s %s", command, argument1, argument2);
	SetCommandFlags(command, flags);
	SetUserFlagBits(client, userFlags);
} 
stock int GetAnyValidClient() {
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i))
		{
			return i;
		}
	}
	return -1;
}