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
GlobalForward g_TrollAppliedForward;
Handle g_hWitchAttack;
int g_iWitchAttackVictim;
Handle hThrowTimer;

ConVar hThrowItemInterval;
ConVar hAutoPunish;
ConVar hMagnetChance;
ConVar hShoveFailChance;
ConVar hAutoPunishExpire;
ConVar hMagnetTargetMode;
ConVar hBadThrowHitSelf;
ConVar hBotReverseFFDefend;
ConVar hSbFriendlyFire;
ConVar hBotDefendChance;

ConVar hSbFixEnabled;
bool wasSbFixEnabled;

int wasAbmAutoHard;
ConVar hAbmAutoHard;

enum playerDataFlags {
	Flag_PendingItemGive = 1,
	Flag_HasSpitTimer = 2,
	Flag_IsTargettingHealer = 4
}

enum struct PlayerData {
	int flags;

	int attackerTargetUid;
	int specialAttackFlags;
	int pendingTrollBan; // Includes ent index of activator

	float lastInSpitTime;

	int shootAtTarget;
	int shootAtLoops;
	int shootAtTargetHealth;

	int smartChargeAttempts;
	int smartChargeMaxAttempts;
	int smartChargeActivator;

	char steamid[32];

	void Reset() {
		this.flags = 0;
		this.attackerTargetUid = 0;
		this.specialAttackFlags = 0;
		this.pendingTrollBan = 0;
		this.lastInSpitTime = 0.0;
		this.shootAtTarget = 0;
		this.shootAtLoops = 0;
		this.smartChargeAttempts = 0;
		this.steamid[0] = '\0';
	}
}

PlayerData pdata[MAXPLAYERS+1];

int lastButtonUser;
int lastCrescendoUser;

bool spIsActive;
enum SpecialSpawnFlags {
	Special_Anywhere = 0,
	Special_OnTarget = 1,
	Special_SpawnDirectOnFailure = 2
}

enum SpecialInternalFlags {
	SPI_KillOnSpawn = 1,
	SPI_AlwaysTarget = 2,
}

int healTargetPlayer;
float healTargetPos[3];
Handle stopHealingTimer;

float entLastHeight[2048];

float fLastAntiRushEvent[MAXPLAYERS+1];
float fAntiRushFrequencyCounter[MAXPLAYERS+1];


#define MODEL_CAR "models/props_vehicles/cara_95sedan.mdl"


#include <feedthetrolls/base>
#include <feedthetrolls/trolls>
#include <feedthetrolls/combos>
#include <feedthetrolls/specials>
#include <feedthetrolls/misc>
#include <feedthetrolls/commands>
#include <feedthetrolls/events>
#include <feedthetrolls/timers>
#include <feedthetrolls/menus>

