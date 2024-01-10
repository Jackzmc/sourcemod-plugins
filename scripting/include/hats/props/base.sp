char g_pendingSaveName[64];
int g_pendingSaveClient;

/* Wish to preface this file:
* It's kinda messy. The main structs are:
* - ItemData
* - CategoryData

The rest are kinda necessary, for sorting reasons (SearchData, RecentEntry).

*/
enum struct PlayerPropData {
	ArrayList listBuffer;
	bool clearListBuffer;
	int lastCategoryIndex;
	int lastItemIndex;
	int lastShowedHint;
	char classnameOverride[32];

	bool isSearchActive;
	ArrayList markedProps;

	// Called on PlayerDisconnect
	void Reset() {
		if(this.listBuffer != null) delete this.listBuffer;
		if(this.markedProps != null) delete this.markedProps;
		this.isSearchActive = false;
		this.clearListBuffer = false;
		this.lastCategoryIndex = 0;
		this.lastItemIndex = 0;
		this.lastShowedHint = 0;
		this.classnameOverride[0] = '\0';
	}

	// Sets the list buffer
	void SetList(ArrayList list, bool cleanupAfterUse = false) {
		this.listBuffer = list;
		this.clearListBuffer = cleanupAfterUse;
	}

	// Is currently only called on item handler cancel (to clear search/recents buffer)
	void CleanupBuffer() {
		if(this.listBuffer != null && this.clearListBuffer) {
			delete this.listBuffer;
			this.clearListBuffer = false;
		}
	}
}
PlayerPropData g_PropData[MAXPLAYERS+1];

enum struct CategoryData {
	// The display name of category
	char name[64];
	// If set, overwrites the classname it is spawned as
	char classnameOverride[32];
	bool hasItems; // true: items is ArrayList<ItemData>, false: items is ArrayList<CategoryData>
	ArrayList items;
}
enum struct ItemData {
	char model[128];
	char name[64];

	void FromSearchData(SearchData search) {
		strcopy(this.model, sizeof(this.model), search.model);
		strcopy(this.name, sizeof(this.name), search.name);
	}
}
enum struct SearchData {
	char model[128];
	char name[64];
	int index;

	void FromItemData(ItemData item) {
		strcopy(this.model, sizeof(this.model), item.model);
		strcopy(this.name, sizeof(this.name), item.name);
	}
}
enum struct SaveData {
	char model[128];
	buildType type;
	float origin[3];
	float angles[3];
	int color[4];

	void FromEntity(int entity) {
		// Use this.model as a buffer:
		GetEntityClassname(entity, this.model, sizeof(this.model));
		if(StrEqual(this.model, "prop_physics")) this.type = Build_Physics;
		else if(StrEqual(this.model, "prop_dynamic")) {
			if(GetEntProp(entity, Prop_Send, "m_nSolidType") == 0) {
				this.type = Build_NonSolid;
			} else {
				this.type = Build_Solid;
			}
		}
		
		GetEntPropString(entity, Prop_Data, "m_ModelName", this.model, sizeof(this.model));
		GetEntPropVector(entity, Prop_Send, "m_vecOrigin", this.origin);
		GetEntPropVector(entity, Prop_Send, "m_angRotation", this.angles);
		GetEntityRenderColor(entity, this.color[0],this.color[1],this.color[2],this.color[3]);
	}

	void Serialize(char[] output, int maxlen) {
		Format(
			output, maxlen, "%s,%d,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%d,%d,%d,%d", 
			this.model, this.type, this.origin[0], this.origin[1], this.origin[2],
			this.angles[0], this.angles[1], this.angles[2],
			this.color[0], this.color[1], this.color[2], this.color[3]
		);
	}

	void Deserialize(const char[] input) {
		char buffer[16];
		int index = SplitString(input, ",", this.model, sizeof(this.model));
		index += SplitString(input[index], ",", buffer, sizeof(buffer));
		this.type = view_as<buildType>(StringToInt(buffer));
		for(int i = 0; i < 3; i++) {
			index += SplitString(input[index], ",", buffer, sizeof(buffer));
			this.origin[i] = StringToFloat(buffer);
		}
		for(int i = 0; i < 3; i++) {
			index += SplitString(input[index], ",", buffer, sizeof(buffer));
			this.angles[i] = StringToFloat(buffer);
		}
		for(int i = 0; i < 4; i++) {
			index += SplitString(input[index], ",", buffer, sizeof(buffer));
			this.color[i] = StringToInt(buffer);
		}
	}
}

enum struct RecentEntry {
	char name[64];
	int count;
}

ArrayList g_categories; // ArrayList<CategoryData>
ArrayList g_spawnedItems; // ArrayList(block=2)<entRef, [creator]>
ArrayList g_savedItems; // ArrayList<entRef>
StringMap g_recentItems; // Key: model[128], value: RecentEntry

#include <hats/props/methods.sp>
#include <hats/props/cmd.sp>
#include <hats/props/menu_handlers.sp>
#include <hats/props/menu_methods.sp>