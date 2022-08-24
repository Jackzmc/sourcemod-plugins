public void OnConfigsExecuted() {
	hSbFixEnabled = FindConVar("sb_fix_enabled");
	hAbmAutoHard = FindConVar("abm_autohard");
}

public void OnMapStart() {
	if(hBotReverseFFDefend.IntValue > 0) hSbFriendlyFire.BoolValue = true;
	AddFileToDownloadsTable("sound/custom/meow1.mp3");
	PrecacheSound("custom/meow1.mp3");	
	AddFileToDownloadsTable("sound/custom/woof1.mp3");
	PrecacheSound("custom/woof1.mp3");	


	lastButtonUser = -1;
	HookEntityOutput("func_button", "OnPressed", Event_ButtonPress);
	CreateTimer(MAIN_TIMER_INTERVAL_S, Timer_Main, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	PrecacheSound("player/footsteps/clown/concrete1.wav");
	PrecacheSound("weapons/ceda_jar/ceda_jar_explode.wav");
	PrecacheSound("weapons/molotov/molotov_detonate_1.wav");

	PrecacheModel(MODEL_CAR);

	g_spSpawnQueue.Clear();
	spIsActive = false;
	//CreateTimer(30.0, Timer_AutoPunishCheck, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}
public void OnClientPutInServer(int client) {
	pdata[client].pendingTrollBan = 0;
	pdata[client].shootAtTarget = 0;
	fAntiRushFrequencyCounter[client] = 0.0;
	if(IsTrollActive(client, "Voice Mute"))
		BaseComm_SetClientMute(client, true);
	SDKHook(client, SDKHook_OnTakeDamage, Event_TakeDamage);
	SDKHook(client, SDKHook_OnTakeDamageAlive, NerfGun_OnTakeDamage);
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast) {
	int userid = event.GetInt("userid");
	if(spIsActive)
		CreateTimer(0.1, Timer_CheckSpecial, userid);
} 



public void OnEntityCreated(int entity, const char[] classname) {
	if(entity >= MaxClients) {
		if(StrEqual(classname, "infected", false))
			SDKHook(entity, SDKHook_OnTakeDamageAlive, NerfGun_OnTakeDamage);
		else if(StrEqual(classname, "prop_physics")) {
			HookSingleEntityOutput(entity, "OnHitByTank", OnCarHitByTank);
		} else if(StrEqual(classname, "prop_car_alarm")) {
			HookSingleEntityOutput(entity, "OnHitByTank", OnCarHitByTank);
		} else if(StrEqual(classname, "tank_rock") || StrContains(classname, "_projectile", true) > -1 ) {
			RequestFrame(EntityCreateCallback, entity);
		}
	}
}

void OnCarHitByTank(const char[] output, int caller, int activator, float delay) {
	entLastHeight[activator] = -10000.0;
	CreateTimer(0.1, Timer_WaitForApex, EntIndexToEntRef(activator), TIMER_REPEAT);
}

void EntityCreateCallback(int entity) {
	if(!HasEntProp(entity, Prop_Send, "m_hOwnerEntity") || !IsValidEntity(entity)) return;
	static char class[16];

	static int badThrowID;
	if(badThrowID == 0) badThrowID = GetTrollID("Bad Throw");

	GetEntityClassname(entity, class, sizeof(class));
	int entOwner = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
	if(entOwner > 0 && entOwner <= MaxClients) {
		if(Trolls[badThrowID].IsActive(entOwner)) {
			static float pos[3];
			GetClientEyePosition(entOwner, pos);
			if(Trolls[badThrowID].IsFlagActive(entOwner, Flag_1) && StrEqual(class, "vomitjar_projectile", true)) {
				AcceptEntityInput(entity, "Kill");
				if(hBadThrowHitSelf.FloatValue > 0.0 && GetRandomFloat() <= hBadThrowHitSelf.FloatValue) {
					L4D_CTerrorPlayer_OnVomitedUpon(entOwner, entOwner);
					EmitSoundToAll("weapons/ceda_jar/ceda_jar_explode.wav", entOwner);
					FindClosestClient(entOwner, false, pos);
				}
				SpawnItem("vomitjar", pos);
			} else if(Trolls[badThrowID].IsFlagActive(entOwner, Flag_2) && StrEqual(class, "molotov_projectile", true)) {
				// Burn them if no one near :)
				if(hBadThrowHitSelf.FloatValue > 0.0 && GetRandomFloat() <= hBadThrowHitSelf.FloatValue) {
					GetClientAbsOrigin(entOwner, pos);
					// Kill molotov if too close to a player, else teleport to feet
					if(IsAnyPlayerNear(entOwner, 500.0)) {
						AcceptEntityInput(entity, "Kill");
						EmitSoundToAll("weapons/molotov/molotov_detonate_1.wav", entOwner);
					} else {
						float vel[3];
						vel[2] -= 50.0;
						pos[2] += 50.0;
						TeleportEntity(entity, pos, NULL_VECTOR, vel);
					}
				} else {
					SpawnItem("molotov", pos);
					AcceptEntityInput(entity, "Kill");
				}
			} else if(Trolls[badThrowID].IsFlagActive(entOwner, Flag_3) && StrEqual(class, "pipe_bomb_projectile", true)) {
				if(hBadThrowHitSelf.FloatValue > 0.0 && GetRandomFloat() <= hBadThrowHitSelf.FloatValue) {
					TeleportEntity(entity, pos, NULL_VECTOR, NULL_VECTOR);
					ExplodeProjectile(entity);
				}
				SpawnItem("pipe_bomb", pos);
			}
			return;
		} else if(Trolls[slipperyShoesIndex].IsActive(entOwner)) {
			if(Trolls[slipperyShoesIndex].activeFlagClients[entOwner] & 4) {
				L4D_StaggerPlayer(entOwner, entOwner, NULL_VECTOR);
			}
			return;
		}
	}
	entLastHeight[entity] = -10000.0;
	CreateTimer(0.1, Timer_WaitForApex, EntIndexToEntRef(entity), TIMER_REPEAT);
}

enum ProjectileMagnetType {
	ProjType_Specials = 1,
	ProjType_Survivors = 2,
	ProjType_Cars = 4,
}



public void Event_DoorToggle(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(client && Trolls[slipperyShoesIndex].IsActive(client) && Trolls[slipperyShoesIndex].activeFlagClients[client] & 2) { 
		L4D_StaggerPlayer(client, client, NULL_VECTOR);
	}
}

public void Event_SecondaryHealthUsed(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(client && Trolls[slipperyShoesIndex].IsActive(client) && Trolls[slipperyShoesIndex].activeFlagClients[client] & 8) { 
		L4D_StaggerPlayer(client, client, NULL_VECTOR);
	}
}

static float SPIT_VEL[3] = { 0.0, 0.0, -1.0 };
public Action Timer_CheckSpecial(Handle h, int specialID) {
	int special = GetClientOfUserId(specialID);
	// Check if new player is the spawned special:
	if(spIsActive && special > 0 && IsFakeClient(special)) {
		//g_iPendingSurvivorAdd
		if(GetClientTeam(special) == 2 && g_iPendingSurvivorAdd && GetEntProp(special, Prop_Send, "m_humanSpectatorUserID") == 0) {
			g_iPendingSurvivorAdd = false;
			isCustomSurvivor[special] = true;
		} else if(GetClientTeam(special) == 3) {
			SpecialType type = view_as<SpecialType>(GetEntProp(special, Prop_Send, "m_zombieClass"));
			if(type == spActiveRequest.type) {
				// Ignore any fake clients with 'Bot' in name
				static char buf[32];
				GetClientName(special, buf, sizeof(buf));
				if(StrContains(buf, "bot", false) == -1) {
					if(spActiveRequest.targetUserId) {
						pdata[special].attackerTargetUid = spActiveRequest.targetUserId; 
						pdata[special].specialAttackFlags = spActiveRequest.flags;
					}

					TeleportEntity(special, spActiveRequest.position, spActiveRequest.angle, NULL_VECTOR);
					if(spActiveRequest.flags & view_as<int>(SPI_KillOnSpawn)) {
						if(type == Special_Spitter) {
							float pos[3];
							GetClientEyePosition(special, pos);
							L4D2_SpitterPrj(special, pos, SPIT_VEL);
						}
						RequestFrame(Frame_Boom, special);
					}

					g_iSpId++;

					ProcessSpecialQueue();
				}
			}
		}
 	}
	return Plugin_Handled;
}
public void Frame_Boom(int special) {
	SDKHooks_TakeDamage(special, special, special, 1000.0);
}
public void Event_PlayerFirstSpawn(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(client > 0)
		ResetClient(client, true);
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) {
	int userid = event.GetInt("userid");
	int client = GetClientOfUserId(userid);
	if(client > 0) {
		pdata[client].specialAttackFlags = 0;
		if(pdata[client].attackerTargetUid > 0) {
			// If special died, clear & subtract one from counter
			pdata[client].attackerTargetUid = 0;
		} else {
			// If player died, stop the targetting
			for(int i = 1; i <= MaxClients; i++) { 
				if(pdata[i].attackerTargetUid == userid) {
					pdata[i].attackerTargetUid = 0;
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
		CreateTimer(0.2, RushPlayer, user);
		CreateTimer(0.6, RushPlayer, user);
		CreateTimer(1.5, RushPlayer, user);
	}
	//Ignore car alarms for autopunish
	lastButtonUser = -1;
}
public Action RushPlayer(Handle h, int user) {
	L4D2_RunScript("RushVictim(GetPlayerFromUserID(%d), %d)", user, 15000);
	return Plugin_Handled;
}
public Action L4D2_OnChooseVictim(int attacker, int &curTarget) {
	static int spMagnetID, tankMagnetID;
	if(spMagnetID == 0) spMagnetID = GetTrollID("Special Magnet");
	if(tankMagnetID == 0) tankMagnetID = GetTrollID("Tank Magnet");

	if(hMagnetChance.FloatValue < GetRandomFloat()) return Plugin_Continue;
	L4D2Infected class = view_as<L4D2Infected>(GetEntProp(attacker, Prop_Send, "m_zombieClass"));
	// Check for any existing victims
	int existingTarget = GetClientOfUserId(pdata[attacker].attackerTargetUid);
	if(existingTarget > 0) {
		if(IsPlayerAlive(existingTarget)) {
			// Insta-specials ALWAYS target, if target has any attackers remaining
			if(pdata[attacker].specialAttackFlags & view_as<int>(SPI_AlwaysTarget)) {
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
			pdata[attacker].attackerTargetUid = 0;
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
		PrintToConsoleAll("[FTT/Debug] infected %N -> attack -> %N", attacker, closestClient);
		pdata[attacker].attackerTargetUid = GetClientUserId(closestClient);
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
	if(client > 0 && client <= MaxClients) {
		static int noShoveIndex;
		if(noShoveIndex == 0) noShoveIndex == GetTrollID("No Shove");
		if(Trolls[noShoveIndex].IsActive(client) && GetRandomFloat() < hShoveFailChance.FloatValue) {
			float shoveTime = L4D2Direct_GetNextShoveTime(client);
			L4D2Direct_SetNextShoveTime(client, shoveTime + 2.0);
			return Plugin_Handled;
		}
	}
	return Plugin_Continue;
}

public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs) {
	if(client <= 0 || sArgs[0] == '@') return Plugin_Continue; //Ignore admin chat or console

	static int honkID;
	static int profanityID;
	if(honkID == 0) honkID = GetTrollID("Honk / Meow / Woof");
	if(profanityID == 0) profanityID = GetTrollID("No Profanity");

	if(Trolls[honkID].IsActive(client) && Trolls[honkID].activeFlagClients[client] & 1) {
		// Honk Processing
		static char strings[32][8]; 
		int words = ExplodeString(sArgs, " ", strings, sizeof(strings), 5);
		for(int i = 0; i < words; i++) {
			if(GetRandomFloat() <= 0.8) strings[i] = "honk   ";
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
		int type = GetRandomInt(1, 14 + 3);
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
	static int SpicyGasIndex;
	if(SpicyGasIndex == 0) SpicyGasIndex = GetTrollID("Spicy Gas");
	static int UziRulesIndex;
	if(UziRulesIndex == 0) UziRulesIndex = GetTrollID("UziRules / AwpSmells");
	
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
		} else if(flags & 32 && GetEntityClassname(weapon, wpnName, sizeof(wpnName))  && StrEqual(wpnName, "weapon_gascan")) {
			return Plugin_Handled;
		}
	} else if(Trolls[UziRulesIndex].IsActive(client) || IsTrollActive(client, "Primary Disable")) {
		GetEdictClassname(weapon, wpnName, sizeof(wpnName));
		if(strcmp(wpnName[7], "rifle") >= 0
			|| strcmp(wpnName[7], "smg") >= 0 
			|| StrEqual(wpnName[7], "grenade_launcher")
			|| strcmp(wpnName[7], "sniper") > -1
			|| StrContains(wpnName, "shotgun") > -1
		) {
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
	} else if(Trolls[SpicyGasIndex].IsActive(client)) {
		if(GetEntityClassname(weapon, wpnName, sizeof(wpnName))) {
			float max = 1.0;
			if(Trolls[SpicyGasIndex].activeFlagClients[client] & 2) max = 0.5;
			else if(Trolls[SpicyGasIndex].activeFlagClients[client] & 4) max = 0.1;
			if(GetRandomFloat() <= max) {
				if(StrEqual(wpnName, "weapon_gascan")) {
					AcceptEntityInput(weapon, "Ignite", client, client);
				} else if(StrEqual(wpnName, "weapon_propanetank") || StrEqual(wpnName, "weapon_oxygentank")) {
					ExplodeProjectile(weapon, false);
				}
			}
		}
	}
	return Plugin_Continue;
}

public Action OnPlayerRunCmd(int client, int& buttons, int& impulse, float vel[3], float angles[3], int& weapon, int& subtype, int& cmdnum, int& tickcount, int& seed, int mouse[2]) {
	int healTarget = GetClientOfUserId(healTargetPlayer);
	if(healTarget > 0 && pdata[client].flags & view_as<int>(Flag_IsTargettingHealer) && healTarget != client) {
		static float pos[3];
		GetClientAbsOrigin(client, pos);
		LookAtClient(client, healTarget);
		if(GetVectorDistance(pos, healTargetPos, true) < 10000.0) {
			if(GetClientAimTarget(client, true) == healTarget) {
				buttons |= IN_ATTACK2;
				return Plugin_Changed;
			}
		}
	}

	// If 'KillMeSoftly' activated:
	if(pdata[client].flags & view_as<int>(Flag_PendingItemGive) && !(buttons & IN_ATTACK2)) {
		int target = GetClientAimTarget(client, true);
		if(target > -1) {
			ClientCommand(client, "slot5");
			buttons |= IN_ATTACK2;
			RequestFrame(StopItemGive, client);
			return Plugin_Changed;
		}
		return Plugin_Continue;
	}


	if(pdata[client].shootAtTarget > 0 && (buttons & IN_ATTACK) == 0)  {
		if(GetClientAimTarget(client, true) == pdata[client].shootAtTarget) {
			if(!IsActorBusy(client))
				PerformScene(client, "PlayerLaugh");
			buttons |= IN_ATTACK &~ (IN_RELOAD);
			return Plugin_Changed;
		} else {
			if(!IsClientConnected(pdata[client].shootAtTarget)) {
				pdata[client].shootAtTarget = 0;
			} else {
				LookAtClient(client, pdata[client].shootAtTarget);
			}
		}
	}

	// Inverted control code:
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

public Action NerfGun_OnTakeDamage(int victim, int& attacker, int& inflictor, float& damage, int& damagetype) {
	static int nerfGunIndex;
	if(nerfGunIndex == 0) nerfGunIndex = GetTrollID("Nerf Gun");
	if(attacker > 0 && attacker <= MaxClients && GetClientTeam(attacker) == 2 && Trolls[nerfGunIndex].IsActive(attacker)) {
		damage = 0.0;
		return Plugin_Changed;
	}
	return Plugin_Continue;
}

public Action Event_TakeDamage(int victim, int& attacker, int& inflictor, float& damage, int& damagetype) {
	//Stop FF from marked:
	static int reverseFF;
	if(reverseFF == 0) reverseFF = GetTrollID("Reverse FF");
	if(attacker > 0 && attacker <= MaxClients) {
		if(GetClientTeam(attacker) == 4 && IsFakeClient(attacker)) return Plugin_Continue;
	}

	if(attacker > 0 && victim <= MaxClients && attacker <= MaxClients && IsClientInGame(attacker) && IsPlayerAlive(attacker)) {
		if(pdata[attacker].shootAtTarget == victim) return Plugin_Continue;
		if(pdata[attacker].pendingTrollBan > 0 && GetClientTeam(attacker) == 2 && GetClientTeam(victim) == 2) {
			return Plugin_Stop;
		}

		

		if(damage > 0.0 && victim != attacker && Trolls[slipperyShoesIndex].IsActive(victim) && Trolls[slipperyShoesIndex].activeFlagClients[victim] & 16) { 
			L4D_StaggerPlayer(victim, victim, NULL_VECTOR);
		}

		if(IsTrollActive(victim, "Damage Boost")) {
			damage * 2;
			return Plugin_Changed;
		} else if(Trolls[reverseFF].IsActive(attacker) && damagetype != DMG_BURN && attacker != victim && GetClientTeam(attacker) == GetClientTeam(victim)) {
			
			float returnDmg = damage; //default is 1:1
			if(Trolls[reverseFF].activeFlagClients[attacker] & 2) {
				returnDmg *= 2.0;
			} else if(Trolls[reverseFF].activeFlagClients[attacker] & 4) {
				returnDmg /= 2.0;
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
		if(hBotReverseFFDefend.IntValue > 0 && IsFakeClient(attacker) && pdata[attacker].shootAtTarget == 0 && GetClientTeam(attacker) == 2 && GetClientTeam(victim) == 2) return Plugin_Stop;
		if(attacker != victim && hBotReverseFFDefend.IntValue > 0 && hBotReverseFFDefend.IntValue == 2 || GetUserAdmin(attacker) == INVALID_ADMIN_ID) {
			if(IsFakeClient(victim) && !IsFakeClient(attacker) && GetClientTeam(attacker) == 2 && GetClientTeam(victim) == 2) {
				if(hBotDefendChance.IntValue >= GetRandomFloat()) {
					if(pdata[victim].shootAtTarget == attacker) {
						pdata[attacker].shootAtTargetHealth -= RoundFloat(damage);
						pdata[victim].shootAtLoops += 4;
						return Plugin_Continue;
					} else if(pdata[victim].shootAtTarget > 0) {
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

public Action OnVocalizeCommand(int client, const char[] vocalize, int initiator) {
	static int vocalGagID;
	static int noRushingUsID;
	if(vocalGagID == 0) vocalGagID = GetTrollID("Vocalize Gag");
	if(noRushingUsID == 0) noRushingUsID = GetTrollID("No Rushing Us");
	if(Trolls[noRushingUsID].IsActive(client) && StrEqual(vocalize, "PlayerHurryUp") || StrEqual(vocalize, "PlayerYellRun") || StrEqual(vocalize, "PlayerMoveOn") || StrEqual(vocalize, "PlayerLeadOn")) {
		float speed = GetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue");
		speed -= 0.01;
		if(speed < 0.0) SetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue", 0.0);
		else if(speed > 0.05) 
			SetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue", speed);
		PrintToConsoleAdmins("[FTT] NoRushingUs: Dropping speed for %N (now %.1f%)", client, speed * 100.0);
	}
	if(Trolls[vocalGagID].IsActive(client)) {
		return Plugin_Handled;
	} 
	return Plugin_Continue;
}

#if defined _sceneprocessor_included
public void OnSceneStageChanged(int scene, SceneStages stage) {
	if(stage == SceneStage_Spawned) {
		static int vocalGagID, vocalizeSpecials;
		if(vocalizeSpecials == 0) vocalizeSpecials = GetTrollID("Vocalize Specials");


		int activator = GetSceneInitiator(scene);
		if(activator > 0 && activator <= MaxClients) {
			if(Trolls[vocalizeSpecials].IsActive(activator)) {
				static char sceneFile[32];
				GetSceneFile(scene, sceneFile, sizeof(sceneFile));
				if(StrContains(sceneFile, "warnboomer") > -1) {
					SpawnSpecialForTarget(Special_Boomer, activator, Special_OnTarget);
				} else if(StrContains(sceneFile, "warnhunter") > -1) {
					SpawnSpecialForTarget(Special_Hunter, activator, Special_OnTarget);
				} else if(StrContains(sceneFile, "warnsmoker") > -1) {
					SpawnSpecialForTarget(Special_Smoker, activator, Special_OnTarget);
				} else if(StrContains(sceneFile, "warnspitter") > -1) {
					SpawnSpecialForTarget(Special_Spitter, activator, Special_OnTarget);
				} else if(StrContains(sceneFile, "warnjockey") > -1) {
					SpawnSpecialForTarget(Special_Jockey, activator, Special_OnTarget);
				} else if(StrContains(sceneFile, "warncharger") > -1) {
					SpawnSpecialForTarget(Special_Charger, activator, Special_OnTarget);
				}
				
				if(Trolls[vocalizeSpecials].activeFlagClients[activator] & 1) {
					CancelScene(scene);
				}
			} else if(Trolls[vocalGagID].IsActive(activator)) {
				CancelScene(scene);
			}
		}
	}
}
#endif

public Action SoundHook(int clients[MAXPLAYERS], int& numClients, char sample[PLATFORM_MAX_PATH], int& entity, int& channel, float& volume, int& level, int& pitch, int& flags, char soundEntry[PLATFORM_MAX_PATH], int& seed) {
	static int honkID;
	static int vocalGagID;
	if(honkID == 0) honkID = GetTrollID("Honk / Meow / Woof");
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
				else if(Trolls[honkID].activeFlagClients[entity] & 4)
					strcopy(sample, sizeof(sample), "custom/woof1.mp3");
				else
					return Plugin_Continue;
				return Plugin_Changed;
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

public void Event_WitchVictimSet(Event event, const char[] name, bool dontBroadcast) {
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

stock int FindClosestVisibleClient(int source) {
	static float pos[3], ang[3];
	GetClientEyePosition(source, pos);
	GetClientEyeAngles(source, ang);
	TR_TraceRayFilter(pos, ang, MASK_VISIBLE, RayType_Infinite, TraceEntityFilterPlayer, source);
	return TR_GetEntityIndex();
}

public bool TraceEntityFilterPlayer(int entity, int mask, any data) {
	return data != entity && entity <= MaxClients && GetClientTeam(entity) == 2 && IsPlayerAlive(entity);
}

// TODO: Increase the frequency of spawns the longer they are in antirush. Possibly increase int and decrease over time
public Action OnAntiRush(int client, int &type, float distance) {
	if(client && client > 0 && client <= MaxClients && type == 3 && IsPlayerAlive(client) && !IsPlayerIncapped(client)) {
		if(GetGameTime() - fLastAntiRushEvent[client] > ANTI_RUSH_DEFAULT_FREQUENCY - fAntiRushFrequencyCounter[client]) { <
			if(fAntiRushFrequencyCounter[client] < ANTI_RUSH_DEFAULT_FREQUENCY) {
            	fAntiRushFrequencyCounter[client] += ANTI_RUSH_FREQ_INC;
			}
            SpecialType special = view_as<SpecialType>(GetRandomInt(1,6));
			fLastAntiRushEvent[client] = GetGameTime();
			SpawnSpecialForTarget(special, client);
			PrintToConsoleAll("[FTT] Spawning anti-rush special on %N (dist=%f) (special=%s)", client, distance, SPECIAL_NAMES[view_as<int>(special)-1]);
		}
	}
	return Plugin_Continue;
}

Action Timer_DecreaseAntiRush(Handle h) {
	for(int i = 1; i <= MaxClients; i++) {
		if(fAntiRushFrequencyCounter[i] > 1.0) {
			fAntiRushFrequencyCounter[i]--;
		} else {
			fAntiRushFrequencyCounter = 0.0;
		}
	}
	return Plugin_Continue;
}

public void L4D2_CInsectSwarm_CanHarm_Post(int acid, int spitter, int entity) {
	if(entity <= MaxClients)
		pdata[entity].lastInSpitTime = GetGameTime();
}

public void Event_EnteredSpit(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(Trolls[stickyGooIndex].IsActive(stickyGooIndex)) {
		float movement = 0.0;
		if(Trolls[stickyGooIndex].activeFlagClients[client] & 1) movement = 0.6;
		else if(Trolls[stickyGooIndex].activeFlagClients[client] & 2) movement = 0.3;

		SetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue", movement);
		pdata[client].lastInSpitTime = GetGameTime();
		if(~pdata[client].flags & view_as<int>(Flag_HasSpitTimer)) {
			CreateTimer(0.2, Timer_CheckIsInSpit, GetClientUserId(client), TIMER_REPEAT);
			pdata[client].flags |= view_as<int>(Flag_HasSpitTimer);
		}
	}

}

public void Event_BotPlayerSwap(Event event, const char[] name, bool dontBroadcast) {
	//Player replaced their idle bot
	int client = GetClientOfUserId(event.GetInt("player"));
	if(client) {
		bool debug_hadTroll = false;
		for(int i = 1; i <= MAX_TROLLS; i++) {
			if(Trolls[i].IsActive(client) && Trolls[i].HasMod(TrollMod_Constant)) { //Add activeFlagClients >= 0 check possibly?
				ApplyAffect(client, Trolls[i], -1, TrollMod_Constant, Trolls[i].activeFlagClients[client]);
				debug_hadTroll = true;
			}
		}
		if(debug_hadTroll) 
			PrintToServer("[FTT] Re-applied trolls for was-idle player %N", client);
	}
}

void Event_HealSuccess(Event event, const char[] name, bool dontBroadcast) {
	int userid = event.GetInt("subject");
	int client = GetClientOfUserId(userid);
	if(client > 0 && userid == healTargetPlayer) {
		StopHealingBots();
	}
}
