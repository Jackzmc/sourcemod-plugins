#pragma semicolon 1
#pragma newdecls required

//#define DEBUG

#define PLUGIN_NAME "L4D2 AI Avoid Minigun"
#define PLUGIN_DESCRIPTION "Makes the ai avoid being infront of a minigun in use"
#define PLUGIN_AUTHOR "jackzmc"
#define PLUGIN_VERSION "1.0"
#define PLUGIN_URL ""
#define UNITS_SPAWN -120.0

#include <sourcemod>
#include <sdktools>
#include "jutils.inc"
//#include <sdkhooks>


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

//possible optimization: Only update player's position every X times, always check for bots
public Action CheckTimer(Handle timer) {
	//Don't do any processing if no one is connected.
	if(GetClientCount(true) == 0) return Plugin_Continue;
	for(int i = 1; i < MaxClients; i++) {
		//possibly can optimize? check array if int is in it.
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
	return Plugin_Continue;
}
