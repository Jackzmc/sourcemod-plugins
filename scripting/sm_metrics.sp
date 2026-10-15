#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <ripext/json>
#include <jutils>
#include <system2>
#include <log>

#include <metrics>

#define VERSION "1.0.0"
#define BUFFER_SIZE 16384

char REQ_BODY_BUFFER[BUFFER_SIZE];
char LINE_BUFFER[2048];

ArrayList g_metricDefs;
StringMap g_changeLists;
StringMap g_changeListCvars;

ConVar cvarMetricsUrl; char metricsUrl[128];
ConVar cvarMetricId; char metricsId[64];
ConVar cvarRecordInterval;
ConVar cvarRecordTimeout;

Handle recordTimer;

Metric g_m_info;

enum struct MetricData {
    Handle owner;

    JSONObject obj;
    int intValue;
    float floatValue;

    bool isFloat; // false: intValue, true: floatValue

    bool IsEmpty() { return this.obj == null; }
}

#include "metrics/natives.sp"

public Plugin myinfo = {
	name =  "SM Metrics API", 
	author = "jackzmc", 
	description = "API to send metrics to Victoria Metrics", 
	version = VERSION, 
	url = "https://github.com/Jackzmc/sourcemod-plugins"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
    RegPluginLibrary("metrics");

	CreateNative("CreateMetric", Native_CreateMetric);
    CreateNative("Metric.GetName", Native_Metric_GetName);
    CreateNative("Metric.SetLabel", Native_Metric_SetLabel);
    CreateNative("Metric.SendFloat", Native_Metric_RecordFloat);
    CreateNative("Metric.SendInt", Native_Metric_RecordInt);
    CreateNative("Metric.Record", Native_Metric_Record);
    CreateNative("Metric.SetInt", Native_Metric_SetInt);
    CreateNative("Metric.SetFloat", Native_Metric_SetFloat);
    CreateNative("Metric.IncrementInt", Native_Metric_IncrementInt);
    CreateNative("Metric.IncrementFloat", Native_Metric_IncrementFloat);
    CreateNative("Metric.Reset", Native_Metric_Reset);
    CreateNative("Metric.ClearRecords", Native_Metric_ClearRecords);
    CreateNative("Metric.HasMetrics", Native_Metric_HasMetrics);
    CreateNative("Metric.ToString", Native_Metric_ToString);
	CreateNative("Metric.SubscribeCvarLabel", Native_Metric_SubLabelChange);
	CreateNative("ClearMetrics", Native_CloseMetrics);

	return APLRes_Success;
}

public void OnPluginStart() {
    Log_Init("metrics", Log_Info);
    Log_CreateCvar("sm_metrics_log_level", Log_Info);
    
    cvarMetricsUrl = CreateConVar("sm_metrics_url", "http://localhost:8428/api/v1/import", "URL of victoria metrics JSON line import API");
    cvarMetricsUrl.GetString(metricsUrl, sizeof(metricsUrl));
    cvarMetricsUrl.AddChangeHook(CVAR_OnMetricsUrlChange);

    cvarMetricId = CreateConVar("sm_metrics_id", "", "Optional unique ID for server");
    cvarMetricId.GetString(metricsId, sizeof(metricsId));
    cvarMetricId.AddChangeHook(CVAR_OnMetricsIdChange);

    cvarRecordInterval = CreateConVar("sm_metrics_record_interval", "30.0", "The interval in seconds at which records are sent", FCVAR_NONE, true, 1.0);
    cvarRecordInterval.AddChangeHook(CVAR_OnIntervalChange);

    cvarRecordTimeout = CreateConVar("sm_metrics_record_timeout", "1", "The number of seconds before a request times out recording metrics", FCVAR_NONE, true, 1.0);

    StartTimer();

    g_metricDefs = new ArrayList(sizeof(MetricData));
    g_changeLists = new StringMap();
    g_changeListCvars = new StringMap();

    RegisterMetrics();

    // For debug use
    RegAdminCmd("sm_mt_flush", Command_Flush, ADMFLAG_GENERIC);

	AutoExecConfig(true, "sm_metrics");
}

public void OnPluginEnd() {
    SendMetrics(g_metricDefs);
}

void StartTimer() {
    if(recordTimer != null) {
        delete recordTimer;
    }
    recordTimer = CreateTimer(cvarRecordInterval.FloatValue, Timer_FlushMetrics, _, TIMER_REPEAT);
}

Action Command_Flush(int client, int args) {
    SendMetrics(g_metricDefs);
    ReplyToCommand(client, "Flushed");
    return Plugin_Handled;
}

void RegisterMetrics() {
    g_m_info = CreateMetric("sm_info");
    char buffer[32];
    int appid = GetAppData(buffer, sizeof(buffer));
    g_m_info.SetLabel("game_version", buffer);
    IntToString(appid, buffer, sizeof(buffer));
    g_m_info.SetLabel("appid", buffer);
    g_m_info.SetLabel("plugin_version", VERSION);
    g_m_info.SetLabel("sm_version", SOURCEMOD_VERSION);
    g_m_info.SetInt(1);
}

Action Timer_FlushMetrics(Handle h) {
    // g_m_info.RecordInt(1);
    SendMetrics(g_metricDefs);
    return Plugin_Continue;
}

void CVAR_OnIntervalChange(ConVar cvar, const char[] oldValue, const char[] newValue) {
    StartTimer();
}

void CVAR_OnMetricsUrlChange(ConVar cvar, const char[] oldValue, const char[] newValue) {
    cvar.GetString(metricsUrl, sizeof(metricsUrl));
}
void CVAR_OnMetricsIdChange(ConVar cvar, const char[] oldValue, const char[] newValue) {
    cvar.GetString(metricsId, sizeof(metricsId));
    // Update id label for all metrics
    for(int i = 0; i < g_metricDefs.Length; i++) {
        JSONObject metric = GetMetricMetricObject(i);
        metric.SetString("id", newValue);

        delete metric;
    }
}

void CVAR_OnSubChange(ConVar cvar, const char[] oldValue, const char[] newValue) {
    char buffer[128];
    cvar.GetName(buffer, sizeof(buffer));
    ArrayList subs;
    if(g_changeLists.GetValue(buffer, subs)) {
        // Update all subbed labels
        for(int i = 0; i < subs.Length; i++) {
            JSONObject metric = GetMetricMetricObject(i);
            metric.SetString("id", newValue);

            delete metric;
        }
    }

    if(newValue[0] == '\0') {
        LogWarn("Metrics URL is empty, no metrics will be sent");
    }
}

/**
 * Send a list of metrics out. Consumes metrics array
 */
void SendMetrics(ArrayList metrics) {
    if(metricsUrl[0] == '\0') return; // ignore if no url
    int len = 0;
    REQ_BODY_BUFFER[0] = '\0';
    LINE_BUFFER[0] = '\0';
    // Read until all metrics flushed
    // TODO: perf: swap to reading from newest to oldest, to reduce array shifts?
    MetricData regData;
    for(int i = 0; i < metrics.Length; i++) {
        g_metricDefs.GetArray(i, regData, sizeof(regData));

        if(regData.obj == null) continue; // skip removed entries

        Metric metric = view_as<Metric>(i);
        metric.Record();
        // if(!metric.HasMetrics()) continue;
        if(metric.ToString(LINE_BUFFER, sizeof(LINE_BUFFER))) {
            int lineLen = strlen(LINE_BUFFER);
            if(len + lineLen >= sizeof(REQ_BODY_BUFFER)) {
                // Buffer is full, flush it
                _SendRequst(REQ_BODY_BUFFER);
                REQ_BODY_BUFFER[0] = '\0';
                len = 0;
            }
            len += StrCat(REQ_BODY_BUFFER, sizeof(REQ_BODY_BUFFER), LINE_BUFFER);
            len += StrCat(REQ_BODY_BUFFER, sizeof(REQ_BODY_BUFFER), "\n");
        } else {
            PrintToServer("warn: line buffer exceeded for metric");
        }
        metric.ClearRecords();
    }
    if(len > 0) _SendRequst(REQ_BODY_BUFFER);
}

void _SendRequst(const char[] buffer) {
    if(buffer[0] == '\0') {
        LogWarn("Cannot send an empty buffer. Ignoring");
        return;
    }
    int bytes = strlen(buffer);
    LogDebug("sending metrics (%d bytes) to %s", bytes, metricsUrl);
    System2HTTPRequest req = new System2HTTPRequest(Request_CB, metricsUrl);
    req.SetUserAgent("sm_metrics/%s (Sourcemod Plugin)", VERSION);
    req.SetData("%s", buffer);
    req.Timeout = cvarRecordTimeout.IntValue;
    req.POST();
}

void Request_CB(bool success, const char[] error, System2HTTPRequest request, System2HTTPResponse response, HTTPRequestMethod method) {
    if(!success) {
        LogError("Failed to send metrics: %s", error);
    } else if(response != null && response.StatusCode != 204 && response.StatusCode != 200) {
        LogError("Got bad response from server (status code %d)", response.StatusCode);
    }
    LogTrace("metrics received successfully");
}