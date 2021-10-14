public void OnPluginEnd() {
	UnhookEntityOutput("func_button", "OnPressed", Event_ButtonPress);
}
public void OnMapEnd() {
	UnhookEntityOutput("func_button", "OnPressed", Event_ButtonPress);
}
public void OnMapStart() {
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
	SDKHook(client, SDKHook_OnTakeDamage, Event_TakeDamage);
}
public void OnClientAuthorized(int client, const char[] auth) {
	if(!IsFakeClient(client)) {
		strcopy(steamids[client], 64, auth);
	}
}
public void Event_PlayerDisconnect(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(g_PendingBanTroll[client] > 0) {
		if(!IsFakeClient(client) && GetUserAdmin(client) == INVALID_ADMIN_ID) {
			BanIdentity(steamids[client], 0, BANFLAG_AUTHID, "Marked as Troll", "ftt", GetClientOfUserId(g_PendingBanTroll[client]));
		}
		g_PendingBanTroll[client] = 0;
	}
	steamids[client][0] = '\0';
	ResetClient(client, true);
	g_iAttackerTarget[client] = 0;
}
public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	g_iAttackerTarget[client] = 0;
}
public Action Event_WeaponReload(int weapon) {
	int client = GetEntPropEnt(weapon, Prop_Send, "m_hOwner");
	if(IsTrollActive(client, "Gun Jam")) {
		float dec = GetRandomFloat(0.0, 1.0);
		if(FloatCompare(dec, 0.50) == -1) { //10% chance gun jams
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
		L4D2_RunScript("RushVictim(GetPlayerFromUserID(%d), %d)", user, 15000);
	}
	//Ignore car alarms for autopunish
	lastButtonUser = -1;
}
public Action L4D2_OnChooseVictim(int attacker, int &curTarget) {
	// =========================
	// OVERRIDE VICTIM
	// =========================
	static int spMagnetID, tankMagnetID;
	if(spMagnetID == 0) spMagnetID = GetTrollID("Special Magnet");
	if(tankMagnetID == 0) tankMagnetID = GetTrollID("Tank Magnet");

	if(hMagnetChance.FloatValue < GetRandomFloat()) return Plugin_Continue;
	L4D2Infected class = view_as<L4D2Infected>(GetEntProp(attacker, Prop_Send, "m_zombieClass"));
	int existingTarget = GetClientOfUserId(g_iAttackerTarget[attacker]);
	if(existingTarget > 0 && IsPlayerAlive(existingTarget) && (hMagnetTargetMode.IntValue & 1 != 1 || !IsPlayerIncapped(existingTarget))) {
		if(class == L4D2Infected_Tank && (hMagnetTargetMode.IntValue % 2 != 2 || !IsPlayerIncapped(existingTarget))) {
			curTarget = existingTarget;
			return Plugin_Changed;
		}else if(hMagnetTargetMode.IntValue & 1 != 1 || !IsPlayerIncapped(existingTarget)) {
			curTarget = existingTarget;
			return Plugin_Changed;
		}
	}

	float closestDistance, survPos[3], spPos[3];
	GetClientAbsOrigin(attacker, spPos); 
	int closestClient = -1;
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i)) {
			//Ignore incapped players if turned on:
			if(IsPlayerIncapped(i)) {
				if((class == L4D2Infected_Tank && hMagnetTargetMode.IntValue & 2 == 2) || hMagnetTargetMode.IntValue & 1 == 1 ) continue;
			}
			
			if(class == L4D2Infected_Tank && Trolls[tankMagnetID].IsActive(i) || (class != L4D2Infected_Tank && Trolls[spMagnetID].IsActive(i))) {
				if(class == L4D2Infected_Tank) {
					if(!WillMagnetRun(Trolls[tankMagnetID], i)) return Plugin_Continue;
				} else if(!WillMagnetRun(Trolls[spMagnetID], i)) return Plugin_Continue;

				GetClientAbsOrigin(i, survPos);
				float dist = GetVectorDistance(survPos, spPos, true);
				if(closestClient == -1 || dist < closestDistance) {
					closestDistance = dist;
					closestClient = i;
				}
			}
		}
	}
	
	if(closestClient > 0) {
		g_iAttackerTarget[attacker] = GetClientUserId(closestClient);
		curTarget = closestClient;
		return Plugin_Changed;
	}
	return Plugin_Continue;
}

bool WillMagnetRun(const Troll troll, int i) {
	if(troll.activeFlagClients[i] == 0) return true;
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
	if(sArgs[0] == '@') return Plugin_Continue;
	static int honkID;
	static int profanityID;
	if(honkID == 0) honkID = GetTrollID("Honk / Meow");
	if(profanityID == 0) profanityID = GetTrollID("No Profanity");

	if(Trolls[honkID].IsActive(client) && Trolls[honkID].activeFlagClients[client] & 1) {
		static char strings[32][7];
		int words = ExplodeString(sArgs, " ", strings, sizeof(strings), 5);
		for(int i = 0; i < words; i++) {
			if(GetRandomFloat() <= 0.8) strings[i] = "honk";
			else strings[i] = "squeak";
		}
		int length = 7 * words;
		char[] message = new char[length];
		ImplodeStrings(strings, 32, " ", message, length);
		CPrintToChatAll("{blue}%N {default}:  %s", client, message);
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
		static char strings[32][MAX_PHRASE_LENGTH];
		ArrayList phrases;
		bool foundWord = false;
		int words = ExplodeString(sArgs, " ", strings, 32, MAX_PHRASE_LENGTH);
		for(int i = 0; i < words; i++) {
			//TODO: Check for valid working
			phrases = GetPhrasesArray(strings[i]);
			if(phrases != null && phrases.Length > 0) {
				foundWord = true;
				phrases.GetString(GetRandomInt(0, phrases.Length - 1), strings[i], MAX_PHRASE_LENGTH);
			}
		}
		int length = MAX_PHRASE_LENGTH * words;
		char[] message = new char[length];
		if(foundWord) {
			ImplodeStrings(strings, 32, " ", message, length);
		} else {
			if(!fullMessagePhraseList) {
				PrintToServer("[FTT] Error: Could not find full message phrases!!!");
				return Plugin_Continue;
			}
			fullMessagePhraseList.GetString(GetRandomInt(0, fullMessagePhraseList.Length - 1), message, MAX_PHRASE_LENGTH);
		}
		if(Trolls[profanityID].activeFlagClients[client] % 2) {
			CPrintToChat(client, "{blue}%N {default}:  %s", client, sArgs);
			for(int i = 1; i <= MaxClients; i++) {
				if(IsClientConnected(i) && IsClientInGame(i) && i != client) {
					CPrintToChat(i, "{blue}%N {default}:  %s", client, message);
				}
			}
		} else {
			CPrintToChatAll("{blue}%N {default}:  %s", client, message);
		}
		PrintToServer("%N: %s", client, sArgs);
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

public Action Event_ItemPickup(int client, int weapon) {
	if(IsTrollActive(client, "No Pickup")) {
		return Plugin_Stop;
	}else{
		static char wpnName[64];
		GetEdictClassname(weapon, wpnName, sizeof(wpnName));
		if(StrContains(wpnName, "rifle") > -1 
			|| StrContains(wpnName, "smg") > -1 
			|| StrContains(wpnName, "weapon_grenade_launcher") > -1 
			|| StrContains(wpnName, "sniper") > -1
			|| StrContains(wpnName, "shotgun") > -1
		) {
			//If 4: Only UZI, if 5: Can't switch.
			if(IsTrollActive(client, "UziRules")) {
				static char currentWpn[32];
				GetClientWeaponName(client, 0, currentWpn, sizeof(currentWpn));
				if(StrEqual(wpnName, "weapon_smg", true)) {
					return Plugin_Continue;
				} else if(StrEqual(currentWpn, "weapon_smg", true)) {
					return Plugin_Stop;
				}else{
					int flags = GetCommandFlags("give");
					SetCommandFlags("give", flags & ~FCVAR_CHEAT);
					FakeClientCommand(client, "give smg");
					SetCommandFlags("give", flags);
					return Plugin_Stop;
				}
			}else if(IsTrollActive(client, "Primary Disable")) {
				return Plugin_Stop;
			}
			return Plugin_Continue;
		}else{
			return Plugin_Continue;
		}
	}
}

public Action OnPlayerRunCmd(int client, int& buttons, int& impulse, float vel[3], float angles[3], int& weapon, int& subtype, int& cmdnum, int& tickcount, int& seed, int mouse[2]) {
	if(g_bPendingItemGive[client] && !(buttons & IN_ATTACK2)) {
		int target = GetClientAimTarget(client, true);
		if(target > -1) {
			buttons |= IN_ATTACK2;
			RequestFrame(StopItemGive, client);
			return Plugin_Changed;
		}
		return Plugin_Continue;
	}
	static int invertedTrollIndex;
	if(invertedTrollIndex <= 0) {
		invertedTrollIndex = GetTrollID("Inverted Controls");
	}
	if(IsTrollActiveByRawID(client, invertedTrollIndex)) {
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
	if(attacker > 0 && attacker <= MaxClients && IsClientInGame(attacker) && IsPlayerAlive(attacker)) {
		if(g_PendingBanTroll[attacker] > 0 && GetClientTeam(attacker) == 2 && GetClientTeam(victim) == 2) {
			
			return Plugin_Stop;
		}
		if(IsTrollActive(victim, "Damage Boost")) {
			damage * 2;
			return Plugin_Changed;
		} else if(Trolls[reverseFF].IsActive(attacker) && attacker != victim && GetClientTeam(attacker) != GetClientTeam(victim)) {
			float returnDmg = damage; //default is 1:1
			if(Trolls[reverseFF].activeFlagClients[attacker] & 4) {
				returnDmg /= 2.0;
			} else if(Trolls[reverseFF].activeFlagClients[attacker] & 2) {
				returnDmg *= 2.0;
			}
			SDKHooks_TakeDamage(attacker, attacker, attacker, returnDmg, damagetype, -1);
			damage = 0.0;
			return Plugin_Changed;
		}
	}
	return Plugin_Continue;
}

public Action SoundHook(int[] clients, int& numClients, char sample[PLATFORM_MAX_PATH], int& entity, int& channel, float& volume, int& level, int& pitch, int& flags, char[] soundEntry, int& seed) {
	if(lastButtonUser > -1 && StrEqual(sample, "npc/mega_mob/mega_mob_incoming.wav")) {
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
			static int honkID;
			if(honkID == 0) {
				honkID = GetTrollID("Honk / Meow");
			}
			if(Trolls[honkID].IsActive(entity)) {
				if(Trolls[honkID].activeFlagClients[entity] & 1)
					strcopy(sample, sizeof(sample), "player/footsteps/clown/concrete1.wav");
				else if(Trolls[honkID].activeFlagClients[entity] & 2)
					strcopy(sample, sizeof(sample), "custom/meow1.mp3");
				else return Plugin_Continue;
				return Plugin_Changed;
			} else if(IsTrollActive(entity, "Vocalize Gag")) {
				return Plugin_Handled;
			}
		}
		
	}
	return Plugin_Continue;
}

public Action Event_WitchVictimSet(Event event, const char[] name, bool dontBroadcast) {
	int witch = event.GetInt("witchid");
	float closestDistance, survPos[3], witchPos[3];
	GetEntPropVector(witch, Prop_Send, "m_vecOrigin", witchPos); 
	int closestClient = -1;
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i)) {
			//Ignore incapped players if hWitchIgnoreIncapp turned on:
			if(IsPlayerIncapped(i) && !hWitchTargetIncapp.BoolValue) {
				continue;
			}
			
			if(IsTrollActive(i, "Witch Magnet")) {
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