#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "1.0"

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


static ArrayList WitchList;
static Handle timer = INVALID_HANDLE;
static bool lateLoaded = false, AutoCrownInPosition = false;
static int AutoCrownBot = -1, AutoCrownTarget;
static float CrownPos[3], CrownAng[3];

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
	if(late) lateLoaded = true;
} 

public void OnPluginStart()
{
	EngineVersion g_Game = GetEngineVersion();
	if(g_Game != Engine_Left4Dead && g_Game != Engine_Left4Dead2) {
		SetFailState("This plugin is for L4D/L4D2 only.");	
	}

	WitchList = new ArrayList(1, 1);
	if(lateLoaded) {
		char classname[32];
		for(int i = MaxClients; i < 2048; i++) {
			if(IsValidEntity(i)) {
				GetEntityClassname(i, classname, sizeof(classname));
				if(StrEqual(classname, "witch", false)) {
					WitchList.Push(i);
					if(timer == INVALID_HANDLE) {
						timer = CreateTimer(0.4, Timer_BotControlTimer, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
					}
				}
			}
		}
	}

	HookEvent("witch_spawn", Event_WitchSpawn);
	HookEvent("witch_killed", Event_WitchKilled);

}


public Action Event_WitchSpawn(Event event, const char[] name, bool dontBroadcast) {
	int witchID = event.GetInt("witchid");
	WitchList.Push(witchID);
	#if defined DEBUG
	PrintToServer("Witch spawned: %d", witchID);
	#endif
	if(timer == INVALID_HANDLE) {
		timer = CreateTimer(0.4, Timer_BotControlTimer, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
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
	if(WitchList.Length == 0) {
		CloseHandle(timer);
	}
	if(AutoCrownTarget == witchID) {
		ResetAutoCrown();
		#if defined DEBUG
		PrintToServer("AutoCrownTarget has died");
		#endif
	}
}

public Action Timer_BotControlTimer(Handle hdl) {
	float botPosition[3], witchPos[3];
	if(WitchList.Length == 0) {
		#if defined DEBUG
		PrintToServer("No witches detected, ending timer");
		#endif
		return Plugin_Stop;
	}
	//TODO: Also check if startled and cancel it immediately. 
	if(AutoCrownBot > -1) {
		GetEntPropVector(AutoCrownTarget, Prop_Send, "m_vecOrigin", witchPos);
		GetClientAbsOrigin(AutoCrownBot, botPosition);

		if(!IsValidEntity(AutoCrownTarget)) {
			ResetAutoCrown();
			
			#if defined DEBUG
			PrintToServer("Could not find valid AutoCrownTarget");
			#endif
		}else if(!IsClientConnected(AutoCrownBot) || !IsPlayerAlive(AutoCrownBot)) {
			AutoCrownBot = -1;
			AutoCrownTarget = -1;
			#if defined DEBUG
			PrintToServer("Could not find valid AutoCrownBot");
			#endif
		}

		float distance = GetVectorDistance(botPosition, witchPos);
		if(distance <= 60) {
			float botAngles[3];
			GetClientAbsAngles(AutoCrownBot, botAngles);
			botAngles[0] = 60.0; 
			botAngles[1] = RadToDeg(ArcTangent2( botPosition[1] - witchPos[1], botPosition[0] - witchPos[0])) + 180.0;
			//Is In Position

			ClientCommand(AutoCrownBot, "slot0");
			TeleportEntity(AutoCrownBot, NULL_VECTOR, botAngles, NULL_VECTOR);
			AutoCrownInPosition = true;
		}else{
			L4D2_RunScript("CommandABot({cmd=1,bot=GetPlayerFromUserID(%i),pos=Vector(%f,%f,%f)})", GetClientUserId(AutoCrownBot), witchPos[0], witchPos[1], witchPos[2]);
		}
		return Plugin_Continue;
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
						if(IsValidEntity(witchID) && GetEntPropFloat(witchID, Prop_Send, "m_rage") <= 0.4) {
							GetEntPropVector(witchID, Prop_Send, "m_vecOrigin", witchPos);
							//TODO: Calculate closest witch
							if(GetVectorDistance(botPosition, witchPos) <= 570) {
								//GetEntPropVector(witchID, Prop_Send, "m_angRotation", witchAng);

								L4D2_RunScript("CommandABot({cmd=1,bot=GetPlayerFromUserID(%i),pos=Vector(%f,%f,%f)})", GetClientUserId(bot), witchPos[0], witchPos[1], witchPos[2]);
								AutoCrownTarget = witchID;
								AutoCrownBot = bot;
								AutoCrownInPosition = false;
								return Plugin_Continue;
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
	if(AutoCrownInPosition && AutoCrownBot == client && !(buttons & IN_ATTACK)) {
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
		L4D2_RunScript("CommandABot({cmd=3,bot=GetPlayerFromUserID(%i)})", GetClientUserId(AutoCrownBot)); 
	AutoCrownBot = -1;

}