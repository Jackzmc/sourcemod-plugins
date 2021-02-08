/**
// ====================================================================================================
Change Log:

1.0.2 (08-February-2021)
    - Fixed wrong value on max health calculation.
    - Fixed sprite hiding behind tank rocks.
    - Fixed sprite hiding while tank throws rocks (ability use).
    - Moved visibility logic to timer.

1.0.1 (30-January-2021)
    - Public release.

1.0.0 (21-April-2019)
    - Private version.

// ====================================================================================================
*/

// ====================================================================================================
// Plugin Info - define
// ====================================================================================================
#define PLUGIN_NAME                   "[L4D1 & L4D2] Tank HP Sprite"
#define PLUGIN_AUTHOR                 "Mart"
#define PLUGIN_DESCRIPTION            "Shows a sprite at the tank head that goes from green to red based on its HP"
#define PLUGIN_VERSION                "1.0.2"
#define PLUGIN_URL                    "https://forums.alliedmods.net/showthread.php?t=330370"

// ====================================================================================================
// Plugin Info
// ====================================================================================================
public Plugin myinfo =
{
    name        = PLUGIN_NAME,
    author      = PLUGIN_AUTHOR,
    description = PLUGIN_DESCRIPTION,
    version     = PLUGIN_VERSION,
    url         = PLUGIN_URL
}

// ====================================================================================================
// Includes
// ====================================================================================================
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

// ====================================================================================================
// Pragmas
// ====================================================================================================
#pragma semicolon 1
#pragma newdecls required

// ====================================================================================================
// Cvar Flags
// ====================================================================================================
#define CVAR_FLAGS                    FCVAR_NOTIFY
#define CVAR_FLAGS_PLUGIN_VERSION     FCVAR_NOTIFY|FCVAR_DONTRECORD|FCVAR_SPONLY

// ====================================================================================================
// Filenames
// ====================================================================================================
#define CONFIG_FILENAME               "l4d_tank_hp_sprite"

// ====================================================================================================
// Defines
// ====================================================================================================
#define CLASSNAME_ENV_SPRITE          "env_sprite"
#define CLASSNAME_TANK_ROCK           "tank_rock"

#define TEAM_SPECTATOR                1
#define TEAM_SURVIVOR                 2
#define TEAM_INFECTED                 3
#define TEAM_HOLDOUT                  4

#define FLAG_TEAM_NONE                (0 << 0) // 0 | 0000
#define FLAG_TEAM_SURVIVOR            (1 << 0) // 1 | 0001
#define FLAG_TEAM_INFECTED            (1 << 1) // 2 | 0010
#define FLAG_TEAM_SPECTATOR           (1 << 2) // 4 | 0100
#define FLAG_TEAM_HOLDOUT             (1 << 3) // 8 | 1000

#define L4D1_ZOMBIECLASS_TANK         5
#define L4D2_ZOMBIECLASS_TANK         8

#define MAXENTITIES                   2048

// ====================================================================================================
// Plugin Cvars
// ====================================================================================================
static ConVar g_hCvar_Enabled;
static ConVar g_hCvar_ZAxis;
static ConVar g_hCvar_FadeDistance;
static ConVar g_hCvar_Sight;
static ConVar g_hCvar_AttackDelay;
static ConVar g_hCvar_AliveShow;
static ConVar g_hCvar_AliveModel;
static ConVar g_hCvar_AliveAlpha;
static ConVar g_hCvar_AliveScale;
static ConVar g_hCvar_DeadShow;
static ConVar g_hCvar_DeadModel;
static ConVar g_hCvar_DeadAlpha;
static ConVar g_hCvar_DeadScale;
static ConVar g_hCvar_DeadColor;
static ConVar g_hCvar_Team;
static ConVar g_hCvar_AllSpecials;

// ====================================================================================================
// bool - Plugin Variables
// ====================================================================================================
static bool   g_bL4D2;
static bool   g_bConfigLoaded;
static bool   g_bEventsHooked;
static bool   g_bCvar_Enabled;
static bool   g_bCvar_Sight;
static bool   g_bCvar_AttackDelay;
static bool   g_bCvar_AliveShow;
static bool   g_bCvar_DeadShow;

// ====================================================================================================
// int - Plugin Variables
// ====================================================================================================
static int    g_iTankClass;
static int    g_iCvar_AliveAlpha;
static int    g_iCvar_DeadAlpha;
static int    g_iCvar_FadeDistance;
static int    g_iCvar_Team;

// ====================================================================================================
// float - Plugin Variables
// ====================================================================================================
static float  g_fVPlayerMins[3] = {-16.0, -16.0,  0.0};
static float  g_fVPlayerMaxs[3] = { 16.0,  16.0, 71.0};
static float  g_fVPos[3];
static float  g_fCvar_ZAxis;
static float  g_fCvar_AttackDelay;
static float  g_fCvar_AliveScale;
static float  g_fCvar_DeadScale;

// ====================================================================================================
// string - Plugin Variables
// ====================================================================================================
static char   g_sCvar_AliveModel[100];
static char   g_sCvar_AliveAlpha[4];
static char   g_sCvar_AliveScale[5];
static char   g_sCvar_DeadModel[100];
static char   g_sCvar_DeadAlpha[4];
static char   g_sCvar_DeadScale[5];
static char   g_sCvar_DeadColor[12];
static char   g_sCvar_FadeDistance[5];

// ====================================================================================================
// client - Plugin Variables
// ====================================================================================================
static int    gc_iTankSpriteRef[MAXPLAYERS+1] = { INVALID_ENT_REFERENCE, ... };
static bool   gc_bVisible[MAXPLAYERS+1][MAXPLAYERS+1];
static float  gc_fLastAttack[MAXPLAYERS+1][MAXPLAYERS+1];

// ====================================================================================================
// entity - Plugin Variables
// ====================================================================================================
static bool   ge_bInvalidTrace[MAXENTITIES+1];
static int    ge_iOwner[MAXENTITIES+1];

// ====================================================================================================
// Plugin Start
// ====================================================================================================
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    EngineVersion engine = GetEngineVersion();

    if (engine != Engine_Left4Dead && engine != Engine_Left4Dead2)
    {
        strcopy(error, err_max, "This plugin only runs in \"Left 4 Dead\" and \"Left 4 Dead 2\" game");
        return APLRes_SilentFailure;
    }

    g_bL4D2 = (engine == Engine_Left4Dead2);
    g_iTankClass = (g_bL4D2 ? L4D2_ZOMBIECLASS_TANK : L4D1_ZOMBIECLASS_TANK);

    return APLRes_Success;
}

/****************************************************************************************************/

public void OnPluginStart()
{
    CreateConVar("l4d_tank_hp_sprite_version", PLUGIN_VERSION, PLUGIN_DESCRIPTION, CVAR_FLAGS_PLUGIN_VERSION);
    g_hCvar_Enabled      = CreateConVar("l4d_tank_hp_sprite_enable", "1", "Enable/Disable the plugin.\n0 = Disable, 1 = Enable", CVAR_FLAGS, true, 0.0, true, 1.0);
    g_hCvar_ZAxis        = CreateConVar("l4d_tank_hp_sprite_z_axis", "92", "Additional Z distance based on the tank position.", CVAR_FLAGS, true, 0.0);
    g_hCvar_FadeDistance = CreateConVar("l4d_tank_hp_sprite_fade_distance", "-1", "Minimum distance that a client must be from the tank to see the sprite (both alive and dead sprites).\n-1 = Always visible.", CVAR_FLAGS, true, -1.0, true, 9999.0);
    g_hCvar_Sight        = CreateConVar("l4d_tank_hp_sprite_sight", "1", "Show the sprite to the survivor only if the Tank is on sight.\n0 = OFF, 1 = ON.", CVAR_FLAGS, true, 0.0, true, 1.0);
    g_hCvar_AttackDelay  = CreateConVar("l4d_tank_hp_sprite_attack_delay", "0.0", "Show the sprite to the survivor attacker, by this amount of time in seconds, after hitting the Tank.\n0 = OFF.", CVAR_FLAGS, true, 0.0);
    g_hCvar_AliveShow    = CreateConVar("l4d_tank_hp_sprite_alive_show", "1", "Show the alive sprite while tank is alive.\n0 = OFF, 1 = ON.", CVAR_FLAGS, true, 0.0, true, 1.0);
    g_hCvar_AliveModel   = CreateConVar("l4d_tank_hp_sprite_alive_model", "materials/vgui/healthbar_white.vmt", "Model of alive tank sprite.");
    g_hCvar_AliveAlpha   = CreateConVar("l4d_tank_hp_sprite_alive_alpha", "200", "Alpha of alive tank sprite.\n0 = Invisible, 255 = Fully Visible", CVAR_FLAGS, true, 0.0, true, 255.0);
    g_hCvar_AliveScale   = CreateConVar("l4d_tank_hp_sprite_alive_scale", "0.25", "Scale of alive tank sprite (increases both height and width).\nNote: Some range values maintain the same size. (e.g. from 0.0 to 0.38 the size doesn't change).", CVAR_FLAGS, true, 0.0);
    g_hCvar_DeadShow     = CreateConVar("l4d_tank_hp_sprite_dead_show", "1", "Show the dead sprite when a tank dies.\n0 = OFF, 1 = ON.", CVAR_FLAGS, true, 0.0, true, 1.0);
    g_hCvar_DeadModel    = CreateConVar("l4d_tank_hp_sprite_dead_model", "materials/sprites/death_icon.vmt", "Model of dead tank sprite.");
    g_hCvar_DeadAlpha    = CreateConVar("l4d_tank_hp_sprite_dead_alpha", "200", "Alpha of dead tank sprite.\n0 = Invisible, 255 = Fully Visible", CVAR_FLAGS, true, 0.0, true, 255.0);
    g_hCvar_DeadScale    = CreateConVar("l4d_tank_hp_sprite_dead_scale", "0.25", "Scale of dead tank sprite (increases both height and width).\nSome range values maintain the size the same.", CVAR_FLAGS, true, 0.0);
    g_hCvar_DeadColor    = CreateConVar("l4d_tank_hp_sprite_dead_color", "225 0 0", "Color of dead tank sprite.\nUse three values between 0-255 separated by spaces (\"<0-255> <0-255> <0-255>\").", CVAR_FLAGS);
    g_hCvar_Team         = CreateConVar("l4d_tank_hp_sprite_team", "3", "Which teams should the sprite be visible.\n0 = NONE, 1 = SURVIVOR, 2 = INFECTED, 4 = SPECTATOR, 8 = HOLDOUT.\nAdd numbers greater than 0 for multiple options.\nExample: \"3\", enables for SURVIVOR and INFECTED.", CVAR_FLAGS, true, 0.0, true, 15.0);
    g_hCvar_AllSpecials  = CreateConVar("l4d_tank_hp_sprite_all_specials", "1", "Should all specials have healthbar or only tanks\n0 = Tanks Only, 1 = All Specials", CVAR_FLAGS, true, 0.0, true, 1.0);

    g_hCvar_Enabled.AddChangeHook(Event_ConVarChanged);
    g_hCvar_ZAxis.AddChangeHook(Event_ConVarChanged);
    g_hCvar_FadeDistance.AddChangeHook(Event_ConVarChanged);
    g_hCvar_Sight.AddChangeHook(Event_ConVarChanged);
    g_hCvar_AttackDelay.AddChangeHook(Event_ConVarChanged);
    g_hCvar_AliveShow.AddChangeHook(Event_ConVarChanged);
    g_hCvar_AliveModel.AddChangeHook(Event_ConVarChanged);
    g_hCvar_AliveAlpha.AddChangeHook(Event_ConVarChanged);
    g_hCvar_AliveScale.AddChangeHook(Event_ConVarChanged);
    g_hCvar_DeadShow.AddChangeHook(Event_ConVarChanged);
    g_hCvar_DeadModel.AddChangeHook(Event_ConVarChanged);
    g_hCvar_DeadAlpha.AddChangeHook(Event_ConVarChanged);
    g_hCvar_DeadScale.AddChangeHook(Event_ConVarChanged);
    g_hCvar_DeadColor.AddChangeHook(Event_ConVarChanged);
    g_hCvar_Team.AddChangeHook(Event_ConVarChanged);

    // Load plugin configs from .cfg
    AutoExecConfig(true, CONFIG_FILENAME);

    // Admin Commands
    RegAdminCmd("sm_print_cvars_l4d_tank_hp_sprite", CmdPrintCvars, ADMFLAG_ROOT, "Print the plugin related cvars and their respective values to the console.");

    CreateTimer(0.1, TimerKill, _, TIMER_REPEAT);
    CreateTimer(0.1, TimerVisible, _, TIMER_REPEAT);
    CreateTimer(0.1, TimerRender, _, TIMER_REPEAT);
}

/****************************************************************************************************/

public void OnPluginEnd()
{
    int entity;
    char targetname[64];

    entity = INVALID_ENT_REFERENCE;
    while ((entity = FindEntityByClassname(entity, CLASSNAME_ENV_SPRITE)) != INVALID_ENT_REFERENCE)
    {
        if (GetEntProp(entity, Prop_Data, "m_iHammerID") == -1)
        {
            GetEntPropString(entity, Prop_Data, "m_iName", targetname, sizeof(targetname));
            if (StrEqual(targetname, "l4d_tank_hp_sprite"))
                AcceptEntityInput(entity, "Kill");
        }
    }
}

/****************************************************************************************************/

public void OnConfigsExecuted()
{
    GetCvars();

    g_bConfigLoaded = true;

    LateLoad();

    HookEvents(g_bCvar_Enabled);
}

/****************************************************************************************************/

public void Event_ConVarChanged(Handle convar, const char[] sOldValue, const char[] sNewValue)
{
    GetCvars();

    HookEvents(g_bCvar_Enabled);
}

/****************************************************************************************************/

public void GetCvars()
{
    g_bCvar_Enabled = g_hCvar_Enabled.BoolValue;
    g_fCvar_ZAxis = g_hCvar_ZAxis.FloatValue;
    g_fVPos[2] = g_fCvar_ZAxis;
    g_iCvar_FadeDistance = g_hCvar_FadeDistance.IntValue;
    FormatEx(g_sCvar_FadeDistance, sizeof(g_sCvar_FadeDistance), "%i", g_iCvar_FadeDistance);
    g_bCvar_Sight = g_hCvar_Sight.BoolValue;
    g_fCvar_AttackDelay = g_hCvar_AttackDelay.FloatValue;
    g_bCvar_AttackDelay = (g_fCvar_AttackDelay > 0.0);
    g_bCvar_AliveShow = g_hCvar_AliveShow.BoolValue;
    g_hCvar_AliveModel.GetString(g_sCvar_AliveModel, sizeof(g_sCvar_AliveModel));
    TrimString(g_sCvar_AliveModel);
    PrecacheModel(g_sCvar_AliveModel, true);
    g_iCvar_AliveAlpha = g_hCvar_AliveAlpha.IntValue;
    FormatEx(g_sCvar_AliveAlpha, sizeof(g_sCvar_AliveAlpha), "%i", g_iCvar_AliveAlpha);
    g_fCvar_AliveScale = g_hCvar_AliveScale.FloatValue;
    FormatEx(g_sCvar_AliveScale, sizeof(g_sCvar_AliveScale), "%.2f", g_fCvar_AliveScale);
    g_bCvar_DeadShow = g_hCvar_DeadShow.BoolValue;
    g_hCvar_DeadModel.GetString(g_sCvar_DeadModel, sizeof(g_sCvar_DeadModel));
    TrimString(g_sCvar_DeadModel);
    PrecacheModel(g_sCvar_DeadModel, true);
    g_iCvar_DeadAlpha = g_hCvar_DeadAlpha.IntValue;
    FormatEx(g_sCvar_DeadAlpha, sizeof(g_sCvar_DeadAlpha), "%i", g_iCvar_DeadAlpha);
    g_fCvar_DeadScale = g_hCvar_DeadScale.FloatValue;
    FormatEx(g_sCvar_DeadScale, sizeof(g_sCvar_DeadScale), "%.2f", g_fCvar_DeadScale);
    g_hCvar_DeadColor.GetString(g_sCvar_DeadColor, sizeof(g_sCvar_DeadColor));
    TrimString(g_sCvar_DeadColor);
    g_iCvar_Team = g_hCvar_Team.IntValue;
}

/****************************************************************************************************/

public void LateLoad()
{
    for (int client = 1; client <= MaxClients; client++)
    {
        if (IsPlayerSpecialInfected(client))
            TankSprite(client);
    }
}

/****************************************************************************************************/

public void OnClientDisconnect(int client)
{
    if (!g_bConfigLoaded)
        return;

    gc_iTankSpriteRef[client] = INVALID_ENT_REFERENCE;

    for (int target = 1; target <= MaxClients; target++)
    {
        gc_bVisible[target][client] = false;
        gc_fLastAttack[target][client] = 0.0;
    }
}

/****************************************************************************************************/

public void OnEntityDestroyed(int entity)
{
    if (!g_bConfigLoaded)
        return;

    if (!IsValidEntityIndex(entity))
        return;

    ge_bInvalidTrace[entity] = false;
    ge_iOwner[entity] = 0;
}

/****************************************************************************************************/

public void OnEntityCreated(int entity, const char[] classname)
{
    if (!g_bConfigLoaded)
        return;

    if (!IsValidEntityIndex(entity))
        return;

    switch (classname[0])
    {
        case 't':
        {
            if (StrEqual(classname, CLASSNAME_TANK_ROCK))
                ge_bInvalidTrace[entity] = true;
        }
    }
}

/****************************************************************************************************/

public void HookEvents(bool hook)
{
    if (hook && !g_bEventsHooked)
    {
        g_bEventsHooked = true;

        HookEvent("player_hurt", Event_PlayerHurt);

        return;
    }

    if (!hook && g_bEventsHooked)
    {
        g_bEventsHooked = false;

        UnhookEvent("player_hurt", Event_PlayerHurt);

        return;
    }
}

/****************************************************************************************************/


public void OnClientPutInServer(int client) {
    if(GetClientTeam(client) == TEAM_INFECTED) {
        //If all specials turned off and not tank; ignore.
        if(!g_hCvar_AllSpecials.BoolValue && GetZombieClass(client) != g_iTankClass) return;
        TankSprite(client);
    }
}

/****************************************************************************************************/

public void Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast) {
    int tank = GetClientOfUserId(event.GetInt("userid"));
    if (IsPlayerSpecialInfected(tank)) {
        TankSprite(tank);
        if(g_bCvar_AttackDelay) {
            int attacker = GetClientOfUserId(event.GetInt("attacker"));
            if (IsValidClient(attacker) && GetClientTeam(attacker) != TEAM_SURVIVOR)
                gc_fLastAttack[tank][attacker] = GetGameTime();
        }
    }
}

/****************************************************************************************************/

public Action TimerKill(Handle timer)
{
    if (!g_bConfigLoaded)
        return Plugin_Continue;

    for (int client = 1; client <= MaxClients; client++)
    {
        if (gc_iTankSpriteRef[client] != INVALID_ENT_REFERENCE && !IsPlayerSpecialInfected(client)) {
            int entity = EntRefToEntIndex(gc_iTankSpriteRef[client]);

            if (entity != INVALID_ENT_REFERENCE)
                AcceptEntityInput(entity, "Kill");

            gc_iTankSpriteRef[client] = INVALID_ENT_REFERENCE;

            for (int client2 = 1; client2 <= MaxClients; client2++)
            {
                gc_bVisible[client][client2] = false;
                gc_fLastAttack[client][client2] = 0.0;
            }
        }
    }

    return Plugin_Continue;
}

/****************************************************************************************************/

public Action TimerVisible(Handle timer)
{
    if (!g_bConfigLoaded)
        return Plugin_Continue;

    if (!g_bCvar_Enabled)
        return Plugin_Continue;

    for (int target = 1; target <= MaxClients; target++)
    {
        if (gc_iTankSpriteRef[target] == INVALID_ENT_REFERENCE)
            continue;

        if (!IsClientConnected(target))
            continue;

        for (int client = 1; client <= MaxClients; client++)
        {
            if (!IsClientConnected(client))
                continue;

            if (IsFakeClient(client))
                continue;

            if (!(GetClientTeamFlag(client) & g_iCvar_Team))
            {
                gc_bVisible[target][client] = false;
                continue;
            }

            if (g_bCvar_AttackDelay || g_bCvar_Sight)
            {
                if (GetClientTeam(client) == TEAM_SURVIVOR || GetClientTeam(client) == TEAM_HOLDOUT)
                {
                    if (g_bCvar_AttackDelay && (GetGameTime() - gc_fLastAttack[target][client] > g_fCvar_AttackDelay))
                    {
                        gc_bVisible[target][client] = false;
                        continue;
                    }

                    if (g_bCvar_Sight && !IsVisibleTo(client, target))
                    {
                        gc_bVisible[target][client] = false;
                        continue;
                    }
                }
            }

            gc_bVisible[target][client] = true;
        }
    }

    return Plugin_Continue;
}

/****************************************************************************************************/

public Action TimerRender(Handle timer)
{
    if (!g_bConfigLoaded)
        return Plugin_Continue;

    if (!g_bCvar_Enabled)
        return Plugin_Continue;

    for (int target = 1; target <= MaxClients; target++)
    {
        if (!IsPlayerSpecialInfected(target))
            continue;

        TankSprite(target);
    }

    return Plugin_Continue;
}

/****************************************************************************************************/

public void TankSprite(int client)
{
    int entity = INVALID_ENT_REFERENCE;

    if (gc_iTankSpriteRef[client] != INVALID_ENT_REFERENCE)
        entity = EntRefToEntIndex(gc_iTankSpriteRef[client]);

    if (entity == INVALID_ENT_REFERENCE)
    {
        entity = CreateEntityByName(CLASSNAME_ENV_SPRITE);
        DispatchKeyValue(entity, "targetname", "l4d_tank_hp_sprite");
        DispatchKeyValue(entity, "spawnflags", "1");
        DispatchKeyValue(entity, "fademindist", g_sCvar_FadeDistance);
        SetEntProp(entity, Prop_Data, "m_iHammerID", -1);
        SDKHook(entity, SDKHook_SetTransmit, OnSetTransmit);
        ge_iOwner[entity] = client;
        gc_iTankSpriteRef[client] =  EntIndexToEntRef(entity);
    }

    if (IsPlayerIncapacitated(client))
    {
        if (g_bCvar_DeadShow)
        {
            DispatchKeyValue(entity, "model", g_sCvar_DeadModel);
            DispatchKeyValue(entity, "rendercolor", g_sCvar_DeadColor);
            DispatchKeyValue(entity, "renderamt", g_sCvar_DeadAlpha); // If renderamt goes before rendercolor, it doesn't render
            DispatchKeyValue(entity, "scale", g_sCvar_DeadScale);
            DispatchSpawn(entity);
            SetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity", client);
            SetVariantString("!activator");
            AcceptEntityInput(entity, "SetParent", client);
            AcceptEntityInput(entity, "ShowSprite");
            TeleportEntity(entity, g_fVPos, NULL_VECTOR, NULL_VECTOR);
        }

        return;
    }

    if (!g_bCvar_AliveShow)
    {
        AcceptEntityInput(entity, "HideSprite");
        return;
    }

    int maxHealth = GetEntProp(client, Prop_Data, "m_iMaxHealth");
    int currentHealth = GetClientHealth(client);

    float percentageHealth;
    if (maxHealth == 0)
        percentageHealth = 0.0;
    else
        percentageHealth = (float(currentHealth) / float(maxHealth));

    bool halfHealth = (percentageHealth <= 0.5);

    char sRenderColor[12];
    Format(sRenderColor, sizeof(sRenderColor), "%i %i 0", halfHealth ? 255 : RoundFloat(255.0 * ((1.0 - percentageHealth) * 2)), halfHealth ? RoundFloat(255.0 * (percentageHealth) * 2) : 255);

    DispatchKeyValue(entity, "model", g_sCvar_AliveModel);
    DispatchKeyValue(entity, "rendercolor", sRenderColor);
    DispatchKeyValue(entity, "renderamt", g_sCvar_AliveAlpha); // If renderamt goes before rendercolor, it doesn't render
    DispatchKeyValue(entity, "scale", g_sCvar_AliveScale);
    DispatchSpawn(entity);
    SetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity", client);
    SetVariantString("!activator");
    AcceptEntityInput(entity, "SetParent", client);
    AcceptEntityInput(entity, "ShowSprite");
    TeleportEntity(entity, g_fVPos, NULL_VECTOR, NULL_VECTOR);
}

/****************************************************************************************************/

public Action OnSetTransmit(int entity, int client)
{
    int owner = ge_iOwner[entity];

    if (owner == client)
        return Plugin_Handled;

    if (gc_bVisible[owner][client])
        return Plugin_Continue;

    return Plugin_Handled;
}

/****************************************************************************************************/

bool IsVisibleTo(int client, int target)
{
    float vClientPos[3];
    float vEntityPos[3];
    float vLookAt[3];
    float vAngles[3];

    GetClientEyePosition(client, vClientPos);
    GetClientEyePosition(target, vEntityPos);
    MakeVectorFromPoints(vClientPos, vEntityPos, vLookAt);
    GetVectorAngles(vLookAt, vAngles);

    Handle trace = TR_TraceRayFilterEx(vClientPos, vAngles, MASK_PLAYERSOLID, RayType_Infinite, TraceFilter, target);

    bool isVisible;

    if (TR_DidHit(trace))
    {
        isVisible = (TR_GetEntityIndex(trace) == target);

        if (!isVisible)
        {
            vEntityPos[2] -= 62.0; // results the same as GetClientAbsOrigin

            delete trace;
            trace = TR_TraceHullFilterEx(vClientPos, vEntityPos, g_fVPlayerMins, g_fVPlayerMaxs, MASK_PLAYERSOLID, TraceFilter, target);

            if (TR_DidHit(trace))
                isVisible = (TR_GetEntityIndex(trace) == target);
        }
    }

    delete trace;

    return isVisible;
}

/****************************************************************************************************/

public bool TraceFilter(int entity, int contentsMask, int client)
{
    if (entity == client)
        return true;

    if (IsValidClientIndex(entity))
        return false;

    return ge_bInvalidTrace[entity] ? false : true;
}

/****************************************************************************************************/

public Action CmdPrintCvars(int client, int args)
{
    PrintToConsole(client, "");
    PrintToConsole(client, "======================================================================");
    PrintToConsole(client, "");
    PrintToConsole(client, "----------------- Plugin Cvars (l4d_tank_hp_sprite) ------------------");
    PrintToConsole(client, "");
    PrintToConsole(client, "l4d_tank_hp_sprite_version : %s", PLUGIN_VERSION);
    PrintToConsole(client, "l4d_tank_hp_sprite_enable : %b (%s)", g_bCvar_Enabled, g_bCvar_Enabled ? "true" : "false");
    PrintToConsole(client, "l4d_tank_hp_sprite_z_axis : %.2f", g_fCvar_ZAxis);
    PrintToConsole(client, "l4d_tank_hp_sprite_fade_distance : %i", g_iCvar_FadeDistance);
    PrintToConsole(client, "l4d_tank_hp_sprite_sight : %b (%s)", g_bCvar_Sight, g_bCvar_Sight ? "true" : "false");
    PrintToConsole(client, "l4d_tank_hp_sprite_attack_delay : %.2f (%s)", g_fCvar_AttackDelay, g_bCvar_AttackDelay ? "true" : "false");
    PrintToConsole(client, "l4d_tank_hp_sprite_alive_show : %b (%s)", g_bCvar_AliveShow, g_bCvar_AliveShow ? "true" : "false");
    PrintToConsole(client, "l4d_tank_hp_sprite_alive_model : \"%s\"", g_sCvar_AliveModel);
    PrintToConsole(client, "l4d_tank_hp_sprite_alive_alpha : %i", g_iCvar_AliveAlpha);
    PrintToConsole(client, "l4d_tank_hp_sprite_alive_scale : %.2f", g_fCvar_AliveScale);
    PrintToConsole(client, "l4d_tank_hp_sprite_dead_show : %b (%s)", g_bCvar_DeadShow, g_bCvar_DeadShow ? "true" : "false");
    PrintToConsole(client, "l4d_tank_hp_sprite_dead_model : \"%s\"", g_sCvar_DeadModel);
    PrintToConsole(client, "l4d_tank_hp_sprite_dead_alpha : %i", g_iCvar_DeadAlpha);
    PrintToConsole(client, "l4d_tank_hp_sprite_dead_scale : %.2f", g_fCvar_DeadScale);
    PrintToConsole(client, "l4d_tank_hp_sprite_dead_color : \"%s\"", g_sCvar_DeadColor);
    PrintToConsole(client, "l4d_tank_hp_sprite_team : %i", g_iCvar_Team);
    PrintToConsole(client, "");
    PrintToConsole(client, "======================================================================");
    PrintToConsole(client, "");

    return Plugin_Handled;
}

// ====================================================================================================
// Helpers
// ====================================================================================================
/**
 * Validates if is a valid client index.
 *
 * @param client        Client index.
 * @return              True if client index is valid, false otherwise.
 */
bool IsValidClientIndex(int client)
{
    return (1 <= client <= MaxClients);
}

/****************************************************************************************************/

/**
 * Validates if is a valid client.
 *
 * @param client        Client index.
 * @return              True if client index is valid and client is in game, false otherwise.
 */
bool IsValidClient(int client)
{
    return (IsValidClientIndex(client) && IsClientInGame(client));
}

/****************************************************************************************************/

/**
 * Validates if is a valid entity index (between MaxClients+1 and 2048).
 *
 * @param entity        Entity index.
 * @return              True if entity index is valid, false otherwise.
 */
bool IsValidEntityIndex(int entity)
{
    return (MaxClients+1 <= entity <= GetMaxEntities());
}

/****************************************************************************************************/

/**
 * Gets the client L4D1/L4D2 zombie class id.
 *
 * @param client        Client index.
 * @return L4D1         1=SMOKER, 2=BOOMER, 3=HUNTER, 4=WITCH, 5=TANK, 6=NOT INFECTED
 * @return L4D2         1=SMOKER, 2=BOOMER, 3=HUNTER, 4=SPITTER, 5=JOCKEY, 6=CHARGER, 7=WITCH, 8=TANK, 9=NOT INFECTED
 */
int GetZombieClass(int client)
{
    return (GetEntProp(client, Prop_Send, "m_zombieClass"));
}

/****************************************************************************************************/

/**
 * Returns is a player is in ghost state.
 *
 * @param client        Client index.
 * @return              True if client is in ghost state, false otherwise.
 */
bool IsPlayerGhost(int client)
{
    return (GetEntProp(client, Prop_Send, "m_isGhost") == 1);
}

/****************************************************************************************************/

/**
 * Validates if the client is incapacitated.
 *
 * @param client        Client index.
 * @return              True if the client is incapacitated, false otherwise.
 */
bool IsPlayerIncapacitated(int client)
{
    return (GetEntProp(client, Prop_Send, "m_isIncapacitated") == 1);
}

/****************************************************************************************************/

/**
 * Returns if the client is a valid tank.
 *
 * @param client        Client index.
 * @return              True if client is a tank, false otherwise.
 */
bool IsPlayerSpecialInfected(int client) {
    bool isValid = IsValidClient(client) && GetClientTeam(client) == TEAM_INFECTED && IsPlayerAlive(client) && !IsPlayerGhost(client);
    if(!g_hCvar_AllSpecials.BoolValue && GetZombieClass(client) != g_iTankClass)
        return false;
    else
        return isValid;
}

/****************************************************************************************************/

/**
 * Returns the team flag from a client.
 *
 * @param client        Client index.
 * @return              Client team flag.
 */
int GetClientTeamFlag(int client)
{
    switch (GetClientTeam(client))
    {
        case TEAM_SURVIVOR:
            return FLAG_TEAM_SURVIVOR;
        case TEAM_INFECTED:
            return FLAG_TEAM_INFECTED;
        case TEAM_SPECTATOR:
            return FLAG_TEAM_SPECTATOR;
        case TEAM_HOLDOUT:
            return FLAG_TEAM_HOLDOUT;
        default:
            return FLAG_TEAM_NONE;
    }
}