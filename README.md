# sourcemod-plugins
All my sourcemod plugins... shitty probably


## Descriptions
* `csgo-knifehp` - On knife kill, gives the player 100 HP (configurable)
    * **Convars:**
      * `knifehp_enable` - Enable regaining health on knife kill
      * `knifehp_max_health` - Maximum health to set an attacker to
      * `knifehp_amount` - Amount of health to give attacker
* `l4d2-manual-director` - Probably going to be posted publicly sometime. allows you to spawn specials on cursor, or via director, forcefully, bypassing limits
    * **Convars:**
      * `manual_director_version|mandirector_version` - ... gets version
      * `mandirector_notify_spawn` - Should spawning specials notify on use?
      * `mandirector_announce_level` - Announcement types. 0 - None, 1 - Only bosses, 2 - Only specials+, 3 - Everything
      * `mandirector_enable_tank` - Should tanks be allowed to be spawned?
      * `mandirector_enable_witch` - Should witches be allowed to be spawned?
      * `mandirector_enable_mob` - Should mobs be allowed to be spawned
    * **Commands:**
      * `sm_spawnspecial` - Spawn a special via director
      * `sm_forcespecial` - Force spawn a special via director, bypassing spawn limits
      * `sm_forcecursor` - Force spawn a special at cursor, bypassing spawn limits
      * `sm_cursormenu` - Show the spawn menu for cursor spawning
      * `sm_specialmenu` - Show the spawn menu for director spawning
      * `sm_directormenu` (Same as sm_specialmenu for now)
* `l4d2-info-cmd` - Technically 'l4d2 game info', havent changed name. Just prints general information, used for a project
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
