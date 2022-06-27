#pragma semicolon 1
#pragma newdecls required

#define DEBUG 1

#define PLUGIN_VERSION "1.0"

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <left4dhooks>
#include <jutils.inc>
#include <sceneprocessor>
#include "l4d_survivor_identity_fix.inc"

char ReserveLevels[4][] = {
	"Public", "Watch", "Admin-Only", "Private"
};
enum ReserveMode {
	Reserve_None = 0,
	Reserve_Watch,
	Reserve_AdminOnly,
	Reserve_Private
}


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
static ConVar hLaserNotice, hFinaleTimer, hFFNotice, hMPGamemode, hPingDropThres, hForceSurvivorSet, hPlayerLimit, hSVMaxPlayers;
static int iFinaleStartTime, botDropMeleeWeapon[MAXPLAYERS+1], iHighPingCount[MAXPLAYERS+1];
ReserveMode reserveMode;
static bool isHighPingIdle[MAXPLAYERS+1], isL4D1Survivors;
static Handle hTakeOverBot, hGoAwayFromKeyboard;
static StringMap SteamIDs;
static char lastSound[MAXPLAYERS+1][64], gamemode[32];

static float OUT_OF_BOUNDS[3] = {0.0, -1000.0, 0.0};

public Plugin myinfo = {
	name = "L4D2 Misc Tools",
	author = "Includes: Notice on laser use, Timer for gauntlet runs",
	description = "jackzmc", 
	version = PLUGIN_VERSION, 
	url = ""
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
	hForceSurvivorSet = FindConVar("l4d_force_survivorset");

	hSVMaxPlayers   = FindConVar("sv_maxplayers");
	if(hSVMaxPlayers != null) { 
		hPlayerLimit    = CreateConVar("sm_player_limit", "0", "Overrides sv_maxplayers. 0 = off, > 0: limit", FCVAR_NONE, true, 0.0, false);
		hPlayerLimit.AddChangeHook(Event_PlayerLimitChange);
		hSVMaxPlayers.IntValue = hPlayerLimit.IntValue;
	}


	hFFNotice.AddChangeHook(CVC_FFNotice);
	if(hFFNotice.IntValue > 0) {
		HookEvent("player_hurt", Event_PlayerHurt);
	}

	LasersUsed = new ArrayList(1, 0);
	SteamIDs = new StringMap();

	ConVar hGamemode = FindConVar("mp_gamemode"); 
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

	AutoExecConfig(true, "l4d2_tools");

	for(int client = 1; client < MaxClients; client++) {
		if(IsClientConnected(client) && IsClientInGame(client) && GetClientTeam(client) == 2) {
			if(IsFakeClient(client)) {
				SDKHook(client, SDKHook_OnTakeDamage, Event_OnTakeDamage);
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
	RegAdminCmd("sm_playsound", Command_PlaySound, ADMFLAG_CHEATS, "Plays a gamesound for player");
	RegAdminCmd("sm_stopsound", Command_StopSound, ADMFLAG_CHEATS, "Stops the last played gamesound for player");
	RegAdminCmd("sm_swap", Command_SwapPlayer, ADMFLAG_CHEATS, "Swarms two player's locations");
	RegAdminCmd("sm_perm", Command_SetServerPermissions, ADMFLAG_KICK, "Sets the server's permissions.");
	RegAdminCmd("sm_perms", Command_SetServerPermissions, ADMFLAG_KICK, "Sets the server's permissions.");
	RegAdminCmd("sm_permissions", Command_SetServerPermissions, ADMFLAG_KICK, "Sets the server's permissions.");
	RegConsoleCmd("sm_pmodels", Command_ListClientModels, "Lists all player's models");
	RegAdminCmd("sm_skipoutro", Command_SkipOutro, ADMFLAG_KICK, "Skips the outro");

	CreateTimer(8.0, Timer_CheckPlayerPings, _, TIMER_REPEAT);
}

public void Event_GamemodeChange(ConVar cvar, const char[] oldValue, const char[] newValue) {
	cvar.GetString(gamemode, sizeof(gamemode));
}

public void Event_PlayerLimitChange(ConVar cvar, const char[] oldValue, const char[] newValue) {
	if(cvar.IntValue > 0) {
		hSVMaxPlayers.IntValue = cvar.IntValue;
	}
}


public void OnClientConnected(int client) {
	if(!IsFakeClient(client) && reserveMode == Reserve_Watch) {
		PrintChatToAdmins("%N is connecting", client);
	}
}

stock void PrintChatToAdmins(const char[] format, any ...) {
	char buffer[254];
	VFormat(buffer, sizeof(buffer), format, 2);
	for(int i = 1; i < MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i)) {
			AdminId admin = GetUserAdmin(i);
			if(admin != INVALID_ADMIN_ID) {
				PrintToChat(i, "%s", buffer);
			}
		}
	}
	PrintToServer("%s", buffer);
}


public void OnClientPostAdminCheck(int client) {
	if(!IsFakeClient(client)) {
		static char auth[32];
		GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth));
		if(reserveMode == Reserve_Private || (reserveMode == Reserve_AdminOnly && GetUserAdmin(client) == INVALID_ADMIN_ID)) {
			int index;
			if(!SteamIDs.GetValue(auth, index)) {
				KickClient(client, "Sorry, server is reserved");
				return;
			}
		}
		SteamIDs.SetValue(auth, client);
	}
}

public Action Command_SetServerPermissions(int client, int args) {
	if(args > 0) {
		char arg1[32];
		GetCmdArg(1, arg1, sizeof(arg1));
		if(StrEqual(arg1, "public", false)) {
			reserveMode = Reserve_None;
		}else if(StrContains(arg1, "noti", false) > -1) {
			reserveMode = Reserve_Watch;
		}else if(StrContains(arg1, "admin", false) > -1) {
			reserveMode = Reserve_AdminOnly;
		}else if(StrEqual(arg1, "private", false)) {
			reserveMode = Reserve_Private;
			static char auth[32];
			for(int i = 1; i <= MaxClients; i++) {
				if(IsClientConnected(i) && IsClientInGame(i) && !IsFakeClient(i)) {
					GetClientAuthId(i, AuthId_Steam2, auth, sizeof(auth));
					SteamIDs.SetValue(auth, i);
				}
			}
		}else {
			ReplyToCommand(client, "Usage: sm_reserve [public/notify/admin/private] or no arguments to view current reservation.");
			return Plugin_Handled;
		}
		PrintToChatAll("Server is now %s.", ReserveLevels[reserveMode]);
	} else {
		ReplyToCommand(client, "Server is currently %s", ReserveLevels[reserveMode]);
	}
	return Plugin_Handled;
}


public Action Timer_CheckPlayerPings(Handle timer) {
	if(StrEqual(gamemode, "hideandseek")) return Plugin_Continue;
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
						//PrintToChat(i, "Type /pingignore to disable this feature.");
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
public Action Command_SwapPlayer(int client, int args) {
	if(args < 1) {
		ReplyToCommand(client, "Usage: sm_swap <player> [player or yourself] [silent]");
	}else{
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
				COMMAND_FILTER_CONNECTED,
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
					COMMAND_FILTER_CONNECTED,
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

public Action Command_SkipOutro(int client, int args) {
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i)) {
			ClientCommand(i, "skipouttro");
		}
	}
	return Plugin_Handled;
}
public Action Command_ListClientModels(int client, int args) {
	char model[64];
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2) {
			GetClientModel(i, model, sizeof(model));
			ReplyToCommand(client, "%N's model: %s", i, model);
		}
	}
}
public Action Command_PlaySound(int client, int args) {
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
				ReplyToCommand(client, "Playing '%s' to %N %s", arg2, target, arg3);
			}
		}
		ShowActivity2(client, target_name, "\"%L\" playing sound \"%s\" to \"%L\"", client, arg2, target_name);
	}
	return Plugin_Handled;
}
public Action Command_StopSound(int client, int args) {
	if(args < 2) {
		ReplyToCommand(client, "Usage: sm_stopsound <player> [soundpath or leave blank for previous]");
	}else{
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
public Action Command_SetClientModel(int client, int args) {
	if(args < 1) {
		ReplyToCommand(client, "Usage: sm_model <model> [player] ['keep']");
	} else {
		static char arg1[2], arg2[16], arg3[8];
		GetCmdArg(1, arg1, sizeof(arg1));
		GetCmdArg(2, arg2, sizeof(arg2));
		GetCmdArg(3, arg3, sizeof(arg3));
		
		int survivorId;
		L4DModelId modelId;

		bool isL4D1 = isL4D1Survivors && hForceSurvivorSet != null && hForceSurvivorSet.IntValue < 2;

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
					COMMAND_FILTER_ALIVE,
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
	if(client == 0) return;

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

public Action VGUIMenu(UserMsg msg_id, Handle bf, const int[] players, int playersNum, bool reliable, bool init) {
	static char buffer[5];
	BfReadString(bf, buffer, sizeof(buffer));
	return strcmp(buffer, "info") == 0 ? Plugin_Handled : Plugin_Continue;
}  
public void OnClientPutInServer(int client) {
	if(!IsFakeClient(client))
		SDKHook(client, SDKHook_WeaponEquip, Event_OnWeaponEquip);
}
public void OnClientDisconnect(int client) {
	if(IsClientConnected(client) && IsClientInGame(client) && botDropMeleeWeapon[client] > -1) {
		float pos[3];
		GetClientAbsOrigin(client, pos);
		TeleportEntity(botDropMeleeWeapon[client], pos, NULL_VECTOR, NULL_VECTOR);
		botDropMeleeWeapon[client] = -1;
	}
	if(!IsFakeClient(client)) {
		static char auth[32];
		GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth));
		SteamIDs.Remove(auth);
	}
}
int disabledItem[2048];
//Can also probably prevent kit drop to pick them up 
public Action Event_WeaponDrop(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	int weapon = event.GetInt("propid");
	char newWpn[32];
	GetEntityClassname(client, newWpn, sizeof(newWpn));
	if(StrEqual(newWpn, "weapon_ammo_pack")) {
		// prevent weapon from being picked up?
		disabledItem[weapon] = client;
		CreateTimer(10.0, Timer_AllowKitPickup, weapon);
	}
}
public Action Event_OnWeaponEquip(int client, int weapon) {
	if(disabledItem[weapon] > 0 && disabledItem[weapon] != client) return Plugin_Handled;
	return Plugin_Continue;
}
public Action Timer_AllowKitPickup(Handle h, int entity) {
	disabledItem[entity] = 0;
}
public void OnMapStart() {
	AddFileToDownloadsTable("sound/custom/meow1.mp3");
	PrecacheSound("custom/meow1.mp3");
	AddFileToDownloadsTable("sound/custom/xen_teleport.mp3");
	PrecacheSound("custom/xen_teleport.mp3");
	AddFileToDownloadsTable("sound/custom/mariokartmusic.mp3");
	PrecacheSound("custom/mariokartmusic.mp3");	
	
	HookEntityOutput("info_changelevel", "OnStartTouch", EntityOutput_OnStartTouchSaferoom);
	HookEntityOutput("trigger_changelevel", "OnStartTouch", EntityOutput_OnStartTouchSaferoom);
	
}
public void OnConfigsExecuted() {
	isL4D1Survivors = L4D2_GetSurvivorSetMap() == 1;
	if(hSVMaxPlayers != null && hPlayerLimit.IntValue > 0) {
		hSVMaxPlayers.IntValue = hPlayerLimit.IntValue;
	}
}

public void OnSceneStageChanged(int scene, SceneStages stage) {
	if(stage == SceneStage_Started) {
		static char sceneFile[64];
		GetSceneFile(scene, sceneFile, sizeof(sceneFile));
		int activator = GetSceneInitiator(scene);
		if(activator == 0) {
			if(StrContains(sceneFile, "scenes/mechanic/dlc1_c6m1_initialmeeting") > -1 || StrEqual(sceneFile, "scenes/teengirl/dlc1_c6m1_initialmeeting07.vcd")) {
				CancelScene(scene);
			}else if(StrEqual(sceneFile, "scenes/teengirl/dlc1_c6m1_initialmeeting13.vcd") && activator == 0) {
				CancelScene(scene);
			}
		}
	}
}
///AFK BOT WEAPON FIX
public Action Event_BotPlayerSwap(Event event, const char[] name, bool dontBroadcast) {
	int bot = GetClientOfUserId(event.GetInt("bot"));
	if(StrEqual(name, "player_bot_replace")) {
		//Bot replaced player, hook any drop events
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
public Action Event_OnWeaponDrop(int client, int weapon) {
	if(!IsValidEntity(weapon) || !IsFakeClient(client)) return Plugin_Continue;
	static char wpn[32];
	GetEdictClassname(weapon, wpn, sizeof(wpn));
	if(StrEqual(wpn, "weapon_melee") && GetEntProp(client, Prop_Send, "m_humanSpectatorUserID") > 0) {
		#if defined DEBUG
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
//STUCK BOTS WITH ZOMBIES FIX
public Action Event_OnTakeDamage(int victim, int& attacker, int& inflictor, float& damage, int& damagetype) {
	if(attacker > MaxClients) {
		char name[16];
		GetEdictClassname(attacker, name, sizeof(name));
		if(!StrEqual(name, "infected", true)) {
			return Plugin_Continue;
		}

		bool attackerVisible = IsEntityInSightRange(victim, attacker, 130.0, 100.0);
		if(!attackerVisible) {
			//Zombie is behind the bot, reduce damage taken and slowly kill zombie (1/10 of default hp per hit)
			damage /= 2.0;
			SDKHooks_TakeDamage(attacker, victim, victim, 10.0);
			return Plugin_Changed;
		}
	}
	return Plugin_Continue;
}
//MINOR FIXES
public void EntityOutput_OnStartTouchSaferoom(const char[] output, int caller, int client, float time) {
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
//FINALE TIME INFO
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
//Give kits to bots that replace kicked player
public void Event_PlayerFirstSpawn(Event event, const char[] name, bool dontBroadcast) {
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