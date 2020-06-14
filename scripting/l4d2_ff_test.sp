#pragma semicolon 1
#pragma newdecls required

//#define DEBUG

#define PLUGIN_NAME "l4d2_ff_test"
#define PLUGIN_DESCRIPTION ""
#define PLUGIN_AUTHOR "jackzmc"
#define PLUGIN_VERSION "1.0"
#define PLUGIN_URL ""

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

static bool bLateLoaded;
static float ffDamage[MAXPLAYERS+1];
static int ffCount[MAXPLAYERS+1];

public Plugin myinfo = 
{
	name = PLUGIN_NAME, 
	author = PLUGIN_AUTHOR, 
	description = PLUGIN_DESCRIPTION, 
	version = PLUGIN_VERSION, 
	url = PLUGIN_URL
};
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
	if(late) {
		bLateLoaded = true;
	}
} 

public void OnPluginStart()
{
	EngineVersion g_Game = GetEngineVersion();
	if(g_Game != Engine_Left4Dead && g_Game != Engine_Left4Dead2)
	{
		SetFailState("This plugin is for L4D/L4D2 only.");	
	}
	if(bLateLoaded) {
		for(int i=1;i<MaxClients;i++) {
			if(IsClientConnected(i)) {
				int team = GetClientTeam(i);
				if(team == 2) {
					SDKHook(i, SDKHook_OnTakeDamageAlive, OnTakeDamage);
					SDKHook(i, SDKHook_WeaponEquip, WeaponCanUse);
				}
			}
		}
	}
	HookEvent("round_start", Event_RoundStart);
	RegConsoleCmd("sm_view_ff", Command_ViewFF, "View all player's friendly fire counts");
}

//sdkhook setups
public void OnClientPutInServer(int client) {
	int team = GetClientTeam(client);
	if(team == 2) {
		SDKHook(client, SDKHook_OnTakeDamageAlive, OnTakeDamage);
		SDKHook(client, SDKHook_WeaponEquip, WeaponCanUse);
	}
}
public void Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast) {
	if(!event.GetBool("disconnect")) {
		int team = event.GetInt("team");
		int userid = GetClientOfUserId(event.GetInt("userid"));
		if(team == 2) {
			SDKHook(userid, SDKHook_OnTakeDamageAlive, OnTakeDamage);
			if(!IsFakeClient(userid)) {
				SDKHook(userid, SDKHook_WeaponEquip, WeaponCanUse);
			}
			//add new hook
		}else{
			SDKUnhook(userid, SDKHook_OnTakeDamageAlive, OnTakeDamage);
			SDKUnhook(userid, SDKHook_WeaponEquip, WeaponCanUse);
		}
	}
}

//events
public void OnMapStart() {
	for(int i=1; i < MaxClients+1; i++) {
		ffDamage[i] = 0.0;
		ffCount[i] = 0;
	}
}
public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast) {
	OnMapStart();
}

//damage counting
public Action OnTakeDamage(int victim,  int& attacker, int& inflictor, float& damage, int& damagetype, int& weapon, float damageForce[3], float damagePosition[3]) {
	ffDamage[attacker] += damage;
	ffCount[attacker]++;
	return Plugin_Continue;
}

//commands
public Action Command_ViewFF(int client, int args) {
	ReplyToCommand(client, "FF Stats for this round: ");
	for(int i=1; i < MaxClients+1; i++) {
		if(IsClientConnected(i) && !IsFakeClient(i)) {
			ReplyToCommand(client, "Client %N: %d HP (%d friendly fires)", i,  RoundToNearest(ffDamage[i]), ffCount[i]);
		}
	}
}

//events
public Action WeaponCanUse(int client, int weapon) {
	char item[32];
	GetEdictClassname(weapon, item, sizeof(item));
	//event.GetString("item", item, sizeof(item));
	if(StrEqual(item, "weapon_rifle_m60", true)) {
		if(ffCount[client] > 5 || ffDamage[client] >= 35) {
			int damage = RoundToNearest(ffDamage[client]);
			PrintToChat(client, "Sorry, you can't use m60s due to your %d ff attacks (total %d HP)", ffCount[client], damage);
			return Plugin_Handled;
		}
	} 
	return Plugin_Continue;
}