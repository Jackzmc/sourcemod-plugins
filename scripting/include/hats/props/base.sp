int g_pendingSaveClient;
ArrayList g_previewItems;
CategoryData ROOT_CATEGORY;
ArrayList g_spawnedItems; // ArrayList(block=2)<entRef, [creator]>
ArrayList g_savedItems; // ArrayList<entRef>
StringMap g_recentItems; // Key: model[128], value: RecentEntry

/* Wish to preface this file:
* It's kinda messy. The main structs are:
* - ItemData
* - CategoryData

The rest are kinda necessary, for sorting reasons (SearchData, RecentEntry).

*/
enum ChatPrompt {
	Prompt_None,
	Prompt_Search,
	Prompt_SaveScene,
	Prompt_SaveSchematic
}
enum SaveType {
	Save_None,
	Save_Scene,
	Save_Schematic
}

int GLOW_MANAGER[3] = { 52, 174, 235 };

enum struct Schematic {
	char name[64];
	char creatorSteamid[32];
	char creatorName[32];
	ArrayList entities;

	void Reset() {
		this.name[0] = '\0';
		this.creatorSteamid[0] = '\0';
		this.creatorName[0] = '\0';
		if(this.entities != null) delete this.entities;
	}

	void AddEntity(int entity, int client) {
		SaveData save;
		save.FromEntity(entity);
		this.entities.PushArray(save);
	}

	void New(int client, const char[] name) {
		if(client > 0) {
			GetClientName(client, this.creatorName, sizeof(this.creatorName));
			GetClientAuthId(client, AuthId_Steam2, this.creatorSteamid, sizeof(this.creatorSteamid));
		}
		strcopy(this.name, sizeof(this.name), name);
		this.entities = new ArrayList(sizeof(SaveData));
	}

	bool Save() {
		char path[PLATFORM_MAX_PATH];
		BuildPath(Path_SM, path, sizeof(path), "data/prop_spawner/schematics/%s.schem", this.name);
		CreateDirectory("data/prop_spawner/schematics", 0775);
		KeyValues kv = new KeyValues(this.name);
		kv.SetString("creator_steamid", this.creatorSteamid);
		kv.SetString("creator_name", this.creatorName);
		kv.JumpToKey("entities");
		this.entities = new ArrayList(sizeof(SaveData));
		SaveData ent;
		while(kv.GotoNextKey()) {
			kv.GetVector("offset", ent.origin);
			kv.GetVector("angles", ent.angles);
			kv.GetColor4("color", ent.color);
			kv.GetString("model", ent.model, sizeof(ent.model));
			this.entities.PushArray(ent);
		}
		kv.ExportToFile(path);
		delete kv;
		return true;
	}

	bool Import(const char[] name) {
		char path[PLATFORM_MAX_PATH];
		BuildPath(Path_SM, path, sizeof(path), "data/prop_spawner/schematics/%s.schem", name);
		KeyValues kv = new KeyValues("root");
		if(kv.ImportFromFile(path)) {
			delete kv;
			return false;
		}
		strcopy(this.name, sizeof(this.name), name);
		kv.GetString("creator_steamid", this.creatorSteamid, sizeof(this.creatorSteamid));
		kv.GetString("creator_name", this.creatorName, sizeof(this.creatorName));
		kv.JumpToKey("entities");
		this.entities = new ArrayList(sizeof(SaveData));
		SaveData ent;
		while(kv.GotoNextKey()) {
			kv.GetVector("offset", ent.origin);
			kv.GetVector("angles", ent.angles);
			kv.GetColor4("color", ent.color);
			kv.GetString("model", ent.model, sizeof(ent.model));
			this.entities.PushArray(ent);
		}
		delete kv;
		return true;
	}

	/// Spawns all schematics entities, returns list of entities, first being parent.
	ArrayList SpawnEntities(const float origin[3], bool asPreview = true) {
		if(this.entities == null) return null;
		SaveData ent;
		int parent = -1;
		ArrayList spawnedEntities = new ArrayList();
		for(int i = 0; i < this.entities.Length; i++) {
			this.entities.GetArray(i, ent, sizeof(ent));
			int entity = ent.ToEntity(origin, asPreview);
			spawnedEntities.Push(EntIndexToEntRef(entity));
			if(i == 0) {
				SetParent(entity, parent)
			} else {
				parent = entity;
			}
		}
		return spawnedEntities;
	}
}
public any Native_SpawnSchematic(Handle plugin, int numParams) {
	char name[32];
	float pos[3];
	float ang[3];
	GetNativeString(0, name, sizeof(name));
	GetNativeArray(1, pos, 3);
	GetNativeArray(1, ang, 3);
	Schematic schem;
	if(!schem.Import(name)) {
		return false;
	}
	ArrayList list = schem.SpawnEntities(pos, false);
	delete list;
	return true;
}

enum struct PropSelectorIterator {
	ArrayList _list;
	int _index;
	int Entity;

	void _Init(ArrayList list) {
		this._list = list;
		this._index = -1;
	}

	bool Next() {
		this._index++;
		return this._index + 1 < this._list.Length;
	}

}


enum struct PropSelector {
	int selectColor[3];
	int limit;
	ArrayList list;
	PrivateForward endCallback;
	PrivateForward selectPreCallback;
	PrivateForward selectPostCallback;
	PrivateForward unSelectCallback;
	int _client;

	PropSelectorIterator Iter() {
		PropSelectorIterator iter;
		iter._Init(this.list);
		return iter;
	}

	void Reset() {
		if(this.endCallback) delete this.endCallback;
		if(this.selectPreCallback) delete this.selectPreCallback;
		if(this.selectPostCallback) delete this.selectPostCallback;
		if(this.unSelectCallback) delete this.unSelectCallback;
		if(this.list) delete this.list;
	}
	
	void Start(int color[3], int flags = 0, int limit = 0) {
		this.selectColor = color;
		this.limit = 0;
		this.list = new ArrayList();
		SendEditorMessage(this._client, "Left click to select, right click to unselect");
		SendEditorMessage(this._client, "Press WALK+USE to confirm, DUCK+USE to cancel");
	}

	void SetOnEnd(PrivateForward callback) {
		this.endCallback = callback;
	}
	void SetOnPreSelect(PrivateForward callback) {
		this.selectPreCallback = callback;
	}
	void SetOnPostSelect(PrivateForward callback) {
		this.selectPostCallback = callback;
	}
	void SetOnUnselect(PrivateForward callback) {
		this.unSelectCallback = callback;
	}

	void StartDirect(int color[3], SelectDoneCallback callback, int limit = 0) {
		PrivateForward fwd = new PrivateForward(ET_Ignore, Param_Cell, Param_Cell); 
		fwd.AddFunction(INVALID_HANDLE, callback);
		this.Start(color, 0, limit);
		this.SetOnEnd(fwd);
	}

	bool IsActive() {
		return this.list != null;
	}

	void End() {
		if(this.list == null) return;
		SendEditorMessage(this._client, "Selection completed");
		// Reset glows, remove selection from our spawned props
		for(int i = 0; i < this.list.Length; i++) {
			int ref = this.list.Get(i);
			if(IsValidEntity(ref)) {
				L4D2_RemoveEntityGlow(ref);
				RemoveSpawnedProp(ref);
			}
		}
		if(this.endCallback) {
			if(GetForwardFunctionCount(this.endCallback) == 0) {
				PrintToServer("[Editor] Warn: Selector.End(): callback has no functions assigned to it.");
			}
			Call_StartForward(this.endCallback);
			Call_PushCell(this._client);
			Call_PushCell(this.list.Clone());
			int result = Call_Finish();
			if(result != SP_ERROR_NONE) {
				PrintToServer("[Editor] Warn: Selector.End() forward error: %d", result);
			}
		} else {
			PrintToServer("[Editor] Warn: Selector.End() called but no callback assigned, voiding list");
		}
		this.Reset();
	}

	void Cancel() {
		if(this.endCallback) {
			Call_StartForward(this.endCallback);
			Call_PushCell(this._client);
			Call_PushCell(INVALID_HANDLE);
			Call_Finish();
		}
		if(this.list) {
			for(int i = 0; i < this.list.Length; i++) {
				int ref = this.list.Get(i);
				L4D2_RemoveEntityGlow(ref);
			}
		}
		PrintToChat(this._client, "\x04[Editor]\x01 Selection cancelled.");
		this.Reset();
	}
	
	int GetEntityRefIndex(int ref) {
		int index = this.list.FindValue(ref);
		if(index > -1) {
			return index;
		}
		return -1;
	}

	/** Removes entity from list
	 * @return returns entity ref of entity removed
	 */
	int RemoveEntity(int entity) {
		if(this.list == null) return -2;

		L4D2_RemoveEntityGlow(entity);
		int ref = EntIndexToEntRef(entity);
		int index = this.GetEntityRefIndex(ref);
		if(index > -1) {
			this.list.Erase(index);
			if(this.unSelectCallback != null) {
				Call_StartForward(this.unSelectCallback)
				Call_PushCell(this._client);
				Call_PushCell(EntRefToEntIndex(ref));
				Call_Finish();
			}
			return ref;
		}
		return INVALID_ENT_REFERENCE;
	}

	/**
	 * Adds entity to list
	 * @return index into list of entity
	 * @return -1 if already added
	 * @return -2 if callback rejected
	 */
	int AddEntity(int entity, bool useCallback = true) {
		if(this.list == null) return -2;

		int ref = EntIndexToEntRef(entity);
		if(this.GetEntityRefIndex(ref) == -1) {
			if(this.selectPreCallback != null && useCallback) {
				Call_StartForward(this.selectPreCallback)
				Call_PushCell(this._client);
				Call_PushCell(entity);
				bool allowed = true;
				PrintToServer("Selector.AddEntity: PRE CALLBACK pre finish");
				Call_Finish(allowed);
				PrintToServer("Selector.AddEntity: PRE CALLBACK pre result %b", allowed);
				if(!allowed) return -2;
			}

			L4D2_SetEntityGlow(entity, L4D2Glow_Constant, 10000, 0, this.selectColor, false);
			int index = this.list.Push(ref);
			PrintToServer("Selector.AddEntity: post CALLBACK pre");
			if(this.selectPostCallback != null && useCallback) {
				Call_StartForward(this.selectPostCallback)
				Call_PushCell(this._client);
				Call_PushCell(entity);
				//Call_PushCell(index);
				Call_Finish();
			}
			PrintToServer("Selector.AddEntity: post CALLBACK post");
			return index;
		}
		return -1;
	}
}
enum struct PlayerPropData {
	ArrayList categoryStack;
	ArrayList itemBuffer;
	bool clearListBuffer;
	int lastCategoryIndex;
	int lastItemIndex;
	// When did the user last interact with prop spawner? (Shows hints after long inactivity)
	int lastActiveTime;
	char classnameOverride[64];
	ChatPrompt chatPrompt;
	PropSelector Selector;
	SaveType pendingSaveType;

	Schematic schematic;
	int highlightedEntityRef;
	int managerEntityRef;

	void Init(int client) {
		this.Selector._client = client;
	}
	// Called on PlayerDisconnect
	void Reset() {
		if(this.Selector.IsActive()) this.Selector.Cancel();
		this.chatPrompt = Prompt_None;
		this.clearListBuffer = false;
		this.lastCategoryIndex = 0;
		this.lastItemIndex = 0;
		this.lastActiveTime = 0;
		this.classnameOverride[0] = '\0';
		this.CleanupBuffers();
		this.pendingSaveType = Save_None;
		this.schematic.Reset();
		this.managerEntityRef = INVALID_ENT_REFERENCE;
		this.StopHighlight();
	}

	void StartHighlight(int entity) {
		this.highlightedEntityRef = EntIndexToEntRef(entity);
		L4D2_SetEntityGlow(entity, L4D2Glow_Constant, 10000, 0, GLOW_MANAGER, false);
	}
	void StopHighlight() {
		if(IsValidEntity(this.highlightedEntityRef)) {
			L4D2_RemoveEntityGlow(this.highlightedEntityRef);
		}
		this.highlightedEntityRef = INVALID_ENT_REFERENCE;
	}

	void StartSchematic(int client, const char[] name) {
		this.schematic.New(client, name);
		this.pendingSaveType = Save_Schematic;
		PrintToChat(client, "\x04[Editor]\x01 Started new schematic: \x05%s", name);
		ShowCategoryList(client, ROOT_CATEGORY);
	}

	// Sets the list buffer
	void SetItemBuffer(ArrayList list, bool cleanupAfterUse = false) {
		// Cleanup previous buffer if exist
		this.itemBuffer = list;
		this.clearListBuffer = cleanupAfterUse;
	}
	void ClearItemBuffer() {
		if(this.itemBuffer != null && this.clearListBuffer) {
			PrintToServer("ClearItemBuffer(): arraylist deleted.");
			delete this.itemBuffer;
		}
		this.clearListBuffer = false;
	}

	void PushCategory(CategoryData category) {
		if(this.categoryStack == null) this.categoryStack = new ArrayList(sizeof(CategoryData));
		this.categoryStack.PushArray(category);
	}

	bool PopCategory(CategoryData data) {
		if(this.categoryStack == null || this.categoryStack.Length == 0) return false;
		int index = this.categoryStack.Length - 1;
		this.categoryStack.GetArray(index, data);
		this.categoryStack.Erase(index);
		return true;
	}
	bool PeekCategory(CategoryData data) {
		if(this.categoryStack == null || this.categoryStack.Length == 0) return false;
		int index = this.categoryStack.Length - 1;
		this.categoryStack.GetArray(index, data);
		return true;
	}

	void GetCategoryTitle(char[] title, int maxlen) {
		CategoryData cat;
		for(int i = 0; i < this.categoryStack.Length; i++) {
			this.categoryStack.GetArray(i, cat);
			if(i == 0)
				Format(title, maxlen, "%s", cat.name);
			else
				Format(title, maxlen, "%s>[%s]", title, cat.name);
		}
	}

	bool HasCategories() {
		return this.categoryStack != null && this.categoryStack.Length > 0;
	}

	// Is currently only called on item/category handler cancel (to clear search/recents buffer)
	void CleanupBuffers() {
		this.ClearItemBuffer();
		if(this.categoryStack != null) {
			delete this.categoryStack;
		}
		this.clearListBuffer = false;
	}
}
PlayerPropData g_PropData[MAXPLAYERS+1];


enum struct CategoryData {
	// The display name of category
	char name[64];
	// If set, overwrites the classname it is spawned as
	char classnameOverride[64];
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
		this.type = Build_Solid;
		if(StrEqual(this.model, "prop_physics")) this.type = Build_Physics;
		else if(StrEqual(this.model, "prop_dynamic")) {
			if(GetEntProp(entity, Prop_Send, "m_nSolidType") == 0) {
				this.type = Build_NonSolid;
			}
		}
		
		GetEntPropString(entity, Prop_Data, "m_ModelName", this.model, sizeof(this.model));
		GetEntPropVector(entity, Prop_Send, "m_vecOrigin", this.origin);
		GetEntPropVector(entity, Prop_Send, "m_angRotation", this.angles);
		GetEntityRenderColor(entity, this.color[0],this.color[1],this.color[2],this.color[3]);
	}

	int ToEntity(const float offset[3], bool asPreview = true) {
		int entity = -1;
		if(this.type == Build_Physics)
			entity = CreateEntityByName("prop_physics");
		else
			entity = CreateEntityByName("prop_dynamic_override");
		if(entity == -1) {
			return -1;
		}
		PrecacheModel(this.model);
		DispatchKeyValue(entity, "model", this.model);
		DispatchKeyValue(entity, "targetname", "saved_prop");
		if(asPreview) {
			DispatchKeyValue(entity, "rendermode", "1");
			DispatchKeyValue(entity, "solid", "0");
		} else {
			DispatchKeyValue(entity, "solid", this.type == Build_NonSolid ? "0" : "6");
		}
		float pos[3];
		for(int i = 0; i < 3; i++)
			pos[i] = this.origin[i] + offset[i];

		TeleportEntity(entity, pos, this.angles, NULL_VECTOR);
		if(!DispatchSpawn(entity)) {
			return -1;
		}
		int alpha = asPreview ? 200 : this.color[3];
		SetEntityRenderColor(entity, this.color[0], this.color[1], this.color[2], alpha);

		if(asPreview)
			g_previewItems.Push(EntIndexToEntRef(entity));
		else
			AddSpawnedItem(entity);
		return entity;
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

#include <hats/props/db.sp>
#include <hats/props/methods.sp>
#include <hats/props/cmd.sp>
#include <hats/props/menu_handlers.sp>
#include <hats/props/menu_methods.sp>