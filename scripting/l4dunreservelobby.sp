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

new Handle:cvarGameMode = INVALID_HANDLE;

public Plugin:myinfo = 
{
	name = "L4D1/2 Remove Lobby Reservation",
	author = "Downtown1",
	description = "Removes lobby reservation when server is full",
	version = UNRESERVE_VERSION,
	url = "http://forums.alliedmods.net/showthread.php?t=87759"
}

new Handle:cvarUnreserve = INVALID_HANDLE;

public OnPluginStart()
{
	LoadTranslations("common.phrases");
	
	RegAdminCmd("sm_unreserve", Command_Unreserve, ADMFLAG_BAN, "sm_unreserve - manually force removes the lobby reservation");
	
	cvarUnreserve = CreateConVar("l4d_unreserve_full", "1", "Automatically unreserve server after a full lobby joins", FCVAR_SPONLY|FCVAR_NOTIFY);
	CreateConVar("l4d_unreserve_version", UNRESERVE_VERSION, "Version of the Lobby Unreserve plugin.", FCVAR_SPONLY|FCVAR_NOTIFY);

	cvarGameMode = FindConVar("mp_gamemode");
}

bool:IsScavengeMode()
{
	decl String:sGameMode[32];
	GetConVarString(cvarGameMode, sGameMode, sizeof(sGameMode));
	if (StrContains(sGameMode, "scavenge") > -1)
	{
		return true;
	}
	else
	{
		return false;
	}	
}

bool:IsVersusMode()
{
	decl String:sGameMode[32];
	GetConVarString(cvarGameMode, sGameMode, sizeof(sGameMode));
	if (StrContains(sGameMode, "versus") > -1)
	{
		return true;
	}
	else
	{
		return false;
	}	
}

IsServerLobbyFull()
{
	new humans = GetHumanCount();
	
	DebugPrintToAll("IsServerLobbyFull : humans = %d", humans);
	
	if(IsVersusMode() || IsScavengeMode())
	{
		return humans >= L4D_MAXHUMANS_LOBBY_VERSUS;
	}
	return humans >= L4D_MAXHUMANS_LOBBY_OTHER;
}

public OnClientPutInServer(client)
{
	DebugPrintToAll("Client put in server %N", client);
	
	if(GetConVarBool(cvarUnreserve) && /*L4D_LobbyIsReserved() &&*/ IsServerLobbyFull())
	{
		//PrintToChatAll("[SM] A full lobby has connected, automatically unreserving the server.");
		L4D_LobbyUnreserve();
	}
}

public Action:Command_Unreserve(client, args)
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
stock bool:IsClientInGameHuman(client)
{
	return IsClientInGame(client) && !IsFakeClient(client);
}

stock GetHumanCount()
{
	new humans = 0;
	
	new i;
	for(i = 1; i < L4D_MAXCLIENTS_PLUS1; i++)
	{
		if(IsClientInGameHuman(i))
		{
			humans++
		}
	}
	
	return humans;
}

DebugPrintToAll(const String:format[], any:...)
{
	#if UNRESERVE_DEBUG	|| UNRESERVE_DEBUG_LOG
	decl String:buffer[192];
	
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