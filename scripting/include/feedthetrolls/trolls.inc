// UP THE VALUE 'MAX_TROLLS' in base.inc before adding new ones!

int t_slipperyShoesIndex = 0;
int t_stickyGooIndex = 0;
int t_invertedTrollIndex;
int t_randomizeAnglesIndex;
int t_randomizeVelocityIndex;
int t_vomitPlayerIndex;
int t_shakeyCameraIndex;
int t_slotRouletteIndex;
int t_damageBoostIndex;
int t_reverseFFIndex;
int t_throwItAllIndex;
int t_hideHUDIndex;
int t_cameraTurnIndex;

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
	#if defined _actions_included
	index = SetupTroll("Witch Magnet", "All witches when startled will target any player with this troll", TrollMod_Constant);
	#endif
	index = SetupTroll("Projectile Magnet", "Makes all projectiles (biles, molotovs, pipes, tank rocks) go to player", TrollMod_Constant);
	Trolls[index].AddCustomFlagPrompt("Target Sources", true);
	// Tied to: ProjectileMagnetType
	Trolls[index].AddFlag("Infected (rocks/goo)", true);
	Trolls[index].AddFlag("Teammates (grenades)", false);
	Trolls[index].AddFlag("Thrown Tank Objects", false);

	/// CATEGORY: Infected
	SetCategory("Infected");
	SetupTroll("Swarm", "Swarms a player with zombies. Requires swarm plugin", TrollMod_Instant | TrollMod_Constant);
	t_vomitPlayerIndex = SetupTroll("Vomit Player", "Shortcut to sm_vomitplayer. vomits the player.", TrollMod_Instant | TrollMod_Constant);
	SetupTroll("Inface Special", "Shortcut to sm_inface", TrollMod_Instant);
	SetupTroll("Insta Special", "Shortcut to sm_insta", TrollMod_Instant);
	SetupTroll("Goo", "Spawns a spitter puddle underneath them", TrollMod_Instant);
	index = SetupTroll("Sticky Goo", "Slows player down in goo", TrollMod_Constant);
	Trolls[index].AddFlagPrompt(false);
	Trolls[index].AddFlag("90% Movement Speed", true);
	Trolls[index].AddFlag("80% Movement Speed", false);
	Trolls[index].AddFlag("70% Movement Speed", false);
	Trolls[index].AddFlag("50% Movement Speed", false);
	Trolls[index].AddFlag("30% Movement Speed", false);
	Trolls[index].AddFlag("0% Movement Speed", false);
	t_stickyGooIndex = index;
	index = SetupTroll("Vocalize Specials", "Spawn commons on special vocals", TrollMod_Constant)
	Trolls[index].AddFlagPrompt(false);
	Trolls[index].AddFlag("Mute Vocalization", true);
	Trolls[index].AddFlag("Do not mute", false);
	index = SetupTroll("Instant Commons", "Spawns commons behind or infront", TrollMod_Instant | TrollMod_Constant);
	Trolls[index].AddFlagPrompt(false);
	Trolls[index].AddFlag("In Back", true);
	Trolls[index].AddFlag("In Front", false);
	index = SetupTroll("Smart Charge", "Waits until coast is clear to charge", TrollMod_Constant);
	Trolls[index].AddCustomFlagPrompt("Attempt Timeout", false);
	Trolls[index].AddFlag("15 Seconds", true);
	Trolls[index].AddFlag("30 Seconds", false);
	Trolls[index].AddFlag("1 minute", false);
	Trolls[index].AddFlag("5 minutes", false);

	// CATEGORY: Projectiles
	SetCategory("Projectiles");
	index = SetupTroll("Rock Dropper", "Drops on a rock. On their head.", TrollMod_Instant);
	// Trolls[index].AddFlagPrompt(false);
	// Trolls[index].AddFlag("Drop From Above", true);
	// Trolls[index].AddFlag("From behind", false);
	index = SetupTroll("Car Splat", "Car. splats.", TrollMod_Instant);
	Trolls[index].AddFlagPrompt(false);
	Trolls[index].AddFlag("On Top", true);
	Trolls[index].AddFlag("Into (Infront)", false);
	Trolls[index].AddFlag("Into (Behind)", false);
	index = SetupTroll("Bad Throw", "Player drops throwables on throw, and biles/molotovs themselves", TrollMod_Constant);
	Trolls[index].AddFlagPrompt(true);
	Trolls[index].AddFlag("Biles", true);
	Trolls[index].AddFlag("Molotovs", true);
	Trolls[index].AddFlag("Pipebombs", true);
	index = SetupTroll("Molotov Bath", "Throws a molotov on their feet", TrollMod_Instant);
	Trolls[index].AddFlagPrompt(false);
	Trolls[index].AddFlag("Normal", true);
	Trolls[index].AddFlag("Set the town ablaze", false);

	// CATEGORY: Items
	SetCategory("Items");
	index = SetupTroll("Throw It All", "Player throws their item(s) periodically to a nearby player", TrollMod_Instant);
	Trolls[index].SetTimer(THROWITALL_INTERVAL, Timer_ThrowTimer);
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
	SetupTroll("CameTooEarly", "When they shoot, random chance they empty whole clip", TrollMod_Constant);
	index = SetupTroll("Slot Roulette", "Randomize their slots", TrollMod_Constant);
	Trolls[index].AddCustomFlagPrompt("Activations:", true);
	Trolls[index].AddFlag("On Vomitted", false); // 1
	Trolls[index].AddFlag("On Damage", false); // 2
	Trolls[index].AddFlag("On Vocalize", false); // 4
	Trolls[index].AddFlag("Periodically", true); //8
	Trolls[index].AddCustomFlagPrompt("Frequency:", false, 8);
	Trolls[index].AddFlag("Subtle", false); // 16
	Trolls[index].AddFlag("Confusing", false); // 32
	Trolls[index].AddFlag("Annoying", false); // 64
	Trolls[index].AddFlag("Unusable", false); // 128
	Trolls[index].SetTimer(0.3, Timer_SlotRoulette, 8);
	t_slotRouletteIndex = index;


	/// CATEGORY: Chat
	SetCategory("Chat");
	SetupTroll("Typoos", "", TrollMod_Constant);
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
	SetupTroll("No Rushing Us", "Decreases player speed everytime they yell hurry up", TrollMod_Constant);

	/// CATEGORY: Health
	SetCategory("Health");
	t_damageBoostIndex = SetupTroll("Damage Boost", "Makes a player take more damage than normal", TrollMod_Constant);
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
	Trolls[index].AddCustomFlagPrompt("Modes", true);
	Trolls[index].AddFlag("Reverse Fire Damage", false); //32
	Trolls[index].AddFlag("Reverse Explosions", false); //64
	t_reverseFFIndex = index;


	index = SetupTroll("Dep Bots", "Makes bots heal a player. At any cost", TrollMod_Constant);
	Trolls[index].AddFlagPrompt(false);
	Trolls[index].AddFlag("Do not spawn extra", true); // 1 
	Trolls[index].AddFlag("Spawn extra bots (broke)", false); // 2
	Trolls[index].AddCustomFlagPrompt("# Of Bots", false);
	Trolls[index].AddFlag("1", false); // 4
	Trolls[index].AddFlag("2", false); // 8
	Trolls[index].AddFlag("3", false); // 16
	Trolls[index].AddFlag("4", true); // 32
	Trolls[index].AddFlag("5", false); // 64
	Trolls[index].AddCustomFlagPrompt("Auto Timeout", false, 0);
	Trolls[index].AddFlag("Until Healed / Map Change", false); // 128
	Trolls[index].AddFlag("15 seconds", true); // 255
	Trolls[index].AddFlag("30 seconds", false); // 512
	Trolls[index].AddFlag("1 minute", false); //1024
	Trolls[index].AddFlag("5 minutes", false); //2048

	/// CATEGORY: Movement
	SetCategory("Movement");
	index = SetupTroll("Slow Speed", "Sets player speed to 0.8x of normal speed", TrollMod_Constant);
	Trolls[index].AddFlagPrompt(false);
	Trolls[index].AddFlag("90% Movement Speed", true);
	Trolls[index].AddFlag("80% Movement Speed", false);
	Trolls[index].AddFlag("70% Movement Speed", false);
	Trolls[index].AddFlag("50% Movement Speed", false);
	Trolls[index].AddFlag("30% Movement Speed", false);
	Trolls[index].AddFlag("0% Movement Speed", false);
	SetupTroll("Higher Gravity", "Sets player gravity to 1.3x of normal gravity", TrollMod_Constant);
	t_invertedTrollIndex = SetupTroll("Inverted Controls", "Well, aint it obvious", TrollMod_Constant);
	SetupTroll("Stagger", "Like a slap, but different", TrollMod_Instant);
	index = SetupTroll("Slippery Shoes", "Periodically stumbles around.", TrollMod_Constant);
	Trolls[index].AddFlagPrompt(true);
	Trolls[index].AddFlag("Periodically", true);
	Trolls[index].AddFlag("When using doors", false);
	Trolls[index].AddFlag("On throwable use", false);
	Trolls[index].AddFlag("On pills/adrenaline use", false);
	Trolls[index].AddFlag("On zombie bite", false);
	t_slipperyShoesIndex = index;
	index = SetupTroll("Randomize Angles", "Randomly change their angles", TrollMod_Constant);
	Trolls[index].AddCustomFlagPrompt("Frequency:", false);
	Trolls[index].AddFlag("Once in a while", true); //1
	Trolls[index].AddFlag("Periodically", false); //2
	Trolls[index].AddFlag("A lot", false); //4
	Trolls[index].AddFlag("Painful", false); //8
	Trolls[index].AddFlag("Seizure", false); //16
	t_randomizeAnglesIndex = index;
	index = SetupTroll("Randomize Velocity", "Randomly change their velocity", TrollMod_Constant);
	Trolls[index].SetTimer(0.1, Timer_RandomVelocity);
	Trolls[index].AddCustomFlagPrompt("Frequency:", false);
	Trolls[index].AddFlag("Loose", true); //1
	Trolls[index].AddFlag("Slippery", false); //2
	Trolls[index].AddFlag("Earthquake", false); //4
	Trolls[index].AddFlag("Severe Earthquake", false); //8
	Trolls[index].AddFlag("Bouncy Castle", false); //16
	t_randomizeVelocityIndex = index;
	index = SetupTroll("Camera Turn", "Constantly turn their camera", TrollMod_Constant);
	Trolls[index].SetTimer(0.1, Timer_TurnCamera);
	Trolls[index].AddCustomFlagPrompt("Direction:", false);
	Trolls[index].AddFlag("Left/Right", true); //1
	Trolls[index].AddFlag("Up/Down", false); //2
	t_cameraTurnIndex = index;


	/// CATEGORY: MISC
	SetCategory("Misc");
	SetupTroll("Gun Jam", "On reload, small chance their gun gets jammed - Can't reload.", TrollMod_Constant);
	SetupTroll("No Shove", "Prevents a player from shoving", TrollMod_Constant);
	index = SetupTroll("No Button Touchie", "Stops people from pressing buttons", TrollMod_Constant);
	Trolls[index].AddFlagPrompt(true);
	Trolls[index].AddFlag("Prevent Use", true);
	Trolls[index].AddFlag("Vomit On Touch", false);
	Trolls[index].AddFlag("Incap On Touch", false);
	Trolls[index].AddFlag("Slay On Touch", false);
	Trolls[index].AddFlag("0.8x Speed", false);
	// TODO: setup instant
	index = SetupTroll("Shakey Camera", "Horrible", TrollMod_Constant);
	Trolls[index].AddFlagPrompt(false);
	// add flag: vomit on touch
	Trolls[index].AddFlag("Annoying but playable", false);
	Trolls[index].AddFlag("Bad", true);
	Trolls[index].AddFlag("Sickness", false);
	Trolls[index].AddFlag("Violent", false);
	Trolls[index].AddFlag("Violent XX", false);
	t_shakeyCameraIndex = index;
	index = SetupTroll("Hide HUD", "Horrible", TrollMod_Constant);
	Trolls[index].AddFlagPrompt(false);
	Trolls[index].AddFlag("Rare & Short", false);
	Trolls[index].AddFlag("Sometimes & Medium", false);
	Trolls[index].AddFlag("Constantly", true);
	t_hideHUDIndex = index;
	index = SetupTroll("Meta: Random", "Picks a random troll", TrollMod_Instant);
	index = SetupTroll("Meta: Inverse", "Uhm you are not supposed to see this...", TrollMod_Instant);
	Trolls[index].hidden = true;
	Trolls[index].AddFlagPrompt(false);
	Trolls[index].AddFlag("100%", true);
	Trolls[index].AddFlag("50%", false);
	Trolls[index].AddFlag("10%", false);



	

	// Initialize the default flag values to -1
	for(int i = 0; i <= MAX_TROLLS; i++) {
		for(int j = 1; j <= MAXPLAYERS; j++) {
			Trolls[i].timerHandles[j] = null;
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
		// for(int i = 0; i <= MAX_TROLLS; i++) {
		// 	Trolls[i].activeFlagClients[victim] = -1;
		// }
		// SetEntityGravity(victim, 1.0);
		// SetEntPropFloat(victim, Prop_Send, "m_flLaggedMovementValue", 1.0);
		ResetClient(victim, true);
		return false;
	} else if(StrEqual(troll.name, "Slow Speed")) {
		if(toActive) {
			float movement = 0.0;
			if(flags & 1) movement = 0.9;
			else if(flags & 2) movement = 0.8;
			else if(flags & 4) movement = 0.7;
			else if(flags & 8) movement = 0.5;
			else if(flags & 16) movement = 0.3;
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
			SetSlot(victim, 5);
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
	} else if(StrEqual(troll.name, "Swarm")) {
		if(modifier & TrollMod_Instant) {
			L4D2_RunScript("RushVictim(GetPlayerFromUserID(%d), %d)", victim, 15000);
		}
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
	} else if(StrEqual(troll.name, "Rock Dropper")) {
		float pos[3], dropPos[3];
		GetClientEyePosition(victim, pos);
		dropPos = pos;
		dropPos[2] += 150.0;
		TR_TraceRayFilter(pos, dropPos, MASK_SOLID, RayType_EndPoint, Filter_IgnorePlayer, victim);
		if(TR_DidHit()) {
			ReplyToCommand(activator, "Could not find a suitable area. Requires vertical space.");
			return false;
		}
		float ang[3];
		ang[0] = 90.0;
		L4D_TankRockPrj(0, dropPos, ang);
	} else if(StrEqual(troll.name, "Molotov Bath")) {
		int count = 1;
		if(flags & 2) count = 8;
		float pos[3], dropPos[3];
		GetClientEyePosition(victim, pos);
		dropPos = pos;
		dropPos[2] += 20.0;
		TR_TraceRayFilter(pos, dropPos, MASK_SOLID, RayType_EndPoint, Filter_IgnorePlayer, victim);
		if(TR_DidHit()) {
			ReplyToCommand(activator, "Could not find a suitable area. Requires vertical space.");
			return false;
		}
		if(IsAnySurvivorInRange(pos, 55.0, victim)) {
			ReplyToCommand(activator, "Victim is too close to other players.");
			return false;
		}
		float vel[3];
		vel[2] = -90.0;
		for(int i = 0; i < count; i++) {
			L4D_MolotovPrj(victim, dropPos, vel);
		}
	} else if(StrEqual(troll.name, "Dep Bots")) {
		if(!toActive) {
			StopHealingBots();
			return true;
		} else if(healTargetPlayer != 0) {
			if(stopHealingTimer != null) {
				TriggerTimer(stopHealingTimer);
			}
			return true;
		}
		bool spawnExtra = flags & 2 > 0;

		int numBots = 4;
		if(flags & 4) numBots = 1;
		else if(flags & 8) numBots = 2;
		else if(flags & 16) numBots = 3;
		else if(flags & 64) numBots = 5;

		float timeout = 0.0;
		if(flags & 255) timeout = 15.0;
		else if(flags & 512) timeout = 30.0;
		else if(flags & 1024) timeout = 60.0;
		else if(flags & 2048) timeout = 300.0;

		// TODO: Extract this !!
		healTargetPlayer = GetClientUserId(victim);

		char buffer[32];
		for(int i = 1; i <= MaxClients; i++) {
			if(IsClientConnected(i) && IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == 2 && IsFakeClient(i)) {
				int kit = GetPlayerWeaponSlot(i, 3);
				if(kit > 0) {
					GetEntityClassname(kit, buffer, sizeof(buffer));
					if(StrEqual(buffer, "weapon_first_aid_kit")) {
						PrintToServer("[FTT] Dep Bots: Found bot %N", i);
						pdata[i].flags |= view_as<int>(Flag_IsTargettingHealer);

						if(--numBots == 0) {
							break;
						}
					}
				}
			}
		}
		CreateTimer(2.0, Timer_UpdateHealTargetPos, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
		if(timeout > 0.0) {
			DataPack pack;
			stopHealingTimer = CreateDataTimer(timeout, Timer_StopHealBots, pack);
			pack.WriteCell(GetClientUserId(activator));
			pack.WriteCell(GetClientUserId(victim))
		}

		if(spawnExtra && numBots > 0) {
			if(hAbmAutoHard != null) {
				wasAbmAutoHard = hAbmAutoHard.IntValue;
				hAbmAutoHard.IntValue = 0;
			}
			CreateTimer(0.2, Timer_SpawnHealBots, numBots, TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT);
		}

		if(hSbFixEnabled != null) {
			wasSbFixEnabled = hSbFixEnabled.BoolValue;
			hSbFixEnabled.BoolValue = false;
		}
	} else if(StrEqual(troll.name, "Smart Charge")) {
		if(pdata[victim].smartChargeActivator > 0) {
			ReplyToCommand(activator, "Target already has smart charge enabled");
			return false;
		} 
		int timeout = 15;
		if(flags & 2) timeout = 30;
		else if(flags & 4) timeout = 60;
		else if(flags & 8) timeout = 300;
		pdata[victim].smartChargeAttempts = 0;
		pdata[victim].smartChargeMaxAttempts = timeout;
		pdata[victim].smartChargeActivator = GetClientUserId(activator);
		CreateTimer(1.0, Timer_CheckForChargerOpportunity, GetClientUserId(victim), TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	}  else if(StrEqual(troll.name, "No Rushing Us")) {
		SetEntPropFloat(victim, Prop_Send, "m_flLaggedMovementValue", 1.0);
	} else if(StrEqual(troll.name, "Hide HUD")) {
		if(toActive)
			HideHUDRandom(victim);
		else
			SetEntProp(victim, Prop_Send, "m_iHideHUD", 0);
	} else if(StrEqual(troll.name, "Meta: Random")) {
		int rndTroll = GetRandomInt(0, MAX_TROLLS);
		int rndFlags = 0;
		int maxFlags = Trolls[rndTroll].GetFlagCount();
		int numFlags = GetRandomInt(0, maxFlags);
		while(numFlags > 0) {
			// Apply a random flag
			rndFlags |= GetRandomInt(0, maxFlags)
			numFlags--;
		}
		trollModifier rndMod = Trolls[rndTroll].GetDefaultMod();
		if(Trolls[rndTroll].HasMod(TrollMod_Constant) && GetURandomFloat() > 0.5) {
			rndMod = TrollMod_Instant;
		} else if(Trolls[rndTroll].HasMod(TrollMod_Instant) && GetURandomFloat() > 0.5) {
			rndMod = TrollMod_Constant;
		}
		Trolls[rndTroll].Activate(victim, activator, rndMod, rndFlags);
	} else if(~modifier & TrollMod_Constant) {
		PrintToServer("[FTT] Warn: Possibly invalid troll, no apply action defined for \"%s\"", troll.name);
		#if defined DEBUG
		ReplyToCommand(activator, "[FTT/Debug] If nothing occurs, this troll possibly was not implemented correctly. ");
		#endif
	}  
	return true;
}