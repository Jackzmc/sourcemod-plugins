#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

public Plugin myinfo =
{
	name = "L4D2 Survivor Bot Fix",
	author = "DingbatFlat",
	description = "Survivor Bot Fix. Improve Survivor Bot",
	version = "1.00",
	url = ""
}

/*
// ====================================================================================================

About:

- Main items that can be improve bots by introducing this plugin.

Help a pinning Survivor.
Attack a Common Infected.
Attack a Special Infected.
Attack a Tank.
Bash a flying Hunter and Jockey.
Shoot a tank rock.
Shoot a Witch (Contronls the attack timing when have a shotgun).
Restrict switching to the sub weapon.

And the action during incapacitated.


- Sourcemod ver 1.10 is required.



// ====================================================================================================

How to use:

Make sure "sb_fix_enabled" in the CVars is 1.


- Select the improved bot with the following CVar.

If "sb_fix_select_type" is 0, It is always enabled.

If "sb_fix_select_type" is 1, the number of people set in "sb_fix_select_number" will be randomly select.

If "sb_fix_select_type" is 2, Select the bot of the character entered in "sb_fix_select_character_name".


- For 1 and 2, bots that improve after left the safe room are selected.



// ====================================================================================================

Change Log:

1.00 (09-September-2021)
    - Initial release.



// ====================================================================================================


// It is difficult to improve the movement operation.
// This is the limit of my power and I can't add any further improvement points maybe... so arrange as you like.
*/

#define SOUND_SELECT "level/gnomeftw.wav"
#define SOUND_SWING	"ui/pickup_guitarriff10.wav"

#define BUFSIZE			(1 << 12)	// 4k

#define ZC_SMOKER       1
#define ZC_BOOMER       2
#define ZC_HUNTER       3
#define ZC_SPITTER      4
#define ZC_JOCKEY       5
#define ZC_CHARGER      6
#define ZC_TANK         8

#define MAXPLAYERS1     (MAXPLAYERS+1)
#define MAXENTITIES 2048

#define WITCH_INCAPACITATED 1
#define WITCH_KILLED 2

/****************************************************************************************************/

// ====================================================================================================
// Handle
// ====================================================================================================
Handle sb_fix_enabled				= INVALID_HANDLE;
Handle sb_fix_select_type			= INVALID_HANDLE;
Handle sb_fix_select_number		= INVALID_HANDLE;
Handle sb_fix_select_character_name	= INVALID_HANDLE;

Handle sb_fix_dont_switch_secondary	= INVALID_HANDLE;

Handle sb_fix_help_enabled			= INVALID_HANDLE;
Handle sb_fix_help_range			= INVALID_HANDLE;
Handle sb_fix_help_shove_type		= INVALID_HANDLE;
Handle sb_fix_help_shove_reloading	= INVALID_HANDLE;

Handle sb_fix_ci_enabled			= INVALID_HANDLE;
Handle sb_fix_ci_range				= INVALID_HANDLE;
Handle sb_fix_ci_melee_allow		= INVALID_HANDLE;
Handle sb_fix_ci_melee_range		= INVALID_HANDLE;

Handle sb_fix_si_enabled			= INVALID_HANDLE;
Handle sb_fix_si_range				= INVALID_HANDLE;
Handle sb_fix_si_ignore_boomer		= INVALID_HANDLE;
Handle sb_fix_si_ignore_boomer_range	= INVALID_HANDLE;

Handle sb_fix_tank_enabled			= INVALID_HANDLE;
Handle sb_fix_tank_range			= INVALID_HANDLE;

Handle sb_fix_si_tank_priority_type	= INVALID_HANDLE;

Handle sb_fix_bash_enabled			= INVALID_HANDLE;
Handle sb_fix_bash_hunter_chance	= INVALID_HANDLE;
Handle sb_fix_bash_hunter_range	= INVALID_HANDLE;
Handle sb_fix_bash_jockey_chance	= INVALID_HANDLE;
Handle sb_fix_bash_jockey_range		= INVALID_HANDLE;

Handle sb_fix_rock_enabled			= INVALID_HANDLE;
Handle sb_fix_rock_range			= INVALID_HANDLE;

Handle sb_fix_witch_enabled		= INVALID_HANDLE;
Handle sb_fix_witch_range			= INVALID_HANDLE;
Handle sb_fix_witch_range_incapacitated	= INVALID_HANDLE;
Handle sb_fix_witch_range_killed		= INVALID_HANDLE;
Handle sb_fix_witch_shotgun_control	= INVALID_HANDLE;
Handle sb_fix_witch_shotgun_range_max	= INVALID_HANDLE;
Handle sb_fix_witch_shotgun_range_min	= INVALID_HANDLE;

Handle sb_fix_prioritize_ownersmoker	= INVALID_HANDLE;

Handle sb_fix_incapacitated_enabled	= INVALID_HANDLE;

Handle sb_fix_debug				= INVALID_HANDLE;

// ====================================================================================================
// SendProp
// ====================================================================================================
int g_Velo = -1;
int g_ActiveWeapon = -1;
int g_iAmmoOffset = -1;

// ====================================================================================================
// Variables
// ====================================================================================================
bool g_hEnabled;
int c_iSelectType;
int c_iSelectNumber;

bool c_bDontSwitchSecondary;

bool c_bHelp_Enabled;
float c_fHelp_Range;
int c_iHelp_ShoveType;
bool c_bHelp_ShoveOnlyReloading;

bool c_bCI_Enabled;
float c_fCI_Range;
bool c_bCI_MeleeEnabled;
float c_fCI_MeleeRange;

bool c_bSI_Enabled;
float c_fSI_Range;
bool c_bSI_IgnoreBoomer;
float c_fSI_IgnoreBoomerRange;

bool c_bTank_Enabled;
float c_fTank_Range;

int c_iSITank_PriorityType;

bool c_bBash_Enabled;
int c_iBash_HunterChance;
float c_fBash_HunterRange;
int c_iBash_JockeyChance;
float c_fBash_JockeyRange;

bool c_bRock_Enabled;
float c_fRock_Range;

bool c_bWitch_Enabled;
float c_fWitch_Range;
float c_fWitch_Range_Incapacitated;
float c_fWitch_Range_Killed;
bool c_bWitch_Shotgun_Control;
float c_fWitch_Shotgun_Range_Max;
float c_fWitch_Shotgun_Range_Min;

bool c_bPrioritize_OwnerSmoker;

bool c_bIncapacitated_Enabled;

bool c_bDebug_Enabled;

// ====================================================================================================
// Int Array
// ====================================================================================================
int  g_iWitch_Process[MAXENTITIES];

int  g_Stock_NextThinkTick[MAXPLAYERS1];

// ====================================================================================================
// Bool Array
// ====================================================================================================
bool g_bFixTarget[MAXPLAYERS1];

bool g_bDanger[MAXPLAYERS1];

bool g_bWitchActive = false;

bool g_bCommonWithinMelee[MAXPLAYERS1];
bool g_bShove[MAXPLAYERS1][MAXPLAYERS1];

// ====================================================================================================
// Round
// ====================================================================================================
bool LeftSafeRoom = false;
bool TimerAlreadyWorking = false;

/****************************************************************************************************/

bool bLateLoad = false;

public APLRes AskPluginLoad2(Handle plugin, bool late, char[] error, int errMax)
{
	bLateLoad = late;
	return APLRes_Success;
}

public void OnPluginStart()
{
	// Notes:
	// If "~_enabled" of the group is not set to 1, other Cvars in that group will not work.
	// If the plugin is too heavy, Try disable searching for "Entities" other than Client. (CI, Witch and tank rock)
	
	// ---------------------------------
	sb_fix_enabled				= CreateConVar("sb_fix_enabled", "1", "Enable the plugin. <0: Disable, 1: Enable>", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	// ---------------------------------
	sb_fix_select_type				= CreateConVar("sb_fix_select_type", "0", "Which survivor bots to improved. <0: All, 1: Randomly select X people when left the safe area, 2: Enter the character name of the survivor bot to improve in \"sb_fix_select_character_name\">", FCVAR_NOTIFY, true, 0.0, true, 2.0);
	sb_fix_select_number			= CreateConVar("sb_fix_select_number", "1", "If \"sb_fix_select_type\" is 1, Enter the number of survivor bots. <0 ~ 4>", FCVAR_NOTIFY, true, 0.0);
	sb_fix_select_character_name	= CreateConVar("sb_fix_select_character_name", "", "If \"sb_fix_select_type\" is 4, Enter the character name to improved. Separate with spaces. Example: \"nick francis bill\"", FCVAR_NOTIFY); // "coach ellis rochelle nick louis francis zoey bill"
	// ---------------------------------
	sb_fix_dont_switch_secondary	= CreateConVar("sb_fix_dont_switch_secondary", "1", "Disallow switching to the secondary weapon until the primary weapon is out of ammo. <0:No, 1:Yes | def: 1>", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	// ---------------------------------
	sb_fix_help_enabled			= CreateConVar("sb_fix_help_enabled", "1", "Help a pinning survivor. <0: Disable, 1: Enable | def: 1>", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	sb_fix_help_range				= CreateConVar("sb_fix_help_range", "1200", "Range to shoot/search a pinning survivor. <1 ~ 3000 | def: 1200>", FCVAR_NOTIFY, true, 1.0, true, 3000.0);
	sb_fix_help_shove_type			= CreateConVar("sb_fix_help_shove_type", "2", "Whether to help by shove. <0: Not help by shove, 1: Smoker only, 2: Smoker and Jockey, 3: Smoker, Jockey and Hunter | def: 2>", FCVAR_NOTIFY, true, 0.0, true, 3.0);
	sb_fix_help_shove_reloading		= CreateConVar("sb_fix_help_shove_reloading", "0", "If \"sb_fix_help_shove_type\" is 2 or more, it is shove only while reloading. <0: No, 1: Yes | def: 0>", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	// ---------------------------------
	sb_fix_ci_enabled				= CreateConVar("sb_fix_ci_enabled", "1", "Deal with Common Infecteds. <0: Disable, 1: Enable | def: 1>", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	sb_fix_ci_range				= CreateConVar("sb_fix_ci_range", "500", "Range to shoot/search a Common Infected. <1 ~ 2000 | def: 500>", FCVAR_NOTIFY, true, 1.0, true, 2000.0);
	sb_fix_ci_melee_allow			= CreateConVar("sb_fix_ci_melee_allow", "1", "Allow to deal with the melee weapon. <0: Disable 1: Enable | def: 1>", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	sb_fix_ci_melee_range			= CreateConVar("sb_fix_ci_melee_range", "160", "If \"sb_fix_ci_melee_allow\" is enabled, range to deal with the melee weapon. <1 ~ 500 | def: 160>", FCVAR_NOTIFY, true, 1.0, true, 500.0);
	// ---------------------------------
	sb_fix_si_enabled				= CreateConVar("sb_fix_si_enabled", "1", "Deal with Special Infecteds. <0: Disable, 1: Enable | def: 1>", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	sb_fix_si_range				= CreateConVar("sb_fix_si_range", "500", "Range to shoot/search a Special Infected. <1 ~ 3000 | def: 500>", FCVAR_NOTIFY, true, 1.0, true, 3000.0);
	sb_fix_si_ignore_boomer		= CreateConVar("sb_fix_si_ignore_boomer", "1", "Ignore a Boomer near Survivors (and shove a Boomer). <0: No, 1: Yes | def: 1>", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	sb_fix_si_ignore_boomer_range	= CreateConVar("sb_fix_si_ignore_boomer_range", "200", "Range to ignore a Boomer. <1 ~ 900 | def: 200>", FCVAR_NOTIFY, true, 1.0, true, 500.0);
	// ---------------------------------
	sb_fix_tank_enabled			= CreateConVar("sb_fix_tank_enabled", "1", "Deal with Tanks. <0: Disable, 1: Enable | def: 1>", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	sb_fix_tank_range				= CreateConVar("sb_fix_tank_range", "1200", "Range to shoot/search a Tank. <1 ~ 3000 | def: 1200>", FCVAR_NOTIFY, true, 1.0, true, 3000.0);
	// ---------------------------------
	sb_fix_si_tank_priority_type		= CreateConVar("sb_fix_si_tank_priority_type", "0", "When a Special Infected and a Tank is together within the specified range, which to prioritize. <0: Nearest, 1: Special Infected, 2: Tank | def: 0>", FCVAR_NOTIFY, true, 0.0, true, 2.0);
	// ---------------------------------
	sb_fix_bash_enabled			= CreateConVar("sb_fix_bash_enabled", "1", "Bash a flying Hunter or Jockey. <0: Disable, 1: Enable | def: 1>", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	sb_fix_bash_hunter_chance		= CreateConVar("sb_fix_bash_hunter_chance", "100", "Chance of bash a flying Hunter. (Even 100 doesn't can perfectly shove). <1 ~ 100 | def: 100>", FCVAR_NOTIFY, true, 0.0, true, 100.0);
	sb_fix_bash_hunter_range		= CreateConVar("sb_fix_bash_hunter_range", "145", "Range to bash/search a flying Hunter. <1 ~ 500 | def: 145>", FCVAR_NOTIFY, true, 1.0, true, 500.0);
	sb_fix_bash_jockey_chance		= CreateConVar("sb_fix_bash_jockey_chance", "100", "Chance of bash a flying Jockey. (Even 100 doesn't can perfectly shove). <1 ~ 100 | def: 100>", FCVAR_NOTIFY, true, 0.0, true, 100.0);
	sb_fix_bash_jockey_range		= CreateConVar("sb_fix_bash_jockey_range", "125", "Range to bash/search a flying Jockey. <1 ~ 500 | def: 125>", FCVAR_NOTIFY, true, 1.0, true, 500.0);
	// ---------------------------------
	sb_fix_rock_enabled			= CreateConVar("sb_fix_rock_enabled", "1", "Shoot a tank rock. <0: Disable, 1: Enable | def: 1>", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	sb_fix_rock_range				= CreateConVar("sb_fix_rock_range", "700", "Range to shoot/search a tank rock. <1 ~ 2000 | def: 700>", FCVAR_NOTIFY, true, 1.0, true, 2000.0);
	// ---------------------------------
	sb_fix_witch_enabled			= CreateConVar("sb_fix_witch_enabled", "1", "Shoot a rage Witch. <0: Disable, 1: Enable | def: 1>", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	sb_fix_witch_range				= CreateConVar("sb_fix_witch_range", "1500", "Range to shoot/search a rage Witch. <1 ~ 2000 | def: 1500>", FCVAR_NOTIFY, true, 1.0, true, 2000.0);
	sb_fix_witch_range_incapacitated	= CreateConVar("sb_fix_witch_range_incapacitated", "1000", "Range to shoot/search a Witch that incapacitated a survivor. <0 ~ 2000 | def: 1000>", FCVAR_NOTIFY, true, 0.0, true, 2000.0);
	sb_fix_witch_range_killed		= CreateConVar("sb_fix_witch_range_killed", "0", "Range to shoot/search a Witch that killed a survivor. <0 ~ 2000 | def: 0>", FCVAR_NOTIFY, true, 0.0, true, 2000.0);
	sb_fix_witch_shotgun_control	= CreateConVar("sb_fix_witch_shotgun_control", "1", "[Witch] If have the shotgun, controls the attack timing. <0: Disable, 1: Enable | def: 1>", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	sb_fix_witch_shotgun_range_max	= CreateConVar("sb_fix_witch_shotgun_range_max", "300", "If a Witch is within distance of the values, stop the attack. <1 ~ 1000 | def: 300>", FCVAR_NOTIFY, true, 1.0, true, 1000.0);
	sb_fix_witch_shotgun_range_min	= CreateConVar("sb_fix_witch_shotgun_range_min", "70", "If a Witch is at distance of the values or more, stop the attack. <1 ~ 500 | def: 70>", FCVAR_NOTIFY, true, 1.0, true, 500.0);
	// ---------------------------------
	sb_fix_prioritize_ownersmoker	= CreateConVar("sb_fix_prioritize_ownersmoker", "1", "Priority given to dealt a Smoker that is try to pinning self. <0: No, 1: Yes | def: 1>", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	// ---------------------------------
	sb_fix_incapacitated_enabled		= CreateConVar("sb_fix_incapacitated_enabled", "1", "Enable Incapacitated Cmd. <0: Disable, 1: Enable | def: 1>", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	// ---------------------------------
	sb_fix_debug					= CreateConVar("sb_fix_debug", "0", "[For debug] Print the action status. <0:Disable, 1:Enable>", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	
	
	HookConVarChange(sb_fix_help_enabled, SBHelp_ChangeConvar);
	HookConVarChange(sb_fix_help_range, SBHelp_ChangeConvar);
	HookConVarChange(sb_fix_help_shove_type, SBHelp_ChangeConvar);
	HookConVarChange(sb_fix_help_shove_reloading, SBHelp_ChangeConvar);
	// ---------------------------------
	HookConVarChange(sb_fix_ci_enabled, SBCI_ChangeConvar);
	HookConVarChange(sb_fix_ci_range, SBCI_ChangeConvar);
	HookConVarChange(sb_fix_ci_melee_allow, SBCI_ChangeConvar);
	HookConVarChange(sb_fix_ci_melee_range, SBCI_ChangeConvar);
	// ---------------------------------
	HookConVarChange(sb_fix_si_enabled, SBSI_ChangeConvar);
	HookConVarChange(sb_fix_si_range, SBSI_ChangeConvar);
	HookConVarChange(sb_fix_si_ignore_boomer, SBSI_ChangeConvar);
	HookConVarChange(sb_fix_si_ignore_boomer_range, SBSI_ChangeConvar)
	// ---------------------------------
	HookConVarChange(sb_fix_tank_enabled, SBTank_ChangeConvar);
	HookConVarChange(sb_fix_tank_range, SBTank_ChangeConvar);
	// ---------------------------------
	HookConVarChange(sb_fix_si_tank_priority_type, SBTank_ChangeConvar);
	// ---------------------------------
	HookConVarChange(sb_fix_bash_enabled, SBBash_ChangeConvar);
	HookConVarChange(sb_fix_bash_hunter_chance, SBBash_ChangeConvar);
	HookConVarChange(sb_fix_bash_hunter_range, SBBash_ChangeConvar);
	HookConVarChange(sb_fix_bash_jockey_chance, SBBash_ChangeConvar);
	HookConVarChange(sb_fix_bash_jockey_range, SBBash_ChangeConvar);
	// ---------------------------------
	HookConVarChange(sb_fix_rock_enabled, SBEnt_ChangeConvar);
	HookConVarChange(sb_fix_rock_range, SBEnt_ChangeConvar);
	HookConVarChange(sb_fix_witch_enabled, SBEnt_ChangeConvar);
	HookConVarChange(sb_fix_witch_range, SBEnt_ChangeConvar);
	HookConVarChange(sb_fix_witch_range_incapacitated, SBEnt_ChangeConvar);
	HookConVarChange(sb_fix_witch_range_killed, SBEnt_ChangeConvar);
	HookConVarChange(sb_fix_witch_shotgun_control, SBEnt_ChangeConvar);
	HookConVarChange(sb_fix_witch_shotgun_range_max, SBEnt_ChangeConvar);
	HookConVarChange(sb_fix_witch_shotgun_range_min, SBEnt_ChangeConvar);
	// ---------------------------------
	HookConVarChange(sb_fix_enabled, SBConfigChangeConvar);
	HookConVarChange(sb_fix_select_type, SBConfigChangeConvar);
	HookConVarChange(sb_fix_select_number, SBConfigChangeConvar);
	HookConVarChange(sb_fix_dont_switch_secondary, SBConfigChangeConvar);
	HookConVarChange(sb_fix_prioritize_ownersmoker, SBConfigChangeConvar);
	HookConVarChange(sb_fix_incapacitated_enabled, SBConfigChangeConvar);
	HookConVarChange(sb_fix_debug, SBConfigChangeConvar);
	// ---------------------------------
	HookConVarChange(sb_fix_select_type, SBSelectChangeConvar);
	HookConVarChange(sb_fix_select_number, SBSelectChangeConvar);
	HookConVarChange(sb_fix_select_character_name, SBSelectChangeConvar);
	
	if (bLateLoad) {
		for (int x = 1; x <= MaxClients; x++) {
			if (x > 0 && x <= MaxClients && IsClientInGame(x)) {
				SDKHook(x, SDKHook_WeaponSwitch, WeaponSwitch);
			}
		}
	}
	
	AutoExecConfig(false, "l4d2_sb_fix");
	
	PrecacheSound(SOUND_SWING);
	
	HookEvent("round_start", Event_RoundStart);
	HookEvent("bot_player_replace", Event_BotAndPlayerReplace, EventHookMode_Pre); // SelectImprovedTarget
	
	HookEvent("player_incapacitated", Event_PlayerIncapacitated); // Witch Event
	HookEvent("player_death", Event_PlayerDeath); // Witch Event
	
	HookEvent("witch_harasser_set", Event_WitchRage);
	
	g_Velo = FindSendPropInfo("CBasePlayer", "m_vecVelocity[0]");
	g_ActiveWeapon = FindSendPropInfo("CBasePlayer", "m_hActiveWeapon");
	g_iAmmoOffset = FindSendPropInfo("CTerrorPlayer", "m_iAmmo");
	
	CreateTimer(3.0, Timer_ShoveChance, _, TIMER_REPEAT);
	
	InitTimers(); // Safe Room Check
}

public void OnMapStart()
{
	input_Help();
	input_CI();
	input_SI();
	input_Tank();
	input_Bash();
	input_Entity();
	inputConfig();
}

public void OnAllPluginsLoaded()
{
	input_Help();
	input_CI();
	input_SI();
	input_Tank();
	input_Bash();
	input_Entity();
	inputConfig();
}

public void SBHelp_ChangeConvar(Handle convar, const char[] oldValue, const char[] intValue)	{ input_Help(); }
public void SBCI_ChangeConvar(Handle convar, const char[] oldValue, const char[] intValue)	{ input_CI(); }
public void SBSI_ChangeConvar(Handle convar, const char[] oldValue, const char[] intValue)	{ input_SI(); }
public void SBTank_ChangeConvar(Handle convar, const char[] oldValue, const char[] intValue)	{ input_Tank(); }
public void SBBash_ChangeConvar(Handle convar, const char[] oldValue, const char[] intValue)	{ input_Bash(); }
public void SBEnt_ChangeConvar(Handle convar, const char[] oldValue, const char[] intValue)	{ input_Entity(); }

public void SBConfigChangeConvar(Handle convar, const char[] oldValue, const char[] intValue) { inputConfig(); }

public void SBSelectChangeConvar(Handle convar, const char[] oldValue, const char[] intValue) { SelectImprovedTarget(); }

void input_Help()
{
	c_bHelp_Enabled = GetConVarBool(sb_fix_help_enabled);
	c_fHelp_Range = GetConVarInt(sb_fix_help_range) * 1.0;
	c_iHelp_ShoveType = GetConVarInt(sb_fix_help_shove_type);
	c_bHelp_ShoveOnlyReloading = GetConVarBool(sb_fix_help_shove_reloading);
}
void input_CI()
{
	c_bCI_Enabled = GetConVarBool(sb_fix_ci_enabled);
	c_fCI_Range = GetConVarInt(sb_fix_ci_range) * 1.0;
	c_bCI_MeleeEnabled = GetConVarBool(sb_fix_ci_melee_allow);
	c_fCI_MeleeRange = GetConVarInt(sb_fix_ci_melee_range) * 1.0;
}
void input_SI()
{
	c_bSI_Enabled = GetConVarBool(sb_fix_si_enabled);
	c_fSI_Range = GetConVarInt(sb_fix_si_range) * 1.0;
	c_bSI_IgnoreBoomer = GetConVarBool(sb_fix_si_ignore_boomer);
	c_fSI_IgnoreBoomerRange = GetConVarInt(sb_fix_si_ignore_boomer_range) * 1.0;
}
void input_Tank()
{
	c_bTank_Enabled = GetConVarBool(sb_fix_tank_enabled);
	c_fTank_Range = GetConVarInt(sb_fix_tank_range) * 1.0;
	
	c_iSITank_PriorityType = GetConVarInt(sb_fix_si_tank_priority_type);
}
void input_Bash()
{
	c_bBash_Enabled = GetConVarBool(sb_fix_bash_enabled);
	c_iBash_HunterChance = GetConVarInt(sb_fix_bash_hunter_chance);
	c_fBash_HunterRange = GetConVarInt(sb_fix_bash_hunter_range) * 1.0;
	c_iBash_JockeyChance = GetConVarInt(sb_fix_bash_jockey_chance);
	c_fBash_JockeyRange = GetConVarInt(sb_fix_bash_jockey_range) * 1.0;
}
void input_Entity()
{
	c_bRock_Enabled = GetConVarBool(sb_fix_rock_enabled);
	c_fRock_Range = GetConVarInt(sb_fix_rock_range) * 1.0;
	
	c_bWitch_Enabled = GetConVarBool(sb_fix_witch_enabled);
	c_fWitch_Range = GetConVarInt(sb_fix_witch_range) * 1.0;
	c_fWitch_Range_Incapacitated = GetConVarInt(sb_fix_witch_range_incapacitated) * 1.0;
	c_fWitch_Range_Killed = GetConVarInt(sb_fix_witch_range_killed) * 1.0;
	c_bWitch_Shotgun_Control = GetConVarBool(sb_fix_witch_shotgun_control);
	c_fWitch_Shotgun_Range_Max = GetConVarInt(sb_fix_witch_shotgun_range_max) * 1.0;
	c_fWitch_Shotgun_Range_Min = GetConVarInt(sb_fix_witch_shotgun_range_min) * 1.0;
}

void inputConfig()
{
	g_hEnabled = GetConVarBool(sb_fix_enabled);
	c_iSelectType = GetConVarInt(sb_fix_select_type);
	c_iSelectNumber = GetConVarInt(sb_fix_select_number);
	
	c_bDontSwitchSecondary = GetConVarBool(sb_fix_dont_switch_secondary);
	
	c_bPrioritize_OwnerSmoker = GetConVarBool(sb_fix_prioritize_ownersmoker);
	
	c_bIncapacitated_Enabled = GetConVarBool(sb_fix_incapacitated_enabled);
	
	c_bDebug_Enabled = GetConVarBool(sb_fix_debug);
}


/****************************************************************************************************/


/* ================================================================================================
*=
*=		Round / Start Ready / Select Improved Targets
*=
================================================================================================ */
public Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	for (int x = 1; x <= MAXPLAYERS; x++) g_bFixTarget[x] = false; // RESET
	
	LeftSafeRoom = false;
	
	
	if (!TimerAlreadyWorking) {
		CreateTimer(1.0, Timer_PlayerLeftCheck);
		TimerAlreadyWorking = true;
	}
	
	InitTimers();
}

public Action Event_BotAndPlayerReplace(Handle event, const char[] name, bool dontBroadcast)
{
	if (!LeftSafeRoom) return;
	
	int bot = GetClientOfUserId(GetEventInt(event, "bot"));
	if (g_bFixTarget[bot]) {
		SelectImprovedTarget();
	}
}

void InitTimers()
{
	if (LeftSafeRoom)
		SelectImprovedTarget();
	else if (!TimerAlreadyWorking)
	{
		TimerAlreadyWorking = true;
		CreateTimer(1.0, Timer_PlayerLeftCheck);
	}
}

public Action Timer_PlayerLeftCheck(Handle Timer)
{
	if (LeftStartArea())
	{
		if (!LeftSafeRoom) {
			LeftSafeRoom = true;
			SelectImprovedTarget();
			// PrintToChatAll("[sb_fix] Survivors left the safe area.");
		}
		
		TimerAlreadyWorking = false;
	}
	else
	{
		CreateTimer(1.0, Timer_PlayerLeftCheck);
	}
	return Plugin_Continue; 
}

bool LeftStartArea()
{
	int ent = -1, maxents = GetMaxEntities();
	for (int i = MaxClients+1; i <= maxents; i++)
	{
		if (IsValidEntity(i))
		{
			static char netclass[32];
			GetEntityNetClass(i, netclass, sizeof(netclass));
			
			if (StrEqual(netclass, "CTerrorPlayerResource"))
			{
				ent = i;
				break;
			}
		}
	}
	
	if (ent > -1)
	{
		int offset = FindSendPropInfo("CTerrorPlayerResource", "m_hasAnySurvivorLeftSafeArea");
		if (offset > 0)
		{
			if (GetEntData(ent, offset))
			{
				if (GetEntData(ent, offset) == 1) return true;
			}
		}
	}
	return false;
}

void SelectImprovedTarget()
{
	if (!g_hEnabled || !LeftSafeRoom) return; // Select targets when left the safe area.
	else if (c_iSelectType == 1) {
		int count;
		for (int x = 1; x <= MaxClients; x++) {
			if (isSurvivorBot(x)) {
				g_bFixTarget[x] = true;
				count++
			}
			
			if (count >= c_iSelectNumber) { break; }
		}
	}
	else if (c_iSelectType == 2)
	{
		static char sSelectName[256];
		GetConVarString(sb_fix_select_character_name, sSelectName, sizeof(sSelectName));
		
		int count;
		for (int x = 1; x <= MaxClients; x++) {
			if (isSurvivorBot(x)) {
				static char sName[128];
				GetClientName(x, sName, sizeof(sName));
				
				if (StrContains(sSelectName, sName, false) != -1) {
					g_bFixTarget[x] = true;
					count++;
					//PrintToChatAll("\x04%d\x05. %N", count, x);
				} else {
					g_bFixTarget[x] = false;
				}
			}
			
		}
	}
}

public Action Timer_ShoveChance(Handle Timer)
{
	// ----------------------- Bash Chance -----------------------
	if (c_iBash_HunterChance < 100 || c_iBash_JockeyChance < 100) {
		for (int sb = 1; sb <= MaxClients; sb++) {
			if (isSurvivorBot(sb) && IsPlayerAlive(sb)) {
				for (int x = 1; x <= MaxClients; x++) {
					if (isInfected(x) && IsPlayerAlive(x)) {
						int zombieClass = getZombieClass(x);
						if (zombieClass == ZC_HUNTER) {
							if (GetRandomInt(0, 100) <= c_iBash_HunterChance) g_bShove[sb][x] = true;
							else g_bShove[sb][x] = false;
							
							// PrintToChatAll("%N's Shove to %N: %b", sb, x, g_bShove[sb][x]);
						}
						else if (zombieClass == ZC_JOCKEY) {
							if (GetRandomInt(0, 100) <= c_iBash_JockeyChance) g_bShove[sb][x] = true;
							else g_bShove[sb][x] = false;
							
							// PrintToChatAll("%N's Shove to %N: %b", sb, x, g_bShove[sb][x]);
						}
					}
				}
			}
		}
	}
}


/****************************************************************************************************/


/* Client key input processing
 *
 * buttons: Entered keys (enum��include/entity_prop_stock.inc�Q��)

 * angles:
 *      [0]: pitch(UP-DOWN) -89~+89
 *      [1]: yaw(360) -180~+180
 */
 
 /*
 *		OnPlayerRunCmd is Runs 30 times per second. (every 0.03333... seconds)
 */
public Action OnPlayerRunCmd(int client, int &buttons, int &impulse,
	float vel[3], float angles[3], int &weapon)
{
	if(GetTickInterval() < 0.03333) return Plugin_Continue; //Stop running on lag
	if (g_hEnabled) {
		if (isSurvivorBot(client) && IsPlayerAlive(client)) {
			if ((c_iSelectType == 0) || (c_iSelectType >= 1 && g_bFixTarget[client])) {
				Action ret = Plugin_Continue;
				ret = onSBRunCmd(client, buttons, vel, angles);
				if (c_bIncapacitated_Enabled) ret = onSBRunCmd_Incapacitated(client, buttons, vel, angles);
				ret = onSBSlotActionCmd(client, buttons, vel, angles);
				
				return ret;
			}
		}
	}
	return Plugin_Continue;
}


/****************************************************************************************************/


/* ================================================================================================
*=
*=		Weapon Switch
*=
================================================================================================ */
public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_WeaponSwitch, WeaponSwitch);
}
public void OnClientDisconnect(int client)
{
	SDKUnhook(client, SDKHook_WeaponSwitch, WeaponSwitch);
}
public Action WeaponSwitch(int client, int weapon)
{
	if (!g_hEnabled) return Plugin_Continue;
	if (!isSurvivor(client) || !IsFakeClient(client) || !IsValidEntity(weapon)) return Plugin_Continue;
	if (isIncapacitated(client) || GetPlayerWeaponSlot(client, 0) == -1) return Plugin_Continue;
	
	static char classname[128];
	GetEntityClassname(weapon, classname, sizeof(classname));
	
	if (isHaveItem(classname, "weapon_melee")
		|| isHaveItem(classname, "weapon_pistol") // Includes Magnum ("weapon_pistol_magnum")
		|| isHaveItem(classname, "weapon_dual_pistol"))
	{
		if (c_bDontSwitchSecondary) {
			int slot0 = GetPlayerWeaponSlot(client, 0);
			int clip, extra_ammo;
			clip = GetEntProp(slot0, Prop_Send, "m_iClip1");
			extra_ammo = PrimaryExtraAmmoCheck(client, slot0); // check
			
			//PrintToChatAll("[%N's] clip: %d, extra_ammo: %d", client, clip, extra_ammo);
			
			//if (!g_bCommonWithinMelee[client] && (clip != 0 || extra_ammo != 0)) PrintToChatAll("switch Stoped");
			
			
			if (!g_bCommonWithinMelee[client] && (clip != 0 || extra_ammo != 0)) return Plugin_Handled;
		}
	}
	else if (StrContains(classname, "first_aid_kit", false) > -1
		|| StrContains(classname, "defibrillator", false) > -1)
	{
		if (g_bDanger[client]) return Plugin_Handled;
	}
	
	return Plugin_Continue;
}

stock Action onSBSlotActionCmd(int client, int &buttons, float vel[3], float angles[3])
{
	if (!isIncapacitated(client) && GetPlayerWeaponSlot(client, 0) > -1) {
		int weapon = GetEntDataEnt2(client, g_ActiveWeapon);
		
		if (weapon <= 0) return Plugin_Continue;
		
		static char classname[32];
		GetEntityClassname(weapon, classname, sizeof(classname));
		
		if (StrContains(classname, "weapon_melee", false) > -1
			|| StrContains(classname, "weapon_pistol", false) > -1
			|| StrContains(classname, "weapon_dual_pistol", false) > -1
			|| StrContains(classname, "weapon_pistol_magnum", false) > -1)
		{
			if (!g_bCommonWithinMelee[client]) {
				static char main_weapon[32];
				GetEntityClassname(GetPlayerWeaponSlot(client, 0), main_weapon, sizeof(main_weapon));
				FakeClientCommand(client, "use %s", main_weapon);
			}
		} else if (StrContains(classname, "first_aid_kit", false) > -1
			|| StrContains(classname, "defibrillator", false) > -1)
		{
			if (g_bDanger[client]) {
				static char main_weapon[32];
				GetEntityClassname(GetPlayerWeaponSlot(client, 0), main_weapon, sizeof(main_weapon));
				FakeClientCommand(client, "use %s", main_weapon);
			}
		}
	}
	return Plugin_Continue;
}


/****************************************************************************************************/


/* ================================================================================================
*=
*=		SB Run Cmd
*=
================================================================================================ */
stock Action onSBRunCmd(int client, int &buttons, float vel[3], float angles[3])
{
	if (!isIncapacitated(client)
		&& GetEntityMoveType(client) != MOVETYPE_LADDER)
	{
		// Find a nearest visible Special Infected
		int int_target = -1;
		float min_dist = 100000.0;
		float self_pos[3], target_pos[3];
		
		if ((c_bSI_Enabled || c_bTank_Enabled) && !NeedsTeammateHelp_ExceptSmoker(client)) {
			GetClientAbsOrigin(client, self_pos);
			for (int x = 1; x <= MaxClients; ++x) {
				if (isInfected(x)
					&& IsPlayerAlive(x)
					&& !isIncapacitated(x)
					&& isVisibleTo(client, x))
				{
					float dist;
					
					GetClientAbsOrigin(x, target_pos);
					dist = GetVectorDistance(self_pos, target_pos);
					
					int zombieClass = getZombieClass(x);
					if ((c_bSI_Enabled && zombieClass != ZC_TANK && dist <= c_fSI_Range)
						|| (c_bTank_Enabled && zombieClass == ZC_TANK && dist <= c_fTank_Range))
					{
						if ((c_iSITank_PriorityType == 1 && zombieClass != ZC_TANK)
							|| (c_iSITank_PriorityType == 2 && zombieClass == ZC_TANK)) {
							if (dist < min_dist) {
								min_dist = dist;
								int_target = x;
								continue;
							}
						}
						
						if (dist < min_dist) {
							min_dist = dist;
							int_target = x;
						}
					}
					
				}
			}
		}
		
		int aCap_Survivor = -1;
		float min_dist_CapSur = 100000.0;
		float target_pos_CapSur[3];
		
		int aCap_Infected = -1;
		float min_dist_CapInf = 100000.0;
		float target_pos_CapInf[3];
		
		if (c_bHelp_Enabled && !NeedsTeammateHelp_ExceptSmoker(client)) {
			// Find a Survivor who are pinned
			for (int x = 1; x <= MaxClients; ++x) {
				if (isSurvivor(x)
					&& NeedsTeammateHelp(x)
					&& (x != client)
					&& (isVisibleTo(client, x) || isVisibleTo(x, client)))
				{
					float dist;
					
					GetClientAbsOrigin(x, target_pos_CapSur);
					dist = GetVectorDistance(self_pos, target_pos_CapSur);
					if (dist < c_fHelp_Range) {
						if (dist < min_dist_CapSur) {
							min_dist_CapSur = dist;
							aCap_Survivor = x;
						}
					}
				}
			}
			
			// Find a Special Infected who are pinning
			for (int x = 1; x <= MaxClients; ++x) {
				if (isInfected(x)
					&& CappingSuvivor(x)
					&& (isVisibleTo(client, x) || isVisibleTo(x, client)))
				{
					float dist;
					
					GetClientAbsOrigin(x, target_pos_CapInf);
					dist = GetVectorDistance(self_pos, target_pos_CapInf);
					if (dist < c_fHelp_Range) {
						if (dist < min_dist_CapInf) {
							min_dist_CapInf = dist;
							aCap_Infected = x;
						}
					}
				}
			}
		}
		
		/*
		// Find aCapSmoker
		int aCapSmoker = -1;
		float min_dist_CapSmo = 100000.0;
		float target_pos_CapSmo[3];
		
		for (int x = 1; x <= MaxClients; ++x) {
			if (isSpecialInfectedBot(x)
				&& IsPlayerAlive(x)
				&& HasValidEnt(x, "m_tongueVictim")
				&& isVisibleTo(int client, x))
			{
				float dist;
				
				GetClientAbsOrigin(x, target_pos_CapSmo);
				dist = GetVectorDistance(self_pos, target_pos_CapSmo);
				if (dist < 700.0) {
					if (dist < min_dist_CapSmo) {
						min_dist_CapSmo = dist;
						aCapSmoker = x;
					}
				}
			}
		}
		*/
		
		// Find a Smoker who is tongued self
		int aCapSmoker = -1;
		
		if (c_bPrioritize_OwnerSmoker) {
			float min_dist_CapSmo = 100000.0;
			float target_pos_CapSmo[3];
			
			for (int x = 1; x <= MaxClients; ++x) {
				if (isInfected(x)
					&& IsPlayerAlive(x)
					&& HasValidEnt(x, "m_tongueVictim"))
				{
					if (GetEntPropEnt(x, Prop_Send, "m_tongueVictim") == client) {
						float dist;
						
						GetClientAbsOrigin(x, target_pos_CapSmo);
						dist = GetVectorDistance(self_pos, target_pos_CapSmo);
						if (dist < 750.0) {
							if (dist < min_dist_CapSmo) {
								min_dist_CapSmo = dist;
								aCapSmoker = x;
							}
						}
					}
				}
			}
		}
		
		// Find a flying Hunter and Jockey
		int aHunterJockey = -1;
		float hunjoc_pos[3];
		float min_dist_HunJoc = 100000.0;
		
		if (c_bBash_Enabled && !NeedsTeammateHelp_ExceptSmoker(client)) {
			for (int x = 1; x <= MaxClients; ++x) {
				if (isInfected(x)
					&& IsPlayerAlive(x)
					&& !isStagger(x)
					&& isVisibleTo(client, x))
				{
					if (getZombieClass(x) == ZC_HUNTER) {
						if (c_iBash_HunterChance == 100 || (c_iBash_HunterChance < 100 && g_bShove[client][x])) {
							float hunterVelocity[3];
							GetEntDataVector(x, g_Velo, hunterVelocity);
							if ((GetClientButtons(x) & IN_DUCK) && hunterVelocity[2] != 0.0) {
								GetClientAbsOrigin(x, hunjoc_pos);
							
								float hundist;
								hundist = GetVectorDistance(self_pos, hunjoc_pos);
								
								if (hundist < c_fBash_HunterRange) { // 145.0 best
									if (hundist < min_dist_HunJoc) {
										min_dist_HunJoc = hundist;
										aHunterJockey = x;
									}
								}
							}
						}
					}
					else if (getZombieClass(x) == ZC_JOCKEY) {
						if (c_iBash_JockeyChance == 100 || (c_iBash_JockeyChance < 100 && g_bShove[client][x])) {
							float jockeyVelocity[3];
							GetEntDataVector(x, g_Velo, jockeyVelocity);
							if (jockeyVelocity[2] != 0.0) {
								GetClientAbsOrigin(x, hunjoc_pos);
								
								float jocdist;
								jocdist = GetVectorDistance(self_pos, hunjoc_pos);
								
								if (jocdist < c_fBash_JockeyRange) { // 125.0 best
									if (jocdist < min_dist_HunJoc) {
										min_dist_HunJoc = jocdist;
										aHunterJockey = x;
									}
								}
							}
						}
					}
				}
			}
		}
		
		// Find a Common Infected
		//int iMaxEntities = GetMaxEntities();
		int aCommonInfected = -1;
		int iCI_MeleeCount = 0;
		float min_dist_CI = 100000.0;
		float ci_pos[3];
		
		if (c_bCI_Enabled && !NeedsTeammateHelp(client)) {
			for (int iEntity = MaxClients+1; iEntity <= MAXENTITIES; ++iEntity) {
				if (IsCommonInfected(iEntity)
					&& GetEntProp(iEntity, Prop_Data, "m_iHealth") > 0
					&& isVisibleToEntity(iEntity, client))
				{
					float dist;
					GetEntPropVector(iEntity, Prop_Data, "m_vecAbsOrigin", ci_pos);
					dist = GetVectorDistance(self_pos, ci_pos);
					
					if (dist < c_fCI_Range) {
						int iSeq = GetEntProp(iEntity, Prop_Send, "m_nSequence", 2);
						// Stagger			122, 123, 126, 127, 128, 133, 134
						// Down Stagger		128, 129, 130, 131
						// Object Climb (Very Low)	182, 183, 184, 185
						// Object Climb (Low)	190, 191, 192, 193, 194, 195, 196, 197, 198, 199
						// Object Climb (High)	206, 207, 208, 209, 210, 211, 218, 219, 220, 221, 222, 223
						
						if ((iSeq <= 121) || (iSeq >= 135 && iSeq <= 189) || (iSeq >= 200 && iSeq <= 205) || (iSeq >= 224)) {
							if (dist < min_dist_CI) {
								min_dist_CI = dist;
								aCommonInfected = iEntity;
							}
						}
					}
					
					if (dist <= c_fCI_MeleeRange) { // ��낯�ĂĂ� MeleeCount �ɂ͓����
						iCI_MeleeCount += 1;
					}
					
				}
			}
		}
		
		// Fina a rage Witch
		int aWitch = -1;
		float min_dist_Witch = 100000.0;
		float witch_pos[3];
		if (g_bWitchActive && c_bWitch_Enabled && !NeedsTeammateHelp(client)) {
			for (int iEntity = MaxClients+1; iEntity <= MAXENTITIES; ++iEntity)
			{
				if (IsWitch(iEntity)
					&& GetEntProp(iEntity, Prop_Data, "m_iHealth") > 0
					&& IsWitchRage(iEntity)
					&& isVisibleToEntity(iEntity, client))
				{
					float witch_dist;
					GetEntPropVector(iEntity, Prop_Data, "m_vecAbsOrigin", witch_pos);
					witch_dist = GetVectorDistance(self_pos, witch_pos);
					
					if ((g_iWitch_Process[iEntity] == 0 && witch_dist < c_fWitch_Range)
						|| (g_iWitch_Process[iEntity] == WITCH_INCAPACITATED && witch_dist < c_fWitch_Range_Incapacitated)
						|| (g_iWitch_Process[iEntity] == WITCH_KILLED && witch_dist < c_fWitch_Range_Killed)) {
						if (witch_dist < min_dist_Witch) {
							min_dist_Witch = witch_dist;
							aWitch = iEntity;
						}
					}
				}
			}
		}
		
		// Find a tank rock
		int aTankRock = -1;
		float rock_min_dist = 100000.0;
		float rock_pos[3];
		if (c_bRock_Enabled && !NeedsTeammateHelp(client)) {
			for (int iEntity = MaxClients+1; iEntity <= MAXENTITIES; ++iEntity)
			{
				if (IsTankRock(iEntity)
					&& isVisibleToEntity(iEntity, client))
				{
					float rock_dist;
					GetEntPropVector(iEntity, Prop_Data, "m_vecAbsOrigin", rock_pos);
					rock_dist = GetVectorDistance(self_pos, rock_pos);
					
					if (rock_dist < c_fRock_Range) {
						if (rock_dist < rock_min_dist) {
							rock_min_dist = rock_dist;
							aTankRock = iEntity;
						}
					}
				}
			}
		}
		
		
		
		/* -------------------------------------------------------------------------------------------------------------------------------------------------------------- 
		*****************************
		*		Get The Weapon		*
		*****************************
		--------------------------------------------------------------------------------------------------------------------------------------------------------------- */
		
		int weapon = GetEntDataEnt2(client, g_ActiveWeapon);
		
		static char AW_Classname[32];
		if (weapon > MAXPLAYERS) GetEntityClassname(weapon, AW_Classname, sizeof(AW_Classname)); // Exception reported: Entity -1 (-1) is invalid
		
		static char main_weapon[32];
		int slot0 = GetPlayerWeaponSlot(client, 0);
		if (slot0 > -1) {			
			GetEntityClassname(slot0, main_weapon, sizeof(main_weapon));
		}
		
		/* -------------------------------------------------------------------------------------------------------------------------------------------------------------- 
		**********************
		*		Action		 *
		**********************
		--------------------------------------------------------------------------------------------------------------------------------------------------------------- */
		
		/* ====================================================================================================
		*
		*  Other Adjustment
		*
		==================================================================================================== */ 
		if (g_bDanger[client]) { // If have the medkit even though it is dangerous, switch to the main weapon
			if (isHaveItem(AW_Classname, "first_aid_kit")) {
				if (main_weapon[1] != 0) {
					FakeClientCommand(client, "use %s", main_weapon);
				} else {
					static char sub_weapon[32];
					int slot1 = GetPlayerWeaponSlot(client, 1);
					if (slot1 > -1) {			
						GetEntityClassname(slot1, sub_weapon, sizeof(sub_weapon)); // SubWeapon
					}
					
					FakeClientCommand(client, "use %s", main_weapon);
				}
			}
		}
		
		if (g_bCommonWithinMelee[client]) {
			if (aCommonInfected < 1) g_bCommonWithinMelee[client] = false;
			if (aCommonInfected > 0) {
				float c_pos[3], common_e_pos[3];
				
				GetClientAbsOrigin(client, c_pos);
				GetEntPropVector(aCommonInfected, Prop_Data, "m_vecOrigin", common_e_pos);
				
				float aimdist = GetVectorDistance(c_pos, common_e_pos);
				
				if (aimdist > c_fCI_MeleeRange) g_bCommonWithinMelee[client] = false;
			}
		}
		
		
		
		/* ====================================================================================================
		*
		*   �D��xA : Bash | flying Hunter, Jockey
		*
		==================================================================================================== */ 
		if (aHunterJockey > 0) {
			if (!g_bDanger[client]) g_bDanger[client] = true;
			
			float c_pos[3], e_pos[3];
			float lookat[3];
			
			GetClientAbsOrigin(client, c_pos);
			GetClientAbsOrigin(aHunterJockey, e_pos);
			e_pos[2] += -10.0;
			
			MakeVectorFromPoints(c_pos, e_pos, lookat);
			GetVectorAngles(lookat, angles);
			
			TeleportEntity(client, NULL_VECTOR, angles, NULL_VECTOR);
			buttons |= IN_ATTACK2;
			if (c_bDebug_Enabled) {
				PrintToChatAll("\x01[%.2f] \x05%N \x01shoved: \x04flying %N (%d)", GetGameTime(), client, aHunterJockey, aHunterJockey);
				EmitSoundToAll(SOUND_SWING, client);
			}
			return Plugin_Changed;
		}
		
		
		/* ====================================================================================================
		*
		*   �D��xB : Self Smoker | aCapSmoker
		*
		==================================================================================================== */ 
		if (aCapSmoker > 0) { // Shoot even if client invisible the smoker
			if (!g_bDanger[client]) g_bDanger[client] = true;
			
			float c_pos[3], e_pos[3];
			float lookat[3];
			
			GetClientAbsOrigin(client, c_pos);
			GetEntPropVector(aCapSmoker, Prop_Data, "m_vecOrigin", e_pos);
			e_pos[2] += 5.0;
			
			//PrintToChatAll("c_pos[0] %.1f  |  [1] %.1f  |  [2] %.1f", c_pos[0], c_pos[1], c_pos[2]);
			//PrintToChatAll("e_pos[0] %.1f  |  [1] %.1f  |  [2] %.1f", e_pos[0], e_pos[1], e_pos[2]);
			
			// GetClientEyePosition(client, c_pos);
			// GetClientEyePosition(aCapSmoker, e_pos);
			// e_pos[2] += -10.0;
			
			MakeVectorFromPoints(c_pos, e_pos, lookat);
			GetVectorAngles(lookat, angles);
			
			if (c_bDebug_Enabled) PrintToChatAll("\x01[%.2f] \x05%N \x01Cap Smoker: \x04%N (%d)", GetGameTime(), client, aCapSmoker, aCapSmoker);

			TeleportEntity(client, NULL_VECTOR, angles, NULL_VECTOR);
			
			float aimdist = GetVectorDistance(c_pos, e_pos);
			
			if (aimdist < 100.0) buttons |= IN_ATTACK2;
			else {
				buttons &= ~IN_ATTACK2;
				buttons |= IN_DUCK;
			}

			if (GetRandomInt(0, 4) == 0) buttons &= ~IN_ATTACK;
			else buttons |= IN_ATTACK;
			
			return Plugin_Changed;
		}
		
		
		/* ====================================================================================================
		*
		*  �D��xC : Help | aCap_Infected, aCap_Survivor
		*
		==================================================================================================== */ 
		if (aCap_Survivor > 0) { // Pass if the client and target are "visible" to each other. so aCap Smoker doesn't pass
			if (!g_bDanger[client]) g_bDanger[client] = true;
			
			float c_pos[3], e_pos[3];
			float lookat[3];
			
			GetClientEyePosition(client, c_pos);
			GetClientEyePosition(aCap_Survivor, e_pos);
			
			if (HasValidEnt(aCap_Survivor, "m_pounceAttacker")) e_pos[2] += 5.0;
			else if (aCapSmoker > 0) { // ���������Ă���Smoker
				GetClientEyePosition(aCapSmoker, e_pos);
				e_pos[2] += -10.0;
			}
			
			float aimdist = GetVectorDistance(c_pos, e_pos);
			
			MakeVectorFromPoints(c_pos, e_pos, lookat);
			GetVectorAngles(lookat, angles);
			
			if (c_bDebug_Enabled) PrintToChatAll("\x01[%.2f] \x05%N \x01Cap Survivor: \x04%N (%d)", GetGameTime(), client, aCap_Survivor, aCap_Survivor);
			
			/****************************************************************************************************/
			
			// If any of the following are active, Switch to the main weapon 
			if (isHaveItem(AW_Classname, "first_aid_kit")
				|| isHaveItem(AW_Classname, "defibrillator")
				|| HasValidEnt(client, "m_reviveTarget")) {
				UseItem(client, main_weapon);
			}
			
			// If the melee weapon is active and the dist from the target is 110 or more, switch to the main weapon
			if (isHaveItem(AW_Classname, "weapon_melee") && aimdist > 110.0) {
				if (g_bCommonWithinMelee[client]) g_bCommonWithinMelee[client] = false;
				UseItem(client, main_weapon);
			}
			
			/****************************************************************************************************/
			
			if ((!isHaveItem(AW_Classname, "weapon_melee")) || (isHaveItem(AW_Classname, "weapon_melee") && aimdist < 110.0)) {
				TeleportEntity(client, NULL_VECTOR, angles, NULL_VECTOR);
		
				if (((c_iHelp_ShoveType >= 1 && HasValidEnt(aCap_Survivor, "m_tongueOwner") && aimdist < 110.0)
						|| (c_iHelp_ShoveType >= 2 && HasValidEnt(aCap_Survivor, "m_jockeyAttacker") && aimdist < 100.0)
						|| (c_iHelp_ShoveType >= 3 && HasValidEnt(aCap_Survivor, "m_pounceAttacker") && aimdist < 100.0)))
				{
					if ((!c_bHelp_ShoveOnlyReloading) || (c_bHelp_ShoveOnlyReloading && isReloading(client)))
						buttons |= IN_ATTACK2; // ����
				}
				
				if (GetRandomInt(0, 4) == 0) buttons &= ~IN_ATTACK;
				else buttons |= IN_ATTACK;
				
				return Plugin_Changed;
			}
		} 
		else if (aCap_Infected > 0 && aCap_Survivor < 1) {
			if (!g_bDanger[client]) g_bDanger[client] = true;
			
			int zombieClass = getZombieClass(aCap_Infected);
			
			float c_pos[3], e_pos[3];
			float lookat[3];
			
			GetClientEyePosition(client, c_pos);
			
			if (aCapSmoker > 0) { // Prioritize aCapSmoker
				GetClientEyePosition(aCapSmoker, e_pos);
				e_pos[2] += -10.0;
			} else {
				GetClientEyePosition(aCap_Infected, e_pos);
				
				if (zombieClass == ZC_SMOKER || zombieClass == ZC_CHARGER) e_pos[2] += -9.0;
				else if (zombieClass == ZC_HUNTER) e_pos[2] += -14.0;
			}
			
			float aimdist = GetVectorDistance(c_pos, e_pos);
			
			if (zombieClass == ZC_CHARGER && aimdist < 300.0) e_pos[2] += 10.0;
			
			MakeVectorFromPoints(c_pos, e_pos, lookat);
			GetVectorAngles(lookat, angles);
			
			if (c_bDebug_Enabled) PrintToChatAll("\x01[%.2f] \x05%N \x01Cap Infected: \x04%N (%d)", GetGameTime(), client, aCap_Infected, aCap_Infected);
			
			/****************************************************************************************************/
			
			// If any of the following are active, Switch to the main weapon 
			if (isHaveItem(AW_Classname, "first_aid_kit")
				|| isHaveItem(AW_Classname, "defibrillator")
				|| HasValidEnt(client, "m_reviveTarget"))
			{
				UseItem(client, main_weapon);
			}
			
			// If the melee weapon is active and the dist from the target is 110 or more, switch to the main weapon
			if (isHaveItem(AW_Classname, "weapon_melee") && aimdist > 110.0)
			{
				if (g_bCommonWithinMelee[client]) g_bCommonWithinMelee[client] = false;
				UseItem(client, main_weapon);
			}
			
			/****************************************************************************************************/
			
			if ((!isHaveItem(AW_Classname, "weapon_melee")) || (isHaveItem(AW_Classname, "weapon_melee") && aimdist < 110.0)) {
				TeleportEntity(client, NULL_VECTOR, angles, NULL_VECTOR);
				
				if (aimdist < 100.0
					&& ((c_iHelp_ShoveType >= 1 && zombieClass == ZC_SMOKER)
						|| (c_iHelp_ShoveType >= 2 && zombieClass == ZC_JOCKEY)
						|| (c_iHelp_ShoveType >= 3 && zombieClass == ZC_HUNTER)))
				{
					if ((!c_bHelp_ShoveOnlyReloading) || (c_bHelp_ShoveOnlyReloading && isReloading(client)))
						buttons |= IN_ATTACK2; // Shove
				}
				
				if (GetRandomInt(0, 4) == 0) buttons &= ~IN_ATTACK;
				else buttons |= IN_ATTACK;
				
				return Plugin_Changed;
			}
		}
		
		
		
		/* ====================================================================================================
		*
		*   �D��xD : Tank Rock, Witch
		*
		==================================================================================================== */ 
		if (aTankRock > 1 && !HasValidEnt(client, "m_reviveTarget")) {
			float c_pos[3], rock_e_pos[3];
			float lookat[3];
			
			GetClientAbsOrigin(client, c_pos);
			GetEntPropVector(aTankRock, Prop_Data, "m_vecAbsOrigin", rock_e_pos);
			rock_e_pos[2] += -50.0;
			
			MakeVectorFromPoints(c_pos, rock_e_pos, lookat);
			GetVectorAngles(lookat, angles);
			
			if (c_bDebug_Enabled) {
				// PrintToChatAll("\x01rock : \x01[0] - \x04%.2f \x01, [1] - \x04%.2f \x01, [2] - \x04%.2f", rock_e_pos[0], rock_e_pos[1], rock_e_pos[2]);
				// PrintToChatAll("\x01client(%N) : \x01[0] - \x04%.2f \x01, [1] - \x04%.2f \x01, [2] - \x04%.2f", client, c_pos[0], c_pos[1], c_pos[2]);
				// PrintToChatAll("---");
			}
			
			float aimdist = GetVectorDistance(c_pos, rock_e_pos);
			
			if (aimdist > 40.0 && !isHaveItem(AW_Classname, "weapon_melee")) { //�ߐڂ������Ă��Ȃ��ꍇ
				TeleportEntity(client, NULL_VECTOR, angles, NULL_VECTOR);
				
				if (GetRandomInt(0, 4) == 0) buttons &= ~IN_ATTACK;
				else buttons |= IN_ATTACK;
			}
			
			return Plugin_Changed;
		}
		
		if (aWitch > 1) {
			float c_pos[3], witch_e_pos[3];
			float lookat[3];
			
			GetClientEyePosition(client, c_pos);
			GetEntPropVector(aWitch, Prop_Data, "m_vecAbsOrigin", witch_e_pos);
			witch_e_pos[2] += 40.0;
			
			MakeVectorFromPoints(c_pos, witch_e_pos, lookat);
			GetVectorAngles(lookat, angles);
			
			if (c_bDebug_Enabled) PrintToChatAll("\x01[%.2f] \x05%N \x01Witch: \x05(%d)", GetGameTime(), client, aWitch);
			
			TeleportEntity(client, NULL_VECTOR, angles, NULL_VECTOR);
			
			float aimdist = GetVectorDistance(c_pos, witch_e_pos);
			
			if (c_bWitch_Shotgun_Control && isHaveItem(AW_Classname, "shotgun")) {
				if (aimdist < 150.0) buttons |= IN_DUCK;
				
				if (aimdist < c_fWitch_Shotgun_Range_Min || aimdist > c_fWitch_Shotgun_Range_Max) { // 70 ~ 300
					if (GetRandomInt(0, 4) == 0) buttons &= ~IN_ATTACK;
					else buttons |= IN_ATTACK;
					//PrintToChatAll("\x05%N %.2f", client, aimdist);
				} else {
					buttons &= ~IN_ATTACK;
					//PrintToChatAll("\x04%N Attack Stop %.2f", client, aimdist);
				}
				return Plugin_Changed;
			}
			
			if (GetRandomInt(0, 4) == 0) buttons &= ~IN_ATTACK;
			else buttons |= IN_ATTACK;
			
			return Plugin_Changed;
		}
		
		
		
		/* ====================================================================================================
		*
		*   �D��xE : Common Infected
		*
		==================================================================================================== */ 
		if (aCommonInfected > 0) {
			if (!HasValidEnt(client, "m_reviveTarget") && StrContains(AW_Classname, "first_aid_kit", false) == -1) {
				// Even if aCommonInfected dies and disappears, the Entity may not disappear for a while.(Bot keeps shooting the place)�B Even with InValidEntity(), true appears...
				// When the entity disappears, m_nNextThinkTick will not advance, so skip that if NextThinkTick has the same value as before.
				
				int iNextThinkTick = GetEntProp(aCommonInfected, Prop_Data, "m_nNextThinkTick");
				
				if (g_Stock_NextThinkTick[client] != iNextThinkTick) // If visible aCommonInfected
				{
					float c_pos[3], common_e_pos[3];
					float lookat[3];
					
					GetClientEyePosition(client, c_pos);
					GetEntPropVector(aCommonInfected, Prop_Data, "m_vecOrigin", common_e_pos);
					
					//float height_difference = (c_pos[2] - common_e_pos[2]) - 60.0;
					
					common_e_pos[2] += 40.0;
					
					float aimdist = GetVectorDistance(c_pos, common_e_pos);
					
					//common_e_pos[2] += (25.0 + (aimdist * 0.05) - (height_difference * 0.1));
					
					// GetClientAbsOrigin(client, c_pos);
					// GetEntPropVector(aCommonInfected, Prop_Data, "m_vecOrigin", common_e_pos);
					// common_e_pos[2] += -30.0;
					
					int iSeq = GetEntProp(aCommonInfected, Prop_Send, "m_nSequence", 2);
					// Stagger			122, 123, 126, 127, 128, 133, 134
					// Down Stagger		128, 129, 130, 131
					// Object Climb (Very Low)	182, 183, 184, 185
					// Object Climb (Low)	190, 191, 192, 193, 194, 195, 196, 197, 198, 199
					// Object Climb (High)	206, 207, 208, 209, 210, 211, 218, 219, 220, 221, 222, 223
					if (iSeq >= 182 && iSeq <= 189) common_e_pos[2] += -10.0;
					
					MakeVectorFromPoints(c_pos, common_e_pos, lookat);
					GetVectorAngles(lookat, angles);
					
					/****************************************************************************************************/
					
					g_Stock_NextThinkTick[client] = iNextThinkTick; // Set the current m_nNextThinkTick
					
					if (c_bDebug_Enabled) PrintToChatAll("\x01[%.2f] \x05%N\x01 Commons: \x04(%d)\x01  |  Dist: \x04%.1f\x01  |  Melee Count: \x04%d", GetGameTime(), client, aCommonInfected, aimdist, iCI_MeleeCount);
					
					// iCI_MeleeCount is from ci_melee_range
					if (c_bCI_MeleeEnabled
						&& aimdist <= c_fCI_MeleeRange
						&& iCI_MeleeCount > 2) {
						g_bCommonWithinMelee[client] = true;
						
						static char sub_weapon[16];
						int slot1 = GetPlayerWeaponSlot(client, 1);
						if (slot1 > -1) {			
							GetEntityClassname(slot1, sub_weapon, sizeof(sub_weapon)); // SubWeapon
						}
						
						if (isHaveItem(sub_weapon, "weapon_melee")) {
							if (!isHaveItem(AW_Classname, "weapon_melee")) {
								FakeClientCommand(client, "use %s", sub_weapon);
							}
						}
					}
					
					if (int_target > 0) {
						if (aimdist <= 90.0) TeleportEntity(client, NULL_VECTOR, angles, NULL_VECTOR);
					} else {
						if (isHaveItem(AW_Classname, "weapon_melee")) {
							if (aimdist <= 90.0) TeleportEntity(client, NULL_VECTOR, angles, NULL_VECTOR);
						} else {
							TeleportEntity(client, NULL_VECTOR, angles, NULL_VECTOR);
						}
					}
					
					if (int_target < 1 || (int_target > 0 && aimdist <= 90.0)) { // If int_target and common at the same time, prioritize to int_target. Attack only when within 90.0 dist.
						if (isHaveItem(AW_Classname, "weapon_melee")) {
							if (GetRandomInt(0, 6) == 0) {
								if (aimdist <= 50.0) buttons |= IN_ATTACK2;
								else if (aimdist > 50.0 && aimdist <= 90.0) buttons |= IN_ATTACK;
							} else {
								if (aimdist <= 90.0) buttons |= IN_ATTACK; // 90.0
							}
							
							// if (GetRandomInt(0, 6) == 0) {
							// 	if (aimdist < 50.0) {
							// 		buttons |= IN_ATTACK2;
							// 	}
							// } else {
							// 	if (aimdist < 90.0) buttons |= IN_ATTACK;
							// }
						} else {
							if (aimdist > 60.0) {
								if (GetRandomInt(0, 4) == 0) buttons &= ~IN_ATTACK;
								else buttons |= IN_ATTACK;
							} else {
								if (GetRandomInt(0, 8) == 0) {
									if (GetRandomInt(0, 4) == 0) buttons &= ~IN_ATTACK;
									else buttons |= IN_ATTACK;
								} else {
									buttons |= IN_ATTACK2;
								}
								
								if (isReloading(client)) {
									if (GetRandomInt(0, 4) == 0) buttons &= ~IN_ATTACK2;
									else buttons |= IN_ATTACK2;
								}
							}
						}
						return Plugin_Changed;
					}
				}
				else // Skip if aCommonInfected is not visible
				{
					// PrintToChatAll("stock %i  |  next %i", g_Stock_NextThinkTick[client], iNextThinkTick);
				}
			}
		}
		
		
		
		/* ====================================================================================================
		*
		*   �D��xF : Special Infected and Tank (int_target)
		*
		==================================================================================================== */ 
		if (int_target > 0) {
			float c_pos[3], e_pos[3];
			float lookat[3];
			
			GetClientAbsOrigin(client, c_pos);
			
			int zombieClass = getZombieClass(int_target);
			
			if (aCapSmoker > 0) { // Prioritize aCapSmoker
				GetClientAbsOrigin(aCapSmoker, e_pos);
				e_pos[2] += -10.0;
			} else {
				GetClientAbsOrigin(int_target, e_pos);
				if (zombieClass == ZC_HUNTER
					&& (GetClientButtons(int_target) & IN_DUCK)) {
					if (GetVectorDistance(c_pos, e_pos) > 250.0) e_pos[2] += -30.0;
					else e_pos[2] += -35.0;
				} else if (zombieClass == ZC_JOCKEY) {
					e_pos[2] += -30.0;
				} else {
					e_pos[2] += -10.0;
				}
			}
			
			if (zombieClass == ZC_TANK && aTankRock > 0) return Plugin_Continue; // If the Tank and tank rock are visible at the same time, prioritize the tank rock
			
			float aimdist = GetVectorDistance(c_pos, e_pos);
			
			if (aimdist < 200.0) {if (!g_bDanger[client]) g_bDanger[client] = true;}
			
			MakeVectorFromPoints(c_pos, e_pos, lookat);
			GetVectorAngles(lookat, angles);
			
			/****************************************************************************************************/
			
			if(isHaveItem(AW_Classname, "first_aid_kit")
				|| isHaveItem(AW_Classname, "defibrillator")
				|| HasValidEnt(client, "m_reviveTarget")) {
				if (aimdist > 250.0) return Plugin_Continue;
				else { UseItem(client, main_weapon); }
			}
			
			if (isHaveItem(AW_Classname, "weapon_shotgun_chrome")
				|| isHaveItem(AW_Classname, "weapon_shotgun_spas")
				|| isHaveItem(AW_Classname, "weapon_pumpshotgun")
				|| isHaveItem(AW_Classname, "weapon_autoshotgun")) {
				if (aimdist > 1000.0) return Plugin_Continue;
			}
			
			if (isHaveItem(AW_Classname, "weapon_melee") && aCommonInfected < 1) {
				if (aimdist > 100.0) UseItem(client, main_weapon);
			}
			
			/****************************************************************************************************/
			
			bool isTargetBoomer = false;
			bool isBoomer_Shoot_OK = false;
			
			if (c_bSI_IgnoreBoomer && zombieClass == ZC_BOOMER) {
				float voS_pos[3];
				for (int s = 1; s <= MaxClients; ++s) {
					if (isSurvivor(s)
						&& IsPlayerAlive(s))
					{
						float fVomit = GetEntPropFloat(s, Prop_Send, "m_vomitStart");
						if (GetGameTime() - fVomit > 10.0) { // Survivors without vomit
							GetClientAbsOrigin(s, voS_pos);
							
							float dist = GetVectorDistance(voS_pos, e_pos); // Distance between the Survivor without vomit and the Boomer
							if (dist >= c_fSI_IgnoreBoomerRange) { isBoomer_Shoot_OK = true; } // If the survivor without vomit is farther than dist "c_fSI_IgnoreBoomerRange (def: 200)"
							else { isBoomer_Shoot_OK = false; break; } // If False appears even once, break
						}
					}
				}
				isTargetBoomer = true;
			}
			
			if ((zombieClass == ZC_JOCKEY && g_bShove[client][int_target])
				|| zombieClass == ZC_SMOKER
				|| (isTargetBoomer && !isBoomer_Shoot_OK))
			{
				if (aimdist < 90.0 && !isStagger(int_target)) {
					TeleportEntity(client, NULL_VECTOR, angles, NULL_VECTOR);
					buttons |= IN_ATTACK2;
					if (c_bDebug_Enabled) {
						PrintToChatAll("\x01[%.2f] \x05%N\x01 int_target shoved: \x04%N (%d)", GetGameTime(), client, int_target, int_target);
						EmitSoundToAll(SOUND_SWING, client);
					}
					return Plugin_Changed;
				}
			}
			
			if (!isHaveItem(AW_Classname, "weapon_melee")
				|| (aimdist < 100.0 && isHaveItem(AW_Classname, "weapon_melee")))
			{
				if (c_bDebug_Enabled) {
					if (!isTargetBoomer) PrintToChatAll("\x01[%.2f] \x05%N\x01 int_target: \x04%N (%d)", GetGameTime(), client, int_target, int_target);
					else PrintToChatAll("\x01[%.2f] \x05%N\x01 int_target: \x04%N (%d) (Shoot: %s)", GetGameTime(), client, int_target, int_target, (isBoomer_Shoot_OK) ? "OK" : "NO");
				}
			
				if (!isTargetBoomer || (isTargetBoomer && isBoomer_Shoot_OK)) {
					TeleportEntity(client, NULL_VECTOR, angles, NULL_VECTOR);
					
					if (GetRandomInt(0, 4) == 0) buttons &= ~IN_ATTACK;
					else buttons |= IN_ATTACK;
				}
				
				return Plugin_Changed;
			}
		}
		
		// if there is no danger, false
		if (g_bDanger[client]) g_bDanger[client] = false;
	}
	
	return Plugin_Continue;
}



/* ================================================================================================
*=
*= 		Incapacitated Run Cmd
*=
================================================================================================ */
stock Action onSBRunCmd_Incapacitated(int client, int &buttons, float vel[3], float angles[3])
{
	if (isIncapacitated(client)) {
		int aCapper = -1;
		float min_dist_Cap = 100000.0;
		float self_pos[3], target_pos[3];
		
		GetClientEyePosition(client, self_pos);
		if (!NeedsTeammateHelp(client)) {
			for (int x = 1; x <= MaxClients; ++x) {
				// �S������Ă��鐶���҂�T��
				if (isSurvivor(x)
					&& NeedsTeammateHelp(x)
					&& (x != client)
					&& (isVisibleTo(client, x) || isVisibleTo(x, client)))
				{
					GetClientAbsOrigin(x, target_pos);
					float dist = GetVectorDistance(self_pos, target_pos);
					if (dist < min_dist_Cap) {
						min_dist_Cap = dist;
						aCapper = x;
					}
				}
				
				// �S�����Ă�����ꊴ���҂�T��
				if (isInfected(x)
					&& CappingSuvivor(x)
					&& (isVisibleTo(client, x) || isVisibleTo(x, client)))
				{
					GetClientAbsOrigin(x, target_pos);
					float dist = GetVectorDistance(self_pos, target_pos);
					if (dist < min_dist_Cap) {
						min_dist_Cap = dist;
						aCapper = x;
					}
				}
			}
		}
		
		if (aCapper > 0) {
			float c_pos[3], e_pos[3];
			float lookat[3];
			
			GetClientEyePosition(client, c_pos);
			GetClientEyePosition(aCapper, e_pos);
			
			e_pos[2] += -15.0;		
			
			if ((isSurvivor(aCapper) && HasValidEnt(aCapper, "m_pounceAttacker"))) {
				e_pos[2] += 18.0;
				// Raise angles if near
			}
			if ((isInfected(aCapper) && getZombieClass(aCapper) == ZC_HUNTER)) {
				e_pos[2] += -15.0;
			}
			
			MakeVectorFromPoints(c_pos, e_pos, lookat);
			GetVectorAngles(lookat, angles);
			
			if (c_bDebug_Enabled) {
				if (isSurvivor(aCapper)) PrintToChatAll("\x01[%.2f] \x05%N \x01Cap Survivor Incapacitated: \x04%N", GetGameTime(), client, aCapper);
				else PrintToChatAll("\x01[%.2f] \x05%N \x01Cap Infected Incapacitated: \x04%N", GetGameTime(), client, aCapper);
			}
			TeleportEntity(client, NULL_VECTOR, angles, NULL_VECTOR);
			
			if (GetRandomInt(0, 4) == 0) buttons &= ~IN_ATTACK;
			else buttons |= IN_ATTACK;
			
			return Plugin_Changed;
		}
		
		
		int int_target = -1;
		int aCommonInfected = -1;
		if (aCapper < 1 && !NeedsTeammateHelp(client)) {
			float min_dist = 100000.0;
			float ci_pos[3];
			
			for (int x = 1; x <= MaxClients; ++x){
				if (isInfected(x)
					&& IsPlayerAlive(x)
					&& (isVisibleTo(client, x) || isVisibleTo(x, client)))
				{
					GetClientAbsOrigin(x, target_pos);
					float dist = GetVectorDistance(self_pos, target_pos);
					if (dist < min_dist) {
						min_dist = dist;
						int_target = x;
						aCommonInfected = -1;
					}
				}
			}
			
			if (c_bCI_Enabled) {
				for (int iEntity = MaxClients+1; iEntity <= MAXENTITIES; ++iEntity) {
					if (IsCommonInfected(iEntity)
						&& GetEntProp(iEntity, Prop_Data, "m_iHealth") > 0
						&& isVisibleToEntity(iEntity, client))
					{
						GetEntPropVector(iEntity, Prop_Data, "m_vecAbsOrigin", ci_pos);
						float dist = GetVectorDistance(self_pos, ci_pos);
						
						if (dist < min_dist) {
							min_dist = dist;
							aCommonInfected = iEntity;
							int_target = -1;
						}
					}
				}
			}
		}
		
		if (aCommonInfected > 0) {
			float c_pos[3], common_e_pos[3];
			float lookat[3];
			
			GetClientEyePosition(client, c_pos);
			GetEntPropVector(aCommonInfected, Prop_Data, "m_vecOrigin", common_e_pos);
			common_e_pos[2] += 35.0;
			
			MakeVectorFromPoints(c_pos, common_e_pos, lookat);
			GetVectorAngles(lookat, angles);
			
			float aimdist = GetVectorDistance(c_pos, common_e_pos);
			
			/****************************************************************************************************/
			
			if (c_bDebug_Enabled) PrintToChatAll("\x01[%.2f] \x05%N\x01 Commons Incapacitated Dist: %.1f", GetGameTime(), client, aimdist);
			
			TeleportEntity(client, NULL_VECTOR, angles, NULL_VECTOR);
			
			if (GetRandomInt(0, 4) == 0) buttons &= ~IN_ATTACK;
			else buttons |= IN_ATTACK;
			
			return Plugin_Changed;
		}
		
		if (int_target > 0) {
			float c_pos[3], e_pos[3];
			float lookat[3];
			
			GetClientEyePosition(client, c_pos);
			GetClientEyePosition(int_target, e_pos);
			
			e_pos[2] += -15.0
			
			int zombieClass = getZombieClass(int_target);
			if (zombieClass == ZC_JOCKEY) {
				e_pos[2] += -30.0;
			} else if (zombieClass == ZC_HUNTER) {
				if ((GetClientButtons(int_target) & IN_DUCK) || HasValidEnt(int_target, "m_pounceVictim")) e_pos[2] += -25.0;
			}
			
			MakeVectorFromPoints(c_pos, e_pos, lookat);
			GetVectorAngles(lookat, angles);
			
			if (c_bDebug_Enabled) PrintToChatAll("\x01[%.2f] \x05%N \x01int target Incapacitated: \x04%N", GetGameTime(), client, int_target);
			
			TeleportEntity(client, NULL_VECTOR, angles, NULL_VECTOR);
			
			if (GetRandomInt(0, 4) == 0) buttons &= ~IN_ATTACK;
			else buttons |= IN_ATTACK;
			
			return Plugin_Changed;
		}
	}
	
	return Plugin_Continue;
}


/* ================================================================================================
*=
*=		Events
*=
================================================================================================ */
public Action Event_PlayerIncapacitated(Handle event, const char[] name, bool dontBroadcast)
{
	if (!g_hEnabled) return Plugin_Handled;
	
	int victim = GetClientOfUserId(GetEventInt(event, "userid"));
	int attackerentid = GetEventInt(event, "attackerentid");
	
	// int type = GetEventInt(event, "type");
	// PrintToChatAll("\x04PlayerIncapacitated");
	// PrintToChatAll("type %i", type);
	
	if (isSurvivor(victim) && IsWitch(attackerentid))
	{
		g_iWitch_Process[attackerentid] = WITCH_INCAPACITATED;
		
		// PrintToChatAll("attackerentid %i attacked %N", attackerentid, victim);
		// int health = GetEventInt(event, "health");
		// int dmg_health = GetEventInt(event, "dmg_health");
		// PrintToChatAll("health: %i, damage: %i", health, dmg_health);
	}
	
	return Plugin_Handled;
}

public Action Event_PlayerDeath(Handle event, const char[] name, bool dontBroadcast)
{
	if (!g_hEnabled) return Plugin_Handled;
	
	int victim = GetClientOfUserId(GetEventInt(event, "userid"));
	int attackerentid = GetEventInt(event, "attackerentid");
	
	// int type = GetEventInt(event, "type");
	// PrintToChatAll("\x04PlayerDeath");
	// PrintToChatAll("type %i", type);
	
	if (isSurvivor(victim) && IsWitch(attackerentid))
	{
		g_iWitch_Process[attackerentid] = WITCH_KILLED;
		
		// PrintToChatAll("attackerentid %i attacked %N", attackerentid, victim);
		// int health = GetEventInt(event, "health");
		// int dmg_health = GetEventInt(event, "dmg_health");
		// PrintToChatAll("health: %i, damage: %i", health, dmg_health);
	}
	
	// Witch Damage type: 4
	// Witch Incapacitated type: 32772
	
	return Plugin_Handled;
}

public Action Event_WitchRage(Handle event, const char[] name, bool dontBroadcast)
{
	int attacker = GetClientOfUserId(GetEventInt(event, "userid"));
	
	if (isSurvivor(attacker)) {
		// CallBotstoWitch(attacker);
		g_bWitchActive = true;
	}	
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if (entity >= MaxClients && g_hEnabled && strcmp(classname, "witch") == 0)
	{
		g_iWitch_Process[entity] = 0;
	}
}

public void OnEntityDestroyed(int entity) {
	if(entity == -1) return;
	static char classname[32];
	GetEntityClassname(entity, classname, sizeof(classname));
	
	if (StrEqual(classname, "witch", false)) {
		if (g_bWitchActive) {
			int iWitch_Count = 0;
			for (int iEntity = MaxClients+1; iEntity <= MAXENTITIES; ++iEntity)
			{
				if (IsWitch(iEntity) && GetEntProp(iEntity, Prop_Data, "m_iHealth") > 0 && IsWitchRage(iEntity))
				{
					iWitch_Count++;
				}
				
				//PrintToChatAll("witch count %d", iWitch_Count);
				
				if (iWitch_Count == 0) {g_bWitchActive = false;}
			}
		}
	}
}


/* ================================================================================================
*=
*=		Stock any
*=
================================================================================================ */
stock void ScriptCommand(int client, const char[] command, const char[] arguments, any ...)
{
	static char vscript[PLATFORM_MAX_PATH];
	VFormat(vscript, sizeof(vscript), arguments, 4);
	
	int flags = GetCommandFlags(command);
	SetCommandFlags(command, flags & ~FCVAR_CHEAT);
	FakeClientCommand(client, "%s %s", command, vscript);
	SetCommandFlags(command, flags);
}

stock void L4D2_RunScript(const char[] sCode, any ...)
{
	static iScriptLogic = INVALID_ENT_REFERENCE;
	if(iScriptLogic == INVALID_ENT_REFERENCE || !IsValidEntity(iScriptLogic)) {
		iScriptLogic = EntIndexToEntRef(CreateEntityByName("logic_script"));
		if(iScriptLogic == INVALID_ENT_REFERENCE || !IsValidEntity(iScriptLogic))
			SetFailState("Could not create 'logic_script'");
		
		DispatchSpawn(iScriptLogic);
	}
	
	static char sBuffer[512];
	VFormat(sBuffer, sizeof(sBuffer), sCode, 2);
	
	SetVariantString(sBuffer);
	AcceptEntityInput(iScriptLogic, "RunScriptCode");
}


/*
*
*   Bool
*
*/
stock bool NeedsTeammateHelp(int client)
{
	if (HasValidEnt(client, "m_tongueOwner")
	|| HasValidEnt(client, "m_pounceAttacker")
	|| HasValidEnt(client, "m_jockeyAttacker")
	|| HasValidEnt(client, "m_carryAttacker")
	|| HasValidEnt(client, "m_pummelAttacker"))
	{
		return true;
	}
	
	return false;
}

stock bool NeedsTeammateHelp_ExceptSmoker(int client)
{
	if (HasValidEnt(client, "m_pounceAttacker")
	|| HasValidEnt(client, "m_jockeyAttacker")
	|| HasValidEnt(client, "m_carryAttacker")
	|| HasValidEnt(client, "m_pummelAttacker"))
	{
		return true;
	}
	
	return false;
}

stock bool CappingSuvivor(int client)
{
	if (HasValidEnt(client, "m_tongueVictim")
	|| HasValidEnt(client, "m_pounceVictim")
	|| HasValidEnt(client, "m_jockeyVictim")
	|| HasValidEnt(client, "m_carryVictim")
	|| HasValidEnt(client, "m_pummelVictim"))
	{
		return true;
	}
	
	return false;
}

stock bool HasValidEnt(int client, const char[] entprop)
{
	int ent = GetEntPropEnt(client, Prop_Send, entprop);
	
	return (ent > 0
		&& IsClientInGame(ent));
}

stock bool IsWitchRage(int id) {
	if (GetEntPropFloat(id, Prop_Send, "m_rage") >= 1.0) return true;
	return false;
}

stock bool IsCommonInfected(int iEntity)
{
	if (iEntity && IsValidEntity(iEntity))
	{
		static char strClassName[16];
		GetEntityClassname(iEntity, strClassName, sizeof(strClassName));
		
		if (strcmp(strClassName[7], "infected", false) == 0)
			return true;
	}
	return false;
}

stock bool IsWitch(int iEntity)
{
	if (iEntity && IsValidEntity(iEntity))
	{
		static char strClassName[8];
		GetEntityClassname(iEntity, strClassName, sizeof(strClassName));
		if (StrEqual(strClassName, "witch"))
			return true;
	}
	return false;
}

stock bool IsTankRock(int iEntity)
{
	if (iEntity && IsValidEntity(iEntity))
	{
		static char strClassName[16];
		GetEntityClassname(iEntity, strClassName, sizeof(strClassName));
		if (StrEqual(strClassName, "tank_rock"))
			return true;
	}
	return false;
}

stock bool isGhost(int i)
{
	return GetEntProp(i, Prop_Send, "m_isGhost") != 0;
}

stock bool isSpecialInfectedBot(int i)
{
	return i > 0 && i <= MaxClients && IsClientInGame(i) && IsFakeClient(i) && GetClientTeam(i) == 3;
}

stock bool isSurvivorBot(int i)
{
	return isSurvivor(i) && IsFakeClient(i);
}

stock bool isInfected(int i)
{
	return i > 0 && i <= MaxClients && IsClientInGame(i) && GetClientTeam(i) == 3 && !isGhost(i);
}

stock bool isSurvivor(int i)
{
	return i > 0 && i <= MaxClients && IsClientInGame(i) && GetClientTeam(i) == 2;
}

stock any getZombieClass(int client)
{
	return GetEntProp(client, Prop_Send, "m_zombieClass");
}

stock bool isIncapacitated(int client)
{
	return GetEntProp(client, Prop_Send, "m_isIncapacitated", 1) == 1;
}

stock bool isReloading(int client)
{
	int slot0 = GetPlayerWeaponSlot(client, 0);
	if (slot0 > -1) {
		return GetEntProp(slot0, Prop_Data, "m_bInReload") > 0;
	}
	return false;
}

stock bool isStagger(int client) // Client Only
{
	float staggerPos[3];
	GetEntPropVector(client, Prop_Send, "m_staggerStart", staggerPos);
	
	if (staggerPos[0] != 0.0 && staggerPos[1] != 0.0 && staggerPos[2] != 0.0) return true;
	
	return false;
}

stock bool isJockeyLeaping(int client)
{
	float jockeyVelocity[3];
	GetEntDataVector(client, g_Velo, jockeyVelocity);
	if (jockeyVelocity[2] != 0.0) return true;
	return false;
}

stock bool isHaveItem(const char[] FItem, const char[] SItem)
{
	if (StrContains(FItem, SItem, false) > -1) return true;
	
	return false;
}

stock void UseItem(int client, const char[] FItem)
{
	FakeClientCommand(client, "use %s", FItem);
}

stock any PrimaryExtraAmmoCheck(int client, int weapon_index)
{
	// Offset:
	// 12: Rifle ALL (Other than M60)
	// 20: SMG ALL
	// 28: Chrome, Pump
	// 32: SPAS, Auto
	// 36: Hunting
	// 40: Sniper
	// 68: Granade Launcher
	// NONE: Rifle M60 is only Clip1
	int offset;
	
	static char sWeaponName[32];
	GetEdictClassname(weapon_index, sWeaponName, sizeof(sWeaponName));
	if (isHaveItem(sWeaponName, "weapon_rifle")) offset = 12;
	else if (isHaveItem(sWeaponName, "weapon_smg")) offset = 20;
	else if (isHaveItem(sWeaponName, "weapon_shotgun_chrome") || isHaveItem(sWeaponName, "weapon_pumpshotgun")) offset = 28;
	else if (isHaveItem(sWeaponName, "weapon_shotgun_spas") || isHaveItem(sWeaponName, "weapon_autoshotgun")) offset = 32;
	else if (isHaveItem(sWeaponName, "weapon_hunting_")) offset = 36;
	else if (isHaveItem(sWeaponName, "weapon_sniper")) offset = 40;
	else if (isHaveItem(sWeaponName, "weapon_grenade_launcher")) offset = 68;
	
	int extra_ammo = GetEntData(client, (g_iAmmoOffset + offset));
	//PrintToChatAll("%N Gun Name: %s, Offset: %i, ExtraAmmo: %i:", client, sWeaponName, offset, extra_ammo);
	
	return extra_ammo;
}

/* -------------------------------------------------------------------------------------------------------------------------------------------------------------- 

--------------------------------------------------------------------------------------------------------------------------------------------------------------------- */

public bool traceFilter(int entity, int mask, any self)
{
	return entity != self;
}

public bool TraceRayDontHitPlayers(int entity, int mask)
{
	// Check if the beam hit a player and tell it to keep tracing if it did
	return (entity <= 0 || entity > MaxClients);
}

// Determine if the head of the target can be seen from the client
stock bool isVisibleTo(int client, int target)
{
	bool ret = false;
	float aim_angles[3];
	float self_pos[3];
	
	GetClientEyePosition(client, self_pos);
	computeAimAngles(client, target, aim_angles);
	
	Handle trace = TR_TraceRayFilterEx(self_pos, aim_angles, MASK_VISIBLE, RayType_Infinite, traceFilter, client);
	if (TR_DidHit(trace)) {
		int hit = TR_GetEntityIndex(trace);
		if (hit == target) {
			ret = true;
		}
	}
	CloseHandle(trace);
	return ret;
}

/* Determine if the head of the entity can be seen from the client */
stock bool isVisibleToEntity(int target, int client)
{
	bool ret = false;
	float aim_angles[3];
	float self_pos[3], target_pos[3];
	float lookat[3];
	
	GetEntPropVector(target, Prop_Data, "m_vecAbsOrigin", target_pos);
	GetClientEyePosition(client, self_pos);
	
	MakeVectorFromPoints(target_pos, self_pos, lookat);
	GetVectorAngles(lookat, aim_angles);
	
	Handle trace = TR_TraceRayFilterEx(target_pos, aim_angles, MASK_VISIBLE, RayType_Infinite, traceFilter, target);
	if (TR_DidHit(trace)) {
		int hit = TR_GetEntityIndex(trace);
		if (hit == client) {
			ret = true;
		}
	}
	delete trace;
	return ret;
}

/* From the client to the target's head, whether it is blocked by mesh */
stock bool isInterruptTo(int client, int target)
{
	bool ret = false;
	float aim_angles[3];
	float self_pos[3];
	
	GetClientEyePosition(client, self_pos);
	computeAimAngles(client, target, aim_angles);
	int Handle trace = TR_TraceRayFilterEx(self_pos, aim_angles, MASK_SOLID, RayType_Infinite, traceFilter, client);
	if (TR_DidHit(trace)) {
		int hit = TR_GetEntityIndex(trace);
		if (hit == target) {
			ret = true;
		}
	}
	CloseHandle(trace);
	return ret;
}

// Calculate the angles from client to target
stock void computeAimAngles(int client, int target, float angles[3], int type = 1)
{
	float target_pos[3];
	float self_pos[3];
	float lookat[3];
	
	GetClientEyePosition(client, self_pos);
	switch (type) {
		case 1: { // Eye (Default)
			GetClientEyePosition(target, target_pos);
		}
		case 2: { // Body
			GetEntPropVector(target, Prop_Data, "m_vecAbsOrigin", target_pos);
		}
		case 3: { // Chest
			GetClientAbsOrigin(target, target_pos);
			target_pos[2] += 45.0;
		}
	}
	MakeVectorFromPoints(self_pos, target_pos, lookat);
	GetVectorAngles(lookat, angles);
}
