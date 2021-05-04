#pragma semicolon 1
#pragma newdecls required

//#define DEBUG

#define PLUGIN_VERSION "1.0"

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <left4dhooks>
#include <jutils.inc>
#include <sceneprocessor>
#include "l4d_survivor_identity_fix.inc"

static ArrayList LasersUsed;
static ConVar hLaserNotice, hFinaleTimer, hFFNotice, hMPGamemode, hPingDropThres;
static int iFinaleStartTime, botDropMeleeWeapon[MAXPLAYERS+1], iHighPingCount[MAXPLAYERS+1];
static bool isHighPingIdle[MAXPLAYERS+1], isL4D1Survivors;
static Handle hTakeOverBot, hGoAwayFromKeyboard;

static float OUT_OF_BOUNDS[3] = {0.0, -1000.0, 0.0};

//TODO: Drop melee on death AND clear on respawn by defib.
//TODO: Auto increase abm_minplayers based on highest player count

public Plugin myinfo = {
	name = "L4D2 Misc Tools",
	author = "Includes: Notice on laser use, Timer for gauntlet runs",
	description = "jackzmc", 
	version = PLUGIN_VERSION, 
	url = ""
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    MarkNativeAsOptional("IdentityFix_SetPlayerModel");
    return APLRes_Success;
}

public void OnPluginStart() {
	EngineVersion g_Game = GetEngineVersion();
	if(g_Game != Engine_Left4Dead2) {
		SetFailState("This plugin is for L4D2 only.");	
	}
	LoadTranslations("common.phrases");

	Handle hConfig = LoadGameConfigFile("l4d2tools");
	if(hConfig == INVALID_HANDLE) SetFailState("Could not load l4d2tools gamedata.");
	StartPrepSDKCall(SDKCall_Player);
	PrepSDKCall_SetFromConf(hConfig, SDKConf_Signature, "TakeOverBot");
	hTakeOverBot = EndPrepSDKCall();
	StartPrepSDKCall(SDKCall_Player);
	PrepSDKCall_SetFromConf(hConfig, SDKConf_Signature, "GoAwayFromKeyboard");
	hGoAwayFromKeyboard = EndPrepSDKCall();
	CloseHandle(hConfig);
	if(hTakeOverBot == INVALID_HANDLE || hGoAwayFromKeyboard == INVALID_HANDLE) {
		SetFailState("One of 3 signatures is invalid");
	}
	
	hLaserNotice 	= CreateConVar("sm_laser_use_notice", "1.0", "Enable notification of a laser box being used", FCVAR_NONE, true, 0.0, true, 1.0);
	hFinaleTimer 	= CreateConVar("sm_time_finale", "0.0", "Record the time it takes to complete finale. 0 -> OFF, 1 -> Gauntlets Only, 2 -> All finales", FCVAR_NONE, true, 0.0, true, 2.0);
	hFFNotice    	= CreateConVar("sm_ff_notice", "0.0", "Notify players if a FF occurs. 0 -> Disabled, 1 -> In chat, 2 -> In Hint text", FCVAR_NONE, true, 0.0, true, 2.0);
	hPingDropThres 	= CreateConVar("sm_autoidle_ping_max", "0.0", "The highest ping a player can have until they will automatically go idle.\n0=OFF, Min is 30", FCVAR_NONE, true, 0.0, true, 1000.0);
	hMPGamemode  = FindConVar("mp_gamemode");

	hFFNotice.AddChangeHook(CVC_FFNotice);
	if(hFFNotice.IntValue > 0) {
		HookEvent("player_hurt", Event_PlayerHurt);
	}

	LasersUsed = new ArrayList(1, 0);

	HookEvent("player_use", Event_PlayerUse);
	HookEvent("round_end", Event_RoundEnd);
	HookEvent("gauntlet_finale_start", Event_GauntletStart);
	HookEvent("finale_start", Event_FinaleStart);
	HookEvent("finale_vehicle_leaving", Event_FinaleEnd);
	HookEvent("player_bot_replace", Event_BotPlayerSwap);
	HookEvent("bot_player_replace", Event_BotPlayerSwap);

	AutoExecConfig(true, "l4d2_tools");

	for(int client = 1; client < MaxClients; client++) {
		if(IsClientConnected(client) && IsClientInGame(client) && GetClientTeam(client) == 2) {
			if(IsFakeClient(client)) {
				SDKHook(client, SDKHook_WeaponDrop, Event_OnWeaponDrop);
			}
		}
	}

	HookUserMessage(GetUserMessageId("VGUIMenu"), VGUIMenu, true);

	RegAdminCmd("sm_model", Command_SetClientModel, ADMFLAG_ROOT);
	RegAdminCmd("sm_surv", Cmd_SetSurvivor, ADMFLAG_ROOT);
	RegAdminCmd("sm_respawn_all", Command_RespawnAll, ADMFLAG_CHEATS, "Makes all dead players respawn in a closet");
	RegConsoleCmd("sm_pmodels", Command_ListClientModels, "Lists all player's models");

	CreateTimer(5.0, Timer_CheckPlayerPings, _, TIMER_REPEAT);
}

public Action Timer_CheckPlayerPings(Handle timer) {
	if(hPingDropThres.IntValue != 0) {
		for (int i = 1; i <= MaxClients; i++ ) {
			if(IsClientConnected(i) && IsClientInGame(i) && !IsFakeClient(i) && IsPlayerAlive(i) && GetClientTeam(i) > 1) {
				int ping = GetEntProp(GetPlayerResourceEntity(), Prop_Send, "m_iPing", _, i);
				if(isHighPingIdle[i] && ping <= hPingDropThres.IntValue) {
					SDKCall(hTakeOverBot, i);
					isHighPingIdle[i] = false;
				}else if(ping > hPingDropThres.IntValue) {
					if(iHighPingCount[i]++ > 2) {
						PrintToChat(i, "Due to your high ping (%d ms) you have been moved to AFK.", ping);
						PrintToChat(i, "You will be automatically switched back once your ping restores");
						SDKCall(hGoAwayFromKeyboard, i);
						isHighPingIdle[i] = true;
						iHighPingCount[i] = 0;
					}

				}
			}
		}
	}
	return Plugin_Continue;
}

public void CVC_FFNotice(ConVar convar, const char[] oldValue, const char[] newValue) {
	if(convar.IntValue > 0) {
		HookEvent("player_hurt", Event_PlayerHurt);
	}else {
		UnhookEvent("player_hurt", Event_PlayerHurt);
	}
}

public Action Event_RoundEnd(Event event, const char[] name, bool dontBroadcast) {
	LasersUsed.Clear();
}
public Action Command_RespawnAll(int client, int args) {
	L4D_CreateRescuableSurvivors();
}
//TODO: Implement idle bot support
public Action Command_ListClientModels(int client, int args) {
	char model[64];
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2) {
			GetClientModel(i, model, sizeof(model));
			ReplyToCommand(client, "%N's model: %s", i, model);
		}
	}
}
public Action Command_SetClientModel(int client, int args) {
	if(args < 1) {
		ReplyToCommand(client, "Usage: sm_model <player> <model> [keep]");
	}else{
		char arg1[32], arg2[16], arg3[8];
		GetCmdArg(1, arg1, sizeof(arg1));
		GetCmdArg(2, arg2, sizeof(arg2));
		GetCmdArg(3, arg3, sizeof(arg3));

		char modelPath[64];
		int modelID = GetSurvivorId(arg2, false);
		if(modelID == -1) {
			ReplyToCommand(client, "Invalid survivor type entered. Case-sensitive, full name required.");
			return Plugin_Handled;
		}
		GetSurvivorModel(modelID, modelPath, sizeof(modelPath));
		//Convert the l4d1 survivors to proper l4d1 ID if game is l4d1
		if(isL4D1Survivors) modelID = GetSurvivorId(arg2, true);

		char target_name[MAX_TARGET_LENGTH];
		int target_list[MAXPLAYERS], target_count;
		bool tn_is_ml;
		if ((target_count = ProcessTargetString(
				arg1,
				client,
				target_list,
				MAXPLAYERS,
				COMMAND_FILTER_CONNECTED,
				target_name,
				sizeof(target_name),
				tn_is_ml)) <= 0)
		{
			/* This function replies to the admin with a failure message */
			ReplyToTargetError(client, target_count);
			return Plugin_Handled;
		}
		int target;
		for (int i = 0; i < target_count; i++) {
			target = target_list[i];
			bool keepModel = StrEqual(arg3, "keep", false);
			if(IsClientConnected(target) && IsClientInGame(target) && IsPlayerAlive(target)) {
				int team = GetClientTeam(target_list[i]);
				if(team == 2 || team == 4) {
					SetEntProp(target, Prop_Send, "m_survivorCharacter", modelID);
					SetEntityModel(target, modelPath);
					if (IsFakeClient(target)) {
						char name[32];
						GetSurvivorName(target, name, sizeof(name));
						SetClientInfo(target, "name", name);
					}
					UpdatePlayerIdentity(target, view_as<Character>(modelID), keepModel);

					int weapon = GetPlayerWeaponSlot(target, 0);
					if( weapon != -1 ) {
						DataPack pack = new DataPack();
						pack.WriteCell(GetClientUserId(target));
						pack.WriteCell(EntIndexToEntRef(weapon)); // Save last held weapon to switch back

						CreateTimer(0.2, Timer_RequipWeapon, pack);
					}
				}
			}
		}
	}
	return Plugin_Handled;
}

public Action Cmd_SetSurvivor(int client, int args) {
	if(args < 1) {
		ReplyToCommand(client, "Usage: sm_surv <player> <survivor>");
	}else{
		char arg1[32], arg2[16];
		GetCmdArg(1, arg1, sizeof(arg1));
		GetCmdArg(2, arg2, sizeof(arg2));

		int modelID = GetSurvivorId(arg2);
		if(modelID == -1) {
			ReplyToCommand(client, "Invalid survivor type entered. Case-sensitive, full name required.");
			return Plugin_Handled;
		}
		char target_name[MAX_TARGET_LENGTH];
		int target_list[MAXPLAYERS], target_count;
		bool tn_is_ml;
		if ((target_count = ProcessTargetString(
				arg1,
				client,
				target_list,
				MAXPLAYERS,
				COMMAND_FILTER_CONNECTED,
				target_name,
				sizeof(target_name),
				tn_is_ml)) <= 0)
		{
			/* This function replies to the admin with a failure message */
			ReplyToTargetError(client, target_count);
			return Plugin_Handled;
		}
		int target;
		for (int i = 0; i < target_count; i++) {
			target = target_list[i];
			SetEntProp(target, Prop_Send, "m_survivorCharacter", modelID);
		}
	}
	return Plugin_Handled;
}

public Action Timer_RequipWeapon(Handle hdl, DataPack pack) {
	pack.Reset();
	int client = GetClientOfUserId(pack.ReadCell());
	if(client == 0) return;

	int weapon;
	
	while( pack.IsReadable() )
	{
		weapon = pack.ReadCell();
		if( EntRefToEntIndex(weapon) != INVALID_ENT_REFERENCE ) {
			EquipPlayerWeapon(client, weapon);
		}
	}
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
				PrintToChat(client, "Could not give back your melee weapon, %N has it instead.", meleeOwnerEnt);
			}
		}
		SDKUnhook(bot, SDKHook_WeaponDrop, Event_OnWeaponDrop);
	}
}
public Action VGUIMenu(UserMsg msg_id, Handle bf, const int[] players, int playersNum, bool reliable, bool init) {
	char buffer[5];
	BfReadString(bf, buffer, sizeof(buffer));
	return StrEqual(buffer, "info") ? Plugin_Handled : Plugin_Continue;
}  
//TODO: Might have to actually check for the bot they control, or possibly the bot will call this itself.
public void OnClientDisconnect(int client) {
	if(IsClientConnected(client) && IsClientInGame(client) && botDropMeleeWeapon[client] > -1) {
		float pos[3];
		GetClientAbsOrigin(client, pos);
		TeleportEntity(botDropMeleeWeapon[client], pos, NULL_VECTOR, NULL_VECTOR);
		botDropMeleeWeapon[client] = -1;
	}
}
public void OnMapStart() {
	HookEntityOutput("info_changelevel", "OnStartTouch", EntityOutput_OnStartTouchSaferoom);
	HookEntityOutput("trigger_changelevel", "OnStartTouch", EntityOutput_OnStartTouchSaferoom);
	char output[2];
	L4D2_GetVScriptOutput("Director.GetSurvivorSet()", output, sizeof(output));
	isL4D1Survivors = StringToInt(output) == 1;
}

public void OnSceneStageChanged(int scene, SceneStages stage) {
	if(stage == SceneStage_Started) {
		char sceneFile[64];
		GetSceneFile(scene, sceneFile, sizeof(sceneFile));
		int activator = GetSceneInitiator(scene);
		if(StrContains(sceneFile, "scenes/mechanic/dlc1_c6m1_initialmeeting") > -1 || StrEqual(sceneFile, "scenes/teengirl/dlc1_c6m1_initialmeeting07.vcd")) {
			CancelScene(scene);
		}else if(StrEqual(sceneFile, "scenes/teengirl/dlc1_c6m1_initialmeeting13.vcd") && activator == 0) {
			CancelScene(scene);
		}
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

public void EntityOutput_OnStartTouchSaferoom(const char[] output, int caller, int client, float time) {
	if(client > 0 && client <= MaxClients && IsValidClient(client) && GetClientTeam(client) == 2) {
		if(botDropMeleeWeapon[client] > 0) {
			PrintToServer("Giving melee weapon back to %N", client);
			float pos[3];
			GetClientAbsOrigin(client, pos);
			TeleportEntity(botDropMeleeWeapon[client], pos, NULL_VECTOR, NULL_VECTOR);
			EquipPlayerWeapon(client, botDropMeleeWeapon[client]);
			botDropMeleeWeapon[client] = -1;
		}
		char currentGamemode[16];
		hMPGamemode.GetString(currentGamemode, sizeof(currentGamemode));
		if(StrEqual(currentGamemode, "tankrun", false)) {
			if(!IsFakeClient(client)) {
				CreateTimer(1.0, Timer_TPBots, client, TIMER_FLAG_NO_MAPCHANGE);
			}
		}
	}
}

public Action Timer_TPBots(Handle timer, int user) {
	float pos[3];
	GetClientAbsOrigin(user, pos);
	for(int i = 1; i < MaxClients + 1; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && IsFakeClient(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i)) {
			TeleportEntity(i, pos, NULL_VECTOR, NULL_VECTOR);
			L4D2_RunScript("CommandABot({cmd=1,bot=GetPlayerFromUserID(%i),pos=Vector(%f,%f,%f)})", GetClientUserId(i), pos[0], pos[1], pos[2]);
			
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
		char entity_name[32];
		int player_id = GetClientOfUserId(event.GetInt("userid"));
		int target_id = event.GetInt("targetid");
	
		GetEntityClassname(target_id, entity_name, sizeof(entity_name));
		
		if(StrEqual(entity_name,"upgrade_laser_sight")) {
			if(LasersUsed.FindValue(target_id) == -1) {
				LasersUsed.Push(target_id);
				PrintToChatAll("%N picked up laser sights", player_id);
			}
		}	
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

stock int GetRealClient(int client) {
	if(IsFakeClient(client)) {
		int realPlayer = GetClientOfUserId(GetEntProp(client, Prop_Send, "m_humanSpectatorUserID"));
		return realPlayer > 0 ? realPlayer : -1;
	}else{
		return client;
	}
}

stock int GetIdleBot(int client) {
	for(int i = 1; i <= MaxClients; i++ ) {
		if(IsClientConnected(i) && HasEntProp(i, Prop_Send, "m_humanSpectatorUserID")) {
			int realPlayer = GetClientOfUserId(GetEntProp(i, Prop_Send, "m_humanSpectatorUserID"));
			if(realPlayer == client) {
				return i;
			}
		}
	}
	return -1;
}