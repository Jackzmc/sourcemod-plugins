# sourcemod-plugins
This is a collection of all the sourcemod plugins I've created, most are just used for my own servers and some for very specific needs.

Not always the latest versions, if you have any interest with plugins I can make sure to upload the latest.

Useful things:
1. Netprop viewer https://jackz.me/netprops/l4d2

## Plugin List

### Created by Me
* #### CSGO
  * [csgo-knifehp](#csgo-knifehp) - First plugin I've made
  * [CSGOTroll](#csgotroll) - Abandoned friend trolling plugin
* #### L4D2
  * [l4d2-manual-director](#l4d2-manual-director) - Spawn specials on demand via director or at your cursor
  * [l4d2-info-cmd](#l4d2-info-cmd) - Prints a full state of all survivors, useful for external information
  * [AutoWarpBot](#autowarpbot) - Abandoned
  * [L4D2FFKickProtection](#l4d2ffkickprotection) - Prevents friendly firing from players being voted off and admins from being kicked
  * [l4d2_avoid_minigun](#l4d2_avoid_minigun) - Makes bots avoid being infront of any in use miniguns. Useful for spawned miniguns
  * [l4d2_ai_minigun](#l4d2_ai_minigun) - Based off [Silver's Survivor Bot Holdout plugin](https://forums.alliedmods.net/showthread.php?p=1741099), allows you to spawn survivor bots but with no limit.
  * [L4D2Tools](#l4d2tools) - A collection of utilities, mostly just used with [l4d_survivor_identity_fix](#l4d_survivor_identity_fix) and the /model command
  * [l4d2_swarm](#l4d2_swarm) - Uses vscript RushVictim to make all zombies target a player, like a more subtle vomitplayer
  * [l4d2_feedthetrolls](#l4d2_feedthetrolls) - Full collection of tools to troll your friends or troll the trolls
  * [l4d2_autobotcrown](#l4d2_autobotcrown) - Bots will auto crown 
  * [l4d2_extraplayeritems](#l4d2_extraplayeritems) - Includes tons of utilities for 5+ games, such as 5+ player hud, extra kit spawning, and more
  * [l4d2_population_control](#l4d2_population_control) - Allows you to custom the type of zombies that spawn (% of clowns, mud men, etc..)
  * [globalbans](#globalbans) - Bans synced via mysql, way lighter than the sourcebans cesspool.
  * [l4d2_rollback](#l4d2_rollback) - Abandoned but makes periodic backup of all player's items
  * [l4d2_autorestart](#l4d2_autorestart) - Restarts server if it's been on for a certain uptime or when empty with just bots
  * [l4d2_TKStopper](#l4d2_tkstopper) - All the teamkiller and shitty aim player punishments. Auto increasing reverse ff and teamkill detection
  * [l4d2_crescendo_control](#l4d2_crescendo_control) - Prevents players from running far ahead and starting events & logs button presses
  * [l4d2_vocalize_control](#l4d2_vocalize_control) - Allows you to locally mute someone from vocalizing
  * [l4d2_hideandseek](#l4d2_hideandseek) - An enhancement to the base hide and seek mutation
  * [l4d2_guesswho](#l4d2_guesswho) - Garrys mod's guess who in l4d2, inspired by hide and seek
  * [sm_namespamblock](#sm_namespamblock) - Basic plugin that bans players if they change their name in rapid succession 
  * [l4d2-stats-plugin](https://github.com/jackzmc/l4d2-stats-plugin) - Custom stats recorder, see https://stats.jackz.me

### Modified Others
* [200IQBots_FlyYouFools](#200iqbots_flyyoufools) - Improved code to make it support multiple tanks and work better
* [l4d_survivor_identity_fix](#l4d_survivor_identity_fix) - Use with [L4D2Tools](#l4d2tools) to change models, some fixes
* [BetterWitchAvoidance](#betterwitchavoidance)
* l4d_anti_rush - Modified plugin to add a forward, so other plugins (like feedthetrolls) can do something
* [l4d2_sb_fix](#l4d2_sb_fix) - Updated to 1.11 & latest sourcepawn syntax & removed the FCVAR_NOTIFY from all cvars (why would you put that?)

## Dependencies
This is a list of most common dependencies, independent if they are used for a certain plugin.
Check the plugin info for an exact list.

* [Left 4 Dhooks Direct](https://forums.alliedmods.net/showthread.php?t=321696)
* [Scene Processor](https://forums.alliedmods.net/showthread.php?p=2147410)

### Development Dependencies
Most L4D2 plugins use my own include: jutils.inc, it's provided in this repo.
Some do require newer includes by modified plugins (such as my improved survivor identity fix)

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
Simple l4d2 plugin that will auto teleport everyone to checkpoint once all real players have reached the saferoom.
Doesn't really work well. Abandoned.

   
### 200IQBots_FlyYouFools
Updated version of ConnerRia's plugin. Improves bots avoidance of tanks. Change from original is updated sourcepawn syntax, some optimizations/cleanup, and fixes such as bots avoiding tank that has not been activated, or not escaping in vehicle due to presence of tank.
Latest version now has support for multiple tanks, the bots might not avoid them as effectively as they would with one tank but they still try their best.
* **Convars:**
   * `FlyYouFools_Version` - Prints the version of plugin


### BetterWitchAvoidance
Inspired by the 200IQBots_FlyYouFools. Bots avoid witch if its over 40% anger when close, or a little bigger range at 60% or more. Not recommended to use, normal behavior seems fine.


### L4D2FFKickProtection
Simple plugin that prevents a player that is being vote-kicked from doing any ff damage to teammates.
It also prevents vote kicking of admins, instead will kick the player and notify admins.

* **Convars:**
  * `sm_votekick_force_threshold <#>` - The threshold of damage where the offending player is just immediately kicked. 0 -> Any attempted damage, -1 -> No auto kick.


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
Requires: [Left4Dhooks](https://forums.alliedmods.net/showthread.php?t=321696)

Spawn the holdout bots used in the passing. This supports all 8 characters, including with the minigun. They can spawn with any weapon or default to ak47.

**Notes:** 
* The minigun holdout bot has to internally be Louis, so it will be Louis making sounds, with whatever model specified being shown. This doesn't apply for normal holdout bot.
* \<survivor name> can be "bill" or their numeric id (4). 

Code modified from https://forums.alliedmods.net/showthread.php?p=1741099

* **Commands:**
  * `sm_ai_minigun <survivor name>` - Spawns an ai bot with minigun infront of wherever you are looking. Can also use numbers (0-7).
  * `sm_ai_holdout <survivor name> [wpn]` - Spawns a normal ai holdout bot (no minigun), with any weapon w/ laser sight (default is ak). 
  * `sm_ai_remove_far` - Removes any holdout or minigun bots that are 750 units or more from any player.


### L4D2Tools
Requires:
* [Left4Dhooks](https://forums.alliedmods.net/showthread.php?t=321696)
* [Scene Processor](https://forums.alliedmods.net/showthread.php?p=2147410)
* [Modified L4D Survivor Identity Fix](#l4d_survivor_identity_fix)

A collection of small tools: 
  * Notification of when someone picks up laser sights (only the first user, includes bots), 
  * Record time it takes for a finale or gauntlet run to be completed.
  * Record the amount of friendly fire damage done
  * Set the survivor models of any survivor with updating [l4d_survivor_identity_fix](#l4d_survivor_identity_fix)
  * Automatically gives melee weapons that an idle bot dropped once no longer idle
  * Automatically make players go idle when ping spikes
  * Slowly kill any zombies attacking survivor bot's blind spots (Fixes bots stuck taking damage and brain dead)

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
Requires:
* [Left4Dhooks](https://forums.alliedmods.net/showthread.php?t=321696)
* (Optional) [Scene Processor](https://forums.alliedmods.net/showthread.php?p=2147410)
* (Optional) [L4D2 Behavior](https://forums.alliedmods.net/showthread.php?p=2752139) - To be replaced with [Actions](https://forums.alliedmods.net/showthread.php?t=336374)
* (Optional) [Modified L4D Antirush](#l4d_anti_rush)

This plugin allows you to enact certain troll modes on any player, some are subtle some are less so. Either way, it works great to deal with a rusher, an asshole or even your friends.

See updated list of trolls and their descriptions:
https://admin.jackz.me/docs/ftt

* **Convars:**
  * `sm_ftt_throw_interval` - For troll mode 'ThrowItAll' (#11), how often players will re-throw all their items. 0 to disable
  * `sm_ftt_autopunish_mode <#>` - (Not used, WIP) Sets the modes that auto punish will activate for. 1 -> Early crescendo activations
  * `sm_ftt_autopunish_action <#>` - Which actions will autopunish activate? Add bits together. 0=None, 1=TankMagnet 2=SpecialMagnet 4=Swarm 8=VomitPlayer
  * `sm_ftt_autopunish_expires <0...>` - How many minutes (in gameticks) until autopunish trolls are removed. 0 for never.
  * `sm_ftt_magnet_chance <0.0 - 1.0>` - % of the time that the magnet will work on a player."
  * `sm_ftt_shove_fail_chance <0.0 - 1.0>` - The % chance that a shove fails
* **Commands:**
  * `sm_fta [player]` - Opens a menu to select a troll to apply, with modifiers and flags
  * `sm_ftr [player]` - Removes all active trolls from a player
  * `sm_ftc [player]` - Opens a menu to select a combo of trolls
  * `sm_ftl` - Lists all players that have a mode applied.
  * `sm_ftm` - Lists all troll options & their descriptions
  * `sm_mark` - Toggles marking a player to be banned when they fully disconnect
  * `sm_insta [player] [special]` - (No arguments opens menu) - Spawns a special via director that will only target the victim
  * `sm_inface [player] [special]` - Identical to above, but special will be spawned as close as possible to survivor. Boomers auto explode.
  * `sm_bots_attack <player> [target health]` - Slightly broken, but makes all bots shoot at player until they hit X health or a timeout is reached.
  * `sm_stagger <player>` - Makes a player stagger, shortcut to the Stagger troll
  * `sm_witch_attack <player>` - Makes all witches agro on the player
  * `sm_scharge <player> [timeout seconds]` - Will wait till there's no obstructions and players in the way and then spawns a charger to charge them.
  * `sm_healbots <player> [# bots or 0 default]` - Makes n amount of bots chase a player down to heal them. Won't stop until they are healed or die.


### l4d2_autobotcrown
Makes any suitable bot (> 40 hp, has shotgun) automatically crown a witch. Supports multiple bots and witches, but only one bot can crown one witch at a time. Plugin is obviously disabled in realism, and is really on suitable for coop or versus. Even works with idle players.

* **Convars:**
  * `l4d2_autocrown_allowed_difficulty <default: 7>` - The difficulties the plugin is active on. 1=Easy, 2=Normal 4=Advanced 8=Expert. Add numbers together.
  * `l4d2_autocrown_modes_tog <default: 7>` - (Not implemented) - Turn on the plugin in these game modes. 0=All, 1=Coop, 2=Survival, 4=Versus, 8=Scavenge. Add numbers together


### l4d2_extraplayeritems
Requires:
* [Left4Dhooks](https://forums.alliedmods.net/showthread.php?t=321696)
* [L4D Info Editor](https://forums.alliedmods.net/showthread.php?p=2614626)
* (Development dependency) Updated l4d2_weapon_stocks.inc

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
  * `l4d2_extraitems_hudstate` - Controls when the extra player hud shows.
    * 0 = Never, 1 = When 5+ players, 2 = Always on


### l4d_survivor_identity_fix
Requires:
* [Left4Dhooks](https://forums.alliedmods.net/showthread.php?t=321696)

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

### globalbans
This plugin will store bans in a database and read from it on connect. This allows you to easily have bans global between servers.
It will automatically intercept any ban that calls OnBanIdentity or OnBanClient (so sm_ban will work normally)
Note: All admin players are ignored

* **Convars:**
  * `sm_globalbans_kick_type <0/1/2>`
    * 0 = Do not kick, just notify
    * 1 = Kick if banned
    * 2 = Kick if cannot reach database


### l4d2_rollback
Requires:
* [Left4Dhooks](https://forums.alliedmods.net/showthread.php?t=321696)

An idea that you can either manually or have events (friendly fire, new player joining) trigger saving all the player's states. Then if say, a troll comes and kills you and/or incaps your team, you can just quick restore to exactly the point you were at with the same items, health, etc. 

Currently **abandoned.**

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
Requires:
* [Left4Dhooks](https://forums.alliedmods.net/showthread.php?t=321696)

Plugin that prevents team killers by checking multiple criterias. Default system is as:
Any survivor that attacks another survivor

1. If within first 2 minutes of joining, no damage is dealt to either victim or attacker. This prevents the next person to join being punished.
2. If during the finale vehicle arrival, they do 0x damage to victim and take 2x reverse friendly fire
3. If neither #1 or #2, both the victim and the attacker take 1/2 the original damage
4. If victim is in a saferoom, no damage is dealt.

See https://admin.jackz.me/docs/plugins#tkstopper for some more implementation information


During any of the above three conditions, if they deal (or attempt to deal) over 75 HP in 15 seconds they will be instantly banned for a set period of time (60 minutes). If they are for sure a team killer, it can be extended to a permanent ban.

* **Cvars:**
  * `l4d2_tk_forgiveness_time <#>` - The minimum amount of seconds to pass (in seconds) where a player's previous accumulated FF is forgive. Default is 15s
  * `l4d2_tk_bantime` - How long in minutes should a player be banned for? 0 for permanently. Default is 60
  * `l4d2_tk_ban_ff_threshold` -  How much damage does a player need to do before being instantly banned. Default 75 HP
  * `l4d2_tk_ban_join_time` -  Upto how many minutes should any new player's FF be ignored. Default is 2 Minutes



### l4d2_crescendo_control
Requires:
* [Left4Dhooks](https://forums.alliedmods.net/showthread.php?t=321696)

This plugin prevents the activation of buttons ahead of the team. It will prevent players from starting crescendos (and some small other activities as a side effect) until a certain threshold of the team has reached the area.

_This plugin is currently in **development.**_ Current implementation may be lacking.


* **Cvars:**
  * `l4d2_crescendo_percent`
  * `l4d2_crescendo_range`


### l4d2_vocalize_control
A very small plugin that simply allows a player to mute another player's vocalizations only for them.

* **Commands:**
  * `sm_vgag <player(s)>` - Vocalize gag or ungags selected player(s)

### l4d2_sb_fix
A fork of https://forums.alliedmods.net/showthread.php?p=2757330
- Updated to latest sourcepawn syntax (now 1.11)
- Fixed some stupid things (all cvars being FCVAR_NOTIFY)


### l4d2_hideandseek
Requires:
* [Left4Dhooks](https://forums.alliedmods.net/showthread.php?t=321696)
* [Scene Processor](https://forums.alliedmods.net/showthread.php?p=2147410)

A sourcemod extenstion of the vscript gamemode (https://steamcommunity.com/sharedfiles/filedetails/?id=2467133506)
- Player blockers, portals, and props to change and control the maps
- Some quality of life (winner messages, change seeker mid game, change map time)
- and a lot more


### l4d2_guesswho
Requires:
* [Left4Dhooks](https://forums.alliedmods.net/showthread.php?t=321696)
* [Scene Processor](https://forums.alliedmods.net/showthread.php?p=2147410)

Based off gmod guess who game, find the real players amongst a group of bots.
All logic is written in this plugin, thus is required. 
Vscript required for hud & mutation

Gamemode: https://steamcommunity.com/sharedfiles/filedetails/?id=2823719841

Requires l4dtoolz and left4dhooks, and optioanlly skip intro cutscene 


### sm_namespamblock

If a user changes their name 3 times within 10 seconds, they will be temp banned for 10 minutes.
Requires recompile to change.

* **Commands:**
  * `status2` - Shitty name, but shows all non-admin players, sorted by last joined ascending (up top). Shows steamid and the first name they joined the server as
  * `sm_status2` - Same command, but allows /status2 in chat
