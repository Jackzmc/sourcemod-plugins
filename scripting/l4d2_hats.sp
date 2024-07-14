#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "1.0"
#define PLAYER_HAT_REQUEST_COOLDOWN 10
// #define DEBUG_GLOW 1
static float EMPTY_ANG[3] = { 0.0, 0.0, 0.0 };

#define DUMMY_MODEL "models/props/cs_office/vending_machine.mdl"

#include <sourcemod>
#include <sdktools>
#include <left4dhooks>
#include <clientprefs>
#include <jutils>
#include <gamemodes/ents>
#include <smlib/effects>
#include <multicolors>
#include <adminmenu>


bool tempGod[MAXPLAYERS+1];
bool inSaferoom[MAXPLAYERS+1];

int g_iLaserIndex;

float cmdThrottle[MAXPLAYERS+1];
static bool onLadder[MAXPLAYERS+1];

Cookie noHatVictimCookie;
Cookie hatPresetCookie;

ConVar cvar_sm_hats_enabled;
ConVar cvar_sm_hats_flags;
ConVar cvar_sm_hats_rainbow_speed;
ConVar cvar_sm_hats_blacklist_enabled;
ConVar cvar_sm_hats_max_distance;

TopMenu g_topMenu;

char g_currentMap[64];

//int g_markedMode

#include <hats/editor.sp>
#include <hats/hats.sp>
#include <hats/hat_presets.sp>
#include <hats/props/base.sp>
#include <hats/natives.sp>
#include <hats_editor>

public Plugin myinfo = {
	name =  "L4D2 Hats & Editor", 
	author = "jackzmc", 
	description = "", 
	version = PLUGIN_VERSION, 
	url = "https://github.com/Jackzmc/sourcemod-plugins"
};

ArrayList NavAreas;
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
	RegPluginLibrary("editor");
	// CreateNative("SpawnSchematic", Native_SpawnSchematic);
	CreateNative("StartEdit", Native_StartEdit);
	CreateNative("StartSpawner", Native_StartSpawner);
	CreateNative("CancelEdit", Native_CancelEdit);
	CreateNative("IsEditorActive", Native_IsEditorActive);


	CreateNative("StartSelector", Native_StartSelector);
	CreateNative("CancelSelector", Native_CancelSelector);
	CreateNative("IsSelectorActive", Native_IsSelectorActive);

	CreateNative("EntitySelector.Start", Native_Selector_Start);
	CreateNative("EntitySelector.Count.get", Native_Selector_GetCount);
	CreateNative("EntitySelector.Active.get", Native_Selector_GetActive);
	CreateNative("EntitySelector.SetOnEnd", Native_Selector_SetOnEnd);
	CreateNative("EntitySelector.SetOnPreSelect", Native_Selector_SetOnPreSelect);
	CreateNative("EntitySelector.SetOnPostSelect", Native_Selector_SetOnPostSelect);
	CreateNative("EntitySelector.SetOnUnselect", Native_Selector_SetOnUnselect);
	CreateNative("EntitySelector.AddEntity", Native_Selector_AddEntity);
	CreateNative("EntitySelector.RemoveEntity", Native_Selector_RemoveEntity);
	CreateNative("EntitySelector.Cancel", Native_Selector_Cancel);
	CreateNative("EntitySelector.End", Native_Selector_End);
	return APLRes_Success;
}


public void OnPluginStart() {
	EngineVersion g_Game = GetEngineVersion();
	if(g_Game != Engine_Left4Dead && g_Game != Engine_Left4Dead2) {
		SetFailState("This plugin is for L4D/L4D2 only.");	
	}

	createdWalls = new ArrayList();
	g_spawnedItems = new ArrayList(2);
	ROOT_CATEGORY.name = "Categories";
	
	LoadTranslations("common.phrases");
	HookEvent("player_entered_checkpoint", OnEnterSaferoom);
	HookEvent("player_left_checkpoint", OnLeaveSaferoom);
	HookEvent("player_bot_replace",  Event_PlayerToIdle);
	HookEvent("bot_player_replace", Event_PlayerOutOfIdle);
	HookEvent("player_spawn", Event_PlayerSpawn);

	RegConsoleCmd("sm_hat", Command_DoAHat, "Hats");
	RegAdminCmd("sm_hatf", Command_DoAHat, ADMFLAG_ROOT, "Hats");
	RegAdminCmd("sm_mkwall", Command_MakeWall, ADMFLAG_CUSTOM2);
	RegAdminCmd("sm_edit", Command_Editor, ADMFLAG_CUSTOM2);
	RegAdminCmd("sm_wall", Command_Editor, ADMFLAG_CUSTOM2);
	RegAdminCmd("sm_prop", Command_Props, ADMFLAG_CUSTOM2);
	RegConsoleCmd("sm_hatp", Command_DoAHatPreset);

	cvar_sm_hats_blacklist_enabled = CreateConVar("sm_hats_blacklist_enabled", "1", "Is the prop blacklist enabled", FCVAR_NONE, true, 0.0, true, 1.0);
	cvar_sm_hats_enabled = CreateConVar("sm_hats_enabled", "1.0", "Enable hats.\n0=OFF, 1=Admins Only, 2=Any", FCVAR_NONE, true, 0.0, true, 2.0);
	cvar_sm_hats_enabled.AddChangeHook(Event_HatsEnableChanged);
	cvar_sm_hats_flags = CreateConVar("sm_hats_features", "153", "Toggle certain features. Add bits together\n1 = Player Hats\n2 = Respect Admin Immunity\n4 = Create a fake hat for hat wearer to view instead, and for yeeting\n8 = No saferoom hats\n16 = Player hatting requires victim consent\n32 = Infected Hats\n64 = Reverse hats\n128 = Delete Thrown Hats", FCVAR_CHEAT, true, 0.0);
	cvar_sm_hats_rainbow_speed = CreateConVar("sm_hats_rainbow_speed", "1", "Speed of rainbow", FCVAR_NONE, true, 0.0);
	cvar_sm_hats_max_distance = CreateConVar("sm_hats_distance", "240", "The max distance away you can hat something. 0 = disable", FCVAR_NONE, true, 0.0);

	if(SQL_CheckConfig(DATABASE_CONFIG_NAME)) {
		if(!ConnectDB()) {
			LogError("Failed to connect to database.");
		}
	}
	

	noHatVictimCookie = new Cookie("hats_no_target", "Disables other players from making you their hat", CookieAccess_Public);
	noHatVictimCookie.SetPrefabMenu(CookieMenu_OnOff_Int, "Disable player hats for self", OnLocalPlayerHatCookieSelect);

	hatPresetCookie = new Cookie("hats_preset", "Sets the preset hat you spawn with", CookieAccess_Public);

	int entity = -1;
	char targetName[32];
	while((entity = FindEntityByClassname(entity, "func_brush")) != INVALID_ENT_REFERENCE) {
		GetEntPropString(entity, Prop_Data, "m_iName", targetName, sizeof(targetName));
		if(StrContains(targetName, "l4d2_hats_") == 0) {
			createdWalls.Push(EntIndexToEntRef(entity));
			SDKHook(entity, SDKHook_Use, OnWallClicked);
		}

	}

	for(int i = 1; i <= MaxClients; i++) {
		Editor[i].client = i;
		Editor[i].Reset(true);
		g_PropData[i].Init(i);
		hatData[i].yeetGroundTimer = null;
	}

	LoadPresets();

	TopMenu topMenu;
	if (LibraryExists("adminmenu") && ((topMenu = GetAdminTopMenu()) != null)) {
		OnAdminMenuReady(topMenu);
	}
}

public void OnLibraryRemoved(const char[] name) {
  if (StrEqual(name, "adminmenu", false)) {
		g_topMenu = null;
   } 
}

///////////////////////////////////////////////////////////////////////////////////////////////

public void OnEnterSaferoom(Event event, const char[] name, bool dontBroadcast) {
	int userid = event.GetInt("userid");
	int client = GetClientOfUserId(userid);
	if(client > 0 && client <= MaxClients && IsValidClient(client) && GetClientTeam(client) == 2 && !IsFakeClient(client)) {
		inSaferoom[client] = true;
		if(cvar_sm_hats_flags.IntValue & view_as<int>(HatConfig_NoSaferoomHats)) {
			if(HasHat(client) && !HasFlag(client, HAT_PRESET)) {
				if(!IsHatAllowedInSaferoom(client)) {
					PrintToChat(client, "[Hats] Hat is not allowed in the saferoom and has been returned");
					ClearHat(client, true);
				} else {
					CreateTimer(2.0, Timer_PlaceHat, userid);
				}
			}
		}
	}
}

public void OnLeaveSaferoom(Event event, const char[] name, bool dontBroadcast) {
	int userid = event.GetInt("userid");
	int client = GetClientOfUserId(userid);
	if(client > 0 && client <= MaxClients && IsValidClient(client) && GetClientTeam(client) == 2) {
		inSaferoom[client] = false;
	}
}

Action Timer_PlaceHat(Handle h, int userid) {
	int client = GetClientOfUserId(userid);
	if(client > 0 && HasHat(client)) {
		GetClientAbsOrigin(client, hatData[client].orgPos);
		GetClientEyeAngles(client, hatData[client].orgAng);
		// GetHorizontalPositionFromOrigin(hatData[client].orgPos, hatData[client].orgAng, 40.0, hatData[client].orgPos);
		hatData[client].orgAng[0] = 0.0;
		PrintToChat(client, "[Hats] Hat has been placed down");
		ClearHat(client, true);
	}
	return Plugin_Handled;
}

// Tries to find a valid location at user's cursor, avoiding placing into solid walls (such as invisible walls) or objects
stock bool GetSmartCursorLocation(int client, float outPos[3]) {
	float start[3], angle[3], ceilPos[3], wallPos[3], normal[3];
	// Get the cursor location
	GetClientEyePosition(client, start);
	GetClientEyeAngles(client, angle);
	TR_TraceRayFilter(start, angle, MASK_SOLID, RayType_Infinite, Filter_NoPlayers, client);
	if(TR_DidHit()) {
		TR_GetEndPosition(outPos);
		// Check if the position is a wall
		TR_GetPlaneNormal(null, normal);
		if(normal[2] < 0.1) {

			// Find a suitable position above
			start[0] = outPos[0];
			start[1] = outPos[1];
			start[2] = outPos[2] += 100.0;
			TR_TraceRayFilter(outPos, start, MASK_SOLID, RayType_EndPoint, TraceEntityFilterPlayer, client);
			bool ceilCollided = TR_DidHit();
			bool ceilOK = !TR_AllSolid();
			TR_GetEndPosition(ceilPos);
			// float distCeil = GetVectorDistance(outPos, ceilPos, true);

			// Find a suitable position backwards
			angle[0] = 70.0;
			angle[1] += 180.0;
			TR_TraceRayFilter(outPos, angle, MASK_SOLID, RayType_Infinite, TraceEntityFilterPlayer, client);
			bool wallCollided = TR_DidHit();
			TR_GetEndPosition(wallPos);
			float distWall = GetVectorDistance(outPos, wallPos, true);

			if(ceilCollided && wallCollided)

			if(wallCollided && distWall < 62500) {
				outPos = wallPos;
			} else if(ceilOK) {
				outPos = ceilPos;
			}
		}
		
		return true;
	} else {
		return false;
	}
} 

// Periodically fixes hat offsets, as some events/actions/anything can cause entities to offset from their parent
Action Timer_RemountHats(Handle h) {
	float p1[3], p2[3];
	for(int i = 1; i <= MaxClients; i++) {
		int entity = GetHat(i);
		if(IsClientConnected(i) && IsClientInGame(i) && !HasFlag(i, HAT_POCKET)) {
			int visibleEntity = EntRefToEntIndex(hatData[i].visibleEntity);
			if(entity > 0) {
				GetClientAbsOrigin(i, p1);
				GetEntPropVector(entity, Prop_Send, "m_vecOrigin", p2);
				if(GetVectorDistance(p1, p2) > 40000.0) {
					ClearParent(entity);
					if(visibleEntity > 0) {
						ClearParent(visibleEntity);
					}
					RequestFrame(Frame_Remount, i);
				}
			} else if(visibleEntity > 0) {
				RemoveEntity(visibleEntity);
				hatData[i].visibleEntity = INVALID_ENT_REFERENCE;
			}
		}
	}
	return Plugin_Handled;
}

// Remounts entity in a new frame to ensure their parent was properly cleared
void Frame_Remount(int i) {
	int entity = GetHat(i);
	if(entity == -1) return;
	SetParent(entity, i);
	SetParentAttachment(entity, hatData[i].attachPoint, false);
	SetParentAttachment(entity, hatData[i].attachPoint, true);
	
	int visibleEntity = EntRefToEntIndex(hatData[i].visibleEntity);
	if(visibleEntity > 0) {
		SetParent(visibleEntity, i);
		SetParentAttachment(visibleEntity, hatData[i].attachPoint, false);
		SetParentAttachment(visibleEntity, hatData[i].attachPoint, true);
	}
}


// Handles making a prop sleep after a set amount of time (called after hat yeet)
Action Timer_PropSleep(Handle h, DataPack pack) {
	pack.Reset();
	int ref = pack.ReadCell();
	int client = GetClientOfUserId(pack.ReadCell());
	if(client > 0 && IsValidEntity(ref)) {
		// CheckKill(ref, client);
		float vel[3];
		TeleportEntity(ref, NULL_VECTOR, NULL_VECTOR, vel);
		PrintToServer("Hats: Yeet delete timeout");
		if(hatData[client].yeetGroundTimer != null) {
			delete hatData[client].yeetGroundTimer;
		}
	}
	return Plugin_Continue;
}
Action Timer_GroundKill(Handle h, DataPack pack) {
	pack.Reset();
	int ref = pack.ReadCell();
	int client = GetClientOfUserId(pack.ReadCell());
	if(client > 0 && IsValidEntity(ref)) {
		float vel[3];
		GetEntPropVector(ref, Prop_Data, "m_vecVelocity", vel);
		if(FloatAbs(vel[2]) < 0.2 || IsNearGround(ref)) {
			PrintToServer("Hats: Yeet ground check %b %b", FloatAbs(vel[2]) < 0.2, IsNearGround(ref));
			vel[0] = 0.0;
			vel[1] = 0.0;
			vel[2] = 0.0;
			TeleportEntity(ref, NULL_VECTOR, NULL_VECTOR, vel);
			// CheckKill(ref, client);
			hatData[client].yeetGroundTimer = null;
			return Plugin_Stop;
		}
		return Plugin_Continue;
	}
	return Plugin_Stop;
}



void CheckKill(int ref, int client) {
	// Check if we should delete thrown hat objects, such as physic props
	if(cvar_sm_hats_flags.IntValue & view_as<int>(HatConfig_DeleteThrownHats)) {
		// Don't delete if someone has hatted it (including ourself):
		for(int i = 1; i <= MaxClients; i++) {
			if(IsClientConnected(i) && IsClientInGame(i) && hatData[i].entity == ref) {
				return;
			}
		}
		
		// Check for prop_ class, only yeetable non-player entity we care as they may be large/collidabl
		// Things like weapons aren't a problem as you can't "collide" and get thrown
		if(EntRefToEntIndex(ref) > MaxClients) {
			char classname[64];
			GetEntityClassname(ref, classname, sizeof(classname));
			if(StrContains(classname, "prop_") > -1) {
				RemoveEntity(ref);
				return;
			}
		}
	}
	AcceptEntityInput(ref, "Sleep");
}

Action Timer_PropYeetEnd(Handle h, DataPack pack) {
	pack.Reset();
	int realEnt = EntRefToEntIndex(pack.ReadCell());
	// int visibleEnt = EntRefToEntIndex(pack.ReadCell());
	// if(IsValidEntity(visibleEnt)) {
	// 	float pos[3], ang[3];
	// 	GetEntPropVector(visibleEnt, Prop_Send, "m_vecOrigin", pos);
	// 	GetEntPropVector(visibleEnt, Prop_Send, "m_angRotation", ang);
	// 	AcceptEntityInput(visibleEnt, "kill");
	// 	if(IsValidEntity(realEnt)) {
	// 		TeleportEntity(realEnt, pos, ang, NULL_VECTOR);
	// 	}
	// }
	if(IsValidEntity(realEnt)) {
		SetEntProp(realEnt, Prop_Send, "m_CollisionGroup", pack.ReadCell());
		SetEntProp(realEnt, Prop_Send, "m_nSolidType", pack.ReadCell());
		SetEntProp(realEnt, Prop_Send, "movetype", pack.ReadCell());
		AcceptEntityInput(realEnt, "Sleep");
	}

	return Plugin_Handled;
}

Action Timer_RemoveGod(Handle h, int userid) {
	int client = GetClientOfUserId(userid);
	if(client) {
		tempGod[client] = false;
		SDKUnhook(client, SDKHook_OnTakeDamageAlive, OnTakeDamageAlive);
	}
	return Plugin_Handled;
}

void Event_PlayerOutOfIdle(Event event, const char[] name, bool dontBroadcast) {
	int bot = GetClientOfUserId(event.GetInt("bot"));
	int client = GetClientOfUserId(event.GetInt("player"));
	if(GetClientTeam(client) != 2) return;
	float pos[3];
	for(int i = 1; i <= MaxClients; i++) {
		if(hatData[i].entity == bot) {
			GetClientAbsOrigin(i, pos);
			ClearHat(i);
			hatData[i].entity = EntIndexToEntRef(client);
			TeleportEntity(hatData[i].entity, pos, hatData[i].orgAng, NULL_VECTOR);
			return;
		}
	}
	PrintToServer("Fixing hatted player to bot: Bot %N to client %N", bot, client);
	// Incase they removed hat right after, manually fix them
	ClearParent(client);
	ClearParent(bot);
	SetEntProp(client, Prop_Send, "m_CollisionGroup", 5);
	SetEntProp(client, Prop_Send, "m_nSolidType", 2);
	SetEntityMoveType(client, MOVETYPE_WALK);
	RequestFrame(Frame_FixClient, client);
	// SetEntProp(client, Prop_Send, "movetype", MOVETYPE_ISOMETRIC);
}

void Frame_FixClient(int client) {
	if(IsClientConnected(client) && GetClientTeam(client) == 2) {
	ClearParent(client);
	SetEntProp(client, Prop_Send, "m_CollisionGroup", 5);
	SetEntProp(client, Prop_Send, "m_nSolidType", 2);
	SetEntityMoveType(client, MOVETYPE_WALK);
	}
	// SetEntProp(client, Prop_Send, "movetype", MOVETYPE_ISOMETRIC);
}
public void Event_PlayerToIdle(Event event, const char[] name, bool dontBroadcast) {
	int bot = GetClientOfUserId(event.GetInt("bot"));
	int client = GetClientOfUserId(event.GetInt("player"));
	if(GetClientTeam(client) != 2) return;
	float pos[3];
	for(int i = 1; i <= MaxClients; i++) {
		if(hatData[i].entity == client) {
			GetClientAbsOrigin(i, pos);
			ClearHat(i);
			hatData[i].entity = EntIndexToEntRef(bot);
			TeleportEntity(hatData[i].entity, pos, hatData[i].orgAng, NULL_VECTOR);
			return;
		}
	}
	// Incase they removed hat right after, manually fix them
	ClearParent(bot);
	SetEntProp(bot, Prop_Send, "m_CollisionGroup", 5);
	SetEntProp(bot, Prop_Send, "m_nSolidType", 2);
	SetEntityMoveType(bot, MOVETYPE_WALK);
}

void OnLocalPlayerHatCookieSelect(int client, CookieMenuAction action, any info, char[] buffer, int maxlen) {
	if(action != CookieMenuAction_SelectOption) return;
	bool value = StringToInt(buffer) == 1;
	if(value) {
		for(int i = 1; i <= MaxClients; i++) {
			int hat = GetHat(i);
			if(hat == client) {
				ClearHat(i, false);
				PrintToChat(i, "%N has blocked player hats for themselves", client);
			}
		}
		ClearHat(client, false);
	}
}

public void Event_HatsEnableChanged(ConVar convar, const char[] sOldValue, const char[] sNewValue) {
	if(convar.IntValue == 0) {
		ClearHats();
	} else if(convar.IntValue == 1) {
		for(int i = 1; i <= MaxClients; i++) {
			if(IsClientConnected(i) && GetUserAdmin(i) == INVALID_ADMIN_ID && HasHat(i)) {
				ClearHat(i, false);
			}
		}
	}
}

ArrayList GetSpawnLocations() {
	ArrayList list = new ArrayList(); 
	ArrayList newList = new ArrayList();
	L4D_GetAllNavAreas(list);
	for(int i = 0; i < list.Length; i++) {
		Address nav = list.Get(i);
		if(L4D_GetNavArea_SpawnAttributes(nav) & NAV_SPAWN_THREAT) {
			newList.Push(nav);
		}
	}
	delete list;
	PrintToServer("[Hats] Got %d valid locations", newList.Length);
	return newList;
}


void ChooseRandomPosition(float pos[3], int ignoreClient = 0) {
	if(NavAreas.Length > 0 && GetURandomFloat() > 0.5) {
		int nav = NavAreas.Get(GetURandomInt() % (NavAreas.Length - 1));
		L4D_FindRandomSpot(nav, pos);
	} else {
		int survivor = GetRandomClient(5, 1);
		if(ignoreClient > 0 && survivor == ignoreClient) survivor = GetRandomClient(5, 1);
		if(survivor > 0) {
			GetClientAbsOrigin(survivor, pos);
		}
	}
}

bool g_inRotate[MAXPLAYERS+1];
public Action OnPlayerRunCmd(int client, int& buttons, int& impulse, float vel[3], float angles[3], int& weapon, int& subtype, int& cmdnum, int& tickcount, int& seed, int mouse[2]) {
	float tick = GetGameTime();
	//////////////////////////////
	// OnPlayerRunCmd :: HATS
	/////////////////////////////
	int oldButtons = GetEntProp(client, Prop_Data, "m_nOldButtons");
	if(IsHatsEnabled(client)) {
		int entity = GetHat(client);
		int visibleEntity = EntRefToEntIndex(hatData[client].visibleEntity);
		if(entity > 0) {
			// Crash prevention: Prevent hat from touching ladder as that can cause server crashes
			if(!onLadder[client] && GetEntityMoveType(client) == MOVETYPE_LADDER) {
				onLadder[client] = true;
				ClearParent(entity);

				// If hat is not a player, we teleport them to the void (0, 0, 0)
				// Ostherwise, we just simply dismount the player while hatter is on ladder
				if(entity >= MaxClients)
					TeleportEntity(entity, EMPTY_ANG, NULL_VECTOR, NULL_VECTOR);
				if(visibleEntity > 0) {
					hatData[client].visibleEntity = INVALID_ENT_REFERENCE;
					RemoveEntity(visibleEntity);
				}
			} 
			// Player is no longer on ladder, restore hat:
			else if(onLadder[client] && GetEntityMoveType(client) != MOVETYPE_LADDER) {
				onLadder[client] = false;
				EquipHat(client, entity);
			}

			// Do the same crash protection for the hat itself, just to be safe:
			if(entity <= MaxClients) {
				if(!onLadder[entity] && GetEntityMoveType(entity) == MOVETYPE_LADDER) {
					onLadder[entity] = true;
					ClearParent(entity);
				} else if(onLadder[entity] && GetEntityMoveType(entity) != MOVETYPE_LADDER) {
					onLadder[entity] = false;
					EquipHat(client, entity);
				}
			}

			// Rainbow hat processing
			if(HasFlag(client, HAT_RAINBOW)) {
				// Decrement and flip, possibly when rainbowticks
				if(hatData[client].rainbowReverse) {
					hatData[client].rainbowColor[0] -= cvar_sm_hats_rainbow_speed.FloatValue;
				} else {
					hatData[client].rainbowColor[0] += cvar_sm_hats_rainbow_speed.FloatValue;
				}
				
				if(hatData[client].rainbowColor[0] > 360.0) {
					hatData[client].rainbowReverse = true;
					hatData[client].rainbowColor[0] = 360.0;
				} else if(hatData[client].rainbowColor[0] < 0.0) {
					hatData[client].rainbowReverse = false;
					hatData[client].rainbowColor[0] = 0.0;
				}

				static int rgb[3];
				HSVToRGBInt(hatData[client].rainbowColor, rgb);
				SetEntityRenderColor(entity, rgb[0], rgb[1], rgb[2]);
				hatData[client].rainbowTicks = -cvar_sm_hats_rainbow_speed.IntValue;
				EquipHat(client, entity);
			}

			// If bot is commandable and reversed (player reverse-hat common/survivor), change position:
			if(HasFlag(client, HAT_COMMANDABLE | HAT_REVERSED) && tickcount % 200 == 0) {
				float pos[3];
				ChooseRandomPosition(pos, client);
				L4D2_CommandABot(entity, client, BOT_CMD_MOVE, pos);
			}
		} 
		// Detect E + R to offset hat or place down
		if(buttons & IN_USE && buttons & IN_RELOAD) {
			if(entity > 0) {
				if(buttons & IN_ZOOM) {
					// Offset controls:
					// if(buttons & IN_JUMP) hatData[client].offset[2] += 1.0;
					// if(buttons & IN_DUCK) hatData[client].offset[2] -= 1.0;
					if(buttons & IN_FORWARD) hatData[client].offset[0] += 1.0;
					if(buttons & IN_BACK) hatData[client].offset[0] -= 1.0;
					if(buttons & IN_MOVELEFT) hatData[client].offset[1] += 1.0;
					if(buttons & IN_MOVERIGHT) hatData[client].offset[1] -= 1.0;
					TeleportEntity(entity, hatData[client].offset, angles, vel);
					return Plugin_Handled;
				} else if(tick - cmdThrottle[client] > 0.25) {
					if(buttons & IN_ATTACK) { // doesn't work reliably for some reason
						ClientCommand(client, "sm_hat y");
					} else if(buttons & IN_DUCK) {
						ClientCommand(client, "sm_hat p");
					}
				}
			} else if(tick - cmdThrottle[client] > 0.25 && L4D2_GetPlayerUseAction(client) == L4D2UseAction_None) {
				ClientCommand(client, "sm_hat");
			}
			cmdThrottle[client] = tick;
			hatData[client].angles = angles;
			return Plugin_Handled;
		}
	}

	//////////////////////////////
	// OnPlayerRunCmd :: ENTITY EDITOR
	/////////////////////////////
	if(g_pendingSaveClient == client) {
		if(g_PropData[client].pendingSaveType == Save_Schematic) {
			// move cursor? or should be editor anyway
		}
	} else if(g_PropData[client].Selector.IsActive()) {
		SetWeaponDelay(client, 0.5);
		if(tick - cmdThrottle[client] >= 0.20) {
			if(buttons & IN_ATTACK) {
				int entity = GetLookingEntity(client, Filter_ValidHats);
				if(entity > 0) {
					if(g_PropData[client].Selector.AddEntity(entity) != -1) {
						PrecacheSound("ui/beep07.wav");
						EmitSoundToClient(client, "ui/beep07.wav", entity, SND_CHANGEVOL, .volume = 0.5);
					}
				} else {
					PrintHintText(client, "No entity found");
				}
			} else if(buttons & IN_ATTACK2) {
				int entity = GetLookingEntity(client, Filter_ValidHats);
				if(entity > 0) {
					if(g_PropData[client].Selector.RemoveEntity(entity)) {
						PrecacheSound("ui/beep22.wav");
						EmitSoundToClient(client, "ui/beep22.wav", entity, SND_CHANGEVOL, .volume = 0.5);
					}
				}
			} else if(buttons & IN_USE) {
				if(buttons & IN_SPEED) {
					//Delete
					g_PropData[client].Selector.End();
				} else if(buttons & IN_DUCK) {
					//Cancel
					g_PropData[client].Selector.Cancel();
				}
			}
			cmdThrottle[client] = tick;
		}
	} else if(Editor[client].IsActive()) { 
		// if(buttons & IN_USE && buttons & IN_RELOAD) {
		// 	ClientCommand(client, "sm_wall done");
		// 	return Plugin_Handled;
		// }
		bool allowMove = true;
		switch(Editor[client].mode) {
			case MOVE_ORIGIN: {
				SetWeaponDelay(client, 0.5);

				bool isRotate;
				int flags = GetEntityFlags(client);
				if(buttons & IN_RELOAD) {
					if(!g_inRotate[client]) {
						g_inRotate[client] = true;
					}
					if(!(oldButtons & IN_JUMP) && (buttons & IN_JUMP)) {
						buttons &= ~IN_JUMP;
						Editor[client].CycleStacker();
					} else if(!(oldButtons & IN_SPEED) && (buttons & IN_SPEED)) {
						Editor[client].ToggleCollision();
						return Plugin_Handled; 
					}  else if(!(oldButtons & IN_DUCK) && (buttons & IN_DUCK)) {
						Editor[client].ToggleCollisionRotate();
						return Plugin_Handled; 
					} else {
						PrintCenterText(client, "%.1f %.1f %.1f", Editor[client].angles[0], Editor[client].angles[1], Editor[client].angles[2]);
						isRotate = true;
						SetEntityFlags(client, flags |= FL_FROZEN);
						if(!(oldButtons & IN_ATTACK) && (buttons & IN_ATTACK)) Editor[client].CycleAxis();
						else if(!(oldButtons & IN_ATTACK2) && (buttons & IN_ATTACK2))  Editor[client].CycleSnapAngle(tick);
						
						// Rotation control:
						// Turn off rotate when player wants rotate
						Editor[client].hasCollisionRotate = false;
						if(tick - cmdThrottle[client] > 0.1) {
							if(Editor[client].axis == 0) {
								int mouseXAbs = IntAbs(mouse[0]); 
								int mouseYAbs = IntAbs(mouse[1]); 
								bool XOverY = mouseXAbs > mouseYAbs;
								if(mouseYAbs > 10 && !XOverY) {
									Editor[client].IncrementAxis(0, mouse[1]);
								} else if(mouseXAbs > 10 && XOverY) {
									Editor[client].IncrementAxis(1, mouse[0]);
								}
							}
							else if(Editor[client].axis == 1) {
								if(mouse[0] > 10) Editor[client].angles[2] += Editor[client].snapAngle;
								else if(mouse[0] < -10) Editor[client].angles[2] -= Editor[client].snapAngle;
							}
							cmdThrottle[client] = tick;
						}
					}
				} else {
					if(g_inRotate[client]) {
						g_inRotate[client] = false;
					}
					// Move position
					float moveAmount = (buttons & IN_SPEED) ? 2.0 : 1.0;
					if(buttons & IN_ATTACK) Editor[client].moveDistance += moveAmount;
					else if(buttons & IN_ATTACK2) Editor[client].moveDistance -= moveAmount;
				}

				// Clear IN_FROZEN when no longer rotate
				if(!isRotate && flags & FL_FROZEN) {
					flags = flags & ~FL_FROZEN;
					SetEntityFlags(client, flags);
				}
				if(Editor[client].stackerDirection == Stack_Off)
					CalculateEditorPosition(client, Filter_IgnorePlayerAndWall);
			}
			case SCALE: {
				SetWeaponDelay(client, 0.5);
				allowMove = false;
				if(buttons & IN_USE) {
					Editor[client].CycleSpeed(tick);
				} else {
					if(buttons & IN_MOVELEFT) {
						Editor[client].IncrementSize(0, -1.0);
					} else if(buttons & IN_MOVERIGHT) {
						Editor[client].IncrementSize(0, 1.0);
						Editor[client].size[0] += Editor[client].moveSpeed; 
					}
					if(buttons & IN_FORWARD) {
						Editor[client].IncrementSize(0, 1.0);
					} else if(buttons & IN_BACK) {
						Editor[client].IncrementSize(0, -1.0);
					}
					if(buttons & IN_JUMP) {
						Editor[client].IncrementSize(0, 1.0);
					} else if(buttons & IN_DUCK) {
						Editor[client].IncrementSize(0, -1.0);
					}
				}
			}
			case COLOR: {
				SetWeaponDelay(client, 0.5);
				PrintHintText(client, "%d %d %d %d", Editor[client].color[0], Editor[client].color[1], Editor[client].color[2], Editor[client].color[3]);
				if(buttons & IN_USE) {
					Editor[client].CycleColorComponent(tick);
				} else if(buttons & IN_ATTACK2) {
					Editor[client].IncreaseColor(1);
					allowMove = false;
				} else if(buttons & IN_ATTACK) {
					Editor[client].IncreaseColor(-1);
					allowMove = false;
				}
			}
		}
		if(buttons & IN_DUCK) {

		}
		if(Editor[client].mode != COLOR && !(oldButtons & IN_USE) && buttons & IN_USE) {
			if(buttons & IN_SPEED) {
				Editor[client].Cancel();
			} else if(buttons & IN_DUCK) {
				Editor[client].CycleBuildType();
				// Editor[client].ShowExtraOptions();
			} else {
				int entity;
				Editor[client].Done(entity);
			}
			
		} else if(!(oldButtons & IN_ZOOM) && buttons & IN_ZOOM) {
			Editor[client].CycleMode(); // ZOOM: Cycle forward
		}

		Editor[client].Draw(BUILDER_COLOR, 0.1, 0.1);
		return allowMove ? Plugin_Continue : Plugin_Handled;
	}

	return Plugin_Continue;
}

int IntAbs(int a) {
	if(a < 0) {
		return a * -1;
	}
	return a;
}

// Don't show real entity to hat wearer (Show for ALL but hat wearer)
Action OnRealTransmit(int entity, int client) {
	#if defined DEBUG_HAT_SHOW_FAKE
		return Plugin_Continue;
	#endif
	if(hatData[client].entity != INVALID_ENT_REFERENCE && EntRefToEntIndex(hatData[client].entity) == entity)
		return Plugin_Handled;
	return Plugin_Continue;
}

// Only show to hat wearer (do not show to ALL)
Action OnVisibleTransmit(int entity, int client) {
	#if defined DEBUG_HAT_SHOW_FAKE
		return Plugin_Continue;
	#endif
	if(hatData[client].visibleEntity != INVALID_ENT_REFERENCE && EntRefToEntIndex(hatData[client].visibleEntity) != entity)
		return Plugin_Handled;
	return Plugin_Continue;
}


public Action OnTakeDamageAlive(int victim, int& attacker, int& inflictor, float& damage, int& damagetype) {
	if(victim > MaxClients || victim <= 0) return Plugin_Continue;
	if(damage > 0.0 && tempGod[victim]) {
		damage = 0.0;
		return Plugin_Handled;
	}
	if(attacker > MaxClients || attacker <= 0) return Plugin_Continue;
	if(victim == EntRefToEntIndex(hatData[attacker].entity) || attacker == EntRefToEntIndex(hatData[victim].entity)) {
		damage = 0.0;
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(client > 0) {
		if(!HasHat(client) && !IsFakeClient(client)) {
			hatPresetCookie.Get(client, ActivePreset[client], 32);
			if(ActivePreset[client][0] != '\0') {
				RestoreActivePreset(client);
				ReplyToCommand(client, "[Hats] Applied your hat preset! Clear it with /hatp");
			}
		}
		SDKHook(client, SDKHook_WeaponCanUse, OnWeaponUse);
	}
}

Action OnWeaponUse(int client, int weapon) {
	int ref = EntIndexToEntRef(weapon);
	// Prevent picking up weapons that are previews
	for(int i = 1; i <= MaxClients; i++) {
		if(Editor[i].entity == ref && Editor[i].flags & Edit_Preview) {
			return Plugin_Handled;
		}
	}
	return Plugin_Continue;
}

public void OnClientDisconnect(int client) {
	tempGod[client] = false;
	Editor[client].Reset();
	g_PropData[client].Reset();
	if(hatData[client].yeetGroundTimer != null)
		delete hatData[client].yeetGroundTimer;
	if(g_pendingSaveClient == client) {
		g_pendingSaveClient = 0;
		ClearSavePreview();
	}
	ClearHat(client, true);
}

public void OnEntityDestroyed(int entity) {
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && !IsFakeClient(i)) {
			if(hatData[i].entity != INVALID_ENT_REFERENCE && EntRefToEntIndex(hatData[i].entity) == entity) {
				ClearHat(i);
				PrintHintText(i, "Hat has vanished");
				ClientCommand(i, "play ui/menu_back.wav");
				break;
			}
		}
	}
}
public void OnMapStart() {
	PrecacheModel(DUMMY_MODEL);
	g_iLaserIndex = PrecacheModel("materials/sprites/laserbeam.vmt");
	CreateTimer(30.0, Timer_RemountHats, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	for(int i = 1; i <= MaxClients; i++) {
		cmdThrottle[i] = 0.0;
		tempGod[i] = false;
	}
	GetCurrentMap(g_currentMap, sizeof(g_currentMap));
	NavAreas = GetSpawnLocations();
}


public void OnMapEnd() {
	delete NavAreas;
	g_spawnedItems.Clear();
	for(int i = 1; i <= createdWalls.Length; i++) {
		if(hatData[i].yeetGroundTimer != null) { 
			delete hatData[i].yeetGroundTimer;
		}
		DeleteWall(i);
	}
	createdWalls.Clear();
	ClearHats();
	UnloadCategories();
	UnloadSave();
	SaveRecents();
}
public void OnPluginEnd() {
	ClearHats();
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i)) {
			int flags = GetEntityFlags(i) & ~FL_FROZEN;
			SetEntityFlags(i, flags);
		}
	}
	if(g_spawnedItems != null) {
		delete g_spawnedItems;
	}
	TriggerInput("prop_preview", "Kill");
}

public bool TraceEntityFilterPlayer(int entity, int contentsMask, any data) {
	if(EntRefToEntIndex(hatData[data].entity) == entity) {
		return false;
	}
	return entity != data;
}  

int GetLookingEntity(int client, TraceEntityFilter filter) {
	static float pos[3], ang[3];
	GetClientEyePosition(client, pos);
	GetClientEyeAngles(client, ang);
	TR_TraceRayFilter(pos, ang, MASK_SOLID, RayType_Infinite, filter, client);
	if(TR_DidHit()) {
		return TR_GetEntityIndex();
	}
	return -1;
}


///////////////////////////////////////////////////////////////////////////////////////////////

stock bool Filter_OnlyPlayers(int entity, int mask, int data) {
	return entity > 0 && entity <= MaxClients && entity != data;
}

stock bool Filter_NoPlayers(int entity, int mask, int data) {
	return entity > MaxClients && entity != data;
}

stock bool Filter_IgnorePlayerAndWall(int entity, int mask, int data) {
	if(entity > MaxClients && entity != data && EntRefToEntIndex(Editor[data].entity) != entity && EntRefToEntIndex(hatData[data].entity) != entity) {
		static char classname[16];
		GetEntityClassname(entity, classname, sizeof(classname));
		// Ignore infected
		return !StrEqual(classname, "infected");
	}
	return false;
}


bool Filter_ValidHats(int entity, int mask, int data) {
	if(entity == data) return false;
	if(entity <= MaxClients && entity > 0) {
		int client = GetRealClient(data);
		if(client == -1) client = data;
		return CanTarget(client); // Don't target if player targetting off
	}
	return CheckBlacklist(entity);
}

bool CheckBlacklist(int entity) {
	if(entity == 0) return false;
	if(cvar_sm_hats_blacklist_enabled.BoolValue) {
		static char buffer[64];
		GetEntityClassname(entity, buffer, sizeof(buffer));
		for(int i = 0; i < MAX_FORBIDDEN_CLASSNAMES; i++) {
			if(StrEqual(FORBIDDEN_CLASSNAMES[i], buffer)) {
				return false;
			}
		}
		if(StrContains(buffer, "prop_") > -1) {
			GetEntPropString(entity, Prop_Data, "m_ModelName", buffer, sizeof(buffer));
			for(int i = 0; i < MAX_FORBIDDEN_MODELS; i++) {
				if(StrEqual(FORBIDDEN_MODELS[i], buffer)) {
					return false;
				}
			}
		}
		GetEntPropString(entity, Prop_Data, "m_iName", buffer, sizeof(buffer));
		if(StrEqual(buffer, "l4d2_randomizer")) {
			return false;
		}
	}
	return true;
}

////////////////////////////////

stock void TriggerInput(const char[] targetName, const char[] input) {
	int entity = -1;
	char _targetName[32];
	while((entity = FindEntityByClassname(entity, "*")) != INVALID_ENT_REFERENCE) {
		GetEntPropString(entity, Prop_Data, "m_iName", _targetName, sizeof(_targetName));
		if(StrEqual(_targetName, targetName)) {
			AcceptEntityInput(entity, input);
		}
	}
}


stock bool FindGround(const float start[3], float end[3]) {
	float angle[3];
	angle[0] = 90.0;

	Handle trace = TR_TraceRayEx(start, angle, MASK_SHOT, RayType_Infinite);
	if(!TR_DidHit(trace)) {
		delete trace;
		return false;
	}
	TR_GetEndPosition(end, trace);
	delete trace;
	return true;
}

stock bool L4D_IsPlayerCapped(int client) {
	if(GetEntPropEnt(client, Prop_Send, "m_pummelAttacker") > 0 || 
		GetEntPropEnt(client, Prop_Send, "m_carryAttacker") > 0 || 
		GetEntPropEnt(client, Prop_Send, "m_pounceAttacker") > 0 || 
		GetEntPropEnt(client, Prop_Send, "m_jockeyAttacker") > 0 || 
		GetEntPropEnt(client, Prop_Send, "m_pounceAttacker") > 0 ||
		GetEntPropEnt(client, Prop_Send, "m_tongueOwner") > 0)
		return true;
	return false;
}
stock void LookAtPoint(int entity, const float destination[3]){
	float angles[3], pos[3], result[3];
	GetEntPropVector(entity, Prop_Send, "m_vecOrigin", pos);
	MakeVectorFromPoints(destination, pos, result);
	GetVectorAngles(result, angles);
	if(angles[0] >= 270){
		angles[0] -= 270;
		angles[0] = (90-angles[0]);
	} else {
		if(angles[0] <= 90){
			angles[0] *= -1;
		}
	}
	angles[1] -= 180;
	TeleportEntity(entity, NULL_VECTOR, angles, NULL_VECTOR);
}

stock float SnapTo(const float value, const float degree) {
	return float(RoundFloat(value / degree)) * degree;
}

stock bool CalculateEditorPosition(int client, TraceEntityFilter filter) {
	if (client > 0 && client <= MaxClients && IsClientInGame(client)) {
		float clientEye[3], clientAngle[3], direction[3];
		GetClientEyePosition(client, clientEye);
		GetClientEyeAngles(client, clientAngle);

		GetAngleVectors(clientAngle, direction, NULL_VECTOR, NULL_VECTOR);
		ScaleVector(direction, Editor[client].moveDistance);
		AddVectors(clientEye, direction, Editor[client].origin);

		if(Editor[client].hasCollision) {
			TR_TraceRayFilter(clientEye, Editor[client].origin, MASK_OPAQUE, RayType_EndPoint, filter, client);
			if (TR_DidHit(INVALID_HANDLE)) {
				TR_GetEndPosition(Editor[client].origin);
				GetEntPropVector(Editor[client].entity, Prop_Send, "m_vecMins", direction);
				Editor[client].origin[2] -= direction[2];
				if(Editor[client].hasCollisionRotate) {
					TR_GetPlaneNormal(INVALID_HANDLE, Editor[client].angles);
					GetVectorAngles(Editor[client].angles, Editor[client].angles);
					Editor[client].angles[0] += 90.0; //need to rotate for some reason
				}
			}
		}

		return true;
	}
	return false;
}