#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "1.0"

//#define DEBUG 0

#define SCAN_INTERVAL 4.0
#define SCAN_RANGE 570.0
#define ACTIVE_INTERVAL 0.4

#include <sourcemod>
#include <sdktools>
#include <adt_array>
#include "jutils.inc"

public Plugin myinfo = 
{
	name =  "L4D2 Auto Bot Witch Crown", 
	author = "jackzmc", 
	description = "Makes bots automatically crown a witch in cases where a witch is blocking the way", 
	version = PLUGIN_VERSION, 
	url = "https://github.com/Jackzmc/sourcemod-plugins"
};

//TODO: convars for allowed gamemodes / difficulties


static ArrayList WitchList;
static Handle timer = INVALID_HANDLE;
static bool lateLoaded = false, AutoCrownInPosition = false;
static int AutoCrownBot = -1, AutoCrownTarget, currentDifficulty, PathfindTries = 0;
static float CrownPos[3], CrownAng[3];
static ConVar hValidDifficulties, hAllowedGamemodes;

float TRACE_MIN_SIZE[3] = {0.0, 0.0, 0.0}, TRACE_MAX_SIZE[3] = {1.0, 1.0, 1.0};


public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
	if(late) lateLoaded = true;
} 

public void OnPluginStart()
{
	EngineVersion g_Game = GetEngineVersion();
	if(g_Game != Engine_Left4Dead && g_Game != Engine_Left4Dead2) {
		SetFailState("This plugin is for L4D/L4D2 only.");	
	}

	WitchList = new ArrayList(1, 0);
	if(lateLoaded) {
		char classname[8];
		for(int i = MaxClients; i < 2048; i++) {
			if(IsValidEntity(i)) {
				GetEntityClassname(i, classname, sizeof(classname));
				if(StrEqual(classname, "witch", false)) {
					if(HasEntProp(i, Prop_Send, "m_rage")) {
						WitchList.Push(EntIndexToEntRef(i));
						#if defined DEBUG
						PrintToServer("Found pre-existing witch %d", i);
						#endif
					}
					
				}
			}
		}
		if(timer == INVALID_HANDLE && WitchList.Length > 0) {
			timer = CreateTimer(SCAN_INTERVAL, Timer_Scan, _, TIMER_REPEAT);
		}
	}

	hValidDifficulties = CreateConVar("l4d2_autocrown_allowed_difficulty", "7", "The difficulties the plugin is active on. 1=Easy, 2=Normal 4=Advanced 8=Expert. Add numbers together.", FCVAR_NONE);
	hAllowedGamemodes = CreateConVar("l4d2_autocrown_modes_tog", "1", "Turn on the plugin in these game modes. 0=All, 1=Coop, 2=Survival, 4=Versus, 8=Scavenge, 16=Other. Add numbers together.", FCVAR_NONE);
	
	char diff[16];
	FindConVar("z_difficulty").GetString(diff, sizeof(diff));
	currentDifficulty = GetDifficultyInt(diff);

	FindConVar("mp_gamemode").AddChangeHook(Change_Gamemode);

	AutoExecConfig(true, "l4d2_autobotcrown");

	HookEvent("witch_spawn", Event_WitchSpawn);
	HookEvent("witch_killed", Event_WitchKilled);
	HookEvent("difficulty_changed", Event_DifficultyChanged);

	RegAdminCmd("sm_ws", Cmd_Status, ADMFLAG_ROOT);

	#if defined DEBUG
	CreateTimer(0.6, Timer_Debug, _, TIMER_REPEAT);
	#endif
}

#if defined DEBUG
public Action Timer_Debug(Handle timer) {
	PrintHintTextToAll("Scan Timer: %b | Active: %b | In Position %b | Witches %d | Bot %N", timer != INVALID_HANDLE, AutoCrownBot > -1, AutoCrownInPosition, WitchList.Length, GetClientOfUserId(AutoCrownBot));
	return Plugin_Continue;
}
#endif


public Action Cmd_Status(int client, int args) {
	ReplyToCommand(client, "Scan Timer: %b | Active: %b | In Position %b | Witches %d | Bot %N", timer != INVALID_HANDLE, AutoCrownBot > -1, AutoCrownInPosition, WitchList.Length, GetClientOfUserId(AutoCrownBot));
	return Plugin_Handled;
}
public void Event_DifficultyChanged(Event event, const char[] name, bool dontBroadcast) {
	char diff[16];
	event.GetString("newDifficulty", diff, sizeof(diff));
	currentDifficulty = GetDifficultyInt(diff);
	if(hValidDifficulties.IntValue & currentDifficulty > 0) {
		if(timer == INVALID_HANDLE && AutoCrownBot == -1) {
			timer = CreateTimer(SCAN_INTERVAL, Timer_Scan, _, TIMER_REPEAT);
		}
	}else{
		delete timer;
	}
}
public void Change_Gamemode(ConVar convar, const char[] oldValue, const char[] newValue) {
	int c0 = CharToLower(newValue[0]);
	int c1 = CharToLower(newValue[1]);
	bool enable = false;
	if(c0 == 'c' && hAllowedGamemodes.IntValue & 1) { //co-op
		enable = true;
	} else if(c0 == 's' && c1 == 'u' && hAllowedGamemodes.IntValue & 2) { //survival
		enable = true;
	} else if(c0 == 'v' && hAllowedGamemodes.IntValue & 4) { //versus
		enable = true;
	} else if(c0 == 's' && c1 == 'c' && hAllowedGamemodes.IntValue & 8) { //scavenge
		enable = true;
	} else if(hAllowedGamemodes.IntValue & 16)
		enable = true;

	if(enable) {
		if(timer == INVALID_HANDLE && AutoCrownBot == -1) {
			timer = CreateTimer(SCAN_INTERVAL, Timer_Scan, _, TIMER_REPEAT);
		}
	} else delete timer;

}

public void Event_WitchSpawn(Event event, const char[] name, bool dontBroadcast) {
	int witchID = event.GetInt("witchid");
	if(HasEntProp(witchID, Prop_Send, "m_rage")) {
		WitchList.Push(EntIndexToEntRef(witchID));
		#if defined DEBUG
		PrintToServer("Witch spawned: %d", witchID);
		#endif
		//If not currently scanning, begin scanning ONLY if not active
		if(timer == INVALID_HANDLE && AutoCrownBot == -1) {
			timer = CreateTimer(SCAN_INTERVAL, Timer_Scan, _, TIMER_REPEAT);
		}
	}
}

public void Event_WitchKilled(Event event, const char[] name, bool dontBroadcast) {
	int witchRef = EntIndexToEntRef(event.GetInt("witchid"));
	int index = WitchList.FindValue(witchRef);
	if(index > -1) {
		WitchList.Erase(index);
	}
	//If witch that was killed, terminate active loop
	if(AutoCrownTarget == witchRef) {
		ResetAutoCrown();
		#if defined DEBUG
		PrintToServer("AutoCrownTarget has died");
		#endif
	}
}
public Action Timer_Active(Handle hdl) {
	float botPosition[3], witchPos[3];
	if(WitchList.Length == 0) {
		#if defined DEBUG
		PrintToServer("No witches detected, ending timer");
		#endif
		return Plugin_Stop;
	}
	//TODO: Also check if startled and cancel it immediately. 
	if(AutoCrownBot == -1) {
		timer = CreateTimer(SCAN_INTERVAL, Timer_Scan, _, TIMER_REPEAT);
		return Plugin_Stop;
	}

	int client = GetClientOfUserId(AutoCrownBot);
	int crownTarget = EntRefToEntIndex(AutoCrownTarget);
	if(crownTarget == INVALID_ENT_REFERENCE) {
		ResetAutoCrown();
		
		#if defined DEBUG
		PrintToServer("Could not find valid AutoCrownTarget");
		#endif
		return Plugin_Stop;
	}else if(client <= 0 || !IsPlayerAlive(client)) {
		ResetAutoCrown();
		#if defined DEBUG
		PrintToServer("Could not find valid AutoCrownBot");
		#endif
		return Plugin_Stop;
	}

	char wpn[32];
	if(!GetClientWeapon(client, wpn, sizeof(wpn)) || !StrEqual(wpn, "weapon_autoshotgun") && !StrEqual(wpn, "weapon_shotgun_spas")) {
		ResetAutoCrown();
		#if defined DEBUG
		PrintToServer("AutoCrownBot does not have a valid weapon (%s)", wpn);
		#endif
		return Plugin_Stop;
	}

	GetEntPropVector(crownTarget, Prop_Send, "m_vecOrigin", witchPos);
	GetClientAbsOrigin(client, botPosition);

	float distance = GetVectorDistance(botPosition, witchPos, true);
	if(distance <= 3600) {
		float botAngles[3];
		GetClientAbsAngles(client, botAngles);
		botAngles[0] = 60.0; 
		botAngles[1] = RadToDeg(ArcTangent2(botPosition[1] - witchPos[1], botPosition[0] - witchPos[0])) + 180.0;
		//Is In Position

		ClientCommand(client, "slot0");
		TeleportEntity(client, NULL_VECTOR, botAngles, NULL_VECTOR);
		AutoCrownInPosition = true;
	} else {
		L4D2_RunScript("CommandABot({cmd=1,bot=GetPlayerFromUserID(%i),pos=Vector(%f,%f,%f)})", AutoCrownBot, witchPos[0], witchPos[1], witchPos[2]);
		PathfindTries++;
	}

	if(PathfindTries > 40) {
		ResetAutoCrown();
		int index = WitchList.FindValue(AutoCrownTarget);
		if(index > -1)
			WitchList.Erase(index);
		//remove witch
		#if defined DEBUG
		PrintToServer("Could not pathfind to witch in time.");
		#endif
	}
	return Plugin_Continue;
}
public Action Timer_Scan(Handle hdl) {
	float botPosition[3], witchPos[3];
	if(WitchList.Length == 0) {
		#if defined DEBUG
		PrintToServer("No witches detected, ending timer");
		#endif
		timer = INVALID_HANDLE;
		return Plugin_Stop;
	}
	for(int bot = 1; bot <= MaxClients; bot++) {
		if(IsClientConnected(bot) && IsClientInGame(bot) && IsFakeClient(bot) && IsPlayerAlive(bot)) {
			//Check if bot has a valid shotgun, with ammo (probably can skip: bot mostly will be full).
			if(GetClientHealth(bot) > 40) {
				char wpn[32];
				if(GetClientWeapon(bot, wpn, sizeof(wpn)) && (StrEqual(wpn, "weapon_autoshotgun") || StrEqual(wpn, "weapon_shotgun_spas"))) {
					GetClientAbsOrigin(bot, botPosition);
					
					//Loop all witches, find any valid nearby witches:
					for(int i = 0; i < WitchList.Length; i++) {
						int witchRef = WitchList.Get(i);
						int witchID = EntRefToEntIndex(witchRef);
						if(witchID == INVALID_ENT_REFERENCE) {
							WitchList.Erase(i);
							continue;
						}
						if(GetEntPropFloat(witchID, Prop_Send, "m_rage") <= 0.4) {
							GetEntPropVector(witchID, Prop_Send, "m_vecOrigin", witchPos);
							if(GetVectorDistance(botPosition, witchPos) <= SCAN_RANGE) {
								//GetEntPropVector(witchID, Prop_Send, "m_angRotation", witchAng);
								#if defined DEBUG
								PrintToServer("Found a valid witch in range of %N: %d", bot, witchID);
								PrintToChatAll("Found a valid witch in range of %N: %d", bot, witchID);
								#endif

								L4D2_RunScript("CommandABot({cmd=1,bot=GetPlayerFromUserID(%i),pos=Vector(%f,%f,%f)})", GetClientUserId(bot), witchPos[0], witchPos[1], witchPos[2]);
								AutoCrownTarget = witchRef;
								AutoCrownBot = GetClientUserId(bot);
								AutoCrownInPosition = false;
								CreateTimer(ACTIVE_INTERVAL, Timer_Active, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
								timer = INVALID_HANDLE;
								return Plugin_Stop;
							}
						}
					}
				}
			}
		}
	}
	return Plugin_Continue;
}

public Action Timer_StopFiring(Handle hdl) {
	ResetAutoCrown();
	return Plugin_Handled;
}

public Action OnPlayerRunCmd(int client, int& buttons, int& impulse, float vel[3], float angles[3], int& weapon, int& subtype, int& cmdnum, int& tickcount, int& seed, int mouse[2]) {
	if(AutoCrownInPosition && GetClientOfUserId(AutoCrownBot) == client && !(buttons & IN_ATTACK)) {
		buttons |= IN_ATTACK;
		return Plugin_Changed;
	}
	return Plugin_Continue;
}

public void ResetAutoCrown() {
	AutoCrownTarget = INVALID_ENT_REFERENCE;
	AutoCrownInPosition = false;
	if(AutoCrownBot > -1)
		L4D2_RunScript("CommandABot({cmd=3,bot=GetPlayerFromUserID(%i)})", AutoCrownBot); 
	AutoCrownBot = -1;
	PathfindTries = 0;
	if(timer != INVALID_HANDLE) {
		CloseHandle(timer);
		timer = INVALID_HANDLE;
	}
}

public void OnMapStart() {
	WitchList.Clear();
	ResetAutoCrown();
}
public void OnMapEnd() {
	if(timer != INVALID_HANDLE) {
		CloseHandle(timer);
		timer = INVALID_HANDLE;
	}
	WitchList.Clear();
}

int GetDifficultyInt(const char[] type) {
	if(StrEqual(type, "impossible")) {
		return 8;
	}else if(StrEqual(type, "hard")) {
		return 4;
	}else if(StrEqual(type, "normal")) {
		return 2;
	}else{
		return 1;
	}
}

stock bool IsPlayerIncapped(int client) {
	return GetEntProp(client, Prop_Send, "m_isIncapacitated") == 1;
}