#pragma semicolon 1
#pragma newdecls required

//#define DEBUG

#define PLUGIN_VERSION "1.0"

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <left4dhooks>
#include "jutils.inc"

static bool bLasersUsed[2048];
static ConVar hLaserNotice, hFinaleTimer, hFFNotice, hMPGamemode;
static int iFinaleStartTime, botDropMeleeWeapon[MAXPLAYERS+1];

static float OUT_OF_BOUNDS[3] = {0.0, -1000.0, 0.0};
static int extraKitsAmount = 0;

//TODO: Remove the Plugin_Stop on pickup, and give item back instead. keep reference to dropped weapon to delete.
public Plugin myinfo = {
	name = "L4D2 Misc Tools",
	author = "Includes: Notice on laser use, Timer for gauntlet runs",
	description = "jackzmc", 
	version = PLUGIN_VERSION, 
	url = ""
};

//TODO: Implement automatic extra kits
public void OnPluginStart() {
	EngineVersion g_Game = GetEngineVersion();
	if(g_Game != Engine_Left4Dead && g_Game != Engine_Left4Dead2) {
		SetFailState("This plugin is for L4D/L4D2 only.");	
	}
	LoadTranslations("common.phrases");
	
	hLaserNotice = CreateConVar("sm_laser_use_notice", "1.0", "Enable notification of a laser box being used", FCVAR_NONE, true, 0.0, true, 1.0);
	hFinaleTimer = CreateConVar("sm_time_finale", "0.0", "Record the time it takes to complete finale. 0 -> OFF, 1 -> Gauntlets Only, 2 -> All finales", FCVAR_NONE, true, 0.0, true, 2.0);
	hFFNotice    = CreateConVar("sm_ff_notice", "0.0", "Notify players if a FF occurs. 0 -> Disabled, 1 -> In chat, 2 -> In Hint text", FCVAR_NONE, true, 0.0, true, 2.0);
	hMPGamemode = FindConVar("mp_gamemode");

	HookEvent("player_use", Event_PlayerUse);
	HookEvent("player_hurt", Event_PlayerHurt);
	HookEvent("round_end", Event_RoundEnd);
	HookEvent("gauntlet_finale_start", Event_GauntletStart);
	HookEvent("finale_start", Event_FinaleStart);
	HookEvent("finale_vehicle_leaving", Event_FinaleEnd);
	HookEvent("player_entered_checkpoint", Event_EnterSaferoom);
	HookEvent("player_bot_replace", Event_BotPlayerSwap);
	HookEvent("bot_player_replace", Event_BotPlayerSwap);
	HookEvent("map_transition", Event_MapTransition);

	AutoExecConfig(true, "l4d2_tools");

	for(int client = 1; client < MaxClients; client++) {
		if(IsClientConnected(client) && IsClientInGame(client) && GetClientTeam(client) == 2) {
			if(IsFakeClient(client))
				SDKHook(client, SDKHook_WeaponDrop, Event_OnWeaponDrop);
		}
	}

	RegAdminCmd("sm_model", Command_SetClientModel, ADMFLAG_ROOT);
}
//TODO: Give kits on fresh start as well, need to set extraKitsAmount
public void OnMapStart() {
	if(L4D_IsFirstMapInScenario()) {
		extraKitsAmount = GetClientCount(true) - 4;
		if(extraKitsAmount < 0) extraKitsAmount = 0;
		PrintToServer("New map has started");
	}
	if(extraKitsAmount > 0) {
		for(int i = 1; i < MaxClients + 1; i++) {
			if(IsClientConnected(i) && IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == 2) {
				PrintToServer("Found a client to spawn %d extra kits: %N", extraKitsAmount, i);
				while(extraKitsAmount > 0) {
					CheatCommand(i, "give", "first_aid_kit", "");
					extraKitsAmount--;
				}
				break;
			}
		}
	}
}

public Action Command_SetClientModel(int client, int args) {
	if(args < 1) {
		ReplyToCommand(client, "Usage: sm_model <player> <model>");
	}else{
		char arg1[32], arg2[16];
		GetCmdArg(1, arg1, sizeof(arg1));
		GetCmdArg(2, arg2, sizeof(arg2));

		char modelPath[64];
		int modelID = GetSurvivorId(arg2);
		if(modelID == -1) {
			ReplyToCommand(client, "Could not find a valid survivor.");
			return Plugin_Handled;
		}
		GetSurvivorModel(modelID, modelPath, sizeof(modelPath));

		char target_name[MAX_TARGET_LENGTH];
		int target_list[MAXPLAYERS], target_count;
		bool tn_is_ml;
		if ((target_count = ProcessTargetString(
				arg1,
				client,
				target_list,
				MAXPLAYERS,
				COMMAND_FILTER_ALIVE, /* Only allow alive players */
				target_name,
				sizeof(target_name),
				tn_is_ml)) <= 0)
		{
			/* This function replies to the admin with a failure message */
			ReplyToTargetError(client, target_count);
			return Plugin_Handled;
		}
		for (int i = 0; i < target_count; i++) {
			if(IsClientConnected(target_list[i]) && IsClientInGame(target_list[i]) && IsPlayerAlive(target_list[i]) && GetClientTeam(target_list[i]) == 2) {
				SetEntProp(target_list[i], Prop_Send, "m_survivorCharacter", modelID);
				SetEntityModel(target_list[i], modelPath);
				if (IsFakeClient(target_list[i])) {
					char name[32];
					GetSurvivorName(target_list[i], name, sizeof(name));
					SetClientInfo(target_list[i], "name", name);
				}

				int primaryWeapon = GetPlayerWeaponSlot(client, 0);
				if(primaryWeapon > -1) {
					SDKHooks_DropWeapon(target_list[i], primaryWeapon, NULL_VECTOR, NULL_VECTOR);

					Handle pack;
					CreateDataTimer(0.1, Timer_RequipWeapon, pack);
					WritePackCell(pack, target_list[i]);
					WritePackCell(pack, primaryWeapon);
				}
			}
		}
	}
	return Plugin_Handled;
}

public Action Timer_RequipWeapon(Handle hdl, Handle pack) {
	ResetPack(pack);
	int client = ReadPackCell(pack);
	int weaponID = ReadPackCell(pack);
	EquipPlayerWeapon(client, weaponID);
}

public Action Event_BotPlayerSwap(Event event, const char[] name, bool dontBroadcast) {
	int bot = GetClientOfUserId(event.GetInt("bot"));
	if(StrEqual(name, "player_bot_replace")) {
		//Bot replaced player
		SDKHook(bot, SDKHook_WeaponDrop, Event_OnWeaponDrop);
	}else{
		//Player replaced a bot
		int client = GetClientOfUserId(event.GetInt("player"));
		if(botDropMeleeWeapon[bot] > 0) {
			int meleeOwnerEnt = GetEntPropEnt(botDropMeleeWeapon[bot], Prop_Send, "m_hOwnerEntity");
			if(meleeOwnerEnt == -1) { 
				EquipPlayerWeapon(client, botDropMeleeWeapon[bot]);
				botDropMeleeWeapon[bot] = -1;
			}else{
				PrintToConsole(client, "Could not give back your melee weapon, %N has it instead.", meleeOwnerEnt);
			}
		}
		SDKUnhook(bot, SDKHook_WeaponDrop, Event_OnWeaponDrop);
	}
}
//TODO: Might have to actually check for the bot they control, or possibly the bot will call this itself.
public void OnClientDisconnect(int client) {
	if(botDropMeleeWeapon[client] > -1) {
		float pos[3];
		GetClientAbsOrigin(client, pos);
		TeleportEntity(botDropMeleeWeapon[client], pos, NULL_VECTOR, NULL_VECTOR);
		botDropMeleeWeapon[client] = -1;
	}
}

public Action Event_OnWeaponDrop(int client, int weapon) {
	if(!IsValidEntity(weapon)) return Plugin_Continue;
	char wpn[32];
	GetEdictClassname(weapon, wpn, sizeof(wpn));
	if(IsFakeClient(client) && StrEqual(wpn, "weapon_melee") && GetEntProp(client, Prop_Send, "m_humanSpectatorUserID") > 0) {
		#if defined DEBUG 0
		PrintToServer("Bot %N dropped melee weapon %s", client, wpn);
		#endif
		RequestFrame(Frame_HideEntity, weapon);
		botDropMeleeWeapon[client] = weapon;
	}
	return Plugin_Continue;
}
public void Frame_HideEntity(int entity) {
	TeleportEntity(entity, OUT_OF_BOUNDS, NULL_VECTOR, NULL_VECTOR);
}

public void Event_EnterSaferoom(Event event, const char[] name, bool dontBroadcast) {
	int user = GetClientOfUserId(event.GetInt("userid"));
	if(user == 0) return;
	if(botDropMeleeWeapon[user] > -1) {
		float pos[3];
		GetClientAbsOrigin(user, pos);
		TeleportEntity(botDropMeleeWeapon[user], pos, NULL_VECTOR, NULL_VECTOR);
		botDropMeleeWeapon[user] = -1;
	}
	char currentGamemode[16];
	hMPGamemode.GetString(currentGamemode, sizeof(currentGamemode));
	if(StrEqual(currentGamemode, "tankrun", false)) {
		if(!IsFakeClient(user)) {
			CreateTimer(1.0, Timer_TPBots, user);
		}
	}
}

public Action Timer_TPBots(Handle timer, any user) {
	float pos[3];
	GetClientAbsOrigin(user, pos);
	for(int i = 1; i < MaxClients; i++) {
		if(IsClientInGame(i) && IsFakeClient(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i)) {
			TeleportEntity(i, pos, NULL_VECTOR, NULL_VECTOR);
		}
	}
}

//laserNotice
public void Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast) {
	if(hFFNotice.IntValue > 0) {
		int victim = GetClientOfUserId(event.GetInt("userid"));
		int attacker = GetClientOfUserId(event.GetInt("attacker"));
		int dmg = event.GetInt("dmg_health");
		if(dmg > 0) {
			if(attacker > 0 && !IsFakeClient(attacker) && attacker != victim) {
				if(GetClientTeam(attacker) == 2 && GetClientTeam(victim) == 2) {
					if(hFFNotice.IntValue == 1) {
						PrintHintTextToAll("%N has done %d HP of friendly fire damage to %N", attacker, dmg, victim);
					}else{
						PrintToChatAll("%N has done %d HP of friendly fire damage to %N", attacker, dmg, victim);
					}
				}
			}
		}
	}
}
public void Event_PlayerUse(Event event, const char[] name, bool dontBroadcast) {
	if(hLaserNotice.BoolValue) {
		char player_name[32], entity_name[32];
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
	}
}
public void Event_FinaleStart(Event event, const char[] name, bool dontBroadcast) {
	if(hFinaleTimer.IntValue == 2) {
		iFinaleStartTime = GetTime();
	}
}
public void Event_FinaleEnd(Event event, const char[] name, bool dontBroadcast) {
	if(hFinaleTimer.IntValue != 0) {
		if(iFinaleStartTime != 0) {
			int difference = GetTime() - iFinaleStartTime;
			
			char time[32];
			FormatSeconds(difference, time, sizeof(time));
			PrintToChatAll("Finale took %s to complete", time);
			iFinaleStartTime = 0;
		}
	}
}
public void Event_CarAlarmTriggered(Event event, const char[] name, bool dontBroadcast) {
	int userID = GetClientOfUserId(event.GetInt("userid"));
	PrintToChatAll("%N activated a car alarm!", userID);
}
public Action Event_MapTransition(Event event, const char[] name, bool dontBroadcast) {
	extraKitsAmount = GetClientCount(true) - 4;
	if(extraKitsAmount < 0) extraKitsAmount = 0;
	PrintToServer("Will spawn an extra %d kits", extraKitsAmount);
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