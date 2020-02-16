#pragma semicolon 1

#define DEBUG

#define PLUGIN_NAME "CSGO Knife Regen"
#define PLUGIN_AUTHOR "jackzmc"
#define PLUGIN_VERSION "1.00"
#define PLUGIN_DESCRIPTION ""

#include <sourcemod>
#include <sdktools>
#include <cstrike>
//#include <sdkhooks>

EngineVersion g_Game;

public Plugin myinfo = 
{
	name = PLUGIN_NAME, 
	author = PLUGIN_AUTHOR, 
	description = PLUGIN_DESCRIPTION, 
	version = PLUGIN_VERSION, 
	url = ""
};

ConVar g_bKnifeHPEnabled, g_iKnifeHPMax, g_iKnifeHPRegain;

public OnPluginStart()
{
	g_Game = GetEngineVersion();
	if (g_Game != Engine_CSGO && g_Game != Engine_CSS)
	{
		SetFailState("This plugin is for CSGO/CSS only.");
	}
	
	g_bKnifeHPEnabled = CreateConVar("knifehp_enable", "1", "Enable regaining health on knife kill", FCVAR_NONE, true, 0.0, true, 1.0);
	g_iKnifeHPMax = CreateConVar("knifehp_max_health", "100", "Maximum health to set an attacker to", FCVAR_NONE, true, 0.0);
	g_iKnifeHPRegain = CreateConVar("knifehp_amount", "100", "Amount of health to give attacker", FCVAR_NONE, true, 0.0);
	HookEvent("player_death", Event_PlayerDeath);
	
	AutoExecConfig(true, "csgo_knifehp");
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	if (g_bKnifeHPEnabled.BoolValue) {
		char weapon_name[64];
		event.GetString("weapon", weapon_name, sizeof(weapon_name));
		if (StrContains(weapon_name, "knife", false) > -1) {
			int attacker = event.GetInt("attacker");
			int client = GetClientOfUserId(attacker);
			
			//get the new health value (current client hp + the regen amount)
			int new_health = GetClientHealth(client) + g_iKnifeHPRegain.IntValue;
			//50 + 20 <= max
			if (IsClientInGame(client) && IsPlayerAlive(client) && !IsFakeClient(client)) {
				if(new_health <= g_iKnifeHPMax.IntValue) { //if the new health is less than max, set it to it
					SetEntityHealth(client, new_health);
				}else{ //if > max, set it to max
					SetEntityHealth(client, g_iKnifeHPMax.IntValue);
				}
			}
			
		}
		
		
	}
} 