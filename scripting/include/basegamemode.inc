// Meta
char gamemode[32];
char currentMap[64];
bool isEnabled, lateLoaded;

// Internal State
char currentSet[16] = "default";
char nextRoundMap[64];
int seekerCam = INVALID_ENT_REFERENCE;
bool isNavBlockersEnabled = true, isPropsEnabled = true, isPortalsEnabled = true;

int g_iLaserIndex;

// Gamemode state
bool isPendingPlay[MAXPLAYERS+1];
bool isViewingCam[MAXPLAYERS+1];


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

