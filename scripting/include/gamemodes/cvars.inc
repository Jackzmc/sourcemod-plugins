static char buffer[128];

methodmap GameConVarStorage < StringMap {
	public GameConVarStorage() {
		return view_as<GameConVarStorage>(new StringMap());
	}

	public void Restore() {
		StringMapSnapshot snapshot = this.Snapshot();
		char key[32];
        #if defined DEBUG_GAME_CVAR_STORAGE
		PrintToServer("GameConVarStorage: Restoring %d saved convars", snapshot.Length);
        #endif
		for(int i = 0; i < snapshot.Length; i++) {
			snapshot.GetKey(i, key, sizeof(key));
			ConVar convar = FindConVar(key);
			if(convar != null) {
				float value;
				if(this.GetValue(key, value)) {
					convar.FloatValue = value;
				} else if(this.GetString(key, buffer, sizeof(buffer))) {
					convar.SetString(buffer);
				} else {
					LogError("GameConVarStorage: Cannot restore invalid cvar (\"%s\")", key);
				}
			}
		}
		this.Clear();
	}

}

methodmap GameConVar < ConVar {
	public GameConVar(const char[] name) {
		return view_as<GameConVar>(FindConVar(name));
	}

	public void RecordInt(int value, GameConVarStorage storage) {
		if(storage != null) {
			this.GetName(buffer, sizeof(buffer));
			storage.SetValue(buffer, float(value));
		}
		this.IntValue = value;
	}

	public void RecordFloat(float value, GameConVarStorage storage) {
		if(storage != null) {
			this.GetName(buffer, sizeof(buffer));
			storage.SetValue(buffer, value);
		}
		this.FloatValue = value;
	}

	public void RecordString(const char[] value, GameConVarStorage storage) {
		if(storage != null) {
			char prevValue[32];
			this.GetName(buffer, sizeof(buffer));
			this.GetString(prevValue, sizeof(prevValue));
			storage.SetString(buffer, prevValue);
		}
		this.SetString(value);
	}

}