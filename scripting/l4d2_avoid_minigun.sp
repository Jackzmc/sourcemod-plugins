#pragma semicolon 1
#pragma newdecls required

//#define DEBUG

#define PLUGIN_NAME "L4D2 AI Avoid Minigun"
#define PLUGIN_DESCRIPTION "Makes the ai avoid being infront of a minigun in use"
#define PLUGIN_AUTHOR "jackzmc"
#define PLUGIN_VERSION "1.0"
#define PLUGIN_URL ""
#define PI 3.14159265358
#define UNITS_SPAWN -120.0

#include <sourcemod>
#include <sdktools>
//#include <sdkhooks>

#define MODEL_MINIGUN		"models/w_models/weapons/w_minigun.mdl"

public Plugin myinfo = 
{
	name = PLUGIN_NAME, 
	author = PLUGIN_AUTHOR, 
	description = PLUGIN_DESCRIPTION, 
	version = PLUGIN_VERSION, 
	url = PLUGIN_URL
};

public void OnPluginStart()
{
	EngineVersion g_Game = GetEngineVersion();
	if(g_Game != Engine_Left4Dead && g_Game != Engine_Left4Dead2)
	{
		SetFailState("This plugin is for L4D/L4D2 only.");	
	}
	CreateTimer(2.0, CheckTimer, _, TIMER_REPEAT);
}

public Action CheckTimer(Handle timer) {
    for(int i = 1; i < MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) == 2) {
			bool usingMinigun = GetEntProp(i, Prop_Send, "m_usingMountedGun", 1) == 1;
			bool usingMountedWeapon = GetEntProp(i, Prop_Send, "m_usingMountedWeapon", 1) == 1;

			if(usingMinigun || usingMountedWeapon) {
				float pos[3], ang[3], finalPos[3], checkPos[3];
				GetClientAbsOrigin(i, pos);
				GetClientEyeAngles(i, ang);
				GetHorizontalPositionFromOrigin(pos, ang, 40.0, checkPos);
				GetHorizontalPositionFromOrigin(pos, ang, UNITS_SPAWN, finalPos);

				for(int bot = 1; bot < MaxClients; bot++) {
					if(IsClientConnected(bot) && IsFakeClient(bot) && GetClientTeam(bot) == 2) {
						float botPos[3];
						GetClientAbsOrigin(bot, botPos);
						
						float center_distance = GetVectorDistance(checkPos, botPos);
						
						if(center_distance <= 70) {
							//PrintHintTextToAll("Bot: %N | d=%f | d2=%f | Vector(%.2f,%.2f,%.2f)", bot, distance, center_distance, finalPos[0], finalPos[1], finalPos[2]);
							//todo: only teleport once?
							//TeleportEntity(bot, finalPos, NULL_VECTOR, NULL_VECTOR);
							L4D2_RunScript("CommandABot({cmd=1,bot=GetPlayerFromUserID(%i),pos=Vector(%f,%f,%f)})", GetClientUserId(bot), finalPos[0], finalPos[1], finalPos[2]);
						}
					}
				}
				break;
			}
		}
	}
}


stock void GetHorizontalPositionFromOrigin(const float pos[3], const float ang[3], float units, float finalPosition[3]) {
	float theta = DegToRad(ang[1]);
	finalPosition[0] = units * Cosine(theta) + pos[0];
	finalPosition[1] = units * Sine(theta) + pos[1];
	finalPosition[2] = pos[2];
}
stock void GetHorizontalPositionFromClient(int client, float units, float finalPosition[3]) {
	float pos[3], ang[3];
	GetClientEyeAngles(client, ang);
	GetClientAbsOrigin(client, pos);

	float theta = DegToRad(ang[1]);
	pos[0] += -150 * Cosine(theta); 
	pos[1] += -150 * Sine(theta); 
	finalPosition = pos;
}

stock void L4D2_RunScript(const char[] sCode, any ...) {
	static int iScriptLogic = INVALID_ENT_REFERENCE;
	if(iScriptLogic == INVALID_ENT_REFERENCE || !IsValidEntity(iScriptLogic)) {
		iScriptLogic = EntIndexToEntRef(CreateEntityByName("logic_script"));
		if(iScriptLogic == INVALID_ENT_REFERENCE|| !IsValidEntity(iScriptLogic))
			SetFailState("Could not create 'logic_script'");
		
		DispatchSpawn(iScriptLogic);
	}
	
	static char sBuffer[512];
	VFormat(sBuffer, sizeof(sBuffer), sCode, 2);
	
	SetVariantString(sBuffer);
	AcceptEntityInput(iScriptLogic, "RunScriptCode");
}
stock void ShowDelayedHintToAll(const char[] format, any ...) {
	char buffer[254];
	VFormat(buffer, sizeof(buffer), format, 2);
	static int hintInt = 0;
	if(hintInt >= 7) {
		PrintHintTextToAll("%s",buffer);
		hintInt = 0;
	}
	hintInt++;
}