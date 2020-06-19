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
bool lateLoaded = false;

//Stats that need to be only sent periodically. (note: possibly deaths?)
static int meleeKills[MAXPLAYERS+1];
static int damageSurvivorGiven[MAXPLAYERS+1];
static int damageSurvivorRec[MAXPLAYERS+1];
static int damageInfectedGiven[MAXPLAYERS+1];
static int damageInfectedRec[MAXPLAYERS+1];
static int damageSurvivorFF[MAXPLAYERS+1];
static int infectedKills[MAXPLAYERS+1];
static int infectedHeadshots[MAXPLAYERS+1];

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
			}
		}
	}

	HookEvent("player_death", Event_PlayerDeath);
	HookEvent("player_hurt", Event_PlayerHurt);
	HookEvent("item_pickup", Event_ItemPickup);
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

	RegConsoleCmd("sm_debug_stats", Command_DebugStats, "Debug stats");

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
	for(int i=1; i<=MaxClients;i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && !IsFakeClient(i) && steamidcache[i][0]) {
			FlushQueuedStats(i);
		}
	}
}
/////////////////////////////////
// PLAYER AUTH
/////////////////////////////////

public void OnClientPutInServer(int client) {
	char steamid[18];
	GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid));
	steamidcache[client] = steamid;
	//TODO: Fetch latest alias & store.
	//Initalize user if they do not exist in db

	if(!IsFakeClient(client)) {
		CreateDBUser(client, steamid);
		IncrementStat(client, "connections", 1);
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
	}
}
public void FlushQueuedStats(int client) {
	if(meleeKills[client] > 0) {
		IncrementStat(client, "melee_kills", meleeKills[client]);
		meleeKills[client] = 0;
	}
	//Update stats (don't bother checking if 0.)
	IncrementStat(client, "survivor_damage_give", damageSurvivorGiven[client]);
	IncrementStat(client, "survivor_damage_rec",damageSurvivorRec[client]);
	IncrementStat(client, "infected_damage_give", damageInfectedGiven[client]);
	IncrementStat(client, "infected_damage_rec", damageInfectedRec[client]);
	IncrementStat(client, "survivor_ff", damageSurvivorFF[client]);
	IncrementStat(client, "common_kills", infectedKills[client]);
	IncrementStat(client, "common_headshots", infectedHeadshots[client]);
	//And clear them.
	damageSurvivorGiven[client] = 0;
	damageSurvivorRec[client] = 0;
	damageInfectedGiven[client] = 0;
	damageInfectedRec[client] = 0;
	damageSurvivorFF[client] = 0;
	infectedKills[client] = 0;
	infectedHeadshots[client] = 0;

	steamidcache[client][0] = '\0';
}
/////////////////////////////////
//DATABASE CALLBACKS
/////////////////////////////////
public void DBC_CheckUserExistance(Database db, DBResultSet results, const char[] error, any data) {
	if(db == null || results == null)
    {
        LogError("DBC_CheckUserExistance returned error: %s", error);
        return;
    }
	int client = GetClientOfUserId(data); 
	char alias[33];
	GetClientName(client, alias, sizeof(alias));
	if(results.RowCount == 0) {
		//user does not exist in db, create now
		
		char query[255]; 
		Format(query, sizeof(query), "INSERT INTO `stats` (`steamid`, `last_alias`) VALUES ('%s', '%s')", steamidcache[client], alias);
		g_db.Query(DBC_Generic, query);
		PrintToServer("Created new database entry for %N (%s)", client, steamidcache[client]);
	}else{
		//User does exist, check if alias is outdated and update if needed
		int last_alias_size = results.FetchSize(1);
		char[] db_last_alias = new char[last_alias_size];
		results.FetchString(1, db_last_alias, last_alias_size);
		if(!StrEqual(db_last_alias, alias, true)) {
			char query[255]; 
			char safe_alias[67];
			db.Escape(alias, safe_alias, 67);

			Format(query, sizeof(query), "UPDATE `stats` SET `last_alias`='%s' WHERE `steamid`='%s'",safe_alias, steamidcache[client]);
			g_db.Query(DBC_Generic, query);
			PrintToServer("Alias for '%s' updated to '%s' (%s)", db_last_alias, alias, steamidcache[client]);
		}
	}
}
public void DBC_Generic(Database db, DBResultSet results, const char[] error, any data)
{
    if(db == null || results == null) {
        LogError("DBC_Generic returned error: %s", error);
        return;
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
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	int dmg = event.GetInt("amount");
	if(attacker > 0 && !IsFakeClient(attacker)) {
		damageSurvivorGiven[attacker] += dmg;
	}
}
public void Event_InfectedDeath(Event event, const char[] name, bool dontBroadcast) {
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	if(!IsFakeClient(attacker)) {
		bool headshot = event.GetBool("headshot");
		if(headshot) {
			infectedHeadshots[attacker]++;
		}
		infectedKills[attacker]++;
	}
}
public void Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast) {
	//TODO: Record damage done to a tank, and a witch.
	int victim = GetClientOfUserId(event.GetInt("userid"));
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	int victim_team = GetClientTeam(victim);
	int dmg = event.GetInt("dmg_health");
	if(dmg <= 0) return;
	if(!IsFakeClient(victim)) {
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
		}else if(attacker_team == 3) {
			damageInfectedGiven[attacker] += dmg;
		}
		if(attacker_team == 2 && victim_team == 2) {
			damageSurvivorFF[attacker] += dmg;
		}
	}
}
public void Event_ItemPickup(Event event, const char[] name, bool dontBroadcast) {
	//TODO: Record damage done to a tank, and a witch.
	char item[64];
	char statname[72];

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