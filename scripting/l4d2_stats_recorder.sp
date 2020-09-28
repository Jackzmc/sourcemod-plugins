#pragma semicolon 1
#pragma newdecls required

//#define DEBUG
#define PLUGIN_VERSION "1.0"

#include <sourcemod>
#include <sdktools>
#include <geoip>
#include <sdkhooks>
//#include <sdkhooks>

public Plugin myinfo = 
{
	name =  "L4D(2) Stats Recorder", 
	author = "jackzmc", 
	description = "", 
	version = PLUGIN_VERSION, 
	url = ""
};
static Database g_db;
static char steamidcache[MAXPLAYERS+1][32];
bool lateLoaded = false, bVersus, bRealism;

//Stats that need to be only sent periodically. (note: possibly deaths?)
static int damageSurvivorGiven[MAXPLAYERS+1];
static int damageInfectedGiven[MAXPLAYERS+1];
static int damageInfectedRec[MAXPLAYERS+1];
static int damageSurvivorFF[MAXPLAYERS+1];
static int doorOpens[MAXPLAYERS+1];
static int witchKills[MAXPLAYERS+1];
static int startedPlaying[MAXPLAYERS+1];
static int points[MAXPLAYERS+1];
static int upgradePacksDeployed[MAXPLAYERS+1];
static int finaleTimeStart;
static int molotovDamage[MAXPLAYERS+1];
static int pipeKills[MAXPLAYERS+1];

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
	if(late) {
		lateLoaded = true;
	}
}
//TODO: player_use (Check laser sights usage)
//TODO: Witch startles
//TODO: Versus as infected stats
//TODO: Move kills to queue stats not on demand
//TODO: map_stats record fastest timestamp

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
				char steamid[32];
				GetClientAuthId(i, AuthId_Steam2, steamid, sizeof(steamid));
				strcopy(steamidcache[i], 32, steamid);
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
	HookEvent("witch_killed", Event_WitchKilled);
	HookEvent("finale_start", Event_FinaleStart);
	HookEvent("gauntlet_finale_start", Event_FinaleStart);
	HookEvent("hegrenade_detonate", Event_GrenadeDenonate);


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
	if(GetClientCount(true) > 0) {
		for(int i=1; i<=MaxClients;i++) {
			if(IsClientConnected(i) && IsClientInGame(i) && !IsFakeClient(i) && steamidcache[i][0]) {
				FlushQueuedStats(i);
			}
		}
	}
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
	if(client > 0 && !IsFakeClient(client)) {
		strcopy(steamidcache[client], 32, auth);
		CreateDBUser(client, steamidcache[client]);
		startedPlaying[client] = GetTime();
	}
}
public void OnClientDisconnect(int client) {
	//Check if any pending stats to send.
	if(!IsFakeClient(client)) {
		FlushQueuedStats(client);
		steamidcache[client][0] = '\0';
		points[client] = 0;
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
void CreateDBUser(int client, const char steamid[32]) {
	if(client > 0 && !IsFakeClient(client)) {
		char query[128];
		Format(query, sizeof(query), "SELECT steamid,last_alias,points FROM stats WHERE steamid='%s'", steamid);
		g_db.Query(DBC_CheckUserExistance, query, GetClientUserId(client));
	}
}
void IncrementStat(int client, const char[] name, int amount = 1, bool lowPriority = false, bool retry = true) {
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
		PrintToServer("[Debug] Updating Stat %s (+%d) for %N (%d) [%s]", name, amount, client, client, steamidcache[client]);
		g_db.Query(DBC_Generic, query, _, lowPriority ? DBPrio_Low : DBPrio_Normal);
	}else{
		if(!IsFakeClient(client)) {
			#if defined debug
			LogError("Incrementing stat (%s) for client %N (%d) [%s] failure: No steamid or is bot", name, client, client, steamidcache[client]);
			#endif
			//attempt to fetch it
			char steamid[32];
			GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid));
			steamidcache[client] = steamid;
			if(retry) {
				IncrementStat(client, name, amount, lowPriority, false);
			}
		}
	}
}
void IncrementMapStat(int client, const char[] mapname, int difficulty) {
	if (steamidcache[client][0] && !IsFakeClient(client)) {
		char query[256], difficultyName[16];
		int realism_amount = bRealism ? 1 : 0;
		switch(difficulty) {
			case 0: strcopy(difficultyName, sizeof(difficultyName), "easy");
			case 1: strcopy(difficultyName, sizeof(difficultyName), "normal");
			case 2: strcopy(difficultyName, sizeof(difficultyName), "advanced");
			case 3: strcopy(difficultyName, sizeof(difficultyName), "expert");
		}
		int time = GetTime() - finaleTimeStart;

		Format(query, sizeof(query), "INSERT INTO stats_maps (steamid, map_name, wins, `difficulty_%s`, realism, best_time)\nVALUES ('%s', '%s', 1, 1, %d, %d)\n ON DUPLICATE KEY UPDATE wins=wins+1,`difficulty_%s`=`difficulty_%s`+1,realism=realism+%d,best_time=GREATEST(%d,VALUES(best_time))", 
			difficultyName, steamidcache[client], mapname, realism_amount, time, difficultyName, difficultyName, realism_amount, time);
		PrintToServer("[Debug] Updated Map Stat %s for %s", mapname, steamidcache[client]);
		g_db.Query(DBC_Generic, query, _);
	}else{
		#if defined debug
		LogError("Incrementing stat (%s) for client %d error: No steamid", mapname, client);
		#endif
	}
}
public void FlushQueuedStats(int client) {
	//Update stats (don't bother checking if 0.)
	char query[1023];
	int minutes_played = (GetTime() - startedPlaying[client]) / 60;
	Format(query, sizeof(query), "UPDATE stats SET survivor_damage_give=survivor_damage_give+%d,survivor_damage_rec=survivor_damage_rec+%d, infected_damage_give=infected_damage_give+%d,infected_damage_rec=infected_damage_rec+%d,survivor_ff=survivor_ff+%d,common_kills=common_kills+%d,common_headshots=common_headshots+%d,melee_kills=melee_kills+%d,door_opens=door_opens+%d,damage_to_tank=damage_to_tank+%d, damage_witch=damage_witch+%d,minutes_played=minutes_played+%d, kills_witch=kills_witch+%d, points=%d, packs_used=packs_used+%d, damage_molotov=damage_molotov+%d, kills_pipe=kills_pipe+%d WHERE steamid='%s'",
		damageSurvivorGiven[client], //survivor_damage_give
		GetEntProp(client, Prop_Send, "m_checkpointDamageTaken"),  //survivor_damage_rec
		damageInfectedGiven[client],  //infected_damage_give
		damageInfectedRec[client],  //infected_damage_rec
		damageSurvivorFF[client],  //survivor_ff
		GetEntProp(client, Prop_Send, "m_checkpointZombieKills"),  //common_kills
		GetEntProp(client, Prop_Send, "m_checkpointHeadshots"),  //common_headshots
		GetEntProp(client, Prop_Send, "m_checkpointMeleeKills"), //melee_kills
		doorOpens[client], //door_opens
		GetEntProp(client, Prop_Send, "m_checkpointDamageToTank"), //damage_to_tank
		GetEntProp(client, Prop_Send, "m_checkpointDamageToWitch"), //damage_witch
		minutes_played, //minutes_played
		witchKills[client], //kills_witch
		points[client], //points
		upgradePacksDeployed[client], //packs_used
		molotovDamage[client], //damage_molotov
		pipeKills[client], //kills_pipe
		steamidcache[client][0]
	);
	g_db.Query(DBC_FlushQueuedStats, query, client);
	//And clear them.

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
	int alias_length = 2*MAX_NAME_LENGTH+1;
	char alias[MAX_NAME_LENGTH], ip[40], country_name[45];
	char[] safe_alias = new char[alias_length];

	GetClientName(client, alias, sizeof(alias));
	db.Escape(alias, safe_alias, alias_length);
	GetClientIP(client, ip, sizeof(ip));
	GeoipCountry(ip, country_name, sizeof(country_name));

	if(results.RowCount == 0) {
		//user does not exist in db, create now
		
		char query[255]; 
		Format(query, sizeof(query), "INSERT INTO `stats` (`steamid`, `last_alias`, `last_join_date`,`created_date`,`country`) VALUES ('%s', '%s', UNIX_TIMESTAMP(), UNIX_TIMESTAMP(), '%s')", steamidcache[client], safe_alias, country_name);
		g_db.Query(DBC_Generic, query);
		PrintToServer("Created new database entry for %N (%s)", client, steamidcache[client]);
	}else{
		//User does exist, check if alias is outdated and update if needed
		while(results.FetchRow()) {
			int field_num;
			if(results.FieldNameToNum("points", field_num)) {
				points[client] = results.FetchInt(field_num);
			}
		}
		if(points[client] == 0) {
			PrintToServer("[Warning] Existing player %N (%d) has no points", client, client);
		}
		char query[255];
		int connections_amount = lateLoaded ? 0 : 1;

		Format(query, sizeof(query), "UPDATE `stats` SET `last_alias`='%s', `last_join_date`=UNIX_TIMESTAMP(), `country`='%s', connections=connections+%d WHERE `steamid`='%s'", safe_alias, country_name, connections_amount, steamidcache[client]);
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
		LogError("DBC_FlushQueuedStats returned error: %s", error);
	}else{
		int client = data;
		damageSurvivorFF[client] = 0;
		damageSurvivorGiven[client] = 0;
		doorOpens[client] = 0;
		witchKills[client] = 0;
		upgradePacksDeployed[client] = 0;
		molotovDamage[client] = 0;
		pipeKills[client] = 0;
		startedPlaying[client] = GetTime();
	}
}
////////////////////////////
// COMMANDS
///////////////////////////
public Action Command_DebugStats(int client, int args) {
	int meleeKills = GetEntProp(client, Prop_Send, "m_checkpointMeleeKills");
	int zombiekills = GetEntProp(client, Prop_Send, "m_checkpointZombieKills");
	ReplyToCommand(client, "m_checkpointMeleeKills %d", meleeKills);
	ReplyToCommand(client, "damageSurvivorGiven %d", damageSurvivorGiven[client]); 
	ReplyToCommand(client, "m_checkpointDamageTaken %d", GetEntProp(client, Prop_Send, "m_checkpointDamageTaken"));
	ReplyToCommand(client, "m_checkpointZombieKills: %d", zombiekills);
	ReplyToCommand(client, "points = %d", points[client]);
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

public void Event_InfectedHurt(Event event, const char[] name, bool dontBroadcast) {
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	if(attacker > 0 && !IsFakeClient(attacker)) {
		int dmg = event.GetInt("amount");
		damageSurvivorGiven[attacker] += dmg;
	}
}
public void Event_InfectedDeath(Event event, const char[] name, bool dontBroadcast) {
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	if(attacker > 0 && !IsFakeClient(attacker)) {
		bool blast = event.GetBool("blast");
		bool headshot = event.GetBool("headshot");
		char wpn_name[32];
		GetClientWeapon(attacker, wpn_name, sizeof(wpn_name));

		if(headshot) {
			points[attacker]+=2;
		}else{
			points[attacker]++;
		}

		if(blast) pipeKills[attacker]++;
	}
}
public void Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast) {
	int victim = GetClientOfUserId(event.GetInt("userid"));
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	int victim_team = GetClientTeam(victim);
	int dmg = event.GetInt("dmg_health");
	if(dmg <= 0) return;
	if(attacker > 0 && !IsFakeClient(attacker)) {
		int attacker_team = GetClientTeam(attacker);
		char wpn_name[32]; 
		event.GetString("weapon", wpn_name, sizeof(wpn_name));

		if(attacker_team == 2) {
			damageSurvivorGiven[attacker] += dmg;

			if(victim_team == 3 && StrEqual(wpn_name, "inferno", true)) {
				molotovDamage[attacker] += dmg;
				points[attacker]++; //give points (not per dmg tho)
			}
		}else if(attacker_team == 3) {
			damageInfectedGiven[attacker] += dmg;
		}
		if(attacker_team == 2 && victim_team == 2) {
			points[attacker]--;
			damageSurvivorFF[attacker] += dmg;
		}
	}
}
public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) {
	int victim = GetClientOfUserId(event.GetInt("userid"));
	if(victim > 0) {
		int attacker = GetClientOfUserId(event.GetInt("attacker"));
		int victim_team = GetClientTeam(victim);

		if(!IsFakeClient(victim)) {
			if(victim_team == 2) {
				IncrementStat(victim, "survivor_deaths", 1);
			}else if(victim_team == 3) {
				IncrementStat(victim, "infected_deaths", 1);
			}
		}

		if(attacker > 0 && !IsFakeClient(attacker) && GetClientTeam(attacker) == 2) {
			if(victim_team == 3) {
				int victim_class = GetEntProp(victim, Prop_Send, "m_zombieClass");
				char class[8], statname[16], wpn_name[32]; 
				event.GetString("weapon", wpn_name, sizeof(wpn_name));

				if(GetInfectedClassName(victim_class, class, sizeof(class))) {
					Format(statname, sizeof(statname), "kills_%s", class);
					IncrementStat(attacker, statname, 1);
					points[attacker] += 5; //special kill
				}
				if(StrEqual(wpn_name, "inferno", true) || StrEqual(wpn_name, "entityflame", true)) {
					IncrementStat(attacker, "kills_molotov", 1);
				}
			}else if(victim_team == 2) {
				IncrementStat(attacker, "ff_kills", 1);
				points[attacker] -= 30; //30 point lost for killing teammate
			}
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
	if(client > 0 && !IsFakeClient(client)) {
		if(StrEqual(name, "heal_success", true)) {
			int subject = GetClientOfUserId(event.GetInt("subject"));
			if(subject == client) {
				IncrementStat(client, "heal_self", 1);
			}else{
				points[client] += 10;
				IncrementStat(client, "heal_others", 1);
			}
		}else if(StrEqual(name, "revive_success", true)) {
			int subject = GetClientOfUserId(event.GetInt("subject"));
			if(subject != client) {
				IncrementStat(client, "revived_others", 1);
				points[client] += 3;
				IncrementStat(subject, "revived", 1);
			}
		}else if(StrEqual(name, "defibrillator_used", true)) {
			points[client]+=9;
			IncrementStat(client, "defibs_used", 1);
		}else{
			IncrementStat(client, name, 1);
		}
	}
}
public void Event_MeleeKill(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(client > 0 && !IsFakeClient(client)) {
		points[client]++;
	}
}
public void Event_TankKilled(Event event, const char[] name, bool dontBroadcast) {
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	int solo = event.GetBool("solo") ? 1 : 0;
	int melee_only = event.GetBool("melee_only") ? 1 : 0;
	if(attacker > 0 && !IsFakeClient(attacker)) {
		if(solo) {
			points[attacker]+=100;
			IncrementStat(attacker, "tanks_killed_solo", 1);
		}
		if(melee_only) {
			points[attacker]+=150;
			IncrementStat(attacker, "tanks_killed_melee", 1);
		}
		points[attacker]+=200;
		char query[256];
		Format(query, sizeof(query), "UPDATE `stats` SET tanks_killed=tanks_killed+1, tanks_killed_solo=tanks_killed_solo+%d, tanks_killed_melee=tanks_killed_melee+%d WHERE `steamid` = '%s'", solo, melee_only);
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
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(client > 0 && !IsFakeClient(client)) {
		upgradePacksDeployed[client]++;
		points[client]+=3;
	}
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
				points[i]+=400;
			}
		}
	}
}
public void Event_WitchKilled(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(client > 0 && !IsFakeClient(client)) {
		witchKills[client]++;
		points[client]+=100;
	}
}

public void Event_FinaleStart(Event event, const char[] name, bool dontBroadcast) {
	finaleTimeStart = GetTime();
}
public void Event_GrenadeDenonate(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(client > 0 && !IsFakeClient(client)) {
		char wpn_name[32];
		GetClientWeapon(client, wpn_name, sizeof(wpn_name));
		//PrintToServer("wpn_Name %s", wpn_name);
		//Somehow have to check if molotov or gr
	}
}
public void OnEntityCreated(int entity) {
	char class[32];
	GetEntityClassname(entity, class, sizeof(class));
	if(StrContains(class,"_projectile",true)) {
		for(int i=1; i<MaxClients;i++) {
			if(IsClientConnected(i) && IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == 2 && !IsFakeClient(i)) {
				int wpn = GetEntPropEnt(i, Prop_Data, "m_hActiveWeapon");
				if (IsValidEntity(wpn)) {
					char name[32];
					GetEntityClassname(wpn, name, sizeof(name));
					if(StrEqual(name, "weapon_vomitjar",true)) {
						float throwtime = GetEntPropFloat(wpn, Prop_Send, "m_fThrowTime");
						if(throwtime > 0.0) {
							IncrementStat(i, "throws_puke", 1);
							break;
						}
						//PrintToServer("[#%d (%N)] test1=%f test2=%d owner=%d", i, i, test, test2, owner);
					}else if(StrEqual(name, "weapon_molotov", true)) {
						float throwtime = GetEntPropFloat(wpn, Prop_Send, "m_fThrowTime");
						if(throwtime > 0.0) {
							IncrementStat(i, "throws_molotov", 1);
							break;
						}
					}else if(StrEqual(name, "weapon_pipe_bomb", true)) {
						float throwtime = GetEntPropFloat(wpn, Prop_Send, "m_fThrowTime");
						if(throwtime > 0.0) {
							IncrementStat(i, "throws_pipe", 1);
							break;
						}
					}
					//PrintToServer("CREATED #%d (%N): wpnid=%d wpnname=%s", i, i, wpn, name);
				}
			} 
		}
		//
	}
}

////////////////////////////
// STOCKS
///////////////////////////
stock bool GetInfectedClassName(int type, char[] buffer, int bufferSize) {
	switch(type) {
		case 1: strcopy(buffer, bufferSize, "smoker");
		case 2: strcopy(buffer, bufferSize, "boomer");
		case 3: strcopy(buffer, bufferSize, "hunter");
		case 4: strcopy(buffer, bufferSize, "spitter");
		case 5: strcopy(buffer, bufferSize, "jockey");
		case 6: strcopy(buffer, bufferSize, "charger");
		default: return false;
	}
	return true;
}
//entity abs origin code from here
//http://forums.alliedmods.net/showpost.php?s=e5dce96f11b8e938274902a8ad8e75e9&p=885168&postcount=3
stock void GetEntityAbsOrigin(int entity, float origin[3]) {
	if (entity && IsValidEntity(entity)
	&& (GetEntSendPropOffs(entity, "m_vecOrigin") != -1)
	&& (GetEntSendPropOffs(entity, "m_vecMins") != -1)
	&& (GetEntSendPropOffs(entity, "m_vecMaxs") != -1))
	{
		float mins[3], maxs[3];
		GetEntPropVector(entity, Prop_Send, "m_vecOrigin", origin);
		GetEntPropVector(entity, Prop_Send, "m_vecMins", mins);
		GetEntPropVector(entity, Prop_Send, "m_vecMaxs", maxs);
		
		origin[0] += (mins[0] + maxs[0]) * 0.5;
		origin[1] += (mins[1] + maxs[1]) * 0.5;
		origin[2] += (mins[2] + maxs[2]) * 0.5;
	}
}