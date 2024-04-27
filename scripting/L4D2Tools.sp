#pragma semicolon 1
#pragma newdecls required

#define DEBUG 1

#define PLUGIN_VERSION "1.0"

#define PRECACHE_SOUNDS_COUNT 4
char PRECACHE_SOUNDS[PRECACHE_SOUNDS_COUNT][] = {
	"custom/xen_teleport.mp3",
	"custom/mariokartmusic.mp3",
	"custom/spookyscaryskeletons.mp3",
	"custom/wearenumberone2.mp3",
};

#include <sourcemod>
#include <sdkhooks>
#include <left4dhooks>
#include <jutils.inc>
#undef REQUIRE_PLUGIN
#tryinclude <sceneprocessor>
#include <multicolors>
#include "l4d_survivor_identity_fix.inc"
#include <anymap>

char MODELS[8][] = {
	"models/survivors/survivor_gambler.mdl",
	"models/survivors/survivor_producer.mdl",
	"models/survivors/survivor_mechanic.mdl",
	"models/survivors/survivor_coach.mdl",
	"models/survivors/survivor_namvet.mdl",
	"models/survivors/survivor_teenangst.mdl",
	"models/survivors/survivor_biker.mdl",
	"models/survivors/survivor_manager.mdl"
};

enum L4DModelId {
	Model_Nick,
	Model_Rochelle,
	Model_Ellis,
	Model_Coach,
	Model_Bill,
	Model_Zoey,
	Model_Francis,
	Model_Louis
}

static ArrayList LasersUsed;
static ConVar hLaserNotice, hFinaleTimer, hFFNotice, hPingDropThres, hForceSurvivorSet, hPlayerLimit, hSVMaxPlayers, hHideMotd, hGamemode;
static int iFinaleStartTime, botDropMeleeWeapon[MAXPLAYERS+1], iHighPingCount[MAXPLAYERS+1];
static bool isHighPingIdle[MAXPLAYERS+1], isL4D1Survivors;
static Handle hGoAwayFromKeyboard;
static StringMap SteamIDs;
static char lastSound[MAXPLAYERS+1][64], gamemode[32];
AnyMap disabledItems;

static float OUT_OF_BOUNDS[3] = {0.0, -1000.0, 0.0};

public Plugin myinfo = {
	name = "L4D2 Misc Tools",
	author = "Includes: Notice on laser use, Timer for gauntlet runs",
	description = "jackzmc", 
	version = PLUGIN_VERSION, 
	url = "https://github.com/Jackzmc/sourcemod-plugins"
};

//TODO: On pickup ammo pack, mark dropped kit/defib 

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
	PrepSDKCall_SetFromConf(hConfig, SDKConf_Signature, "GoAwayFromKeyboard");
	hGoAwayFromKeyboard = EndPrepSDKCall();
	delete hConfig;

	if(hGoAwayFromKeyboard == INVALID_HANDLE) {
		SetFailState("GoAwayFromKeyboard signature is invalid");
	}

	hLaserNotice 	= CreateConVar("sm_laser_use_notice", "1.0", "Enable notification of a laser box being used", FCVAR_NONE, true, 0.0, true, 1.0);
	hFinaleTimer 	= CreateConVar("sm_time_finale", "0.0", "Record the time it takes to complete finale. 0 -> OFF, 1 -> Gauntlets Only, 2 -> All finales", FCVAR_NONE, true, 0.0, true, 2.0);
	hFFNotice    	= CreateConVar("sm_ff_notice", "0.0", "Notify players if a FF occurs. 0 -> Disabled, 1 -> In chat, 2 -> In Hint text", FCVAR_NONE, true, 0.0, true, 2.0);
	hPingDropThres 	= CreateConVar("sm_autoidle_ping_max", "0.0", "The highest ping a player can have until they will automatically go idle.\n0=OFF, Min is 30", FCVAR_NONE, true, 0.0, true, 1000.0);
	hForceSurvivorSet = FindConVar("l4d_force_survivorset");
	hHideMotd       = CreateConVar("sm_hidemotd", "1", "Hide the MOTD when the server is running", FCVAR_NONE, true, 0.0, true, 1.0);

	hSVMaxPlayers   = FindConVar("sv_maxplayers");
	if(hSVMaxPlayers != null) { 
		hPlayerLimit    = CreateConVar("sm_player_limit", "0", "Overrides sv_maxplayers. 0 = off, > 0: limit", FCVAR_NONE, true, 0.0, false);
		hPlayerLimit.AddChangeHook(Event_PlayerLimitChange);
		if(hPlayerLimit.IntValue > 0) hSVMaxPlayers.IntValue = hPlayerLimit.IntValue;
	}

	hFFNotice.AddChangeHook(CVC_FFNotice);
	if(hFFNotice.IntValue > 0) {
		HookEvent("player_hurt", Event_PlayerHurt);
	}

	LasersUsed = new ArrayList(1, 0);
	disabledItems = new AnyMap();
	SteamIDs = new StringMap();

	hGamemode = FindConVar("mp_gamemode"); 
	hGamemode.GetString(gamemode, sizeof(gamemode));
	hGamemode.AddChangeHook(Event_GamemodeChange);
	Event_GamemodeChange(hGamemode, gamemode, gamemode);

	HookEvent("player_use", Event_PlayerUse);
	HookEvent("round_end", Event_RoundEnd);
	HookEvent("gauntlet_finale_start", Event_GauntletStart);
	HookEvent("finale_start", Event_FinaleStart);
	HookEvent("finale_vehicle_leaving", Event_FinaleEnd);
	HookEvent("player_bot_replace", Event_BotPlayerSwap);
	HookEvent("bot_player_replace", Event_BotPlayerSwap);
	HookEvent("player_first_spawn", Event_PlayerFirstSpawn);
	HookEvent("weapon_drop", Event_WeaponDrop);
	HookEvent("player_disconnect", Event_PlayerDisconnect);

	AutoExecConfig(true, "l4d2_tools");

	for(int client = 1; client < MaxClients; client++) {
		if(IsClientConnected(client) && IsClientInGame(client) && GetClientTeam(client) == 2) {
			if(IsFakeClient(client)) {
				SDKHook(client, SDKHook_OnTakeDamage, Event_OnTakeDamageBot);
				SDKHook(client, SDKHook_WeaponDrop, Event_OnWeaponDrop);
			} else {
				SDKHook(client, SDKHook_WeaponEquip, Event_OnWeaponEquip);
			}
		}
	}

	HookUserMessage(GetUserMessageId("VGUIMenu"), VGUIMenu, true);

	RegAdminCmd("sm_model", Command_SetClientModel, ADMFLAG_KICK);
	RegAdminCmd("sm_surv", Cmd_SetSurvivor, ADMFLAG_KICK);
	RegAdminCmd("sm_respawn_all", Command_RespawnAll, ADMFLAG_CHEATS, "Makes all dead players respawn in a closet");
	RegAdminCmd("sm_playsound", Command_PlaySound, ADMFLAG_KICK, "Plays a gamesound for player");
	RegAdminCmd("sm_stopsound", Command_StopSound, ADMFLAG_GENERIC, "Stops the last played gamesound for player");
	RegAdminCmd("sm_swap", Command_SwapPlayer, ADMFLAG_KICK, "Swarms two player's locations");
	RegConsoleCmd("sm_pmodels", Command_ListClientModels, "Lists all player's models");
	RegAdminCmd("sm_skipoutro", Command_SkipOutro, ADMFLAG_KICK, "Skips the outro");

	CreateTimer(8.0, Timer_CheckPlayerPings, _, TIMER_REPEAT);
}

void Event_GamemodeChange(ConVar cvar, const char[] oldValue, const char[] newValue) {
	cvar.GetString(gamemode, sizeof(gamemode));
}

void Event_PlayerLimitChange(ConVar cvar, const char[] oldValue, const char[] newValue) {
	if(cvar.IntValue > 0) {
		hSVMaxPlayers.IntValue = cvar.IntValue;
	}
}

Action Timer_CheckPlayerPings(Handle timer) {
	if(StrEqual(gamemode, "hideandseek")) return Plugin_Continue;
	if(hPingDropThres.IntValue != 0) {
		for (int i = 1; i <= MaxClients; i++ ) {
			if(IsClientConnected(i) && IsClientInGame(i) && !IsFakeClient(i) && IsPlayerAlive(i) && GetClientTeam(i) > 1) {
				int ping = GetEntProp(GetPlayerResourceEntity(), Prop_Send, "m_iPing", _, i);
				if(isHighPingIdle[i] && ping <= hPingDropThres.IntValue) {
					L4D_TakeOverBot(i);
					isHighPingIdle[i] = false;
					iHighPingCount[i] = 0;
				}else if(ping > hPingDropThres.IntValue) {
					if(iHighPingCount[i]++ > 2) {
						PrintToChat(i, "Due to your high ping (%d ms) you have been moved to AFK.", ping);
						PrintToChat(i, "You will be automatically switched back once your ping restores");
						// SDKCall(hGoAwayFromKeyboard, i);
						//PrintToChat(i, "Type /pingignore to disable this feature.");
						// L4D_ReplaceWithBot(i);
						isHighPingIdle[i] = true;
						iHighPingCount[i] = 0;
					}

				}
			}
		}
	}
	return Plugin_Continue;
}

void CVC_FFNotice(ConVar convar, const char[] oldValue, const char[] newValue) {
	if(convar.IntValue > 0) {
		HookEvent("player_hurt", Event_PlayerHurt);
	} else {
		UnhookEvent("player_hurt", Event_PlayerHurt);
	}
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast) {
	LasersUsed.Clear();
}

Action Command_RespawnAll(int client, int args) {
	L4D_CreateRescuableSurvivors();
	return Plugin_Handled;
}

Action Command_SwapPlayer(int client, int args) {
	if(args < 1) {
		ReplyToCommand(client, "Usage: sm_swap <player> [another player (default: self)] [\"silent\"]");
	} else {
		char arg1[64], arg2[64], arg3[8];
		GetCmdArg(1, arg1, sizeof(arg1));
		GetCmdArg(2, arg2, sizeof(arg2));
		GetCmdArg(3, arg3, sizeof(arg3));

		char target_name[MAX_TARGET_LENGTH];
		int target_list[MAXPLAYERS], target_count;
		bool tn_is_ml;
		if ((target_count = ProcessTargetString(
				arg1,
				client,
				target_list,
				1,
				COMMAND_FILTER_CONNECTED | COMMAND_FILTER_NO_IMMUNITY,
				target_name,
				sizeof(target_name),
				tn_is_ml)) <= 0)
		{
			/* This function replies to the admin with a failure message */
			ReplyToTargetError(client, target_count);
			return Plugin_Handled;
		}
		int target = target_list[0];
		int target2 = client;
		if(args == 2) {
			if ((target_count = ProcessTargetString(
					arg2,
					client,
					target_list,
					1,
					COMMAND_FILTER_CONNECTED | COMMAND_FILTER_NO_IMMUNITY,
					target_name,
					sizeof(target_name),
					tn_is_ml)) <= 0)
			{
				/* This function replies to the admin with a failure message */
				ReplyToTargetError(client, target_count);
			}
			target2 = target_list[0];
		}
		float pos1[3], pos2[3];
		float ang1[3], ang2[3];
		GetClientAbsOrigin(target, pos1);
		GetClientAbsOrigin(target2, pos2);
		GetClientAbsAngles(target, ang1);
		GetClientAbsAngles(target2, ang2);
		TeleportEntity(target, pos2, ang2, NULL_VECTOR);
		TeleportEntity(target2, pos1, ang1, NULL_VECTOR);
		if(args < 3 || !StrEqual(arg3, "silent") && !StrEqual(arg2, "silent")) {
			EmitSoundToClient(target, "custom/xen_teleport.mp3", target, 0);
			EmitSoundToClient(target2, "custom/xen_teleport.mp3", target2);
		}
	}
	return Plugin_Handled;
}

Action Command_SkipOutro(int client, int args) {
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i)) {
			ClientCommand(i, "skipouttro");
		}
	}
	return Plugin_Handled;
}
Action Command_ListClientModels(int client, int args) {
	char model[64];
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2) {
			GetClientModel(i, model, sizeof(model));
			ReplyToCommand(client, "%N's model: %s", i, model);
		}
	}
	return Plugin_Handled;
}
Action Command_PlaySound(int client, int args) {
	if(args < 2) {
		ReplyToCommand(client, "Usage: sm_playsound <player> <soundpath>");
	}else{
		char arg1[32], arg2[64], arg3[16];
		GetCmdArg(1, arg1, sizeof(arg1));
		GetCmdArg(2, arg2, sizeof(arg2));
		GetCmdArg(3, arg3, sizeof(arg3));

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
			StopSound(target, 0, lastSound[target]);
		}
		PrecacheSound(arg2);
		for (int i = 0; i < target_count; i++) {
			target = target_list[i];
			if(IsClientConnected(target) && IsClientInGame(target) && !IsFakeClient(target)) {
				if(StrEqual(arg3, "direct"))
					ClientCommand(target, "playgamesound %s", arg2);
				else
					EmitSoundToClient(target, arg2, target);
				strcopy(lastSound[target], 64, arg2);
			}
		}
		CShowActivity2(client, "[SM] ", "playing sound {olive}%s{default} to {yellow}%s", arg2, target_name);
	}
	return Plugin_Handled;
}

Action Command_StopSound(int client, int args) {
	if(args < 2) {
		ReplyToCommand(client, "Usage: sm_stopsound <player> [soundpath or leave blank for previous]");
	} else {
		char arg1[32], arg2[64];
		GetCmdArg(1, arg1, sizeof(arg1));
		GetCmdArg(2, arg2, sizeof(arg2));

		char target_name[MAX_TARGET_LENGTH];
		int target_list[MAXPLAYERS], target_count;
		bool tn_is_ml;
		if ((target_count = ProcessTargetString(
				arg1,
				client,
				target_list,
				MAXPLAYERS,
				COMMAND_FILTER_CONNECTED | COMMAND_FILTER_NO_IMMUNITY,
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
			if(IsClientConnected(target) && IsClientInGame(target) && !IsFakeClient(target)) {
				if(args < 2) 
					StopSound(target, 0, lastSound[target]);
				else
					StopSound(target, 0, arg2);
			}
		}
	}
	return Plugin_Handled;
}

Action Command_SetClientModel(int client, int args) {
	if(args < 1) {
		ReplyToCommand(client, "Usage: sm_model <model> [player] ['keep']");
	} else {
		char arg1[2], arg2[16], arg3[8];
		GetCmdArg(1, arg1, sizeof(arg1));
		GetCmdArg(2, arg2, sizeof(arg2));
		GetCmdArg(3, arg3, sizeof(arg3));
		
		int survivorId;
		L4DModelId modelId;


		bool isL4D1 = isL4D1Survivors;
		if(hForceSurvivorSet != null && hForceSurvivorSet.IntValue > 0) isL4D1 = hForceSurvivorSet.IntValue == 1;

		char s = CharToLower(arg1[0]);
		if(s == 'b') {
			survivorId = isL4D1 ? 0 : 4;
			modelId = Model_Bill;
		} else if(s == 'z') {
			survivorId = isL4D1 ? 1 : 5;
			modelId = Model_Zoey;
		} else if(s == 'l') {
			survivorId = isL4D1 ? 2 : 7;
			modelId = Model_Louis;
		} else if(s == 'f') {
			survivorId = isL4D1 ? 3 : 6;
			modelId = Model_Francis;
		} else if(s == 'n') {
			survivorId = 0;
			modelId = Model_Nick;
			if(isL4D1) PrintToChat(client, "Note: Only models for L4D2 characters are supported in L4D1 maps.");
		} else if(s == 'r') {
			survivorId = 1;
			modelId = Model_Rochelle;
			if(isL4D1) PrintToChat(client, "Note: Only models for L4D2 characters are supported in L4D1 maps.");
		} else if(s== 'e') {
			survivorId = 3;
			modelId = Model_Ellis;
			if(isL4D1) PrintToChat(client, "Note: Only models for L4D2 characters are supported in L4D1 maps.");
		} else if(s == 'c') {
			survivorId = 2;
			modelId = Model_Coach;
			if(isL4D1) PrintToChat(client, "Note: Only models for L4D2 characters are supported in L4D1 maps.");
		} else {
			ReplyToCommand(client, "Unknown survivor \"%s\". Syntax changed: model <survivor> [player or none for self]", arg1);
			return Plugin_Handled;
		}
		
		bool keep = StrEqual(arg2, "keep", false) || StrEqual(arg3, "keep", false);

		if(args > 1) {
			char target_name[1];
			int target_list[MAXPLAYERS], target_count;
			bool tn_is_ml;
			if ((target_count = ProcessTargetString(
					arg2,
					client,
					target_list,
					MAXPLAYERS,
					COMMAND_FILTER_ALIVE | COMMAND_FILTER_NO_IMMUNITY,
					target_name,
					sizeof(target_name),
					tn_is_ml)) <= 0)
			{
				/* This function replies to the admin with a failure message */
				ReplyToTargetError(client, target_count);
				return Plugin_Handled;
			}
			for (int i = 0; i < target_count; i++) {
				int target = target_list[i];
				int team = GetClientTeam(target);
				if(team == 2 || team == 4) {
					SetCharacter(target, survivorId, modelId, keep);
				}
			}
		} else {
			SetCharacter(client, survivorId, modelId, keep);
		}
	}
	return Plugin_Handled;
}

void SetCharacter(int target, int survivorIndex, L4DModelId modelIndex, bool keepModel) {
	SetEntProp(target, Prop_Send, "m_survivorCharacter", survivorIndex);
	SetEntityModel(target, MODELS[view_as<int>(modelIndex)]);
	if (IsFakeClient(target)) {
		char name[32];
		GetSurvivorName(target, name, sizeof(name));
		SetClientInfo(target, "name", name);
	}
	UpdatePlayerIdentity(target, view_as<Character>(survivorIndex), keepModel);

	DataPack pack = new DataPack();
	pack.WriteCell(GetClientUserId(target));
	bool dualWield = false;
	for(int slot = 0; slot <= 4; slot++) {
		int weapon = AddWeaponSlot(target, slot, pack);
		if(weapon > 0) {
			if(slot == 1 && HasEntProp(weapon, Prop_Send, "m_isDualWielding")) {
				dualWield = GetEntProp(weapon, Prop_Send, "m_isDualWielding") == 1;
				SetEntProp(weapon, Prop_Send, "m_isDualWielding", 0); 
			}
			SDKHooks_DropWeapon(target, weapon, NULL_VECTOR);
		}
	}
	pack.WriteCell(dualWield);
	CreateTimer(0.1, Timer_RequipWeapon, pack);
}

int AddWeaponSlot(int target, int slot, DataPack pack) {
	int weapon = GetPlayerWeaponSlot(target, slot);
	if( weapon > 0 ) {
		pack.WriteCell(EntIndexToEntRef(weapon)); // Save last held weapon to switch back
		return weapon;
	} else {
		pack.WriteCell(-1); // Save last held weapon to switch back
		return -1;
	}
}

public Action Timer_RequipWeapon(Handle hdl, DataPack pack) {
	pack.Reset();
	int client = GetClientOfUserId(pack.ReadCell());
	if(client == 0) return Plugin_Handled;

	int weapon, pistolSlotItem = -1;

	for(int slot = 0; slot <= 4; slot++) {
		weapon = pack.ReadCell();
		if(EntRefToEntIndex(weapon) != INVALID_ENT_REFERENCE) {
			if(slot == 1) {
				pistolSlotItem = weapon;
			}
			EquipPlayerWeapon(client, weapon);
		}
	}
	bool isDualWield = pack.ReadCell() == 1;
	if(isDualWield && pistolSlotItem != -1 && HasEntProp(pistolSlotItem, Prop_Send, "m_isDualWielding")) {
		SetEntProp(pistolSlotItem, Prop_Send, "m_isDualWielding", 1);
	}
	return Plugin_Handled;
}

Action Cmd_SetSurvivor(int client, int args) {
	if(args < 1) {
		ReplyToCommand(client, "Usage: sm_surv <player> <survivor>");
	} else {
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
				COMMAND_FILTER_CONNECTED | COMMAND_FILTER_NO_IMMUNITY,
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

// Hide MOTD
Action VGUIMenu(UserMsg msg_id, Handle bf, const int[] players, int playersNum, bool reliable, bool init) {
	if(!hHideMotd.BoolValue) return Plugin_Continue;
	static char buffer[8];
	// Show MOTD on versus games
	hGamemode.GetString(buffer, sizeof(buffer));
	if(StrEqual(buffer, "versus", false)) return Plugin_Continue;

	BfReadString(bf, buffer, sizeof(buffer));
	return strcmp(buffer, "info") == 0 ? Plugin_Handled : Plugin_Continue;
}  

public void OnClientPutInServer(int client) {
	if(!IsFakeClient(client))
		SDKHook(client, SDKHook_WeaponEquip, Event_OnWeaponEquip);
	else
		SDKHook(client, SDKHook_OnTakeDamage, Event_OnTakeDamageBot);
}

public void OnClientDisconnect(int client) {
	isHighPingIdle[client] = false;
	iHighPingCount[client] = 0;
	if(IsClientConnected(client) && IsClientInGame(client) && botDropMeleeWeapon[client] > -1 && IsValidEntity(botDropMeleeWeapon[client])) {
		float pos[3];
		GetClientAbsOrigin(client, pos);
		TeleportEntity(botDropMeleeWeapon[client], pos, NULL_VECTOR, NULL_VECTOR);
		botDropMeleeWeapon[client] = -1;
	}
}

public void Event_PlayerDisconnect(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(client && !IsFakeClient(client)) {
		char auth[32];
		GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth));
		SteamIDs.Remove(auth);
	}
}

//Can also probably prevent kit drop to pick them up 
public void Event_WeaponDrop(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	int weapon = event.GetInt("propid");
	char newWpn[32];
	GetEntityClassname(client, newWpn, sizeof(newWpn));
	if(StrEqual(newWpn, "weapon_ammo_pack")) {
		// prevent weapon from being picked up?
		disabledItems.SetValue(weapon, GetClientUserId(client));
		CreateTimer(10.0, Timer_AllowKitPickup, weapon);
	}
}
public Action Event_OnWeaponEquip(int client, int weapon) {
	int userid;
	if(disabledItems.GetValue(weapon, userid) && GetClientUserId(client) == userid)
		return Plugin_Handled;
	else return Plugin_Continue;
}
public Action Timer_AllowKitPickup(Handle h, int entity) {
	disabledItems.Remove(entity);
	return Plugin_Handled;
}
public void OnMapStart() {
	#if PRECACHE_SOUNDS_COUNT > 0
	char buffer[128];
	for(int i = 0; i < PRECACHE_SOUNDS_COUNT; i++) {
		Format(buffer, sizeof(buffer), "sound/%s", PRECACHE_SOUNDS[i]);
		AddFileToDownloadsTable(buffer);
		PrecacheSound(PRECACHE_SOUNDS[i]);
	}
	#endif
	
	HookEntityOutput("info_changelevel", "OnStartTouch", EntityOutput_OnStartTouchSaferoom);
	HookEntityOutput("trigger_changelevel", "OnStartTouch", EntityOutput_OnStartTouchSaferoom);
}
public void OnMapEnd() {
	disabledItems.Clear();
}
public void OnConfigsExecuted() {
	isL4D1Survivors = L4D2_GetSurvivorSetMap() == 1;
	if(hSVMaxPlayers != null && hPlayerLimit.IntValue > 0) {
		hSVMaxPlayers.IntValue = hPlayerLimit.IntValue;
	}
}

#if defined _sceneprocessor_included
public void OnSceneStageChanged(int scene, SceneStages stage) {
	if(stage == SceneStage_SpawnedPost) {
		int activator = GetSceneInitiator(scene);
		// int actor = GetActorFromScene(scene);
		
		// PrintToServer("activator=%N actor=%N %s", activator, actor, sceneFile);
		if(activator == 0) {
			static char sceneFile[64];
			GetSceneFile(scene, sceneFile, sizeof(sceneFile));
			if(StrContains(sceneFile, "scenes/mechanic/dlc1_c6m1_initialmeeting") > -1 || StrEqual(sceneFile, "scenes/teengirl/dlc1_c6m1_initialmeeting07.vcd")) {
				CancelScene(scene);
			} else if(StrEqual(sceneFile, "scenes/teengirl/dlc1_c6m1_initialmeeting13.vcd")) {
				CancelScene(scene);
			} else if(StrEqual(sceneFile, "scenes/coach/worldc1m3b04.vcd")) {
				CancelScene(scene);
			}
		}
	}
}
#endif
///AFK BOT WEAPON FIX
public void Event_BotPlayerSwap(Event event, const char[] name, bool dontBroadcast) {
	int bot = GetClientOfUserId(event.GetInt("bot"));
	if(StrEqual(name, "player_bot_replace")) {
		// Bot replaced player, hook any drop events
		SDKHook(bot, SDKHook_WeaponDrop, Event_OnWeaponDrop);
	} else {
		// Player replaced a bot
		int client = GetClientOfUserId(event.GetInt("player"));
		if(client && botDropMeleeWeapon[bot] > 0) {
			int meleeOwnerEnt = GetEntPropEnt(botDropMeleeWeapon[bot], Prop_Send, "m_hOwnerEntity");
			if(meleeOwnerEnt == -1) { 
				int currentWeapon = GetPlayerWeaponSlot(client, 1);
				if(currentWeapon > 0) {
					char buffer[32];
					GetEntityClassname(currentWeapon, buffer, sizeof(buffer));
					// Only delete their duplicate pistols, let melees get thrown out (into the world)
					if(!StrEqual(buffer, "weapon_melee"))
						RemoveEntity(currentWeapon);
				}
				EquipPlayerWeapon(client, botDropMeleeWeapon[bot]);
				botDropMeleeWeapon[bot] = -1;
			}
		}
		SDKUnhook(bot, SDKHook_WeaponDrop, Event_OnWeaponDrop);
	}
}
Action Event_OnWeaponDrop(int client, int weapon) {
	if(!IsValidEntity(weapon) || !IsFakeClient(client)) return Plugin_Continue;
	if(GetEntProp(client, Prop_Send, "m_humanSpectatorUserID") > 0) {
		char wpn[32];
		GetEdictClassname(weapon, wpn, sizeof(wpn));
		if(StrEqual(wpn, "weapon_melee") || StrEqual(wpn, "weapon_pistol_magnum")) {
			#if defined DEBUG
			PrintToServer("Bot %N dropped melee weapon %s", client, wpn);
			#endif
			RequestFrame(Frame_HideEntity, weapon);
			botDropMeleeWeapon[client] = weapon;
		}
	}
	return Plugin_Continue;
}
void Frame_HideEntity(int entity) {
	if(IsValidEntity(entity))
		TeleportEntity(entity, OUT_OF_BOUNDS, NULL_VECTOR, NULL_VECTOR);
}
// Only called for bots, kills zombies behind bots, preventing them being stuck when their AI doesn't want to keep them alive
Action Event_OnTakeDamageBot(int victim, int& attacker, int& inflictor, float& damage, int& damagetype) {
	if(attacker > MaxClients) {
		static char name[16];
		GetEdictClassname(attacker, name, sizeof(name));
		if(!StrEqual(name, "infected", true)) {
			return Plugin_Continue;
		}

		bool attackerVisible = IsEntityInSightRange(victim, attacker, 130.0, 10000.0);
		if(!attackerVisible) {
			//Zombie is behind the bot, reduce damage taken and slowly kill zombie (1/10 of default hp per hit)
			damage /= 2.0;
			SDKHooks_TakeDamage(attacker, victim, victim, 30.0);
			return Plugin_Changed;
		}
	}
	return Plugin_Continue;
}
//MINOR FIXES
void EntityOutput_OnStartTouchSaferoom(const char[] output, int caller, int client, float time) {
	if(client > 0 && client <= MaxClients && IsValidClient(client) && GetClientTeam(client) == 2) {
		if(StrEqual(gamemode, "coop", false)) {
			if(botDropMeleeWeapon[client] > 0) {
				PrintToServer("Giving melee weapon back to %N", client);
				float pos[3];
				GetClientAbsOrigin(client, pos);
				TeleportEntity(botDropMeleeWeapon[client], pos, NULL_VECTOR, NULL_VECTOR);
				EquipPlayerWeapon(client, botDropMeleeWeapon[client]);
				botDropMeleeWeapon[client] = -1;
			}
		} else if(StrEqual(gamemode, "tankrun", false)) {
			if(!IsFakeClient(client)) {
				CreateTimer(1.0, Timer_TPBots, client, TIMER_FLAG_NO_MAPCHANGE);
			}
		}
	}
}

Action Timer_TPBots(Handle timer, int user) {
	float pos[3];
	GetClientAbsOrigin(user, pos);
	for(int i = 1; i < MaxClients + 1; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && IsFakeClient(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i)) {
			TeleportEntity(i, pos, NULL_VECTOR, NULL_VECTOR);
			L4D2_RunScript("CommandABot({cmd=1,bot=GetPlayerFromUserID(%i),pos=Vector(%f,%f,%f)})", GetClientUserId(i), pos[0], pos[1], pos[2]);
			
		}
	}
	return Plugin_Handled;
}
//FRIENDLY FIRE NOTICE
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
//LASER SIGHT NOTICE
void Event_PlayerUse(Event event, const char[] name, bool dontBroadcast) {
	if(hLaserNotice.BoolValue) {
		int client = GetClientOfUserId(event.GetInt("userid"));
		int targetEntity = event.GetInt("targetid");
	
		char classname[32];
		GetEntityClassname(targetEntity, classname, sizeof(classname));
		
		if(StrEqual(classname, "upgrade_laser_sight")) {
			if(LasersUsed.FindValue(targetEntity) == -1) {
				LasersUsed.Push(targetEntity);
				PrintToChatAll("%N picked up laser sights", client);
			}
		}	
	}
}
//FINALE TIME INFO
void Event_GauntletStart(Event event, const char[] name, bool dontBroadcast) {
	if(hFinaleTimer.IntValue > 0) {
		iFinaleStartTime = GetTime();
	}
}
void Event_FinaleStart(Event event, const char[] name, bool dontBroadcast) {
	if(hFinaleTimer.IntValue == 2) {
		iFinaleStartTime = GetTime();
	}
}
void Event_FinaleEnd(Event event, const char[] name, bool dontBroadcast) {
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
//Give kits to bots that replace kicked player
void Event_PlayerFirstSpawn(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(client > 0 && IsFakeClient(client) && HasEntProp(client, Prop_Send, "m_humanSpectatorUserID") && GetEntProp(client, Prop_Send, "m_humanSpectatorUserID") < 0) {
		int ent = GivePlayerItem(client, "weapon_first_aid_kit");
		EquipPlayerWeapon(client, ent);
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