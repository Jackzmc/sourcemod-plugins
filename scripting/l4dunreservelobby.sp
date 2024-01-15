#include <sourcemod>
#include <sdktools>
#include <left4dhooks>

#define UNRESERVE_VERSION "1.1.1"

#define UNRESERVE_DEBUG 0
#define UNRESERVE_DEBUG_LOG 0

#define L4D_MAXCLIENTS MaxClients
#define L4D_MAXCLIENTS_PLUS1 (L4D_MAXCLIENTS + 1)

#define L4D_MAXHUMANS_LOBBY_VERSUS 8
#define L4D_MAXHUMANS_LOBBY_OTHER 4

ConVar cvarGameMode;
ConVar cvarUnreserve;

public Plugin myinfo = 
{
	name = "L4D1/2 Remove Lobby Reservation",
	author = "Downtown1",
	description = "Removes lobby reservation when server is full",
	version = UNRESERVE_VERSION,
	url = "http://forums.alliedmods.net/showthread.php?t=87759"
}


public OnPluginStart()
{
	LoadTranslations("common.phrases");
	
	RegAdminCmd("sm_unreserve", Command_Unreserve, ADMFLAG_BAN, "sm_unreserve - manually force removes the lobby reservation");
	
	cvarUnreserve = CreateConVar("l4d_unreserve_full", "1", "Automatically unreserve server after a full lobby joins", FCVAR_SPONLY|FCVAR_NOTIFY);
	CreateConVar("l4d_unreserve_version", UNRESERVE_VERSION, "Version of the Lobby Unreserve plugin.", FCVAR_SPONLY|FCVAR_NOTIFY);

	HookEvent("game_init", Event_GameStart);


	cvarGameMode = FindConVar("mp_gamemode");
}

void Event_GameStart(Event event, const char[] name, bool dontBroadcast) {
	CreateTimer(20.0, Timer_CheckPlayers);
}

Action Timer_CheckPlayers(Handle h) {
	if(AreAllPlayersConnecting()) {
		PrintToServer("4 Players connecting, unreserving");
		L4D_LobbyUnreserve();
	}
	return Plugin_Continue;
}

bool AreAllPlayersConnecting() {
	int count = 0;
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && !IsFakeClient(i)) {
			if(!IsClientInGame(i)) return false;
			count++;
		}
	}
	return count >= 4;
}

bool IsServerLobbyFull()
{
	int humans = GetHumanCount();
	
	DebugPrintToAll("IsServerLobbyFull : humans = %d", humans);
	
	char sGameMode[32];
	cvarGameMode.GetString(sGameMode, sizeof(sGameMode));
	if(StrEqual(sGameMode, "versus") || StrEqual(sGameMode, "scavenge"))
	{
		return humans >= L4D_MAXHUMANS_LOBBY_VERSUS;
	}
	return humans >= L4D_MAXHUMANS_LOBBY_OTHER;
}

public OnClientPutInServer(int client)
{
	DebugPrintToAll("Client put in server %N", client);
	
	if(GetConVarBool(cvarUnreserve) && /*L4D_LobbyIsReserved() &&*/ IsServerLobbyFull())
	{
		//PrintToChatAll("[SM] A full lobby has connected, automatically unreserving the server.");
		L4D_LobbyUnreserve();
	}
}

Action Command_Unreserve(int client, int args)
{
	/*if(!L4D_LobbyIsReserved())
	{
		ReplyToCommand(client, "[SM] Server is already unreserved.");
	}*/
	
	L4D_LobbyUnreserve();
	PrintToChatAll("[SM] Lobby reservation has been removed.");
	
	return Plugin_Handled;
}


//client is in-game and not a bot
stock bool IsClientInGameHuman(int client)
{
	return IsClientInGame(client) && !IsFakeClient(client);
}

stock int GetHumanCount()
{
	int humans = 0;
	
	int i;
	for(i = 1; i < L4D_MAXCLIENTS_PLUS1; i++)
	{
		if(IsClientInGameHuman(i))
		{
			humans++
		}
	}
	
	return humans;
}

void DebugPrintToAll(const char[] format, any...)
{
	#if UNRESERVE_DEBUG	|| UNRESERVE_DEBUG_LOG
	char buffer[192];
	
	VFormat(buffer, sizeof(buffer), format, 2);
	
	#if UNRESERVE_DEBUG
	PrintToChatAll("[UNRESERVE] %s", buffer);
	PrintToConsole(0, "[UNRESERVE] %s", buffer);
	#endif
	
	LogMessage("%s", buffer);
	#else
	//suppress "format" never used warning
	if(format[0])
		return;
	else
		return;
	#endif
}