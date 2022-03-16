public void OnPluginEnd() {
	UnhookEntityOutput("func_button", "OnPressed", Event_ButtonPress);
}
public void OnMapEnd() {
	UnhookEntityOutput("func_button", "OnPressed", Event_ButtonPress);
}
public void OnMapStart() {
	if(hBotReverseFFDefend.IntValue > 0) hSbFriendlyFire.BoolValue = true;
	AddFileToDownloadsTable("sound/custom/meow1.mp3");
	PrecacheSound("custom/meow1.mp3");	

	lastButtonUser = -1;
	HookEntityOutput("func_button", "OnPressed", Event_ButtonPress);
	CreateTimer(MAIN_TIMER_INTERVAL_S, Timer_Main, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	PrecacheSound("player/footsteps/clown/concrete1.wav");
	PrecacheSound("weapons/ceda_jar/ceda_jar_explode.wav");
	PrecacheSound("weapons/molotov/molotov_detonate_1.wav");
	//CreateTimer(30.0, Timer_AutoPunishCheck, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}
public void OnClientPutInServer(int client) {
	g_PendingBanTroll[client] = 0;
	shootAtTarget[client] = 0;
	if(IsTrollActive(client, "Voice Mute"))
		BaseComm_SetClientMute(client, true);
	SDKHook(client, SDKHook_OnTakeDamage, Event_TakeDamage);
}
public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast) {
	int userid = event.GetInt("userid");
	CreateTimer(0.1, Timer_CheckSpecial, userid);
}
public Action Timer_CheckSpecial(Handle h, int specialID) {
	int special = GetClientOfUserId(specialID);
	// Check if new player is the spawned special:
	if(special > 0 && gInstaSpecialType > -1 && IsFakeClient(special) && GetClientTeam(special) == 3) {
		int type = GetEntProp(special, Prop_Send, "m_zombieClass");
		// Verify type of special is spawned special
		if(type == gInstaSpecialType) {
			// Ignore 'ManualDirectorBot' or abm bots
			static char buf[32];
			GetClientName(special, buf, sizeof(buf));
			if(StrContains(buf, "bot", false) == -1) {
				gInstaSpecialType = -1;
				// Set special to only attack them:
				g_iAttackerTarget[special] = gInstaSpecialTarget;
				// Incremenet count of specials targetting player:
				gInstaSpecialMagnet[GetClientOfUserId(gInstaSpecialTarget)]++;

				TeleportEntity(special, gInstaSpecialSpawnPos, gInstaSpecialSpawnAng, NULL_VECTOR);
				if(gInstaSpecialInstaKill) {
					RequestFrame(Frame_Boom, special);
				}
			}
		}
	} 
}
public void Frame_Boom(int special) {
	SDKHooks_TakeDamage(special, special, special, 1000.0);
	gInstaSpecialInstaKill = false;
}
public void Event_PlayerFirstSpawn(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(client > 0)
		ResetClient(client, true);
}
public void OnClientAuthorized(int client, const char[] auth) {
	if(!IsFakeClient(client)) {
		strcopy(steamids[client], 64, auth);
	}
}
public void Event_PlayerDisconnect(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(client > 0 && g_PendingBanTroll[client] > 0) {
		if(!IsFakeClient(client) && GetUserAdmin(client) == INVALID_ADMIN_ID) {
			BanIdentity(steamids[client], 0, BANFLAG_AUTHID, "Marked as Troll", "ftt", GetClientOfUserId(g_PendingBanTroll[client]));
		}
		g_PendingBanTroll[client] = 0;
	}
	steamids[client][0] = '\0';
	g_iAttackerTarget[client] = 0;
	shootAtTarget[client] = 0;
	shootAtTargetLoops[client] = 0;
	shootAtTargetHP[client] = 0;
}
public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(client > 0) {
		if(g_iAttackerTarget[client] > 0) {
			// If special died, clear & subtract one from counter
			int target = GetClientOfUserId(g_iAttackerTarget[client]);
			gInstaSpecialMagnet[target]--;
			if(gInstaSpecialMagnet[target] == 0) {
				PrintToServer("[FTT] gInstaSpecialMagnet dropped below 0");
				gInstaSpecialMagnet[target] = 0;
			}
			g_iAttackerTarget[client] = 0;
		} else {
			// If player died, stop the targetting
			for(int i = 1; i <= MaxClients; i++) { 
				if(g_iAttackerTarget[i] == client) {
					g_iAttackerTarget[i] = 0;
					break;
				}
			}
		}
	}
}
public Action Event_WeaponReload(int weapon) {
	int client = GetEntPropEnt(weapon, Prop_Send, "m_hOwner");
	if(client > 0 &&  IsTrollActive(client, "Gun Jam")) {
		if(GetRandomFloat() < 0.10) { //10% chance gun jams
			return Plugin_Stop;
		}
	}
	return Plugin_Continue;
}
public Action Event_ButtonPress(const char[] output, int entity, int client, float delay) {
	if(client > 0 && client <= MaxClients) {
		lastButtonUser = client;
	}
	return Plugin_Continue;
}

public void Event_PanicEventCreate(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(client) {
		lastButtonUser = client;
	}
}
public void Event_CarAlarm(Event event, const char[] name, bool dontBroadcast) {
	int user = event.GetInt("userid");
	int client = GetClientOfUserId(user);
	if(client) {
		PrintToChatAll("%N has alerted the horde!", client);
		CreateTimer(0.5, RushPlayer, user);
	}
	//Ignore car alarms for autopunish
	lastButtonUser = -1;
}
public Action RushPlayer(Handle h, int user) {
	L4D2_RunScript("RushVictim(GetPlayerFromUserID(%d), %d)", user, 15000);
}
public Action L4D2_OnChooseVictim(int attacker, int &curTarget) {
	static int spMagnetID, tankMagnetID;
	if(spMagnetID == 0) spMagnetID = GetTrollID("Special Magnet");
	if(tankMagnetID == 0) tankMagnetID = GetTrollID("Tank Magnet");

	if(hMagnetChance.FloatValue < GetRandomFloat()) return Plugin_Continue;
	L4D2Infected class = view_as<L4D2Infected>(GetEntProp(attacker, Prop_Send, "m_zombieClass"));
	// Check for any existing victims
	int existingTarget = GetClientOfUserId(g_iAttackerTarget[attacker]);
	if(existingTarget > 0) {
		if(IsPlayerAlive(existingTarget)) {
			// Insta-specials ALWAYS target, if target has any attackers remaining
			if(gInstaSpecialMagnet[existingTarget] > 0) {
				curTarget = existingTarget;
				return Plugin_Changed;
			} 
			// Stop targetting if no longer magnetted:
			if(class == L4D2Infected_Tank) {
				if(!Trolls[tankMagnetID].IsActive(existingTarget) || !WillMagnetRun(Trolls[tankMagnetID], existingTarget)) return Plugin_Continue;
			} else if(class != L4D2Infected_Tank) {
				if(!Trolls[spMagnetID].IsActive(existingTarget) || !WillMagnetRun(Trolls[spMagnetID], existingTarget)) return Plugin_Continue;
			}

			// Only set target based on incap rules:
			if(class == L4D2Infected_Tank && (!IsPlayerIncapped(existingTarget) || hMagnetTargetMode.IntValue & 2) && WillMagnetRun(Trolls[tankMagnetID], existingTarget)) {
				curTarget = existingTarget;
				return Plugin_Changed;
			} else if(class != L4D2Infected_Tank && (!IsPlayerIncapped(existingTarget) || hMagnetTargetMode.IntValue & 1) && WillMagnetRun(Trolls[spMagnetID], existingTarget)) {
				curTarget = existingTarget;
				return Plugin_Changed;
			}
		} else {
			g_iAttackerTarget[attacker] = 0;
		}
	}

	// If no existing target, find closest valid victim
	float closestDistance, survPos[3], spPos[3];
	GetClientAbsOrigin(attacker, spPos); 
	int closestClient = -1;
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i)) {
			if(class == L4D2Infected_Tank) {
				if(!Trolls[tankMagnetID].IsActive(i) || !WillMagnetRun(Trolls[tankMagnetID], i)) continue;
			} else if(class != L4D2Infected_Tank) {
				if(!Trolls[spMagnetID].IsActive(i) || !WillMagnetRun(Trolls[spMagnetID], i)) continue;
			}

			if(IsPlayerIncapped(i)) {
				if(class == L4D2Infected_Tank && hMagnetTargetMode.IntValue & 2 == 0) continue;
				if(class !=  L4D2Infected_Tank && hMagnetTargetMode.IntValue & 1 == 0) continue;
			}

			PrintToConsoleAll("[FTT/Debug] Adding possible magnet victim %N for %N", i, attacker);

			GetClientAbsOrigin(i, survPos);
			float dist = GetVectorDistance(survPos, spPos, true);
			if(dist < closestDistance || closestClient == -1) {
				closestDistance = dist;
				closestClient = i;
			}
		}
	}
	// If found, set, else just let game decide
	if(closestClient > 0) {
		g_iAttackerTarget[attacker] = GetClientUserId(closestClient);
		curTarget = closestClient;
		return Plugin_Changed;
	}
	return Plugin_Continue;
}

bool WillMagnetRun(const Troll troll, int i) {
	if(troll.activeFlagClients[i] == 0) return false;

	float cChance = 1.0;
	//Skip first bit as it is ('Always')
	if(troll.activeFlagClients[i] & 2) // 2nd: 50%
		cChance = 0.5;
	else if(troll.activeFlagClients[i] & 4) //3rd: 10%
		cChance = 0.1;
	return GetRandomFloat() <= cChance;
}

public Action L4D2_OnEntityShoved(int client, int entity, int weapon, float vecDir[3], bool bIsHighPounce) {
	if(client > 0 && client <= MaxClients && IsTrollActive(client, "No Shove") && hShoveFailChance.FloatValue > GetRandomFloat()) {
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs) {
	if(sArgs[0] == '@') return Plugin_Continue; //Ignore admin chat

	static int honkID;
	static int profanityID;
	if(honkID == 0) honkID = GetTrollID("Honk / Meow");
	if(profanityID == 0) profanityID = GetTrollID("No Profanity");

	if(Trolls[honkID].IsActive(client) && Trolls[honkID].activeFlagClients[client] & 1) {
		// Honk Processing
		static char strings[32][7];
		int words = ExplodeString(sArgs, " ", strings, sizeof(strings), 5);
		for(int i = 0; i < words; i++) {
			if(GetRandomFloat() <= 0.8) strings[i] = "honk";
			else strings[i] = "squeak";
		}
		int length = 7 * words;
		char[] message = new char[length];
		ImplodeStrings(strings, 32, " ", message, length);
		if(Trolls[honkID].activeFlagClients[client] & 1)
			CPrintToChatAll("{blue}%N {default}:  %s", client, message);
		else {
			CPrintToChat(client, "{blue}%N {default}:  %s", client, message);
			bool showOriginalToOthers = Trolls[honkID].activeFlagClients[client] & 4 != 0;
			for(int i = 1; i <= MaxClients; i++) {
				if(IsClientConnected(i) && IsClientInGame(i) && i != client) {
					if(showOriginalToOthers)
						CPrintToChat(i, "{blue}%N {default}:  %s", client, sArgs);
					else
						CPrintToChat(i, "{blue}%N {default}:  %s", client, message);
				}
			}
		}
		PrintToServer("%N: %s", client, sArgs);
		return Plugin_Handled;
	} else if(IsTrollActive(client, "Reversed")) {
		int length = strlen(sArgs);
		char[] message = new char[length+1];
		int j = 0;
		for(int i = length - 1; i >= 0; i--) {
			message[j++] = sArgs[i];
		}
		message[j] = '\0';
		CPrintToChatAll("{blue}%N {default}:  %s", client, message);
		PrintToServer("%N: %s", client, sArgs);
		return Plugin_Handled;
	}else if(IsTrollActive(client, "iCantSpellNoMore")) {
		int type = GetRandomInt(1, 13 + 5);
		char letterSrc, replaceChar;
		switch(type) {
			case 1: {
				letterSrc = 'e';
				replaceChar = 'b';
			}
			case 2: {
				letterSrc = 't';
				replaceChar = 'e';
			}
			case 3: {
				letterSrc = 'i';
				replaceChar = 'e';
			}
			case 4: {
				letterSrc = 'a';
				replaceChar = 's';
			}
			case 5: {
				letterSrc = 'u';
				replaceChar = 'i';
			}
			case 6: {
				letterSrc = '.';
				replaceChar = '/';
			}
			case 7: {
				letterSrc = 'm';
				replaceChar = 'n';
			}
			case 8: {
				letterSrc = 'n';
				replaceChar = 'm';
			}
			case 9: {
				letterSrc = 'l';
				replaceChar = 'b';
			}
			case 10: {
				letterSrc = 'l';
				replaceChar = 'b';
			}
			case 11: {
				letterSrc = 'h';
				replaceChar = 'j';
			}
			case 12: {
				letterSrc = 'o';
				replaceChar = 'i';
			}
			case 13: {
				letterSrc = 'e';
				replaceChar = 'r';
			}
			case 14: {
				letterSrc = 'w';
				replaceChar = 'h';
			}

			default:
				return Plugin_Continue;
		}
		int strLength = strlen(sArgs);
		char[] newMessage = new char[strLength + 20];
		int n = 0;
		while (sArgs[n] != '\0') {
			if(sArgs[n] == letterSrc) {
				newMessage[n] = replaceChar;
			}else{
				newMessage[n] = sArgs[n];
			}
			n++;
		}  
		PrintToServer("%N: %s", client, sArgs);
		CPrintToChatAll("{blue}%N {default}:  %s", client, newMessage);
		return Plugin_Handled;
	}else if(Trolls[profanityID].IsActive(client)) {
		char strings[32][MAX_PHRASE_LENGTH];
		static ArrayList phrases;
		bool foundWord = false;
		int words = ExplodeString(sArgs, " ", strings, 32, MAX_PHRASE_LENGTH);
		// Replace all swear words
		for(int i = 0; i < words; i++) {
			phrases = GetPhrasesArray(strings[i]);
			if(phrases != null && phrases.Length > 0) {
				foundWord = true;
				phrases.GetString(GetRandomInt(0, phrases.Length - 1), strings[i], MAX_PHRASE_LENGTH);
			}
		}
		int length = MAX_PHRASE_LENGTH * words;
		char[] message = new char[length];

		if(foundWord) {
			// Found at least one word, keep modified intact
			ImplodeStrings(strings, 32, " ", message, length);
		} else if(Trolls[profanityID].activeFlagClients[client] & 2) { 
			// Replace full message content if flag enabled
			if(!fullMessagePhraseList) {
				PrintToServer("[FTT] Error: Could not find full message phrases!!!");
				return Plugin_Continue;
			}
			fullMessagePhraseList.GetString(GetRandomInt(0, fullMessagePhraseList.Length - 1), message, MAX_PHRASE_LENGTH);
		} else {
			// Flag off, keep original text
			return Plugin_Continue;
		}

		if(Trolls[profanityID].activeFlagClients[client] & 8) { //If 'show original' enabled
			CPrintToChat(client, "{blue}%N {default}:  %s", client, sArgs);
			for(int i = 1; i <= MaxClients; i++) {
				if(IsClientConnected(i) && IsClientInGame(i) && i != client) {
					CPrintToChat(i, "{blue}%N {default}:  %s", client, message);
				}
			}
		} else { //else show modified to all
			CPrintToChatAll("{blue}%N {default}:  %s", client, message);
		}
		// Print original in console no matter what
		PrintToServer("%N: %s", client, sArgs);
		return Plugin_Handled;
	}
	return Plugin_Continue;
}
static char SMG[8] = "smg";
static char AWP[16] = "sniper_awp";

public Action Event_ItemPickup(int client, int weapon) {
	static int NoPickupIndex;
	if(NoPickupIndex == 0) NoPickupIndex = GetTrollID("No Pickup");
	static char wpnName[64];
	if(Trolls[NoPickupIndex].IsActive(client)) {
		int flags = Trolls[NoPickupIndex].activeFlagClients[client];
		if(flags & 1 && GetPlayerWeaponSlot(client, view_as<int>(L4DWeaponSlot_Primary)) == weapon) {
			// No Primary
			return Plugin_Handled;
		} else if(flags & 2 && GetEntityClassname(weapon, wpnName, sizeof(wpnName))  && StrEqual(wpnName, "weapon_melee")) {
			// No melee 
			return Plugin_Handled;
		} else if(flags & 4 && GetPlayerWeaponSlot(client,  view_as<int>(L4DWeaponSlot_Grenade)) == weapon) {
			// No throwables
			return Plugin_Handled;
		} else if(flags & 8 && GetEntityClassname(weapon, wpnName, sizeof(wpnName))  && StrEqual(wpnName, "weapon_first_aid_kit")) {
			// No Kits
			return Plugin_Handled;
		} else if(flags & 16 && GetPlayerWeaponSlot(client,  view_as<int>(L4DWeaponSlot_Pills)) == weapon) {
			// No Pills / Adr
			return Plugin_Handled;
		}
		return Plugin_Continue;
	} else {
		GetEdictClassname(weapon, wpnName, sizeof(wpnName));
		if(strcmp(wpnName[7], "rifle") >= 0
			|| strcmp(wpnName[7], "smg") >= 0 
			|| StrEqual(wpnName[7], "grenade_launcher")
			|| strcmp(wpnName[7], "sniper") > -1
			|| StrContains(wpnName, "shotgun") > -1
		) {
			static int UziRulesIndex;
			if(UziRulesIndex == 0) UziRulesIndex = GetTrollID("UziRules / AwpSmells");
			//If 4: Only UZI, if 5: Can't switch.
			if(Trolls[UziRulesIndex].IsActive(client)) {
				static char comp[16]; 
				if(Trolls[UziRulesIndex].activeFlagClients[client] & 1)
					strcopy(comp, sizeof(comp), SMG);
				else
					strcopy(comp, sizeof(comp), AWP);
				static char currentWpn[32];
				GetClientWeaponName(client, 0, currentWpn, sizeof(currentWpn));
				if(StrEqual(wpnName[7], comp)) {
					return Plugin_Continue;
				} else if(StrEqual(currentWpn[7], comp)) {
					return Plugin_Stop;
				} else {
					int flags = GetCommandFlags("give");
					SetCommandFlags("give", flags & ~FCVAR_CHEAT);
					FakeClientCommand(client, "give %s", comp);
					SetCommandFlags("give", flags);
					return Plugin_Stop;
				}
			} else if(IsTrollActive(client, "Primary Disable")) {
				return Plugin_Stop;
			}
		}

		return Plugin_Continue;
	}
}

public Action OnPlayerRunCmd(int client, int& buttons, int& impulse, float vel[3], float angles[3], int& weapon, int& subtype, int& cmdnum, int& tickcount, int& seed, int mouse[2]) {
	// If 'KillMeSoftly' activated:
	if(g_bPendingItemGive[client] && !(buttons & IN_ATTACK2)) {
		int target = GetClientAimTarget(client, true);
		if(target > -1) {
			ClientCommand(client, "slot5");
			buttons |= IN_ATTACK2;
			RequestFrame(StopItemGive, client);
			return Plugin_Changed;
		}
		return Plugin_Continue;
	}

	if (shootAtTarget[client] > 0 && (buttons & IN_ATTACK) == 0)  {
		// If so, block their crouching (+duck)
		if(GetClientAimTarget(client, true) == shootAtTarget[client]) {
			if(!IsActorBusy(client))
				PerformScene(client, "PlayerLaugh");
			buttons |= IN_ATTACK;
			return Plugin_Changed;
		} else {
			if(!IsClientConnected(shootAtTarget[client])) {
				shootAtTarget[client] = 0;
			} else {
				LookAtClient(client, shootAtTarget[client]);
			}
		}
    }

	// Inverted control code:
	static int invertedTrollIndex;
	if(invertedTrollIndex == 0) invertedTrollIndex = GetTrollID("Inverted Controls");
 	if(Trolls[invertedTrollIndex].IsActive(client)) {
		if(buttons & IN_MOVELEFT || buttons & IN_MOVERIGHT) {
			vel[1] = -vel[1];
		}
		if(buttons & IN_FORWARD || buttons & IN_BACK) {
			vel[0] = -vel[0];
		}
		if(buttons & IN_JUMP) {
			buttons = buttons & ~IN_JUMP | IN_DUCK;
		} else if(buttons & IN_DUCK) {
			buttons = buttons & ~IN_DUCK | IN_JUMP;
		}
		if(buttons & IN_RUN) {
			buttons = buttons & ~IN_RUN | IN_WALK;
		} else if(buttons & IN_WALK) {
			buttons = buttons & ~IN_WALK | IN_RUN;
		}
		if(buttons & IN_RELOAD) {
			buttons = buttons & ~IN_RELOAD | IN_ATTACK2;
		} else if(buttons & IN_ATTACK2) {
			buttons = buttons & ~IN_ATTACK2 | IN_RELOAD;
		}
		return Plugin_Changed;
	}
	return Plugin_Continue;
}

public Action Event_TakeDamage(int victim, int& attacker, int& inflictor, float& damage, int& damagetype) {
	//Stop FF from marked:
	static int reverseFF;
	if(reverseFF == 0) reverseFF = GetTrollID("Reverse FF");
	if(attacker > 0 && attacker <= MaxClients && GetClientTeam(attacker) == 4 && IsFakeClient(attacker)) return Plugin_Stop;
	if(attacker > 0 && victim <= MaxClients && attacker <= MaxClients && IsClientInGame(attacker) && IsPlayerAlive(attacker)) {
		if(shootAtTarget[attacker] == victim) return Plugin_Continue;
		if(g_PendingBanTroll[attacker] > 0 && GetClientTeam(attacker) == 2 && GetClientTeam(victim) == 2) {
			return Plugin_Stop;
		}

		if(IsTrollActive(victim, "Damage Boost")) {
			damage * 2;
			return Plugin_Changed;
		} else if(Trolls[reverseFF].IsActive(attacker) && damagetype != DMG_BURN && attacker != victim && GetClientTeam(attacker) == GetClientTeam(victim)) {
			float returnDmg = damage; //default is 1:1
			if(Trolls[reverseFF].activeFlagClients[attacker] & 4) {
				returnDmg /= 2.0;
			} else if(Trolls[reverseFF].activeFlagClients[attacker] & 2) {
				returnDmg *= 2.0;
			} else if(Trolls[reverseFF].activeFlagClients[attacker] & 8) {
				returnDmg = 0.0;
			} else if(Trolls[reverseFF].activeFlagClients[attacker] & 16) {
				returnDmg *= 3.0;
			}
			SDKHooks_TakeDamage(attacker, attacker, attacker, returnDmg, damagetype, -1);
			damage = 0.0;
			return Plugin_Changed;
		}

		if(damagetype & DMG_BURN || damagetype & DMG_BLAST) {
			if(IsFakeClient(attacker)) return Plugin_Handled;
			else return Plugin_Continue;
		}
		if(hBotReverseFFDefend.IntValue > 0 && IsFakeClient(attacker) && shootAtTarget[attacker] == 0 && GetClientTeam(attacker) == 2 && GetClientTeam(victim) == 2) return Plugin_Stop;
		if(attacker != victim && hBotReverseFFDefend.IntValue > 0 && hBotReverseFFDefend.IntValue == 2 || GetUserAdmin(attacker) == INVALID_ADMIN_ID) {
			if(IsFakeClient(victim) && !IsFakeClient(attacker) && GetClientTeam(attacker) == 2 && GetClientTeam(victim) == 2) {
				if(hBotDefendChance.IntValue >= GetRandomFloat()) {
					if(shootAtTarget[victim] == attacker) {
						shootAtTargetHP[attacker] -= RoundFloat(damage);
						shootAtTargetLoops[victim] += 4;
						return Plugin_Continue;
					} else if(shootAtTarget[victim] > 0) {
						// Don't switch, wait for timer to stop
						return Plugin_Continue;
					}
					SetBotTarget(attacker, victim, GetClientRealHealth(attacker) - RoundFloat(damage));
				}
			}
		}
	}
	return Plugin_Continue;
}

public Action SoundHook(int[] clients, int& numClients, char sample[PLATFORM_MAX_PATH], int& entity, int& channel, float& volume, int& level, int& pitch, int& flags, char[] soundEntry, int& seed) {
	static int honkID;
	static int vocalGagID;
	if(honkID == 0) honkID = GetTrollID("Honk / Meow");
	if(vocalGagID == 0) vocalGagID = GetTrollID("Vocalize Gag");
	
	if(lastButtonUser > 0 && IsClientConnected(lastButtonUser) && !IsFakeClient(lastButtonUser) && StrEqual(sample, "npc/mega_mob/mega_mob_incoming.wav")) {
		PrintToConsoleAll("CRESCENDO STARTED BY %N", lastButtonUser);
		#if defined DEBUG
		PrintToChatAll("CRESCENDO STARTED BY %N", lastButtonUser);
		#endif
		
		lastCrescendoUser = lastButtonUser;
		if(IsPlayerFarDistance(lastButtonUser, AUTOPUNISH_FLOW_MIN_DISTANCE)) {
			NotifyAllAdmins("Autopunishing player %N for activation of event far from team", lastButtonUser);
			ShowActivityEx(0, "[FTT] ", "activated autopunish for crescendo activator %N (auto)", lastButtonUser);
			LogAction(0, lastButtonUser, "\"%L\" automatic autopunish for crescendo activator \"%L\"", 0, lastButtonUser);
			ActivateAutoPunish(lastButtonUser);
		}
		lastButtonUser = -1;
	}else if(numClients > 0 && entity > 0 && entity <= MaxClients) {
		if(StrContains(sample, "survivor\\voice") > -1) {
			if(Trolls[honkID].IsActive(entity)) {
				if(Trolls[honkID].activeFlagClients[entity] & 1)
					strcopy(sample, sizeof(sample), "player/footsteps/clown/concrete1.wav");
				else if(Trolls[honkID].activeFlagClients[entity] & 2)
					strcopy(sample, sizeof(sample), "custom/meow1.mp3");
				else return Plugin_Changed;
			} else if(Trolls[vocalGagID].IsActive(entity)) {
				if(Trolls[vocalGagID].activeFlagClients[entity] & 2) {
					clients[0] = entity;
					numClients = 1;
					return Plugin_Changed;
				}
				return Plugin_Handled;
			}
		}
	}
	return Plugin_Continue;
}

public Action Event_WitchVictimSet(Event event, const char[] name, bool dontBroadcast) {
	static int witchTrollID;
	if(witchTrollID == 0) witchTrollID = GetTrollID("Witch Magnet");

	int witch = event.GetInt("witchid"), closestClient = -1;
	float closestDistance, survPos[3], witchPos[3];
	GetEntPropVector(witch, Prop_Send, "m_vecOrigin", witchPos); 

	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i)) {
			//Ignore incapped players if hWitchIgnoreIncapp turned on:
			if(IsPlayerIncapped(i) && ~hMagnetTargetMode.IntValue & 4) {
				continue;
			}
			
			if(Trolls[witchTrollID].IsActive(i)) {
				GetClientAbsOrigin(i, survPos);
				float dist = GetVectorDistance(survPos, witchPos, true);
				if(closestClient == -1 || dist < closestDistance) {
					closestDistance = dist;
					closestClient = i;
				}
			}
		}
	}
	
	if(closestClient > 0) {
		DataPack pack;
		CreateDataTimer(0.1, Timer_NextWitchSet, pack);
		pack.WriteCell(GetClientUserId(closestClient));
		pack.WriteCell(witch);
		CreateDataTimer(0.2, Timer_NextWitchSet, pack);
		pack.WriteCell(GetClientUserId(closestClient));
		pack.WriteCell(witch);
	}
}

public void OnEntityCreated(int entity, const char[] classname) {
	if(IsValidEntity(entity) && StrContains(classname, "_projectile", true) > -1 ) {
		RequestFrame(EntityCreateCallback, entity);
	}
}

void EntityCreateCallback(int entity) {
	if(!HasEntProp(entity, Prop_Send, "m_hOwnerEntity") || !IsValidEntity(entity)) return;
	static char class[16];

	static int badThrowID;
	if(badThrowID == 0) {
		badThrowID = GetTrollID("Bad Throw");
	}

	GetEntityClassname(entity, class, sizeof(class));
	int entOwner = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
	if(entOwner > 0 && entOwner <= MaxClients) {
		if(Trolls[badThrowID].IsActive(entOwner)) {
			static float pos[3];
			GetClientEyePosition(entOwner, pos);
			if(Trolls[badThrowID].IsFlagActive(entOwner, Flag_1) && StrContains(class, "vomitjar", true) > -1) {
				AcceptEntityInput(entity, "Kill");
				if(hBadThrowHitSelf.FloatValue > 0.0 && GetRandomFloat() <= hBadThrowHitSelf.FloatValue) {
					L4D_CTerrorPlayer_OnVomitedUpon(entOwner, entOwner);
					EmitSoundToAll("weapons/ceda_jar/ceda_jar_explode.wav", entOwner);
					FindClosestClient(entOwner, false, pos);
				}
				SpawnItem("vomitjar", pos);
			} else if(Trolls[badThrowID].IsFlagActive(entOwner, Flag_2) && StrContains(class, "molotov", true) > -1) {
				// Burn them if no one near :)
				if(hBadThrowHitSelf.FloatValue > 0.0 && GetRandomFloat() <= hBadThrowHitSelf.FloatValue) {
					GetClientAbsOrigin(entOwner, pos);
					if(IsAnyPlayerNear(entOwner, 500.0)) {
						AcceptEntityInput(entity, "Kill");
						EmitSoundToAll("weapons/molotov/molotov_detonate_1.wav", entOwner);
					} else { // or delete if there is
						TeleportEntity(entity, pos, NULL_VECTOR, NULL_VECTOR);
					}
				} else {
					SpawnItem("molotov", pos);
					AcceptEntityInput(entity, "Kill");
				}
			} else if(Trolls[badThrowID].IsFlagActive(entOwner, Flag_3) && StrContains(class, "pipe_bomb", true) > -1) {
				if(hBadThrowHitSelf.FloatValue > 0.0 && GetRandomFloat() <= hBadThrowHitSelf.FloatValue)
					TeleportEntity(entity, pos, NULL_VECTOR, NULL_VECTOR);
				SpawnItem("pipe_bomb", pos);
			}
		}
	}
}

public Action L4D2_MeleeGetDamageForVictim(int client, int weapon, int victim, float &damage) {
	static int dullMeleeID;
	if(!dullMeleeID) dullMeleeID = GetTrollID("Dull Melee");
	if(Trolls[dullMeleeID].IsActive(client)) {
		float max = 1.0;
		if(Trolls[dullMeleeID].activeFlagClients[client] & 2) max = 0.5;
		else if(Trolls[dullMeleeID].activeFlagClients[client] & 4) max = 0.1;
		if(GetRandomFloat() <= max) {
			damage = 0.0;
			return Plugin_Changed;
		}
	}
	return Plugin_Continue;
}

int FindClosestVisibleClient(int source) {
	static float pos[3], ang[3];
	GetClientEyePosition(source, pos);
	GetClientEyeAngles(source, ang);
	Handle handle = TR_TraceRayFilterEx(pos, ang, MASK_VISIBLE, RayType_Infinite, TraceEntityFilterPlayer, source);
	return TR_GetEntityIndex(handle);
}

public bool TraceEntityFilterPlayer(int entity, int mask, any data) {
	return data != entity && entity <= MaxClients && GetClientTeam(entity) == 2 && IsPlayerAlive(entity);
}

float iLastAntiRushEvent[MAXPLAYERS+1];
public Action OnAntiRush(int client, int &type, float distance) {
	PrintToConsoleAll("[FTT] Antirush: %N (dist=%d) (GameTime=%f)", client, distance, GetGameTime());
	if(type == 3 && IsPlayerAlive(client) && !IsPlayerIncapped(client)) {
		if(GetGameTime() - iLastAntiRushEvent[client] > 30.0) {
			SpecialType special = view_as<SpecialType>(GetRandomInt(0,6));
			iLastAntiRushEvent[client] = GetGameTime();
			SpawnSpecialNear(client, special);
			PrintToConsoleAll("[FTT] Spawning anti-rush special on %N (dist=%f) (special=%d)", client, distance, special);
		}
	}
}