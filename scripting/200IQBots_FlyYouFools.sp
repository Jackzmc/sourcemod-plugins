#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#define PLUGIN_VERSION "1.5" 
#pragma newdecls required

//#define DEBUG

static bool bEscapeReady = false;
static int iAliveTanks; 
static bool bIsTank[MAXPLAYERS+1];

public Plugin myinfo =
{
    name = "Fly You Fools",
    author = "ConnerRia & Jackzmc",
    description = "Survivor bots will retreat from tank. Improved version.",
    version = PLUGIN_VERSION,
    url = "N/A"
}


public void OnPluginStart()
{
	EngineVersion g_Game = GetEngineVersion();
	if(g_Game != Engine_Left4Dead && g_Game != Engine_Left4Dead2)
	{		
		SetFailState("Plugin supports Left 4 Dead series only.");
	}
	
	CreateConVar("FlyYouFools_Version", PLUGIN_VERSION, "FlyYouFools Version", FCVAR_NOTIFY|FCVAR_REPLICATED|FCVAR_DONTRECORD);
	
	HookEvent("map_transition", Event_RoundStart, EventHookMode_PostNoCopy);	
	HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
	HookEvent("tank_spawn", Event_TankSpawn);
	HookEvent("tank_killed", Event_TankDeath);
	HookEvent("tank_killed", Event_RoundStart, EventHookMode_PostNoCopy);	
	HookEvent("finale_vehicle_incoming", Event_FinaleArriving, EventHookMode_PostNoCopy);
}


public void OnMapStart() {
	resetPlugin();
}	

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast) {
	resetPlugin();
}

public void Event_TankSpawn(Event event, const char[] name, bool dontBroadcast) {
	int userID = GetClientOfUserId(GetEventInt(event, "userid"));
	bIsTank[userID] = true;
	if(iAliveTanks == 0 && !bEscapeReady) {
		CreateTimer(0.1, BotControlTimerV2, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	}
	iAliveTanks++;
}
public void Event_TankDeath(Event event, const char[] name, bool dontBroadcast) {
	int userID = GetClientOfUserId(GetEventInt(event, "userid"));
	bIsTank[userID] = false;
	iAliveTanks--;
}
public void Event_FinaleArriving(Event event, const char[] name, bool dontBroadcast) {
	bEscapeReady = true;
}
/*
CommandABot:
0 -> ATTACK
1 -> MOVETO
2 -> RUN AWAY
3 -> RESET

New logic overview:
1. Loop all valid survivors
2. Loop all tanks per survivor
3. Find the closest tank
4. Retreat if in close range (~300 units)
*/
//TODO: possibly check if multiple loops being created
public Action BotControlTimerV2(Handle timer)
{
	//remove timer once tanks no longer exists/are all dead or finale escape vehicle arrived
	if(bEscapeReady || iAliveTanks == 0) {
		//Check if there is any existing bots, if escape NOT ready
		if(!bEscapeReady) FindExistingTank();
		return Plugin_Stop;
	}
	if(iAliveTanks == 0) return Plugin_Continue;

	int botHealth, closestTank, tank_target, distanceFromSurvivor;
	float BotPosition[3], TankPosition[3], smallestDistance;

	//Loop all players, finding survivors. (survivor team, bots, not tank.)
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i) && IsPlayerAlive(i) && IsFakeClient(i) && !bIsTank[i] && GetClientTeam(i) == 2) {	
			//Grab health of bot and current position
			botHealth = GetClientHealth(i);
			GetClientAbsOrigin(i, BotPosition);

			smallestDistance = 0.0;
			closestTank = -1;
			//Loop all players, finding tanks (alive, bot, tank)
			for(int tankID = 1; tankID <= MaxClients; tankID++) {
				if (IsClientInGame(tankID) && IsPlayerAlive(tankID) && IsFakeClient(tankID) && bIsTank[tankID]) {	
					//Check if tank has a target. tank_target will be -1 if not activated
					tank_target = GetEntPropEnt(tankID, Prop_Send, "m_lookatPlayer", 0);
					if(tank_target > -1) {
						
						//Fetch the tank's position
						GetClientAbsOrigin(tankID, TankPosition);
						//Get distance to survivor, and compare to get closest tank
						distanceFromSurvivor = GetVectorDistance(BotPosition, TankPosition);
						if(distanceFromSurvivor <= 1000 && smallestDistance > distanceFromSurvivor || smallestDistance == 0.0) {
							smallestDistance = distanceFromSurvivor;
							closestTank = tankID;
						}
						
					}
				}
			}
			//If the closest tank exists (-1 means no tank.) and is close, avoid.
			//TODO: Possibly only run if they have an item in the pill shot, or have medkit.
			if(closestTank > -1 && smallestDistance <= 300 && botHealth >= 40) {
				//L4D2_RunScript("CommandABot({cmd=3,bot=GetPlayerFromUserID(%i)})", GetClientUserId(i));
				L4D2_RunScript("CommandABot({cmd=2,bot=GetPlayerFromUserID(%i),target=GetPlayerFromUserID(%i)})", GetClientUserId(i), GetClientUserId(closestTank));
			}
		}
	}
	return Plugin_Continue;
}

void resetPlugin() {
	bEscapeReady = false;
	iAliveTanks = 0;
	FindExistingTank();
}


public void FindExistingTank() {
	//Loop all valid clients, check if they a BOT and an infected. Check for a name that contains "Tank"
	iAliveTanks = 0;
	char name[16];
	for (int i = 1; i < MaxClients+1 ;i++) {
		if(IsClientInGame(i) && IsFakeClient(i) && IsPlayerAlive(i) && GetClientTeam(i) == 3) {
			GetClientName(i, name, sizeof(name));
			if(StrContains(name, "Tank", true) > -1) {
				bIsTank[i] = true;
				//PrintToServer("Found existing tank: %N (%i)", i, i);
				iAliveTanks++;
				continue;
			}
		}
		bIsTank[i] = false;
		
	}
	if(iAliveTanks > 0) {
		CreateTimer(0.1, BotControlTimerV2, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
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
/**
* Get the classname of an item in a slot
*
* @param client 		The client to check inventory from
* @param slot			The item slot index
* @param buffer     	The char[] buffer to set text to
* @param bufferSize 	The size of the buffer
* @return				True if item, false if no item
*/
stock bool GetItemSlotClassName(int client, int slot, char[] buffer, int bufferSize) {
	int item = GetPlayerWeaponSlot(client, slot);
	if(item > -1) {
		GetEdictClassname(item, buffer, bufferSize);
		return true;
	}else{
		return false;
	}
}
