#define DEBUG

#define PLUGIN_AUTHOR "Stugger"
#define PLUGIN_VERSION "2.2"

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <smlib/effects>

public Plugin myinfo = 
{
	name = "GrabEnt",
	author = PLUGIN_AUTHOR,
	description = "Grab then Move, Push/Pull or Rotate the entity you're looking at until released",
	version = PLUGIN_VERSION,
	url = ""
};

int g_pGrabbedEnt[MAXPLAYERS + 1];
int g_eRotationAxis[MAXPLAYERS + 1] =  { -1, ... };
int g_eOriginalColor[MAXPLAYERS + 1][4];

float g_pLastButtonPress[MAXPLAYERS + 1];
float g_fGrabOffset[MAXPLAYERS + 1][3];
float g_fGrabDistance[MAXPLAYERS + 1];

MoveType g_pLastMoveType[MAXPLAYERS + 1];
bool g_pInRotationMode[MAXPLAYERS + 1];
bool g_eReleaseFreeze[MAXPLAYERS + 1] =  { true, ... };
bool g_bHighlightEntity[MAXPLAYERS+1];

Handle g_eGrabTimer[MAXPLAYERS+1];

int g_BeamSprite; 
int g_HaloSprite;
int g_iLaserIndex;

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

#define MAX_HIGHLIGHTED_CLASSNAMES 3
static char HIGHLIGHTED_CLASSNAMES[MAX_HIGHLIGHTED_CLASSNAMES][] = {
	"env_physics_blocker",
	"env_player_blocker",
	"func_brush"
}

ConVar g_cvarEnabled;

public void OnPluginStart()
{
	g_cvarEnabled = CreateConVar("sm_grabent_allow", "1", "Is grabent allowed", FCVAR_NONE, true, 0.0, true, 1.0);
	RegAdminCmd("sm_grabent_freeze", Cmd_ReleaseFreeze, ADMFLAG_CHEATS, "<0/1> - Toggle entity freeze/unfreeze on release.");
	RegAdminCmd("sm_grab", Cmd_Grab, ADMFLAG_CHEATS, "Toggle Grab the entity in your crosshair.");
	RegAdminCmd("+grabent", Cmd_Grab, ADMFLAG_CHEATS, "Grab the entity in your crosshair.");
	RegAdminCmd("-grabent", Cmd_Release, ADMFLAG_CHEATS, "Release the grabbed entity.");
}

public void OnMapStart()
{
	g_iLaserIndex = PrecacheModel("materials/sprites/laserbeam.vmt");
	g_BeamSprite = PrecacheModel("materials/sprites/laser.vmt", true);
	g_HaloSprite = PrecacheModel("materials/sprites/halo01.vmt", true);
	
	for (int i = 0; i < MAXPLAYERS; i++) {
		g_pGrabbedEnt[i] = -1;
		g_eRotationAxis[i] = -1;
		g_pLastButtonPress[i] = 0.0;
		
		g_pInRotationMode[i] = false;
		g_eReleaseFreeze[i] = true;
		
		g_eGrabTimer[i] = null;
	}
}
public void OnClientDisconnect(client)
{
	if (g_pGrabbedEnt[client] != -1 && IsValidEntity(g_pGrabbedEnt[client]))
		Cmd_Release(client, 0);
		
	g_eRotationAxis[client] = -1;
	
	g_pLastButtonPress[client] = 0.0;
	
	g_pInRotationMode[client] = false;
	g_eReleaseFreeze[client] = true;
}

//============================================================================
//							FREEZE SETTING COMMAND							//
//============================================================================
public Action Cmd_ReleaseFreeze(client, args)
{
	if (args < 1) {
		ReplyToCommand(client, "\x04[SM]\x01 \x05sm_grabent_freeze <0/1>\x01 -- \x050\x01: Entity unfreeze on release, \x051\x01: Entity freeze on release");
		return Plugin_Handled;
	}
	
	char sArg[16];
	GetCmdArg(1, sArg, sizeof(sArg)); TrimString(sArg);
	
	if (!StrEqual(sArg, "0") && !StrEqual(sArg, "1")) {
		ReplyToCommand(client, "\x04[SM]\x01 ERROR: Value can only be either 0 or 1");
		return Plugin_Handled;
	}

	g_eReleaseFreeze[client] = StrEqual(sArg, "1");
	
	PrintToChat(client, "\x04[SM]\x01 Entities will now be \x05%s\x01 on Release!", g_eReleaseFreeze[client] == true ? "Frozen" : "Unfrozen");
	return Plugin_Handled;
}

//============================================================================
//							GRAB ENTITY COMMAND								//
//============================================================================
Action Cmd_Grab(int client, int args) {
	if(!g_cvarEnabled.BoolValue) {
		ReplyToCommand(client, "[SM] Grabent is disabled");
		return Plugin_Handled;
	} else if (client < 1 || client > MaxClients || !IsClientInGame(client)) {
		return Plugin_Handled;
	} else if (g_pGrabbedEnt[client] > 0 && IsValidEntity(g_pGrabbedEnt[client])) {
		Cmd_Release(client, 0);
		return Plugin_Handled;
	}
		
	// int ent = GetClientAimTarget(client, false);
	int ent =  GetLookingEntity(client, Filter_IgnoreForbidden);
	
	if (ent == -1 || !IsValidEntity(ent))
		return Plugin_Handled; //<-- timer to allow search for entity??

	// Grab the parent
	int parent = GetEntPropEnt(ent, Prop_Data, "m_hParent");
	if(parent > 0) {
		ent = parent;
	}
	if(!CheckBlacklist(ent)) {
		return Plugin_Handled;
	}

	float entOrigin[3], playerGrabOrigin[3];
	GetEntPropVector(ent, Prop_Send, "m_vecOrigin", entOrigin);
	GetClientEyePosition(client, playerGrabOrigin);
	
	g_pGrabbedEnt[client] = ent;
	
	// Get the point at which the ray first hit the entity
	float initialRay[3];
	GetInitialRayPosition(client, initialRay);
	
	// Calculate the offset between intitial ray hit and the entities origin
	g_fGrabOffset[client][0] = entOrigin[0] - initialRay[0];
	g_fGrabOffset[client][1] = entOrigin[1] - initialRay[1];
	g_fGrabOffset[client][2] = entOrigin[2] - initialRay[2];
	
	// Calculate the distance between ent and player
	float xDis = Pow(initialRay[0]-(playerGrabOrigin[0]), 2.0);
	float yDis = Pow(initialRay[1]-(playerGrabOrigin[1]), 2.0);
	float zDis = Pow(initialRay[2]-(playerGrabOrigin[2]), 2.0);
	g_fGrabDistance[client] = SquareRoot((xDis)+(yDis)+(zDis));

	// Get and Store entities original color (useful if colored)
	int entColor[4];
	int colorOffset = GetEntSendPropOffs(ent, "m_clrRender");
	
	if (colorOffset > 0) 
	{
		entColor[0] = GetEntData(ent, colorOffset, 1);
		entColor[1] = GetEntData(ent, colorOffset + 1, 1);
		entColor[2] = GetEntData(ent, colorOffset + 2, 1);
		entColor[3] = GetEntData(ent, colorOffset + 3, 1);
	}
	
	g_eOriginalColor[client][0] = entColor[0];
	g_eOriginalColor[client][1] = entColor[1];
	g_eOriginalColor[client][2] = entColor[2];
	g_eOriginalColor[client][3] = entColor[3];
	
	// Set entities color to grab color (green and semi-transparent)
	SetEntityRenderMode(ent, RENDER_TRANSALPHA);
	SetEntityRenderColor(ent, 0, 255, 0, 235);
	
	// Freeze entity
	char sClass[64];
	GetEntityClassname(ent, sClass, sizeof(sClass)); TrimString(sClass);
	
	if (StrEqual(sClass, "player", false)) {
		g_pLastMoveType[ent] = GetEntityMoveType(ent);
		SetEntityMoveType(ent, MOVETYPE_NONE);
	} else
		AcceptEntityInput(ent, "DisableMotion");

	
	g_pLastMoveType[client] = GetEntityMoveType(client);
	// Disable weapon prior to timer
	SetWeaponDelay(client, 1.0);
	
	// Make sure rotation mode can immediately be entered
	g_pLastButtonPress[client] = GetGameTime() - 2.0;
	g_pInRotationMode[client] = false;

	g_bHighlightEntity[client] = false;
	for(int i = 0; i < MAX_HIGHLIGHTED_CLASSNAMES; i++) {
		if(StrEqual(HIGHLIGHTED_CLASSNAMES[i], sClass)) {
			g_bHighlightEntity[client] = true;
			break;
		}
	}
	
	DataPack pack;
	g_eGrabTimer[client] = CreateDataTimer(0.1, Timer_UpdateGrab, pack, TIMER_REPEAT);
	pack.WriteCell(client);
	
	return Plugin_Handled;
}
 
//============================================================================
//							TIMER FOR GRAB ENTITY							//
//============================================================================
public Action Timer_UpdateGrab(Handle timer, DataPack pack) {
	int client;
	pack.Reset();
	client = pack.ReadCell();
	
	if (!IsValidEntity(client) || client < 1 || client > MaxClients || !IsClientInGame(client))
		return Plugin_Stop;
	
	if (g_pGrabbedEnt[client] == -1 || !IsValidEntity(g_pGrabbedEnt[client]))
		return Plugin_Stop;
	
	// Continuously delay use of weapon, as to not fire any bullets when pushing/pulling/rotating
	SetWeaponDelay(client, 1.0);	

	if(g_bHighlightEntity[client]) {
		char targetname[64];
		GetEntPropString(g_pGrabbedEnt[client], Prop_Data, "m_iName", targetname, sizeof(targetname));
		PrintCenterText(client, "%s", targetname);
		GlowEntity(client, g_pGrabbedEnt[client]);
	}
	
	// *** Enable/Disable Rotation Mode
	if (GetClientButtons(client) & IN_RELOAD) {
		// Avoid instant enable/disable of rotation mode by requiring a one second buffer
		if (GetGameTime() - g_pLastButtonPress[client] >= 1.0) {
			g_pLastButtonPress[client] = GetGameTime();
			g_pInRotationMode[client] = g_pInRotationMode[client] == true ? false : true;
			PrintToChat(client, "\x04[SM]\x01 Rotation Mode \x05%s\x01", g_pInRotationMode[client] == true ? "Enabled" : "Disabled");		
			
			// Restore the entities color and alpha if enabling
			if(g_pInRotationMode[client]) {
				SetEntityRenderColor(g_pGrabbedEnt[client], 255, 255, 255, 255);
				PrintToChat(client, "\x05[A]\x01 RED \x05[S]\x01 GREEN \x05[D]\x01 BLUE \x05[W]\x01 SHOW RINGS");
			}
			// Change back to grabbed color if disabling
			else
				SetEntityRenderColor(g_pGrabbedEnt[client], 0, 255, 0, 235);
		}
	}
	// ***In Rotation Mode
	if (g_pInRotationMode[client]) {
		SetEntityMoveType(client, MOVETYPE_NONE);
		
		float ang[3], pos[3], mins[3], maxs[3];
		GetEntPropVector(g_pGrabbedEnt[client], Prop_Send, "m_angRotation", ang);
		GetEntPropVector(g_pGrabbedEnt[client], Prop_Send, "m_vecOrigin", pos);
		GetEntPropVector(g_pGrabbedEnt[client], Prop_Send, "m_vecMins", mins);
		GetEntPropVector(g_pGrabbedEnt[client], Prop_Send, "m_vecMaxs", maxs);
		
		// If the entity is a child, it will have a null position, so we'll hesitantly use the parents position
		int parent = GetEntPropEnt(g_pGrabbedEnt[client], Prop_Data, "m_hMoveParent");
		if (parent > 0 && IsValidEntity(parent))
			GetEntPropVector(parent, Prop_Send, "m_vecOrigin", pos);
		
		// Get rotation axis from button press
		int buttonPress = GetClientButtons(client);	
		switch(buttonPress) {
			case IN_FORWARD: {
				g_eRotationAxis[client] = -1;  // [W] = Show Rings
				PrintToChat(client, "\x04[SM]\x01 Show Rings \x05On\x01");
			}
			case IN_MOVELEFT: {
				g_eRotationAxis[client] = 0;  // [A] = x axis
				PrintToChat(client, "\x04[SM]\x01 Rotation Axis \x05X\x01");
			}
			case IN_BACK: {
				g_eRotationAxis[client] = 1; 		// [S] = y axis
				PrintToChat(client, "\x04[SM]\x01 Rotation Axis \x05Y\x01");
			}
			case IN_MOVERIGHT: {
				g_eRotationAxis[client] = 2; // [D] = z axis
				PrintToChat(client, "\x04[SM]\x01 Rotation Axis \x05Z\x01");
			}
		}

			
		// Reset angles when A+S+D is pressed
		if((buttonPress & IN_MOVELEFT) && (buttonPress & IN_BACK) && (buttonPress & IN_MOVERIGHT)) { 
			ang[0] = 0.0; ang[1] = 0.0; ang[2] = 0.0;
			g_eRotationAxis[client] = -1;
		}
		
		// Largest side should dictate the diameter of the rings
		float diameter, sendAng[3];
		diameter = (maxs[0] > maxs[1]) ? (maxs[0] + 10.0) : (maxs[1] + 10.0);
		diameter = ((maxs[2] + 10.0) > diameter) ? (maxs[2] + 10.0) : diameter;
		
		// Sending original ang will cause non-stop rotation issue
		sendAng = ang; 
		
		// Draw rotation rings
		switch(g_eRotationAxis[client]) {
			case -1: CreateRing(client, sendAng, pos, diameter, 0, true); // all 3 rings
			case 0:  CreateRing(client, sendAng, pos, diameter, 0, false); // red (x)
			case 1:  CreateRing(client, sendAng, pos, diameter, 1, false); // green (y)
			case 2:  CreateRing(client, sendAng, pos, diameter, 2, false); // blue (z)
		}
		
		// Rotate with mouse if on a rotation axis (A,S,D)
		if (g_eRotationAxis[client] != -1) {
			// + Rotate
			if (GetClientButtons(client) & IN_ATTACK) 
				ang[g_eRotationAxis[client]] += 10.0;
			// - Rotate
			else if (GetClientButtons(client) & IN_ATTACK2) 
				ang[g_eRotationAxis[client]] -= 10.0;
		}
		
		TeleportEntity(g_pGrabbedEnt[client], NULL_VECTOR, ang, NULL_VECTOR);
	}
	// ***Not in Rotation Mode
	if (!g_pInRotationMode[client] || g_eRotationAxis[client] == -1) {
		// Keep track of player noclip as to avoid forced enable/disable
		if(!g_pInRotationMode[client]) {
			SetEntityMoveType(client, g_pLastMoveType[client])
		}
		// Push entity (Allowed if we're in rotation mode, not on a rotation axis (-1))
		if (GetClientButtons(client) & IN_ATTACK) 
		{
			if (g_fGrabDistance[client] < 80)
	    		g_fGrabDistance[client] += 10;
			else
	    		g_fGrabDistance[client] += g_fGrabDistance[client] / 25;
		}
		// Pull entity (Allowed if we're in rotation mode, not on a rotation axis (-1))
		else if (GetClientButtons(client) & IN_ATTACK2 && g_fGrabDistance[client] > 25) 
		{
			if (g_fGrabDistance[client] < 80)
	    		g_fGrabDistance[client] -= 10;
			else
	    		g_fGrabDistance[client] -= g_fGrabDistance[client] / 25;		
		}
		
		g_eRotationAxis[client] = -1;
	}

	// *** Runs whether in rotation mode or not
	float entNewPos[3];
	int buttons = GetClientButtons(client);
	GetEntNewPosition(client, entNewPos, buttons & IN_SPEED == 0);
	entNewPos[0] += g_fGrabOffset[client][0];
	entNewPos[1] += g_fGrabOffset[client][1];
	entNewPos[2] += g_fGrabOffset[client][2];


	float mins[3];
	GetEntPropVector(g_pGrabbedEnt[client], Prop_Data, "m_vecMins", mins);
	entNewPos[2] -= mins[2]; 
	
	TeleportEntity(g_pGrabbedEnt[client], entNewPos, NULL_VECTOR, NULL_VECTOR);
	
	return Plugin_Handled;
}

//============================================================================
//							RELEASE ENTITY COMMAND							//
//============================================================================
public Action Cmd_Release(client, args) {
	if (!IsValidEntity(client) || client < 1 || client > MaxClients || !IsClientInGame(client))
		return Plugin_Handled;
		
	if (g_pGrabbedEnt[client] == -1 || !IsValidEntity(g_pGrabbedEnt[client]))
		return Plugin_Handled;
		
	// Allow near-immediate use of weapon
	SetWeaponDelay(client, 0.2);
	
	SetEntityMoveType(client, g_pLastMoveType[client]);

	
	// Unfreeze if target was a player and unfreeze if setting is set to 0
	char sClass[64];
	GetEntityClassname(g_pGrabbedEnt[client], sClass, sizeof(sClass)); TrimString(sClass);
	
	if (StrEqual(sClass, "player", false))
		SetEntityMoveType(g_pGrabbedEnt[client], g_pLastMoveType[g_pGrabbedEnt[client]]);
	else if (g_eReleaseFreeze[client] == false)
		AcceptEntityInput(g_pGrabbedEnt[client], "EnableMotion");
		
	// Restore color and alpha to original prior to grab
	SetEntityRenderColor(g_pGrabbedEnt[client], g_eOriginalColor[client][0], g_eOriginalColor[client][1], g_eOriginalColor[client][2], g_eOriginalColor[client][3]);
	
	// Kill the grab timer and reset control values
	if (IsValidHandle(g_eGrabTimer[client])) {
		delete g_eGrabTimer[client];
	}
	
	g_pGrabbedEnt[client] = -1;
	g_eRotationAxis[client] = -1;
	g_pInRotationMode[client] = false;
	
	return Plugin_Handled;
}

//============================================================================
//							***		UTILITIES	***							//
//============================================================================
int GetLookingEntity(int client, TraceEntityFilter filter) {
	static float pos[3], ang[3];
	GetClientEyePosition(client, pos);
	GetClientEyeAngles(client, ang);
	TR_TraceRayFilter(pos, ang, MASK_ALL, RayType_Infinite, filter, client);
	if(TR_DidHit()) {
		return TR_GetEntityIndex();
	}
	return -1;
}

stock bool GetEntNewPosition(int client, float endPos[3], bool doCollision = true)
{ 
	if (client > 0 && client <= MaxClients && IsClientInGame(client)) {
		float clientEye[3], clientAngle[3], direction[3];
		GetClientEyePosition(client, clientEye);
		GetClientEyeAngles(client, clientAngle);

		GetAngleVectors(clientAngle, direction, NULL_VECTOR, NULL_VECTOR);
		ScaleVector(direction, g_fGrabDistance[client]);
		AddVectors(clientEye, direction, endPos);

		if(doCollision) {
			TR_TraceRayFilter(clientEye, endPos, MASK_OPAQUE, RayType_EndPoint, TraceRayFilterEnt, client);
			if (TR_DidHit(INVALID_HANDLE)) {
				TR_GetEndPosition(endPos);
			}
		}
		return true;
	}

	return false;
}
/////
stock bool GetInitialRayPosition(int client, float endPos[3])
{ 
	if (client > 0 && client <= MaxClients && IsClientInGame(client)) {
		float clientEye[3], clientAngle[3];
		GetClientEyePosition(client, clientEye);
		GetClientEyeAngles(client, clientAngle);

		TR_TraceRayFilter(clientEye, clientAngle, MASK_SOLID, RayType_Infinite, TraceRayFilterActivator, client);
		if (TR_DidHit(INVALID_HANDLE))
			TR_GetEndPosition(endPos);
		return true;
	}
	return false;
}
/////
stock void SetWeaponDelay(int client, float delay)
{
	if (IsValidEntity(client) && client > 0 && client <= MaxClients && IsClientInGame(client)) {
		int pWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
		
		if (IsValidEntity(pWeapon) && pWeapon != -1) {
			SetEntPropFloat(pWeapon, Prop_Send, "m_flNextPrimaryAttack", GetGameTime() + delay); 
			SetEntPropFloat(pWeapon, Prop_Send, "m_flNextSecondaryAttack", GetGameTime() + delay); 
		}
	}
}
/////
stock void CreateRing(int client, float ang[3], float pos[3], float diameter, int axis, bool trio)
{
	if (!IsValidEntity(client) || client < 1 || client > MaxClients || !IsClientInGame(client))
		return;
		
	float ringVecs[26][3];
	int ringColor[3][4];

	ringColor[0] = { 255, 0, 0, 255 };
	ringColor[1] = { 0, 255, 0, 255 };
	ringColor[2] = { 0, 0, 255, 255 };
	
	int numSides = (!trio) ? 26 : 17;
	float angIncrement = (!trio) ? 15.0 : 24.0;

	for (int i = 1; i < numSides; i++) {
		float direction[3], endPos[3];
		switch(axis) {
			case 0: GetAngleVectors(ang, direction, NULL_VECTOR, NULL_VECTOR);
			case 1:
			{
				ang[2] = 0.0;
				GetAngleVectors(ang, NULL_VECTOR, direction, NULL_VECTOR);
			}
			case 2: GetAngleVectors(ang, NULL_VECTOR, NULL_VECTOR, direction);
		}
	
		ScaleVector(direction, diameter);
		AddVectors(pos, direction, endPos);

		if (i == 1) ringVecs[0] = endPos;
			
		ringVecs[i] = endPos;
		ang[axis] += angIncrement;
		
		TE_SetupBeamPoints(ringVecs[i-1], ringVecs[i], g_BeamSprite, g_HaloSprite, 0, 15, 0.2, 2.5, 2.5, 1, 0.0, ringColor[axis], 10);
		TE_SendToClient(client, 0.0);
		
		if(trio && i == numSides-1 && axis < 2) {
			i = 0;
			ang[axis] -= angIncrement * (numSides-1);
			axis += 1;
		}
	}
}

void GlowEntity(int client, int entity) {
	float pos[3], mins[3], maxs[3], angles[3];
	GetEntPropVector(entity, Prop_Send, "m_angRotation", angles);
	GetEntPropVector(entity, Prop_Send, "m_vecOrigin", pos);
	GetEntPropVector(entity, Prop_Send, "m_vecMins", mins);
	GetEntPropVector(entity, Prop_Send, "m_vecMaxs", maxs);
	Effect_DrawBeamBoxRotatableToClient(client, pos, mins, maxs, angles, g_iLaserIndex, 0, 0, 30, 0.1, 0.4, 0.4, 0, 0.1, { 0, 255, 0, 235 }, 0);
}

//============================================================================
//							***		FILTERS		***							//
//============================================================================

public bool TraceRayFilterEnt(int entity, int mask, any:client)
{
	if (entity == client || entity == g_pGrabbedEnt[client]) 
		return false;
	return true;
}  
/////
public bool TraceRayFilterActivator(int entity, int mask, any:activator)
{
	if (entity == activator)
		return false;
	return true;
}

bool Filter_IgnoreForbidden(int entity, int mask, int data) {
	if(entity == data || entity == 0) return false;
	if(entity <= MaxClients) return true;
	return CheckBlacklist(entity);
}

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
	if(StrContains(buffer, "randomizer") == 0) {
		return false;
	}
	GetEntityClassname(entity, buffer, sizeof(buffer));
	return true;
}