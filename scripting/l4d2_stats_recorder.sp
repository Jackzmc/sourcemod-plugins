#pragma semicolon 1
#pragma newdecls required

//#define DEBUG

#define PLUGIN_NAME "L4D(2) Stats Recorder"
#define PLUGIN_DESCRIPTION ""
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
static Database g_db;
char steamidcache[MAXPLAYERS+1][18];
bool lateLoaded = false, bVersus, bRealism;

//Stats that need to be only sent periodically. (note: possibly deaths?)
static int meleeKills[MAXPLAYERS+1];
static int damageSurvivorGiven[MAXPLAYERS+1];
static int damageSurvivorRec[MAXPLAYERS+1];
static int damageInfectedGiven[MAXPLAYERS+1];
static int damageInfectedRec[MAXPLAYERS+1];
static int damageSurvivorFF[MAXPLAYERS+1];
static int infectedKills[MAXPLAYERS+1];
static int infectedHeadshots[MAXPLAYERS+1];
static int doorOpens[MAXPLAYERS+1];
static int damageToTank[MAXPLAYERS+1];
static int damageWitch[MAXPLAYERS+1];
static int startedPlaying[MAXPLAYERS+1];

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
	if(late) {
		lateLoaded = true;
	}
}
//TODO: melee_kill (Cache clients and on map end push?) 
//TODO: player_use (Check laser sights usage)

public void OnPluginStart()
{
	EngineVersion g_Game = GetEngineVersion();
	if(g_Game != Engine_Left4Dead && g_Game != Engine_Left4Dead2)
	{
		SetFailState("This plugin is for L4D/L4D2 only.");	
	}

	if(!ConnectDB()) {
		SetFailState("Failed to connect to database.");
	}

	if(lateLoaded) {
		for(int i=1; i<MaxClients;i++) {
			if(IsClientConnected(i) && IsClientInGame(i) && !IsFakeClient(i)) {
				char steamid[18];
				GetClientAuthId(i, AuthId_Steam2, steamid, sizeof(steamid));
				steamidcache[i] = steamid;
				startedPlaying[i] = GetTime();
			}
		}
	}

	ConVar hGamemode = FindConVar("mp_gamemode");
	hGamemode.AddChangeHook(CVC_GamemodeChange);

	HookEvent("player_death", Event_PlayerDeath);
	HookEvent("player_hurt", Event_PlayerHurt);
	//HookEvent("item_pickup", Event_ItemPickup);
	HookEvent("player_incapacitated", Event_PlayerIncap);
	HookEvent("pills_used", Event_ItemUsed);
	HookEvent("defibrillator_used", Event_ItemUsed);
	HookEvent("adrenaline_used", Event_ItemUsed);
	HookEvent("heal_success", Event_ItemUsed);
	HookEvent("revive_success", Event_ItemUsed); //Yes it's not an item. No I don't care.
	HookEvent("melee_kill", Event_MeleeKill);
	HookEvent("tank_killed", Event_TankKilled);
	HookEvent("infected_hurt", Event_InfectedHurt);
	HookEvent("infected_death", Event_InfectedDeath);
	HookEvent("door_open", Event_DoorOpened);
	HookEvent("upgrade_pack_used", Event_UpgradePackUsed);
	HookEvent("finale_win", Event_FinaleWin);

	RegConsoleCmd("sm_debug_stats", Command_DebugStats, "Debug stats");
	RegConsoleCmd("sm_debug_cache", Command_DebugCache);

	CreateTimer(60.0, Timer_FlushStats, _, TIMER_REPEAT);
}
public void OnPluginEnd() {
	for(int i=1; i<=MaxClients;i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && !IsFakeClient(i) && steamidcache[i][0]) {
			FlushQueuedStats(i);
		}
	}
}
//////////////////////////////////
// TIMER
/////////////////////////////////
public Action Timer_FlushStats(Handle timer) {
	//Periodically flush the statistics
	int updated = 0;
	for(int i=1; i<=MaxClients;i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && !IsFakeClient(i) && steamidcache[i][0]) {
			//Don't update player's stats if they have not done anything.
			if(damageSurvivorGiven[i] > 0 || damageSurvivorRec[i] > 0 || damageInfectedGiven[i] > 0 || damageInfectedRec[i] > 0) {
				FlushQueuedStats(i);
				updated++;
			}
		}
	}
	if(updated > 0) PrintToServer("Flush stats for %d clients", updated);
}
/////////////////////////////////
// CONVAR CHANGES
/////////////////////////////////
public void CVC_GamemodeChange(ConVar convar, const char[] oldValue, const char[] newValue) {
	if(StrEqual(newValue, "realism")) {
		bRealism = true;
		bVersus = false;
	}else if(StrEqual(newValue, "versus")) {
		bVersus = true;
		bRealism = false;
	}else {
		bRealism = false;
		bVersus = false;
	}
}
/////////////////////////////////
// PLAYER AUTH
/////////////////////////////////

public void OnClientAuthorized(int client, const char[] auth) {
	if(!IsFakeClient(client)) {
		strcopy(steamidcache[client], 18, auth);
		CreateDBUser(client, steamidcache[client]);
		IncrementStat(client, "connections", 1);
		startedPlaying[client] = GetTime();
	}
}
public void OnClientDisconnect(int client) {
	//Check if any pending stats to send.
	if(!IsFakeClient(client)) {
		FlushQueuedStats(client);
	}
}

///////////////////////////////////
//DB METHODS
//////////////////////////////////

bool ConnectDB() {
    char error[255];
    g_db = SQL_Connect("stats", true, error, sizeof(error));
    if (g_db == null) {
		LogError("Database error %s", error);
		delete g_db;
		return false;
    } else {
		PrintToServer("Connected to database stats");
		return true;
    }
}
void CreateDBUser(int client, const char steamid[18]) {
	char query[255], escaped_id[37];
	g_db.Escape(steamid, escaped_id, 37);
	Format(query, sizeof(query), "SELECT steamid,last_alias FROM stats WHERE steamid='%s'", escaped_id);
	g_db.Query(DBC_CheckUserExistance, query, GetClientUserId(client));
}
void IncrementStat(int client, const char[] name, int amount = 1, bool lowPriority = false) {
	if (steamidcache[client][0] && !IsFakeClient(client)) {
		if(g_db == INVALID_HANDLE) {
			LogError("Database handle is invalid.");
			return;
		}
		int escaped_name_size = 2*strlen(name)+1;
		char[] escaped_name = new char[escaped_name_size];
		char query[255];
		g_db.Escape(name, escaped_name, escaped_name_size);
		Format(query, sizeof(query), "UPDATE stats SET `%s`=`%s`+%d WHERE steamid='%s'", escaped_name, escaped_name, amount, steamidcache[client]);
		PrintToServer("[Debug] Updated Stat %s (+%d) for %s", name, amount, steamidcache[client]);
		g_db.Query(DBC_Generic, query, _, lowPriority ? DBPrio_Low : DBPrio_Normal);
	}else{
		#if defined debug
		LogError("Incrementing stat (%s) for client %d failure: No steamid", name, client);
		#endif
		if(!IsFakeClient(client)) {
			//attempt to fetch it
			char steamid[18];
			GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid));
			steamidcache[client] = steamid;
		}
	}
}
void IncrementMapStat(int client, const char[] mapname, int difficulty) {
	if (steamidcache[client][0] && !IsFakeClient(client)) {
		char query[255], difficultyName[16];
		int realism_amount = bRealism ? 1 : 0;
		switch(difficulty) {
			case 0: strcopy(difficultyName, sizeof(difficultyName), "easy");
			case 1: strcopy(difficultyName, sizeof(difficultyName), "normal");
			case 2: strcopy(difficultyName, sizeof(difficultyName), "advanced");
			case 3: strcopy(difficultyName, sizeof(difficultyName), "expert");
		}

		Format(query, sizeof(query), "INSERT INTO stats_maps (steamid, map_name, wins, `difficulty_%s`, realism)\nVALUES ('%s', '%s', 1, 1, %d)\n ON DUPLICATE KEY UPDATE wins=wins+1,`difficulty_%s`=`difficulty_%s`+1,realism=realism+%d", 
			difficultyName, steamidcache[client], mapname, realism_amount, difficultyName, difficultyName, realism_amount);
		PrintToServer("[Debug] Updated Map Stat %s for %s", mapname, steamidcache[client]);
		g_db.Query(DBC_Generic, query, _);
	}else{
		#if defined debug
		LogError("Incrementing stat (%s) for client %d failure: No steamid", mapname, client);
		#endif
	}
}
public void FlushQueuedStats(int client) {
	//Update stats (don't bother checking if 0.)
	char query[512];
	int minutes_played = (GetTime() - startedPlaying[client]) / 60;
	Format(query, sizeof(query), "UPDATE stats SET survivor_damage_give=survivor_damage_give+%d,survivor_damage_rec=survivor_damage_rec+%d, infected_damage_give=infected_damage_give+%d,infected_damage_rec=infected_damage_rec+%d,survivor_ff=survivor_ff+%d,common_kills=common_kills+%d,common_headshots=common_headshots+%d,melee_kills=melee_kills+%d,door_opens=door_opens+%d,damage_to_tank=damage_to_tank+%d, damage_witch=damage_witch+%d,minutes_played=minutes_played+%d WHERE steamid='%s'",
		damageSurvivorGiven[client],
		damageSurvivorRec[client], 
		damageInfectedGiven[client], 
		damageInfectedRec[client], 
		damageSurvivorFF[client], 
		infectedKills[client], 
		infectedHeadshots[client], 
		meleeKills[client], 
		doorOpens[client],
		damageToTank[client],
		damageWitch[client],
		minutes_played,
		steamidcache[client][0]
	);
	g_db.Query(DBC_FlushQueuedStats, query, client);
	//And clear them.
	

	steamidcache[client][0] = '\0';
}
/////////////////////////////////
//DATABASE CALLBACKS
/////////////////////////////////
public void DBC_CheckUserExistance(Database db, DBResultSet results, const char[] error, any data) {
	if(db == null || results == null) {
        LogError("DBC_CheckUserExistance returned error: %s", error);
        return;
    }
	int client = GetClientOfUserId(data); 
	char alias[33];
	GetClientName(client, alias, sizeof(alias));
	if(results.RowCount == 0) {
		//user does not exist in db, create now
		
		char query[255]; 
		Format(query, sizeof(query), "INSERT INTO `stats` (`steamid`, `last_alias`, `last_join_date`) VALUES ('%s', '%s', NOW())", steamidcache[client], alias);
		g_db.Query(DBC_Generic, query);
		PrintToServer("Created new database entry for %N (%s)", client, steamidcache[client]);
	}else{
		//User does exist, check if alias is outdated and update if needed
		char safe_alias[67], query[255];
		db.Escape(alias, safe_alias, 67);

		Format(query, sizeof(query), "UPDATE `stats` SET `last_alias`='%s', `last_join_date`=NOW() WHERE `steamid`='%s'",safe_alias, steamidcache[client]);
		g_db.Query(DBC_Generic, query);
	}
}
public void DBC_Generic(Database db, DBResultSet results, const char[] error, any data)
{
    if(db == null || results == null) {
        LogError("DBC_Generic returned error: %s", error);
        return;
    }
}
public void DBC_FlushQueuedStats(Database db, DBResultSet results, const char[] error, any data) {
	if(db == null || results == null) {
		LogError("DBC_FlushQueued returne derror: %S", error);
	}else{
		int client = data;
		meleeKills[client] = 0;
		damageSurvivorGiven[client] = 0;
		damageSurvivorRec[client] = 0;
		damageInfectedGiven[client] = 0;
		damageInfectedRec[client] = 0;
		damageSurvivorFF[client] = 0;
		infectedKills[client] = 0;
		infectedHeadshots[client] = 0;
		doorOpens[client] = 0;
		damageToTank[client] = 0;
		damageWitch[client] = 0;
		startedPlaying[client] = GetTime();
	}
}
////////////////////////////
// COMMANDS
///////////////////////////
public Action Command_DebugStats(int client, int args) {
	ReplyToCommand(client, "Your queued stats: ");
	ReplyToCommand(client, "melee_kills = %d", meleeKills[client]);
	ReplyToCommand(client, "damageSurvivorGiven = %d", damageSurvivorGiven[client]);
	ReplyToCommand(client, "damageSurvivorRec = %d", damageSurvivorRec[client]);
	ReplyToCommand(client, "damageInfectedGiven = %d", damageInfectedGiven[client]); 
	ReplyToCommand(client, "damageInfectedRec= %d", damageInfectedRec[client]);
	ReplyToCommand(client, "infectedKills = %d", infectedKills[client]);
	ReplyToCommand(client, "infectedHeadshots = %d", infectedHeadshots[client]);
	return Plugin_Handled;
}
public Action Command_DebugCache(int client, int args) {
	ReplyToCommand(client, "Cache:");
	for(int i=1; i<=MaxClients;i++) {
		if(IsClientConnected(i) && IsClientInGame(i)) {
			ReplyToCommand(client, "#%d (%N) steamid: %s", i, i, steamidcache[i]); 
		}
	}
	return Plugin_Handled;
}

////////////////////////////
// EVENTS 
////////////////////////////

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(client > 0 && !IsFakeClient(client)) {
		int team = GetClientTeam(client);
		if(team == 2) {
			IncrementStat(client, "survivor_deaths", 1);
		}else if(team == 3) {
			IncrementStat(client, "infected_deaths", 1);
		}
	}
}
public void Event_InfectedHurt(Event event, const char[] name, bool dontBroadcast) {
	//TODO: Record damage done to a tank, and a witch.
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	int dmg = event.GetInt("amount");
	if(attacker > 0 && !IsFakeClient(attacker)) {
		damageSurvivorGiven[attacker] += dmg;
		int target_id = event.GetInt("entityid");
		char entity_name[32];
		GetEntityClassname(target_id, entity_name, sizeof(entity_name));
		if(StrEqual(entity_name, "witch", false)) {
			damageWitch[attacker]++;
		}
	}
}
public void Event_InfectedDeath(Event event, const char[] name, bool dontBroadcast) {
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	if(attacker > 0 && !IsFakeClient(attacker)) {
		bool headshot = event.GetBool("headshot");
		if(headshot) {
			infectedHeadshots[attacker]++;
		}
		infectedKills[attacker]++;
	}
}
public void Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast) {
	int victim = GetClientOfUserId(event.GetInt("userid"));
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	int victim_team = GetClientTeam(victim);
	int dmg = event.GetInt("dmg_health");
	if(dmg <= 0) return;
	if(victim > 0 && !IsFakeClient(victim)) {
		if(victim_team == 2) {
			damageSurvivorRec[victim] += dmg;
		}else if(victim_team == 3) {
			damageInfectedRec[victim] += dmg;
		}
	}
	if(attacker > 0 && !IsFakeClient(attacker)) {
		int attacker_team = GetClientTeam(attacker);
		if(attacker_team == 2) {
			damageSurvivorGiven[attacker] += dmg;

			char victim_name[64];
			GetClientName(victim, victim_name, sizeof(victim_name));
			if(IsFakeClient(victim) && StrContains(victim_name, "Tank", true) > -1) {
				damageToTank[attacker] += dmg;
			}
		}else if(attacker_team == 3) {
			damageInfectedGiven[attacker] += dmg;
		}
		if(attacker_team == 2 && victim_team == 2) {
			damageSurvivorFF[attacker] += dmg;
		}
	}
}
public void Event_ItemPickup(Event event, const char[] name, bool dontBroadcast) {
	char statname[72], item[64];

	int client = GetClientOfUserId(event.GetInt("userid"));
	if(!IsFakeClient(client)) {
		event.GetString("item", item, sizeof(item));
		ReplaceString(item, sizeof(item), "weapon_", "", true);
		Format(statname, sizeof(statname), "pickups_%s", item);
		IncrementStat(client, statname, 1);
	}
}
public void Event_PlayerIncap(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(!IsFakeClient(client) && GetClientTeam(client) == 2) {
		IncrementStat(client, "survivor_incaps", 1);
	}
}
public void Event_ItemUsed(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(!IsFakeClient(client)) {
		if(StrEqual(name, "heal_success", true)) {
			int subject = GetClientOfUserId(event.GetInt("subject"));
			if(subject == client) {
				IncrementStat(client, "heal_self", 1);
			}else{
				IncrementStat(client, "heal_others", 1);
			}
		}else if(StrEqual(name, "revive_success", true)) {
			int subject = GetClientOfUserId(event.GetInt("subject"));
			if(subject != client) {
				IncrementStat(client, "revived_others", 1);
				IncrementStat(subject, "revived", 1);
			}
		}else if(StrEqual(name, "defibrillator_used", true)) {
			IncrementStat(client, "defibs_used", 1);
		}else{
			IncrementStat(client, name, 1);
		}
	}
}
public void Event_MeleeKill(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(client > 0 && !IsFakeClient(client)) {
		meleeKills[client]++;
	}
}
public void Event_TankKilled(Event event, const char[] name, bool dontBroadcast) {
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	bool solo = event.GetBool("solo");
	bool melee_only = event.GetBool("melee_only");
	if(attacker > 0 && !IsFakeClient(attacker)) {
		if(solo) {
			IncrementStat(attacker, "tanks_killed_solo", 1);
		}
		if(melee_only) {
			IncrementStat(attacker, "tanks_killed_melee", 1);
		}
		IncrementStat(attacker, "tanks_killed", 1);
	}
}
public void Event_DoorOpened(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(event.GetBool("closed") && !IsFakeClient(client)) {
		doorOpens[client]++;

	}
}

public void Event_UpgradePackUsed(Event event, const char[] name, bool dontBroadcast) {
	int upgradeid = event.GetInt("upgradeid");
	PrintToServer("upgradepackused: %d", upgradeid);
}
public void Event_FinaleWin(Event event, const char[] name, bool dontBroadcast) {
	char map_name[128];
	int difficulty = event.GetInt("difficulty");
	event.GetString("map_name", map_name, sizeof(map_name));
	for(int i=1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && !IsFakeClient(i) && steamidcache[i][0]) {
			int team = GetClientTeam(i);
			if(team == 2) {
				IncrementMapStat(i, map_name, difficulty);
				IncrementStat(i, "finales_won",1);
			}
		}
	}
}