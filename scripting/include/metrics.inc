#if defined _metrics_included_
  #endinput
#endif
#define _metrics_included_
#include <ripext/json>

native Metric CreateMetric(const char[] metricName);
native void ClearMetrics();

methodmap Metric {
    property int RegId {
        public get() {
            return view_as<int>(this);
        }
    }

    public native void GetName(char[] buffer, int maxlen);

    /**
     * Set a label value for this specific metric
     */
    public native Metric SetLabel(const char[] key, const char[] value);
    public Metric SetLabelInt(const char[] key, int value) {
        char buffer[64];
        IntToString(value, buffer, sizeof(buffer));
        this.SetLabel(key, buffer);
        return this;
    }

    /** Subscribe to change list so when given cvar changes, the label is updated */
    public native Metric SubscribeCvarLabel(const char[] cvarName);

    /** Submits float value (ignores internal value) */
    public native void SendFloat(float value);
    public native void SendInt(int value);

    /** Submits the current value in buffer. 
     * If last value incremented was a float, sends as float, otherwise int */
    public native void Record();

    public native void SetInt(int value);
    public native void SetFloat(float value);

    public native int IncrementInt(int count = 1);
    public native int IncrementFloat(float count = 1.0);
    /** reset value */
    public native void Reset();

    public native bool HasMetrics();
    /**
     * Clear the list of metrics
     */
    public native void ClearRecords();

    public native bool ToString(char[] buffer, int maxlen);
}