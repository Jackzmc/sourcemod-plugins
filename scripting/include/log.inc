#if defined _log_included
    #endinput
#endif
#define _log_included
#define LOG_BUFFER_SIZE 1024

int LOG_LEVEL = Log_Info;

enum LogLevel {
    Log_Error = 1,
    Log_Warn = 2,
    Log_Info = 3,
    Log_Debug = 4,
    Log_Trace = 5,
    Log__MaxLevels
}
char LOG_LEVEL_PREFIX[Log__MaxLevels][] = {
    "-",
    "ERROR",
    "WARN",
    "INFO",
    "DEBUG",
    "TRACE"
};

static int adminFlag;
static char logPrefix[64] = "LOG_CALL_Log_Init_FIRST";
static char adminCmd[64];
static int defaultTargets;

void Log_Init(const char[] prefix, LogLevel level, int admFlag = ADMFLAG_GENERIC, const char[] admCmd = "sm_kick", int _defaultTargets = Target_Console) {
    strcopy(logPrefix, sizeof(logPrefix), prefix);
    LOG_LEVEL = level;
    adminFlag = admFlag;
    strcopy(adminCmd, sizeof(adminCmd), admCmd);
    defaultTargets = _defaultTargets;
}

public void PrintToConsoleAdmins(const char[] format, any ...) {
	char buffer[255];
	VFormat(buffer, sizeof(buffer), format, 2);
	for(int i = 1; i < MaxClients; i++) {
		if(IsClientInGame(i)) {
            if(CheckCommandAccess(i, adminCmd, adminFlag)) {
				PrintToConsole(i, "%s", buffer);
            }
		}
	}
}

public void PrintToChatAdmins(const char[] format, any ...) {
	char buffer[255];
	VFormat(buffer, sizeof(buffer), format, 2);
	for(int i = 1; i < MaxClients; i++) {
		if(IsClientInGame(i)) {
            if(CheckCommandAccess(i, adminCmd, adminFlag)) {
				PrintToChat(i, "%s", buffer);
            }
		}
	}
}

enum LogTargets {
    /// Logs to server console (LogMessage)
    Target_ServerConsole = 1,
    /// Logs to all admins' consoles (if they have sm_ban permission)
    Target_AdminConsole = 2,
    /// Logs to all admins' chats (if they have sm_ban permission)
    Target_AdminChat = 4,

    /// Logs to all targets (ServerConsole + AdminConsole + AdminChat)
    Target_All = Target_ServerConsole | Target_AdminConsole | Target_AdminChat,
    /// Logs to only admin console and server console
    Target_Console = Target_ServerConsole | Target_AdminConsole
}

/// Logs to specified targets at specified level 
public void Log(LogLevel level, int targets, const char[] format, any ...) {
    if(view_as<int>(level) > view_as<int>(LOG_LEVEL)) return;

    char buffer[LOG_BUFFER_SIZE];
	VFormat(buffer, sizeof(buffer), format, 4);

    _log(level, targets, buffer);
}

public void LogWarn(const char[] format, any ...) {
    char buffer[LOG_BUFFER_SIZE];
	VFormat(buffer, sizeof(buffer), format, 2);
    _log(Log_Warn, defaultTargets, buffer);
}

public void LogInfo(const char[] format, any ...) {
    char buffer[LOG_BUFFER_SIZE];
	VFormat(buffer, sizeof(buffer), format, 2);
    _log(Log_Info, defaultTargets, buffer);
}

public void LogDebug(const char[] format, any ...) {
    char buffer[LOG_BUFFER_SIZE];
	VFormat(buffer, sizeof(buffer), format, 2);
    _log(Log_Debug, defaultTargets, buffer);
}

public void LogTrace(const char[] format, any ...) {
    char buffer[LOG_BUFFER_SIZE];
	VFormat(buffer, sizeof(buffer), format, 2);
    _log(Log_Trace, defaultTargets, buffer);
}


void _log(LogLevel level, int targets, const char[] msg) {
    if(view_as<int>(level) > view_as<int>(LOG_LEVEL)) return;

    // Use LogError for errors shown to server console. 
    if(level == Log_Error) {
        LogError("%s", msg);
    } else {
        LogMessage("%s: %s", LOG_LEVEL_PREFIX[level], msg);
    }

    // Log to any configured targets
    if(targets & view_as<int>(Target_AdminConsole) == view_as<int>(Target_AdminConsole))
        PrintToConsoleAdmins("[%s] [%s] %s", logPrefix, LOG_LEVEL_PREFIX[level], msg);
    if(targets &  view_as<int>(Target_AdminChat) ==  view_as<int>(Target_AdminChat))
        PrintToChatAdmins("[%s] [%s] %s", logPrefix, LOG_LEVEL_PREFIX[level], msg);
}

/// Use this change hook callback to automatically set LOG_LEVEL to a cvar's value
public void LOG_OnCvarChange(ConVar convar, const char[] oldValue, const char[] newValue) {
    #pragma unused oldValue
    #pragma unused newValue
	LOG_LEVEL = convar.IntValue;
    LogMessage("Log level changed to %s", LOG_LEVEL_PREFIX[LOG_LEVEL]);
}

public ConVar Log_CreateCvar(const char[] cvar, LogLevel defaultLevel) {
    char buffer[2];
    IntToString(defaultLevel, buffer, sizeof(buffer));

    ConVar cv = CreateConVar(cvar, buffer, "Set the highest level to show logs for.\n1: ERROR\n2: WARN\n3: INFO\n4: DEBUG\n5: TRACE", FCVAR_NONE, true, 1.0, true, 5.0);
    cv.AddChangeHook(LOG_OnCvarChange);
    return cv;
}