#pragma semicolon 1
#pragma newdecls required

//#define DEBUG

#define PLUGIN_NAME "L4D2 AI Avoid Minigun"
#define PLUGIN_DESCRIPTION "Makes the ai avoid being infront of a minigun in use"
#define PLUGIN_AUTHOR "jackzmc"
#define PLUGIN_VERSION "1.0"
#define PLUGIN_URL ""

#include <sourcemod>
#include <sdktools>
#include "jutils.inc"

//#include <sdkhooks>

static bool bIsSurvivorClient[MAXPLAYERS+1];

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
	CreateTimer(5.0, CheckTimer, _, TIMER_REPEAT);
	HookEvent("player_team", Event_PlayerTeamSwitch);
}

public void OnMapStart() {
	for(int i = 1; i < MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2) {
			bIsSurvivorClient[i] = true;
 		}
	}
}

public void OnClientPutInGame(int client) {
	if(IsClientInGame(client) && GetClientTeam(client) == 2) {
		bIsSurvivorClient[client] = true;
	}
}

public void OnClientDisconnect(int client) {
	bIsSurvivorClient[client] = false;
}

public void Event_PlayerTeamSwitch(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	int team = event.GetInt("team");
	if(team == 2) {
		bIsSurvivorClient[client] = true;
	}else if(bIsSurvivorClient[client]) {
		bIsSurvivorClient[client] = false;
	}
}

public Action CheckTimer(Handle timer) {
	//Don't do any processing if no one is connected.
	//optimization: Only update player-based positions ever 5 loops (5 * 5 = 25 seconds)
	static int timer_update_pos;
	if(GetClientCount(true) == 0) return Plugin_Continue;
	static float pos[3], ang[3], botPos[3], center_distance;
	static float finalPos[3], checkPos[3];
	bool usingMinigun, usingMountedWeapon;

	for(int i = 1; i < MaxClients; i++) {
		if(bIsSurvivorClient[i] && IsClientConnected(i) && IsClientInGame(i) && IsPlayerAlive(i) && !IsFakeClient(i)) {
			usingMinigun = GetEntProp(i, Prop_Send, "m_usingMountedGun", 1) == 1;
			usingMountedWeapon = GetEntProp(i, Prop_Send, "m_usingMountedWeapon", 1) == 1;

			if(usingMinigun || usingMountedWeapon) {
				if(timer_update_pos == 0) {
					GetClientAbsOrigin(i, pos);
					GetClientEyeAngles(i, ang);
					GetHorizontalPositionFromOrigin(pos, ang, 40.0, checkPos); //get center point of check radius
					GetHorizontalPositionFromOrigin(pos, ang, -120.0, finalPos); //get center point of the bot destination
				}

				for(int bot = 1; bot < MaxClients; bot++) {
					if(bIsSurvivorClient[bot] && IsClientInGame(bot) && IsFakeClient(bot) && IsPlayerAlive(bot)) {
						GetClientAbsOrigin(bot, botPos);
						
						center_distance = GetVectorDistance(checkPos, botPos, true);
						
						if(center_distance <= 4900) {
							L4D2_RunScript("CommandABot({cmd=1,bot=GetPlayerFromUserID(%i),pos=Vector(%f,%f,%f)})", GetClientUserId(bot), finalPos[0], finalPos[1], finalPos[2]);
						}else{
							L4D2_RunScript("CommandABot({cmd=3,bot=GetPlayerFromUserID(%i)})", GetClientUserId(bot));
						}
					}
				}
				break;
			}
		}
	}
	timer_update_pos++;
	if(timer_update_pos >= 5) timer_update_pos = 0;
	return Plugin_Continue;
}
