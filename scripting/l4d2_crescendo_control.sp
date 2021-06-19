#pragma semicolon 1
#pragma newdecls required

#define DEBUG 0

#define PLUGIN_VERSION "1.0"

#define PANIC_DETECT_THRESHOLD 50.0

#include <sourcemod>
#include <sdktools>
#include <left4dhooks>
//#include <sdkhooks>

static ConVar hPercent, hRange, hEnabled;
static char gamemode[32];
static bool panicStarted;
static float lastButtonPressTime;
static float flowRate[MAXPLAYERS+1];

public Plugin myinfo = 
{
	name =  "L4D2 Crescendo Control", 
	author = "jackzmc", 
	description = "Prevents players from starting crescendos early", 
	version = PLUGIN_VERSION, 
	url = ""
};

public void OnPluginStart()
{
	EngineVersion g_Game = GetEngineVersion();
	if(g_Game != Engine_Left4Dead2)
	{
		SetFailState("This plugin is for L4D2 only.");	
	}

	hEnabled = CreateConVar("l4d2_crescendo_control", "1", "Should plugin be active?", FCVAR_NONE, true, 0.0, true, 1.0);
	hPercent = CreateConVar("l4d2_crescendo_percent", "0.75", "The percent of players needed to be in range for crescendo to start", FCVAR_NONE);
	hRange = CreateConVar("l4d2_crescendo_range", "200.0", "How many units away something range brain no work", FCVAR_NONE);

	ConVar hGamemode = FindConVar("mp_gamemode"); 
	hGamemode.GetString(gamemode, sizeof(gamemode));
	hGamemode.AddChangeHook(Event_GamemodeChange);

	AddNormalSoundHook(view_as<NormalSHook>(SoundHook));
	//dhook setup
}

public void Event_GamemodeChange(ConVar cvar, const char[] oldValue, const char[] newValue) {
	cvar.GetString(gamemode, sizeof(gamemode));
}


public void OnMapStart() {
	if(!StrEqual(gamemode, "tankrun")) {
		HookEntityOutput("func_button", "OnPressed", Event_ButtonPress);
		CreateTimer(0.3, Timer_GetFlows, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	}
}

public void OnMapEnd() {
	panicStarted = false;
	for(int i = 1; i <= MaxClients; i++) {
		flowRate[i] = 0.0;
	}
}

public void OnClientDisconnect(int client) {
	flowRate[client] = 0.0;
}

public Action Timer_GetFlows(Handle h) {
	static float flow;
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i)) {
			flow = L4D2Direct_GetFlowDistance(i);
			if(flow > flowRate[i]) {
				flowRate[i] = flow;
			}
		}
	}
}

public Action Event_ButtonPress(const char[] output, int entity, int client, float delay) {
	if(hEnabled.BoolValue && client > 0 && client <= MaxClients) {
		AdminId admin = GetUserAdmin(client);
		if(admin != INVALID_ADMIN_ID && admin.HasFlag(Admin_Custom1)) return Plugin_Continue;

		if(panicStarted) {
			panicStarted = false;
			return Plugin_Continue;
		}

		static float pos[3];
		GetEntPropVector(entity, Prop_Send, "m_vecOrigin", pos);
		float activatorFlow = L4D2Direct_GetFlowDistance(client);

		PrintToConsoleAll("[CC] Button Press by %N", client);
		
		if(!IsActivationAllowed(activatorFlow, 1500.0)) {
			ClientCommand(client, "play ui/menu_invalid.wav");
			PrintToChat(client, "Please wait for players to catch up.");
			AcceptEntityInput(entity, "Lock");
			RequestFrame(Frame_ResetButton, entity);
			return Plugin_Handled;
		}
		lastButtonPressTime = GetGameTime();
	}
	return Plugin_Continue;
}


public Action SoundHook(int[] clients, int& numClients, char sample[PLATFORM_MAX_PATH], int& entity, int& channel, float& volume, int& level, int& pitch, int& flags, char[] soundEntry, int& seed) {
	if(StrEqual(sample, "npc/mega_mob/mega_mob_incoming.wav") && lastButtonPressTime > 0) {
		if(GetGameTime() - lastButtonPressTime < PANIC_DETECT_THRESHOLD) {
			panicStarted = true;
		}
	}
	return Plugin_Continue;
}

public void Frame_ResetButton(int entity) {
	AcceptEntityInput(entity, "Unlock");
}


//  5 far/8 total
// [Debug] average 4222.518066 - difference 2262.424316
// [Debug] Percentage of far players: 0.625000% | Average 4222.518066

stock bool IsActivationAllowed(float flowmax, float threshold) {
	int farSurvivors, totalSurvivors;
	float totalFlow;
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i)) {
			if(flowRate[i] < flowmax - threshold) {
				PrintDebug("Adding %N of flow %f to average", i, flowRate[i]);
				farSurvivors++;
				totalFlow += flowRate[i];
			}
			totalSurvivors++;
		}
	}
	if(farSurvivors == 0) return true;
	float average = totalFlow / farSurvivors;
	float percentFar = float(farSurvivors) / float(totalSurvivors);
	
	PrintDebug("average %f - difference %f - % far %f%% ", average, flowmax - average, percentFar);
	//If the average is in the range, allow
	if(flowmax - average <= threshold) return true;
	//If not, check the ratio of players
	return percentFar <= 0.30;
}

stock float GetAverageFlowBehind(float flowmax) {
	int survivors;
	float totalFlow;
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i)) {
			survivors++;
			totalFlow += flowRate[i];
		}
	}
	return totalFlow / survivors;
}


stock void PrintDebug(const char[] format, any ... ) {
	#if defined DEBUG
	char buffer[256];
	VFormat(buffer, sizeof(buffer), format, 2);
	PrintToServer("[Debug] %s", buffer);
	PrintToConsoleAll("[Debug] %s", buffer);
	#endif
}