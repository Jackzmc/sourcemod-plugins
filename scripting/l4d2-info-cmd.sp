#pragma semicolon 1

#define DEBUG

#define PLUGIN_NAME "L4D2 Game Info"
#define PLUGIN_DESCRIPTION ""
#define PLUGIN_AUTHOR "jackzmc"
#define PLUGIN_VERSION "1.0"

#include <sourcemod>
#include <sdktools>
//#include <sdkhooks>

char g_icDifficulty[16] = "Normal";

public Plugin myinfo = 
{
	name = PLUGIN_NAME, 
	author = PLUGIN_AUTHOR, 
	description = PLUGIN_DESCRIPTION, 
	version = PLUGIN_VERSION, 
	url = ""
};

public OnPluginStart()
{
	EngineVersion g_Game = GetEngineVersion();
	if(g_Game != Engine_Left4Dead && g_Game != Engine_Left4Dead2)
	{
		SetFailState("This plugin is for L4D/L4D2 only.");	
	}
	RegConsoleCmd("sm_gameinfo", PrintGameInfo, "Show the director main menu");
	HookEvent("difficulty_changed", Event_DifficultyChanged);
	FindConVar("z_difficulty").GetString(g_icDifficulty, sizeof(g_icDifficulty));
	CreateTimer(300.0, Timer_PrintInfoMessage, _, TIMER_REPEAT);
}
public OnClientPutInServer(client)
{
	PrintToChat(client, "Welcome to the Manual Director server! For information or access the panel go to l4d2.jackz.me");
}
// print info
public Action Timer_PrintInfoMessage(Handle timer)
{
	PrintToChatAll("This is the Manual Director server. Access the panel, and info about the server at l4d2.jackz.me");
	return Plugin_Continue;
}
public Action PrintGameInfo(int client, int args) {
	//print server info
	ReplyToCommand(client, ">map,diff");
	char map[32];
	
	GetCurrentMap(map, sizeof(map));
	
	ReplyToCommand(client, "%s,%s",map,g_icDifficulty);
	//print client info
	ReplyToCommand(client,">id,name,bot,health,status,throwSlot,kitSlot,pillSlot,modelName");
	for (int i = 1; i < MaxClients;i++) {
		if (!IsClientInGame(i)) continue;
		if (GetClientTeam(i) != 2) continue;
		int hp = GetClientRealHealth(i);
		int bot = IsFakeClient(i);
		bool incap = IsPlayerIncapped(i);
		bool blackandwhite = IsPlayerNearDead(i);
		
		char status[9];
		char name[32];
		char pillType[32];
		char kitType[32];
		char throwType[32];
		char survType[9];
		
		if(hp < 0) {
			status = "dead";
		}else if(incap) {
			status = "incap";
		}else if(blackandwhite) {
			status = "neardead";
		}else{
			status = "alive";
		}
		int pillWpn = GetPlayerWeaponSlot(i, 4); //pills slot
		int kitWpn = GetPlayerWeaponSlot(i, 3);
		int throwWpn = GetPlayerWeaponSlot(i, 2);
		if(pillWpn != -1) GetEdictClassname(pillWpn, pillType, sizeof(pillType));
		if(kitWpn != -1) GetEdictClassname(kitWpn, kitType, sizeof(kitType));
		if(throwWpn != -1) GetEdictClassname(throwWpn, throwType, sizeof(throwType));
		ReplaceString(pillType, sizeof(pillType), "weapon_", "");
		ReplaceString(kitType, sizeof(kitType), "weapon_", "");
		ReplaceString(throwType, sizeof(throwType), "weapon_", "");
		
		GetClientName(i, name, sizeof(name));
		GetModelName(i, survType, sizeof(survType));
		
		ReplyToCommand(client,"%d,%s,%d,%d,%s,%s,%s,%s,%s", i, name, bot, hp, status, throwType, kitType, pillType, survType);
	}
	
}
// EVENTS //
public void Event_DifficultyChanged(Event event, const char[] name, bool dontBroadcast) {
	event.GetString("newDifficulty",g_icDifficulty,sizeof(g_icDifficulty));
}
// METHODS //
bool IsPlayerIncapped(int client)
{
	if (GetEntProp(client, Prop_Send, "m_isIncapacitated", 1)) return true;
	return false;
}
bool IsPlayerNearDead(int client) {
	if (GetEntProp(client, Prop_Send, "m_bIsOnThirdStrike", 1)) return true;
	return false;
}

stock void GetModelName(int client, char[] buffer, int length) {
	char modelName[38];
	GetClientModel(client, modelName, sizeof(modelName));
	if(StrContains(modelName,"biker",false) > -1) {
		strcopy(buffer, length, "Francis"); 
	}else if(StrContains(modelName,"teenangst",false) > -1) {
		strcopy(buffer, length, "Zoey"); 
	}else if(StrContains(modelName,"namvet",false) > -1) {
		strcopy(buffer, length, "Bill"); 
	}else if(StrContains(modelName,"manager",false) > -1) {
		strcopy(buffer, length, "Louis"); 
	}else if(StrContains(modelName,"coach",false) > -1) {
		strcopy(buffer, length, "Coach"); 
	}else if(StrContains(modelName,"producer",false) > -1) {
		strcopy(buffer, length, "Rochelle"); 
	}else if(StrContains(modelName,"gambler",false) > -1) {
		strcopy(buffer, length, "Nick"); 
	}else if(StrContains(modelName,"mechanic",false) > -1) {
		strcopy(buffer, length, "Ellis"); 
	}
}

stock GetClientRealHealth(client)
{
    //First filter -> Must be a valid client, successfully in-game and not an spectator (The dont have health).
    if(!client
    || !IsValidEntity(client)
    || !IsClientInGame(client)
    || !IsPlayerAlive(client)
    || IsClientObserver(client))
    {
        return -1;
    }
    
    //If the client is not on the survivors team, then just return the normal client health.
    if(GetClientTeam(client) != 2)
    {
        return GetClientHealth(client);
    }
    
    //First, we get the amount of temporal health the client has
    float buffer = GetEntPropFloat(client, Prop_Send, "m_healthBuffer");
    
    //We declare the permanent and temporal health variables
    float TempHealth;
    int PermHealth = GetClientHealth(client);
    
    //In case the buffer is 0 or less, we set the temporal health as 0, because the client has not used any pills or adrenaline yet
    if(buffer <= 0.0)
    {
        TempHealth = 0.0;
    }
    
    //In case it is higher than 0, we proceed to calculate the temporl health
    else
    {
        //This is the difference between the time we used the temporal item, and the current time
        float difference = GetGameTime() - GetEntPropFloat(client, Prop_Send, "m_healthBufferTime");
        
        //We get the decay rate from this convar (Note: Adrenaline uses this value)
        float decay = GetConVarFloat(FindConVar("pain_pills_decay_rate"));
        
        //This is a constant we create to determine the amount of health. This is the amount of time it has to pass
        //before 1 Temporal HP is consumed.
        float constant = 1.0/decay;
        
        //Then we do the calcs
        TempHealth = buffer - (difference / constant);
    }
    
    //If the temporal health resulted less than 0, then it is just 0.
    if(TempHealth < 0.0)
    {
        TempHealth = 0.0;
    }
    
    //Return the value
    return RoundToFloor(PermHealth + TempHealth);
}  