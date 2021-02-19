#pragma semicolon 1
#pragma newdecls required

//#define DEBUG

#define PLUGIN_VERSION "1.0"

#include <sourcemod>
#include <sdktools>
//#include <sdkhooks>

public Plugin myinfo = 
{
	name =  "L4D2 Population Control", 
	author = "jackzmc", 
	description = "", 
	version = PLUGIN_VERSION, 
	url = ""
};

static ConVar hPercentTotal;
static ConVar hPercentClown;
static ConVar hPercentMud;

public void OnPluginStart() {
	EngineVersion g_Game = GetEngineVersion();
	if(g_Game != Engine_Left4Dead2) {
		SetFailState("This plugin is for L4D2 only.");	
	}
	PrecacheModel("models/infected/common_male_clown.mdl");
	PrecacheModel("models/infected/common_male_mud.mdl");


	hPercentTotal = CreateConVar("l4d2_population_global_chance", "1.0", "The % chance that any the below chances occur.\n0.0 = NEVER, 1.0: ALWAYS");
	hPercentClown = CreateConVar("l4d2_population_clowns", "0.0", "The % chance that a common spawns as a clown.\n0.0 = OFF, 1.0 = ALWAYS", FCVAR_NONE, true, 0.0, true, 1.0);
	hPercentMud = CreateConVar("l4d2_population_mud", "0.0", "The % chance that a common spawns as a mud zombie.\n0.0 = OFF, 1.0 = ALWAYS", FCVAR_NONE, true, 0.0, true, 1.0);
}

public void OnEntityCreated(int entity, const char[] classname) {
	if (StrEqual(classname, "infected")) {
		char m_ModelName[PLATFORM_MAX_PATH];
		GetEntPropString(entity, Prop_Data, "m_ModelName", m_ModelName, sizeof(m_ModelName));
		PrintToConsoleAll("Infected -> %s", m_ModelName);
		if(GetRandomFloat() <= hPercentTotal.FloatValue) {
			float spawnPercentage = GetRandomFloat();
			if(spawnPercentage <= hPercentClown.FloatValue) {
				SetEntityModel(entity, "models/infected/common_male_clown.mdl");
			}else if(spawnPercentage <= hPercentMud.FloatValue) {
				SetEntityModel(entity, "models/infected/common_male_mud.mdl");
			}
		}
	}
}