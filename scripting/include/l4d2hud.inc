//Sourcemod Wrapper around the L4D2 EMS Hud System
//Created by https://github.com/Jackzmc
//See it here: https://github.com/Jackzmc/sourcemod-plugins/blob/master/scripting/include/l4d2hud.inc

enum hudPosition {
    HUD_POSITION_FAR_LEFT, 
    HUD_POSITION_FAR_RIGHT,
    HUD_POSITION_RIGHT_TOP, 
    HUD_POSITION_RIGHT_BOT,
    HUD_POSITION_MID_TOP, 
    HUD_POSITION_MID_BOT,
    HUD_POSITION_LEFT_TOP, 
    HUD_POSITION_LEFT_BOT,
    HUD_POSITION_TICKER,
    HUD_POSITION_MID_BOX,
    HUD_POSITION_SCORE_TITLE,
    HUD_POSITION_SCORE_1, 
    HUD_POSITION_SCORE_2, 
    HUD_POSITION_SCORE_3, 
    HUD_POSITION_SCORE_4
};

char hudPositions[17][] = {
    "FAR_LEFT",
    "RIGHT_TOP",
    "RIGHT_BOT",
    "MID_TOP",
    "MID_BOT",
    "SCORE_3",
    "LEFT_TOP",
    "LEFT_BOT",
    "TICKER",
    "MID_BOX",
    "FAR_LEFT",
    "FAR_RIGHT",
    "SCORE_TITLE",
    "SCORE_1",
    "SCORE_2",
    "SCORE_3",
    "SCORE_4"
};

enum hudFlag {
    HUD_FLAG_PRESTR = 1,
    HUD_FLAG_POSTSTR = 2,
    HUD_FLAG_BEEP = 4,
    HUD_FLAG_BLINK = 8,
    HUD_FLAG_COUNTDOWN_WARN = 16,
    HUD_FLAG_NOBG = 32,
    HUD_FLAG_ALLOWNEGTIMER = 64,
    HUD_FLAG_SHOW_TIME = 128,
    HUD_FLAG_NOTVISIBLE = 256,
    HUD_FLAG_ALIGN_LEFT = 512,
    HUD_FLAG_ALIGN_CENTER = 1024,
    HUD_FLAG_ALIGN_RIGHT = 2048,
    HUD_FLAG_TEAM_SURVIVORS = 4096,
    HUD_FLAG_TEAM_INFECTED = 8192,
    HUD_FLAG_AS_TIME = 16384,
    HUD_FLAG_TEAM_MASK = 32768
};

char hudFlags[16][16] = {
    "PRESTR",
    "POSTSTR",
    "BEEP",
    "BLINK",
    "COUNTDOWN_WARN",
    "NOBG",
    "ALLOWNEGTIMER",
    "SHOW_TIME",
    "NOTVISIBLE",
    "ALIGN_LEFT",
    "ALIGN_CENTER",
    "ALIGN_RIGHT",
    "TEAM_SURVIVORS",
    "TEAM_INFECTED",
    "AS_TIME",
    "TEAM_MASK",
};

char huds[15][1024];

void SetupHUD(hudPosition position, int flags, float x, float y, float w, float h) {
    if(x > 1.0 || x < 0.0) {
        ThrowError("HUD X Coordinate must be between 0.0 - 1.0");
    }else if(y > 1.0 || y < 0.0) {
        ThrowError("HUD Y Coordinate must be between 0.0 - 1.0");
    }else if(w > 1.0 || w < 0.0) {
        ThrowError("HUD Width must be between 0.0 - 1.0");
    }else if(h > 1.0 || h < 0.0) {
        ThrowError("HUD Height must be between 0.0 - 1.0");
    }

    char buffer[256];
    if(flags > 0) {
        ArrayList flagStrings = new ArrayList(ByteCountToCells(16));

        for(int i = 0; i < sizeof(hudFlags); i++) {
            int flag = RoundFloat(Pow(2.0, float(i)));
            if(flags & flag == flag) {
                flagStrings.PushString(hudFlags[i]);
            }
        }


        char flagBuffer[16];
        for(int i = 0; i < flagStrings.Length; i++) {
            flagStrings.GetString(i, flagBuffer, sizeof(flagBuffer));
            PrintToServer("flag[%d] = %s", i, flagBuffer);
            if(i == flagStrings.Length - 1) {
                Format(buffer, sizeof(buffer), "%s g_ModeScript.HUD_FLAG_%s", buffer, flagBuffer);
            } else {
                Format(buffer, sizeof(buffer), "%s g_ModeScript.HUD_FLAG_%s |", buffer, flagBuffer);
            }
        }
        delete flagStrings;

        Format(buffer, sizeof(buffer), "flags = %s,", buffer);
    }


    int id = view_as<int>(position);
    Format(huds[id], 1024, "SMHud%d <- { Fields = { players = { slot = g_ModeScript.HUD_%s, dataval = \"%%s\", %s name = \"smhud%d\" } } }; HUDSetLayout( SMHud%d ); HUDPlace( g_ModeScript.HUD_%s, %f, %f, %f, %f )", id, hudPositions[id], buffer, id, id, hudPositions[id], x, y, w, h);
    L4D2_RunScript(huds[id], "");
}

void SetHUDText(hudPosition position, const char[] format, any ...) {
    if(huds[view_as<int>(position)][0] == '\0') {
        ThrowError("HUD at position was not setup.");
    }
    static char sBuffer[1024];
    VFormat(sBuffer, sizeof(sBuffer), format, 3);

    L4D2_RunScript(huds[view_as<int>(position)], sBuffer);
}

bool IsHUDSetup(hudPosition position) {
    return huds[view_as<int>(position)][0] != '\0';
}

void DeleteHUD(hudPosition position) {
    L4D2_RunVScript("SMHud%d <- { Fields = { } }; HUDSetLayout(SMHud%d); HUDPlace( g_ModeScript.HUD_%s, 0.0, 0.0, 0.0, 0.0 ); g_ModeScript", view_as<int>(position), view_as<int>(position), hudPositions[positions]);
    huds[view_as<int>(position)][0] = '\0';
}

void GetHUDFormatString(hudPosition position, char[] buffer, int buffersize) {
    strcopy(buffer, buffersize, huds[view_as<int>(position)]);
}

#define MAX_MESSAGES 6
#define MESSAGE_DURATION 40
#define MAX_MESSAGE_LENGTH 64
#define MESSAGE_UPDATE_INTERVAL 0.8
//This is hard coded into engine:
#define MAX_HUD_LENGTH 1023

hudPosition MSG_HUD_POS; 

char messages[MAX_MESSAGES][MAX_MESSAGE_LENGTH];
char lastMsgFull[];
int msgExpiresTime;
Handle msgTimer;

void SetupMessageHud(hudPosition position) {
    MSG_HUD_POS = position;
    SetupHUD(MSG_HUD_POS, HUD_FLAG_ALIGN_LEFT | HUD_FLAG_NOBG | HUD_FLAG_TEAM_SURVIVORS, 0.0, 0.0, 1.0, 1.0);
    msgTimer = CreateTimer(MESSAGE_UPDATE_INTERVAL, Timer_ProcessMessages, _, TIMER_REPEAT);
}

void CloseMessageHud() {
    if(msgTimer != null)
        CloseHandle(msgTimer);
    ClearMessages();
}
//TODO: Replace repeat timer, just use one-time delay, only add one
//Internally process and print all messages
void Timer_ProcessMessages(Handle h) {
    if(GetGameTime() > msgExpiresTime) {
        messages.Erase(0);
        msgExpiresTime = GetGameTime() + MESSAGE_DURATION;
    }
    char buffer[MAX_HUD_LENGTH];
    for(int i = 0; i < messages.Length; i++) {
        ImplodeStrings(messages, MAX_MESSAGES, "\\n", buffer, sizeof(buffer));
    }
    SetHUDText(MSG_HUD_POS, buffer);
}

//Adds a message to the message queue
void AddMessageToHud(const char msg[MAX_MESSAGE_LENGTH]) {
    for(int i = 1; i < MAX_MESSAGES - 1; i++) {
        strcopy(messages[i], MAX_MESSAGE_LENGTH, messages[i+1]);
    }
    strcopy(messages[MAX_MESSAGES-1], MAX_MESSAGE_LENGTH, msg);
}
//Clears all messages
void ClearMessageHud() {
    for(int i = 0; i < MAX_MESSAGES; i++) {
        messages[i][0] = '\0';
    }
}

stock void L4D2_RunVScript(const char[] sCode, any ...) {
	static int iScriptLogic = INVALID_ENT_REFERENCE;
	if(iScriptLogic == INVALID_ENT_REFERENCE || !IsValidEntity(iScriptLogic)) {
		iScriptLogic = EntIndexToEntRef(CreateEntityByName("logic_script"));
		if(iScriptLogic == INVALID_ENT_REFERENCE|| !IsValidEntity(iScriptLogic))
			SetFailState("Could not create 'logic_script'");
		
		DispatchSpawn(iScriptLogic);
	}
	
	static char sBuffer[512];
	VFormat(sBuffer, sizeof(sBuffer), sCode, 2);
	
	SetVariantString(sBuffer);
	AcceptEntityInput(iScriptLogic, "RunScriptCode");
}