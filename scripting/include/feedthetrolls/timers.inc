public Action Timer_ThrowTimer(Handle timer) {
	int count = 0;
	for(int i = 1; i < MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && IsPlayerAlive(i) && IsTrollActive(i, "ThrowItAll")) {
			ThrowAllItems(i);
			count++;
		}
	}
	return count > 0 ? Plugin_Continue : Plugin_Stop;
}

public Action Timer_Main(Handle timer) {
	static int loop;
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && IsPlayerAlive(i)) {
			if(IsTrollActive(i, "SlowDrain")) {
				if(loop % 4 == 0) {
					int hp = GetClientHealth(i);
					if(hp > 50) {
						SetEntProp(i, Prop_Send, "m_iHealth", hp - 1); 
					}
				}
			}else if(IsTrollActive(i, "TempHealthQuickDrain")) {
				if(loop % 2 == 0) {
					float bufferTime = GetEntPropFloat(i, Prop_Send, "m_healthBufferTime");
					float buffer = GetEntPropFloat(i, Prop_Send, "m_healthBuffer");
					float tempHealth = GetTempHealth(i);
					if(tempHealth > 0.0) {
						PrintToConsole(i, "%f | %f %f", tempHealth, buffer, bufferTime);
						//SetEntPropFloat(i, Prop_Send, "m_healthBuffer", buffer - 10.0); 
						SetEntPropFloat(i, Prop_Send, "m_healthBufferTime", bufferTime - 7.0); 
					}
				}
			}else if(IsTrollActive(i, "Swarm")) {
				L4D2_RunScript("RushVictim(GetPlayerFromUserID(%d), %d)", GetClientUserId(i), 15000);
			}
		}
	}
	if(++loop >= 60) {
		loop = 0;
	}
	return Plugin_Continue;
}

public Action Timer_GivePistol(Handle timer, int client) {
	int flags = GetCommandFlags("give");
	SetCommandFlags("give", flags & ~FCVAR_CHEAT);
	FakeClientCommand(client, "give pistol");
	SetCommandFlags("give", flags|FCVAR_CHEAT);
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
					CreateTimer(0.2, Timer_GivePistol, victim);
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
			DisableTroll(client, "SpecialMagnet");
		if(hAutoPunish.IntValue & 1 == 1) 
			DisableTroll(client, "TankMagnet");
	}
}

public Action Timer_NextWitchSet(Handle timer, DataPack pack) {
	pack.Reset();
	int client = GetClientOfUserId(pack.ReadCell());
	int witch = pack.ReadCell();
	SetWitchTarget(witch, client);
}