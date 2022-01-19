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
};

GlobalForward g_PlayerMarkedForward;
Handle g_hWitchAttack;
Handle hThrowTimer;

ConVar hVictimsList;
ConVar hThrowItemInterval;
ConVar hAutoPunish;
ConVar hMagnetChance;
ConVar hShoveFailChance;
ConVar hAutoPunishExpire;
ConVar hMagnetTargetMode;
ConVar hBadThrowHitSelf;
ConVar hBotReverseFFDefend;
ConVar hSbFriendlyFire;


bool g_bPendingItemGive[MAXPLAYERS+1];

int g_iAmmoTable; //Loads the ammo table to get max ammo for weapons
int autoPunished = -1;
int autoPunishMode; 
int lastButtonUser;
int lastCrescendoUser;
int g_iAttackerTarget[MAXPLAYERS+1];
int g_PendingBanTroll[MAXPLAYERS+1];

int gInstaSpecialType = -1;
int gInstaSpecialTarget;
float gInstaSpecialSpawnPos[3];
float gInstaSpecialSpawnAng[3];
bool gInstaSpecialInstaKill;
int gInstaSpecialMagnet[MAXPLAYERS+1];

char steamids[MAXPLAYERS+1][64];

int shootAtTarget[MAXPLAYERS+1];
int shootAtTargetLoops[MAXPLAYERS+1];
int shootAtTargetHP[MAXPLAYERS+1];

#include <feedthetrolls/base>
#include <feedthetrolls/trolls>
#include <feedthetrolls/combos>
#include <feedthetrolls/specials>
#include <feedthetrolls/misc>
#include <feedthetrolls/commands>
#include <feedthetrolls/events>
#include <feedthetrolls/timers>
#include <feedthetrolls/menus>

