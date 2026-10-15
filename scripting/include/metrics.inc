#if defined _metrics_included_
  #endinput
#endif
#define _metrics_included_

#include <ripext/json>

public SharedPlugin __pl_metrics_ = 
{
	name = "metrics",
	file = "sm_metrics.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

/**
 * Creates a new metrics 'handle' for a metric. A Metric is an unique set of metric name + labels.
 * 
 * ClearMetrics() should be called on plugin ending to clear any registered metrics 
 * so that there are no duplicate values
 * 
 * Add labels with SetLabel or SubscribeCvarLevel to add a cvar as a level
 * 
 * This should be called when the 'metrics' library is added, so they are re-created on API reload.
 * 
 * The internal value by default is an integer, but if IncrementFloat or SetFloat is called, it will be turned into a float.
 */
native Metric CreateMetric(const char[] metricName);
/**
 * Clears all metrics that have been created by this plugin. 
 * This should be called OnPluginEnd, otherwise duplicate metrics will be sent
 */
native void ClearMetrics();

methodmap Metric {
    /** The registration ID (for internal use) */
    property int RegId {
        public get() {
            return view_as<int>(this);
        }
    }

    /** Stores the metric name in the buffer */
    public native void GetName(char[] buffer, int maxlen);

    /**
     * Set a label for this specific metric
     */
    public native Metric SetLabel(const char[] key, const char[] value);
    /**
     * Set a label for this specific metric
     */
    public Metric SetLabelInt(const char[] key, int value) {
        char buffer[64];
        IntToString(value, buffer, sizeof(buffer));
        this.SetLabel(key, buffer);
        return this;
    }

    /** Subscribe to change list so when given cvar changes, the label is updated */
    public native Metric SubscribeCvarLabel(const char[] cvarName);

    /** Submits float value (ignores internal value, should not be used) */
    public native void SendFloat(float value);
    /** Submits int value (ignores internal value, should not be used) */
    public native void SendInt(int value);

    /** Records internal value to be sent to VM. Should not be called */
    public native void Record();

    /** Set the integer value of internal value */
    public native void SetInt(int value);
    /** Set the float value of internal value */
    public native void SetFloat(float value);

    /** Increments the integer value of internal value by count */
    public native int IncrementInt(int count = 1);
    /** Increments the float value of internal value by amount */
    public native int IncrementFloat(float amount = 1.0);
    /** Resets the internal value to 0/0.0 */
    public native void Reset();
    /** Is there any metrics that are pending being sent to VM */
    public native bool HasMetrics();
    /** Clear the list of penidng metrics */
    public native void ClearRecords();
    /** Serialize the metric to a JSON string */
    public native bool ToString(char[] buffer, int maxlen);
}

#if !defined REQUIRE_PLUGIN
public void __pl_metrics_SetNTVOptional() {
    MarkNativeAsOptional("CreateMetric");
    MarkNativeAsOptional("Metric.GetName");
    MarkNativeAsOptional("Metric.SetLabel");
    MarkNativeAsOptional("Metric.SendFloat");
    MarkNativeAsOptional("Metric.SendInt");
    MarkNativeAsOptional("Metric.Record");
    MarkNativeAsOptional("Metric.SetInt");
    MarkNativeAsOptional("Metric.SetFloat");
    MarkNativeAsOptional("Metric.IncrementInt");
    MarkNativeAsOptional("Metric.IncrementFloat");
    MarkNativeAsOptional("Metric.Reset");
    MarkNativeAsOptional("Metric.ClearRecords");
    MarkNativeAsOptional("Metric.HasMetrics");
    MarkNativeAsOptional("Metric.ToString");
    MarkNativeAsOptional("Metric.SubscribeCvarLabel");
    MarkNativeAsOptional("ClearMetrics");
}
#endif