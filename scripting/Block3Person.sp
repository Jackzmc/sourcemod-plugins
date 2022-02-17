#define PLUGIN_VERSION "1.1"

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>

public Plugin myinfo =
{
	name = "Block3person",
	author = "Dragokas",
	description = "Block 3-rd person view by creating blindness",
	version = PLUGIN_VERSION,
	url = "https://github.com/dragokas"
}

bool aBlinded[MAXPLAYERS];
UserMsg g_FadeUserMsgId;

static const int BLIND_DURATION = 50;


public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	char sGameName[12];
	GetGameFolderName(sGameName, sizeof(sGameName));
	if( strcmp(sGameName, "left4dead", false) )
	{
		strcopy(error, err_max, "Plugin only supports Left 4 Dead 1.");
		return APLRes_SilentFailure;
	}
	g_FadeUserMsgId = GetUserMessageId("Fade");
	if (g_FadeUserMsgId == INVALID_MESSAGE_ID) {
		strcopy(error, err_max, "Cannot find Fade user message ID.");
		return APLRes_SilentFailure;
	}
	return APLRes_Success;
}

public void OnPluginStart()
{
	LoadTranslations("Block3Person.phrases");
	HookEvent("round_start", OnRoundStart, EventHookMode_PostNoCopy);
}

public Action OnRoundStart(Event event, const char[] name, bool dontBroadcast) 
{
	CreateTimer(0.9, Timer_CheckClientViewState, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	return Plugin_Continue;
}  

public Action Timer_CheckClientViewState(Handle timer)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i) && GetClientTeam(i) == 2 && !IsFakeClient(i) && IsPlayerAlive(i))
			QueryClientConVar(i, "c_thirdpersonshoulder", QueryClientConVarCallback);
	}
	return Plugin_Continue;
}

public void QueryClientConVarCallback(QueryCookie cookie, int client, ConVarQueryResult result, const char[] sCvarName, const char[] bCvarValue)
{
	if (StringToInt(bCvarValue) != 0) {
		if (!aBlinded[client]) {
			aBlinded[client] = true;
			BlindClient(client, true);
			PrintHintText(client, "%t", "Blind_Warning");
		}
	} else {
		if (aBlinded[client]) {
			aBlinded[client] = false;
			PrintHintText(client, "%t", "Unblind_tip");
			BlindClient(client, false);
		}
	}
}

void BlindClient(int target, bool bDoBlind = true)
{
	int targets[2];
	targets[0] = target;
	
	int holdtime;

	int flags;
	if (!bDoBlind)
	{
		flags = (0x0001 | 0x0010);
		holdtime = 10000;
	}
	else
	{
		flags = (0x0002 | 0x0008);
		holdtime = 10;
	}
	
	int color[4] = { 0, 0, 0, 0 };
	color[3] = 255;
	
	Handle message = StartMessageEx(g_FadeUserMsgId, targets, 1);
	if (GetUserMessageType() == UM_Protobuf)
	{
		Protobuf pb = UserMessageToProtobuf(message);
		pb.SetInt("duration", BLIND_DURATION);
		pb.SetInt("hold_time", holdtime);
		pb.SetInt("flags", flags);
		pb.SetColor("clr", color);
	}
	else
	{
		BfWrite bf = UserMessageToBfWrite(message);
		bf.WriteShort(BLIND_DURATION);
		bf.WriteShort(holdtime);
		bf.WriteShort(flags);
		bf.WriteByte(color[0]);
		bf.WriteByte(color[1]);
		bf.WriteByte(color[2]);
		bf.WriteByte(color[3]);
	}
	
	EndMessage();
}