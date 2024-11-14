#if defined _overlay_included
	#endinput
#endif
#define _overlay_included
#include <ripext>

public SharedPlugin __pl_overlay = {
	name = "overlay",
	file = "overlay.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#define ACTION_ARG_LENGTH 128 // The length each arg (separated by space) can be

// typedef ActionFallbackHandlerCallback = function void (const char[] actionName, const char[][] args, int numArgs);
// typedef ActionHandlerCallback = function void (const char[][] args, int numArgs);
typedef ActionFallbackHandlerCallback = function void (const char[] actionName, UIActionEvent event, int client);
typedef ActionHandlerCallback = function void (UIActionEvent event, int client);


native bool IsOverlayConnected();

// myplugin:action_name
// Handles any action for actionNamespace and actionName
native void RegisterActionHandler(const char[] actionNamespace, const char[] commandName, ActionFallbackHandlerCallback cb);
// Handles all actions for namespace that were not caught by RegisterActionHandler
native void RegisterActionAnyHandler(const char[] actionNamespace, ActionHandlerCallback cb);

enum struct ClientAction {
    char steamid[32];
    char ns[64];
    char instanceId[64];
    char command[128];
    char input[512];
}

// Utility to get arguments from an action input.
methodmap UIActionEvent {
    public UIActionEvent(ArrayList list) {
        return view_as<UIActionEvent>(list);   
    }

    // 1 indexed. 0 returns full action string
    public void GetArg(int argNum, char[] output, int maxlen) {
        view_as<ArrayList>(this).GetString(argNum, output, maxlen);
    }
    public int GetArgInt(int argNum) {
        char buffer[32];
        this.GetArg(argNum, buffer, sizeof(buffer));
        return StringToInt(buffer);
    }
    public float GetArgFloat(int argNum) {
        char buffer[32];
        this.GetArg(argNum, buffer, sizeof(buffer));
        return StringToFloat(buffer);
    }
    
    public void _Delete() {
        delete view_as<ArrayList>(this);
    }

    property int Args {
        public get() { return view_as<ArrayList>(this).Length; }
    }
}

methodmap UIElement < JSONObject {
    public UIElement(const char[] elemNamespace, const char[] templateId, const char[] instanceId) {
        JSONObject obj = new JSONObject();
        obj.SetString("namespace", elemNamespace);
        obj.SetString("instance_id", instanceId);
        obj.SetString("template_id", templateId);
        obj.SetBool("visibility", false);
        obj.Set("steamids", new JSONArray());
        obj.Set("variables", new JSONObject());

        return view_as<UIElement>(obj);
    }

    property bool Visible {
		public get() {
            return view_as<JSONObject>(this).GetBool("visibility");
        }
        public set(bool value) {
            view_as<JSONObject>(this).SetBool("visibility", value);
        }
    }

    public void GetTemplateId(char[] buffer, int maxlen) {
        view_as<JSONObject>(this).GetString("template_id", buffer, maxlen);
    }

    public void GetInstanceId(char[] buffer, int maxlen) {
        view_as<JSONObject>(this).GetString("instance_id", buffer, maxlen);
    }

    public void SetVar(const char[] id, JSON json) {
        view_as<JSONObject>(this).Set(id, json);
    }
    
    public void SetVarInt(const char[] id, int value) {
        view_as<JSONObject>(this).SetInt(id, value);
    }
    
    public void SetVarFloat(const char[] id, float value) {
        view_as<JSONObject>(this).SetFloat(id, value);
    }

    public void SetVarString(const char[] id, const char[] value) {
        view_as<JSONObject>(this).SetString(id, value);
    }

    public void SetVarBool(const char[] id, bool value) {
        view_as<JSONObject>(this).SetBool(id, value);
    }

    public native bool SendAll();
    public native bool SendTo(int client);
    public bool SendToMultiple(int[] clientIds, int numClients) {
        for(int i = 0; i < numClients; i++) {
            this.SendTo(clientIds[i]);
        }
    }
}

methodmap UIPosition < JSONObject {
    public UIPosition(int x = 0, int y = 0) {
        JSONObject obj = new JSONObject();
        obj.SetInt("x", x);
        obj.SetInt("y", y);
        return view_as<UIPosition>(obj);
    }

    property int X {
        public get() { return view_as<JSONObject>(this).GetInt("x"); }
        public set(int coord) { view_as<JSONObject>(this).SetInt("x", coord); }
    }

    property int Y {
        public get() { return view_as<JSONObject>(this).GetInt("y"); }
        public set(int coord) { view_as<JSONObject>(this).SetInt("y", coord); }
    }
}

methodmap UISize < JSONObject {
    public UISize(int width, int height) {
        JSONObject obj = new JSONObject();
        obj.SetInt("width", width);
        obj.SetInt("height", height);
        return view_as<UISize>(obj);
    }

    property int Width {
        public get() { return view_as<JSONObject>(this).GetInt("width"); }
        public set(int value) { view_as<JSONObject>(this).SetInt("height", value); }
    }

    property int Height {
        public get() { return view_as<JSONObject>(this).GetInt("height"); }
        public set(int value) { view_as<JSONObject>(this).SetInt("height", value); }
    }
}

methodmap UIColor < JSONObject {
    /// Creates a new UIColor with RGB between 0-255, alpha is normalized 0.0-1.0
    public UIColor(int r = 255, int g = 255, int b = 255) {
        JSONObject obj = new JSONObject();
        obj.SetInt("r", r);
        obj.SetInt("g", g);
        obj.SetInt("g", b);
        return view_as<UIColor>(obj);
    }

    property int R {
        public get() { return view_as<JSONObject>(this).GetInt("r"); }
        public set(int value) { view_as<JSONObject>(this).SetInt("r", value); }
    }
    property int G {
        public get() { return view_as<JSONObject>(this).GetInt("g"); }
        public set(int value) { view_as<JSONObject>(this).SetInt("g", value); }
    }
    property int B {
        public get() { return view_as<JSONObject>(this).GetInt("b"); }
        public set(int value) { view_as<JSONObject>(this).SetInt("b", value); }
    }
}

enum UIVisibility {
    /// Always show
    Vis_Always = 0,
    /// Only show when overlay is in interact mode or edit mode
    Vis_InteractableOnly,
    /// Only show when overlay is in non-interactable mode or edit mode
    Vis_DisplayOnly
}

methodmap TempUIElementDefaults < JSONObject {
    public TempUIElementDefaults() {
        JSONObject obj = new JSONObject();
        obj.Set("position", new UIPosition(0, 0))
        obj.Set("bgColor", new UIColor());
        obj.SetInt("visibility", 0);
        return view_as<TempUIElementDefaults>(obj);
    }

    public bool GetTitle(char[] output, int maxlen) {
        view_as<JSONObject>(this).GetString("title", output, maxlen);
    }
    public bool SetTitle(const char[] title) {
        view_as<JSONObject>(this).SetString("title", title);
    }
    property UIPosition Position {
        public get() { return view_as<UIPosition>(view_as<JSONObject>(this).Get("position")); }
        // public set(UIPosition pos) { view_as<JSONObject>(this).Set("position", view_as<JSON>(pos)); }
    }
    property UIColor BackgroundColor {
        public get() { return view_as<UIColor>(view_as<JSONObject>(this).Get("bgColor")); }
        // public set(UIColor color) { view_as<JSONObject>(this).Set("bgColor", view_as<JSON>(color)); }
    }
    property UISize Size {
        public get() { return view_as<UISize>(view_as<JSONObject>(this).Get("size")); }
        // public set(UISize size) { view_as<JSONObject>(this).Set("size", view_as<JSON>(size)); }
    }
    /// Returns or sets opacity, -1 is not set
    property int Opacity {
        public get() {
            JSONObject obj = view_as<JSONObject>(this);
            if(!obj.HasKey("opacity")) return -1;
            return obj.GetInt("opacity");
        }
        public set(int value) {
            JSONObject obj = view_as<JSONObject>(this);
            if(value == -1) obj.Remove("opacity")
            else obj.SetInt("opacity", value);
        }
    }

    property UIVisibility Visibility {
        public get() {
            return view_as<UIVisibility>(view_as<JSONObject>(this).GetInt("visibility"));
        } 
        public set(UIVisibility value) {
            view_as<JSONObject>(this).SetInt("visibility", view_as<int>(value))
        }
    }

}

enum UIType {
    Element_Unknown = -1,
    Element_Text,
    Element_List,
    Element_Audio
}
enum UIFlags {
    Element_None
}

#define UI_TYPES_MAX 2
char UI_TYPE_IDS[UI_TYPES_MAX][] = {
    "text", // Element_Text
    "list" // Element_List
}


methodmap TempUIElement < JSONObject {
    public TempUIElement(const char[] type) {
        JSONObject obj = new JSONObject();
        obj.Set("defaults", new TempUIElementDefaults());
        obj.SetInt("flags", 0);
        obj.SetString("type", type);

        return view_as<TempUIElement>(obj);
    }

    property UIType Type {
        public get() {
            char type[32];
            view_as<JSONObject>(this).GetString("type", type, sizeof(type));
            for(int i = 0; i < UI_TYPES_MAX; i++) {
                if(StrEqual(type, UI_TYPE_IDS[i])) {
                    return view_as<UIType>(i);
                }
            }
            return Element_Unknown
        }
        public set(UIType type) {
            view_as<JSONObject>(this).SetString("type", UI_TYPE_IDS[view_as<int>(type)]);
        }
    }

    property TempUIElementDefaults Defaults {
        public get() { return view_as<TempUIElementDefaults>(view_as<JSONObject>(this).Get("defaults")); }
    }

    public void SetVariable(const char[] id, JSON json) {
        view_as<JSONObject>(this).Set(id, json);
    }

    public void SetVariableInt(const char[] id, int value) {
        view_as<JSONObject>(this).SetInt(id, value);
    }
    
    public void SetVariableFloat(const char[] id, float value) {
        view_as<JSONObject>(this).SetFloat(id, value);
    }

    public void SetVariableString(const char[] id, const char[] value) {
        view_as<JSONObject>(this).SetString(id, value);
    }

    public void SetVariableBool(const char[] id, bool value) {
        view_as<JSONObject>(this).SetBool(id, value);
    }
}
methodmap TextElement < TempUIElement {
    public TextElement() {
        TempUIElement elem = new TempUIElement("text");
        return view_as<TextElement>(elem);
    }

    public void GetTemplate(char[] output, int maxlen) {
        view_as<JSONObject>(this).GetString("template", output, maxlen);
    }
    public void SetTemplate(const char[] template) {
        view_as<JSONObject>(this).SetString("template", template);
    }
}

methodmap TempUI {
    /** Creates a new TempUI with an optional predefined option
     * @param elemId a unique id of temp element
     * @param The lifetime (in seconds) of element until element is deleted. 0 for never
    */
    public TempUI(const char[] elemId, const char[] type, int lifetime = 0) {
        JSONObject obj = new JSONObject();
        obj.SetString("elem_id", elemId);
        obj.Set("steamids", new JSONArray());
        obj.SetInt("expires_seconds", 0);
        TempUIElement element = new TempUIElement(type);
        obj.Set("element", element);
        return view_as<TempUI>(obj);
    }

    /// How long the temp UI lasts, 0 for never.
    property int Duration {
		public get() {
            return view_as<JSONObject>(this).GetInt("expires_seconds");
        }
        public set(int value) {
            view_as<JSONObject>(this).SetInt("expires_seconds", value);
        }
    }

    property bool Visible {
		public get() {
            return view_as<JSONObject>(this).GetBool("visibility");
        }
        public set(bool value) {
            view_as<JSONObject>(this).SetBool("visibility", value);
        }
    }

    property TempUIElement Element {
        public get() { 
            return view_as<TempUIElement>(view_as<JSONObject>(this).Get("element"));
        }
        public set(TempUIElement newElement) {
            // Delete old element
            JSON elem = view_as<JSONObject>(this).Get("element");
            if(elem != null) delete elem;

            view_as<JSONObject>(this).Set("element", view_as<JSON>(newElement));
        }
    }

    public void Clear() {
        view_as<JSONObject>(this).Clear();
    }

     public void Hide() {
        this.Visible = false;
    }
    public void Show() {
        this.Visible = true;
    }

    public native bool SendAll();
    public native bool SendTo(int client);
    public bool SendToMultiple(int[] clientIds, int numClients) {
        for(int i = 0; i < numClients; i++) {
            this.SendTo(clientIds[i]);
        }
    }
}

enum AudioState {
    // Audio stopped, reset to startTime
    Audio_Stopped,
    // Pauses audio at current time
    Audio_Paused,
    Audio_Play
}

// List of clients to send an element to. If empty, it will default to all connected clients.
methodmap ClientList < JSONArray {
    public ClientList() {
        return view_as<ClientList>(new JSONArray());
    }

    property int Length {
        public get() { return view_as<JSONArray>(this).Length; }
    }

    public native void AddClient(int client);

    public native bool HasClient(int client);

    public void Clear() {
        view_as<JSONArray>(this).Clear();
    }
}

methodmap AudioResource < JSONObject {
    public AudioResource(const char[] url, float volume = 0.5) {
        JSONObject obj = new JSONObject();
        obj.SetString("source", url);
        obj.SetFloat("volume", volume);
        obj.SetInt("state", 0);
        obj.Set("steamids", new JSONArray());
        obj.SetBool("repeat", false)
        return view_as<AudioResource>(obj);
    }

    property AudioState State {
        public get() {
            return view_as<AudioState>(view_as<JSONObject>(this).GetInt("state"));
        }
        public set(AudioState state) {
            view_as<JSONObject>(this).SetInt("state", view_as<int>(state));
        }
    }

    property float Volume {
        public get() {
            return view_as<JSONObject>(this).GetFloat("volume");
        }
        public set(float volume) {
            view_as<JSONObject>(this).SetFloat("volume", volume);
        }
    }

    property bool Repeat {
        public get() {
            return view_as<JSONObject>(this).GetBool("repeat");
        }
        public set(bool repeat) {
            view_as<JSONObject>(this).SetBool("repeat", repeat);
        }
    }

    property ClientList Clients {
        public get() {
            return view_as<ClientList>(view_as<JSONObject>(this).Get("steamids"));
        }
    } 
    /// Plays or resumes playing
    public native void Play();
    /// Stops playing audio, clients will reset to beginning
    public native void Stop();
    /// Pauses audio, resuming to current play duration
    public native void Pause();

    public void Clear() {
        view_as<JSONObject>(this).Clear();
    }
}

native int FindClientBySteamId2(const char[] steamid);

#if !defined REQUIRE_PLUGIN
public void __pl_overlay_SetNTVOptional() {
	MarkNativeAsOptional("IsOverlayConnected");
    MarkNativeAsOptional("RegisterActionAnyHandler");
    MarkNativeAsOptional("RegisterActionHandler");

	MarkNativeAsOptional("UIElement.SendAll");
	MarkNativeAsOptional("UIElement.SendTo");
	MarkNativeAsOptional("TempUI.SendAll");
	MarkNativeAsOptional("TempUI.SendTo");
    MarkNativeAsOptional("AudioResource.Play");
    MarkNativeAsOptional("AudioResource.Stop");
    MarkNativeAsOptional("AudioResource.Pause");

    MarkNativeAsOptional("FindClientBySteamId2");
}
#endif