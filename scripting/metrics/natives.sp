int Native_CreateMetric(Handle plugin, int numParams) {
    char metricName[64];

    GetNativeString(1, metricName, sizeof(metricName));


    MetricData regData;
    regData.obj = new JSONObject();
    regData.owner = plugin;

    JSONObject metric = new JSONObject();
    metric.SetString("__name__", metricName);
    metric.SetString("id", metricsId);
    regData.obj.Set("metric", metric);
    delete metric;

    JSONArray values = new JSONArray();
    regData.obj.Set("values", values);
    delete values;

    JSONArray timestamps = new JSONArray();
    regData.obj.Set("timestamps", timestamps);
    delete timestamps;

    // Reuse an empty index or push new
    int id = FindExistingIndex();
    if(id != -1) g_metricDefs.SetArray(id, regData, sizeof(regData));
    else id = g_metricDefs.PushArray(regData, sizeof(regData));

    LogInfo("Registered metric \"%s\" (id:%d)", metricName, id);

    return id;
}

/** find an index that is unused */
int FindExistingIndex() {
    MetricData regData;
    for(int i = 0; i < g_metricDefs.Length; i++) {
        g_metricDefs.GetArray(i, regData, sizeof(regData));
        if(regData.IsEmpty()) return i;
    }
    return -1;
}

void Native_CloseMetrics(Handle plugin, int numParams) {
    LogDebug("Plugin (%d) wants to close metrics", plugin);
    MetricData regData;
    for(int i = 0; i < g_metricDefs.Length; i++) {
        g_metricDefs.GetArray(i, regData, sizeof(regData));
        if(regData.owner == plugin) {
            // TODO: clear 'metric', 'values', 'timestamp' ?
            regData.obj.Clear()
            regData.owner = null;
            delete regData.obj;
            LogInfo("Closed metric #%d for plugin %d", i, plugin);
        }
    }
}

JSONObject GetMetricRootObject(int index) {
    MetricData regData;
    g_metricDefs.GetArray(index, regData, sizeof(regData));
    if(regData.IsEmpty()) ThrowError("Metric #%d has closed", index);
    return regData.obj;
}

JSONObject GetMetricMetricObject(int index) {
    JSONObject root = GetMetricRootObject(index);
    JSONObject metric = view_as<JSONObject>(root.Get("metric"));
    return metric;
}

void Native_Metric_GetName(Handle plugin, int numParams) {
    int regId = GetNativeCell(1);
    int bufSize = GetNativeCell(3);

    char[] buf = new char[bufSize + 1];

    JSONObject metric = GetMetricMetricObject(regId);
    metric.GetString("__name__", buf, bufSize);
    delete metric;

    SetNativeString(2, buf, bufSize);
}

void Native_Metric_SetLabel(Handle plugin, int numParams) {
    int regId = GetNativeCell(1);

    int keyLen;
    GetNativeStringLength(2, keyLen);
    char[] keyBuf = new char[keyLen + 1];
    GetNativeString(2, keyBuf, keyLen + 1);

    int valLen;
    GetNativeStringLength(3, valLen);
    char[] valBuf = new char[valLen  + 1];
    GetNativeString(3, valBuf, valLen + 1);

    JSONObject metric = GetMetricMetricObject(regId);
    metric.SetString(keyBuf, valBuf);
    delete metric;
}



int Native_Metric_SubLabelChange(Handle plugin, int numParams) {
    int regId = GetNativeCell(1);

    int cvarLen;
    GetNativeStringLength(2, cvarLen);
    char[] cvarName = new char[cvarLen + 1];
	GetNativeString(2, cvarName, cvarLen + 1);
 
    ArrayList list;
    if(!g_changeLists.GetValue(cvarName, list)) {
        ConVar cvar = FindConVar(cvarName);
        if(!cvar) {
            return ThrowNativeError(SP_ERROR_NATIVE, "ConVar \"%s\" does not exist", cvarName);
        }
        g_changeListCvars.SetValue(cvarName, cvar);
        cvar.AddChangeHook(CVAR_OnSubChange);

        list = new ArrayList();
    }
    list.Push(regId);
    g_changeLists.SetValue(cvarName, list);
    return regId;
}

// records timestamp and returns view to values array (must close)
JSONArray _recordValue(int regId) {
    JSONObject root = GetMetricRootObject(regId);
    JSONArray values = view_as<JSONArray>(root.Get("values"));
    JSONArray timestamps = view_as<JSONArray>(root.Get("timestamps"));

    // record 64-bit ms time
    static char timeBuf[32];
    int time64[2];
    GetTime(time64);
    Int64ToString(time64, timeBuf, sizeof(timeBuf));
    StrCat(timeBuf, sizeof(timeBuf), "000"); // convert sec->ms
    timestamps.PushInt64(timeBuf);
    delete timestamps;
    
    return values;
}

void Native_Metric_RecordInt(Handle plugin, int numParams) {
    int regId = GetNativeCell(1);
    int value = GetNativeCell(2);

    JSONArray values = _recordValue(regId);
    values.PushInt(value);
    delete values;
}

void Native_Metric_RecordFloat(Handle plugin, int numParams) {
    int regId = GetNativeCell(1);
    float value = GetNativeCell(2);

    JSONArray values = _recordValue(regId);
    values.PushFloat(value);
    delete values;
}

int Native_Metric_IncrementInt(Handle plugin, int numParams) {
    int regId = GetNativeCell(1);
    int amount = GetNativeCell(2);

    MetricData regData;
    g_metricDefs.GetArray(regId, regData, sizeof(regData));
    regData.intValue += amount;
    regData.isFloat = false;
    g_metricDefs.SetArray(regId, regData, sizeof(regData));

    // Push change
    // JSONArray values = _recordValue(regId);
    // values.PushInt(regData.intValue);
    // delete values;

    return regData.intValue;
}

any Native_Metric_IncrementFloat(Handle plugin, int numParams) {
    int regId = GetNativeCell(1);
    float amount = GetNativeCell(2);

    MetricData regData;
    g_metricDefs.GetArray(regId, regData, sizeof(regData));
    regData.floatValue += amount;
    regData.isFloat = true;
    g_metricDefs.SetArray(regId, regData, sizeof(regData));

    // Push change
    // JSONArray values = _recordValue(regId);
    // values.PushFloat(regData.floatValue);
    // delete values;

    return regData.floatValue;
}

void Native_Metric_SetInt(Handle plugin, int numParams) {
    int regId = GetNativeCell(1);
    int amount = GetNativeCell(2);

    MetricData regData;
    g_metricDefs.GetArray(regId, regData, sizeof(regData));
    regData.intValue = amount;
    regData.isFloat = false;
    g_metricDefs.SetArray(regId, regData, sizeof(regData));

    // Push change
    // JSONArray values = _recordValue(regId);
    // values.PushInt(regData.intValue);
    // delete values;
}

void Native_Metric_SetFloat(Handle plugin, int numParams) {
    int regId = GetNativeCell(1);
    float amount = GetNativeCell(2);

    MetricData regData;
    g_metricDefs.GetArray(regId, regData, sizeof(regData));
    regData.floatValue = amount;
    regData.isFloat = true;
    g_metricDefs.SetArray(regId, regData, sizeof(regData));

    // Push change
    // JSONArray values = _recordValue(regId);
    // values.PushFloat(regData.floatValue);
    // delete values;
}

void Native_Metric_Record(Handle plugin, int numParams) {
    int regId = GetNativeCell(1);

    MetricData regData;
    g_metricDefs.GetArray(regId, regData, sizeof(regData));

    JSONArray values = _recordValue(regId);
    if(regData.isFloat) values.PushFloat(regData.floatValue);
    else values.PushInt(regData.intValue);
    delete values;
}

void Native_Metric_Reset(Handle plugin, int numParams) {
    int regId = GetNativeCell(1);

    MetricData regData;
    g_metricDefs.GetArray(regId, regData, sizeof(regData));
    regData.floatValue = 0.0;
    regData.intValue = 0;
    regData.isFloat = false;
    g_metricDefs.SetArray(regId, regData, sizeof(regData));
}

int Native_Metric_HasMetrics(Handle plugin, int numParams) {
    int regId = GetNativeCell(1);

    JSONObject root = GetMetricRootObject(regId);

    JSONArray values = view_as<JSONArray>(root.Get("values"));
    bool hasMetrics = values.Length > 0;
    delete values;

    return hasMetrics;
}

void Native_Metric_ClearRecords(Handle plugin, int numParams) {
    int regId = GetNativeCell(1);

    JSONObject root = GetMetricRootObject(regId);

    JSONArray values = view_as<JSONArray>(root.Get("values"));
    values.Clear();
    delete values;

    JSONArray timestamps = view_as<JSONArray>(root.Get("timestamps"));
    timestamps.Clear();
    delete timestamps;
}


int Native_Metric_ToString(Handle plugin, int numParams) {
    int regId = GetNativeCell(1);

    int bufLen = GetNativeCell(3);
    char[] buf = new char[bufLen];

    JSONObject root = GetMetricRootObject(regId);
    if(root.ToString(buf, bufLen, JSON_COMPACT)) {
        SetNativeString(2, buf, bufLen);
        return true;
    }
    return false;
}
