#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <jutils>
#include <metrics>
#tryinclude <left4dhooks>

public Plugin myinfo = {
	name =  "SM Metrics Client", 
	author = "jackzmc", 
	description = "General queries to send metrics from Metrics API", 
	version = "1.0.0", 
	url = "https://github.com/Jackzmc/sourcemod-plugins"
};

char SPECIAL_IDS[6][] = {
	"jockey",
	"smoker",
	"boomer",
	"hunter",
	"charger",
	"spitter"
};

Metric METRIC_PLAYERS[5];
Metric METRIC_INCAPS;
Metric METRIC_DEATHS_SURVIVORS;
Metric METRIC_DEATHS_INFECTED[6];

Metric METRIC_TEST;

public void OnPluginStart() {
	RegisterMetrics();

    HookEvent("player_team", Event_PlayerTeam);
    HookEvent("player_incapacitated", Event_L4D2_Incapped);
    HookEvent("player_death", Event_Death);

    RegAdminCmd("sm_mt_test", Command_Test, ADMFLAG_GENERIC);
}

public void OnLibraryAdded(const char[] name) {
    if(StrEqual(name, "metrics")) {
        RegisterMetrics();
    }
}

public void OnPluginEnd() {
    ClearMetrics();
}

public void OnMapEnd() {
    METRIC_INCAPS.Reset();
}

Action Command_Test(int client, int args) {
    int val = METRIC_TEST.IncrementInt(1);
    ReplyToCommand(client, "now %d", val);
    return Plugin_Handled;
}

void RegisterMetrics() {
    METRIC_INCAPS = CreateMetric("sm_l4d2_incap_count")
        .SubscribeCvarLabel("z_difficulty")
        .SubscribeCvarLabel("mp_gamemode");
    METRIC_TEST = CreateMetric("sm_test");
    METRIC_DEATHS_SURVIVORS = CreateMetric("sm_l4d2_survivor_death_count")
        .SubscribeCvarLabel("z_difficulty")
        .SubscribeCvarLabel("mp_gamemode");
    for(int i = 0; i < 6; i++)
        METRIC_DEATHS_INFECTED[i] = CreateMetric("sm_l4d2_infected_death_count")
            .SetLabel("class", SPECIAL_IDS[i])
            .SubscribeCvarLabel("z_difficulty")
            .SubscribeCvarLabel("mp_gamemode");
    _registerSMPlayers();

}

void _registerSMPlayers() {
    for(int i = 0; i < 5; i++) {
        METRIC_PLAYERS[i] = CreateMetric("sm_players");
        METRIC_PLAYERS[i].SetLabelInt("team", i);
        METRIC_PLAYERS[i].SetInt(GetTeamClientCount(i));
    }
}

void Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast) {
    int oldTeam = event.GetInt("oldteam");
	int team = event.GetInt("team");
    // Update counts (real + bots)
    METRIC_PLAYERS[oldTeam].SetInt(GetTeamClientCount(oldTeam));
    METRIC_PLAYERS[team].SetInt(GetTeamClientCount(team));
}

void Event_L4D2_Incapped(Event event, const char[] name, bool dontBroadcast) {
    METRIC_INCAPS.IncrementInt();
}

void Event_Death(Event event, const char[] name, bool dontBroadcast) {
    int victim = GetClientOfUserId(event.GetInt("userid"));
    if(victim > 0) {
        int team = GetClientTeam(victim);
        if(team == 2) {
            METRIC_DEATHS_SURVIVORS.IncrementInt();
        } else if(team == 3) {
	        int class = GetEntProp(victim, Prop_Send, "m_zombieClass");
            METRIC_DEATHS_INFECTED[class].IncrementInt();
        }
    }
}