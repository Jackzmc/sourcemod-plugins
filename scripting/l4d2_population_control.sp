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
static ConVar hPercentCeda;
static ConVar hPercentWorker;
static ConVar hPercentRiot;
static ConVar hPercentJimmy;
static ConVar hPercentFallen;

static bool IsDoneLoading;

#define COMMON_MODELS_COUNT 6
static char INFECTED_MODELS[COMMON_MODELS_COUNT][] = {
	"models/infected/common_male_clown.mdl", //clown
	"models/infected/common_male_mud.mdl", //mud
	"models/infected/common_male_ceda.mdl", //ceda
	"models/infected/common_male_riot.mdl", //riot
	"models/infected/common_male_jimmy.mdl", //jimmy
	"models/infected/common_male_fallen_survivor.mdl", //fallen

};
static char WORKER_MODELS[3][] = {
	"models/infected/common_worker_male01.mdl",
	"models/infected/common_male_roadcrew.mdl",
	"models/infected/common_male_roadcrew_rain.mdl"
};
enum CommonTypes {
	Common_Clown,
	Common_Mud,
	Common_Ceda,
	Common_Riot,
	Common_Jimmy,
	Common_Worker = -1,
};

public void OnPluginStart() {
	EngineVersion g_Game = GetEngineVersion();
	if(g_Game != Engine_Left4Dead2) {
		SetFailState("This plugin is for L4D2 only.");	
	}

	hPercentTotal  = CreateConVar("l4d2_population_global_chance", "1.0", "The % chance that any the below chances occur.\n0.0 = NEVER, 1.0: ALWAYS");
	hPercentClown  = CreateConVar("l4d2_population_clowns", "0.0", "The % chance that a common spawns as a clown.\n0.0 = OFF, 1.0 = ALWAYS", FCVAR_NONE, true, 0.0, true, 1.0);
	hPercentMud    = CreateConVar("l4d2_population_mud", "0.0", "The % chance that a common spawns as a mud zombie.\n0.0 = OFF, 1.0 = ALWAYS", FCVAR_NONE, true, 0.0, true, 1.0);
	hPercentCeda   = CreateConVar("l4d2_population_ceda", "0.0", "The % chance that a common spawns as a ceda zombie.\n0.0 = OFF, 1.0 = ALWAYS", FCVAR_NONE, true, 0.0, true, 1.0);
	hPercentWorker = CreateConVar("l4d2_population_worker", "0.0", "The % chance that a common spawns as a worker zombie.\n0.0 = OFF, 1.0 = ALWAYS", FCVAR_NONE, true, 0.0, true, 1.0);
	hPercentRiot   = CreateConVar("l4d2_population_riot", "0.0", "The % chance that a common spawns as a riot zombie.\n0.0 = OFF, 1.0 = ALWAYS", FCVAR_NONE, true, 0.0, true, 1.0);
	hPercentJimmy  = CreateConVar("l4d2_population_jimmy", "0.0", "The % chance that a common spawns as a Jimmy Gibs Jr. zombie.\n0.0 = OFF, 1.0 = ALWAYS", FCVAR_NONE, true, 0.0, true, 1.0);

	RegConsoleCmd("sm_population_list", Cmd_List, "Lists the current population percentages", FCVAR_NONE);
	RegConsoleCmd("sm_populations", Cmd_List, "Lists the current population percentages", FCVAR_NONE);

	//AutoExecConfig(true, "l4d2_population_control");
}
public void OnMapStart() {
	for(int i = 0; i < COMMON_MODELS_COUNT; i++) {
		PrecacheModel(INFECTED_MODELS[i], true);
	}
	for(int i = 0; i < 3; i++) {
		PrecacheModel(WORKER_MODELS[i], true);
	}
	IsDoneLoading = true;
}
public void OnMapEnd() {
	IsDoneLoading = false;
}

public void OnEntityCreated(int entity, const char[] classname) {
	if (StrEqual(classname, "infected") && IsDoneLoading) {
		char m_ModelName[PLATFORM_MAX_PATH];
		GetEntPropString(entity, Prop_Data, "m_ModelName", m_ModelName, sizeof(m_ModelName));
		if(GetRandomFloat() <= hPercentTotal.FloatValue) {
			if(GetRandomFloat() <= hPercentClown.FloatValue) {
				SetEntityModel(entity, INFECTED_MODELS[Common_Clown]);
			}else if(GetRandomFloat() <= hPercentMud.FloatValue) {
				SetEntityModel(entity, INFECTED_MODELS[Common_Mud]);
			}else if(GetRandomFloat() <= hPercentCeda.FloatValue) {
				SetEntityModel(entity, INFECTED_MODELS[Common_Ceda]);
			}else if(GetRandomFloat() <= hPercentWorker.FloatValue) {
				//worker has multiple models:
				SetEntityModel(entity, WORKER_MODELS[GetRandomInt(0,2)]);
			}else if(GetRandomFloat() <= hPercentRiot.FloatValue) {
				SetEntityModel(entity, INFECTED_MODELS[Common_Riot]);
			}else if(GetRandomFloat() <= hPercentJimmy.FloatValue) {
				SetEntityModel(entity, INFECTED_MODELS[Common_Jimmy]);
			}
		}
	}
}

public Action Cmd_List(int client, int args) {
	ReplyToCommand(client, "L4D2 Population Chances");
	ReplyToCommand(client, "%.1f%% global chance", hPercentTotal.FloatValue * 100);
	ReplyToCommand(client, "%.1f%% Clowns", hPercentClown.FloatValue * 100);
	ReplyToCommand(client, "%.1f%% Mud Commons", hPercentMud.FloatValue * 100);
	ReplyToCommand(client, "%.1f%% Ceda Commons", hPercentCeda.FloatValue * 100);
	ReplyToCommand(client, "%.1f%% Worker Commons", hPercentWorker.FloatValue * 100);
	ReplyToCommand(client, "%.1f%% Riot Commons", hPercentRiot.FloatValue * 100);
	ReplyToCommand(client, "%.1f%% Jimmy Gibs", hPercentJimmy.FloatValue * 100);
	return Plugin_Handled;
}