public bool GetVector(JSONObject obj, const char[] key, float out[3]) {
	if(!obj.HasKey(key)) return false;
	JSONArray vecArray = view_as<JSONArray>(obj.Get(key));
	if(vecArray != null) {
		out[0] = vecArray.GetFloat(0);
		out[1] = vecArray.GetFloat(1);
		out[2] = vecArray.GetFloat(2);
	}
	return true;
}

public void GetColor(JSONObject obj, const char[] key, int out[4], int defaultColor[4]) {
	if(obj.HasKey(key)) {
		JSONArray vecArray = view_as<JSONArray>(obj.Get(key));
		out[0] = vecArray.GetInt(0);
		out[1] = vecArray.GetInt(1);
		out[2] = vecArray.GetInt(2);
		if(vecArray.Length == 4)
			out[3] = vecArray.GetInt(3);
		else
			out[3] = 255;
	} else {
		out = defaultColor;
	}
}

stock JSONArray FromFloatArray(float[] vec, int count) {
	JSONArray arr = new JSONArray();
	for(int i = 0 ; i < count; i++) {
		arr.PushFloat(vec[i]);
	}
	return arr;
}
stock JSONArray FromIntArray(int[] vec, int count) {
	JSONArray arr = new JSONArray();
	for(int i = 0 ; i < count; i++) {
		arr.PushInt(vec[i]);
	}
	return arr;
}

bool IdentifyEntityScene(int client, int entityIndex) {
	if(g_MapData.scenes == null) return false;
	float origin[3];
	GetEntPropVector(entityIndex, Prop_Send, "m_vecOrigin", origin);
	char type[64];
	GetEntityClassname(entityIndex, type, sizeof(type));
	char model[128];
	GetEntPropString(entityIndex, Prop_Data, "m_ModelName", model, sizeof(model));

	PrintToServer("identify \"%s\" \"%s\" %.4f %.4f %.4f", type, model, origin[0], origin[1], origin[2]);
	PrintToChat(client, "Identifying %s (%d)", type, entityIndex);

	
	SceneData scene;
	SceneVariantData choice;
	VariantEntityData entity;
	bool hasMatch = false;
	for(int i = 0; i < g_MapData.scenes.Length; i++) {
        g_MapData.scenes.GetArray(i, scene);
        for(int v = 0; v < scene.variants.Length; v++) {
			scene.variants.GetArray(v, choice);
			for(int j = 0; j < choice.entities.Length; j++) {
				choice.entities.GetArray(j, entity);
				if(StrEqual(entity.type, type)) {
					if(StrEqual(entity.model, model)) {
						if(IsVectorEqual(entity.origin, origin, 0.1)) {
							PrintToChat(client, "  Match %s#%d entity#%d", scene.name, v, j);
							hasMatch = true;
						} 

						// return true;
					}
				}
			}
		} 
    }
	if(!hasMatch) PrintToChat(client, "Scene: None");
	return hasMatch;
}

bool FloatsEqual(float a, float b, float diff) {
	return FloatAbs(a - b) <= diff;
}
bool IsVectorEqual(const float a[3], const float b[3], float delta) {
	return FloatsEqual(a[0], b[0], delta) && FloatsEqual(a[1], b[1], delta) && FloatsEqual(a[2], b[2], delta);
}