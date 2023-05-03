#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "1.0"
#define PLAYER_HAT_REQUEST_COOLDOWN 10
#define DEBUG_GLOW 1
static float EMPTY_ANG[3] = { 0.0, 0.0, 0.0 };

#define DUMMY_MODEL "models/props/cs_office/vending_machine.mdl"

#include <sourcemod>
#include <sdktools>
#include <left4dhooks>
#include <clientprefs>
#include <jutils>
#include <gamemodes/ents>
#include <smlib/effects>

enum hatFlags {
	HAT_NONE = 0,
	HAT_POCKET = 1,
	HAT_REVERSED = 2,
	HAT_COMMANDABLE = 4,
	HAT_RAINBOW = 8
}
enum struct HatData {
	int entity; // The entity REFERENCE
	int visibleEntity; // Thee visible entity REF
	
	// Original data for entity
	float orgPos[3];
	float orgAng[3];
	float offset[3];
	float angles[3];
	int collisionGroup;
	int solidType;
	int moveType;
	
	float scale;
	int flags;
	float rainbowColor[3];
	int rainbowTicks;
	bool rainbowReverse;
}
enum hatFeatures {
	HatConfig_None = 0,
	HatConfig_PlayerHats = 1,
	HatConfig_RespectAdminImmunity = 2,
	HatConfig_FakeHat = 4,
	HatConfig_NoSaferoomHats = 8,
	HatConfig_PlayerHatConsent = 16,
	HatConfig_InfectedHats = 32,
	HatConfig_ReversedHats = 64,
	HatConfig_DeleteThrownHats = 128
}

HatData hatData[MAXPLAYERS+1];
int lastHatRequestTime[MAXPLAYERS+1], g_iLaserIndex;
bool tempGod[MAXPLAYERS+1];
bool inSaferoom[MAXPLAYERS+1];

static float cmdThrottle[MAXPLAYERS+1];
static bool onLadder[MAXPLAYERS+1];
float lastAng[MAXPLAYERS+1][3];

Cookie noHatVictimCookie;
ConVar cvar_sm_hats_enabled;
ConVar cvar_sm_hats_flags;
ConVar cvar_sm_hat_rainbow_speed;
ConVar cvar_sm_hats_blacklist_enabled;

#define MAX_FORBIDDEN_CLASSNAMES 12
static char FORBIDDEN_CLASSNAMES[MAX_FORBIDDEN_CLASSNAMES][] = {
	"prop_door_rotating_checkpoint",
	"env_physics_blocker",
	"env_player_blocker",
	"func_brush",
	"func_simpleladder",
	"prop_door_rotating",
	"func_button",
	"func_elevator",
	"func_button_timed",
	// "func_movelinear",
	// "infected",
	"func_lod",
	"func_door",
	"prop_ragdoll"
};

#define MAX_REVERSE_CLASSNAMES 2
static char REVERSE_CLASSNAMES[MAX_REVERSE_CLASSNAMES][] = {
	"infected",
	"func_movelinear"
};

int BUILDER_COLOR[4] = { 0, 255, 0, 235 };
int WALL_COLOR[4] = { 255, 0, 0, 235 };
float ORIGIN_SIZE[3] = { 2.0, 2.0, 2.0 };

enum wallMode {
	INACTIVE = 0,
	MOVE_ORIGIN,
	SCALE,
	FREELOOK
}

ArrayList createdWalls;

enum struct WallBuilderData {
	float origin[3];
	float mins[3];
	float angles[3];
	float size[3];
	wallMode mode;
	int axis;
	int snapAngle;
	int movetype;
	int moveSpeed;
	float moveDistance;
	int entity;
	bool canScale;

	void Reset() {
		this.size[0] = this.size[1] = this.size[2] = 5.0;
		this.angles[0] = this.angles[1] = this.angles[2] = 0.0;
		this.axis = 0;
		this.movetype = 0;
		this.canScale = true;
		this.moveDistance = 100.0;
		this.moveSpeed = 1;
		this.snapAngle = 30;
		this.entity = INVALID_ENT_REFERENCE;
		this.CalculateMins();
		this.SetMode(INACTIVE);
	}

	void CalculateMins() {
		this.mins[0] = -this.size[0];
		this.mins[1] = -this.size[1];
		this.mins[2] = -this.size[2];
	}

	void Draw(int color[4], float lifetime, float amplitude = 0.1) {
		if(!this.canScale && this.entity != INVALID_ENT_REFERENCE) {
			TeleportEntity(this.entity, this.origin, this.angles, NULL_VECTOR);
		} else {
			Effect_DrawBeamBoxRotatableToAll(this.origin, this.mins, this.size, this.angles, g_iLaserIndex, 0, 0, 30, lifetime, 0.4, 0.4, 0, amplitude, color, 0);
		}
		Effect_DrawAxisOfRotationToAll(this.origin, this.angles, ORIGIN_SIZE, g_iLaserIndex, 0, 0, 30, 0.2, 0.1, 0.1, 0, 0.0, 0);
	}

	bool IsActive() {
		return this.mode != INACTIVE;
	}

	void SetMode(wallMode mode) {
		this.mode = mode;
	}

	void CycleMode(int client, float tick) {
		if(tick - cmdThrottle[client] <= 0.25) return;
		int flags = GetEntityFlags(client) & ~FL_FROZEN;
		SetEntityFlags(client, flags);
		switch(this.mode) {
			// MODES: 
			// - MOVE (cursor point)
			// - ROTATE
			// - SCALE
			// - FREECAM
			case MOVE_ORIGIN: {
				if(this.canScale) {
					this.mode = SCALE;
					PrintToChat(client, "\x04[Walls]\x01 Mode: \x05Scale\x01 (Press \x04RELOAD\x01 to change mode)");
				} else {
					this.mode = FREELOOK;
					PrintToChat(client, "\x04[Walls]\x01 Mode: \x05Freelook\x01 (Press \x04RELOAD\x01 to change mode)");
				}
			}
			case SCALE: {
				this.mode = FREELOOK;
				PrintToChat(client, "\x04[Walls]\x01 Mode: \x05Freelook\x01 (Press \x04RELOAD\x01 to change mode)");
			}
			case FREELOOK: {
				this.mode = MOVE_ORIGIN;
				PrintToChat(client, "\x04[Walls]\x01 Mode: \x05Move & Rotate\x01 (Press \x04RELOAD\x01 to change mode)");
				// PrintToChat(client, "Hold \x04USE (E)\x01 to rotate, \x04WALK (SHIFT)\x01 to change speed");
			}
		}
		cmdThrottle[client] = tick;
	}

	void CycleAxis(int client, float tick) {
		if(tick - cmdThrottle[client] <= 0.20) return;
		if(this.axis == 0) {
			this.axis = 1;
			PrintToChat(client, "\x04[Walls]\x01 Rotate Axis: \x05HEADING (Y)\x01");
		} else {
			this.axis = 0;
			PrintToChat(client, "\x04[Walls]\x01 Rotate Axis: \x05PITCH (X)\x01");
		}
		cmdThrottle[client] = tick;
	}

	void CycleSnapAngle(int client, float tick) {
		if(tick - cmdThrottle[client] <= 0.20) return;
		switch(this.snapAngle) {
			case 1: this.snapAngle = 15;
			case 15: this.snapAngle = 30;
			case 30: this.snapAngle = 45;
			case 45: this.snapAngle = 90;
			case 90: this.snapAngle = 1;
		}

		this.angles[0] = SnapTo(this.angles[0], float(this.snapAngle));
		this.angles[1] = SnapTo(this.angles[1], float(this.snapAngle));
		this.angles[2] = SnapTo(this.angles[2], float(this.snapAngle));

		if(this.snapAngle == 1)
			PrintToChat(client, "\x04[Walls]\x01 Rotate Snap Degrees: \x04(OFF)\x01", this.snapAngle);
		else
			PrintToChat(client, "\x04[Walls]\x01 Rotate Snap Degrees: \x05%d\x01", this.snapAngle);
		cmdThrottle[client] = tick;
	}

	void CycleSpeed(int client, float tick) {
		if(tick - cmdThrottle[client] <= 0.25) return;
		this.moveSpeed++;
		if(this.moveSpeed > 10) this.moveSpeed = 1;
		PrintToChat(client, "\x04[Walls]\x01 Scale Speed: \x05%d\x01", this.moveSpeed);
		// if(this.movetype == 0) {
		// 	this.movetype = 1;
		// 	PrintToChat(client, "\x04[SM]\x01 Move Type: \x05HEADING (Y)\x01");
		// } else {
		// 	this.movetype = 0;
		// 	PrintToChat(client, "\x04[SM]\x01 Rotate Axis: \x05PITCH (X)\x01");
		// }
		cmdThrottle[client] = tick;
	}

	void CycleMoveMode(int client, float tick) {
		if(tick - cmdThrottle[client] <= 0.25) return;
		this.movetype++;
		PrintToChat(client, "\x04[Walls]\x01 Move Type: \x05%d\x01", this.movetype);
		// if(this.movetype == 0) {
		// 	this.movetype = 1;
		// 	PrintToChat(client, "\x04[SM]\x01 Move Type: \x05HEADING (Y)\x01");
		// } else {
		// 	this.movetype = 0;
		// 	PrintToChat(client, "\x04[SM]\x01 Rotate Axis: \x05PITCH (X)\x01");
		// }
		if(this.movetype == 3) this.movetype = 0;
		cmdThrottle[client] = tick;
	}

	int Build() {
		if(!this.canScale) {
			this.Reset();
			return -3;
		}
		// Don't need to build a new one if we editing:
		int blocker = this.entity;
		bool isEdit = true;
		if(blocker == INVALID_ENT_REFERENCE) {
			isEdit = false;
			blocker = CreateEntityByName("func_brush");
			if(blocker == -1) return -1;
			DispatchKeyValueVector(blocker, "mins", this.mins);
			DispatchKeyValueVector(blocker, "maxs", this.size);
			DispatchKeyValueVector(blocker, "boxmins", this.mins);
			DispatchKeyValueVector(blocker, "boxmaxs", this.size);

			DispatchKeyValueVector(blocker, "angles", this.angles);
			DispatchKeyValue(blocker, "model", DUMMY_MODEL);
			DispatchKeyValue(blocker, "intialstate", "1");
			// DispatchKeyValueVector(blocker, "angles", this.angles);
			DispatchKeyValue(blocker, "BlockType", "4");
			char name[32];
			Format(name, sizeof(name), "l4d2_hats_%d", createdWalls.Length);
			DispatchKeyValue(blocker, "targetname", name);
			// DispatchKeyValue(blocker, "excludednpc", "player");
			TeleportEntity(blocker, this.origin, this.angles, NULL_VECTOR);
			if(!DispatchSpawn(blocker)) return -1;
			SetEntPropVector(blocker, Prop_Send, "m_vecMins", this.mins);
			SetEntPropVector(blocker, Prop_Send, "m_vecMaxs", this.size);
			SetEntProp(blocker, Prop_Send, "m_nSolidType", 2);
			int enteffects = GetEntProp(blocker, Prop_Send, "m_fEffects");
			enteffects |= 32; //EF_NODRAW
			SetEntProp(blocker, Prop_Send, "m_fEffects", enteffects); 
			AcceptEntityInput(blocker, "Enable");
		} else {
			TeleportEntity(this.entity, this.origin, this.angles, NULL_VECTOR);
			SetEntPropVector(this.entity, Prop_Send, "m_vecMins", this.mins);
			SetEntPropVector(this.entity, Prop_Send, "m_vecMaxs", this.size);
		}

		this.Draw(WALL_COLOR, 5.0, 1.0);
		this.Reset();
		return isEdit ? -2 : createdWalls.Push(EntIndexToEntRef(blocker));
	}

	void Import(int entity, bool makeCopy = false) {
		this.Reset();
		GetEntPropVector(entity, Prop_Send, "m_vecOrigin", this.origin);
		GetEntPropVector(entity, Prop_Send, "m_angRotation", this.angles);
		GetEntPropVector(entity, Prop_Send, "m_vecMins", this.mins);
		GetEntPropVector(entity, Prop_Send, "m_vecMaxs", this.size);
		if(!makeCopy) {
			this.entity = entity;
		}
		this.SetMode(SCALE);
	}
}

WallBuilderData WallBuilder[MAXPLAYERS+1];

public Plugin myinfo = 
{
	name =  "L4D2 Hats", 
	author = "jackzmc", 
	description = "", 
	version = PLUGIN_VERSION, 
	url = "https://github.com/Jackzmc/sourcemod-plugins"
};

ArrayList NavAreas;

public void OnPluginStart() {
	EngineVersion g_Game = GetEngineVersion();
	if(g_Game != Engine_Left4Dead && g_Game != Engine_Left4Dead2) {
		SetFailState("This plugin is for L4D/L4D2 only.");	
	}

	createdWalls = new ArrayList();
	
	LoadTranslations("common.phrases");
	HookEvent("player_entered_checkpoint", OnEnterSaferoom);
	HookEvent("player_left_checkpoint", OnLeaveSaferoom);
	HookEvent("player_bot_replace", Event_PlayerOutOfIdle );
	HookEvent("bot_player_replace", Event_PlayerToIdle);

	RegConsoleCmd("sm_hat", Command_DoAHat, "Hats");
	RegAdminCmd("sm_mkwall", Command_MakeWall, ADMFLAG_CHEATS);
	RegAdminCmd("sm_walls", Command_ManageWalls, ADMFLAG_CHEATS);
	RegAdminCmd("sm_wall", Command_ManageWalls, ADMFLAG_CHEATS);

	cvar_sm_hats_blacklist_enabled = CreateConVar("sm_hats_blacklist_enabled", "1", "Is the prop blacklist enabled", FCVAR_NONE, true, 0.0, true, 1.0);
	cvar_sm_hats_enabled = CreateConVar("sm_hats_enabled", "1.0", "Enable hats.\n0=OFF, 1=Admins Only, 2=Any", FCVAR_NONE, true, 0.0, true, 2.0);
	cvar_sm_hats_enabled.AddChangeHook(Event_HatsEnableChanged);
	cvar_sm_hats_flags = CreateConVar("sm_hats_features", "153", "Toggle certain features. Add bits together\n1 = Player Hats\n2 = Respect Admin Immunity\n4 = Create a fake hat for hat wearer to view instead, and for yeeting\n8 = No saferoom hats\n16 = Player hatting requires victim consent\n32 = Infected Hats\n64 = Reverse hats", FCVAR_CHEAT, true, 0.0);
	cvar_sm_hat_rainbow_speed = CreateConVar("sm_hats_rainbow_speed", "1", "Speed of rainbow", FCVAR_NONE, true, 0.0);

	noHatVictimCookie = new Cookie("hats_no_target", "Disables other players from making you their hat", CookieAccess_Public);
	noHatVictimCookie.SetPrefabMenu(CookieMenu_OnOff_Int, "Disable player hats for self", OnLocalPlayerHatCookieSelect);

	int entity = -1;
	char targetName[32];
	while((entity = FindEntityByClassname(entity, "func_brush")) != INVALID_ENT_REFERENCE) {
		GetEntPropString(entity, Prop_Data, "m_iName", targetName, sizeof(targetName));
		if(StrContains(targetName, "l4d2_hats_") == 0) {
			createdWalls.Push(EntIndexToEntRef(entity));
		}
	}
}

////////////////////////////////////////////////////////////////

public Action Command_DoAHat(int client, int args) {
	int hatter = GetHatter(client);
	if(hatter > 0) {
		ClearHat(hatter, HasFlag(hatter, HAT_REVERSED));
		PrintToChat(hatter, "[Hats] %N has unhatted themselves", client);
		return Plugin_Handled;
	}

	AdminId adminId = GetUserAdmin(client);
	if(cvar_sm_hats_enabled.IntValue == 1) {
		if(adminId == INVALID_ADMIN_ID) {
			PrintToChat(client, "[Hats] Hats are for admins only");
			return Plugin_Handled;
		}
	} else if(!adminId.HasFlag(Admin_Cheats)) {
		PrintToChat(client, "[Hats] You do not have permission");
		return Plugin_Handled;
	}
	if(cvar_sm_hats_enabled.IntValue == 0) {
		ReplyToCommand(client, "[Hats] Hats are disabled");
		return Plugin_Handled;
	} else if(GetClientTeam(client) != 2 && ~cvar_sm_hats_flags.IntValue & view_as<int>(HatConfig_InfectedHats)) {
		PrintToChat(client, "[Hats] Hats are only available for survivors.");
		return Plugin_Handled;
	}

	int oldVisible = EntRefToEntIndex(hatData[client].visibleEntity);
	if(oldVisible > 0) {
		AcceptEntityInput(oldVisible, "Kill");
		hatData[client].visibleEntity = INVALID_ENT_REFERENCE;
	}

	int entity = GetHat(client);
	if(entity > 0) {
		char arg[4];
		GetCmdArg(1, arg, sizeof(arg));
		// int orgEntity = entity;
		if(HasFlag(client, HAT_REVERSED)) {
			entity = client;
		}
		ClearParent(entity);

		if(arg[0] == 's') {
			char sizeStr[4];
			GetCmdArg(2, sizeStr, sizeof(sizeStr));
			float size = StringToFloat(sizeStr);
			if(HasEntProp(entity, Prop_Send, "m_flModelScale"))
				SetEntPropFloat(entity, Prop_Send, "m_flModelScale", size);
			else
				PrintHintText(client, "Hat does not support scaling");
			int child = -1;
			while((child = FindEntityByClassname(child, "*")) != INVALID_ENT_REFERENCE )
			{
				int parent = GetEntPropEnt(child, Prop_Data, "m_pParent");
				if(parent == entity && HasEntProp(child, Prop_Send, "m_flModelScale")) {
					if(HasEntProp(child, Prop_Send, "m_flModelScale")) {
						PrintToConsole(client, "found child %d for %d", child, entity);
						SetEntPropFloat(child, Prop_Send, "m_flModelScale", size);
					} else {
						PrintToConsole(client, "Child %d for %d cannot be scaled", child, entity);
					}
					
				}
			}

			EquipHat(client, entity);
			return Plugin_Handled;
		} else if(arg[0] == 'r' && arg[1] == 'a') {
			SetFlag(client, HAT_RAINBOW);
			hatData[client].rainbowTicks = 0;
			hatData[client].rainbowReverse = false;
			hatData[client].rainbowColor[0] = 0.0;
			hatData[client].rainbowColor[1] = 255.0;
			hatData[client].rainbowColor[2] = 255.0;
			EquipHat(client, entity);
			ReplyToCommand(client, "Rainbow hats enabled");
			return Plugin_Handled;
		}

		
		AcceptEntityInput(entity, "EnableMotion");
		SetEntProp(entity, Prop_Send, "m_CollisionGroup", hatData[client].collisionGroup);
		SetEntProp(entity, Prop_Send, "m_nSolidType", hatData[client].solidType);

		int flags = ~GetEntityFlags(entity) & FL_FROZEN;
		SetEntityFlags(entity, flags);
		int visibleEntity = EntRefToEntIndex(hatData[client].visibleEntity);
		SDKUnhook(entity, SDKHook_SetTransmit, OnRealTransmit);
		if(visibleEntity > 0) {
			SDKUnhook(visibleEntity, SDKHook_SetTransmit, OnVisibleTransmit);
			AcceptEntityInput(visibleEntity, "Kill");
			hatData[client].visibleEntity = INVALID_ENT_REFERENCE;
		}
		tempGod[client] = true;

		CreateTimer(2.0, Timer_RemoveGod, GetClientUserId(client));
		if(entity <= MaxClients) {
			tempGod[entity] = true;
			hatData[client].orgAng[2] = 0.0;
			CreateTimer(2.5, Timer_RemoveGod, GetClientUserId(entity));
			SetEntityMoveType(entity, MOVETYPE_WALK);
		} else {
			SetEntProp(entity, Prop_Send, "movetype", hatData[client].moveType);
		}

		if(arg[0] == 'y') {
			GetClientEyeAngles(client, hatData[client].orgAng);
			GetClientAbsOrigin(client, hatData[client].orgPos);
			hatData[client].orgPos[2] += 45.0;
			float ang[3], vel[3];
			
			GetClientEyeAngles(client, ang);
			ang[2] = 0.0;
			if(ang[0] > 0.0) ang[0] = -ang[0];
			// ang[0] = -45.0;

			vel[0] = Cosine(DegToRad(ang[1])) * 1500.0;
			vel[1] = Sine(DegToRad(ang[1])) * 1500.0;
			vel[2] = 700.0;
			if(entity <= MaxClients) {
				TeleportEntity(entity, hatData[client].orgPos, hatData[client].orgAng, NULL_VECTOR);
				L4D2_CTerrorPlayer_Fling(entity, client, vel);
			} /*else if(visibleEntity > 0) {
				PrintToChat(client, "Yeeting fake car...");
				ClearParent(visibleEntity);

				SetEntProp(visibleEntity, Prop_Send, "movetype", 6);

				AcceptEntityInput(visibleEntity, "EnableMotion");

				TeleportEntity(entity, OUT_OF_BOUNDS, hatData[client].orgAng, NULL_VECTOR);
				TeleportEntity(visibleEntity, hatData[client].orgPos, hatData[client].orgAng, vel);
				DataPack pack;
				CreateDataTimer(4.0, Timer_PropYeetEnd, pack);
				pack.WriteCell(hatData[client].entity);
				pack.WriteCell(hatData[client].visibleEntity);
				pack.WriteCell(hatData[client].collisionGroup);
				pack.WriteCell(hatData[client].solidType);
				pack.WriteCell(hatData[client].moveType);
				hatData[client].visibleEntity = INVALID_ENT_REFERENCE;
				hatData[client].entity = INVALID_ENT_REFERENCE;
			} */ else {
				GetHorizontalPositionFromClient(client, 80.0, hatData[client].orgPos);
				hatData[client].orgPos[2] += 35.0;
				TeleportEntity(entity, hatData[client].orgPos, hatData[client].orgAng, vel);
				CreateTimer(6.0, Timer_PropSleep, hatData[client].entity);
			}
			PrintToChat(client, "[Hats] Yeeted hat");
			hatData[client].entity = INVALID_ENT_REFERENCE;
			return Plugin_Handled;
		} else if(arg[0] == 'c') {
			if(GetCursorLocation(client, hatData[client].orgPos)) {
				GlowPoint(hatData[client].orgPos);
				TeleportEntity(entity, hatData[client].orgPos, hatData[client].orgAng, NULL_VECTOR);
				PrintToChat(client, "[Hats] Placed hat on cursor.");
			} else {
				PrintToChat(client, "[Hats] Could not find cursor position.");
			}
		} else if(arg[0] == 'p' || (entity <= MaxClients && arg[0] != 'r')) {
			if(!HasFlag(client, HAT_REVERSED)) {

				GetClientEyePosition(client, hatData[client].orgPos);
				GetClientEyeAngles(client, hatData[client].orgAng);
				GetHorizontalPositionFromOrigin(hatData[client].orgPos, hatData[client].orgAng, 80.0, hatData[client].orgPos);
				hatData[client].orgAng[0] = 0.0;
				// GlowPoint(hatData[client].orgPos, 2.0);
				float mins[3];
				GetEntPropVector(entity, Prop_Data, "m_vecMins", mins);
				// GlowPoint(hatData[client].orgPos, 3.0);
				hatData[client].orgPos[2] += mins[2]; 
				FindGround(hatData[client].orgPos, hatData[client].orgPos);
				// GlowPoint(hatData[client].orgPos);
			}

			
			/*GetGroundTopDown(client,  hatData[client].orgPos, hatData[client].orgAng);
			// GetGround(client, hatData[client].orgPos, hatData[client].orgAng);
			float mins[3];
			GetEntPropVector(entity, Prop_Data, "m_vecMins", mins);
			hatData[client].orgPos[2] -= mins[2];
			GetHorizontalPositionFromOrigin(hatData[client].orgPos, hatData[client].orgAng, 80.0, hatData[client].orgPos);*/
			TeleportEntity(entity, hatData[client].orgPos, hatData[client].orgAng, NULL_VECTOR);
			// hatData[client].orgPos[2] = mins[2];
			PrintToChat(client, "[Hats] Placed hat in front of you.");
		} else if(arg[0] == 'd') {
			WallBuilder[client].Reset();
			WallBuilder[client].entity = EntIndexToEntRef(entity);
			WallBuilder[client].canScale = false;	
			WallBuilder[client].SetMode(MOVE_ORIGIN);
			PrintToChat(client, "\x04[Walls] \x01Beta Prop Mover active for \x04%d", entity);
		} else {
			PrintToChat(client, "[Hats] Restored hat to its original position.");
		}

		if(hatData[client].scale > 0 && HasEntProp(entity, Prop_Send, "m_flModelScale"))
			SetEntPropFloat(entity, Prop_Send, "m_flModelScale", hatData[client].scale);

		AcceptEntityInput(entity, "Sleep");
		TeleportEntity(entity, hatData[client].orgPos, hatData[client].orgAng, NULL_VECTOR);
		hatData[client].entity = INVALID_ENT_REFERENCE;
	} else {
		int flags = 0;
		entity = GetLookingEntity(client, Filter_ValidHats); //GetClientAimTarget(client, false);
		if(entity <= 0) {
			PrintCenterText(client, "[Hats] No entity found");
		} else {
			if(args > 0) {
				char arg[4];
				GetCmdArg(1, arg, sizeof(arg));
				if(arg[0] == 'r') {
					flags |= view_as<int>(HAT_REVERSED);
				}
			}
			int parent = GetEntPropEnt(entity, Prop_Data, "m_hParent");
			if(parent > 0 && entity > MaxClients) {
				PrintToConsole(client, "[Hats] Selected a child entity, selecting parent (child %d -> parent %d)", entity, parent);
				entity = parent;
			} else if(entity <= MaxClients) {
				if(GetClientTeam(entity) != 2 && ~cvar_sm_hats_flags.IntValue & view_as<int>(HatConfig_InfectedHats)) {
					PrintToChat(client, "[Hats] Cannot make enemy a hat... it's dangerous");
					return Plugin_Handled;
				} else if(entity == EntRefToEntIndex(WallBuilder[client].entity)) {
					PrintToChat(client, "[Hats] You are currently editing this entity");
					return Plugin_Handled;
				} else if(inSaferoom[client] && cvar_sm_hats_flags.IntValue & view_as<int>(HatConfig_NoSaferoomHats)) {
					PrintToChat(client, "[Hats] Hats are not allowed in the saferoom");
					return Plugin_Handled;
				} else if(!IsPlayerAlive(entity) || GetEntProp(entity, Prop_Send, "m_isHangingFromLedge") || L4D_IsPlayerCapped(entity)) {
					PrintToChat(client, "[Hats] Player is either dead, hanging or in the process of dying.");
					return Plugin_Handled;
				} else if(EntRefToEntIndex(hatData[entity].entity) == client) {
					PrintToChat(client, "[Hats] Woah you can't be making a black hole, jesus be careful.");
					return Plugin_Handled;
				} else if(~cvar_sm_hats_flags.IntValue & view_as<int>(HatConfig_PlayerHats)) {
					PrintToChat(client, "[Hats] Player hats are disabled");
					return Plugin_Handled;
				} else if(!CanTarget(entity)) {
					PrintToChat(client, "[Hats] Player has disabled player hats for themselves.");
					return Plugin_Handled;
				} else if(!CanTarget(client)) {
					PrintToChat(client, "[Hats] Cannot hat a player when you have player hats turned off");
					return Plugin_Handled;
				} else if(cvar_sm_hats_flags.IntValue & view_as<int>(HatConfig_RespectAdminImmunity)) {
					AdminId targetAdmin = GetUserAdmin(entity);
					AdminId clientAdmin = GetUserAdmin(client);
					if(targetAdmin != INVALID_ADMIN_ID && clientAdmin == INVALID_ADMIN_ID) {
						PrintToChat(client, "[Hats] Cannot target an admin");
						return Plugin_Handled;
					} else if(targetAdmin != INVALID_ADMIN_ID && targetAdmin.ImmunityLevel > clientAdmin.ImmunityLevel) {
						PrintToChat(client, "[Hats] Cannot target %N, they are immune to you", entity);
						return Plugin_Handled;
					}
				}
				if(!IsFakeClient(entity) && cvar_sm_hats_flags.IntValue & view_as<int>(HatConfig_PlayerHatConsent) && ~flags & view_as<int>(HAT_REVERSED)) {
					int lastRequestDiff = GetTime() - lastHatRequestTime[client];
					if(lastRequestDiff < PLAYER_HAT_REQUEST_COOLDOWN) {
						PrintToChat(client, "[Hats] Player hat under %d seconds cooldown", lastRequestDiff);
						return Plugin_Handled;
					}

					Menu menu = new Menu(HatConsentHandler);
					menu.SetTitle("%N: Requests to hat you", client);
					char id[8];
					Format(id, sizeof(id), "%d|1", GetClientUserId(client));
					menu.AddItem(id, "Accept");
					Format(id, sizeof(id), "%d|0", GetClientUserId(client));
					menu.AddItem(id, "Reject");
					menu.Display(entity, 12);
					PrintHintText(client, "Sent hat request to %N", entity);
					PrintToChat(entity, "[Hats] %N requests to hat you, 1 to Accept, 2 to Reject. Expires in 12 seconds.", client);
					return Plugin_Handled;
				}
			}


			char classname[64];
			GetEntityClassname(entity, classname, sizeof(classname));
			if(cvar_sm_hats_blacklist_enabled.BoolValue) {
				for(int i = 0; i < MAX_FORBIDDEN_CLASSNAMES; i++) {
					if(StrEqual(FORBIDDEN_CLASSNAMES[i], classname)) {
						PrintToChat(client, "[Hats] Entity (%s) is a blacklisted entity. Naughty.", classname);
						return Plugin_Handled;
					}
				}
			}

			if(~flags & view_as<int>(HAT_REVERSED)) {
				for(int i = 0; i < MAX_REVERSE_CLASSNAMES; i++) {
					if(StrEqual(REVERSE_CLASSNAMES[i], classname)) {
						flags |= view_as<int>(HAT_REVERSED);
						break;
					}
				}
			}
			EquipHat(client, entity, classname, flags);
		}
	}
	return Plugin_Handled;
}

public Action Command_MakeWall(int client, int args) {
	if(WallBuilder[client].IsActive()) {
		if(args == 1) {
			char arg1[16];
			GetCmdArg(1, arg1, sizeof(arg1));
			if(StrEqual(arg1, "build", false)) {
				int flags = GetEntityFlags(client) & ~FL_FROZEN;
				SetEntityFlags(client, flags);
				int id = WallBuilder[client].Build();
				if(id == -1) {
					PrintToChat(client, "\x04[Walls]\x01 Wall Creation: \x04Error\x01");
				} else if(id == -2) {
					PrintToChat(client, "\x04[Walls]\x01 Wall Edit: \x04Complete\x01");
				} else if(id == -3) {
					PrintToChat(client, "\x04[Walls]\x01 Entity Edit: \x04Complete\x01");
				} else {
					PrintToChat(client, "\x04[Walls]\x01 Wall Creation: \x05Wall #%d Created\x01", id + 1);
				}
				return Plugin_Handled;
			} else if(StrEqual(arg1, "export")) {
				PrintToChat(client, "{");
				PrintToChat(client, "\t\"origin\" \"%.2f %.2f %.2f\"", WallBuilder[client].origin[0], WallBuilder[client].origin[1], WallBuilder[client].origin[2]);
				PrintToChat(client, "\t\"angles\" \"%.2f %.2f %.2f\"", WallBuilder[client].angles[0], WallBuilder[client].angles[1], WallBuilder[client].angles[2]);
				PrintToChat(client, "\t\"size\" \"%.2f %.2f %.2f\"", WallBuilder[client].size[0], WallBuilder[client].size[1], WallBuilder[client].size[2]);
				PrintToChat(client, "}");
			} else if(StrEqual(arg1, "cancel")) {
				int flags = GetEntityFlags(client) & ~FL_FROZEN;
				SetEntityFlags(client, flags);
				WallBuilder[client].SetMode(INACTIVE);
				PrintToChat(client, "\x04[Walls]\x01 Wall Creation: \x04Cancelled\x01");
			}
		} else {
			ReplyToCommand(client, "\x04[Walls]\x01 Unknown option, try \x05/mkwall build\x01 to finish or \x04/mkwall cancel\x01 to cancel");
		}

	} else {
		WallBuilder[client].Reset();
		if(args > 0) {
			// TODO: Determine axis
			
			char arg2[8];
			for(int i = 0; i < 3; i++) {
				GetCmdArg(i + 1, arg2, sizeof(arg2));
				float value;
				if(StringToFloatEx(arg2, value) == 0) {
					value = 1.0;
				}
				WallBuilder[client].size[i] = value;
			}

			float rot[3];
			GetClientEyeAngles(client, rot);
			if(rot[2] > 45 && rot[2] < 135 || rot[2] > -135 && rot[2] < -45) {
				float temp = WallBuilder[client].size[0];
				WallBuilder[client].size[0] = WallBuilder[client].size[1];
				WallBuilder[client].size[1] = temp;
			}
			
			WallBuilder[client].CalculateMins();
		}
		WallBuilder[client].SetMode(SCALE);
		GetCursorLimited(client, 100.0, WallBuilder[client].origin, Filter_IgnorePlayer);
		PrintToChat(client, "\x04[Walls]\x01 New Wall Started. End with \x05/mkwall build\x01 or \x04/mkwall cancel\x01");
		PrintToChat(client, "\x04[Walls]\x01 Mode: \x05Scale\x01");
	}
	return Plugin_Handled;
}

public Action Command_ManageWalls(int client, int args) {
	if(args == 0) {
		PrintToChat(client, "\x04[Walls]\x01 Created Walls: \x05%d\x01", createdWalls.Length);
		for(int i = 1; i <= createdWalls.Length; i++) {
			GlowWall(i, 20.0);
		}
		return Plugin_Handled;
	}
	char arg1[16], arg2[16];
	GetCmdArg(1, arg1, sizeof(arg1));
	GetCmdArg(2, arg2, sizeof(arg2));
	if(StrEqual(arg1, "delete")) {
		if(StrEqual(arg2, "all")) {
			int walls = createdWalls.Length;
			for(int i = 1; i <= createdWalls.Length; i++) {
				DeleteWall(i);
			}
			PrintToChat(client, "\x04[Walls]\x01 Deleted \x05%d\x01 Walls", walls);
		} else {
			int id = GetWallId(client, arg2);
			if(id > -1) {
				DeleteWall(id);
				PrintToChat(client, "\x04[Walls]\x01 Deleted Wall: \x05#%d\x01", id);
			}
		}
	} else if(StrEqual(arg1, "create")) {
		ReplyToCommand(client, "\x04[Walls]\x01 Syntax: /mkwall [size x] [size y] [size z]");
	} else if(StrEqual(arg1, "toggle")) {
		if(StrEqual(arg2, "all")) {
			int walls = createdWalls.Length;
			for(int i = 1; i <= createdWalls.Length; i++) {
				int entity = GetWallEntity(i);
				AcceptEntityInput(entity, "Toggle");
				GlowWall(i);
			}
			PrintToChat(client, "\x04[Walls]\x01 Toggled \x05%d\x01 walls", walls);
		} else {
			int id = GetWallId(client, arg2);
			if(id > -1) {
				int entity = GetWallEntity(id);
				AcceptEntityInput(entity, "Toggle");
				GlowWall(id);
				PrintToChat(client, "\x04[Walls]\x01 Toggled Wall: \x05#%d\x01", id);
			}
		}
	} else if(StrEqual(arg1, "filter")) {
		if(args < 3) {
			ReplyToCommand(client, "\x04[Walls]\x01 Syntax: \x05/walls filter <id/all> <filter type>\x04");
			ReplyToCommand(client, "\x04[Walls]\x01 Valid filters: \x05player");
			return Plugin_Handled;
		}

		char arg3[32];
		GetCmdArg(3, arg3, sizeof(arg3));

		SetVariantString(arg3);
		if(StrEqual(arg2, "all")) {
			int walls = createdWalls.Length;
			for(int i = 1; i <= createdWalls.Length; i++) {
				int entity = GetWallEntity(i);
				AcceptEntityInput(entity, "SetExcluded");
			}
			PrintToChat(client, "\x04[Walls]\x01 Set %d walls' filter to \x05%s\x01", walls, arg3);
		} else {
			int id = GetWallId(client, arg2);
			if(id > -1) {
				int entity = GetWallEntity(id);
				AcceptEntityInput(entity, "SetExcluded");
				PrintToChat(client, "\x04[Walls]\x01 Set wall #%d filter to \x05%s\x01", id, arg3);
			}
		}
	} else if(StrEqual(arg1, "edit")) {
		int id = GetWallId(client, arg2);
		if(id > -1) {
			int entity = GetWallEntity(id);
			WallBuilder[client].Import(entity);
			PrintToChat(client, "\x04[Walls]\x01 Editing wall \x05%d\x01. End with \x05/mkwall build\x01 or \x04/mkwall cancel\x01", id);
			PrintToChat(client, "\x04[Walls]\x01 Mode: \x05Scale\x01");
		}
	} else if(StrEqual(arg1, "edite")) {
		int index = StringToInt(arg2);
		if(index > 0 && IsValidEntity(index)) {
			WallBuilder[client].Reset();
			WallBuilder[client].entity = EntIndexToEntRef(index);
			WallBuilder[client].canScale = false;	
			WallBuilder[client].SetMode(MOVE_ORIGIN);
			PrintToChat(client, "\x04[Walls]\x01 Editing wall \x05%d\x01. End with \x05/mkwall build\x01 or \x04/mkwall cancel\x01", index);
			PrintToChat(client, "\x04[Walls]\x01 Mode: \x05Move & Rotate\x01");
		} else {
			ReplyToCommand(client, "\x04[Walls]\x01 Invalid or non existent entity");
		}
	} else if(StrEqual(arg1, "copy")) {
		int id = GetWallId(client, arg2);
		if(id > -1) {
			int entity = GetWallEntity(id);
			WallBuilder[client].Import(entity, true);
			GetCursorLimited(client, 100.0, WallBuilder[client].origin, Filter_IgnorePlayer);
			PrintToChat(client, "\x04[Walls]\x01 Editing copy of wall \x05%d\x01. End with \x05/mkwall build\x01 or \x04/mkwall cancel\x01", id);
			PrintToChat(client, "\x04[Walls]\x01 Mode: \x05Scale\x01");
		}
	} else if(StrEqual(arg1, "list")) {
		for(int i = 1; i <= createdWalls.Length; i++) {
			int entity = GetWallEntity(i);
			ReplyToCommand(client, "Wall #%d - EntIndex: %d", i, EntRefToEntIndex(entity));
		}
	}
	return Plugin_Handled;
}

int GetWallId(int client, const char[] arg) {
	int id;
	if(StringToIntEx(arg, id) > 0 && id > 0 && id <= createdWalls.Length) {
		int entity = GetWallEntity(id);
		if(!IsValidEntity(entity)) {
			ReplyToCommand(client, "\x04[Walls]\x01 The wall with specified id no longer exists.");
			createdWalls.Erase(id);
			return -2;
		}
		return id;
	} else {
		ReplyToCommand(client, "\x04[Walls]\x01 Invalid wall id, must be between 0 - %d", createdWalls.Length - 1 );
		return -1;
	}
}

int GetWallEntity(int id) {
	if(id <= 0 || id > createdWalls.Length) {
		ThrowError("Invalid wall id (%d)", id);
	}
	return createdWalls.Get(id - 1);
}

public int HatConsentHandler(Menu menu, MenuAction action, int target, int param2) {
	if (action == MenuAction_Select) {
		static char info[8];
		menu.GetItem(param2, info, sizeof(info));
		static char str[2][8];
		ExplodeString(info, "|", str, 2, 8, false);
		int activator = GetClientOfUserId(StringToInt(str[0]));
		int hatAction = StringToInt(str[1]);
		if(activator == 0) {
			ReplyToCommand(target, "Player has gone idle or left");
			return 0;
		} else if(hatAction == 1) {
			EquipHat(activator, target, "player", 0);
		} else {
			ClientCommand(activator, "play player/orch_hit_csharp_short.wav");
			PrintHintText(activator, "%N refused your request", target);
			lastHatRequestTime[activator] = GetTime();
		}
	} else if (action == MenuAction_End)	
		delete menu;
	return 0;
}

///////////////////////////////////////////////////////////////////////////////////////////////

public void Event_ItemPickup(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	for(int slot = 0; slot <= 5; slot++) {
		int wpn = GetPlayerWeaponSlot(client, slot);
		for(int i = 1; i <= MaxClients; i++) {
			if(i != client && IsClientConnected(i) && IsClientInGame(i) && !IsFakeClient(i)) {
				int hat = GetHat(i);
				if(hat == wpn) {
				
					break;
				}
			}
		}
	}
}


// TODO: Possibly detect instead the hat itself entering saferoom
public void OnEnterSaferoom(Event event, const char[] name, bool dontBroadcast) {
	int userid = event.GetInt("userid");
	int client = GetClientOfUserId(userid);
	if(client > 0 && client <= MaxClients && IsValidClient(client) && GetClientTeam(client) == 2) {
		inSaferoom[client] = true;
		if(cvar_sm_hats_flags.IntValue & view_as<int>(HatConfig_NoSaferoomHats)) {
			if(HasHat(client)) {
				if(!IsHatAllowed(client)) {
					PrintToChat(client, "[Hats] Hat is not allowed in the saferoom and has been returned");
					ClearHat(client, true);
				} else {
					CreateTimer(2.0, Timer_PlaceHat, userid);
					// float maxflow = L4D2Direct_GetMapMaxFlowDistance()
					// L4D_GetNavArea_SpawnAttributes
					// L4D_GetNavAreaPos
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

public void EntityOutput_OnStartTouchSaferoom(const char[] output, int caller, int client, float time) {
	if(cvar_sm_hats_flags.IntValue & view_as<int>(HatConfig_NoSaferoomHats) && client > 0 && client <= MaxClients && IsValidClient(client) && GetClientTeam(client) == 2) {
		if(HasHat(client)) {
			if(!IsHatAllowed(client)) {
				PrintToChat(client, "[Hats] Hat is not allowed in the saferoom and has been returned");
				ClearHat(client, true);
			} else {
				CreateTimer(2.0, Timer_PlaceHat, GetClientUserId(client));
				// float maxflow = L4D2Direct_GetMapMaxFlowDistance()
				// L4D_GetNavArea_SpawnAttributes
				// L4D_GetNavAreaPos
			}
		}
	}
}

Action Timer_PlaceHat(Handle h, int userid) {
	int client = GetClientOfUserId(userid);
	if(client > 0 && HasHat(client)) {
		GetClientEyePosition(client, hatData[client].orgPos);
		GetClientEyeAngles(client, hatData[client].orgAng);
		GetHorizontalPositionFromOrigin(hatData[client].orgPos, hatData[client].orgAng, 80.0, hatData[client].orgPos);
		hatData[client].orgAng[0] = 0.0;
		PrintToChat(client, "[Hats] Hat has been placed down");
		ClearHat(client, true);
	}
	return Plugin_Handled;
}
void GlowPoint(const float pos[3], float lifetime = 5.0) {
	#if defined DEBUG_GLOW
	PrecacheModel("models/props_fortifications/orange_cone001_reference.mdl");
	int entity = CreateEntityByName("prop_dynamic");
	DispatchKeyValue(entity, "disableshadows", "1");
	DispatchKeyValue(entity, "model", "models/props_fortifications/orange_cone001_reference.mdl");
	TeleportEntity(entity, pos, NULL_VECTOR, NULL_VECTOR);
	DispatchSpawn(entity);
	CreateTimer(lifetime, Timer_Kill, entity);
	#endif
}

Action Timer_Kill(Handle h, int entity) {
	if(IsValidEntity(entity))
		AcceptEntityInput(entity, "Kill");
	return Plugin_Handled;
}

stock bool GetCursorLocation(int client, float outPos[3]) {
	float start[3], angle[3], ceilPos[3], wallPos[3], normal[3];
	GetClientEyePosition(client, start);
	GetClientEyeAngles(client, angle);
	TR_TraceRayFilter(start, angle, MASK_SOLID, RayType_Infinite, Filter_NoPlayers, client);
	if(TR_DidHit()) {
		TR_GetEndPosition(outPos);
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
			float distCeil = GetVectorDistance(outPos, ceilPos, true);
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
				AcceptEntityInput(visibleEntity, "Kill");
				hatData[i].visibleEntity = INVALID_ENT_REFERENCE;
			}
		}
	}
	return Plugin_Handled;
}

void Frame_Remount(int i) {
	int entity = GetHat(i);
	if(entity == -1) return;
	SetParent(entity, i);
	SetParentAttachment(entity, "eyes", false);
	SetParentAttachment(entity, "eyes", true);
	
	int visibleEntity = EntRefToEntIndex(hatData[i].visibleEntity);
	if(visibleEntity > 0) {
		SetParent(visibleEntity, i);
		SetParentAttachment(visibleEntity, "eyes", false);
		SetParentAttachment(visibleEntity, "eyes", true);
	}
}

// TODO: toggle highlight
// pick a diff model
Action Timer_PropSleep(Handle h, int ref) {
	if(IsValidEntity(ref)) {
		if(cvar_sm_hats_flags.IntValue & view_as<int>(HatConfig_DeleteThrownHats)) {
			// Don't delete if someone has hatted it (including ourself):
			for(int i = 1; i <= MaxClients; i++) {
				if(IsClientConnected(i) && IsClientInGame(i) && hatData[i].entity == ref) {
					return Plugin_Handled;
				}
			}
			char classname[64];
			GetEntityClassname(ref, classname, sizeof(classname));
			if(StrContains(classname, "prop_") > -1) {
 				AcceptEntityInput(ref, "Kill");
				return Plugin_Handled;
			}
		}
		AcceptEntityInput(ref, "Sleep");
	}
	return Plugin_Handled;
}

Action Timer_PropYeetEnd(Handle h, DataPack pack) {
	pack.Reset();
	int realEnt = EntRefToEntIndex(pack.ReadCell());
	int visibleEnt = EntRefToEntIndex(pack.ReadCell());
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


public void Event_PlayerOutOfIdle(Event event, const char[] name, bool dontBroadcast) {
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

public Action OnPlayerRunCmd(int client, int& buttons, int& impulse, float vel[3], float angles[3], int& weapon, int& subtype, int& cmdnum, int& tickcount, int& seed, int mouse[2]) {
	float tick = GetGameTime();
	if(cvar_sm_hats_enabled.IntValue == 0 || (GetUserAdmin(client) == INVALID_ADMIN_ID && cvar_sm_hats_enabled.IntValue == 1)) return Plugin_Continue;
	int entity = GetHat(client);
	int visibleEntity = EntRefToEntIndex(hatData[client].visibleEntity);
	///#HAT PROCESS
	if(entity > 0) {
		// try to tp hat to its own pos
		if(!onLadder[client] && GetEntityMoveType(client) == MOVETYPE_LADDER) {
			onLadder[client] = true;
			ClearParent(entity);
			// Hide hat temporarily in void:
			TeleportEntity(entity, EMPTY_ANG, NULL_VECTOR, NULL_VECTOR);
			if(visibleEntity > 0) {
				hatData[client].visibleEntity = INVALID_ENT_REFERENCE;
				AcceptEntityInput(visibleEntity, "Kill");
			}
		} else if(onLadder[client] && GetEntityMoveType(client) != MOVETYPE_LADDER) {
			onLadder[client] = false;
			EquipHat(client, entity);
		}

		if(HasFlag(client, HAT_RAINBOW)) {
			// Decrement and flip, possibly when rainbowticks
			if(hatData[client].rainbowReverse) {
				hatData[client].rainbowColor[0] -= cvar_sm_hat_rainbow_speed.FloatValue;
			} else {
				hatData[client].rainbowColor[0] += cvar_sm_hat_rainbow_speed.FloatValue;
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
			hatData[client].rainbowTicks = -cvar_sm_hat_rainbow_speed.IntValue;
			EquipHat(client, entity);
		}

		if(entity <= MaxClients) {
			if(!onLadder[entity] && GetEntityMoveType(entity) == MOVETYPE_LADDER) {
				onLadder[entity] = true;
				ClearParent(entity);
			} else if(onLadder[entity] && GetEntityMoveType(entity) != MOVETYPE_LADDER) {
				onLadder[entity] = false;
				EquipHat(client, entity);
			}
		}
		if(HasFlag(client, HAT_COMMANDABLE | HAT_REVERSED) && tickcount % 200 == 0) {
			float pos[3];
			ChooseRandomPosition(pos, client);
			L4D2_CommandABot(entity, client, BOT_CMD_MOVE, pos);
		}
	} 
	if(buttons & IN_USE && buttons & IN_RELOAD) {
		if(entity > 0) {
			if(buttons & IN_ZOOM) {
				if(buttons & IN_JUMP) hatData[client].offset[2] += 1.0;
				if(buttons & IN_DUCK) hatData[client].offset[2] -= 1.0;
				if(buttons & IN_FORWARD) hatData[client].offset[0] += 1.0;
				if(buttons & IN_BACK) hatData[client].offset[0] -= 1.0;
				if(buttons & IN_MOVELEFT) hatData[client].offset[1] += 1.0;
				if(buttons & IN_MOVERIGHT) hatData[client].offset[1] -= 1.0;
				TeleportEntity(entity, hatData[client].offset, angles, vel);
				return Plugin_Handled;
			} else if(tick - cmdThrottle[client] > 0.25) {
				if(buttons & IN_ATTACK) {
					ClientCommand(client, "sm_hat %s", 'y');
				} else if(buttons & IN_DUCK) {
					ClientCommand(client, "sm_hat %s", 'p');
				}
			}
		} else if(tick - cmdThrottle[client] > 0.25 && L4D2_GetPlayerUseAction(client) == L4D2UseAction_None) {
			ClientCommand(client, "sm_hat");
		}
		cmdThrottle[client] = tick;
		lastAng[client] = angles;
		hatData[client].angles = angles;
		return Plugin_Handled;
	}

	///#WALL BUILDER PROCESS
	if(WallBuilder[client].IsActive()) { 
		bool allowMove = true;
		switch(WallBuilder[client].mode) {
			case MOVE_ORIGIN: {
				SetWeaponDelay(client, 0.5);
				// switch(buttons) {
				// 	case IN_: WallBuilder[client].CycleSpeed(client, tick);
				// }

				if(WallBuilder[client].movetype == 0) {
					bool isRotate;
					int flags = GetEntityFlags(client);
					if(buttons & IN_USE) {
						PrintCenterText(client, "%d %d", mouse[0], mouse[1]);
						isRotate = true;
						SetEntityFlags(client, flags |= FL_FROZEN);
						if(buttons & IN_ATTACK) WallBuilder[client].CycleAxis(client, tick);
						else if(buttons & IN_ATTACK2) WallBuilder[client].CycleSnapAngle(client, tick);
						
						if(tick - cmdThrottle[client] > 0.25) {
							if(WallBuilder[client].axis == 0) {
								if(mouse[1] > 10) WallBuilder[client].angles[0] += WallBuilder[client].snapAngle;
								else if(mouse[1] < -10) WallBuilder[client].angles[0] -= WallBuilder[client].snapAngle;
							} else if(WallBuilder[client].axis == 1) {
								if(mouse[0] > 10) WallBuilder[client].angles[1] += WallBuilder[client].snapAngle;
								else if(mouse[0] < -10) WallBuilder[client].angles[1] -= WallBuilder[client].snapAngle;
							}
							cmdThrottle[client] = tick;
						}
						
					} else {
						switch(buttons) {
							case IN_ATTACK: WallBuilder[client].moveDistance++;
							case IN_ATTACK2: WallBuilder[client].moveDistance--;
							case IN_WALK: WallBuilder[client].CycleMoveMode(client, tick);
						}
					}
					if(!isRotate && flags & FL_FROZEN) {
						flags = ~flags & FL_FROZEN;
						SetEntityFlags(client, flags);
					}
					GetCursorLimited(client, WallBuilder[client].moveDistance, WallBuilder[client].origin, Filter_IgnorePlayerAndWall);
					// GetCursorLocationLimited(client, WallBuilder[client].moveDistance, WallBuilder[client].origin);
				} else if(WallBuilder[client].movetype == 1) {
					switch(buttons) {
						case IN_FORWARD: WallBuilder[client].origin[0] += WallBuilder[client].moveSpeed;
						case IN_BACK: WallBuilder[client].origin[0] -= WallBuilder[client].moveSpeed; 
						case IN_MOVELEFT: WallBuilder[client].origin[1] += WallBuilder[client].moveSpeed;
						case IN_MOVERIGHT: WallBuilder[client].origin[1] -= WallBuilder[client].moveSpeed; 
						case IN_JUMP: WallBuilder[client].origin[2] += WallBuilder[client].moveSpeed;
						case IN_DUCK: WallBuilder[client].origin[2] -= WallBuilder[client].moveSpeed; 
					}
					allowMove = false;
				} else {
					GetCursorLocation(client, WallBuilder[client].origin);
				}
			}
			case SCALE: {
				SetWeaponDelay(client, 0.5);
				allowMove = false;
				bool sizeChanged = false;
				switch(buttons) {
					case IN_MOVELEFT: {
						WallBuilder[client].size[0] -=WallBuilder[client].moveSpeed; 
						if(WallBuilder[client].size[0] <= 0.0) WallBuilder[client].size[0] = 0.0;
						sizeChanged = true;
					} case IN_MOVERIGHT: {
						WallBuilder[client].size[0] += WallBuilder[client].moveSpeed;
						sizeChanged = true;
					} case IN_FORWARD: {
						WallBuilder[client].size[1]+= WallBuilder[client].moveSpeed;
						sizeChanged = true;
					} case IN_BACK: {
						WallBuilder[client].size[1] -= WallBuilder[client].moveSpeed;
						if(WallBuilder[client].size[1] <= 0.0) WallBuilder[client].size[1] = 0.0;
						sizeChanged = true;
					} case IN_JUMP: {
						WallBuilder[client].size[2] += WallBuilder[client].moveSpeed;
						sizeChanged = true;
					} case IN_DUCK: { 
						if(WallBuilder[client].size[2] <= 0.0) WallBuilder[client].size[2] = 0.0;
						WallBuilder[client].size[2] -= WallBuilder[client].moveSpeed;
						sizeChanged = true;
					}
					case IN_USE: WallBuilder[client].CycleSpeed(client, tick);
				}
				if(sizeChanged) {
					WallBuilder[client].CalculateMins();
				}
			}
		}

		switch(buttons) {
			case IN_RELOAD: WallBuilder[client].CycleMode(client, tick); // R: Cycle forward
		}

		WallBuilder[client].Draw(BUILDER_COLOR, 0.1, 0.1);

		return allowMove ? Plugin_Continue : Plugin_Handled;
	}
	return Plugin_Continue;
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

public void OnClientDisconnect(int client) {
	tempGod[client] = false;
	WallBuilder[client].Reset();
}

public void OnEntityDestroyed(int entity) {
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && !IsFakeClient(i)) {
			if(EntRefToEntIndex(hatData[i].entity) == entity) {
				ClearHat(i);
				PrintHintText(i, "Hat entity has vanished");
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
	NavAreas = GetSpawnLocations();

	HookEntityOutput("info_changelevel", "OnStartTouch", EntityOutput_OnStartTouchSaferoom);
	HookEntityOutput("trigger_changelevel", "OnStartTouch", EntityOutput_OnStartTouchSaferoom);
}

public void OnMapEnd() {
	delete NavAreas;
	for(int i = 1; i <= createdWalls.Length; i++) {
		DeleteWall(i);
	}
	createdWalls.Clear();
	ClearHats();
}
public void OnPluginEnd() {
	ClearHats();
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i)) {
			int flags = GetEntityFlags(i) & ~FL_FROZEN;
			SetEntityFlags(i, flags);
		}
	}
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
	TR_TraceRayFilter(pos, ang, MASK_SHOT, RayType_Infinite, filter, client);
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
	return entity > 0 && entity != data && EntRefToEntIndex(WallBuilder[data].entity) != entity;
}

bool Filter_IgnorePlayer(int entity, int mask, int data) {
	return entity > 0 && entity != data;
}
bool Filter_ValidHats(int entity, int mask, int data) {
	if(entity == data) return false;
	if(entity <= MaxClients) {
		int client = GetRealClient(data);
		return CanTarget(client); // Don't target if player targetting off
	}
	if(cvar_sm_hats_blacklist_enabled.BoolValue) {
		static char classname[32];
		GetEntityClassname(entity, classname, sizeof(classname));
		for(int i = 0; i < MAX_FORBIDDEN_CLASSNAMES; i++) {
			if(StrEqual(FORBIDDEN_CLASSNAMES[i], classname)) {
				return false;
			}
		}
	}
	return true;
}

////////////////////////////////

void ClearHats() {
	for(int i = 1; i <= MaxClients; i++) {
		if(HasHat(i)) {
			ClearHat(i, false);
		}
		if(IsClientConnected(i) && IsClientInGame(i)) SetEntityMoveType(i, MOVETYPE_WALK);
	}
}
void ClearHat(int i, bool restore = false) {

	int entity = EntRefToEntIndex(hatData[i].entity);
	int visibleEntity = EntRefToEntIndex(hatData[i].visibleEntity);
	int modifyEntity = HasFlag(i, HAT_REVERSED) ? i : entity;
	
	if(visibleEntity > 0) {
		SDKUnhook(visibleEntity, SDKHook_SetTransmit, OnVisibleTransmit);
		AcceptEntityInput(visibleEntity, "Kill");
	}
	if(modifyEntity > 0) {
		SDKUnhook(modifyEntity, SDKHook_SetTransmit, OnRealTransmit);
		ClearParent(modifyEntity);
	} else {
		return;
	}
	
	int flags = ~GetEntityFlags(entity) & FL_FROZEN;
	SetEntityFlags(entity, flags);
	// if(HasEntProp(entity, Prop_Send, "m_flModelScale"))
		// SetEntPropFloat(entity, Prop_Send, "m_flModelScale", 1.0);
	SetEntProp(modifyEntity, Prop_Send, "m_CollisionGroup", hatData[i].collisionGroup);
	SetEntProp(modifyEntity, Prop_Send, "m_nSolidType", hatData[i].solidType);
	SetEntProp(modifyEntity, Prop_Send, "movetype", hatData[i].moveType);

	hatData[i].entity = INVALID_ENT_REFERENCE;
	hatData[i].visibleEntity = INVALID_ENT_REFERENCE;

	if(HasFlag(i, HAT_REVERSED)) {
		entity = i;
		i = modifyEntity;
	}

	if(entity <= MAXPLAYERS) {
		AcceptEntityInput(entity, "EnableLedgeHang");
	}
	if(restore) {
		// If hat is a player, override original position to hat wearer's
		if(entity <= MAXPLAYERS && HasEntProp(i, Prop_Send, "m_vecOrigin")) {
			GetEntPropVector(i, Prop_Send, "m_vecOrigin", hatData[i].orgPos);
		}
		// Restore to original position
		if(HasFlag(i, HAT_REVERSED)) {
			TeleportEntity(i, hatData[i].orgPos, hatData[i].orgAng, NULL_VECTOR);
		} else {
			TeleportEntity(entity, hatData[i].orgPos, hatData[i].orgAng, NULL_VECTOR);
		}
	}
}

bool HasHat(int client) {
	return GetHat(client) > 0;
}

int GetHat(int client) {
	if(hatData[client].entity == INVALID_ENT_REFERENCE) return -1;
	int index = EntRefToEntIndex(hatData[client].entity);
	if(index <= 0) return -1;
	if(!IsValidEntity(index)) return -1;
	return index; 
}

int GetHatter(int client) {
	int myRef = EntIndexToEntRef(client);
	for(int i = 1; i <= MaxClients; i++) {
		if(hatData[client].entity == myRef) {
			return i;
		}
	}
	return -1;
}

bool CanTarget(int victim) {
	static char buf[2];
	noHatVictimCookie.Get(victim, buf, sizeof(buf));
	return StringToInt(buf) == 0;
}

bool IsHatAllowed(int client) {
	char name[32];
	GetEntityClassname(hatData[client].entity, name, sizeof(name));
	// Don't allow non-weapons in saferoom
	if(StrEqual(name, "prop_physics")) {
		GetEntPropString(hatData[client].entity, Prop_Data, "m_ModelName", name, sizeof(name));
		if(StrContains(name, "gnome") != -1) {
			return true;
		}
		PrintToConsole(client, "Dropping hat: prop_physics (%s)", name);
		return false;
	}
	else if(StrEqual(name, "player") || StrContains(name, "weapon_") > -1 || StrContains(name, "upgrade_") > -1) {
		return true;
	}
	PrintToConsole(client, "Dropping hat: %s", name);
	return false;
}


void SetFlag(int client, hatFlags flag) {
	hatData[client].flags |= view_as<int>(flag);
}

bool HasFlag(int client, hatFlags flag) {
	return hatData[client].flags & view_as<int>(flag) != 0;
}

void EquipHat(int client, int entity, const char[] classname = "", int flags = HAT_NONE) {
	if(HasHat(client))
		ClearHat(client, true);

	// Player specific tweaks
	int visibleEntity;
	if(entity == 0) {
		ThrowError("Attempted to equip world (client = %d)", client);
		return;
	}

	hatData[client].entity = EntIndexToEntRef(entity);
	int modifyEntity = HasFlag(client, HAT_REVERSED) ? client : entity;
	hatData[client].collisionGroup = GetEntProp(modifyEntity, Prop_Send, "m_CollisionGroup");
	hatData[client].solidType = GetEntProp(modifyEntity, Prop_Send, "m_nSolidType");
	hatData[client].moveType = GetEntProp(modifyEntity, Prop_Send, "movetype");

	
	if(modifyEntity <= MaxClients) {
		SDKHook(modifyEntity, SDKHook_OnTakeDamageAlive, OnTakeDamageAlive);
		AcceptEntityInput(modifyEntity, "DisableLedgeHang");
	} else if(cvar_sm_hats_flags.IntValue & view_as<int>(HatConfig_FakeHat)) {
		return;
		// char model[64];
		// GetEntPropString(entity, Prop_Data, "m_ModelName", model, sizeof(model));
		// visibleEntity = CreateEntityByName("prop_dynamic");
		// DispatchKeyValue(visibleEntity, "model", model);
		// DispatchKeyValue(visibleEntity, "disableshadows", "1");
		// DispatchSpawn(visibleEntity);
		// SetEntProp(visibleEntity, Prop_Send, "m_CollisionGroup", 1);
		// hatData[client].visibleEntity = EntIndexToEntRef(visibleEntity);
		// SDKHook(visibleEntity, SDKHook_SetTransmit, OnVisibleTransmit);
		// SDKHook(entity, SDKHook_SetTransmit, OnRealTransmit);
	}
	SDKHook(client, SDKHook_OnTakeDamageAlive, OnTakeDamageAlive);
	// Temp remove the hat to be yoinked by another player
	for(int i = 1; i <= MaxClients; i++) {
		if(i != client && EntRefToEntIndex(hatData[i].entity) == entity) {
			ClearHat(i);
		}
	}

	// Called on initial hat
	if(classname[0] != '\0') {
		if(entity <= MaxClients && !IsFakeClient(entity)) {
			PrintToChat(entity, "[Hats] %N has hatted you, type /hat to dismount at any time", client);
		}
		
		// Reset things:
		hatData[client].flags = 0;
		hatData[client].offset[0] = hatData[client].offset[1] = hatData[client].offset[2] = 0.0;
		hatData[client].angles[0] = hatData[client].angles[1] = hatData[client].angles[2] = 0.0;

		if(modifyEntity <= MaxClients) {
			if(HasFlag(client, HAT_REVERSED)) {
				hatData[client].offset[2] += 7.2;
			} else {
				hatData[client].offset[2] += 4.2;
			}
		} else {
			float mins[3];
			GetEntPropVector(modifyEntity, Prop_Send, "m_vecMins", mins);
			hatData[client].offset[2] += mins[2];
		}

		if(cvar_sm_hats_flags.IntValue & view_as<int>(HatConfig_ReversedHats) && flags & view_as<int>(HAT_REVERSED)) {
			SetFlag(client, HAT_REVERSED);
			if(StrEqual(classname, "infected") || (entity <= MaxClients && IsFakeClient(entity))) {
				SetFlag(client, HAT_COMMANDABLE);
			}
			PrintToChat(client, "[Hats] Set yourself as %s (%d)'s hat", classname, entity);
			if(entity <= MaxClients) {
				LogAction(client, entity, "\"%L\" made themselves \"%L\" (%s)'s hat (%d, %d)", client, entity, classname, entity, visibleEntity);
				PrintToChat(entity, "[Hats] %N has set themselves as your hat", client);
			}
		} else {
			if(StrEqual(classname, "infected")) {
				int eflags = GetEntityFlags(entity) | FL_FROZEN;
				SetEntityFlags(entity, eflags);
				hatData[client].offset[2] = 36.0;
			}
			if(entity <= MaxClients)
				PrintToChat(client, "[Hats] Set %N (%d) as a hat", entity, entity);
			else
				PrintToChat(client, "[Hats] Set %s (%d) as a hat", classname, entity);
			if(entity <= MaxClients)
				LogAction(client, entity, "\"%L\" picked up \"%L\" (%s) as a hat (%d, %d)", client, entity, classname, entity, visibleEntity);
			else
				LogAction(client, -1, "\"%L\" picked up %s as a hat (%d, %d)", client, classname, entity, visibleEntity);
		}
		hatData[client].scale = -1.0;

	}
	AcceptEntityInput(modifyEntity, "DisableMotion");

	// Get the data (position, angle, movement shit)

	GetEntPropVector(modifyEntity, Prop_Send, "m_vecOrigin", hatData[client].orgPos);
	GetEntPropVector(modifyEntity, Prop_Send, "m_angRotation", hatData[client].orgAng);
	hatData[client].collisionGroup = GetEntProp(modifyEntity, Prop_Send, "m_CollisionGroup");
	hatData[client].solidType = GetEntProp(modifyEntity, Prop_Send, "m_nSolidType");
	hatData[client].moveType = GetEntProp(modifyEntity, Prop_Send, "movetype");
	

	if(StrEqual(classname, "witch", false)) {
		TeleportEntity(entity, EMPTY_ANG, NULL_VECTOR, NULL_VECTOR);
		SetFlag(client, HAT_POCKET);
	}

	if(!HasFlag(client, HAT_POCKET)) {
		// TeleportEntity(entity, EMPTY_ANG, EMPTY_ANG, NULL_VECTOR);
		if(HasFlag(client, HAT_REVERSED)) {
			SetParent(client, entity);
			if(StrEqual(classname, "infected")) {
				SetParentAttachment(modifyEntity, "head", true);
				TeleportEntity(modifyEntity, hatData[client].offset, hatData[client].angles, NULL_VECTOR);
				SetParentAttachment(modifyEntity, "head", true);
			} else {
				SetParentAttachment(modifyEntity, "eyes", true);
				TeleportEntity(modifyEntity, hatData[client].offset, hatData[client].angles, NULL_VECTOR);
				SetParentAttachment(modifyEntity, "eyes", true);
			}
			
			if(HasFlag(client, HAT_COMMANDABLE)) {
				ChooseRandomPosition(hatData[client].offset);
				L4D2_CommandABot(entity, client, BOT_CMD_MOVE, hatData[client].offset);
			}
		} else {
			SetParent(entity, client);
			SetParentAttachment(modifyEntity, "eyes", true);
			TeleportEntity(modifyEntity, hatData[client].offset, hatData[client].angles, NULL_VECTOR);
			SetParentAttachment(modifyEntity, "eyes", true);
		}

		if(visibleEntity > 0) {
			SetParent(visibleEntity, client);
			SetParentAttachment(visibleEntity, "eyes", true);
			hatData[client].offset[2] += 10.0;
			TeleportEntity(visibleEntity, hatData[client].offset, hatData[client].angles, NULL_VECTOR);
			SetParentAttachment(visibleEntity, "eyes", true);
			#if defined DEBUG_HAT_SHOW_FAKE
			L4D2_SetEntityGlow(visibleEntity, L4D2Glow_Constant, 0, 0, color2, false);
			#endif
		}

		#if defined DEBUG_HAT_SHOW_FAKE
		L4D2_SetEntityGlow(modifyEntity, L4D2Glow_Constant, 0, 0, color, false);
		#endif

		SetEntProp(modifyEntity, Prop_Send, "m_nSolidType", 0);
		SetEntProp(modifyEntity, Prop_Send, "m_CollisionGroup", 1);
		SetEntProp(modifyEntity, Prop_Send, "movetype", MOVETYPE_NONE);
	}
}


void GlowWall(int id, float lifetime = 5.0) {
	int ref = GetWallEntity(id);
	float pos[3], mins[3], maxs[3], angles[3];
	GetEntPropVector(ref, Prop_Send, "m_angRotation", angles);
	GetEntPropVector(ref, Prop_Send, "m_vecOrigin", pos);
	GetEntPropVector(ref, Prop_Send, "m_vecMins", mins);
	GetEntPropVector(ref, Prop_Send, "m_vecMaxs", maxs);
	Effect_DrawBeamBoxRotatableToAll(pos, mins, maxs, angles, g_iLaserIndex, 0, 0, 30, lifetime, 0.4, 0.4, 0, 1.0, WALL_COLOR, 0);
}
void DeleteWall(int id) {
	GlowWall(id);
	int ref = GetWallEntity(id);
	if(IsValidEntity(ref)) {
		AcceptEntityInput(ref, "Kill");
	}
	createdWalls.Erase(id - 1);
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
	}else{
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