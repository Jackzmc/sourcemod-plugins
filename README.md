# sourcemod-plugins
All my sourcemod plugins... shitty probably

## Plugin List

### Created by Me
* [csgo-knifehp](#csgo-knifehp)
* [l4d2-manual-director](#l4d2-manual-director)
* [l4d2-info-cmd](#l4d2-info-cmd)
* [AutoWarpBot](#AutoWarpBot)
* [L4D2FFKickProtection](#L4D2FFKickProtection)
* [l4d2_ff_test](#l4d2_ff_test)
* [CSGOTroll](#CSGOTroll)
* [l4d2_avoid_minigun](#l4d2_avoid_minigun)
* [l4d2_ai_minigun](#l4d2_ai_minigun)
* [L4D2Tools](#L4D2Tools)
* [l4d2_swarm](#l4d2_swarm)
* [l4d2_feedthetrolls](#l4d2_feedthetrolls)
* [l4d2_autobotcrown](#l4d2_autobotcrown)
* [l4d2_extraplayeritems](#l4d2_extraplayeritems)
* [l4d2_population_control](#l4d2_population_control)

### Modified Others
* [200IQBots_FlyYouFools](#200IQBots_FlyYouFools)
* [l4d_survivor_identity_fix](#l4d_survivor_identity_fix)
* [BetterWitchAvoidance](#BetterWitchAvoidance)


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
   * `sm_ff_notice <0/1/2>` - Notify players if a FF occurs. 0 -> Disabled, 1 -> In chat, 2 -> In Hint text
   
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
Spawn the holdout bots used in the passing. This supports all 8 characters, including with the minigun. They can spawn with any weapon or default to ak47.

**Notes:** 
* The minigun holdout bot has to internally be Louis, so it will be Louis making sounds, but whatever model specified shown. This doesn't apply for normal holdout bot.
* \<survivor name> can be "bill" or their numeric id (4). 

Code modified from https://forums.alliedmods.net/showthread.php?p=1741099

* **Commands:**
  * `sm_ai_minigun <survivor name>` - Spawns an ai bot with minigun infront of wherever you are looking. Can also use numbers (0-7).
  * `sm_ai_holdout <survivor name> [wpn]` - Spawns a normal ai holdout bot (no minigun), with any weapon w/ laser sight (default is ak). 
  * `sm_ai_remove_far` - Removes any holdout or minigun bots that are 750 units or more from any player.

### L4D2Tools
A collection of small tools: 
  * Notification of when someone picks up laser sights (only the first user, includes bots), 
  * Record time it takes for a finale or gauntlet run to be completed.
  * Record the amount of friendly fire damage done
  * Set the survivor models of any survivor to another correctly.
  * Alert when a player activates a car alarm
  * Automatically give back any dropped melee weapons once no longer idle (if not equipped by another player)

* **Convars:**
   * `sm_laser_use_notice <0/1>` - Enable notification of when a laser box was used first
   * `sm_time_finale <0/1/2>` - Record the time it takes to complete finale. 0 -> OFF, 1 -> Gauntlets Only, 2 -> All finales
   * `sm_ff_notice <0/1/2>` - Should we record FF damages? 0: OFF, 1: To chat, 2: To HUD text.
* **Commands:**
  * `sm_model <player> <character>` - Sets the survivor model of the target player(s). 'character' is name or ID of character.

### l4d2_swarm
This plugin is used to counter trolls and otherwise bad players. It simply uses the new script function RushVictim() to make all zombies in X radius attack Y target. It's that simple. 

This really only affects wandering zombies, mobs and panic events, but it may work slightly when bile or pipes are thrown. It does not and can't change the targets of zombies.

* **Convars:**
  * `sm_swarm_default_range <20-Infinity>` - The default range for commands & menus. Defaults to 7,500
* **Commands:**
  * `sm_swarm [player] [range]` - Swarm a player, or random if none."
    * Aliases: `sm_rush`
  * `sm_rushmenu` - Opens a menu to quickly rush any player. Can be bound to a key to quickly rush as well
    * Aliases: `sm_rmenu`
  * `sm_swarmtoggle <player> [range]` - Will continuously run the swarm method on the player at the range. Use the command again or type "disable" for player to disable. Switching players will not disable, just switches target.
    * Aliases: `sm_rushtoggle`, `sm_rt`
  * `sm_rushtogglemenu` - Will open a menu to quickly select a player to continuously rush.
    * Aliases: `sm_rtmenu`

### l4d2_feedthetrolls
This plugin allows you to enact certain troll modes on any player, some are subtle some are less so. Either way, it works great to deal with a rusher, an asshole or even your friends.

Troll Modes: (updated 1/2/2021)
1. **SlowSpeed** (0.8 < 1.0 base) - Slows down a user
2. **HigherGravity** (1.3 > 1.0) - Adds more gravity to a user
3. **HalfPrimary** - Sets user's primary reserve ammo in half
4. **UziRules** - Picking up a weapon only gives them a UZI
5. **PrimaryDisable** - Cannot pickup primary weapons at all
6. **SlowDrain** - Health slowly drains every few seconds (controlled by cvar)
7. **Clusmy** - Randomly drops any melee weapon, great with a swarm
8. **IcantSpellNoMore** - Garble their chat messages
9. **CameTooEarly** - (not implemented) A chance that when shooting, they empty a whole clip at once
10. **KillMeSoftly** - Makes the player eat or waste their pills
11. **ThrowItAll** - Makes a player throw all their items at any nearby players. Runs on the interval set by sm_ftt_throw_interval.
12. **GunJam** - On reload, small chance their gun gets jammed - Can't reload.
13. **NoPickup** - Prevents a player from picking up ANY (new) item. Use ThrowItAll to make them drop
14.	**Swarm** - Swarms a player with zombies. Requires my [swarm plugin](#l4d2_swarm)

* **Convars:**
  * `sm_ftt_victims` - A comma separated list of troll targets. Unused while new version is being implemented
  * `sm_ftt_throw_interval` - For troll mode 'ThrowItAll' (#11), how often players will re-throw all their items. 0 to disable
  * `sm_ftt_autopunish_mode` - (Not used, WIP) Sets the modes that auto punish will activate for. 1 -> Early crescendo activations
* **Commands:**
  * `sm_fta <player(s)> <mode #>` - Applies a mode to a set of users. See list above
  * `sm_fta` - No arguments: Shows a menu, choose player, mode, and modifiers all in one.
  * `sm_ftr <player(s)>` - Removes & deactivates all trolls.
  * `sm_ftl` - Lists all players that have a mode applied.

### l4d2_autobotcrown
Makes any suitable bot (> 40 hp, has shotgun) automatically crown a witch. Supports multiple bots and witches, but only one bot can crown one witch at a time. Plugin is obviously disabled in realism, and is really on suitable for coop or versus. Even works with idle players.

* **Convars:**
  * `l4d2_autocrown_allowed_difficulty <default: 7>` - The difficulties the plugin is active on. 1=Easy, 2=Normal 4=Advanced 8=Expert. Add numbers together.
  * `l4d2_autocrown_modes_tog <default: 7>` - (Not implemented) - Turn on the plugin in these game modes. 0=All, 1=Coop, 2=Survival, 4=Versus, 8=Scavenge. Add numbers together

### l4d2_extraplayeritems
A tool that can automatically provide items for > 5 player co-op games (or versus). When the second saferoom is entered, any time someone heals they will be given an extra kit afterwards until all extra kits are consumed. Extra kits are the same amount of extra palyers. When the level transitions, any players who do not have kits will receive one, and if there is still extra kits, on heal they will be given still.

Also features a part that will increase the item count on any item, kit, or weapon spawns at a random percentage that increases based on player count. This is controlled by the `l4d2_extraitem_chance` cvar.

* **Convars:**
  * `l4d2_extraitem_chance` - The base chance (multiplied by player count) of an extra item being spawned. Default: 0.056

### l4d_survivor_identity_fix
A fork of Merudo, Shadowysn's identity fix plugin that adds support for other plugins to update the model cache. This is used by [L4D2Tools](#L4D2Tools) to update the identity when someone changes their model with sm_model. It also will clear the memory of model when a player disconnects entirely or on a new map.

### l4d2_population_control
Allows you to set the chances that a common spawns as a certain uncommon. The order of the cvars is the order the percentages are ran
* **Convars:**
  * `l4d2_population_chance <0.0-1.0>` Default: 1.0, the chance that the code runs on a spawn (basically if 0.0, none of the % chances will run for all types)
  * `l4d2_population_clowns <0.0-1.0>` The chance that on a common spawn that the special will be a clown.
  * `l4d2_population_mud    <0.0-1.0>` The chance that on a common spawn that the special will be a mud common.
  * `l4d2_population_ceda   <0.0-1.0>` The chance that on a common spawn that the special will be a ceda common.
  * `l4d2_population_worker <0.0-1.0>` The chance that on a common spawn that the special will be a worker common.
  * `l4d2_population_riot   <0.0-1.0>` The chance that on a common spawn that the special will be a riot common.
  * `l4d2_population_jimmy  <0.0-1.0>` The chance that on a common spawn that the special will be a jimmy common
* **Commands:**
  * `sm_populations` or `sm_population_list` - Lists all the cvar values