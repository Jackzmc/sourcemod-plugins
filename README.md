# sourcemod-plugins
This is a collection of all the sourcemod plugins I've created, most are just used for my own servers and some for very specific needs.


Not always the latest versions, if you have any interest with plugins I can make sure to upload the latest.


Useful things:
1. Netprop viewer https://jackz.me/netprops/l4d2

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
* [l4d2_extrafinaletanks](#l4d2_extrafinaletanks)
* [globalbans](#globalbans)
* [l4d2_rollback](#l4d2_rollback)
* [l4d2_autorestart](#l4d2_autorestart)
* [l4d2_TKStopper](#l4d2_TKStopper)
* [l4d2_crescendo_control](#l4d2_crescendo_control)

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
   * `sm_spawnspecial <special> [amount]` - Spawn a special via director
   * `sm_forcespecial <special> [amount]` - Force spawn a special via director, bypassing spawn limits
   * `sm_forcecursor  <special> [amount]` - Force spawn a special at cursor, bypassing spawn limits
   * `sm_cursormenu` - Show the spawn menu for cursor spawning
   * `sm_specialmenu` - Show the spawn menu for director spawning
   * `sm_directormenu` (Same as sm_specialmenu for now)
   
### l4d2-info-cmd
Technically 'l4d2 game info', haven't changed name. Just prints general information, used for a project
* **Commands:**
   * `sm_gameinfo`
* Example Response:
    ```
    >map,diff,mode,tempoState,totalSeconds
    c1m1_hotel,1,coop,3,1622
    >id,name,bot,health,status,throwSlot,kitSlot,pillSlot,survivorType,velocity,primaryWpn,secondaryWpn
    1,Jackz,0,80,alive,0,,first_aid_kit,,Bill,0,,pistol
    3,Zoey,1,75,alive,0,,first_aid_kit,,Zoey,0,,pistol
    4,Francis,1,76,alive,0,,,,Francis,0,,pistol
    5,Louis,1,90,alive,0,,first_aid_kit,,Louis,0,,pistol
    ```
    
### AutoWarpBot
Simple l4d2 plugin that will auto teleport everyone to checkpoint once all real players have reached the saferoom

   
### 200IQBots_FlyYouFools
Updated version of ConnerRia's plugin. Improves bots avoidance of tanks. Change from original is updated sourcepawn syntax, some optimizations/cleanup, and fixes such as bots avoiding tank that has not been activated, or not escaping in vehicle due to presence of tank.
Latest version now has support for multiple tanks, the bots might not avoid them as effectively as they would with one tank but they still try their best.
* **Convars:**
   * `FlyYouFools_Version` - Prints the version of plugin

### BetterWitchAvoidance
Inspired by the 200IQBots_FlyYouFools. Bots avoid witch if its over 40% anger when close, or a little bigger range at 60% or more. Not recommended to use, normal behavior seems fine.

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
  * Set the survivor models of any survivor with updating [l4d_survivor_identity_fix](#l4d_survivor_identity_fix)
  * Automatically gives melee weapons that an idle bot dropped once no longer idle
  * Automatically make players go idle when ping spikes
  * Slowly kill any bots attacking survivor bot's blind spots (Fixes bots stuck taking damage and brain dead)

* **Convars:**
   * `sm_laser_use_notice <0/1>` - Enable notification of when a laser box was used first
   * `sm_time_finale <0/1/2>` - Record the time it takes to complete finale. 0 -> OFF, 1 -> Gauntlets Only, 2 -> All finales
   * `sm_ff_notice <0/1/2>` - Should we record FF damages? 0: OFF, 1: To chat, 2: To HUD text.
   * `sm_autoidle_ping_max <30.0...>` - "The highest ping a player can have until they will automatically go idle.\n0=OFF, Min is 30
* **Commands:**
  * `sm_model <player> <character>` - Sets the survivor model of the target player(s). 'character' is name or ID of character.
  * `sm_surv <player> <character>` - Sets the m_survivorCharacter prop only of the target player(s). 'character' is name or ID of character.

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

Troll Modes: (updated 4/20/2021)

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
14. **Swarm** - Swarms a player with zombies. Requires my [swarm plugin](#l4d2_swarm)
15. **Honk** – Replaces player's chat messages with honk
16. **Special Magnet** – Attracts ALL specials to the closest alive trolled target with this troll enabled
17. **Tank Magnet** – Attracts ALL tanks to the closest alive trolled target with this troll enabled
18. **No Shove** – Prevents player from shoving at a % chance
19. **Damage Boost** – Will make the player take 2x more damage than normal
20. **Temp Quick Drain** – Will make a player’s temp health drain very quickly
21. **Vomit Player** – Instantly vomits the player
22. **Vocalize Gag** - Prevents player from vocalizing entirely

* **Convars:**
  * `sm_ftt_victims` - A comma separated list of troll targets. Unused while new version is being implemented
  * `sm_ftt_throw_interval` - For troll mode 'ThrowItAll' (#11), how often players will re-throw all their items. 0 to disable
  * `sm_ftt_autopunish_mode <#>` - (Not used, WIP) Sets the modes that auto punish will activate for. 1 -> Early crescendo activations
  * `sm_ftt_autopunish_action <#>` - Which actions will autopunish activate? Add bits together. 0=None, 1=TankMagnet 2=SpecialMagnet 4=Swarm 8=VomitPlayer
  * `sm_ftt_autopunish_expires <0...>` - How many minutes (in gameticks) until autopunish trolls are removed. 0 for never.
  * `sm_ftt_magnet_chance <0.0 - 1.0>` - % of the time that the magnet will work on a player."
  * `sm_ftt_shove_fail_chance <0.0 - 1.0>` - The % chance that a shove fails
* **Commands:**
  * `sm_fta <player(s)> <mode #>` - Applies a mode to a set of users. See list above
  * `sm_fta` - No arguments: Shows a menu, choose player, mode, and modifiers all in one.
  * `sm_ftr <player(s)>` - Removes & deactivates all trolls.
  * `sm_ftl` - Lists all players that have a mode applied.
  * `sm_ftm` - Lists all troll options & their descriptions

### l4d2_autobotcrown
Makes any suitable bot (> 40 hp, has shotgun) automatically crown a witch. Supports multiple bots and witches, but only one bot can crown one witch at a time. Plugin is obviously disabled in realism, and is really on suitable for coop or versus. Even works with idle players.

* **Convars:**
  * `l4d2_autocrown_allowed_difficulty <default: 7>` - The difficulties the plugin is active on. 1=Easy, 2=Normal 4=Advanced 8=Expert. Add numbers together.
  * `l4d2_autocrown_modes_tog <default: 7>` - (Not implemented) - Turn on the plugin in these game modes. 0=All, 1=Coop, 2=Survival, 4=Versus, 8=Scavenge. Add numbers together

### l4d2_extraplayeritems
A well rounded tool that provides extra utilities to a 5+ co-op campaign. 

Features:
* Automatically giving extra kits for each extra player in saferooms
* Increasing item count for items randomly depending on player count
* Fix same-models survivors having to fight over ammo pack usage
* Automatically lock the exit saferoom door until a threshold of players or time has passed

* **Convars:**
  * `l4d2_extraitem_chance` - The base chance (multiplied by player count) of an extra item being spawned. Default: 0.056
  * `l4d2_extraitems_kitmode` - Decides how extra kits should be added. Default is 0
    * 0 -> Overwrites previous extra kits
    * 1 -> Adds onto previous extra kits
  * `l4d2_extraitems_updateminplayers` - Should the plugin update abm's cvar min_players convar to the player count? (0 no, 1 yes)
  * `l4d2_extraitems_doorunlock_percent` - The percent of players that need to be loaded in before saferoom door is opened.
    * Default is 0.8, set to 0 to disable door locking
  * `l4d2_extraitems_doorunlock_wait` - How many seconds after to unlock saferoom door. 0 to disable timer
  * `l4d2_extraitems_doorunlock_open` - Controls when or if the door automatically opens after unlocked. Add bits together.
    * 0 = Never, 1 = When timer expires, 2 = When all players loaded in

### l4d_survivor_identity_fix
A fork of [Survivor Identity Fix plugin](https://forums.alliedmods.net/showthread.php?t=280539) that adds support for other plugins to update the model cache. This is used by [L4D2Tools](#L4D2Tools) to update the identity when someone changes their model with `sm_model`. It also will clear the memory of model when a player disconnects entirely or on a new map.

In addition, has a fix for the passing finale, and will automatically move L4D characters to L4D2 until finale starts preventing game messing up their characters.

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
  * `l4d2_population_common <#>` - The maximum amount of commons that can spawn. 
    * 0 will turn off, 
    * value > 0 will enforce the exact value
    * value < 0 will enforce z_common_limit + | value |
* **Commands:**
  * `sm_populations` or `sm_population_list` - Lists all the cvar values

### l4d2_extrafinaletanks
This plugin will automatically spawn an extra amount of tanks (determined by `l4d2_eft_count` cvar) after the second tank stage in a finale is over.
* **Convars:**
  * `l4d2_eft_count <#>` - Default is 1, determines how many tanks that are allowed to spawn in the extra tank stage
  * `l4d2_eft_chance <0.0-1.0> - Default is 0.0, determines the chance of each tank spawning in extra tank stage.
    * If the spawn fails, it will still count as a spawn, the percentage is PER tank

### globalbans
This plugin will store bans in a database and read from it on connect. This allows you to easily have bans global between servers.
It will automatically intercept any ban that calls OnBanIdentity or OnBanClient (so sm_ban will work normally)
Note: All admin players are ignored

* **Convars:**
  * `sm_hKickOnDBFailure <0/1>` - Should the plugin kick players if it cannot connect to the database?

### l4d2_rollback
An idea that you can either manually or have events (friendly fire, new player joining) trigger saving all the player's states. Then if say, a troll comes and kills you and/or incaps your team, you can just quick restore to exactly the point you were at with the same items, health, etc. 

Currently **in development.**

Currently auto triggers:

1. On any recent friendly fire  (only triggers once per 100 game ticks)
2. Any new player joins (only triggers once per 100 game ticks)

* **Commands:**
  * `sm_save` - Initiates a manual save of all player's states 
  * `sm_state` - Lists all the states
  * `sm_restore <player(s)>` - Restores the selected player's state. @all for all 

### l4d2_autorestart
Plugin that automatically restarts server when the server is NOT hibernating, with bots around and no players.
This fixes an issue with (shitty) custom maps that force sb_all_bot_game to 1 and disable hibernation

### l4d2_TKStopper
Plugin that prevents team killers by checking multiple criterias. Default system is as:
Any survivor that attacks another survivor

1. If within first 2 minutes of joining, no damage is dealt to either victim or attacker. This prevents the next person to join being punished.
2. If during the finale vehicle arrival, they do 0x damage to victim and take 2x reverse friendly fire
3. If neither #1 or #2, both the victim and the attacker take 1/2 the original damage
4. If victim is in a saferoom, no damage is dealt.


During any of the above three conditions, if they deal (or attempt to deal) over 75 HP in 15 seconds they will be instantly banned for a set period of time (60 minutes). If they are for sure a team killer, it can be extended to a permanent ban.

* **Cvars:**
  * `l4d2_tk_forgiveness_time <#>` - The minimum amount of seconds to pass (in seconds) where a player's previous accumulated FF is forgive. Default is 15s
  * `l4d2_tk_bantime` - How long in minutes should a player be banned for? 0 for permanently. Default is 60
  * `l4d2_tk_ban_ff_threshold` -  How much damage does a player need to do before being instantly banned. Default 75 HP
  * `4d2_tk_ban_join_time` -  Upto how many minutes should any new player's FF be ignored. Default is 2 Minutes


### l4d2_crescendo_control
This plugin prevents the activation of buttons ahead of the team. It will prevent players from starting crescendos (and some small other activities as a side effect) until a certain threshold of the team has reached the area.

_This plugin is currently in **development.**_ Current implementation may be lacking.

(For technical information look at https://jackz.me/l4d2/admin/#plugins under 'Crescendo Stopper')

* **Cvars:**
  * `l4d2_crescendo_percent`
  * `l4d2_crescendo_range`