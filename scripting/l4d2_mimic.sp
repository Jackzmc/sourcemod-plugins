#pragma semicolon 1
#pragma newdecls required

//#define DEBUG

#define PLUGIN_VERSION "1.0"

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <jutils>
#include <left4dhooks>

int g_mimicBot;
int g_mimicController;
int g_mimicCamera;

public Plugin myinfo = 
{
	name =  "L4D2 Mimic", 
	author = "jackzmc", 
	description = "", 
	version = PLUGIN_VERSION, 
	url = "https://github.com/Jackzmc/sourcemod-plugins"
};

public void OnPluginStart() {
	EngineVersion g_Game = GetEngineVersion();
	if(g_Game != Engine_Left4Dead && g_Game != Engine_Left4Dead2) {
		SetFailState("This plugin is for L4D/L4D2 only.");	
	}

	RegAdminCmd("sm_mimic", Command_Mimic, ADMFLAG_CHEATS);
	HookEvent("player_bot_replace", Event_BotToIdle);
	AddCommandListener(OnCommand);
}

public void OnPluginEnd() {
	StopMimic();
}

#define PASSTHROUGH_COMMANDS_MAX 10
char PASSTHROUGH_COMMANDS[PASSTHROUGH_COMMANDS_MAX][] = {
	"say",
	"vocalize",
	"sm_give",
	"give",
	"sm_say",
	"sm_chat",
	"use",
	"sm_slay",
	"sm_model",
	"sm_surv",
};

Action OnCommand(int client, const char[] command, int argc) {
	if(g_mimicController == 0 || client != g_mimicController) return Plugin_Continue;
	for(int i = 0; i < PASSTHROUGH_COMMANDS_MAX; i++) {
		if(StrEqual(command, PASSTHROUGH_COMMANDS[i])) {
			char args[256];
			GetCmdArgString(args, sizeof(args));
			// PrintToServer("pass: %s %s", command, args);
			FakeClientCommandEx(g_mimicBot, "%s %s", command, args);
			return Plugin_Handled;
		}
	}
	// PrintToServer("ignore: %s", command);
	return Plugin_Continue;
}

void Event_BotToIdle(Event event, const char[] name, bool dontBroadcast) {
	int player = GetClientOfUserId(event.GetInt("player"));
	int bot    = GetClientOfUserId(event.GetInt("bot")); 
	if(g_mimicBot == player) {
		KickClient(bot);
		RequestFrame(SetupMimic);
	}
}
public void OnClientDisconnect(int client) {
	if(client == g_mimicBot || client == g_mimicController) {
		StopMimic();
	}
}

Action Command_Mimic(int client, int args) {
	if(g_mimicController != 0) {
		if(g_mimicController == client) {
			StopMimic();
		} else {
			ReplyToCommand(client, "Mimic is currently active by another player.");
		}
	} else if(args > 0) {
		char name[32], id[4];
		GetCmdArg(1, name, sizeof(name));
		int survivorId = -1;
		if(args > 1) {
			GetCmdArg(2, id, sizeof(id));
			survivorId = GetSurvivorId(id, L4D2_GetSurvivorSetMap() == 0);
		}
		StartMimic(client, name, survivorId);
	} else {
		ReplyToCommand(client, "Enter name");
	}
	return Plugin_Handled;
}

void StartMimic(int controller, const char[] name, int survivorId = -1) {
	int bot = CreateFakeClient(name);
	if(bot == -1) {
		PrintToChat(controller, "Could not spawn fake client");
		return;
	}
	DispatchKeyValue(bot, "classname", "SurvivorBot");
		
	ChangeClientTeam(bot, 2);
	if(!DispatchSpawn(bot)) {
		PrintToChat(controller, "Could not dispatch spawn");
		return;
	}
	L4D_RespawnPlayer(bot);

	char model[128];
	GetEntPropString(controller, Prop_Data, "m_ModelName", model, sizeof(model));
	SetEntityModel(bot, model);

	int camera = CreateEntityByName("point_viewcontrol_survivor");
	DispatchKeyValue(camera, "targetname", "mimic_cam");
	DispatchSpawn(camera);

	g_mimicBot = bot;
	g_mimicController = controller;
	g_mimicCamera = camera;

	SDKHook(controller, SDKHook_WeaponSwitchPost, OnWeaponSwitchPost);
	PrintToServer("controller: %N | bot: %N(#%d) | camera: %d", controller, bot, GetClientUserId(bot), camera);
	
	RequestFrame(SetupMimic, survivorId);
}

void SetupMimic(int survivorId = -1) {
	if(g_mimicController == 0) return;
	float pos[3], ang[3];
	GetClientAbsOrigin(g_mimicController, pos);
	int nav = L4D_GetNearestNavArea(pos);
	if(nav > 0) {
		L4D_FindRandomSpot(nav, pos);
	}
	TeleportEntity(g_mimicBot, pos, NULL_VECTOR, NULL_VECTOR);
	CheatCommand(g_mimicBot, "give", "rifle_ak47", "");
	CheatCommand(g_mimicBot, "give", "first_aid_kit", "");
	
	if(survivorId == -1) survivorId = GetEntProp(g_mimicController, Prop_Send, "m_survivorCharacter");
	SetEntProp(g_mimicBot, Prop_Send, "m_survivorCharacter", survivorId);


	AcceptEntityInput(g_mimicCamera, "Disable", g_mimicController);
	GetClientEyePosition(g_mimicBot, pos);
	GetClientEyeAngles(g_mimicBot, ang);
	ClearParent(g_mimicCamera);
	TeleportEntity(g_mimicCamera, pos, NULL_VECTOR, NULL_VECTOR);
	SetParent(g_mimicCamera, g_mimicBot);
	AcceptEntityInput(g_mimicCamera, "Enable", g_mimicController);
}

void OnWeaponSwitchPost(int client, int weapon) {
	if(g_mimicBot == 0) return;
	for(int slot = 0; slot < 5; slot++) {
		int slotWpn = GetPlayerWeaponSlot(client, slot);
		if(slotWpn == weapon) {
			ClientCommand(g_mimicBot, "slot%d", slot);
			return;
		}
	}
}



void StopMimic() {
	if(g_mimicBot > 0 && IsClientInGame(g_mimicBot)) {
		if(L4D_GoAwayFromKeyboard(g_mimicBot)) {
			int bot = L4D_GetBotOfIdlePlayer(g_mimicBot);
			if(bot > 0) {
				KickClient(bot);
			}
		}
		KickClient(g_mimicBot);
	}
	if(g_mimicCamera > 0 && IsValidEntity(g_mimicCamera)) {
		AcceptEntityInput(g_mimicCamera, "Disable");
		RemoveEntity(g_mimicCamera);
	}
	if(g_mimicController > 0 && IsClientConnected(g_mimicController)) {
		SDKUnhook(g_mimicController, SDKHook_WeaponSwitchPost, OnWeaponSwitchPost);
	}

	g_mimicBot = 0;
	g_mimicController = 0;
	g_mimicCamera = 0;
}

int prevButtons;
float prevAngles[3], prevVel[3];
public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon) {
	if(client == g_mimicController) {
		if(!IsPlayerAlive(client)) {
			StopMimic();
		}
		prevAngles = angles;
		prevButtons = buttons;
		prevVel = vel;
		SetEntPropFloat(client, Prop_Send, "m_flNextAttack", GetGameTime() + 1.0);
		// TeleportEntity(client, NULL_VECTOR, angles, NULL_VECTOR);
		return Plugin_Handled;
	} else if(client == g_mimicBot) {
		if(!IsPlayerAlive(client)) {
			StopMimic();
		}
		buttons = prevButtons | IN_BULLRUSH;
		angles = prevAngles;
		vel = prevVel;
		TeleportEntity(client, NULL_VECTOR, angles, NULL_VECTOR);
		return Plugin_Changed;
	}
	return Plugin_Continue;
}