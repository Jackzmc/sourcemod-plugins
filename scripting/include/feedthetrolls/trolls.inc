// UP THE VALUE 'MAX_TROLLS' in base.inc before adding new ones!

Troll t_specialMagnet;
Troll t_tankMagnet;
int t_slipperyShoesIndex = 0;
Troll t_stickyGoo;
Troll t_invertedTroll;
int t_randomizeAnglesIndex;
int t_randomizeVelocityIndex;
int t_vomitPlayerIndex;
int t_shakeyCameraIndex;
int t_slotRouletteIndex;
Troll t_damageBoost;
Troll t_reverseFF;
int t_hideHUDIndex;
Troll t_throwItAll;
Troll t_voiceMute;
Troll t_gunJam;
Troll t_honk;
Troll t_vocalGag;
Troll t_dullMelee;
Troll t_rewind;
Troll t_noRushingUs;
Troll t_noProfanity;

void SetupTrolls() {
	trollKV = new StringMap();
	categories = new ArrayList(ByteCountToCells(16));
	TrollBuilder("Reset User", "Resets the user, removes all troll effects", TrollMod_Instant);

	/// CATEGORY: Magnets
	TrollBuilder troll;
	SetCategory("Magnets");
	troll = TrollBuilder("Special Magnet", "Attracts ALL specials to any alive target with this troll enabled", TrollMod_Constant);
	AddMagnetFlags(troll);
	t_specialMagnet = troll.Build();
	troll = TrollBuilder("Tank Magnet", "Attracts ALL tanks to any alive target with this troll enabled", TrollMod_Constant);
	AddMagnetFlags(troll);
	t_tankMagnet = troll.Build();
	#if defined _actions_included
	TrollBuilder("Witch Magnet", "All witches when startled will target any player with this troll", TrollMod_Constant);
	#endif
	TrollBuilder("Projectile Magnet", "Makes all projectiles (biles, molotovs, pipes, tank rocks) go to player", TrollMod_Constant)
		.AddPromptMulti("Target Sources")
			// Tied to: ProjectileMagnetType
			.AddOption("Infected (rocks/goo)", true)
			.AddOption("Teammates (grenades)")
			.AddOption("Thrown Tank Objects");

	/// CATEGORY: Infected
	SetCategory("Infected");
	TrollBuilder("Swarm", "Swarms a player with zombies. Requires swarm plugin", TrollMod_Instant | TrollMod_Constant);
	t_vomitPlayerIndex = TrollBuilder("Vomit Player", "Shortcut to sm_vomitplayer. vomits the player.", TrollMod_Instant | TrollMod_Constant).Id;
	TrollBuilder("Insta Special", "Shortcut to sm_insta", TrollMod_Instant)
		.AddPrompt()
			.AddOption("Around them (Director)", true)
			.AddOption("On top / in-face");
	TrollBuilder("Goo", "Spawns a spitter puddle underneath them", TrollMod_Instant);
	t_stickyGoo = TrollBuilder("Sticky Goo", "Slows player down in goo", TrollMod_Constant)
		.AddPrompt()
			.AddOptionFloat("90% Movement Speed", true, 0.9)
			.AddOptionFloat("80% Movement Speed", false, 0.8)
			.AddOptionFloat("70% Movement Speed", false, 0.7)
			.AddOptionFloat("50% Movement Speed", false, 0.5)
			.AddOptionFloat("30% Movement Speed", false, 0.3)
			.AddOptionFloat("0% Movement Speed", false, 0.0)
		.Build();
	TrollBuilder("Vocalize Specials", "Spawn commons on special vocals", TrollMod_Constant)
		.AddPrompt()
			.AddOption("Mute Vocalization", true)
			.AddOption("Do not mute", false)
	TrollBuilder("Instant Commons", "Spawns commons behind or infront", TrollMod_Instant | TrollMod_Constant)
		.AddPrompt()
			.AddOption("In Back", true)
			.AddOption("In Front", false);
	TrollBuilder("Smart Charge", "Waits until coast is clear to charge", TrollMod_Constant)
		.AddPrompt("Attempt Timeout")
			.OnPromptActivate(Activate_SmartCharge)
			.AddOptionInt("15 Seconds", true, 15)
			.AddOptionInt("30 Seconds", false, 30)
			.AddOptionInt("1 minute", false, 60)
			.AddOptionInt("5 minutes", false, 300);

	// CATEGORY: Projectiles
	SetCategory("Projectiles");
	TrollBuilder("Rock Dropper", "Drops on a rock. On their head.", TrollMod_Instant);
	TrollBuilder("Car Splat", "Car. splats.", TrollMod_Instant)
		.AddPrompt()
			.AddOption("On Top", true)
			.AddOption("Into (Infront)", false)
			.AddOption("Into (Behind)", false);
	TrollBuilder("Bad Throw", "Player drops throwables on throw, and biles/molotovs themselves", TrollMod_Constant)
		.AddPromptMulti()
			.AddOption("Biles", true)
			.AddOption("Molotovs", true)
			.AddOption("Pipebombs", true)
	TrollBuilder("Molotov Bath", "Throws a molotov on their feet", TrollMod_Instant)
		.AddPrompt()
			.AddOption("Normal", true)
			.AddOption("Set the town ablaze", false);

	// CATEGORY: Items
	SetCategory("Items");
	t_throwItAll = TrollBuilder("Throw It All", "Player throws their item(s) periodically to a nearby player", TrollMod_Instant)
		.SetTimer(THROWITALL_INTERVAL, Timer_ThrowTimer)
		.Build();
	TrollBuilder("Spicy Gas", "Gascans player picks up just ignite. Magic.", TrollMod_Constant)
		.AddPrompt()
			.AddOption("Always (100%)", false)
			.AddOption("Half Time (50%)", true)
			.AddOption("Rare (10%)", false);
	TrollBuilder("No Pickup", "Prevents a player from picking up ANY (new) item. Use ThrowItAll to make them drop", TrollMod_Constant)
		.AddPromptMulti()
			.AddOption("No Primary", false)
			.AddOption("No Melee", false)
			.AddOption("No Throwables", true)
			.AddOption("No Kits", true)
			.AddOption("No Pills / Adr", true)
			.AddOption("No GASCANS", true);
	TrollBuilder("UziRules / AwpSmells", "Picking up a weapon gives them a UZI or AWP instead", TrollMod_Constant)
		.AddPrompt()
			.AddOption("UZI Only", true)
			.AddOption("AWP Only", false)
	TrollBuilder("Primary Disable", "Player cannot pickup any weapons, only melee/pistols", TrollMod_Constant);
	t_dullMelee = TrollBuilder("Dull Melee", "Player's melee weapon does 0 damage (based on %). Headshots still work", TrollMod_Constant)
		.AddPrompt()
			.AddOptionFloat("Always (100%)", false, 1.0)
			.AddOptionFloat("Half Time (50%)", true, 0.5)
			.AddOptionFloat("Rare (10%)", false, 0.10)
		.Build();
	TrollBuilder("Nerf Gun", "When they shoot it does no damage.", TrollMod_Constant);
	TrollBuilder("Randomize Clip Ammo", "Randomly changes their clip ammo downwards", TrollMod_Constant | TrollMod_Instant);

	t_slotRouletteIndex = TrollBuilder("Slot Roulette", "Randomize their slots", TrollMod_Constant)
		.SetTimer(0.2, Timer_SlotRoulette, 8)
		.AddPromptMulti("Activiations")
			.AddOption("On Vomitted") // 1 << 0
			.AddOption("On Damage") // 1 << 1
			.AddOption("On Vocalize") // 1 << 2
			.AddOption("Periodically") // 1 << 3
		.AddPrompt("Frequency", 1 << 3)
			.AddOption("Subtle") // 1 << 4
			.AddOption("Confusing") // 1 << 5
			.AddOption("Annoying") // 1 << 6
			.AddOption("Unusuable") // 1 << 7
		.Id;

	/// CATEGORY: Chat
	SetCategory("Chat");
	TrollBuilder("Typoos", "", TrollMod_Constant);
	TrollBuilder("iCantSpellNoMore", "Chat messages letter will randomly changed with wrong letters", TrollMod_Constant);
	t_noProfanity = TrollBuilder("No Profanity", "Replaces some words with random phrases", TrollMod_Constant)
		.AddPrompt()
			.AddOption("Only Replace Swears")
			.AddOption("Replace Full Messages", true)
		.AddPrompt()
			.AddOption("Show Modified to Them", true)
			.AddOption("Show Original to Them")
		.Build();
	t_vocalGag = TrollBuilder("Vocalize Gag", "Prevents player from sending any vocalizations (even automatic)", TrollMod_Constant)
		.AddPromptMulti()
			.AddOption("Quieter", false)
			.AddOption("Painful", false)
		.Build()
	t_honk = TrollBuilder("Honk & Animal Sounds", "Custom sounds", TrollMod_Constant)
		.AddPrompt("Choose Sound:")
			.AddOption("Honk", true) // 1 << 0
			.AddOption("Quack", false) // 1 << 1
			.AddOption("Meow", false) // 1 << 2
			.AddOption("Woof", false) // 1 << 3
		.AddPrompt("Choose Chat modifier:", 1)
			.AddOption("Show Modified To All", true) // 1 << 4
			.AddOption("Show Original To Others", false) // 1 << 5
		.Build();
	TrollBuilder("Reversed", "Reserves their message", TrollMod_Constant);
	t_voiceMute = TrollBuilder("Voice Mute", "Mutes from voice", TrollMod_Constant).Build();
	t_noRushingUs = TrollBuilder("No Rushing Us", "Decreases player speed everytime they yell hurry up", TrollMod_Constant).Build();

	/// CATEGORY: Health
	SetCategory("Health");
	t_damageBoost = TrollBuilder("Damage Boost", "Makes a player take more damage than normal", TrollMod_Constant).Build();
	TrollBuilder("Temp Health Quick Drain", "Makes a player's temporarily health drain very quickly", TrollMod_Constant);
	TrollBuilder("Slow Drain", "Will make the player slowly lose health over time", TrollMod_Constant);
	TrollBuilder("KillMeSoftly", "Make player eat or waste pills whenever possible", TrollMod_Instant | TrollMod_Constant);
	t_reverseFF = TrollBuilder("Reverse FF", "All damage dealt to a player is reversed", TrollMod_Constant)
		.AddPrompt("Choose Reverse FF", false)
			.AddOptionFloat("1:1 Ratio", true, 1.0) //1 
			.AddOptionFloat("2x Ratio", false, 2.0) //2
			.AddOptionFloat("0.5x Ratio", false, 0.5) //4
			.AddOptionFloat("0.0x Ratio (None)", false, 0.0) //8
			.AddOptionFloat("3x Ratio", false, 3.0) //16
		.AddPromptMulti("Modes")
			.AddOption("Reverse Fire Damage", false) //32
			.AddOption("Reverse Explosions", false) //64
		.Build();


	TrollBuilder("Dep Bots", "Makes bots heal a player. At any cost", TrollMod_Constant)
		.AddPrompt()
			.AddOption("Do not spawn extra", true) // 1 
			.AddOption("Spawn extra bots (broke)", false) // 2
		.AddPrompt("# Of Bots")
			.AddOption("1", false) // 4
			.AddOption("2", false) // 8
			.AddOption("3", false) // 16
			.AddOption("4", true) // 32
			.AddOption("5", false) // 64
		.AddPrompt("Auto Timeout")
			.AddOption("Until Healed / Map Change", false) // 128
			.AddOption("15 seconds", true) // 255
			.AddOption("30 seconds", false) // 512
			.AddOption("1 minute", false) //1024
			.AddOption("5 minutes", false); //2048

	/// CATEGORY: Movement
	SetCategory("Movement");
	TrollBuilder("Slow Speed", "Sets player speed to 0.8x of normal speed", TrollMod_Constant)
		.OnReset(Reset_SlowSpeed)
		.AddPrompt()
			.OnPromptActivate(Activate_SlowSpeed)
			.AddOptionFloat("90% Movement Speed", true, 0.9)
			.AddOptionFloat("80% Movement Speed", false, 0.8)
			.AddOptionFloat("70% Movement Speed", false, 0.7)
			.AddOptionFloat("50% Movement Speed", false, 0.5)
			.AddOptionFloat("30% Movement Speed", false, 0.3)
			.AddOptionFloat("0% Movement Speed", false, 0.0);
	TrollBuilder("Higher Gravity", "Sets player gravity to 1.3x of normal gravity", TrollMod_Constant)
		.OnActivate(Activate_HighGravity)
		.OnReset(Reset_HighGravity);
	t_invertedTroll = TrollBuilder("Inverted Controls", "Well, aint it obvious", TrollMod_Constant).Build();
	t_slipperyShoesIndex = TrollBuilder("Slippery Shoes", "Periodically stumbles around.", TrollMod_Constant | TrollMod_Instant)
		.AddPromptMulti()
			.AddOption("Periodically", true) // 1 << 0
			.AddOption("When using doors") // 1 << 1
			.AddOption("On throwable use")
			.AddOption("On pills/adrenaline use")
			.AddOption("On zombie bite")
		.Id
	t_randomizeAnglesIndex = TrollBuilder("Randomize Angles", "Randomly change their angles", TrollMod_Constant)
		.AddPrompt("Frequency:")
			.AddOption("Once in a while", true) //1
			.AddOption("Periodically", false) //2
			.AddOption("A lot", false) //4
			.AddOption("Painful", false) //8
			.AddOption("Seizure", false) //16
	 	.Id;
	t_randomizeVelocityIndex = TrollBuilder("Randomize Velocity", "Randomly change their velocity", TrollMod_Constant)
		.SetTimer(0.1, Timer_RandomVelocity)
		.AddPrompt("Frequency:")
			.AddOption("Loose", true) //1
			.AddOption("Slippery", false) //2
			.AddOption("Earthquake", false) //4
			.AddOption("Severe Earthquake", false) //8
			.AddOption("Bouncy Castle", false) //16
		.Id;
	t_rewind = TrollBuilder("Rewind", "Teleports player backwards", TrollMod_Instant | TrollMod_Constant)
		// .SetTimer(10.0, Timer_RandomRewind)
		.SetAutoTimer(10.0)
		.OnActivate(Activate_Rewind)
		.AddPrompt("Distance")
			.AddOptionFloat("Subtle", false, 10.0)
			.AddOptionFloat("Tiny", false, 50.0)
			.AddOptionFloat("Normal", true, 100.0)
			.AddOptionFloat("Far", false, 250.0)
		.Build();

	/// CATEGORY: MISC
	SetCategory("Misc");
	t_gunJam = TrollBuilder("Gun Jam", "On reload, small chance their gun gets jammed - Can't reload.", TrollMod_Constant).Build();
	TrollBuilder("No Shove", "Prevents a player from shoving", TrollMod_Constant);
	TrollBuilder("No Button Touchie", "Stops people from pressing buttons", TrollMod_Constant)
		.AddPromptMulti()
			.AddOption("Prevent Use", true)
			.AddOption("Vomit On Touch", false)
			.AddOption("Incap On Touch", false)
			.AddOption("Slay On Touch", false)
			.AddOption("0.8x Speed", false);
	// TODO: setup instant
	t_shakeyCameraIndex = TrollBuilder("Shakey Camera", "Horrible", TrollMod_Constant)
		.AddPrompt()
	// add flag: vomit on touch
			.AddOption("Annoying but playable", false)
			.AddOption("Bad", true)
			.AddOption("Sickness", false)
			.AddOption("Violent", false)
			.AddOption("Violent XX", false)
		.Id;
	t_hideHUDIndex = TrollBuilder("Hide HUD", "Horrible", TrollMod_Constant)
		.AddPrompt()
			.AddOption("Rare & Short", false)
			.AddOption("Sometimes & Medium", false)
			.AddOption("Constantly", true)
		.Id;
	TrollBuilder("Meta: Random", "Picks a random troll", TrollMod_Instant);
	t_metaReverse = TrollBuilder("Meta: Inverse", "Uhm you are not supposed to see this...", TrollMod_Instant)
		.Hide()
		.AddPrompt()
			.AddOptionFloat("100%", true, 1.0)
			.AddOptionFloat("50%", false, 0.5)
			.AddOptionFloat("10%", false, 0.1)
		.Build();

	// Initialize the default flag values to -1
	for(int i = 0; i <= MAX_TROLLS; i++) {
		for(int j = 1; j <= MAXPLAYERS; j++) {
			Trolls[i].timerHandles[j] = null;
			Trolls[i].activeFlagClients[j] = -1;
		}
	}

}

TrollEffectResponse Activate_SmartCharge(Troll troll, int activator, int victim, int timeout, int flags, trollModifier mod) {
	if(pdata[victim].smartChargeActivator > 0) {
		ReplyToCommand(activator, "Target already has smart charge enabled");
		return TE_Error;
	} 
	pdata[victim].smartChargeAttempts = 0;
	pdata[victim].smartChargeMaxAttempts = timeout;
	pdata[victim].smartChargeActivator = GetClientUserId(activator);
	CreateTimer(1.0, Timer_CheckForChargerOpportunity, GetClientUserId(victim), TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	return TE_Success;
}

void Activate_Rewind(Troll troll, int activator, int victim, int flags, trollModifier mod) {
	float distance;
	troll.GetPromptDataFloat(activator, 0, distance);
	RewindPlayer(victim, distance);
}
void Activate_SlowSpeed(Troll troll, int activator, int victim, float movement, int flags, trollModifier mod) {
	SetEntPropFloat(victim, Prop_Send, "m_flLaggedMovementValue", movement);
}
void Reset_SlowSpeed(Troll troll, int activator, int victim) {
	SetEntPropFloat(victim, Prop_Send, "m_flLaggedMovementValue", 1.0);
}
void Activate_HighGravity(Troll troll, int activator, int victim, int flags, trollModifier mod) {
	SetEntityGravity(victim, 1.3);
}
void Reset_HighGravity(Troll troll, int activator, int victim) {
	SetEntityGravity(victim, 1.0);
}

void AddMagnetFlags(TrollBuilder troll) {
	troll.AddPrompt("Choose Magnet Chance:")
		.AddOptionFloat("Always (100%)", true, 1.0)
		.AddOptionFloat("Half Time (50%)", false, 0.5)
		.AddOptionFloat("Rare (10%)", false, 0.1);
}

TrollEffectResponse ApplyAffect(int victim, Troll troll, int activator, trollModifier modifier, int flags) {
	bool toActive = troll.IsActive(victim);
	char name[MAX_TROLL_NAME_LENGTH];
	troll.GetName(name, sizeof(name));
	if(troll.Id == 0) {
		LogAction(activator, victim, "\"%L\" reset all effects for \"%L\"", activator, victim);
		ShowActivityEx(activator, "[FTT] ", "reset effects for %N. ", victim);
		ResetClient(victim, true);
		return TE_Error; // Not an error, but don't want to show activation
	} else if(StrEqual(name, "UziRules / AwpSmells")) {
		DisableTroll(victim, "No Pickup");
		DisableTroll(victim, "Primary Disable");
	} else if(StrEqual(name, "Primary Disable")) {
		DisableTroll(victim, "UziRules / AwpSmells");
		DisableTroll(victim, "No Pickup");
		SDKHook(victim, SDKHook_WeaponCanUse, Event_ItemPickup);
	} else if(StrEqual(name, "No Pickup")) {
		DisableTroll(victim, "UziRules / AwpSmells");
		DisableTroll(victim, "Primary Disable");
		SDKHook(victim, SDKHook_WeaponCanUse, Event_ItemPickup);
	} else if(StrEqual(name, "KillMeSoftly")) {
		static char wpn[32];
		GetClientWeaponName(victim, 4, wpn, sizeof(wpn));
		if(StrEqual(wpn, "weapon_adrenaline") || StrEqual(wpn, "weapon_pain_pills")) {
			SetSlot(victim, 5);
			pdata[victim].flags |= view_as<int>(Flag_PendingItemGive);
		}else{
			ReplyToCommand(activator, "User does not have pills or adrenaline");
			return TE_Error;
		}
		//TODO: Implement TrollMod_Constant
		return TE_Error;
	} else if(StrEqual(name, "Throw It All")) {
		if(modifier & TrollMod_Instant) {
			if(flags & 1) { // Hacky, just throw their kit
				ThrowItemToPlayer(victim, activator, 3);
			} else ThrowAllItems(victim);
		}
	} else if(StrEqual(name, "Swarm")) {
		if(modifier & TrollMod_Instant) {
			L4D2_RunScript("RushVictim(GetPlayerFromUserID(%d), %d)", victim, 15000);
		}
	} else if(StrEqual(name, "Gun Jam")) {
		int wpn = GetClientWeaponEntIndex(victim, 0);
		if(wpn > -1)
			SDKHook(wpn, SDKHook_Reload, Event_WeaponReload);
		else {
			ReplyToCommand(activator, "Victim does not have a primary weapon.");
			return TE_Error;
		}
	} else if(StrEqual(name, "Vomit Player"))
		L4D_CTerrorPlayer_OnVomitedUpon(victim, victim);
	else if(StrEqual(name, "Insta Special")) {
		int mode = 0;
		if(flags & 2) mode = 1;
		ShowInstaSpecialChooser(activator, GetClientUserId(victim), mode);
		return TE_Menu;
	} else if(StrEqual(name, "Goo")) {
		static float pos[3], ang[3];
		GetClientAbsOrigin(victim, pos);
		GetClientAbsAngles(victim, ang);
		L4D2_SpitterPrj(victim, pos, ang);
	} else if(StrEqual(name, "Stagger")) {
		L4D_StaggerPlayer(victim, victim, NULL_VECTOR);
	} else if(StrEqual(name, "Voice Mute")) {
		BaseComm_SetClientMute(victim, toActive);
	} else if(StrEqual(name, "Spicy Gas")) {
		SDKHook(victim, SDKHook_WeaponCanUse, Event_ItemPickup);
	} else if(StrEqual(name, "Car Splat")) {
		if(flags & 1) {
			if(!SpawnCarOnPlayer(victim)) {
				ReplyToCommand(activator, "Could not find a suitable area to spawn a car. Requires vertical space above victim.");
				return TE_Error;
			}
		} else if(flags & 2) {
			if(!SpawnCarToPlayer(victim, 450.0)) {
				ReplyToCommand(activator, "Could not find a suitable area to spawn a car. Requires space ahead of victim");
				return TE_Error;
			}
		} else if(flags & 4) {
			if(!SpawnCarToPlayer(victim, -450.0)) {
				ReplyToCommand(activator, "Could not find a suitable area to spawn a car. Requires space behind victim");
				return TE_Error;
			}
		}
	} else if(StrEqual(name, "Instant Commons")) {
		if(modifier & TrollMod_Instant) {
			float pos[3];
			GetHorizontalPositionFromClient(victim, flags & 1 ? -40.0 : 40.0, pos);
			int victimId = GetClientUserId(victim);
			for(int i = 0; i < 30; i++) {
				int c = L4D_SpawnCommonInfected(pos);
				L4D2_RunScript("CommandABot({cmd=0,bot=EntIndexToHScript(%i),target=GetPlayerFromUserID(%i)})", c, victimId);
			}
		}
	} else if(StrEqual(name, "Randomize Clip Ammo")) {
		if(modifier & TrollMod_Instant) {
			int primaryWpn = GetPlayerWeaponSlot(victim, 0);
			if(primaryWpn > 0) {
				int maxCap = GetEntProp(primaryWpn, Prop_Send, "m_iClip1");
				SetEntProp(primaryWpn, Prop_Send, "m_iClip1", GetRandomInt(0, maxCap));
			}
		}
	} else if(StrEqual(name, "Rock Dropper")) {
		float pos[3], dropPos[3];
		GetClientEyePosition(victim, pos);
		dropPos = pos;
		dropPos[2] += 150.0;
		TR_TraceRayFilter(pos, dropPos, MASK_SOLID, RayType_EndPoint, Filter_IgnorePlayer, victim);
		if(TR_DidHit()) {
			ReplyToCommand(activator, "Could not find a suitable area. Requires vertical space.");
			return TE_Error;
		}
		float ang[3];
		ang[0] = 90.0;
		L4D_TankRockPrj(0, dropPos, ang);
	} else if(StrEqual(name, "Molotov Bath")) {
		int count = 1;
		if(flags & 2) count = 8;
		float pos[3], dropPos[3];
		GetClientEyePosition(victim, pos);
		dropPos = pos;
		dropPos[2] += 20.0;
		TR_TraceRayFilter(pos, dropPos, MASK_SOLID, RayType_EndPoint, Filter_IgnorePlayer, victim);
		if(TR_DidHit()) {
			ReplyToCommand(activator, "Could not find a suitable area. Requires vertical space.");
			return TE_Error;
		}
		if(IsAnySurvivorInRange(pos, 55.0, victim)) {
			ReplyToCommand(activator, "Victim is too close to other players.");
			return TE_Error;
		}
		float vel[3];
		vel[2] = -90.0;
		for(int i = 0; i < count; i++) {
			L4D_MolotovPrj(victim, dropPos, vel);
		}
	} else if(StrEqual(name, "Dep Bots")) {
		if(!toActive) {
			StopHealingBots();
			return TE_Success;
		} else if(healTargetPlayer != 0) {
			if(stopHealingTimer != null) {
				TriggerTimer(stopHealingTimer);
			}
			return TE_Success;
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
	} else if(StrEqual(name, "Smart Charge")) {
		if(pdata[victim].smartChargeActivator > 0) {
			ReplyToCommand(activator, "Target already has smart charge enabled");
			return TE_Error;
		} 
		int timeout = 15;
		if(flags & 2) timeout = 30;
		else if(flags & 4) timeout = 60;
		else if(flags & 8) timeout = 300;
		pdata[victim].smartChargeAttempts = 0;
		pdata[victim].smartChargeMaxAttempts = timeout;
		pdata[victim].smartChargeActivator = GetClientUserId(activator);
		CreateTimer(1.0, Timer_CheckForChargerOpportunity, GetClientUserId(victim), TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	}  else if(StrEqual(name, "No Rushing Us")) {
		SetEntPropFloat(victim, Prop_Send, "m_flLaggedMovementValue", 1.0);
	} else if(StrEqual(name, "Hide HUD")) {
		if(toActive)
			HideHUDRandom(victim);
		else
			SetEntProp(victim, Prop_Send, "m_iHideHUD", 0);
	} else if(StrEqual(name, "Rewind")) {
		if(modifier & TrollMod_Instant) {
			RewindPlayer(victim);
		}
	} else if(StrEqual(name, "Meta: Random")) {
		Troll rndTroll = Troll(GetRandomInt(0, MAX_TROLLS));
		int rndFlags = 0;
		int maxFlags = rndTroll.TotalOptionsCount;
		int numFlags = GetRandomInt(0, maxFlags);
		while(numFlags > 0) {
			// Apply a random flag
			rndFlags |= GetRandomInt(0, maxFlags)
			numFlags--;
		}
		trollModifier rndMod = rndTroll.GetDefaultMod();
		if(rndTroll.HasMod(TrollMod_Constant) && GetURandomFloat() > 0.5) {
			rndMod = TrollMod_Instant;
		} else if(rndTroll.HasMod(TrollMod_Instant) && GetURandomFloat() > 0.5) {
			rndMod = TrollMod_Constant;
		}
		rndTroll.Activate(victim, activator, rndMod, rndFlags);
	} else if(~modifier & TrollMod_Constant) {
		PrintToServer("[FTT] Warn: Possibly invalid troll, no apply action defined for \"%s\"", name);
		#if defined DEBUG
		ReplyToCommand(activator, "[FTT/Debug] If nothing occurs, this troll possibly was not implemented correctly. ");
		#endif
	}  
	return TE_Success;
}