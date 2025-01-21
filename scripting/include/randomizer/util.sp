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