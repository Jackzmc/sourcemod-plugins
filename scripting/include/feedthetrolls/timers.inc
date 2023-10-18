
Action Timer_ThrowTimer(Handle timer, int client) {
	if(!IsClientInGame(client)) {
		Trolls[t_throwItAllIndex].timerHandles[client] = null;
		return Plugin_Stop;
	}
	ThrowAllItems(client);
	return Plugin_Continue;
}
int instantCommonRef[MAXPLAYERS+1];

Action Timer_RandomVelocity(Handle h, int client) {
	if(!IsClientInGame(client)) {
		Trolls[t_randomizeVelocityIndex].timerHandles[client] = null;
		return Plugin_Stop;
	}
	float bounds = 50.0;
	if(Trolls[t_randomizeVelocityIndex].activeFlagClients[client] & 2) bounds = 100.0;
	else if(Trolls[t_randomizeVelocityIndex].activeFlagClients[client] & 4) bounds = 200.0;
	else if(Trolls[t_randomizeVelocityIndex].activeFlagClients[client] & 8) bounds = 500.0;
	else if(Trolls[t_randomizeVelocityIndex].activeFlagClients[client] & 16) bounds = 1000.0;
	float vel[3];
	GetEntPropVector(client, Prop_Data, "m_vecVelocity", vel);
	vel[0] += GetRandomFloat(-bounds, bounds);
	vel[1] += GetRandomFloat(-bounds, bounds);
	vel[2] += GetRandomFloat(-20.0, 100.0);
	SetAbsVelocity(client, vel);
	return Plugin_Continue;
}

Action Timer_Main(Handle timer) {
	static int loopTick;

	static int slowDrainIndex;
	if(!slowDrainIndex) slowDrainIndex = GetTrollID("Slow Drain");
	static int tempHealthQuickDrainIndex;
	if(!tempHealthQuickDrainIndex) tempHealthQuickDrainIndex = GetTrollID("Temp Health Quick Drain");
	static int swarmIndex;
	if(!swarmIndex) swarmIndex = GetTrollID("Swarm");
	static int instantCommonIndex;
	if(!instantCommonIndex) instantCommonIndex = GetTrollID("Instant Commons");
	static int randomizeAmmoIndex;
	if(!randomizeAmmoIndex) randomizeAmmoIndex = GetTrollID("Randomize Clip Ammo");

	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == 2) {
			if(Trolls[t_randomizeAnglesIndex].IsActive(i)) {
				float chance = 0.10;
				if(Trolls[t_randomizeAnglesIndex].activeFlagClients[i] & 2) chance = 0.35;
				else if(Trolls[t_randomizeAnglesIndex].activeFlagClients[i] & 4) chance = 0.58;
				else if(Trolls[t_randomizeAnglesIndex].activeFlagClients[i] & 8) chance = 0.90;
				else if(Trolls[t_randomizeAnglesIndex].activeFlagClients[i] & 16) chance = 1.00;
				if(GetURandomFloat() < chance) {
					float ang[3];
					ang[0] = GetRandomFloat(-180.0, 180.0);
					ang[1] = GetRandomFloat(-180.0, 180.0);
					TeleportEntity(i, NULL_VECTOR, ang, NULL_VECTOR);
				}
			}
			if(Trolls[t_randomizeVelocityIndex].IsActive(i)) {
				float bounds = 50.0;
				if(Trolls[t_randomizeVelocityIndex].activeFlagClients[i] & 2) bounds = 100.0;
				else if(Trolls[t_randomizeVelocityIndex].activeFlagClients[i] & 4) bounds = 200.0;
				else if(Trolls[t_randomizeVelocityIndex].activeFlagClients[i] & 8) bounds = 500.0;
				else if(Trolls[t_randomizeVelocityIndex].activeFlagClients[i] & 16) bounds = 1000.0;
				float vel[3];
				GetEntPropVector(i, Prop_Data, "m_vecVelocity", vel);
				vel[0] += GetRandomFloat(-bounds, bounds);
				vel[1] += GetRandomFloat(-bounds, bounds);
				vel[2] += GetRandomFloat(-100.0, 150.0);
				SetAbsVelocity(i, vel);
			}
			if(Trolls[slowDrainIndex].IsActive(i)) {
				if(loopTick % 4 == 0) {
					int hp = GetClientHealth(i);
					if(hp > 50) {
						SetEntProp(i, Prop_Send, "m_iHealth", hp - 1); 
					}
				}
			}
			if(Trolls[tempHealthQuickDrainIndex].IsActive(i)) {
				if(loopTick % 3 == 0) {
					float bufferTime = GetEntPropFloat(i, Prop_Send, "m_healthBufferTime");
					float tempHealth = L4D_GetTempHealth(i);
					if(tempHealth > 0.0) {
						SetEntPropFloat(i, Prop_Send, "m_healthBufferTime", bufferTime - 7.0); 
					}
				}
			}
			if(Trolls[swarmIndex].IsActive(i)) {
				L4D2_RunScript("RushVictim(GetPlayerFromUserID(%d), %d)", GetClientUserId(i), 15000);
			} 
			if(Trolls[t_slipperyShoesIndex].IsActive(i) && Trolls[t_slipperyShoesIndex].activeFlagClients[i] & 1) {
				if(GetRandomFloat() <= 0.4) {
					L4D_StaggerPlayer(i, i, NULL_VECTOR);
				}
			}  
			if(Trolls[instantCommonIndex].IsActive(i)) {
				int common = EntRefToEntIndex(instantCommonRef[i]);
				if(common <= 0 || !IsValidEntity(common)) {
					static float pos[3];
					GetHorizontalPositionFromClient(i, Trolls[instantCommonIndex].activeFlagClients[i] & 1 ? -40.0 : 40.0, pos);
					common = L4D_SpawnCommonInfected(pos);
					instantCommonRef[i] = EntIndexToEntRef(common);
				}
				SetEntPropEnt(common, Prop_Send, "m_clientLookatTarget", i);
				SetEntProp(common, Prop_Send, "m_nSequence", 96);
			} 
			if(loopTick % 60 && Trolls[randomizeAmmoIndex].IsActive(i)) {
				int primaryWpn = GetPlayerWeaponSlot(i, 0);
				if(primaryWpn > 0) {
					int maxCap = GetEntProp(primaryWpn, Prop_Send, "m_iClip1");
					SetEntProp(primaryWpn, Prop_Send, "m_iClip1", GetRandomInt(0, maxCap));
				}
			}
			if(Trolls[t_vomitPlayerIndex].IsActive(i)) {
				if(loopTick % 4 == 0) {
					L4D_CTerrorPlayer_OnVomitedUpon(i, i);
				}
			}
			if(Trolls[t_shakeyCameraIndex].IsActive(i)) {
				float amplitude = 1.0;
				float freq = 1.0;
				if(Trolls[t_shakeyCameraIndex].activeFlagClients[i] & 1) { 
					amplitude = 1.0;
					freq = 1.0;
				} else if(Trolls[t_shakeyCameraIndex].activeFlagClients[i] & 2) { 
					amplitude = 5.0;
					freq = 5.0;
				} else if(Trolls[t_shakeyCameraIndex].activeFlagClients[i] & 4) { 
					amplitude = 20.0;
					freq = 20.0;
				} else if(Trolls[t_shakeyCameraIndex].activeFlagClients[i] & 8) { 
					amplitude = 50.0;
					freq = 50.0;
				} else if(Trolls[t_shakeyCameraIndex].activeFlagClients[i] & 16) { 
					amplitude = 100.0;
					freq = 200.0;
				}
				ShakePlayer(i, amplitude, freq, MAIN_TIMER_INTERVAL_S + 2.0);
			}
			if(Trolls[t_slotRouletteIndex].IsActive(i) && Trolls[t_slotRouletteIndex].activeFlagClients[i] & 8) {
				float chance = 1.0;
				if(Trolls[t_slotRouletteIndex].activeFlagClients[i] & 16) { 
					chance = 0.05;
				} else if(Trolls[t_slotRouletteIndex].activeFlagClients[i] & 32) { 
					chance = 0.2;
				} else if(Trolls[t_slotRouletteIndex].activeFlagClients[i] & 64) { 
					chance = 0.4;
				}

				if(GetURandomFloat() < chance) {
					SetSlot(i, -1);
				}
			}
			if(Trolls[t_hideHUDIndex].IsActive(i)) {
				HideHUDRandom(i);
			}
		}
	}
	if(++loopTick >= 60) {
		loopTick = 0;
	}
	return Plugin_Continue;
}
Action Timer_SlotRoulette(Handle h, int client) {
	if(!IsClientInGame(client)) {
		Trolls[t_slotRouletteIndex].timerHandles[client] = null;
		return Plugin_Stop;
	}
	if(Trolls[t_slotRouletteIndex].activeFlagClients[client] & 8) {
		float chance = 1.0;
		if(Trolls[t_slotRouletteIndex].activeFlagClients[client] & 16) { 
			chance = 0.1;
		} else if(Trolls[t_slotRouletteIndex].activeFlagClients[client] & 32) { 
			chance = 0.3;
		} else if(Trolls[t_slotRouletteIndex].activeFlagClients[client] & 64) { 
			chance = 0.5;
		}

		if(GetURandomFloat() < chance) {
			SetSlot(client, -1);
		}
	}
	return Plugin_Continue;
}
Action Timer_GivePistol(Handle timer, int user) {
	int client = GetClientOfUserId(user);
	if(client > 0) {
		int flags = GetCommandFlags("give");
		SetCommandFlags("give", flags & ~FCVAR_CHEAT);
		FakeClientCommand(client, "give pistol");
		SetCommandFlags("give", flags);
	}
	return Plugin_Handled;
}

Action Timer_ThrowWeapon(Handle timer, Handle pack) {
	ResetPack(pack);
	float dest[3];
	dest[0] = ReadPackFloat(pack);
	dest[1] = ReadPackFloat(pack);
	dest[2] = ReadPackFloat(pack);
	int slot = ReadPackCell(pack);
	int victim = ReadPackCell(pack);

	int wpnRef = GetPlayerWeaponSlot(victim, slot);
	if(wpnRef != -1) {
		int wpn = EntRefToEntIndex(wpnRef);
		if(wpn != INVALID_ENT_REFERENCE) {
			if(slot == 1) {
				static char name[16];
				GetEdictClassname(wpn, name, sizeof(name));
				if(!StrEqual(name, "weapon_pistol", false)) {
					SDKHooks_DropWeapon(victim, wpn, dest);
					CreateTimer(0.2, Timer_GivePistol, GetClientUserId(victim));
				}
			}else 
				SDKHooks_DropWeapon(victim, wpn, dest);
		}
	}
	return Plugin_Handled;
}

Action Timer_ResetAutoPunish(Handle timer, int user) {
	int client = GetClientOfUserId(user);
	if(client) {
		if(hAutoPunish.IntValue & 2 == 2) 
			DisableTroll(client, "Special Magnet");
		if(hAutoPunish.IntValue & 1 == 1) 
			DisableTroll(client, "Tank Magnet");
	}
	return Plugin_Handled;
}

Action Timer_NextWitchSet(Handle timer, DataPack pack) {
	pack.Reset();
	int client = GetClientOfUserId(pack.ReadCell());
	int witch = pack.ReadCell();
	SetWitchTarget(witch, client);
	return Plugin_Handled;
}

Action Timer_KickBot(Handle timer, int client) {
	if(IsClientInGame(client) && !IsClientInKickQueue(client) && IsFakeClient(client)) {
		KickClient(client);
	}
	return Plugin_Handled;
}

Action Timer_Delete(Handle h, int id) {
	if(IsValidEntity(id))
		AcceptEntityInput(id, "Kill");
	return Plugin_Handled;
}

Action Timer_ShootReverse(Handle h, DataPack pack) {
	pack.Reset();
	int attacker = pack.ReadCell();
	int target = pack.ReadCell();
	int weapon = pack.ReadCell();
	int ammo = pack.ReadCell();
	

	if(!IsClientConnected(target) || !IsClientConnected(attacker) || attacker > MaxClients || target > MaxClients) return Plugin_Stop;
	static float targetPos[3], botAngles[3], botPosition[3];
	GetClientAbsOrigin(attacker, targetPos);
	GetClientAbsAngles(attacker, botAngles);
	GetClientAbsOrigin(attacker, botPosition);

	botAngles[1] = RadToDeg(ArcTangent2( botPosition[1] - targetPos[1], botPosition[0] - targetPos[0])) + 180.0;
	TeleportEntity(attacker, NULL_VECTOR, botAngles, NULL_VECTOR);	
	pdata[attacker].shootAtLoops--;
	if(IsValidEntity(weapon))
		SetEntProp(weapon, Prop_Send, "m_iClip1", ammo);
	if(pdata[attacker].shootAtLoops > 0 && GetClientRealHealth(target) > pdata[target].shootAtTargetHealth) {
		return Plugin_Continue;
	} else {
		pdata[attacker].shootAtTarget = 0;
		pdata[attacker].shootAtLoops = 0;
		pdata[attacker].shootAtTargetHealth = 0;
		return Plugin_Stop;
	}
}
// We check if the special never spawned (g_iSpId never advances, and run the next in queue)
// Prevents the queue from stalling
Action Timer_CheckSpecialSpawned(Handle h, int id) {
	if(g_iSpId == id) {
		PrintToServer("[FTT] Special did not spawn in time, continuing.");
		g_iSpId++;
		ProcessSpecialQueue();
	}
	return Plugin_Handled;
}

Action Timer_CheckIsInSpit(Handle h, int userid) {
	int client = GetClientOfUserId(userid);
	if(client && GetGameTime() - pdata[userid].lastInSpitTime > 3.0) {
		SetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue", 1.0);
		pdata[client].flags &= ~view_as<int>(Flag_HasSpitTimer);
		return Plugin_Stop;
	}
	return Plugin_Continue;
}

float CHARGER_CHECK_MIN[3] = { -15.0, -15.0, 2.0};
float CHARGER_CHECK_MAX[3] = { 15.0, 15.0, 20.0 };

Action Timer_CheckForChargerOpportunity(Handle h, int userid) {
	int client = GetClientOfUserId(userid);
	if(client) {
		int activator = GetClientOfUserId(pdata[client].smartChargeActivator);
		if(!activator) {
			pdata[client].smartChargeActivator = 0;
		}
		float pos[3], ang[3], endPos[3], spawnPos[3];
		GetClientAbsOrigin(client, pos);
		GetClientEyeAngles(client, ang);

		GetHorizontalPositionFromOrigin(pos, ang, -150.0, endPos);
		TR_TraceHullFilter(endPos, pos, CHARGER_CHECK_MIN, CHARGER_CHECK_MAX, MASK_SOLID, Filter_CheckChargerValid, client);
		if(!TR_DidHit()) {
			spawnPos = endPos;
			GetHorizontalPositionFromOrigin(pos, ang, 500.0, endPos);
			TR_TraceHullFilter(endPos, pos, CHARGER_CHECK_MIN, CHARGER_CHECK_MAX, MASK_SOLID, Filter_CheckChargerValid, client);
			if(!TR_DidHit()) {
				SpawnSpecialAtPosition(Special_Charger, spawnPos, ang, client, view_as<int>(Special_AlwaysTarget));
				if(activator) PrintToChat(activator, "Auto charge %N successfully after %d tries", client, pdata[client].smartChargeAttempts);
				pdata[client].smartChargeAttempts = 0;
				pdata[client].smartChargeActivator = 0;
				return Plugin_Stop;
			}
		}
		if(++pdata[client].smartChargeAttempts > pdata[client].smartChargeMaxAttempts) {
			if(activator) PrintToChat(activator, "Auto charge timed out after %d attempts", pdata[client].smartChargeAttempts);
			pdata[client].smartChargeAttempts = 0;
			pdata[client].smartChargeActivator = 0;
			DisableTroll(client, "Smart Charge");
			return Plugin_Stop;
		}
		return Plugin_Continue;
	}
	return Plugin_Stop;
}

public bool Filter_CheckChargerValid(int entity, int contentsMask, any data) {
	return entity <= 0 || entity >= MaxClients || (entity != data && GetClientTeam(entity) == 2);
}

public Action Timer_UpdateHealTargetPos(Handle h) {
	int healTarget = GetClientOfUserId(healTargetPlayer);
	if(healTarget == 0) {
		PrintToServer("[FTT] Dep Bots: Lost heal target, stopping");
		return Plugin_Stop;
	}
	GetAbsOrigin(healTarget, healTargetPos);
	int bots = 0;
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsFakeClient(i) && pdata[i].flags & view_as<int>(Flag_IsTargettingHealer)) {
			bots++;
			L4D2_RunScript("CommandABot({cmd=1,bot=GetPlayerFromUserID(%d),pos=Vector(%f,%f,%f)})", GetClientUserId(i), healTargetPos[0], healTargetPos[1], healTargetPos[2]);
			int kit = GetPlayerWeaponSlot(i, 3);
			if(kit > -1) {
				SetEntPropEnt(i, Prop_Send, "m_hActiveWeapon", kit);
			}
		}
	}
	return bots > 0 ? Plugin_Continue : Plugin_Stop;
}

Action Timer_SpawnHealBots(Handle h, int max) {
	static int count;
	if(count < max) {
		if(!AddSurvivor()) {
			count = 0;
			CreateTimer(0.5, Timer_SpawnHealBotsPost);
			return Plugin_Stop;
		}
		count++;
		return Plugin_Continue;
	}
	count = 0;
	CreateTimer(0.5, Timer_SpawnHealBotsPost);
	return Plugin_Stop;
}

Action Timer_SpawnHealBotsPost(Handle h) {
	PrintToServer("bots post");
	char classname[32];
	for(int i = 1; i <= MaxClients; i++) {
		if(isCustomSurvivor[i]) {
			int kit = GetPlayerWeaponSlot(i, 3);
			if(kit > 0) {
				GetEntityClassname(kit, classname, sizeof(classname));
				if(StrEqual(classname, "weapon_first_aid_kit")) {
					continue;
				}
			}
			GiveClientWeapon(i, "weapon_first_aid_kit");
			pdata[i].flags &= view_as<int>(Flag_IsTargettingHealer);
		}
	}
	return Plugin_Handled;
}
Action Timer_StopHealBots(Handle h, DataPack pack) {
	pack.Reset();
	int activator = GetClientOfUserId(pack.ReadCell());
	int victim = GetClientOfUserId(pack.ReadCell());
	if(activator) {
		PrintToChat(activator, "Dep bots has expired");
	}
	if(victim) {
		DisableTroll(victim, "Dep Bots");
	}
	StopHealingBots();
	return Plugin_Stop;
}


#define NO_ATTEMPT_MAX_DIST 1000.0
#define NO_ATTEMPT_MAX_DIST_OPT NO_ATTEMPT_MAX_DIST * NO_ATTEMPT_MAX_DIST


Action Timer_WaitForApex(Handle h, int entref) {
	if(!IsValidEntity(entref)) return Plugin_Stop;
	int entity = EntRefToEntIndex(entref);

	static float pos[3];
	GetEntPropVector(entity, Prop_Send, "m_vecOrigin", pos);

	if(entLastHeight[entity] > pos[2]) {
		char classname[32];
		GetEntityClassname(entity, classname, sizeof(classname));

		int target;
		if(StrEqual(classname, "tank_rock") || StrEqual(classname, "spitter_projectile"))
			target = GetRandomThrowableMagnetTarget(ProjType_Specials);
		else if(StrEqual(classname, "prop_physics") || StrEqual(classname, "prop_car_alarm"))
			target = GetRandomThrowableMagnetTarget(ProjType_Cars)
		else {
			int entOwner = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
			target = GetRandomThrowableMagnetTarget(ProjType_Survivors, entOwner);
		}

		if(target > 0) {
			float targetPos[3], vel[3];
			GetClientAbsOrigin(target, targetPos);
			TR_TraceRay(pos, targetPos, MASK_SHOT, RayType_EndPoint);
			if(TR_DidHit()) {
				TR_GetEndPosition(pos);
				if(GetVectorDistance(pos, targetPos, true) >  NO_ATTEMPT_MAX_DIST_OPT) {
					return Plugin_Stop;
				}
			}

			// SetEntityMoveType(entity, MOVETYPE_FLY);
			SetEntityGravity(entity, 0.001);
			float distance = GetVectorDistance(pos, targetPos);
			SubtractVectors(targetPos, pos, vel);
			ScaleVector(vel, 1000.0 / distance);
			TeleportEntity(entity, NULL_VECTOR, NULL_VECTOR, vel);

			CreateTimer(3.0, Timer_ResetGravity, entref);
		}
		return Plugin_Stop;
	}
	entLastHeight[entity] = pos[2];
	return Plugin_Continue;
}

Action Timer_ResetGravity(Handle h, int entref) {
	if(IsValidEntity(entref)) {
		int entity = EntRefToEntIndex(entref);
		SetEntityGravity(entity, 800.0); // could pull from sv_gravity but no ones gonna notice
	}
	return Plugin_Handled;
}
Action Timer_RestoreHud(Handle h, int userid) {
	int client = GetClientOfUserId(userid);
	if(client > 0) {
		SetEntProp(client, Prop_Send, "m_iHideHUD", 0);
	}
	return Plugin_Handled;
}