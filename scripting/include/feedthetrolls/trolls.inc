// UP THE VALUE 'MAX_TROLLS' in base.inc before adding new ones!

int slipperyShoesIndex = 0;
int stickyGooIndex = 0;
int invertedTrollIndex;
// int fireSpitMagnetTrollIndex;

void SetupTrolls() {
	trollKV = new StringMap();
	categories = new ArrayList(ByteCountToCells(16));
	gRandomClients = new ArrayList();
	int index;
	SetupTroll("Reset User", "Resets the user, removes all troll effects", TrollMod_Instant);

	/// CATEGORY: Magnets
	SetCategory("Magnets");
	index = SetupTroll("Special Magnet", "Attracts ALL specials to any alive target with this troll enabled", TrollMod_Constant);
	AddMagnetFlags(index);
	index = SetupTroll("Tank Magnet", "Attracts ALL tanks to any alive target with this troll enabled", TrollMod_Constant);
	AddMagnetFlags(index);
	#if defined _behavior_included
	index = SetupTroll("Witch Magnet", "All witches when startled will target any player with this troll", TrollMod_Constant);
	#endif
	// fireSpitMagnetTrollIndex = SetupTroll("Fire & Acid Magnet", "Make the player gravitate toward danger", TRollMod_Constant);

	/// CATEGORY: Infected
	SetCategory("Infected");
	SetupTroll("Swarm", "Swarms a player with zombies. Requires swarm plugin", TrollMod_Instant | TrollMod_Constant);
	SetupTroll("Vomit Player", "Shortcut to sm_vomitplayer. vomits the player.", TrollMod_Instant);
	SetupTroll("Inface Special", "Shortcut to sm_inface", TrollMod_Instant);
	SetupTroll("Insta Special", "Shortcut to sm_insta", TrollMod_Instant);
	SetupTroll("Goo", "Spawns a spitter puddle underneath them", TrollMod_Instant);
	index = SetupTroll("Sticky Goo", "Slows player down in goo", TrollMod_Constant);
	Trolls[index].AddFlagPrompt(false);
	Trolls[index].AddFlag("60% Movement Speed", true);
	Trolls[index].AddFlag("30% Movement Speed", false);
	Trolls[index].AddFlag("0% Movement Speed", false);
	stickyGooIndex = index;
	index = SetupTroll("Vocalize Specials", "Spawn commons on special vocals", TrollMod_Constant);
	Trolls[index].AddFlagPrompt(false);
	Trolls[index].AddFlag("Mute Vocalization", true);
	Trolls[index].AddFlag("Do not mute", false);
	index = SetupTroll("Instant Commons", "Spawns commons behind or infront", TrollMod_Instant | TrollMod_Constant);
	Trolls[index].AddFlagPrompt(false);
	Trolls[index].AddFlag("In Back", true);
	Trolls[index].AddFlag("In Front", false);


	// CATEGORY: Items
	SetCategory("Items");
	index = SetupTroll("Throw It All", "Player throws their item(s) periodically to a nearby player", TrollMod_Instant);
	//Can't add directly, is custom troll: 
	// Trolls[index].AddFlag("Throw to Admin", true);
	// Trolls[index].AddFlag("Drop At Feet", false);
	// Trolls[index].AddFlag("Drop At Admin", false);
	index = SetupTroll("Bad Throw", "Player drops throwables on throw, and biles/molotovs themselves", TrollMod_Constant);
	Trolls[index].AddFlagPrompt(true);
	Trolls[index].AddFlag("Biles", true);
	Trolls[index].AddFlag("Molotovs", true);
	Trolls[index].AddFlag("Pipebombs", true);
	index = SetupTroll("Spicy Gas", "Gascans player picks up just ignite. Magic.", TrollMod_Constant);
	Trolls[index].AddFlagPrompt(false);
	Trolls[index].AddFlag("Always (100%)", false);
	Trolls[index].AddFlag("Half Time (50%)", true);
	Trolls[index].AddFlag("Rare (10%)", false);
	index = SetupTroll("No Pickup", "Prevents a player from picking up ANY (new) item. Use ThrowItAll to make them drop", TrollMod_Constant);
	Trolls[index].AddFlagPrompt(true);
	Trolls[index].AddFlag("No Primary", false);
	Trolls[index].AddFlag("No Melee", false);
	Trolls[index].AddFlag("No Throwables", true);
	Trolls[index].AddFlag("No Kits", true);
	Trolls[index].AddFlag("No Pills / Adr", true);
	Trolls[index].AddFlag("No GASCANS", true);
	index = SetupTroll("UziRules / AwpSmells", "Picking up a weapon gives them a UZI or AWP instead", TrollMod_Constant);
	Trolls[index].AddFlagPrompt(false);
	Trolls[index].AddFlag("UZI Only", true);
	Trolls[index].AddFlag("AWP Only", false);
	SetupTroll("Primary Disable", "Player cannot pickup any weapons, only melee/pistols", TrollMod_Constant);
	index = SetupTroll("Dull Melee", "Player's melee weapon does 0 damage (based on %). Headshots still work", TrollMod_Constant);
	Trolls[index].AddFlagPrompt(false);
	Trolls[index].AddFlag("Always (100%)", false);
	Trolls[index].AddFlag("Half Time (50%)", true);
	Trolls[index].AddFlag("Rare (10%)", false);
	SetupTroll("Nerf Gun", "When they shoot it does no damage.", TrollMod_Constant);
	SetupTroll("Randomize Clip Ammo", "Randomly changes their clip ammo downwards", TrollMod_Constant | TrollMod_Instant);

	/// CATEGORY: Chat
	SetCategory("Chat");
	SetupTroll("iCantSpellNoMore", "Chat messages letter will randomly changed with wrong letters", TrollMod_Constant);
	index = SetupTroll("No Profanity", "Replaces some words with random phrases", TrollMod_Constant);
	Trolls[index].AddFlagPrompt(false);
	Trolls[index].AddFlag("Only Replace Swears", false);
	Trolls[index].AddFlag("Replace Full Messages", true);
	Trolls[index].AddFlagPrompt(false);
	Trolls[index].AddFlag("Show Modified to Them", true);
	Trolls[index].AddFlag("Show Original to Them", false);
	index = SetupTroll("Vocalize Gag", "Prevents player from sending any vocalizations (even automatic)", TrollMod_Constant);
	// Trolls[index].AddFlagPrompt(false);
	// Trolls[index].AddFlag("Mute for All", true);
	// Trolls[index].AddFlag("Mute For All But Them", false);
	index = SetupTroll("Honk / Meow / Woof", "Custom sounds", TrollMod_Constant);
	Trolls[index].AddCustomFlagPrompt("Choose Sound:");
	Trolls[index].AddFlag("Honk", true);
	Trolls[index].AddFlag("Meow", false);
	Trolls[index].AddFlag("Woof", false);
	Trolls[index].AddCustomFlagPrompt("Choose Chat modifier:", false, 1);
	Trolls[index].AddFlag("Show Modified to Them", true);
	Trolls[index].AddFlag("Show Original to Them", false);
	Trolls[index].AddFlag("Show Modified Only To Them", false);
	SetupTroll("Reversed", "Reserves their message", TrollMod_Constant);
	SetupTroll("Voice Mute", "Mutes from voice", TrollMod_Constant);

	/// CATEGORY: Health
	SetCategory("Health");
	SetupTroll("Damage Boost", "Makes a player take more damage than normal", TrollMod_Constant);
	SetupTroll("Temp Health Quick Drain", "Makes a player's temporarily health drain very quickly", TrollMod_Constant);
	SetupTroll("Slow Drain", "Will make the player slowly lose health over time", TrollMod_Constant);
	SetupTroll("KillMeSoftly", "Make player eat or waste pills whenever possible", TrollMod_Instant | TrollMod_Constant);
	index = SetupTroll("Reverse FF", "All damage dealt to a player is reversed", TrollMod_Constant);
	Trolls[index].AddCustomFlagPrompt("Choose Reverse FF", false);
	Trolls[index].AddFlag("1:1 Ratio", true); //1 
	Trolls[index].AddFlag("2x Ratio", false); //2
	Trolls[index].AddFlag("0.5x Ratio", false); //4
	Trolls[index].AddFlag("0.0x Ratio (None)", false); //8
	Trolls[index].AddFlag("3x Ratio", false); //16
	Trolls[index].AddFlag("-2x Ratio", false); //16

	/// CATEGORY: Movement
	SetCategory("Movement");
	index = SetupTroll("Slow Speed", "Sets player speed to 0.8x of normal speed", TrollMod_Constant);
	Trolls[index].AddFlagPrompt(false);
	Trolls[index].AddFlag("60% Movement Speed", true);
	Trolls[index].AddFlag("30% Movement Speed", false);
	Trolls[index].AddFlag("0% Movement Speed", false);
	SetupTroll("Higher Gravity", "Sets player gravity to 1.3x of normal gravity", TrollMod_Constant);
	invertedTrollIndex = SetupTroll("Inverted Controls", "Well, aint it obvious", TrollMod_Constant);
	SetupTroll("Stagger", "Like a slap, but different", TrollMod_Instant);
	index = SetupTroll("Slippery Shoes", "Periodically stumbles around.", TrollMod_Constant);
	Trolls[index].AddFlagPrompt(true);
	Trolls[index].AddFlag("Periodically", true);
	Trolls[index].AddFlag("When using doors", false);
	Trolls[index].AddFlag("On throwable use", false);
	Trolls[index].AddFlag("On pills/adrenaline use", false);
	Trolls[index].AddFlag("On zombie bite", false);
	slipperyShoesIndex = index;

	/// CATEGORY: MISC
	SetCategory("Misc");
	SetupTroll("Gun Jam", "On reload, small chance their gun gets jammed - Can't reload.", TrollMod_Constant);
	SetupTroll("No Shove", "Prevents a player from shoving", TrollMod_Constant);
	index = SetupTroll("Car Splat", "Car. splats.", TrollMod_Instant);
	Trolls[index].AddFlagPrompt(false);
	Trolls[index].AddFlag("On Top", true);
	Trolls[index].AddFlag("Into (Infront)", false);
	Trolls[index].AddFlag("Into (Behind)", false);
	SetupTroll("CameTooEarly", "When they shoot, random chance they empty whole clip", TrollMod_Constant);
	index = SetupTroll("Meta: Inverse", "Uhm you are not supposed to see this...", TrollMod_Instant);
	Trolls[index].hidden = true;
	Trolls[index].AddFlagPrompt(false);
	Trolls[index].AddFlag("100%", true);
	Trolls[index].AddFlag("50%", false);
	Trolls[index].AddFlag("10%", false);

	

	// Initialize the default flag values to -1
	for(int i = 0; i <= MAX_TROLLS; i++) {
		for(int j = 1; j <= MAXPLAYERS; j++) {
			Trolls[i].activeFlagClients[j] = -1;
		}
	}

}

void AddMagnetFlags(int index) {
	Trolls[index].AddCustomFlagPrompt("Choose Magnet Chance:", false);
	Trolls[index].AddFlag("Always (100%)", true);
	Trolls[index].AddFlag("Half Time (50%)", false);
	Trolls[index].AddFlag("Rare (10%)", false);
}

bool ApplyAffect(int victim, const Troll troll, int activator, trollModifier modifier, int flags) {
	bool toActive = IsTrollActiveByRawID(victim, troll.id);
	if(StrEqual(troll.name, "Reset User")) {
		LogAction(activator, victim, "\"%L\" reset all effects for \"%L\"", activator, victim);
		ShowActivityEx(activator, "[FTT] ", "reset effects for %N. ", victim);
		for(int i = 0; i <= MAX_TROLLS; i++) {
			Trolls[i].activeFlagClients[victim] = -1;
		}
		SetEntPropFloat(victim, Prop_Send, "m_flLaggedMovementValue", 1.0);
		SetEntityGravity(victim, 1.0);
		SetEntPropFloat(victim, Prop_Send, "m_flLaggedMovementValue", 1.0);
		return false;
	} else if(StrEqual(troll.name, "Slow Speed")) {
		if(toActive) {
			float movement = 0.0;
			if(flags & 1) movement = 0.6;
			else if(flags & 2) movement = 0.3;
			SetEntPropFloat(victim, Prop_Send, "m_flLaggedMovementValue", movement);
		} else 
			SetEntPropFloat(victim, Prop_Send, "m_flLaggedMovementValue", 1.0);
	} else if(StrEqual(troll.name, "Higher Gravity"))
		SetEntityGravity(victim, toActive ? 1.3 : 1.0);
	else if(StrEqual(troll.name, "UziRules / AwpSmells")) {
		DisableTroll(victim, "No Pickup");
		DisableTroll(victim, "Primary Disable");
	} else if(StrEqual(troll.name, "Primary Disable")) {
		DisableTroll(victim, "UziRules / AwpSmells");
		DisableTroll(victim, "No Pickup");
		SDKHook(victim, SDKHook_WeaponCanUse, Event_ItemPickup);
	} else if(StrEqual(troll.name, "No Pickup")) {
		DisableTroll(victim, "UziRules / AwpSmells");
		DisableTroll(victim, "Primary Disable");
		SDKHook(victim, SDKHook_WeaponCanUse, Event_ItemPickup);
	} else if(StrEqual(troll.name, "CameTooEarly")) {
		ReplyToCommand(activator, "This troll mode is not implemented.");
	} else if(StrEqual(troll.name, "KillMeSoftly")) {
		static char wpn[32];
		GetClientWeaponName(victim, 4, wpn, sizeof(wpn));
		if(StrEqual(wpn, "weapon_adrenaline") || StrEqual(wpn, "weapon_pain_pills")) {
			ClientCommand(victim, "slot5");
			pdata[victim].flags |= view_as<int>(Flag_PendingItemGive);
		}else{
			ReplyToCommand(activator, "User does not have pills or adrenaline");
			return false;
		}
		//TODO: Implement TrollMod_Constant
		return false;
	} else if(StrEqual(troll.name, "Throw It All")) {
		if(modifier & TrollMod_Instant) {
			if(flags & 1) { // Hacky, just throw their kit
				ThrowItemToPlayer(victim, activator, 3);
			} else ThrowAllItems(victim);
		}
		if(hThrowTimer == INVALID_HANDLE && modifier & TrollMod_Constant) {
			hThrowTimer = CreateTimer(hThrowItemInterval.FloatValue, Timer_ThrowTimer, _, TIMER_REPEAT);
		}
	} else if(StrEqual(troll.name, "Swarm")) {
		if(modifier & TrollMod_Instant) {
			L4D2_RunScript("RushVictim(GetPlayerFromUserID(%d), %d)", victim, 15000);
		}
		return true;
	} else if(StrEqual(troll.name, "Gun Jam")) {
		int wpn = GetClientWeaponEntIndex(victim, 0);
		if(wpn > -1)
			SDKHook(wpn, SDKHook_Reload, Event_WeaponReload);
		else {
			ReplyToCommand(activator, "Victim does not have a primary weapon.");
			return false;
		}
	} else if(StrEqual(troll.name, "Vomit Player"))
		L4D_CTerrorPlayer_OnVomitedUpon(victim, victim);
	else if(StrEqual(troll.name, "Inface Special")) {
		ShowInstaSpecialChooser(activator, GetClientUserId(victim), 1);
		return false;
	} else if(StrEqual(troll.name, "Insta Special")) {
		ShowInstaSpecialChooser(activator, GetClientUserId(victim), 0);
		return false;
	} else if(StrEqual(troll.name, "Goo")) {
		static float pos[3], ang[3];
		GetClientAbsOrigin(victim, pos);
		GetClientAbsAngles(victim, ang);
		L4D2_SpitterPrj(victim, pos, ang);
	} else if(StrEqual(troll.name, "Stagger")) {
		L4D_StaggerPlayer(victim, victim, NULL_VECTOR);
	} else if(StrEqual(troll.name, "Voice Mute")) {
		BaseComm_SetClientMute(victim, toActive);
	} else if(StrEqual(troll.name, "Spicy Gas")) {
		SDKHook(victim, SDKHook_WeaponCanUse, Event_ItemPickup);
	} else if(StrEqual(troll.name, "Car Splat")) {
		if(flags & 1) {
			if(!SpawnCarOnPlayer(victim)) {
				ReplyToCommand(activator, "Could not find a suitable area to spawn a car. Requires vertical space above victim.");
				return false;
			}
		} else if(flags & 2) {
			if(!SpawnCarToPlayer(victim, 450.0)) {
				ReplyToCommand(activator, "Could not find a suitable area to spawn a car. Requires space ahead of victim");
				return false;
			}
		} else if(flags & 4) {
			if(!SpawnCarToPlayer(victim, -450.0)) {
				ReplyToCommand(activator, "Could not find a suitable area to spawn a car. Requires space behind victim");
				return false;
			}
		}
	} else if(StrEqual(troll.name, "Instant Commons")) {
		if(modifier & TrollMod_Instant) {
			float pos[3];
			GetHorizontalPositionFromClient(victim, flags & 1 ? -40.0 : 40.0, pos);
			int victimId = GetClientUserId(victim);
			for(int i = 0; i < 30; i++) {
				int c = L4D_SpawnCommonInfected(pos);
				L4D2_RunScript("CommandABot({cmd=0,bot=EntIndexToHScript(%i),target=GetPlayerFromUserID(%i)})", c, victimId);
			}
		}
	} else if(StrEqual(troll.name, "Randomize Clip Ammo")) {
		if(modifier & TrollMod_Instant) {
			int primaryWpn = GetPlayerWeaponSlot(victim, 0);
			if(primaryWpn > 0) {
				int maxCap = GetEntProp(primaryWpn, Prop_Send, "m_iClip1");
				SetEntProp(primaryWpn, Prop_Send, "m_iClip1", GetRandomInt(0, maxCap));
			}
		}
	}  else if(~modifier & TrollMod_Constant) {
		PrintToServer("[FTT] Warn: Possibly invalid troll, no apply action defined for \"%s\"", troll.name);
		#if defined DEBUG
		ReplyToCommand(activator, "[FTT/Debug] If nothing occurs, this troll possibly was not implemented correctly. ");
		#endif
	} 
	return true;
}