#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "1.0"

//#define DEBUG 0

#define SCAN_INTERVAL 5.0
#define SCAN_RANGE 750.0
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
	url = ""
};

//TODO: convars for allowed gamemodes / difficulties


static ArrayList WitchList;
static Handle timer = INVALID_HANDLE;
static bool lateLoaded = false, AutoCrownInPosition = false;
static int AutoCrownBot = -1, AutoCrownTarget, currentDifficulty;
static float CrownPos[3], CrownAng[3];
static ConVar hValidDifficulties, hAllowedGamemodes;

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
		char classname[32];
		for(int i = MaxClients; i < 2048; i++) {
			if(IsValidEntity(i)) {
				GetEntityClassname(i, classname, sizeof(classname));
				if(StrEqual(classname, "witch", false)) {
					WitchList.Push(i);
					if(timer == INVALID_HANDLE) {
						timer = CreateTimer(SCAN_INTERVAL, Timer_Scan, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
					}
				}
			}
		}
	}

	hValidDifficulties = CreateConVar("l4d2_autocrown_allowed_difficulty", "7", "The difficulties the plugin is active on. 1=Easy, 2=Normal 4=Advanced 8=Expert. Add numbers together.", FCVAR_NONE);
	hAllowedGamemodes = CreateConVar("l4d2_autocrown_modes_tog", "1", "Turn on the plugin in these game modes. 0=All, 1=Coop, 2=Survival, 4=Versus, 8=Scavenge. Add numbers together.", FCVAR_NONE);
	
	char diff[16];
	FindConVar("z_difficulty").GetString(diff, sizeof(diff));
	currentDifficulty = GetDifficultyInt(diff);

	FindConVar("mp_gamemode").AddChangeHook(Change_Gamemode);

	AutoExecConfig(true, "l4d2_autobotcrown");

	HookEvent("witch_spawn", Event_WitchSpawn);
	HookEvent("witch_killed", Event_WitchKilled);
	HookEvent("difficulty_changed", Event_DifficultyChanged);

	RegAdminCmd("sm_ws", Cmd_Status, ADMFLAG_ROOT);
}
public Action Cmd_Status(int client, int args) {
	ReplyToCommand(client, "Scan Timer: %b | Active: %b | In Position %b | Witches %d", timer != INVALID_HANDLE, AutoCrownBot > -1, AutoCrownInPosition, WitchList.Length);
	return Plugin_Handled;
}
public void Event_DifficultyChanged(Event event, const char[] name, bool dontBroadcast) {
	char diff[16];
	event.GetString("newDifficulty", diff, sizeof(diff));
	currentDifficulty = GetDifficultyInt(diff);
	if(hAllowedGamemodes.IntValue & currentDifficulty > 0) {
		if(timer == INVALID_HANDLE && AutoCrownBot == -1) {
			timer = CreateTimer(SCAN_INTERVAL, Timer_Scan, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
		}
	}else{
		CloseHandle(timer);
	}
}
public void Change_Gamemode(ConVar convar, const char[] oldValue, const char[] newValue) {
	if(StrEqual(newValue, "realism")) {
		CloseHandle(timer);
	}

}

public bool IsGamemodeAllowed() {
	return true;
}

public Action Event_WitchSpawn(Event event, const char[] name, bool dontBroadcast) {
	int witchID = event.GetInt("witchid");
	WitchList.Push(witchID);
	#if defined DEBUG
	PrintToServer("Witch spawned: %d", witchID);
	#endif
	if(timer == INVALID_HANDLE && AutoCrownBot == -1) {
		timer = CreateTimer(SCAN_INTERVAL, Timer_Scan, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	}
}

public Action Event_WitchKilled(Event event, const char[] name, bool dontBroadcast) {
	int witchID = event.GetInt("witchid");
	int index = FindValueInArray(WitchList, witchID);
	#if defined DEBUG
	PrintToServer("Witched killed: %d", witchID);
	#endif
	if(index > -1) {
		RemoveFromArray(WitchList, index);
	}
	if(AutoCrownTarget == witchID) {
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
	if(AutoCrownBot > -1) {
		int client = GetClientOfUserId(AutoCrownBot);
		if(!IsValidEntity(AutoCrownTarget)) {
			ResetAutoCrown();
			
			#if defined DEBUG
			PrintToServer("Could not find valid AutoCrownTarget");
			#endif
			return Plugin_Stop;
		}else if(client <= 0 || !IsClientConnected(client) || !IsClientInGame(client) || !IsPlayerAlive(client)) {
			AutoCrownBot = -1;
			AutoCrownTarget = -1;
			#if defined DEBUG
			PrintToServer("Could not find valid AutoCrownBot");
			#endif
			return Plugin_Stop;
		}

		GetEntPropVector(AutoCrownTarget, Prop_Send, "m_vecOrigin", witchPos);
		GetClientAbsOrigin(client, botPosition);

		float distance = GetVectorDistance(botPosition, witchPos);
		if(distance <= 60) {
			float botAngles[3];
			GetClientAbsAngles(client, botAngles);
			botAngles[0] = 60.0; 
			botAngles[1] = RadToDeg(ArcTangent2( botPosition[1] - witchPos[1], botPosition[0] - witchPos[0])) + 180.0;
			//Is In Position

			ClientCommand(client, "slot0");
			TeleportEntity(client, NULL_VECTOR, botAngles, NULL_VECTOR);
			AutoCrownInPosition = true;
		}else{
			L4D2_RunScript("CommandABot({cmd=1,bot=GetPlayerFromUserID(%i),pos=Vector(%f,%f,%f)})", AutoCrownBot, witchPos[0], witchPos[1], witchPos[2]);
		}
		return Plugin_Continue;
	}else{
		timer = CreateTimer(SCAN_INTERVAL, Timer_Scan, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
		return Plugin_Stop;
	}
}
public Action Timer_Scan(Handle hdl) {
	float botPosition[3], witchPos[3];
	if(WitchList.Length == 0) {
		#if defined DEBUG
		PrintToServer("No witches detected, ending timer");
		#endif
		return Plugin_Stop;
	}
	for(int bot = 1; bot < MaxClients+1; bot++) {
		if(IsClientConnected(bot) && IsClientInGame(bot) && IsFakeClient(bot) && IsPlayerAlive(bot)) {
			//Check if bot has a valid shotgun, with ammo (probably can skip: bot mostly will be full).
			if(GetClientHealth(bot) > 40) {
				char wpn[32];
				if(GetClientWeapon(bot, wpn, sizeof(wpn)) && 
					StrEqual(wpn, "weapon_autoshotgun") || StrEqual(wpn, "weapon_shotgun_spas")
				) {
					GetClientAbsOrigin(bot, botPosition);
					
					for(int i = 0; i < WitchList.Length; i++) {
						int witchID = WitchList.Get(i);
						if(IsValidEntity(witchID) && HasEntProp(witchID, Prop_Send, "m_rage") && GetEntPropFloat(witchID, Prop_Send, "m_rage") <= 0.4) {
							GetEntPropVector(witchID, Prop_Send, "m_vecOrigin", witchPos);
							if(GetVectorDistance(botPosition, witchPos) <= SCAN_RANGE) {
								//GetEntPropVector(witchID, Prop_Send, "m_angRotation", witchAng);
								//TODO: Implement a line-of-sight trace
								#if defined DEBUG
								PrintToServer("Found a valid witch in range of %N: %d", bot, witchID);
								#endif
								L4D2_RunScript("CommandABot({cmd=1,bot=GetPlayerFromUserID(%i),pos=Vector(%f,%f,%f)})", GetClientUserId(bot), witchPos[0], witchPos[1], witchPos[2]);
								AutoCrownTarget = witchID;
								AutoCrownBot = GetClientUserId(bot);
								AutoCrownInPosition = false;
								CreateTimer(ACTIVE_INTERVAL, Timer_Active, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
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
}

public Action OnPlayerRunCmd(int client, int& buttons, int& impulse, float vel[3], float angles[3], int& weapon, int& subtype, int& cmdnum, int& tickcount, int& seed, int mouse[2]) {
	if(AutoCrownInPosition && GetClientOfUserId(AutoCrownBot) == client && !(buttons & IN_ATTACK)) {
		buttons |= IN_ATTACK;
		//CreateTimer(0.4, Timer_StopFiring);
		return Plugin_Changed;
	}
	return Plugin_Continue;
}

public void ResetAutoCrown() {
	AutoCrownTarget = -1;
	AutoCrownInPosition = false;
	if(AutoCrownBot > -1)
		L4D2_RunScript("CommandABot({cmd=3,bot=GetPlayerFromUserID(%i)})", AutoCrownBot); 
	AutoCrownBot = -1;
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