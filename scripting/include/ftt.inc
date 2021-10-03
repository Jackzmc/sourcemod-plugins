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
int  g_iAttackerTarget[MAXPLAYERS+1];
int autoPunished = -1, autoPunishMode, lastButtonUser, lastCrescendoUser;
bool g_bPendingItemGive[MAXPLAYERS+1], g_PendingBanTroll[MAXPLAYERS+1];
GlobalForward g_PlayerMarkedForward;
char steamids[MAXPLAYERS+1][64];
Handle g_hWitchAttack;

//HANDLES
Handle hThrowTimer;
//CONVARS
ConVar hVictimsList, hThrowItemInterval, hAutoPunish, hMagnetChance, hShoveFailChance, hAutoPunishExpire, hMagnetTargetMode, hWitchTargetIncapp;
ConVar hBadThrowHitSelf;
//BOOLS
bool lateLoaded; //Is plugin late loaded
bool bChooseVictimAvailable = false; //For charge player feature, is it available?
//INTEGERS
int g_iAmmoTable; //Loads the ammo table to get ammo amounts
int gChargerVictim = -1; //For charge player feature

#include <feedthetrolls/base>
#include <feedthetrolls/trolls>
#include <feedthetrolls/specials>
#include <feedthetrolls/misc>
#include <feedthetrolls/commands>
#include <feedthetrolls/events>
#include <feedthetrolls/timers>
#include <feedthetrolls/menus>
