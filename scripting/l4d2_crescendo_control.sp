#pragma semicolon 1
#pragma newdecls required

#define DEBUG 0
#define PLUGIN_VERSION "1.0"

#include <sourcemod>
#include <sdktools>
#include <left4dhooks>
//#include <sdkhooks>

#define PANIC_DETECT_THRESHOLD 50.0
#define MAX_GROUPS 4

enum struct Group {
	float pos[3];
	ArrayList members;
}

enum struct GroupResult {
	int groupCount;
	int ungroupedCount;
	float ungroupedRatio;
}


static ConVar hPercent, hRange, hEnabled, hGroupTeamDist;
static char gamemode[32];
static bool panicStarted;
static float lastButtonPressTime;
static float flowRate[MAXPLAYERS+1];

static Group g_groups[MAX_GROUPS];

public Plugin myinfo = 
{
	name =  "L4D2 Crescendo Control", 
	author = "jackzmc", 
	description = "Prevents players from starting crescendos early", 
	version = PLUGIN_VERSION, 
	url = "https://github.com/Jackzmc/sourcemod-plugins"
};

public void OnPluginStart()
{
	EngineVersion g_Game = GetEngineVersion();
	if(g_Game != Engine_Left4Dead2)
	{
		SetFailState("This plugin is for L4D2 only.");	
	}

	hEnabled = CreateConVar("l4d2_crescendo_control", "1", "Should plugin be active?\n 1 = Enabled normally\n2 = Admins with bypass allowed only", FCVAR_NONE, true, 0.0, true, 1.0);
	hPercent = CreateConVar("l4d2_crescendo_percent", "0.5", "The percent of players needed to be in range for crescendo to start", FCVAR_NONE);
	hRange = CreateConVar("l4d2_crescendo_range", "250.0", "How many units away something range brain no work", FCVAR_NONE);
	hGroupTeamDist = CreateConVar("l4d2_cc_team_maxdist", "320.0", "The maximum distance another player can be away from someone to form a group", FCVAR_NONE, true, 10.0);

	ConVar hGamemode = FindConVar("mp_gamemode"); 
	hGamemode.GetString(gamemode, sizeof(gamemode));
	hGamemode.AddChangeHook(Event_GamemodeChange);

	AddNormalSoundHook(SoundHook);

	RegAdminCmd("sm_dgroup", Command_DebugGroups, ADMFLAG_GENERIC);
	for(int i = 0; i < MAX_GROUPS; i++) {
		g_groups[i].members = null;
	}
}

Action Command_DebugGroups(int client, int args) {
	PrintDebug("Running manual compute of groups");
	if(client == 0) {
		PrintDebug("Ran from server console, using first player on server");
		for(int i = 1; i <= MaxClients; i++) {
			if(IsClientConnected(i) && IsClientInGame(i)) {
				client = i;
				PrintDebug("User: %N", i);
				break;
			}
		}
	}
	float activatorFlow = L4D2Direct_GetFlowDistance(client);
	GroupResult result;
	ComputeGroups(result, activatorFlow);
	return Plugin_Handled;
}

public void Event_GamemodeChange(ConVar cvar, const char[] oldValue, const char[] newValue) {
	cvar.GetString(gamemode, sizeof(gamemode));
}


public void OnMapStart() {
	if(StrEqual(gamemode, "coop")) {
		HookEntityOutput("func_button", "OnPressed", Event_ButtonPress);
		CreateTimer(1.0, Timer_GetFlows, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
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
	return Plugin_Continue;
}

public float GetFlowAtPosition(const float pos[3]) {
	Address area = L4D_GetNearestNavArea(pos, 50.0, false, false, false, 2);
	if(area == Address_Null) return -1.0;
	return L4D2Direct_GetTerrorNavAreaFlow(area);
}

public Action Event_ButtonPress(const char[] output, int entity, int client, float delay) {
	if(hEnabled.IntValue > 0 && client > 0 && client <= MaxClients) {
		float activatorFlow = L4D2Direct_GetFlowDistance(client);
		GroupResult result;
		ComputeGroups(result, activatorFlow);
		PrintToConsoleAll("[CC] Button Press by %N", client);

		AdminId admin = GetUserAdmin(client);
		if(admin != INVALID_ADMIN_ID && admin.HasFlag(Admin_Custom1)) {
			lastButtonPressTime = GetGameTime();
			return Plugin_Continue;
		} else if(result.groupCount > 0 && result.ungroupedCount > 0) {
			lastButtonPressTime = GetGameTime();
			return Plugin_Continue;
		}

		if(panicStarted) {
			panicStarted = false;
			return Plugin_Continue;
		}


		static float pos[3];
		GetEntPropVector(entity, Prop_Send, "m_vecOrigin", pos);


		if(hEnabled.IntValue == 2 || !IsActivationAllowed(activatorFlow, 1500.0)) {
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


public Action SoundHook(int clients[MAXPLAYERS], int& numClients, char sample[PLATFORM_MAX_PATH], int& entity, int& channel, float& volume, int& level, int& pitch, int& flags, char soundEntry[PLATFORM_MAX_PATH], int& seed) {
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
bool ComputeGroups(GroupResult result, float activateFlow) {
	float prevPos[3], pos[3];
	// int prevMember = -1;
	// ArrayList groupMembers = new ArrayList();
	int groupIndex = 0;
	// ArrayList groups = new ArrayList();

	// Group group;
	// // Create the first group
	// group.pos = pos;
	// group.members = new ArrayList();
	// PrintToServer("[cc] Creating first group");

	bool inGroup[MAXPLAYERS+1];

	ArrayList members = new ArrayList();
	for(int i = 0; i < MAX_GROUPS; i++) { 
		if(g_groups[i].members != null) { 
			delete g_groups[i].members;
		}
	}
	
	for(int i = 1; i <= MaxClients; i++) {
		if(!inGroup[i] && IsClientConnected(i) && IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == 2) {
			float prevFlow = L4D2Direct_GetFlowDistance(i);
			GetClientAbsOrigin(i, prevPos);

			members.Clear();
			
			for(int j = 1; j <= MaxClients; j++) {
				if(j != i && IsClientConnected(j) && IsClientInGame(j) && IsPlayerAlive(j) && GetClientTeam(j) == 2) {
					// TODO: MERGE groups
					GetClientAbsOrigin(j, pos);
					float flow = L4D2Direct_GetFlowDistance(j);
					float dist = FloatAbs(GetVectorDistance(prevPos, pos));
					float flowDiff = FloatAbs(prevFlow - flow);
					if(dist <= hGroupTeamDist.FloatValue) {
						// Add user as leader to group:
						if(members.Length == 0) {
							members.Push(GetClientUserId(i));
							inGroup[i] = true;
							// PrintDebug("add leader to group %d: %N", groupIndex + 1, i);
						}
						PrintDebug("add member to group %d: %N (dist = %.4f) (fldiff = %.1f)", groupIndex + 1, j, dist, flowDiff);
						inGroup[j] = true;
						members.Push(GetClientUserId(j));
					} else {
						// PrintDebug("not adding member to group %d: %N (dist = %.4f) (fldiff = %.1f) (l:%N)", groupIndex + 1, j, dist, flowDiff, i);
					}
				}
			}
			if(members.Length > 1) {
				// Drop the old members:
				if(g_groups[groupIndex].members != null) {
					delete g_groups[groupIndex].members;
				}
				g_groups[groupIndex].pos = prevPos;
				g_groups[groupIndex].members = members;
				members = new ArrayList();
				// PrintDebug("created group #%d with %d members", groupIndex + 1, g_groups[groupIndex].members.Length);
				groupIndex++;
				if(groupIndex == MAX_GROUPS) {
					PrintDebug("maximum amount of groups reached (%d)", MAX_GROUPS);
					break;
				}
			}
		}
	}
	delete members;

	int totalGrouped = 0;
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == 2) {
			if(inGroup[i])
				totalGrouped++;
			else
				result.ungroupedCount++;
		}
	}

	result.ungroupedRatio = float(result.ungroupedCount) / float(totalGrouped);

	PrintDebug("total grouped: %d | total ungrouped: %d | ratio: %f", totalGrouped, result.ungroupedCount, result.ungroupedRatio);

	PrintDebug("total groups created: %d", groupIndex);

	PrintDebug("===GROUP SUMMARY===");
	for(int i = 0; i < MAX_GROUPS; i++) {
		if(g_groups[i].members != null && g_groups[i].members.Length > 0) {
			PrintDebug("---Group %d---", i + 1);
			PrintDebug("Origin: %.1f %.1f %.1f", g_groups[i].pos[0], g_groups[i].pos[1], g_groups[i].pos[2]);
			float groupFlow = GetFlowAtPosition(g_groups[i].pos);
			PrintDebug("Flow Diff: %.2f (g:%.1f) (a:%.1f) (gtdist:%.f)", FloatAbs(activateFlow - groupFlow), activateFlow, groupFlow, hGroupTeamDist.FloatValue);
			PrintDebug("Leader: %N (uid#%d)", GetClientOfUserId(g_groups[i].members.Get(0)), g_groups[i].members.Get(0));
			for(int j = 1; j < g_groups[i].members.Length; j++) {
				int userid = g_groups[i].members.Get(j);
				PrintDebug("Member: %N (uid#%d)", GetClientOfUserId(userid), userid);
			}
		}
	}
	if(result.ungroupedCount > 0) {
		PrintDebug("--UNGROUPED SUMMARY--");
		for(int i = 1; i <= MaxClients; i++) {
			if(!inGroup[i] && IsClientConnected(i) && IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == 2) { 
				PrintDebug("User: %N (uid#%d)", i, GetClientUserId(i));
			}
		}
		PrintDebug("--END UNGROUPED SUMMARY--");
	}
	PrintDebug("===END GROUP SUMMARY===");
	// delete groupMembers;

	result.groupCount = groupIndex;
	return groupIndex > 0;
}

public Action L4D2_CGasCan_EventKilled(int gascan, int &inflictor, int &attacker) {
	if(hEnabled.IntValue > 0 && attacker > 0 && attacker <= MaxClients) {
		float activatorFlow = L4D2Direct_GetFlowDistance(attacker);
		GroupResult result;
		PrintToConsoleAll("[CC] Gascan Shot by %N", attacker);
		ComputeGroups(result, activatorFlow);

		AdminId admin = GetUserAdmin(attacker);
		if(admin != INVALID_ADMIN_ID && admin.HasFlag(Admin_Custom1)) {
			lastButtonPressTime = GetGameTime();
			return Plugin_Continue;
		} else if(result.groupCount > 0 && result.ungroupedCount > 0) {
			lastButtonPressTime = GetGameTime();
			return Plugin_Continue;
		}

		if(panicStarted) {
			panicStarted = false;
			return Plugin_Continue;
		}


		PrintToConsoleAll("[CC] Gascan Light by %N", attacker);
		if(hEnabled.IntValue == 2 || !IsActivationAllowed(activatorFlow, 1500.0)) {
			ClientCommand(attacker, "play ui/menu_invalid.wav");
			PrintToChat(attacker, "Please wait for players to catch up.");
			return Plugin_Handled;
		}
		lastButtonPressTime = GetGameTime();
	}
	return Plugin_Continue;
}


//  5 far/8 total
// [Debug] average 4222.518066 - difference 2262.424316
// [Debug] Percentage of far players: 0.625000% | Average 4222.518066

stock bool IsActivationAllowed(float flowmax, float threshold) {
	// Broken behavior, just short circuit true
	if(flowmax <= 0.01) return true;

	int farSurvivors, totalSurvivors;
	float totalFlow;
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i) && !IsFakeClient(i)) {
			if(flowRate[i] < flowmax - threshold) {
				PrintDebug("Adding %N with flow of %.2f to far survivors average", i, flowRate[i]);
				farSurvivors++;
				totalFlow += flowRate[i];
			}
			totalSurvivors++;
		}
	}
	if(farSurvivors == 0 || totalSurvivors == 1) return true;
	float average = totalFlow / farSurvivors;
	float percentFar = float(farSurvivors) / float(totalSurvivors);
	
	PrintDebug("Average Flow %f - Difference %f - Far % %f%% ", average, flowmax - average, percentFar * 100);
	//If the average is in the range, allow
	if(flowmax - average <= threshold) {
		PrintDebug("Activation is allowed (in range)");
		return true;
	}
	//If not, check the ratio of players
	bool isAllowed = percentFar <= 0.40;
	PrintDebug("Activation is %s", isAllowed ? "allowed" : "blocked");
	return isAllowed;
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
	// PrintToServer("[CrescendoControl:Debug] %s", buffer);
	PrintToConsoleAll("[CrescendoControl:Debug] %s", buffer);
	LogToFile("crescendo_control.log", "%s", buffer);
	#endif
}