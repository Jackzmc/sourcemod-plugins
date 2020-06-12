# sourcemod-plugins
All my sourcemod plugins... shitty probably

## Plugin List
* [csgo-knifehp](#csgo-knifehp)
* [l4d2-manual-director](#l4d2-manual-director)
* [l4d2-info-cmd](#l4d2-info-cmd)
* [AutoWarpBot](#AutoWarpBot)
* [200IQBots_FlyYouFools](#200IQBots_FlyYouFools)

## Descriptions
### csgo-knifehp
On knife kill, gives the player 100 HP (configurable)
* **Convars:**
   * `knifehp_enable <0/1>` - Enable regaining health on knife kill
   * `knifehp_max_health <#>` - Maximum health to set an attacker to
   * `knifehp_amount <#>` - Amount of health to give attacker
   
### l4d2-manual-director
Probably going to be posted publicly sometime. allows you to spawn specials on cursor, or via director, forcefully, bypassing limits
* **Convars:**
   * `manual_director_version|mandirector_version` - ... gets version
   * `mandirector_notify_spawn <1/0>` - Should spawning specials notify on use?
   * `mandirector_announce_level <0/1/2/3>` - Announcement types. 0 - None, 1 - Only bosses, 2 - Only specials+, 3 - Everything
   * `mandirector_enable_tank <0/1>` - Should tanks be allowed to be spawned?
   * `mandirector_enable_witch <0/1>` - Should witches be allowed to be spawned?
   * `mandirector_enable_mob <0/1>` - Should mobs be allowed to be spawned
* **Commands:**
   * `sm_spawnspecial` - Spawn a special via director
   * `sm_forcespecial` - Force spawn a special via director, bypassing spawn limits
   * `sm_forcecursor` - Force spawn a special at cursor, bypassing spawn limits
   * `sm_cursormenu` - Show the spawn menu for cursor spawning
   * `sm_specialmenu` - Show the spawn menu for director spawning
   * `sm_directormenu` (Same as sm_specialmenu for now)
   
### l4d2-info-cmd
Technically 'l4d2 game info', havent changed name. Just prints general information, used for a project
* **Commands:**
   * `sm_gameinfo`
* Example Response:
    ```
    >map,diff
    c8m2_subway,Normal
    >id,name,bot,health,status,afk,throwSlot,kitSlot,pillSlot,modelName
    1,Jackz,0,80,alive,0,,first_aid_kit,,Bill
    3,Zoey,1,75,alive,0,,first_aid_kit,,Zoey
    4,Francis,1,76,alive,0,,,,Francis
    5,Louis,1,90,alive,0,,first_aid_kit,,Louis
    ```
    
### AutoWarpBot
Simple l4d2 plugin that will auto teleport everyone to checkpoint once all real players have reached the saferoom

### L4D2Tools
A group of misc tools for l4d2. Including: Notify on lasers use, and a finale timer (gauntlets or all finales)
* **Convars:**
   * `sm_laser_use_notice <1/0>` - Enable notification of a laser box being used
   * `sm_time_finale <0/1/2>` - Record the time it takes to complete finale. 0 -> OFF, 1 -> Gauntlets Only, 2 -> All finales
   
### 200IQBots_FlyYouFools
Updated version of ConnerRia's plugin. Improves bots avoidance of tanks. Change from original is updated source syntax, some optimizations/cleanup, and fixes such as bots avoiding tank that has not been activated, or not escaping in vehicle due to presence of tank.
* **Convars:**
   * `FlyYouFools_Version` - Prints the version of plugin

### BetterWitchAvoidance
Inspired by the 200IQBots_FlyYouFools. Bots avoid witch if its over 40% anger when close, or a little bigger range at 60% or more.