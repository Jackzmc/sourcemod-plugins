
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
	static int loop;
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i) && IsClientInGame(i) && IsPlayerAlive(i)) {
			if(IsTrollActive(i, "Slow Drain")) {
				if(loop % 4 == 0) {
					int hp = GetClientHealth(i);
					if(hp > 50) {
						SetEntProp(i, Prop_Send, "m_iHealth", hp - 1); 
					}
				}
			}else if(IsTrollActive(i, "Temp Health Quick Drain")) {
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