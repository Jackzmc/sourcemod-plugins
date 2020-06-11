#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#define PLUGIN_VERSION "1.4" 

static bool bEscapeReady = false;
static int TankClient; 
//static ConVar hTankDangerDistance;

public Plugin myinfo =
{
    name = "Fly You Fools",
    author = "ConnerRia & Jackzmc",
    description = "Survivor bots will retreat from tank. ",
    version = PLUGIN_VERSION,
    url = "N/A"
}

public OnPluginStart()
{
	EngineVersion g_Game = GetEngineVersion();
	if(g_Game != Engine_Left4Dead && g_Game != Engine_Left4Dead2)
	{		
		SetFailState("Plugin supports Left 4 Dead series only.");
	}
	
	CreateConVar("FlyYouFools_Version", PLUGIN_VERSION, "FlyYouFools Version", FCVAR_NOTIFY|FCVAR_REPLICATED|FCVAR_DONTRECORD);
	//hTankDangerDistance = CreateConVar("200IQBots_TankDangerRange", "800.0", "The range by which survivors bots will detect the presence of tank and retreat. ", FCVAR_NOTIFY|FCVAR_REPLICATED);
	
	HookEvent("map_transition", Event_RoundStart, EventHookMode_Pre);	
	HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
	HookEvent("tank_spawn", Event_TankSpawn);
	HookEvent("tank_killed", Event_RoundStart);	
	HookEvent("finale_vehicle_incoming", Event_FinaleArriving);
	
	AutoExecConfig(true, "200IQBots_FlyYouFools");
	
	FindExistingTank();
}

public OnMapStart() {
	TankClient = -1;
	bEscapeReady  = false;
}	

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast) {
	TankClient = -1;
	bEscapeReady  = false;
}

public void Event_TankSpawn(Event event, const char[] name, bool dontBroadcast) {
	TankClient = GetClientOfUserId(GetEventInt(event, "userid"));
	CreateTimer(0.1, BotControlTimer, _, TIMER_REPEAT);
}
public void Event_FinaleArriving(Event event, const char[] name, bool dontBroadcast) {
	bEscapeReady  = true;
}
public Action BotControlTimer(Handle timer)
{
	//remove timer once tank no longer exists, is dead, or finale escape vehicle arrived
	if(bEscapeReady || TankClient == -1 || !IsClientInGame(TankClient) || !IsPlayerAlive(TankClient)) {
		return Plugin_Stop;
	}
	//Once an AI tank is awakened, m_lookatPlayer is set to a player ID
	//Possible props: m_lookatPlayer, m_zombieState, m_hasVisibleThreats
	int tank_target = GetEntPropEnt(TankClient, Prop_Send, "m_lookatPlayer", 0);
	//bool hasVisibleThreats = GetEntProp(TankClient, Prop_Send, "m_hasVisibleThreats", 1) == 1;
	//char targetted_name[64];
	if(tank_target > -1) {
		//debug shit:
		//GetClientName(tank_target, targetted_name, sizeof(targetted_name));
		//ShowHintToAll("tank_target: %d (%s) | visible threats: %b", tank_target, targetted_name, hasVisibleThreats);
		for (new i = 1; i <= MaxClients; i++)
		{
			if (IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == 2 && IsFakeClient(i))
			{	
				//If distance between bot and tank is less than 200IQBots_TankDangerRange's float value
				//if not tank target, and tank != visible threats, then attack
				if(tank_target == i) {
					L4D2_RunScript("CommandABot({cmd=2,bot=GetPlayerFromUserID(%i),target=GetPlayerFromUserID(%i)})", GetClientUserId(i), GetClientUserId(TankClient));
				}else {
					float TankPosition[3];
					float BotPosition[3];
					
					GetClientAbsOrigin(TankClient, TankPosition);
					GetClientAbsOrigin(i, BotPosition);
					
					float distance = GetVectorDistance(BotPosition, TankPosition);
					if(distance < 200) {
						L4D2_RunScript("CommandABot({cmd=2,bot=GetPlayerFromUserID(%i),target=GetPlayerFromUserID(%i)})", GetClientUserId(i), GetClientUserId(TankClient));
						//do not attack if super close.
					} else {
						L4D2_RunScript("CommandABot({cmd=0,bot=GetPlayerFromUserID(%i),target=GetPlayerFromUserID(%i)})", GetClientUserId(i), GetClientUserId(TankClient));
					}
				}
				
			}
		}	 
	}	
	return Plugin_Continue;
}



public void FindExistingTank() {
	for (int i = 1; i < MaxClients+1 ;i++) {
		if (!IsClientInGame(i)) continue;
		if (!IsFakeClient(i)) continue;
		char name[16];
		GetClientName(i, name, sizeof(name));
		
		if(StrContains(name,"Tank",true) > -1) {
			PrintToServer("Found existing tank with id %d", i);
			TankClient = i;
			CreateTimer(0.1, BotControlTimer, _, TIMER_REPEAT);
			break;
		}
	}
}

//Credits to Timocop for the stock :D
/**
* Runs a single line of vscript code.
* NOTE: Dont use the "script" console command, it starts a new instance and leaks memory. Use this instead!
*
* @param sCode		The code to run.
* @noreturn
*/
stock void L4D2_RunScript(const char[] sCode, any ...) {
	static iScriptLogic = INVALID_ENT_REFERENCE;
	if(iScriptLogic == INVALID_ENT_REFERENCE || !IsValidEntity(iScriptLogic)) {
		iScriptLogic = EntIndexToEntRef(CreateEntityByName("logic_script"));
		if(iScriptLogic == INVALID_ENT_REFERENCE || !IsValidEntity(iScriptLogic))
			SetFailState("Could not create 'logic_script'");
		
		DispatchSpawn(iScriptLogic);
	}
	
	static char sBuffer[512];
	VFormat(sBuffer, sizeof(sBuffer), sCode, 2);
	
	SetVariantString(sBuffer);
	AcceptEntityInput(iScriptLogic, "RunScriptCode");
}
stock void ShowHintToAll(const char[] format, any ...) {
	char buffer[254];
	VFormat(buffer, sizeof(buffer), format, 2);
	static int hintInt = 0;
	if(hintInt >= 9) {
		PrintHintTextToAll("%s",buffer);
		hintInt = 0;
	}
	hintInt++;
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
stock bool GetItemClassSlot(int client, int slot, char[] buffer, int bufferSize) {
	int item = GetPlayerWeaponSlot(client, slot);
	if(item > -1) {
		GetEdictClassname(item, buffer, bufferSize);
		return true;
	}else{
		return false;
	}
}