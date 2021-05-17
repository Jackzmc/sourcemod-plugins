#pragma semicolon 1
#pragma newdecls required

#define DEBUG 0

#define PLUGIN_VERSION "1.0"

#define PANIC_DETECT_THRESHOLD 50.0

#include <sourcemod>
#include <sdktools>
#include <left4dhooks>
//#include <sdkhooks>

static ConVar hPercent, hRange;
static bool panicStarted;
static float lastButtonPressTime;

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

	hPercent = CreateConVar("l4d2_crescendo_percent", "0.75", "The percent of players needed to be in range for crescendo to start", FCVAR_NONE);
	hRange = CreateConVar("l4d2_crescendo_range", "150.0", "How many units away something range brain no work", FCVAR_NONE);

	AddNormalSoundHook(view_as<NormalSHook>(SoundHook));
	//dhook setup
}

public void OnMapStart() {
	HookEntityOutput("func_button", "OnPressed", Event_ButtonPress);
}

public void OnMapEnd() {
	panicStarted = false;
}

public Action Event_ButtonPress(const char[] output, int entity, int client, float delay) {
	if(client > 0 && client <= MaxClients) {
		if(panicStarted) {
			panicStarted = false;
			return Plugin_Continue;
		}

		static float pos[3];
		GetEntPropVector(entity, Prop_Send, "m_vecOrigin", pos);
		float activatorFlow = L4D2Direct_GetFlowDistance(client);
		
		if(!IsActivationAllowed(activatorFlow, 1500.0)) {
			PrintDebug("WOULD DENY BUTTON FOR %N", client);
			PrintDebug("WOULD DENY BUTTON FOR %N", client);
			PrintDebug("WOULD DENY BUTTON FOR %N", client);

			/*ClientCommand(client, "play ui/menu_invalid.wav");
			PrintToChat(client, "Please wait for players to catch up.");
			AcceptEntityInput(entity, "Lock");
			RequestFrame(Frame_ResetButton, entity);
			return Plugin_Handled;*/
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

stock bool IsActivationAllowed(float flowmax, float threshold) {
	int farSurvivors, totalSurvivors;
	float totalFlow;
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i)) {
			float flow = L4D2Direct_GetFlowDistance(i);
			if(flow < flowmax - threshold) {
				PrintDebug("Adding %N of flow %f to average", i, flow);
				farSurvivors++;
				totalFlow += flow;
			}
			totalSurvivors++;
		}
	}
	PrintDebug("%d far/%d total", farSurvivors, totalSurvivors);
	if(farSurvivors == 0) return true;
	float average = totalFlow / farSurvivors;
	PrintDebug("average %f - difference %f", average, flowmax - average);
	//If the average is in the range, allow
	if(flowmax - average <= threshold) return true;
	//If not, check the ratio of players
	float percentFar = float(farSurvivors) / float(totalSurvivors);
	PrintDebug("Percentage of far players: %f%% | Average %f", percentFar, average);
	return percentFar <= 0.30;
}

stock float GetAverageFlowBehind(float flowmax) {
	int survivors;
	float totalFlow;
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i)) {
			float flow = L4D2Direct_GetFlowDistance(i);
			survivors++;
			totalFlow += flow;
		}
	}
	return totalFlow / survivors;
}

//TODO: Improve logic to get "average" flow minimum
stock float GetLowestFlow() {
	int lowestClient;
	float lowest = -1.0, secondLowest = -1.0;
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i)) {
			float flow = L4D2Direct_GetFlowDistance(i);
			if(flow < lowest || lowest == -1) {
				lowestClient = i;
				secondLowest = lowest;
				lowest = flow;
			}
		}
	}

	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i) && lowestClient != i) {
			float flow = L4D2Direct_GetFlowDistance(i);
			if(flow < secondLowest || secondLowest == -1) {
				secondLowest = flow;
			}
		}
	}
	PrintDebug("Lowest flow: %f | 2nd lowest: %f", lowest, secondLowest);
	return lowest;
}

stock void PrintDebug(const char[] format, any ... ) {
	#if defined DEBUG
	char buffer[256];
	VFormat(buffer, sizeof(buffer), format, 2);
	PrintToServer("[Debug] %s", buffer);
	PrintToConsoleAll("[Debug] %s", buffer);
	#endif
}