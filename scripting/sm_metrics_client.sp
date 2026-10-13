#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <jutils>
#include <metrics>

public Plugin myinfo = {
	name =  "SM Metrics Client", 
	author = "jackzmc", 
	description = "", 
	version = "1.0", 
	url = "https://github.com/Jackzmc/sourcemod-plugins"
};

Metric METRIC_PLAYERS[5];
Metric METRIC_INCAPS;

Metric METRIC_TEST;

public void OnPluginStart() {
	RegisterMetrics();

    HookEvent("player_team", Event_PlayerTeam);
    HookEvent("player_incapacitated", Event_L4D2_Incapped);

    RegAdminCmd("sm_mt_test", Command_Test, ADMFLAG_GENERIC);
}

public void OnLibraryAdded(const char[] name) {
    if(StrEqual(name, "metrics")) {
        RegisterMetrics();
    }
}
public void OnLibraryRemoved(const char[] name) {
    if(StrEqual(name, "metrics")) {
        // TODO: somehow stop if removed?
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

public void Event_L4D2_Incapped(Event event, const char[] name, bool dontBroadcast) {
    METRIC_INCAPS.IncrementInt();
}
