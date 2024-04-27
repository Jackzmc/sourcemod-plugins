#pragma semicolon 1
#pragma newdecls required

#define CLOWN_MUSIC_THRESHOLD 30

//#define DEBUG

#define PLUGIN_VERSION "1.0"

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <anymap>

public Plugin myinfo = 
{
	name =  "L4D2 Population Control", 
	author = "jackzmc", 
	description = "", 
	version = PLUGIN_VERSION, 
	url = "https://github.com/Jackzmc/sourcemod-plugins"
};

static ConVar hPercentTotal;
static ConVar hPercentClown;
static ConVar hPercentMud;
static ConVar hPercentCeda;
static ConVar hPercentWorker;
static ConVar hPercentRiot;
static ConVar hPercentJimmy;
static ConVar hTotalZombies;
static ConVar hZCommonLimit;

static bool IsDoneLoading, clownMusicPlayed;

static int iCurrentCommons, commonLimit, clownCommonsSpawned;
static AnyMap commonType;

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
enum CommonType {
	Common_Worker = -2,
	Common_Any = -1,
	Common_Clown,
	Common_Mud,
	Common_Ceda,
	Common_Riot,
	Common_Jimmy,
	Common_Fallen,
};

//TODO: Add back survivor zombie, inc z_fallen_max_count 

public void OnPluginStart() {
	EngineVersion g_Game = GetEngineVersion();
	if(g_Game != Engine_Left4Dead2) {
		SetFailState("This plugin is for L4D2 only.");	
	}

	commonType = new AnyMap();

	HookEvent("game_start", OnGameStart);

	hPercentTotal  = CreateConVar("l4d2_population_global_chance", "1.0", "The % chance that any the below chances occur.\n0.0 = NEVER, 1.0: ALWAYS");
	hPercentClown  = CreateConVar("l4d2_population_clowns", "0.0", "The % chance that a common spawns as a clown.\n0.0 = OFF, 1.0 = ALWAYS", FCVAR_NONE, true, 0.0, true, 1.0);
	hPercentMud    = CreateConVar("l4d2_population_mud", "0.0", "The % chance that a common spawns as a mud zombie.\n0.0 = OFF, 1.0 = ALWAYS", FCVAR_NONE, true, 0.0, true, 1.0);
	hPercentCeda   = CreateConVar("l4d2_population_ceda", "0.0", "The % chance that a common spawns as a ceda zombie.\n0.0 = OFF, 1.0 = ALWAYS", FCVAR_NONE, true, 0.0, true, 1.0);
	hPercentWorker = CreateConVar("l4d2_population_worker", "0.0", "The % chance that a common spawns as a worker zombie.\n0.0 = OFF, 1.0 = ALWAYS", FCVAR_NONE, true, 0.0, true, 1.0);
	hPercentRiot   = CreateConVar("l4d2_population_riot", "0.0", "The % chance that a common spawns as a riot zombie.\n0.0 = OFF, 1.0 = ALWAYS", FCVAR_NONE, true, 0.0, true, 1.0);
	hPercentJimmy  = CreateConVar("l4d2_population_jimmy", "0.0", "The % chance that a common spawns as a Jimmy Gibs Jr. zombie.\n0.0 = OFF, 1.0 = ALWAYS", FCVAR_NONE, true, 0.0, true, 1.0);
	hTotalZombies  = CreateConVar("l4d2_population_common", "0.0", "The maximum amount of commons, anymore will be deleted.\n0 = Turn Off\n> 0: Fixed limit\n< 0: z_common_limit + absolute value", FCVAR_NONE);
	hZCommonLimit  = FindConVar("z_common_limit");

	hTotalZombies.AddChangeHook(CVAR_hTotalZombiesChanged);
	CVAR_hTotalZombiesChanged(hTotalZombies, "0", "0");

	//HookEvent("infected_death", Event_InfectedDeath);

	RegConsoleCmd("sm_population_list", Cmd_List, "Lists the current population percentages", FCVAR_NONE);
	RegConsoleCmd("sm_populations", Cmd_List, "Lists the current population percentages", FCVAR_NONE);

	//AutoExecConfig(true, "l4d2_population_control");
}

public void OnGameStart(Event event, const char[] name, bool dontBroadcast) {
	hPercentTotal.FloatValue = 1.0;
	hPercentClown.FloatValue = 0.0;
	hPercentMud.FloatValue = 0.0;
	hPercentCeda.FloatValue = 0.0;
	hPercentWorker.FloatValue = 0.0;
	hPercentRiot.FloatValue = 0.0;
	hPercentJimmy.FloatValue = 0.0;
	hTotalZombies.FloatValue = 0.0;
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
	iCurrentCommons = 0;
	clownCommonsSpawned = 0;
	commonType.Clear();
}

public void CVAR_hTotalZombiesChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
	if(hTotalZombies.IntValue > 0) {
		commonLimit = hTotalZombies.IntValue;
	} else if(hTotalZombies.IntValue < 0) {
		commonLimit = hZCommonLimit.IntValue - hTotalZombies.IntValue;
	} else {
		commonLimit = 0;
	}
}

//TODO: Setup music to play when % of clowns are in

public void OnEntityCreated(int entity, const char[] classname) {
	if (StrEqual(classname, "infected") && IsDoneLoading) {
		SDKHook(entity, SDKHook_SpawnPost, Hook_SpawnPost);

		// char m_ModelName[PLATFORM_MAX_PATH];
		// GetEntPropString(entity, Prop_Data, "m_ModelName", m_ModelName, sizeof(m_ModelName));
		if(GetRandomFloat() <= hPercentTotal.FloatValue) {
			if(GetRandomFloat() <= hPercentClown.FloatValue) {
				SetEntityModel(entity, INFECTED_MODELS[Common_Clown]);
				commonType.SetValue(entity, Common_Clown);
			}else if(GetRandomFloat() <= hPercentMud.FloatValue) {
				SetEntityModel(entity, INFECTED_MODELS[Common_Mud]);
				commonType.SetValue(entity, Common_Mud);
			}else if(GetRandomFloat() <= hPercentCeda.FloatValue) {
				SetEntityModel(entity, INFECTED_MODELS[Common_Ceda]);
				commonType.SetValue(entity, Common_Ceda);
			}else if(GetRandomFloat() <= hPercentWorker.FloatValue) {
				//worker has multiple models:
				SetEntityModel(entity, WORKER_MODELS[GetRandomInt(0,2)]);
				commonType.SetValue(entity, Common_Worker);
			}else if(GetRandomFloat() <= hPercentRiot.FloatValue) {
				SetEntityModel(entity, INFECTED_MODELS[Common_Riot]);
				commonType.SetValue(entity, Common_Riot);
			}else if(GetRandomFloat() <= hPercentJimmy.FloatValue) {
				SetEntityModel(entity, INFECTED_MODELS[Common_Jimmy]);
				commonType.SetValue(entity, Common_Jimmy);
			}else{
				commonType.SetValue(entity, Common_Any);
			}
		}else{
			commonType.SetValue(entity, Common_Any);
		}
	}
}

public Action Hook_SpawnPost(int entity) {
	if(commonLimit != 0) {
		if(iCurrentCommons >= commonLimit) {
			AcceptEntityInput(entity, "Kill");
			return Plugin_Continue;
		}
	}
	++iCurrentCommons;
	CommonType type;
	if(commonType.GetValue(entity, type) && type == Common_Clown) {
		if(++clownCommonsSpawned > CLOWN_MUSIC_THRESHOLD && !clownMusicPlayed) {
			clownMusicPlayed = true;
			EmitSoundToAll("custom/clown.mp3");
			//Play music
		}
	}
	return Plugin_Continue;
} 

// public Action Event_InfectedDeath(Event event, const char[] name, bool dontBroadcast) {
// 	--iCurrentCommons;
// 	if(commonType[entity] == 2) {
// 		--clownCommonsSpawned;
// 	}
// }

public void OnEntityDestroyed(int entity) {
	if(entity > 0 && entity <= 2048 && commonType.ContainsKey(entity)) {
		CommonType type;
		if(commonType.GetValue(entity, type) && type == Common_Clown) {
			--clownCommonsSpawned;
		}
		commonType.Remove(entity);
		if(--iCurrentCommons < CLOWN_MUSIC_THRESHOLD - 10) {
			clownMusicPlayed = false;
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
	ReplyToCommand(client, "%d total commons allowed", commonLimit);
	return Plugin_Handled;
}