#pragma semicolon 1
#pragma newdecls required

//#define DEBUG

#define PLUGIN_VERSION "1.0"

#include <sourcemod>
#include <sdktools>
//#include <sdkhooks>

public Plugin myinfo = 
{
	name =  "L4D2 Vocalize Control", 
	author = "jackzmc", 
	description = "", 
	version = PLUGIN_VERSION, 
	url = ""
};

ArrayList gaggedPlayers[MAXPLAYERS];

public void OnPluginStart()
{
	EngineVersion g_Game = GetEngineVersion();
	if(g_Game != Engine_Left4Dead2)
	{
		SetFailState("This plugin is for L4D2 only.");	
	}

	for(int i = 0; i < sizeof(gaggedPlayers); i++) {
        gaggedPlayers[i] = new ArrayList(MAXPLAYERS - 1);
    }

	HookEvent("player_disconnect", Event_PlayerDisconnect);

	RegConsoleCmd("sm_vgag", Cmd_VGag, "Gags a player\'s vocalizations locally");
	AddNormalSoundHook(view_as<NormalSHook>(SoundHook));
}

public void Event_PlayerDisconnect(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(client > 0) {
		//Clear the player's list of gagged
		gaggedPlayers[client].Clear();
		//Remove this player from any other player's gag list
		for(int i = 0; i <= MaxClients; i++) {
			int index = gaggedPlayers[i].FindValue(client);
			if(index > -1) {
				gaggedPlayers[i].Erase(index);
			}
		}
	}
}

public Action Cmd_VGag(int client, int args) {
    if(args < 1) {
		ReplyToCommand(client, "Usage: sm_vgag <player>");
	} else {
		char arg1[32];
		GetCmdArg(1, arg1, sizeof(arg1));
		char target_name[MAX_TARGET_LENGTH];
		int target_list[MAXPLAYERS], target_count;
		bool tn_is_ml;
		if ((target_count = ProcessTargetString(
				arg1,
				client,
				target_list,
				MAXPLAYERS,
				COMMAND_FILTER_ALIVE,
				target_name,
				sizeof(target_name),
				tn_is_ml)) <= 0)
		{
			ReplyToTargetError(client, target_count);
			return Plugin_Handled;
		}
		for (int i = 0; i < target_count; i++) {
            int playerIndex = gaggedPlayers[client].FindValue(target_list[i]);
            if(playerIndex > -1) {
                gaggedPlayers[client].Erase(playerIndex);
                ReplyToCommand(client, "Locally vocalize ungagged %s", target_name);
            }else{
                gaggedPlayers[client].Push(target_list[i]);
                ReplyToCommand(client, "Locally vocalize gagged %s", target_name);
            }
		}
	}
    return Plugin_Handled;
}

public Action SoundHook(int[] clients, int& numClients, char sample[PLATFORM_MAX_PATH], int& entity, int& channel, float& volume, int& level, int& pitch, int& flags, char[] soundEntry, int& seed) {
	if(numClients > 0 && entity > 0 && entity <= MaxClients) {
		if(StrContains(sample, "survivor\\voice") > -1) {
			for(int i = 0; i < numClients; i++) {
                int client = clients[i];
                if(gaggedPlayers[client].FindValue(entity) > -1) {
					// Swap gagged player to end of list, then remove it (dec. numClients is effectively same)
					int swap = clients[numClients - 1];
					clients[numClients - 1] = client;
					clients[i] = swap;
					numClients -= 1;
					return Plugin_Handled;
                    //Remove client from clients
                }
            }
		}
		
	}
	return Plugin_Continue;
}
