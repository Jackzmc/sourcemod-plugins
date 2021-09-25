#include <sourcemod>
#include <sdktools>
#include <left4dhooks>

#pragma semicolon 1
#pragma newdecls required

ConVar g_cvSurvivorSet;

public Plugin myinfo =  
{ 
	name = "[L4D2] Survivor Set Enforcer", 
	author = "DeathChaos, modified by Psyk0tik (Crasher_3637)", 
	description = "Forces L4D2 survivor set.", 
	version = "1.0",
	url = ""
};

public void OnPluginStart() 
{ 
	g_cvSurvivorSet = CreateConVar("l4d_force_survivorset", "0", "Forces specified survivor set (0 - no change, 1 - force L4D1, 2 - Force L4D2)", _, true, 0.0, true, 2.0);
} 

public Action L4D_OnGetSurvivorSet(int &retVal)
{
	int iSet = g_cvSurvivorSet.IntValue;
	if (iSet > 0)
	{
		retVal = iSet;

		return Plugin_Handled;
	}

	return Plugin_Continue;
}

public Action L4D_OnFastGetSurvivorSet(int &retVal)
{
	int iSet = g_cvSurvivorSet.IntValue;
	if (iSet > 0)
	{
		retVal = iSet;

		return Plugin_Handled;
	}

	return Plugin_Continue;
}