/**
*	 ___      _______  _______  _______    _   ___    ______   _______  _______  ______
*	|   |    |       ||       ||       |  | | |   |  |      | |       ||   _   ||      |
*	|   |    |    ___||    ___||_     _|  | |_|   |  |  _    ||    ___||  |_|  ||  _    |
*	|   |    |   |___ |   |___   |   |    |       |  | | |   ||   |___ |       || | |   |
*	|   |___ |    ___||    ___|  |   |    |___    |  | |_|   ||    ___||       || |_|   |
*	|       ||   |___ |   |      |   |        |   |  |       ||   |___ |   _   ||       |
*	|_______||_______||___|      |___|        |___|  |______| |_______||__| |__||______|
*	
*	This include contains a ton of useful stocks and functions you can use for Left 4 Dead (2).
*	Author: Keith Warren (Drixevel)
*	https://github.com/Drixevel
*
*	NOTE: The best way to use this include is to copy and paste into your projects manually.
*	Credits: 
**/

#if defined _misc_l4d_included
 #endinput
#endif
#define _misc_l4d_included

enum L4DGame
{
	L4DGame_L4D = 0,
	L4DGame_L4D2 = 1
}

enum L4DTeam
{
	L4DTeam_Unassigned = 0,
	L4DTeam_Spectator = 1,
	L4DTeam_Survivors = 2,
	L4DTeam_Infected = 3
}

enum L4DSurvivor
{
	L4DSurvivor_Bill = 0,
	L4DSurvivor_Zoey = 1,
	L4DSurvivor_Louis = 2,
	L4DSurvivor_Francis = 3
}

enum L4D2Survivor
{
	L4D2Survivor_Nick = 0,
	L4D2Survivor_Rochelle = 1,
	L4D2Survivor_Coach = 2,
	L4D2Survivor_Ellis = 3
}

enum L4DInfected
{
	L4DInfected_None = 0,
	L4DInfected_Smoker = 1,
	L4DInfected_Boomer = 2,
	L4DInfected_Hunter = 3,
	L4DInfected_Witch = 4,
	L4DInfected_Tank = 5
}

enum L4D2Infected
{
	L4D2Infected_None = 0,
	L4D2Infected_Smoker = 1,
	L4D2Infected_Boomer = 2,
	L4D2Infected_Hunter = 3,
	L4D2Infected_Spitter = 4,
	L4D2Infected_Jockey = 5,
	L4D2Infected_Charger = 6,
	L4D2Infected_Witch = 7,
	L4D2Infected_Tank = 8
}

/**
 * Gets a client's current team.
 *
 * @param client		Client index.
 * @return				Current L4DTeam of client.
 * @error				Invalid client index.
 */
stock L4DTeam L4D_GetClientTeam(int client)
{
	return view_as<L4DTeam>(GetClientTeam(client));
}

/**
 * Gets the current group of survivors assigned to the map.
 * @return			L4DGame enum index.
 */
stock L4DGame L4D_GetSurvivorGroup()
{
	int entity = -1; char sCharacter[32];
	while ((entity = FindEntityByClassname(entity, "info_survivor_position")) != -1)
	{
		GetEntPropString(entity, Prop_Data, "m_iszSurvivorName", sCharacter, sizeof(sCharacter));

		if (strlen(sCharacter) > 0 && (StrEqual(sCharacter, "Bill") || StrEqual(sCharacter, "Zoey") || StrEqual(sCharacter, "Louis") || StrEqual(sCharacter, "Francis")))
			return L4DGame_L4D;
	}

	return L4DGame_L4D2;
}

/**
 * Checks if the survivor is incapped.
 *
 * @param client	Players index.
 * @return			True if player is incapacitated, false otherwise.
 */
stock bool L4D_IsClientIncapacitated(int client)
{
	return view_as<bool>(GetEntProp(client, Prop_Send, "m_isIncapacitated"));
}

stock bool L4D_IsClientIncapped(int client)
{
	return view_as<bool>(GetEntProp(client, Prop_Send, "m_isIncapacitated"));
}

/**
 * Checks if the survivor is capped.
 *
 * @param client	Players index.
 * @return			True if the player is capped, false otherwise.
 */
stock bool L4D_IsPlayerCapped(int client)
{
	if(GetEntPropEnt(client, Prop_Send, "m_pummelAttacker") > 0 || 
		GetEntPropEnt(client, Prop_Send, "m_carryAttacker") > 0 || 
		GetEntPropEnt(client, Prop_Send, "m_pounceAttacker") > 0 || 
		GetEntPropEnt(client, Prop_Send, "m_jockeyAttacker") > 0 || 
		GetEntPropEnt(client, Prop_Send, "m_pounceAttacker") > 0 ||
		GetEntPropEnt(client, Prop_Send, "m_tongueOwner") > 0)
		return true;
	return false;
}

/*********************************************************************/
/*********************************************************************/
//Survivors
/*********************************************************************/
/*********************************************************************/

/**
 * Retrieves the survivor ID of the client for L4D.
 *
 * @param client	Players index.
 * @return			Index of the survivor, -1 otherwise.
 */
stock L4DSurvivor L4D_GetClientSurvivorId(int client)
{
	int offset = FindSendPropInfo("CTerrorPlayer", "m_survivorCharacter");
	return view_as<L4DSurvivor>(GetEntData(client, offset, 1));
}

/**
 * Retrieves the survivor ID of the client for L4D2.
 *
 * @param client	Players index.
 * @return			Index of the survivor, -1 otherwise.
 */
stock L4D2Survivor L4D2_GetClientSurvivorId(int client)
{
	int offset = FindSendPropInfo("CTerrorPlayer", "m_survivorCharacter");
	return view_as<L4D2Survivor>(GetEntData(client, offset, 1));
}

/**
 * Retrieves the survivor name of the client for L4D.
 *
 * @param client	Players index.
 * @return			True if found, false otherwise.
 */
stock bool L4D_GetClientSurvivorName(int client, char[] name, int size)
{
	return L4D_GetSurvivorName(L4D_GetClientSurvivorId(client), name, size);
}

/**
 * Retrieves the survivor name of the client for L4D2.
 *
 * @param client	Players index.
 * @return			True if found, false otherwise.
 */
stock bool L4D2_GetClientSurvivorName(int client, char[] name, int size)
{
	return L4D2_GetSurvivorName(L4D2_GetClientSurvivorId(client), name, size);
}

/**
 * Retrieves the ID of any of the L4D survivors.
 *
 * @param name		Name of the survivor.
 * @return			The ID of the survivor, -1 for not found.
 */
stock L4DSurvivor L4D_GetSurvivorID(const char[] name)
{
	if (StrEqual(name, "bill", false))
		return L4DSurvivor_Bill;
	else if (StrEqual(name, "zoey", false))
		return L4DSurvivor_Zoey;
	else if (StrEqual(name, "louis", false))
		return L4DSurvivor_Louis;
	else if (StrEqual(name, "francis", false))
		return L4DSurvivor_Francis;
	
	return -1;
}

/**
 * Retrieves the ID of any of the L4D2 survivors.
 *
 * @param name		Name of the survivor.
 * @return			The ID of the survivor, -1 for not found.
 */
stock L4D2Survivor L4D2_GetSurvivorID(const char[] name)
{
	if (StrEqual(name, "nick", false))
		return L4D2Survivor_Nick;
	else if (StrEqual(name, "rochelle", false))
		return L4D2Survivor_Rochelle;
	else if (StrEqual(name, "coach", false))
		return L4D2Survivor_Coach;
	else if (StrEqual(name, "ellis", false))
		return L4D2Survivor_Ellis;
	
	return -1;
}

/**
 * Retrieves the name of any of the L4D survivors.
 *
 * @param id		ID of the survivor.
 * @return			True if found and buffer filled, false otherwise.
 */
stock bool L4D_GetSurvivorName(L4DSurvivor id, char[] name, int size, bool capitalize = false)
{
	switch (id)
	{
		case L4DSurvivor_Bill:
		{
			strcopy(name, size, capitalize ? "Bill" : "bill");
			return true;
		}
		case L4DSurvivor_Zoey:
		{
			strcopy(name, size, capitalize ? "Zoey" : "zoey");
			return true;
		}
		case L4DSurvivor_Louis:
		{
			strcopy(name, size, capitalize ? "Louis" : "louis");
			return true;
		}
		case L4DSurvivor_Francis:
		{
			strcopy(name, size, capitalize ? "Francis" : "francis");
			return true;
		}
	}
	
	return false;
}

/**
 * Retrieves the name of any of the L4D2 survivors.
 *
 * @param id		ID of the survivor.
 * @return			True if found and buffer filled, false otherwise.
 */
stock bool L4D2_GetSurvivorName(L4D2Survivor id, char[] name, int size, bool capitalize = false)
{
	switch (id)
	{
		case L4D2Survivor_Nick:
		{
			strcopy(name, size, capitalize ? "Nick" : "nick");
			return true;
		}
		case L4D2Survivor_Rochelle:
		{
			strcopy(name, size, capitalize ? "Rochelle" : "rochelle");
			return true;
		}
		case L4D2Survivor_Coach:
		{
			strcopy(name, size, capitalize ? "Coach" : "coach");
			return true;
		}
		case L4D2Survivor_Ellis:
		{
			strcopy(name, size, capitalize ? "Ellis" : "ellis");
			return true;
		}
	}
	
	return false;
}

/*********************************************************************/
/*********************************************************************/
//Infected
/*********************************************************************/
/*********************************************************************/

/**
 * Retrieves the infected ID of the client for L4D.
 *
 * @param client	Players index.
 * @return			Index of the infected, -1 otherwise.
 */
stock L4DInfected L4D_GetClientInfectedId(int client)
{
	return view_as<L4DInfected>(GetEntProp(client, Prop_Send, "m_zombieClass"));
}

/**
 * Retrieves the infected ID of the client for L4D2.
 *
 * @param client	Players index.
 * @return			Index of the infected, -1 otherwise.
 */
stock L4D2Infected L4D2_GetClientInfectedId(int client)
{
	return view_as<L4D2Infected>(GetEntProp(client, Prop_Send, "m_zombieClass"));
}

/**
 * Retrieves the infected name of the client for L4D.
 *
 * @param client	Players index.
 * @return			True if found, false otherwise.
 */
stock bool L4D_GetClientInfectedName(int client, char[] name, int size)
{
	return L4D_GetInfectedName(L4D_GetClientInfectedId(client), name, size);
}

/**
 * Retrieves the infected name of the client for L4D2.
 *
 * @param client	Players index.
 * @return			True if found, false otherwise.
 */
stock bool L4D2_GetClientInfectedName(int client, char[] name, int size)
{
	return L4D2_GetInfectedName(L4D2_GetClientInfectedId(client), name, size);
}

/**
 * Retrieves the ID of any of the L4D infected.
 *
 * @param name		Name of the infected.
 * @return			The ID of the infected, -1 for not found.
 */
stock L4DInfected L4D_GetInfectedID(const char[] name)
{
	if (StrEqual(name, "smoker", false))
		return L4DInfected_Smoker;
	else if (StrEqual(name, "boomer", false))
		return L4DInfected_Boomer;
	else if (StrEqual(name, "hunter", false))
		return L4DInfected_Hunter;
	else if (StrEqual(name, "witch", false))
		return L4DInfected_Witch;
	else if (StrEqual(name, "tank", false))
		return L4DInfected_Tank;
	
	return L4DInfected_None;
}

/**
 * Retrieves the ID of any of the L4D2 infected.
 *
 * @param name		Name of the infected.
 * @return			The ID of the infected, -1 for not found.
 */
stock L4D2Infected L4D2_GetInfectedID(const char[] name)
{
	if (StrEqual(name, "smoker", false))
		return L4D2Infected_Smoker;
	else if (StrEqual(name, "boomer", false))
		return L4D2Infected_Boomer;
	else if (StrEqual(name, "hunter", false))
		return L4D2Infected_Hunter;
	else if (StrEqual(name, "spitter", false))
		return L4D2Infected_Spitter;
	else if (StrEqual(name, "charger", false))
		return L4D2Infected_Charger;
	else if (StrEqual(name, "jockey", false))
		return L4D2Infected_Jockey;
	else if (StrEqual(name, "witch", false))
		return L4D2Infected_Witch;
	else if (StrEqual(name, "tank", false))
		return L4D2Infected_Tank;
	
	return L4D2Infected_None;
}

/**
 * Retrieves the name of any of the L4D infected.
 *
 * @param id		ID of the infected.
 * @return			True if found and buffer filled, false otherwise.
 */
stock bool L4D_GetInfectedName(L4DInfected id, char[] name, int size, bool capitalize = false)
{
	switch (id)
	{
		case L4DInfected_None:
			return false;
		case L4DInfected_Smoker:
		{
			strcopy(name, size, capitalize ? "Smoker" : "smoker");
			return true;
		}
		case L4DInfected_Boomer:
		{
			strcopy(name, size, capitalize ? "Boomer" : "boomer");
			return true;
		}
		case L4DInfected_Hunter:
		{
			strcopy(name, size, capitalize ? "Hunter" : "hunter");
			return true;
		}
		case L4DInfected_Witch:
		{
			strcopy(name, size, capitalize ? "Witch" : "witch");
			return true;
		}
		case L4DInfected_Tank:
		{
			strcopy(name, size, capitalize ? "Tank" : "tank");
			return true;
		}
	}
	
	return false;
}

/**
 * Retrieves the name of any of the L4D2 infected.
 *
 * @param id		ID of the infected.
 * @return			True if found and buffer filled, false otherwise.
 */
stock bool L4D2_GetInfectedName(L4D2Infected id, char[] name, int size, bool capitalize = false)
{
	switch (id)
	{
		case L4D2Infected_None:
			return false;
		case L4D2Infected_Smoker:
		{
			strcopy(name, size, capitalize ? "Smoker" : "smoker");
			return true;
		}
		case L4D2Infected_Boomer:
		{
			strcopy(name, size, capitalize ? "Boomer" : "boomer");
			return true;
		}
		case L4D2Infected_Hunter:
		{
			strcopy(name, size, capitalize ? "Hunter" : "hunter");
			return true;
		}
		case L4D2Infected_Spitter:
		{
			strcopy(name, size, capitalize ? "Spitter" : "spitter");
			return true;
		}
		case L4D2Infected_Jockey:
		{
			strcopy(name, size, capitalize ? "Jockey" : "jockey");
			return true;
		}
		case L4D2Infected_Charger:
		{
			strcopy(name, size, capitalize ? "Charger" : "charger");
			return true;
		}
		case L4D2Infected_Witch:
		{
			strcopy(name, size, capitalize ? "Witch" : "witch");
			return true;
		}
		case L4D2Infected_Tank:
		{
			strcopy(name, size, capitalize ? "Tank" : "tank");
			return true;
		}
	}
	
	return false;
}