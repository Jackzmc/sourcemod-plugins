#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_NAME "Better Witch Avoidance"
#define PLUGIN_DESCRIPTION "Makes bots avoid witches better"
#define PLUGIN_AUTHOR "jackzmc"
#define PLUGIN_VERSION "1.0"
#define PLUGIN_URL ""

#include <sourcemod>
#include <sdktools>
//#include <sdkhooks>


public Plugin myinfo = 
{
	name = PLUGIN_NAME, 
	author = PLUGIN_AUTHOR, 
	description = PLUGIN_DESCRIPTION, 
	version = PLUGIN_VERSION, 
	url = PLUGIN_URL
};

static int iWitchEntity = -1;

public void OnPluginStart()
{
	EngineVersion g_Game = GetEngineVersion();
	if(g_Game != Engine_Left4Dead && g_Game != Engine_Left4Dead2)
	{
		SetFailState("This plugin is for L4D/L4D2 only.");	
	}
	HookEvent("witch_spawn", Event_WitchSpawn);
	HookEvent("witch_killed", Event_WitchKilled, EventHookMode_PostNoCopy);
	//todo: existing witch find
	//m_rage
}


public void Event_WitchSpawn(Event event, const char[] name, bool dontBroadcast) {
	iWitchEntity = GetEventInt(event, "witchid");
	CreateTimer(0.1, BotControlTimer, _, TIMER_REPEAT);
}

public void Event_WitchKilled(Event event, const char[] name, bool dontBroadcast) {
	iWitchEntity = -1;
}
public Action BotControlTimer(Handle timer)
{
	//remove timer once witch is dead 
	if(iWitchEntity == -1 || !IsValidEntity(iWitchEntity)) {
		//incase any other witches are available
		//FindExistingWitch();
		return Plugin_Stop;
	}
	if(HasEntProp(iWitchEntity,Prop_Send,"m_rage")) {
		float witch_anger = GetEntPropFloat(iWitchEntity, Prop_Send, "m_rage", 0);
		if(FloatCompare(witch_anger,0.4) == 1) {
			float WitchPosition[3];
			GetEntPropVector(iWitchEntity, Prop_Send, "m_vecOrigin", WitchPosition);
			for (int i = 1; i < MaxClients; i++) {
				if (IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == 2 && IsFakeClient(i)) {
					float BotPosition[3];
					GetClientAbsOrigin(i, BotPosition);
					
					float distance = GetVectorDistance(BotPosition, WitchPosition);
					if(distance <= 120 || (FloatCompare(witch_anger,0.6) == 1 && distance <= 220)) {
						L4D2_RunScript("CommandABot({cmd=2,bot=GetPlayerFromUserID(%i),target=EntIndexToHScript(%d)})", GetClientUserId(i), iWitchEntity);
					}
				}
			}
		}
	}
	
	return Plugin_Handled;
}
public void FindExistingWitch() {
	for (int i = MaxClients + 1; i < GetMaxEntities(); i++) {
		if(IsValidEntity(i)) {
			char name[16];
			GetEntityClassname(i, name, sizeof(name));
			if(StrContains(name,"Witch",true) > -1) {
				PrintToServer("Found existing witch with id %d", i);
				iWitchEntity = i;
				CreateTimer(0.1, BotControlTimer, _, TIMER_REPEAT);
				break;
			}
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