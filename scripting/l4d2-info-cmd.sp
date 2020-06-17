#pragma semicolon 1

#define debug false

#define PLUGIN_NAME "L4D2 Game Info"
#define PLUGIN_DESCRIPTION ""
#define PLUGIN_AUTHOR "jackzmc"
#define PLUGIN_VERSION "1.1"

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

char g_icDifficulty[16] = "Normal";
char g_icGamemode[16] = "coop";
char g_icCurrentMap[32];

int g_icPlayerManager; //entid -> typically 25 (MaxClients+1)

bool g_icHealing[MAXPLAYERS+1]; //state
bool g_icBeingHealed[MAXPLAYERS+1]; //state

ConVar g_icCouponCode, g_icCouponCoins;

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
	
	//hook events & cmds
	RegConsoleCmd("sm_gameinfo", PrintGameInfo, "Show the director main menu");
	HookEvent("difficulty_changed", Event_DifficultyChanged);
	HookEvent("heal_begin", Event_HealStart);
	//HookEvent("heal_end", Event_HealStop);
	HookEvent("heal_success", Event_HealStop);
	HookEvent("heal_interrupted", Event_HealStop);
	
	//hook cvars, game info states
	FindConVar("z_difficulty").GetString(g_icDifficulty, sizeof(g_icDifficulty));
	ConVar ic_gamemode = FindConVar("mp_gamemode"); 
	ic_gamemode.GetString(g_icGamemode, sizeof(g_icGamemode));
	if (ic_gamemode != null) ic_gamemode.AddChangeHook(Event_GamemodeChange);
	GetCurrentMap(g_icCurrentMap, sizeof(g_icCurrentMap));
	
	AutoExecConfig();
	
	//setup advertisement
	CreateConVar("l4d2_gameinfo_version", PLUGIN_VERSION, "plugin version", FCVAR_SPONLY | FCVAR_DONTRECORD);
	g_icCouponCode = CreateConVar("l4d2_gameinfo_code","","Provide a coupon code");
	g_icCouponCoins = CreateConVar("l4d2_gameinfo_coins","0","Provide a coupon code's zekoins", FCVAR_NONE, true, 0.0);
	CreateTimer(400.0, Timer_PrintInfoMessage, _, TIMER_REPEAT);
}
// print info
public Action Timer_PrintInfoMessage(Handle timer)
{
	PrintToChatAll("This is the Manual Director server. Access the panel, and info about the server at l4d2.jackz.me");
	return Plugin_Continue;
}
public Action PrintGameInfo(int client, int args) {
	//print server info
	ReplyToCommand(client, ">map,diff,mode,tempoState,totalSeconds");
	int missionDuration = GetEntProp(g_icPlayerManager, Prop_Send, "m_missionDuration", 1);
	int tempoState = GetEntProp(g_icPlayerManager, Prop_Send, "m_tempoState", 1);
	ReplyToCommand(client, "%s,%s,%s,%d,%d",g_icCurrentMap,g_icDifficulty,g_icGamemode,tempoState,missionDuration);
	//print client info
	ReplyToCommand(client,">id,name,bot,health,status,throwSlot,kitSlot,pillSlot,modelName,velocity");
	for (int i = 1; i < MaxClients;i++) {
		if (!IsClientInGame(i)) continue;
		if (GetClientTeam(i) != 2) continue;
		int hp = GetClientRealHealth(i);
		int bot = IsFakeClient(i);
		bool crouched = GetEntProp(i, Prop_Send, "m_bDucked", 1) == 1;
		bool incap = GetEntProp(i, Prop_Send, "m_isIncapacitated", 1) == 1;
		bool blackandwhite = GetEntProp(i, Prop_Send, "m_bIsOnThirdStrike", 1) == 1;
		int velocity = RoundFloat(GetPlayerSpeed(i));
		
		char status[9];
		char name[32];
		char pillItem[32];
		char kitItem[32];
		char throwItem[32];
		char character[9];
		
		if(hp < 0) {
			status = "dead";
		}else if(incap) {
			status = "incap";
		}else if(blackandwhite) {
			status = "neardead";
		}else if(g_icHealing[i]) {
			status = "healing";
		}else if(g_icBeingHealed[i]) {
			status = "bheal";
		}else if(crouched) {
			status = "crouched";
		}else{
			status = "alive";
		}
		GetItemSlotClassName(i, 2, throwItem, sizeof(throwItem), true);
		GetItemSlotClassName(i, 3, kitItem, sizeof(kitItem), true);
		GetItemSlotClassName(i, 4, pillItem, sizeof(pillItem), true);
		
		GetClientName(i, name, sizeof(name));
		GetModelName(i, character, sizeof(character));
		
		ReplyToCommand(client,"%d,%s,%d,%d,%s,%s,%s,%s,%s,%d", i, name, bot, hp, status, throwItem, kitItem, pillItem, character, velocity);
	}
	
}
// EVENTS //
public void Event_GamemodeChange(ConVar cvar, const char[] oldValue, const char[] newValue) {
	cvar.GetString(g_icGamemode, sizeof(g_icGamemode));
}
public void OnMapStart() {
	GetCurrentMap(g_icCurrentMap, sizeof(g_icCurrentMap));
	//grab the player_manager
	//int playerManager;
	for (int i = MaxClients + 1; i < GetMaxEntities(); i++) {
		if(Entity_ClassNameMatches(i, "_player_manager", true)) {
			g_icPlayerManager = i;
			break;
		}
	}
	if(g_icPlayerManager == -1) {
		SetFailState("Unable to find \"*_player_manager\" entity");
	}
	#if debug
	SDKHook(g_icPlayerManager, SDKHook_ThinkPost, PlayerManager_OnThinkPost);
	#endif
}
public void Event_DifficultyChanged(Event event, const char[] name, bool dontBroadcast) {
	event.GetString("newDifficulty",g_icDifficulty,sizeof(g_icDifficulty));
}
public void Event_HealStart(Event event, const char[] name, bool dontBroadcast) {
	int healer = GetClientOfUserId(event.GetInt("userid"));
	int healing = GetClientOfUserId(event.GetInt("subject"));
	g_icHealing[healer] = true;
	g_icBeingHealed[healing] = true;
}
public void Event_HealStop(Event event, const char[] name, bool dontBroadcast) {
	int healer = GetClientOfUserId(event.GetInt("userid"));
	int healing = GetClientOfUserId(event.GetInt("subject"));
	g_icHealing[healer] = false;
	g_icBeingHealed[healing] = false;
}
#if debug
int g_ichuddelay = 0;
public PlayerManager_OnThinkPost(int playerManager) {
	if(g_ichuddelay == 0) {
		int missionDuration = GetEntProp(playerManager, Prop_Send, "m_missionDuration", 1);
		int tempoState = GetEntProp(playerManager, Prop_Send, "m_tempoState", 1);
		PrintHintTextToAll("temp: %d | duration: %d", tempoState, missionDuration);
	}
	if (++g_ichuddelay >= 10) g_ichuddelay = 0;
}
#endif
public OnClientPutInServer(client)
{
	PrintToChat(client, "Welcome to the Manual Director server! For information or access the panel go to l4d2.jackz.me.");
	char coupon[9]; 
	g_icCouponCode.GetString(coupon, sizeof(coupon));
	if(strlen(coupon) > 0) {
		char coins[32] = "free";
		if (g_icCouponCoins.IntValue > 0) IntToString(g_icCouponCoins.IntValue, coins, sizeof(coins));
		PrintToChat(client, "Signup with redemption code '%s' for %s initial coins", coupon, coins);
	}
	
}
// METHODS //
stock float GetPlayerSpeed(int client) {
	int iVelocity = FindSendPropInfo("CTerrorPlayer", "m_vecVelocity[0]");
	float velocity[3];
	GetEntDataVector(client, iVelocity, velocity);
	return GetVectorLength(velocity, false);
	/*float x = GetEntPropFloat(client, Prop_Send, "m_vecVelocity[0]", 0);
	float y = GetEntPropFloat(client, Prop_Send, "m_vecVelocity", 1);
	float z = GetEntPropFloat(client, Prop_Send, "m_vecVelocity", 2);
	
	return SquareRoot(x * x + y * y + z * z);
	//eturn GetVectorLength(vector, false);*/
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
stock bool Entity_ClassNameMatches(entity, const char[] className, partialMatch=false)
{
	char entity_className[64];
	Entity_GetClassName(entity, entity_className, sizeof(entity_className));

	if (partialMatch) {
		return (StrContains(entity_className, className) != -1);
	}

	return StrEqual(entity_className, className);
}
stock Entity_GetClassName(entity, char[] buffer, size)
{
	return GetEntPropString(entity, Prop_Data, "m_iClassname", buffer, size);
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
/**
* Get the classname of an item in a slot
*
* @param client 		The client to check inventory from
* @param slot			The item slot index
* @param buffer     	The char[] buffer to set text to
* @param bufferSize 	The size of the buffer
* @return				True if item, false if no item
*/
stock bool GetItemSlotClassName(int client, int slot, char[] buffer, int bufferSize, bool excludeWpnPrefix = false) {
	int item = GetPlayerWeaponSlot(client, slot);
	if(item > -1) {
		GetEdictClassname(item, buffer, bufferSize);
		if(excludeWpnPrefix) {
			ReplaceString(buffer, bufferSize, "weapon_", "");
		}
		return true;
	}else{
		return false;
	}
}