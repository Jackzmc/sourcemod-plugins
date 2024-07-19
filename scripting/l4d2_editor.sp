#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "1.0"

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
#include <ripext>

int g_iLaserIndex;

float cmdThrottle[MAXPLAYERS+1];

TopMenu g_topMenu;

char g_currentMap[64];

//int g_markedMode

#include <editor/editor.sp>
#include <editor/props/base.sp>
#include <editor/natives.sp>
#include <editor>

public Plugin myinfo = {
	name =  "L4D2 Hats & Editor", 
	author = "jackzmc", 
	description = "", 
	version = PLUGIN_VERSION, 
	url = "https://github.com/Jackzmc/sourcemod-plugins"
};

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
	HookEvent("player_spawn", Event_PlayerSpawn);

	RegAdminCmd("sm_mkwall", Command_MakeWall, ADMFLAG_CUSTOM2);
	RegAdminCmd("sm_edit", Command_Editor, ADMFLAG_CUSTOM2);
	RegAdminCmd("sm_wall", Command_Editor, ADMFLAG_CUSTOM2);
	RegAdminCmd("sm_prop", Command_Props, ADMFLAG_CUSTOM2);

	if(SQL_CheckConfig(DATABASE_CONFIG_NAME)) {
		if(!ConnectDB()) {
			LogError("Failed to connect to database.");
		}
	}
	
	int entity = -1;
	char targetName[32];
	while((entity = FindEntityByClassname(entity, "func_brush")) != INVALID_ENT_REFERENCE) {
		GetEntPropString(entity, Prop_Data, "m_iName", targetName, sizeof(targetName));
		if(StrContains(targetName, "editor") == 0) {
			createdWalls.Push(EntIndexToEntRef(entity));
			SDKHook(entity, SDKHook_Use, OnWallClicked);
		}

	}

	for(int i = 1; i <= MaxClients; i++) {
		Editor[i].client = i;
		Editor[i].Reset(true);
		g_PropData[i].Init(i);
	}

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


bool g_inRotate[MAXPLAYERS+1];
public Action OnPlayerRunCmd(int client, int& buttons, int& impulse, float vel[3], float angles[3], int& weapon, int& subtype, int& cmdnum, int& tickcount, int& seed, int mouse[2]) {
	float tick = GetGameTime();
	int oldButtons = GetEntProp(client, Prop_Data, "m_nOldButtons");
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
					ArrayList items = g_PropData[client].Selector.End();
					delete items;
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
						Editor[client].IncrementSize(1, 1.0);
					} else if(buttons & IN_BACK) {
						Editor[client].IncrementSize(1, -1.0);
					}
					if(buttons & IN_JUMP) {
						Editor[client].IncrementSize(2, 1.0);
					} else if(buttons & IN_DUCK) {
						Editor[client].IncrementSize(2, -1.0);
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

void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(client > 0) {
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
	Editor[client].Reset();
	g_PropData[client].Reset();
	if(g_pendingSaveClient == client) {
		g_pendingSaveClient = 0;
		ClearSavePreview();
	}
}

public void OnMapStart() {
	PrecacheModel(DUMMY_MODEL);
	g_iLaserIndex = PrecacheModel("materials/sprites/laserbeam.vmt");
	for(int i = 1; i <= MaxClients; i++) {
		cmdThrottle[i] = 0.0;
	}
	GetCurrentMap(g_currentMap, sizeof(g_currentMap));
}


public void OnMapEnd() {
	g_spawnedItems.Clear();
	for(int i = 1; i <= createdWalls.Length; i++) {
		DeleteWall(i);
	}
	createdWalls.Clear();
	UnloadCategories();
	UnloadSave();
	SaveRecents();
}
public void OnPluginEnd() {
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i)) {
			int flags = GetEntityFlags(i) & ~FL_FROZEN;
			SetEntityFlags(i, flags);
		}
	}
	if(g_spawnedItems != null) {
		delete g_spawnedItems;
	}
	TriggerInput("editor_preview", "Kill");
}

public bool TraceEntityFilterPlayer(int entity, int contentsMask, any data) {
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
	if(entity > MaxClients && entity != data && EntRefToEntIndex(Editor[data].entity) != entity) {
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
		return true;
	}
	return CheckBlacklist(entity);
}


#define MAX_FORBIDDEN_CLASSNAMES 10
static char FORBIDDEN_CLASSNAMES[MAX_FORBIDDEN_CLASSNAMES][] = {
	// "env_physics_blocker",
	// "env_player_blocker",
	"func_brush",
	"func_simpleladder",
	"func_button",
	"func_elevator",
	"func_button_timed",
	"func_movelinear",
	"func_tracktrain",
	// "infected",
	"func_lod",
	"prop_ragdoll",
	"move_rope"
};

#define MAX_FORBIDDEN_MODELS 2
char FORBIDDEN_MODELS[MAX_FORBIDDEN_MODELS][] = {
	"models/props_vehicles/c130.mdl",
	"models/props_vehicles/helicopter_rescue.mdl"
};

bool CheckBlacklist(int entity) {
	if(entity == 0) return false;
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
				if(~Editor[client].flags & Edit_WallCreator) {
					GetEntPropVector(Editor[client].entity, Prop_Send, "m_vecMins", direction);
					Editor[client].origin[2] -= direction[2];
				}
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