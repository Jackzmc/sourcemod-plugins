#pragma semicolon 1
#pragma newdecls required

//#define DEBUG

#define PLUGIN_VERSION "1.0"

#include <sourcemod>
#include <sdktools>
#include <multicolors>
#include <jutils>
#include <l4d2_perms>

#define RESERVE_LEVELS 4
char ReserveLevels[RESERVE_LEVELS][] = {
	"Public", "Watch", "Admin Only", "Private"
};

StringMap g_steamIds;


ConVar cv_cheatsMode;
ConVar cv_reserveMode;
ConVar cv_reserveMessage; char g_reserveMessage[64];
ConVar cv_sm_cheats;

bool g_ignoreModeChange;
ReserveMode g_previousMode;

public Plugin myinfo = 
{
	name =  "L4D2 Perms", 
	author = "jackzmc", 
	description = "", 
	version = PLUGIN_VERSION, 
	url = "https://github.com/Jackzmc/sourcemod-plugins"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
	return APLRes_Success;
}

public void OnPluginStart() {
	EngineVersion g_Game = GetEngineVersion();
	if(g_Game != Engine_Left4Dead && g_Game != Engine_Left4Dead2) {
		SetFailState("This plugin is for L4D/L4D2 only.");	
	}

	g_steamIds = new StringMap();

	cv_reserveMessage = CreateConVar("sm_perms_reserve_msg", "Sorry, server is reserved.", "The message sent to users when server is reserved.");
	cv_reserveMessage.AddChangeHook(OnReserveMsgChanged);

	cv_reserveMode = CreateConVar("sm_perms_reserve_mode", "0", "The current reservation mode. \n 0 = None (public)\n 1 = Watch\n 2 = Admin Only\n 3 = Private", FCVAR_DONTRECORD, true, 0.0, true, float(RESERVE_LEVELS));
	cv_reserveMode.AddChangeHook(OnReserveModeChanged);

	cv_sm_cheats = CreateConVar("sm_cheats", "0", "Is sm cheats enabled?", FCVAR_NONE, true, 0.0, true, 1.0); 
	cv_sm_cheats.AddChangeHook(OnCheatsChanged);
	
	cv_cheatsMode = CreateConVar("sm_perms_cheats_mode", "2", "When cheats are turned on, which reservation should be set?.\n 0 = None (public)\n 1 = Watch\n 2 = Admin Only\n 3 = Private", FCVAR_NONE, true, 0.0, true, float(RESERVE_LEVELS - 1));

	// cv_cheats = FindConVar("sv_cheats");

	HookEvent("player_disconnect", Event_PlayerDisconnect);

	AutoExecConfig(true, "l4d2_perms");


	RegAdminCmd("sm_perm", Command_SetServerPermissions, ADMFLAG_KICK, "Sets the server's permissions.");
	RegAdminCmd("sm_perms", Command_SetServerPermissions, ADMFLAG_KICK, "Sets the server's permissions.");
}

void OnCheatsChanged(ConVar cvar, const char[] oldValue, const char[] newValue) {
	if(g_ignoreModeChange) {
		g_ignoreModeChange = false;
		return;
	}
	if(cvar.IntValue > 0) {
		g_previousMode = GetReserveMode();
		if(g_previousMode == Reserve_None || g_previousMode == Reserve_Watch)
			SetReserveMode(view_as<ReserveMode>(cv_cheatsMode.IntValue), "cheats activated");
	} else {
		SetReserveMode(g_previousMode);
	}
}

void OnReserveModeChanged(ConVar cvar, const char[] oldValue, const char[] newValue) {
	if(g_ignoreModeChange) {
		g_ignoreModeChange = false;
		return;
	}
	if(cvar.IntValue >= 0 && cvar.IntValue < RESERVE_LEVELS) {
		PrintChatToAdmins("Server access changed to %s", ReserveLevels[cvar.IntValue]);
		PrintToServer("Server access changed to %s", ReserveLevels[cvar.IntValue]);
		ReserveMode mode = view_as<ReserveMode>(cvar.IntValue);
		char buffer[32];
		if(mode == Reserve_AdminOnly || mode == Reserve_Private) {
			for(int i = 1; i <= MaxClients; i++) {
				if(IsClientInGame(i) && !IsFakeClient(i)) {
					GetClientAuthId(i, AuthId_Steam2, buffer, sizeof(buffer));
					g_steamIds.SetValue(buffer, i);
				}
			}
		}
	} else {
		// cvar.SetString(oldValue);
	}
}

void OnReserveMsgChanged(ConVar cvar, const char[] oldValue, const char[] newValue) {
	cvar.GetString(g_reserveMessage, sizeof(g_reserveMessage));
}

public void OnClientConnected(int client) {
	if(!IsFakeClient(client) && GetReserveMode() == Reserve_Watch) {
		PrintChatToAdmins("%N is connecting", client);
	}
}

public void Event_PlayerDisconnect(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(client > 0) {
		if(GetClientCount(false) == 0) {
			// Clear when last player disconnected
			SetReserveMode(Reserve_None);
			g_ignoreModeChange = true;
			cv_sm_cheats.IntValue = 0;
		}
	}
}

public void OnClientPostAdminCheck(int client) {
	if(!IsFakeClient(client)) {
		if(GetReserveMode() == Reserve_AdminOnly && GetUserAdmin(client) == INVALID_ADMIN_ID) {
			char auth[32];
			GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth));
			// Check if they are whitelisted:
			if(!g_steamIds.ContainsKey(auth)) {
				KickClient(client, "Sorry, server is reserved");
				return;
			}
		}
	}
}

public void OnClientAuthorized(int client, const char[] auth) {
	if(IsFakeClient(client)) return;
	if(GetReserveMode() == Reserve_Private) {
		if(!g_steamIds.ContainsKey(auth)) {
			KickClient(client, "Sorry, server is reserved");
		}
	}
	// Don't insert id here if admin only, let admin check do that
	if(GetReserveMode() != Reserve_AdminOnly) {
		g_steamIds.SetValue(auth, client);
	}
}


Action Command_SetServerPermissions(int client, int args) {
	if(args > 0) {
		char arg1[32];
		GetCmdArg(1, arg1, sizeof(arg1));
		if(StrEqual(arg1, "public", false)) {
			SetReserveMode(Reserve_None);
		} else if(StrContains(arg1, "noti", false) > -1 || StrContains(arg1, "watch", false) > -1) {
			SetReserveMode(Reserve_Watch);
		} else if(StrContains(arg1, "admin", false) > -1) {
			SetReserveMode(Reserve_AdminOnly);
		} else if(StrEqual(arg1, "private", false)) {
			SetReserveMode(Reserve_Private);
		} else {
			ReplyToCommand(client, "Usage: sm_reserve [public/notify/admin/private] or no arguments to view current reservation.");
			return Plugin_Handled;
		}
	} else {
		ReplyToCommand(client, "Server access level is currently %s", ReserveLevels[GetReserveMode()]);
	}
	return Plugin_Handled;
}

ReserveMode GetReserveMode() {
	return view_as<ReserveMode>(cv_reserveMode.IntValue);
}

void SetReserveMode(ReserveMode mode, const char[] reason = "") {
	ReserveMode curMode = GetReserveMode();
	// Clear allowed users when undoing private
	if(curMode != mode && curMode == Reserve_Private) {
		g_steamIds.Clear();
	}

	if(reason[0] != '\0') {
		// Print custom message if a reason is passed:
		g_ignoreModeChange = true;
		PrintChatToAdmins("Server access changed to %s (%s)", ReserveLevels[mode], reason);
		PrintToServer("Server access changed to %s (%s)", ReserveLevels[mode], reason);
	}
	cv_reserveMode.IntValue = view_as<int>(mode);
}