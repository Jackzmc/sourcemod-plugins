// Meta
char gamemode[32];
char currentMap[64];
bool isEnabled, lateLoaded;

// Internal State
char currentSet[16] = "default";
char nextRoundMap[64];
bool isNavBlockersEnabled = true, isPropsEnabled = true, isPortalsEnabled = true;

int g_iLaserIndex;

// Gamemode state
bool isPendingPlay[MAXPLAYERS+1];


// PeekCam specifics
PeekCamera PeekCam;
static int seekerCam = INVALID_ENT_REFERENCE;
static bool isViewingCam[MAXPLAYERS+1];
static int seekerTarget;

enum PeekPerspective {
	Cam_Unknown,
	Cam_FirstPerson,
	Cam_ThirdPerson
}

methodmap PeekCamera {
	property int Target {
		public get() {
			return GetClientOfUserId(seekerTarget);
		}
		public set(int client) {
			this.Create();
			seekerTarget = GetClientUserId(client);

			AcceptEntityInput(seekerCam, "ClearParent");
			AcceptEntityInput(seekerCam, "Disable");
		}
	}

	property PeekPerspective Perspective {
		public set(PeekPerspective perspective) {
			this.SetPerspective(perspective);
		}
	}

	public void SetPerspective(PeekPerspective perspective) {
		float pos[3], ang[3];
		int client = this.Target;
		GetClientEyePosition(client, pos);
		GetClientEyeAngles(client, ang);

		if(perspective == Cam_FirstPerson) {
					
			TeleportEntity(seekerCam, pos, ang, NULL_VECTOR);
			SetParent(seekerCam, client);
			SetParentAttachment(seekerCam, "primary", false);
		} else if(perspective == Cam_ThirdPerson) {
			float endPos[3];
			TR_TraceRayFilter(pos, ang, CONTENTS_PLAYERCLIP | MASK_SOLID | MASK_VISIBLE, RayType_Infinite, Filter_IgnoreAll);
			if(TR_DidHit()) {
				TR_GetEndPosition(endPos);
			}
			endPos[2] += 50.0;

			ang[0] = 0.0;
			float deltaA = endPos[0] - pos[0];
			float deltaB = endPos[1] - pos[1];
			float deltaC = endPos[2] - pos[2];
			ang[0] = RadToDeg(ArcTangent(deltaC / GetVectorDistance(endPos, pos, false) ));
			ang[1] = RadToDeg(ArcTangent2(deltaA, deltaB));
			TeleportEntity(seekerCam, endPos, ang, NULL_VECTOR);
		}
	}

	public void SetViewing(int client, bool active) {
		if(seekerCam != INVALID_ENT_REFERENCE) {
			AcceptEntityInput(seekerCam, "Enable", client); // Need to always activate before deactivating to fix a semi-common bug
			if(!active) {
				AcceptEntityInput(seekerCam, "Disable", client);
				AcceptEntityInput(seekerCam, "Kill");
				seekerCam = INVALID_ENT_REFERENCE;
			}
		} else {
			PrintToServer("WARN: SetPeekCamActive(%d, %b) when seekerCam invalid", client, active);
		}
		isViewingCam[client] = active;
	}

	public bool IsViewing(int client) {
		return isViewingCam[client];
	}

	public void Create() {
		if(seekerCam == INVALID_ENT_REFERENCE || !IsValidEntity(seekerCam)) {
			seekerCam = CreateEntityByName("point_viewcontrol_survivor");
			DispatchKeyValue(seekerCam, "targetname", "hscam");
			DispatchSpawn(seekerCam);
			for(int i = 0; i <= MaxClients; i++) {
				isViewingCam[i] = false;
			}
		}
	}

	public bool Exists() {
		return seekerCam != INVALID_ENT_REFERENCE && IsValidEntity(seekerCam)
	}

	public void Destroy() {
		if(seekerCam == INVALID_ENT_REFERENCE || !IsValidEntity(seekerCam)) {
			seekerTarget = 0;
			AcceptEntityInput(seekerCam, "Disable");
			AcceptEntityInput(seekerCam, "Kill");
			seekerCam = INVALID_ENT_REFERENCE
		}
	}
}


enum struct EntityConfig {
	float origin[3];
	float rotation[3];
	char type[32];
	char model[64];
	float scale[3];
	float offset[3];
}

enum struct MapConfig {
	ArrayList entities;
	ArrayList inputs;
	float spawnpoint[3];
	bool hasSpawnpoint;
	int mapTime;
	bool canClimb;
	bool pressButtons;
}

MapConfig mapConfig;
ArrayList validMaps;
ArrayList validSets;

stock void SetParent(int child, int parent) {
	SetVariantString("!activator");
	AcceptEntityInput(child, "SetParent", parent);
}

stock void SetParentAttachment(int child, const char[] attachment, bool withOffset = false) {
	SetVariantString(attachment);
	if(withOffset)
		AcceptEntityInput(child, "SetParentAttachmentMaintainOffset");
	else
		AcceptEntityInput(child, "SetParentAttachment");
}

stock void ClearParent(int child) {
	AcceptEntityInput(child, "ClearParent");
}