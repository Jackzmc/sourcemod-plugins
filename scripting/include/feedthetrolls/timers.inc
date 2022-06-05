
public Action Timer_ThrowTimer(Handle timer) {
	int count = 0;
	for(int i = 1; i < MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && IsPlayerAlive(i) && IsTrollActive(i, "Throw It All")) {
			ThrowAllItems(i);
			count++;
		}
	}
	return count > 0 ? Plugin_Continue : Plugin_Stop;
}

public Action Timer_Main(Handle timer) {
	static int loopTick;
	static int slowDrainIndex;
	if(!slowDrainIndex) slowDrainIndex = GetTrollID("Slow Drain");
	static int tempHealthQuickDrainIndex;
	if(!tempHealthQuickDrainIndex) tempHealthQuickDrainIndex = GetTrollID("Temp Health Quick Drain");
	static int swarmIndex;
	if(!swarmIndex) swarmIndex = GetTrollID("Swarm");

	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && IsPlayerAlive(i)) {
			if(Trolls[slowDrainIndex].IsActive(i)) {
				if(loopTick % 4 == 0) {
					int hp = GetClientHealth(i);
					if(hp > 50) {
						SetEntProp(i, Prop_Send, "m_iHealth", hp - 1); 
					}
				}
			}else if(Trolls[tempHealthQuickDrainIndex].IsActive(i)) {
				if(loopTick % 2 == 0) {
					float bufferTime = GetEntPropFloat(i, Prop_Send, "m_healthBufferTime");
					float buffer = GetEntPropFloat(i, Prop_Send, "m_healthBuffer");
					float tempHealth = GetTempHealth(i);
					if(tempHealth > 0.0) {
						PrintToConsole(i, "%f | %f %f", tempHealth, buffer, bufferTime);
						//SetEntPropFloat(i, Prop_Send, "m_healthBuffer", buffer - 10.0); 
						SetEntPropFloat(i, Prop_Send, "m_healthBufferTime", bufferTime - 7.0); 
					}
				}
			}else if(Trolls[swarmIndex].IsActive(i)) {
				L4D2_RunScript("RushVictim(GetPlayerFromUserID(%d), %d)", GetClientUserId(i), 15000);
			} else if(Trolls[slipperyShoesIndex].IsActive(i) && Trolls[slipperyShoesIndex].activeFlagClients[i] & 1) {
				if(GetRandomFloat() <= 0.4) {
					L4D_StaggerPlayer(i, i, NULL_VECTOR);
				}
			}
		}
	}
	if(++loopTick >= 60) {
		loopTick = 0;
	}
	return Plugin_Continue;
}

public Action Timer_GivePistol(Handle timer, int user) {
	int client = GetClientOfUserId(user);
	if(client > 0) {
		int flags = GetCommandFlags("give");
		SetCommandFlags("give", flags & ~FCVAR_CHEAT);
		FakeClientCommand(client, "give pistol");
		SetCommandFlags("give", flags);
	}
}

public Action Timer_ThrowWeapon(Handle timer, Handle pack) {
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
}

public Action Timer_ResetAutoPunish(Handle timer, int user) {
	int client = GetClientOfUserId(user);
	if(client) {
		if(hAutoPunish.IntValue & 2 == 2) 
			DisableTroll(client, "Special Magnet");
		if(hAutoPunish.IntValue & 1 == 1) 
			DisableTroll(client, "Tank Magnet");
	}
}

public Action Timer_NextWitchSet(Handle timer, DataPack pack) {
	pack.Reset();
	int client = GetClientOfUserId(pack.ReadCell());
	int witch = pack.ReadCell();
	SetWitchTarget(witch, client);
}

public Action Timer_KickBot(Handle timer, int client) {
	if(IsClientInGame(client) && (!IsClientInKickQueue(client))) {
		if(IsFakeClient(client)) KickClient(client);
	}
}

public Action Timer_Delete(Handle h, int id) {
	AcceptEntityInput(id, "Kill");
}

public Action Timer_ShootReverse(Handle h, DataPack pack) {
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
	shootAtTargetLoops[attacker]--;
	if(IsValidEntity(weapon))
		SetEntProp(weapon, Prop_Send, "m_iClip1", ammo);
	if(shootAtTargetLoops[attacker] > 0 && GetClientRealHealth(target) > shootAtTargetHP[target]) {
		return Plugin_Continue;
	} else {
		shootAtTargetLoops[attacker] = 0;
		shootAtTarget[attacker] = 0;
		shootAtTargetHP[target] = 0;
		return Plugin_Stop;
	}
}

public Action Timer_CheckSpecialSpawned(Handle h, int id) {
	if(g_iSpId == id) {
		PrintToServer("[FTT] Special did not spawn in time, continuing.");
		g_iSpId++;
		ProcessSpecialQueue();
	}
}

public Action Timer_CheckIsInSpit(Handle h, int userid) {
	int client = GetClientOfUserId(userid);
	if(client && GetGameTime() - iLastInSpit[userid] > 3.0) {
		SetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue", 1.0);
		return Plugin_Stop;
	}
	return Plugin_Continue;
}