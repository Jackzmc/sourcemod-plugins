#pragma semicolon 1

#define DEBUG

#define PLUGIN_AUTHOR ""
#define PLUGIN_VERSION "0.00"

#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <sdkhooks>

EngineVersion g_Game;
ConVar hTrollEnableState, hShotFailPercentage, hTrollTargets, hGunType;
bool TrollTargets[MAXPLAYERS+1], lateLoaded;

public Plugin myinfo = 
{
	name = "",
	author = PLUGIN_AUTHOR,
	description = "",
	version = PLUGIN_VERSION,
	url = ""
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
	if(late) {
		lateLoaded = true;
	}
} 

public OnPluginStart()
{
	g_Game = GetEngineVersion();
	if(g_Game != Engine_CSGO && g_Game != Engine_CSS)
	{
		SetFailState("This plugin is for CSGO/CSS only.");	
	}
	//convars
	hTrollEnableState = CreateConVar("troll_enable", "1.0", "Enable troll. 0 -> OFF, 1 -> Shots", FCVAR_NONE, true, 0.0, true, 1.0);
	hShotFailPercentage = CreateConVar("troll_shot_fail_percentage", "0.4", "The percentage that the troll acts (shots fail). float 0-1", FCVAR_NONE, true, 0.0, true, 1.0);
	hTrollTargets = CreateConVar("troll_targets", "", "comma seperated list of steamid64 targets (ex: STEAM_0:0:75141700)", FCVAR_NONE);
	hGunType = CreateConVar("troll_shot_mode", "0", "0 -> ALL Weapons, 1 -> AWP", FCVAR_NONE, true, 0.0, true, 1.0);

	if(lateLoaded) FindExistingVictims();
}

public void OnClientAuthorized(int client, const char[] auth) {
	if(hTrollEnableState.IntValue > 0) {
		if(StrContains(auth, "BOT", true) == -1) {
			TestForTrollUser(client, auth);
		}
	}
}
public void OnClientPutInServer(int client) {
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}
public OnClientDisconnect(int client) {
	TrollTargets[client] = false;
}
public void FindExistingVictims() {
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientInGame(i) && IsClientAuthorized(i)) {
			if(!IsFakeClient(i)) {
				char auth[64];
				GetClientAuthId(i, AuthId_Steam2, auth, sizeof(auth));
				TestForTrollUser(i, auth);
			}
			SDKHook(i, SDKHook_OnTakeDamage, OnTakeDamage);
		}
	}
}
public bool TestForTrollUser(int client, const char[] auth) {
	char targets[32][8];
	char raw_targets[64];
	hTrollTargets.GetString(raw_targets, sizeof(raw_targets));
	ExplodeString(raw_targets, ",", targets, 8, 32, false);
	for(int i = 0; i < 8; i++) {
		if(StrEqual(targets[i], auth, true)) {
			PrintToServer("Troll victim detected with id %d and steamid %s", client, auth);
			TrollTargets[client] = true;
			return true;
		}
	}
	return false;
}
public Action OnTakeDamage(int victim,  int& attacker, int& inflictor, float& damage, int& damagetype, int& weapon, float damageForce[3], float damagePosition[3]) {
	if(hTrollEnableState.IntValue == 1) {
		if(TrollTargets[attacker]) {
			bool try_failure = false;
			char weapon_name[64];
			GetClientWeapon(victim, weapon_name, sizeof(weapon_name));

			if(hGunType.IntValue == 0) {
                try_failure = true;
			}else{
				if(StrEqual(weapon_name, "weapon_awp", true)) {
					try_failure = true;
				}

            }
			float random_float = GetURandomFloat();
			if(try_failure) {
				if(FloatCompare(random_float, hShotFailPercentage.FloatValue) == -1) {
					damage = 0.0;
					return Plugin_Handled;
				}
			}
		}
	}
	return Plugin_Continue;
}