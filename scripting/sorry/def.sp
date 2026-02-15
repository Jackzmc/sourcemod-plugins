
#define MODEL_CAR "models/props_vehicles/cara_95sedan.mdl"
#define MODEL_CRATE "models/props_junk/wood_crate002a.mdl"
#define SOUND_CAR_ALARM "vehicles/car_alarm/car_alarm2.wav"
#define SOUND_EXPLODE_BOMB "weapons/hegrenade/beep.wav"
#define MODEL_PEANUT "models/props_fairgrounds/Lil'Peanut_cutout001.mdl"
#define MODEL_GNOME "models/props_junk/gnome.mdl"

enum sorryResponseValues {
	Sorry_Accept = 1,
	Sorry_Reject = 0,
	Sorry_RejectSlap = -3,
	Sorry_RejectIncap = -2,
	Sorry_RejectKill = -1,
	Sorry_RejectStealHealth = -5,
	Sorry_RejectCrush = -4,
	Sorry_AcceptSlap = 2,
	Sorry_RejectRockDrop = -6,
	Sorry_RejectSwapPosition = -7,
	Sorry_RejectStealItem = -8,
	Sorry_UnoReverse = 4,
	Sorry_RejectVomit = -10,
	Sorry_RejectIdle = -11,
	Sorry_RejectCharge = -12,
	Sorry_RejectRewind = -13,
	Sorry_RejectConfuse = -14,
	Sorry_ThirdParty = 3,
	Sorry_AcceptAssure = 5,
	Sorry_RejectStealAmmo = -15,
	Sorry_RejectBoxDrop = -16,
	Sorry_RejectBurn = -17,
	Sorry_AcceptHealth = 6,
	Sorry_RejectSpecial = -18,
	Sorry_RejectMakeClown = -19,
	Sorry_RejectTimeout = -20,
	Sorry_RejectGivePitchfork = -21,
	Sorry_RejectDropAll = -22,
	Sorry_RejectHorde = -23,
	Sorry_AcceptImmune = 7,
	Sorry_RejectCarAlarm = -24,
	Sorry_RejectBecomeRandomPeanut = -25,
	Sorry_FakeAccept = 8,
	Sorry_FakeReject = -26,
	Sorry_RejectCloset = -27,
	Sorry_RejectSpin = -28,
	Sorry_RejectBanishToVoid = -29,
	Sorry_AcceptSpeedBoost = 9,
	Sorry_AcceptUltimateSacrifice = 10,
	Sorry_RejectGnome = -30,
	Sorry_RejectBecomeDisgruntled = -31,
	Sorry_RejectInconvenientHealth = -32,
	Sorry_RejectExplode = -33,
	Sorry_AcceptBecomePeanut = 11,
	Sorry_RejectDraw4 = -34,
	Sorry_RejectProp = -35,
	Sorry_RejectKidnap = -36,
	Sorry_RejectSpook = -37,
	Sorry_AcceptFreeRevive = 12
}

#if defined DEBUG_SORRY
bool _debugSorry = true;
#else
bool _debugSorry = false;
#endif

char currentMap[64];
AnyMap g_sorryResponseHandlers;
// After all responses registered, this contains linear list of runcmd forwards for optimization
ArrayList g_onPlayerRunCmdForwards;
ArrayList g_onClientSayCommandForwards;

AnyMap clownLastHonked;

SorryStore_t SorryStore[MAXPLAYERS+1];
methodmap SorryStore_t < StringMap {
	public SorryStore_t(int client) {
		StringMap map = new StringMap();
		map.SetValue("_index", client);
		return view_as<SorryStore_t>(map);
	}

	property int ClientUserId {
		public get() {
			int index = this.Client;
			return GetClientUserId(index);
		}
	}

	property int Client {
		public get() {
			int index;
			if(!this.GetValue("_index", index)) {
				LogError("_index key missing");
			}
			return index;

		}
	}

	public void _setupKeyClear(const char[] key, float ttl) {
		DataPack pack;
		CreateDataTimer(ttl, SorryStore_ClearKey, pack);
		pack.WriteCell(this.ClientUserId);
		pack.WriteCell(strlen(key));
		pack.WriteString(key);
	}

	public void SetValueTemp(const char[] key, int value, float ttl) {
		this.SetValue(key, value);
		this._setupKeyClear(key, ttl);
	}

	public void SetStringTemp(const char[] key, const char[] value, float ttl) {
		this.SetString(key, value);
		this._setupKeyClear(key, ttl);
	}

	/**
	 * Increments the stored value by increment. If not set, defaults to increment
	 */
	public int IncrementValue(const char[] key, int increment) {
		int value = 0;
		this.GetValue(key, value);
		value += increment;
		this.SetValue(key, value);
	}
}

void SorryStore_Setup() {
	for(int i = 1; i <= MaxClients; i++) {
		SorryStore[i] = new SorryStore_t(i);
	}
}
Action SorryStore_ClearKey(Handle h, DataPack pack) {
	pack.Reset();
	int client = GetClientOfUserId(pack.ReadCell());
	if(client == 0) LogError("SorryStore_ClearKey: client invalid");

	int len = pack.ReadCell();
	char[] key = new char[len];
	pack.ReadString(key, len);

	SorryStore[client].Remove(key);
	return Plugin_Handled;
}

int sorryBounds[2];

bool isInSaferoom[MAXPLAYERS+1];

bool isUnderAttack[MAXPLAYERS+1];
float saferoomPos[3]; bool foundSaferoomPos;


#define MAX_SORRY_DATA 4
#define SORRY_NSLOT MAX_SORRY_DATA - 1
#define RECENT_HURT_RECORD_TIME 60.0
#define EVENT_ID_LENGTH 16

enum struct SorryData {
	int victimUserid;
	char eventId[EVENT_ID_LENGTH];
	char hurtType[32];
	float hurtTime; // GetGameTime()
	int dmgType; //DMG_* 

	int GetVictim() {
		if(this.victimUserid == 0) return -1;
		int client = GetClientOfUserId(this.victimUserid);
		if(client > 0 && GetGameTime() - this.hurtTime <= RECENT_HURT_RECORD_TIME) {
			return client;
		}
		return -1;
	}

	bool IsValid() {
		return this.eventId[0] != '\0' || this.GetVictim() > 0;
	}

	void Reset() {
		this.victimUserid = 0;
		this.eventId[0] = '\0';
		this.hurtType[0] = '\0';
		this.dmgType = 0;
	}

	void SetEvent(const char[] event) {
		strcopy(this.eventId, EVENT_ID_LENGTH, event);
	}
}
enum struct SorryResponse {
	int id;
	char label[32];
	float chance;
	char eventId[EVENT_ID_LENGTH];
}
ArrayList g_sorryResponses;


SorryData sorryData[MAXPLAYERS+1][MAX_SORRY_DATA];

AnyMap g_runAwayParents;