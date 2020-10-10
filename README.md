# sourcemod-plugins
All my sourcemod plugins... shitty probably

## Plugin List
* [csgo-knifehp](#csgo-knifehp)
* [l4d2-manual-director](#l4d2-manual-director)
* [l4d2-info-cmd](#l4d2-info-cmd)
* [AutoWarpBot](#AutoWarpBot)
* [200IQBots_FlyYouFools](#200IQBots_FlyYouFools)
* [BetterWitchAvoidance](#BetterWitchAvoidance)
* [L4D2FFKickProtection](#L4D2FFKickProtection)
* [l4d2_ff_test](#l4d2_ff_test)
* [CSGOTroll](#CSGOTroll)
* [l4d2_avoid_minigun](#l4d2_avoid_minigun)
* [l4d2_ai_minigun](#l4d2_ai_minigun)
* [L4D2Tools](#L4D2Tools)

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
A group of misc tools for l4d2. Including: Notify on lasers use, and a finale timer (gauntlets or all finales), and who trigger a car alarm in the chat.
* **Convars:**
   * `sm_laser_use_notice <1/0>` - Enable notification of a laser box being used
   * `sm_time_finale <0/1/2>` - Record the time it takes to complete finale. 0 -> OFF, 1 -> Gauntlets Only, 2 -> All finales
   
### 200IQBots_FlyYouFools
Updated version of ConnerRia's plugin. Improves bots avoidance of tanks. Change from original is updated source syntax, some optimizations/cleanup, and fixes such as bots avoiding tank that has not been activated, or not escaping in vehicle due to presence of tank.
Latest version now has support for multiple tanks, the bots might not avoid them as effectively as they would with one tank but they still try their best.
* **Convars:**
   * `FlyYouFools_Version` - Prints the version of plugin

### BetterWitchAvoidance
Inspired by the 200IQBots_FlyYouFools. Bots avoid witch if its over 40% anger when close, or a little bigger range at 60% or more.

### L4D2FFKickProtection
Simple plugin that prevents a player that is being vote-kicked from doing any ff damage to teammates. 
* **Convars:**
  * `sm_votekick_force_threshold <#>` - The threshold of damage where the offending player is just immediately kicked. 0 -> Any attempted damage, -1 -> No auto kick.

### l4d2_ff_test
More of a joke plugin, it will prevent a player from picking up a m60 if their friendly fire count or damage is over a certain threshold (Hardcoded as 5 and 35 respectively)

It also can modify the FF damage done to the victim, and redirect on a scale back to the attacker
* **Convars:**
  * `sm_redirect_ff_scale <#.#>` - The redirected damage back to attacker. 0.0 -> OFF | 1 -> All damage. Minimum 0.0
  * `sm_victim_ff_scale <0.0-1.0>` - This is multiplied by the damage the victim will receive. 0 -> No damage, 1 -> All damage
* **Commands:**
  * `sm_view_ff` - View the ff damage and count of all players

### CSGOTroll
Another joke plugin, with it configured, a victim will have a % chance their shots just fail. This can be for the AWP or all weapons at least for now.
* **Convars:**
  * `troll_enable <0/1>` - Enable troll. 0 -> OFF, 1 -> Shots
  * `troll_shot_fail_percentage <0.0-1.0>` - percentage float (0.0 to 1.0) chance that victims' shots fail
  * `troll_targets <ids>` - comma separated list of steamid64 targets (ex: STEAM_0:0:75141700)
  * `troll_shot_mode <0/1>` - 0 -> ALL Weapons, 1 -> AWP

### l4d2_avoid_minigun
Makes the bots avoid standing in front of or on top of the player that is using a minigun. It checks every 2.0 seconds if they are in the way, then forces them to move to behind you.  There is no configuration, all automatic.

### l4d2_ai_minigun
Allows you to spawn a holdout type bot. This bot will spawn with a minigun, like louis in the passing. Supports all 8 characters. 
Technically it is louis using minigun with a model change, but it works fine.

**Notes:** Sometimes bill model fails to spawn in, and is just invisible. Also, the minigun holdout bot has to internally be Louis, so it will be louis making sounds, but whatever model specified shown. This doesn't apply for normal holdout bot.

Code modified from https://forums.alliedmods.net/showthread.php?p=1741099

* **Commands:**
  * `sm_ai_minigun <survivor name>` - Spawns an ai bot with minigun infront of wherever you are looking. Can also use numbers (0-7).
  * `sm_ai_holdout <survivor name>` - Spawns a normal ai holdout bot (no minigun), with ak47 w/ laser sight. 

### L4D2Tools
A collection of small tools: Notification of when someone picks up laser sights (only the first user, includes bots), and records time it takes for a finale or gauntlet run.

* **Convars:**
   * `sm_laser_use_notice <0/1>` - Enable notification of when a laser box was used first
   * `sm_time_finale <0/1/2>` - Record the time it takes to complete finale. 0 -> OFF, 1 -> Gauntlets Only, 2 -> All finales