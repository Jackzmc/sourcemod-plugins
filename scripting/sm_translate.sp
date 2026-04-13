#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <system2>
#include <ripext>
#include <multicolors>

ConVar cvarTranslatePath;
char g_translatePath[64];

char g_desiredLangCode[8];

// JSONObject EMPTY_BODY;

public Plugin myinfo = {
    name =  "Translate Chat Messages", 
    author = "jackzmc", 
    description = "", 
    version = "1.0", 
    url = "https://github.com/Jackzmc/sourcemod-plugins"
};

/**
 * * ON CHAT MSG:
 *  1. Get target languages for ALL recipients, pass list to API
 * 
 * 
 * * ADD !t <CODE> <msg> command 
 * 
 */

public void OnPluginStart() {
    cvarTranslatePath = CreateConVar("sm_translate_api_path", "http://localhost:5000/translate", "The full protocol + host + path to the translation endpoint");
    cvarTranslatePath.AddChangeHook(OnPathChanged);
    cvarTranslatePath.GetString(g_translatePath, sizeof(g_translatePath));



    GetLanguageInfo(LANG_SERVER, g_desiredLangCode, sizeof(g_desiredLangCode), "", 0);

    RegConsoleCmd("sm_t", Command_Translate, "Manually translate sentence to english");

    AutoExecConfig(true, "sm_translate");
}

void OnPathChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
    strcopy(g_translatePath, sizeof(g_translatePath), newValue);
}

public void OnClientSayCommand_Post(int client, const char[] command, const char[] sArgs) {
    if(client > 0 && StrEqual(command, "say") && !IsFakeClient(client) && g_translatePath[0] != '\0') {
        CheckTranslate(client, sArgs, null);
    }
}

void MergeRemainingArgs(int argIndex, char[] output, int maxlen) {
    // Correct commands that don't wrap message in quotes
    int args = GetCmdArgs();
    if(args > argIndex) {
        char buffer[64];
        for(int i = argIndex; i <= args; i++) {
            GetCmdArg(i, buffer, sizeof(buffer));
            Format(output, maxlen, "%s %s", output, buffer);
        }
    }
}

Action Command_Translate(int client, int args) {
    if(args < 2) {
        char arg[4];
        GetCmdArg(0, arg, sizeof(arg));
        ReplyToCommand(client, "Syntax: %s LANG \"message in quotes\"", arg);
        return Plugin_Handled;
    }

    char code[4];
    GetCmdArg(1, code, sizeof(code));
    char msg[256];
    GetCmdArg(2, msg, sizeof(msg));

    MergeRemainingArgs(3, msg, sizeof(msg));

    ArrayList targets = new ArrayList();
    targets.PushString(code);

    CheckTranslate(client, msg, targets);

    return Plugin_Handled;
}

ArrayList GetTargetLanguages() {
    ArrayList list = new ArrayList();
    char code[8];
    for(int i = 1; i <= MaxClients; i++) {
        if(IsClientInGame(i) && !IsFakeClient(i)) {
            int langId = GetClientLanguage(i);
            GetLanguageInfo(langId, code, sizeof(code), "", 0);
            
            if(list.FindString(code) == -1) {
                list.PushString(code);
            }
        }
    }
    return list;
}

void JoinString(ArrayList list, int partMaxLength, char[] output, int maxlen) {
    char[] buffer = new char[partMaxLength];
    for(int i = 0; i < list.Length; i++) {
        list.GetString(i, buffer, partMaxLength);
        Format(output, maxlen, "%s%s%s", output, buffer, (i != list.Length - 1 ? "," : ""));
    }
}

/***
 * Attempts to automatically translate message into desired languages
 * @param client client user index that sent message
 * @param message message to translate
 * @param desiredLanguages a list of language code strings to translate. if null, will be populated with all online players' languages
 * @param skipCheck if true, skips the language check optimization and translates always
 */
void CheckTranslate(int client, const char[] message, ArrayList desiredLanguages = null) {
    if(desiredLanguages == null) desiredLanguages = GetTargetLanguages();

    int msgLen = strlen(message) * 2; 
    char[] msg = new char[msgLen];
    System2_URLEncode(msg, msgLen, "%s", message);

    char targets[32];
    JoinString(desiredLanguages, 4, targets, sizeof(targets));
    System2_URLEncode(targets, sizeof(targets), "%s", targets);
    delete desiredLanguages;

    static char buffer[256];
    Format(buffer, sizeof(buffer), "?text=%s&targets=%s", msg, targets);

    System2HTTPRequest request = new System2HTTPRequest(OnTranslateResponse, "%s%s", g_translatePath, buffer);
    request.Any = GetClientUserId(client);
    request.POST();
}

void OnTranslateResponse(bool success, const char[] error, System2HTTPRequest request, System2HTTPResponse response, HTTPRequestMethod method) {
    if(!response) {
        PrintToServer("Network error %s", error);
        return;
    } else if (response.StatusCode != 200) {
        LogError("Translate failed. Status %d", response.StatusCode);
        return;
    }
    /**
     *  result: "translated" | "skipped",
        source: string,
        target: string,

        text?: string,
     */
    char buffer[256];
    response.GetContent(buffer, sizeof(buffer));
    JSONObject obj = JSONObject.FromString(buffer);
    char srcLang[8];
    obj.GetString("source", srcLang, sizeof(srcLang));

    JSONArray translations = view_as<JSONArray>(obj.Get("translations"));
    JSONObject result;
    char lang[8];
    int client = GetClientOfUserId(request.Any);
    for(int i = 0; i < translations.Length; i++) {
        result = view_as<JSONObject>(translations.Get(i));
        result.GetString("lang", lang, sizeof(lang));
        result.GetString("text", buffer, sizeof(buffer));

        SendTranslation(client, srcLang, lang, buffer);
    }
}

bool SendTranslation(int sourceClient, const char[] srcLangCode, const char[] targetLangCode, const char[] msg) {
    int langId = GetLanguageByCode(targetLangCode);
    if(langId == -1) {
        PrintToServer("[Translations] WARN: Unknown language code \"%s\"", targetLangCode);
        return false;
    }

    for(int i = 1; i <= MaxClients; i++) {
        if(IsClientInGame(i) && !IsFakeClient(i)) {
            int targetLangId = GetClientLanguage(i);
            if(targetLangId == langId)
                C_PrintToChat(sourceClient, "{olive}[%s] %N: %s", srcLangCode, sourceClient, msg);
        }
    }
    return true;
}