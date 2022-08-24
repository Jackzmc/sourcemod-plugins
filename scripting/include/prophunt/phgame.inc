static int mapChangeMsgTicks = 5;

int GetColorInt(int r, int g, int b) {
	int color = r;
	color += 256 * g;
	color += 65536 * b;
	return color;
}

Action Timer_ChangeMap(Handle h) {
	PrintToChatAll("Changing map to %s in %d seconds", nextRoundMap, mapChangeMsgTicks);
	if(mapChangeMsgTicks-- == 0) {
		ForceChangeLevel(nextRoundMap, "GuessWhoMapSelect");
		nextRoundMap[0] = '\0';
		return Plugin_Stop;
	}
	return Plugin_Continue;
}

void ChangeMap(const char map[64], int time = 5) {
	strcopy(nextRoundMap, sizeof(nextRoundMap), map);
	mapChangeMsgTicks = time;
	CreateTimer(1.0, Timer_ChangeMap, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

bool FindSpawnPosition(float pos[3], bool includePlayers = true) {
	if(includePlayers) {
		for(int i = 1; i <= MaxClients; i++) {
			if(IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i)) {
				GetClientAbsOrigin(i, pos);
				return true;
			}
		}
	}
	int entity = INVALID_ENT_REFERENCE;
	while ((entity = FindEntityByClassname(entity, "info_player_start")) != INVALID_ENT_REFERENCE) {
		GetEntPropVector(entity, Prop_Send, "m_vecOrigin", pos);
		return true;
	}
	return false;
}

static char buffer[128];

bool isSeeker[MAXPLAYERS+1];

methodmap PropHuntGame < BaseGame {

	property int Seekers {
		public get() {
			int count = 0;
			for(int i = 1; i <= MaxClients; i++) {
				if(isSeeker[i]) count++;
			}
			return count;
		}
	}

	public bool IsSeeker(int client) {
		return isSeeker[client];
	}

	public void SetSeeker(int client, bool value) {
		isSeeker[client] = value;
	}

	public void ClearSeekers() {
		for(int i = 1; i <= MaxClients; i++) {
			isSeeker[i] = false;
		}
	}

	property int Tick {
		public get() {
			if(!isEnabled) return -1;
			L4D2_GetVScriptOutput("g_ModeScript.MutationState.Tick", buffer, sizeof(buffer));
			int value = -1;
			if(StringToIntEx(buffer, value) > 0) {
				return value;
			} else {
				return -1;
			}
		}
		public set(int tick) {
			Format(buffer, sizeof(buffer), "g_ModeScript.MutationState.Tick = %d", tick);
			L4D2_ExecVScriptCode(buffer);
		}
	}

	property GameState State {
		public get() {
			if(!isEnabled) return State_Unknown;
			L4D2_GetVScriptOutput("g_ModeScript.MutationState.State", buffer, sizeof(buffer));
			int stage = 0;
			if(StringToIntEx(buffer, stage) > 0) {
				return view_as<GameState>(stage);
			} else {
				return State_Unknown;
			}
		}
		public set(GameState state) {
			if(isEnabled) {
				Format(buffer, sizeof(buffer), "g_ModeScript.MutationState.State = %d", view_as<int>(state));
				L4D2_ExecVScriptCode(buffer);
			}
		}
	}

	property int MapTime {
		public get() {
			L4D2_GetVScriptOutput("g_ModeScript.MutationState.MaxTime", buffer, sizeof(buffer));
			return StringToInt(buffer);
		}
		public set(int seconds) {
			Format(buffer, sizeof(buffer), "g_ModeScript.MutationState.MaxTime = %d", seconds);
			L4D2_ExecVScriptCode(buffer);
			if(timesUpTimer != null) {
				float remaining = float(seconds) - float(this.Tick);
				delete timesUpTimer;
				timesUpTimer = CreateTimer(remaining, Timer_TimesUp, _, TIMER_FLAG_NO_MAPCHANGE);
			}
		}
	}

	public void Start() {

	}

	public void End(GameState state) {
		this.State = state;
		CreateTimer(5.0, Timer_ResetAll);
	}

	public void Cleanup(bool noClearInv = false) {
		DeleteCustomEnts();
	}

	public int _FindSeeker() {
		if(!isEnabled) return -1;
		L4D2_GetVScriptOutput("g_ModeScript.MutationState.CurrentSeeker && \"GetPlayerUserId\" in g_ModeScript.MutationState.CurrentSeeker ? g_ModeScript.MutationState.CurrentSeeker.GetPlayerUserId() : -1", buffer, sizeof(buffer));
		int uid = StringToInt(buffer);
		if(uid > 0) {
			return GetClientOfUserId(uid);
		} else {
			Game.Debug("Mutation has no seeker, manually attempting to find seeker");
			for(int i = 1; i <= MaxClients; i++) {
				if(IsClientConnected(i) && IsClientInGame(i)) {
					int entity = GetPlayerWeaponSlot(i, 1);
					if(entity > -1 && GetEntityClassname(entity, buffer, sizeof(buffer)) && StrEqual(buffer, "melee")) {
						GetEntPropString(entity, Prop_Data, "m_strMapSetScriptName", buffer, sizeof(buffer));
						if(StrEqual(buffer, "smg")) {
							return i;
						}
					}
				}
			}
		}
		Game.Debug("All attempts to find a seeker failed");
		return -1;
	}


	public void ForceSetSeeker(int client, bool ignoreBalance = false) { 
		ignoreSeekerBalance = true;
		this.Seeker = client;
	}

	public bool TeleportToSpawn(int client) {
		if(mapConfig.hasSpawnpoint) {
			TeleportEntity(client, mapConfig.spawnpoint, NULL_VECTOR, NULL_VECTOR);
			return true;
		} else {
			float pos[3];
			if(FindSpawnPosition(pos)) {
				return false;
			}
			TeleportEntity(client, pos, NULL_VECTOR, NULL_VECTOR);
		}
		return false;
	}

	public void TeleportAllToStart() {
		if(mapConfig.hasSpawnpoint) {
			PrintToServer("[GuessWho] Teleporting all players to provided spawnpoint (%f %f %f)", mapConfig.spawnpoint[0], mapConfig.spawnpoint[1], mapConfig.spawnpoint[2]);
			for(int i = 1; i <= MaxClients; i++) {
				if(IsClientConnected(i) && IsClientInGame(i)) {
					this.TeleportToSpawn(i);
				}
			}
		} else {
			PrintToServer("[GuessWho] Warn: No spawnpoint found (provided or map spawn)");
		}
	}

	// Ignores seeker
	property int AlivePlayers {
		public get() {
			int amount = 0;
			for(int i = 1; i <= MaxClients; i++) {
				if(!this.IsSeeker(i) && IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i) && !IsFakeClient(i)) {
					amount++;
				}
			}
			return amount;
		}
	}

	public void SetupInventory(int client) {
		ClearInventory(client);
		if(this.IsSeeker(client)) {
			CheatCommand(client, "give", "smg");
		}
	}

	public void SetupPlayer(int client) {
		this.SetupInventory(client);
		SDKHook(client, SDKHook_OnTakeDamageAlive, OnTakeDamageAlive);
	}

	public void UnsetupPlayer(int client) {
		SDKUnhook(client, SDKHook_OnTakeDamageAlive, OnTakeDamageAlive);
	}
}

stock bool ArePlayersJoining() {
	for(int i = 1;  i <= MaxClients; i++) {
		if(IsClientConnected(i) && !IsClientInGame(i)) {
			return true;
		}
	}
	return false;
}

stock void GetHorizontalPositionFromClient(int client, float units, float finalPosition[3]) {
	float pos[3], ang[3];
	GetClientEyeAngles(client, ang);
	GetClientAbsOrigin(client, pos);

	float theta = DegToRad(ang[1]);
	pos[0] += units * Cosine(theta); 
	pos[1] += units * Sine(theta); 
	finalPosition = pos;
}

stock void GetAnglesLookAt(int iClient, int iTarget, float fFinalPos[3]) {
	static float fTargetPos[3]; 
	static float fTargetAngles[3]; 
	static float fClientPos[3]; 
	
	GetEntPropVector(iClient, Prop_Send, "m_vecOrigin", fClientPos);
	GetClientEyePosition(iTarget, fTargetPos);
	GetClientEyeAngles(iTarget, fTargetAngles);
	
	float fVecFinal[3];
	AddInFrontOf(fTargetPos, fTargetAngles, 7.0, fVecFinal);
	MakeVectorFromPoints(fClientPos, fVecFinal, fFinalPos);
	
	GetVectorAngles(fFinalPos, fFinalPos);

	// TeleportEntity(iClient, NULL_VECTOR, fFinalPos, NULL_VECTOR);
}
stock void AddInFrontOf(const float fVecOrigin[3], const float fVecAngle[3], float fUnits, float fOutPut[3])
{
	float fVecView[3]; GetViewVector(fVecAngle, fVecView);
	
	fOutPut[0] = fVecView[0] * fUnits + fVecOrigin[0];
	fOutPut[1] = fVecView[1] * fUnits + fVecOrigin[1];
	fOutPut[2] = fVecView[2] * fUnits + fVecOrigin[2];
}
stock void GetViewVector(const float fVecAngle[3], float fOutPut[3])
{
	fOutPut[0] = Cosine(fVecAngle[1] / (180 / FLOAT_PI));
	fOutPut[1] = Sine(fVecAngle[1] / (180 / FLOAT_PI));
	fOutPut[2] = -Sine(fVecAngle[0] / (180 / FLOAT_PI));
}

stock void LookAtClient(int iClient, int iTarget) {
	static float fTargetPos[3]; 
	static float fTargetAngles[3]; 
	static float fClientPos[3]; 
	static float fFinalPos[3];
	
	GetClientEyePosition(iClient, fClientPos);
	GetClientEyePosition(iTarget, fTargetPos);
	GetClientEyeAngles(iTarget, fTargetAngles);
	
	float fVecFinal[3];
	AddInFrontOf(fTargetPos, fTargetAngles, 7.0, fVecFinal);
	MakeVectorFromPoints(fClientPos, fVecFinal, fFinalPos);
	
	GetVectorAngles(fFinalPos, fFinalPos);

	TeleportEntity(iClient, NULL_VECTOR, fFinalPos, NULL_VECTOR);
}

stock void LookAtPoint(int client, const float targetPos[3]) {
	static float targetAngles[3]; 
	static float clientPos[3]; 
	static float fFinalPos[3];
	
	GetClientEyePosition(client, clientPos);
	GetClientEyeAngles(client, targetAngles);
	
	float fVecFinal[3];
	AddInFrontOf(targetPos, targetAngles, 7.0, fVecFinal);
	MakeVectorFromPoints(clientPos, fVecFinal, fFinalPos);
	
	GetVectorAngles(fFinalPos, fFinalPos);

	TeleportEntity(client, NULL_VECTOR, fFinalPos, NULL_VECTOR);
}


void SetPlayerBlind(int target, int amount) {
	int targets[1];
	targets[0] = target;
	
	int duration = 1536;
	int holdtime = 1536;
	int flags = (amount == 0) ? (0x0001 | 0x0010) : (0x0002 | 0x0008);
	int color[4] = { 0, 0, 0, 0 };
	color[3] = amount;
	
	Handle message = StartMessageEx(g_FadeUserMsgId, targets, 1);
	BfWrite bf = UserMessageToBfWrite(message);
	bf.WriteShort(duration);
	bf.WriteShort(holdtime);
	bf.WriteShort(flags);		
	bf.WriteByte(color[0]);
	bf.WriteByte(color[1]);
	bf.WriteByte(color[2]);
	bf.WriteByte(color[3]);
	EndMessage();
}

#define HIDER_DISTANCE_MAX_SIZE 10


#define MAX_AUTO_VOCALIZATIONS 9
static char AUTO_VOCALIZATIONS[MAX_AUTO_VOCALIZATIONS][] = {
	"PlayerLaugh",
	"PlayerSpotPill",
	"Playerlookout",
	"EatPills",
	"ReviveMeInterrupted",
	"PlayerIncapacitated",
	"PlayerNiceShot",
	"ResponseSoftDispleasureSwear",
	"PlayerAreaClear"
};

enum struct HiderDistQueue {
	int index;
	float list[HIDER_DISTANCE_MAX_SIZE];
	int lastVocalize;

	void AddPos(const float pos[3]) {
		this.list[this.index] = GetVectorDistance(seekerPos, pos);
		if(++this.index == HIDER_DISTANCE_MAX_SIZE) {
			this.index = 0;
		}
	}

	void Clear() {
		for(int i = 0; i < HIDER_DISTANCE_MAX_SIZE; i++) {
			this.list[i] = 0.0;
		}
	}

	float GetAverage() {
		float sum = 0.0;
		for(int i = 0; i < HIDER_DISTANCE_MAX_SIZE; i++) {
			sum += this.list[i];
		}
		return sum / float(HIDER_DISTANCE_MAX_SIZE);
	}

	void Check(int i) {
		if(this.GetAverage() > HIDER_MIN_AVG_DISTANCE_AUTO_VOCALIZE) {
			int time = GetTime();
			if(time - this.lastVocalize > HIDER_AUTO_VOCALIZE_GRACE_TIME) {
				this.lastVocalize = time;
				int index = GetRandomInt(0, MAX_AUTO_VOCALIZATIONS - 1);
				PerformScene(i, AUTO_VOCALIZATIONS[index]);
			}
		}
	}
}

HiderDistQueue distQueue[MAXPLAYERS+1];