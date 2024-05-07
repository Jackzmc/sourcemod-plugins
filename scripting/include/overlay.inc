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
    
    public void SetVariable(const char[] id, int value) {
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