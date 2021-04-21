#pragma semicolon 1

#define MAX_CODE_SIZE 8
#define KICK_REASON "Did not submit a valid verification code in time."
#define VERIFICATION_MSG "Welcome! Please enter this code in chat to play: %s"
#define VERIFICATION_SUCCESS "Thank you for verifying. Have fun!"
#define VERIFICATION_FAIL "Invalid verification code. %d tries remaining."
#define VERIFICATION_TIME 120.0

#define DEBUG
#define PLUGIN_VERSION "0.1.0"

#include <sourcemod>
#include <sdktools>
#include <tf2>
#include <tf2_stocks>
//#include <sdkhooks>


static char captchas[MAXPLAYERS+1][MAX_CODE_SIZE+1];
static Handle captchaKickTimer[MAXPLAYERS+1];
static int captchaTriesRemaining[MAXPLAYERS+1];
static TFTeam playerTeam[MAXPLAYERS+1];
static TFClassType playerClass[MAXPLAYERS+1];

public Plugin myinfo = {
	name = "TF2 Captcha",
	author = "Jackz",
	description = "",
	version = PLUGIN_VERSION,
	url = ""
};

public void OnPluginStart() {
	EngineVersion g_Game = GetEngineVersion();
	if(g_Game != Engine_TF2) {
		SetFailState("This plugin is for TF2 only.");	
	}

	HookEvent("player_changeclass", Event_PlayerChangeClass);
	HookEvent("player_team", Event_PlayerSwitchTeam);
	HookEvent("player_disconnect", Event_PlayerDisconnect);
}

public Action Event_PlayerSwitchTeam(Event event, const char[] name, bool dontBroadcast) {
	int userid = event.GetInt("userid");
	int client = GetClientOfUserId(userid);
	if(client > 0 && captchaKickTimer[client] != INVALID_HANDLE) {
		RequestFrame(Frame_SwitchTeam, client);
	}
}

public void Frame_SwitchTeam(int userid) {
	int client = GetClientOfUserId(userid);
	if(client > 0)
		TF2_ChangeClientTeam(client, TFTeam_Spectator);
}

public Action Event_PlayerChangeClass(Event event, const char[] name, bool dontBroadcast) {
	int userid = event.GetInt("userid");
	int client = GetClientOfUserId(userid);
	
	if(client > 0 && captchas[client][0] == '\0' && !IsFakeClient(client)) { 
		playerTeam[client] = TF2_GetClientTeam(client);
		playerClass[client] = TF2_GetPlayerClass(client);
		TF2_ChangeClientTeam(client, TFTeam_Spectator);
		for(int i = 0; i < MAX_CODE_SIZE; i++) {
			captchas[client][i] = GetRandomInt(0, 9)+ '0';
		}
		captchas[client][MAX_CODE_SIZE] = '\0';
		captchaTriesRemaining[client] = 3;
		PrintToChat(client, VERIFICATION_MSG, captchas[client]);
		captchaKickTimer[client] = CreateTimer(VERIFICATION_TIME, Timer_Kick, userid);
    }
}

public Action Timer_Kick(Handle handle, int userid) {
	int client = GetClientOfUserId(userid);
	if(client > 0)
		KickClient(client, KICK_REASON);
}

public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs) {
	if(captchaKickTimer[client] != INVALID_HANDLE) {
		if(StrEqual(sArgs, captchas[client])) {
			CloseHandle(captchaKickTimer[client]);
			captchaKickTimer[client] = INVALID_HANDLE;
			PrintToChat(client, VERIFICATION_SUCCESS);
			TF2_ChangeClientTeam(client, playerTeam[client]);
			//TF2_SetPlayerClass(client, playerClass[client]);
		}else{
			if(--captchaTriesRemaining[client] == 0) {
				TriggerTimer(captchaKickTimer[client]);
				captchaKickTimer[client] = INVALID_HANDLE;
			}else{
				PrintToChat(client, VERIFICATION_FAIL, captchaTriesRemaining[client]);
			}
		}
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

public void OnClientDisconnect(int client) {
}

public Action Event_PlayerDisconnect(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	captchas[client][0] = '\0';
}