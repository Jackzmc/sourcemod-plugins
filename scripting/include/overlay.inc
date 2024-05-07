#if defined _overlay_included
	#endinput
#endif
#define _overlay_included
#include <ripext>

native bool SendTempUI(int client, const char[] id, int lifetime, JSONObject element);

native bool ShowUI(int client, const char[] elemNamespace, const char[] elemId, JSONObject variables);

native bool HideUI(int client, const char[] elemNamespace, const char[] elemId);

native bool PlayAudio(int client, const char[] url);

native bool IsOverlayConnected();

forward void OnUIAction(const char[] elemNamespace, const char[] elemId, const char[] action);

typedef UIActionCallback = function void (const char[][] args, int numArgs);

methodmap UIElement < JSONObject {
    public UIElement(const char[] elemNamespace, const char[] elemId) {
        JSONObject obj = new JSONObject();
        obj.SetString("namespace", elemNamespace);
        obj.SetString("elem_id", elemId);
        obj.SetBool("visibility", false);
        obj.Set("variables", new JSONObject());

        return view_as<UIElement>(obj);
    }

    property bool Visible {
		public get() {
            return view_as<JSONObject>(this).GetBool("visibility");
        }
        public set(bool value) {
            view_as<JSONObject>(this).SetBool("visibility", value);
            this.Send();
        }
    }

    /** Is the UI element globally sent to all connected players?
    *  Specify players with .AddClient() or clear with .ClearClients()
    */
    property bool Global {
        public get() {
            return !view_as<JSONObject>(this).HasKey("steamids")
        }
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

    public void SetActionCallback(UIActionCallback callback) {}

    public void AddClient(const char[] steamid) {
        // if(!IsClientInGame(client) || steamidCache[client][0] == '\0') ThrowError("Client %d is not connected, ingame, or authorized");
        JSONObject obj = view_as<JSONObject>(this);
        JSONArray steamids = view_as<JSONArray>(obj.Get("steamids"));
        if(steamids == null) {
            steamids = new JSONArray();
            obj.Set("steamids", steamids)
        }
        steamids.PushString(steamid);
    }

    public void ClearClients() {
        view_as<JSONObject>(this).Remove("steamids");
    }

    public void Clear() {
        view_as<JSONObject>(this).Clear();
    }

    public native bool Send();
}

methodmap UIPosition {
    public UIPosition(int x = 0, int y = 0) {
        JSONObject obj = new JSONObject();
        obj.SetInt("x", x);
        obj.SetInt("y", y);
        return view_as<UIPosition>(obj);
    }

    property int X {
        public get() { return view_as<JSONObject>(this).GetInt("x"); }
        public set(int coord) { return view_as<JSONObject>(this).SetInt("x", coord); }
    }

    property int Y {
        public get() { return view_as<JSONObject>(this).GetInt("y"); }
        public set(int coord) { return view_as<JSONObject>(this).SetInt("y", coord); }
    }
}

methodmap UIColor {
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
        public set(int value) { return view_as<JSONObject>(this).SetInt("r", value); }
    }
    property int G {
        public get() { return view_as<JSONObject>(this).GetInt("g"); }
        public set(int value) { return view_as<JSONObject>(this).SetInt("g", value); }
    }
    property int B {
        public get() { return view_as<JSONObject>(this).GetInt("b"); }
        public set(int value) { return view_as<JSONObject>(this).SetInt("b", value); }
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

methodmap TempUIElementDefaults {
    public TempUIElementDefaults() {
        JSONObject obj = new JSONObject();
        obj.Set("position", new UIPosition(0, 0))
        obj.Set("bgColor", new UIColor());
        obj.SetInt("visibility", 0);
        return view_as<TempUIElementDefaults>(obj);
    }

    public bool GetTitle(char[] output, int maxlen) {
        view_as<JSONObject>(this).GetString(output, maxlen);
    }
    public bool SetTitle(const char[] title) {
        view_as<JSONObject>(this).SetString(title);
    }
    property UIPosition Position {
        public get() { return view_as<JSONObject>(this).Get("position"); }
        public set(UIPosition pos) { view_as<JSONObject>(this).Set("position", pos); }
    }
    property UIColor BackgroundColor {
        public get() { return view_as<JSONObject>(this).Get("bgColor"); }
        public set(UIColor color) { view_as<JSONObject>(this).Set("bgColor", color); }
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
            if(value == -1) obj.remove("opacity")
            return obj.SetInt("opacity", value);
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
}

#define UI_TYPES_MAX 2
char UI_TYPE_IDS[UI_TYPES_MAX][] = {
    "text", // Element_Text
    "list" // Element_List
}


methodmap TempUIElement {
    public TempUIElement(const char[] type) {
        JSONObject obj = new JSONObject();
        obj.Set("defaults", new TempUIElementDefaults());
        obj.Set("flags", 0);
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
        public get() { return view_as<JSONObject>(this).Get("defaults"); }
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
        TempUIElement elem = new TempUIElement();
        elem.SetString("type", UI_TYPE_IDS[Element_Text]);
        return view_as<TextElement>(elem);
    }

    public void GetTemplate(char[] output, int maxlen) {
        return view_as<JSONObject>(this).GetString("template", output, maxlen);
    }
    public void SetTemplate(const char[] template) {
        return view_as<JSONObject>(this).SetString("template", template);
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
        TempUIElement element = new TempUIElement(type);
        obj.Set("element", element);
        return view_as<TempUI>(obj);
    }

    property bool Visible {
		public get() {
            return view_as<JSONObject>(this).GetBool("visibility");
        }
        public set(bool value) {
            view_as<JSONObject>(this).SetBool("visibility", value);
            this.Send();
        }
    }

    /** Is the UI element globally sent to all connected players?
    *  Specify players with .AddClient() or clear with .ClearClients()
    */
    property bool Global {
        public get() {
            return !view_as<JSONObject>(this).HasKey("steamids")
        }
    }

    property TempUIElement Element {
        public get() { 
            return view_as<JSONObject>(this).Get("element")
        }
        public set(TempUIElement newElement) {
            view_as<JSONObject>(this).Set("element", newElement);
        }
    }

    public void SetActionCallback(UIActionCallback callback) {}

    public void AddClient(const char[] steamid) {
        // if(!IsClientInGame(client) || steamidCache[client][0] == '\0') ThrowError("Client %d is not connected, ingame, or authorized");
        JSONObject obj = view_as<JSONObject>(this);
        JSONArray steamids = view_as<JSONArray>(obj.Get("steamids"));
        if(steamids == null) {
            steamids = new JSONArray();
            obj.Set("steamids", steamids)
        }
        steamids.PushString(steamid);
    }

    public void ClearClients() {
        view_as<JSONObject>(this).Remove("steamids");
    }

    public void Clear() {
        view_as<JSONObject>(this).Clear();
    }

    public native bool Send();

}