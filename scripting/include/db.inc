static Database _conn;
static DatabaseManager _manager;
static char _dbName[64];
static float _inactiveTimeoutTime;

// TODO: log optional

/**  */
static Handle _gameEndTimer = null;
DatabaseManager DB_Init(const char[] databaseName, float idleTimeoutTime = 60.0) {
    if(!SQL_CheckConfig(databaseName)) {
        SetFailState("No database entry for %s; no database to connect to.", databaseName);
    }
    HookEvent("player_connect", Event_PlayerConnect);
    HookEvent("game_end", Event_GameEnd);
    strcopy(_dbName, sizeof(_dbName), databaseName);
    _inactiveTimeoutTime = idleTimeoutTime;
    return _manager;
}

/**
 * Attempts to connect to DB, returning true on success or if already connected
 * Returns false if not connected
 */
bool DB_TryConnect() {
    if(_gameEndTimer != null) {
        Log(Log_Debug, Target_ServerConsole, "cancelling idle timer");
        // TODO: if it gets cancelled, the next time it triggers would be after game ends again
        // do we need to add one on Query()
        delete _gameEndTimer;
    }
    if(_conn != null) return true; // already connected
    static char error[255];
    _conn = SQL_Connect(_dbName, true, error, sizeof(error));
    if (_conn == null) {
        Log(Log_Error, Target_ServerConsole, "Database error %s", error);
        delete _conn;
        return false;
    } else {
        SQL_LockDatabase(_conn);
        SQL_FastQuery(_conn, "SET NAMES \"UTF8mb4\"");  
        SQL_UnlockDatabase(_conn);
        _conn.SetCharset("utf8mb4");
        Log(Log_Info, Target_ServerConsole, "Opened connection to database " ... DB_NAME);
        return true;
    }
}
/**
 * Closes DB if connected
 */
void DB_Close() {
    if(_conn != null) {
        Log(Log_Info, Target_ServerConsole, "Closed connection to database");
        delete _conn;
    }
}
static Action Timer_CloseDB(Handle h) {
    DB_Close();
    return Plugin_Handled;
}

/** Creates a timer that closes DB. Kill this timer to cancel */
Handle DB_CloseDelayed(float time) {
    return CreateTimer(time, Timer_CloseDB);
}

void Event_PlayerConnect(Event event, const char[] name, bool dontBroadcast) {
    // Ensure we have a connection to db when a player is connecting
    DB_TryConnect();
}

void Event_GameEnd(Event event, const char[] name, bool dontBroadcast) {
    // TODO: min time interval to start end timer for any minor time delay
    _gameEndTimer = DB_CloseDelayed(_inactiveTimeoutTime);
}

// A reconnectable database
// Only supports one instance
methodmap DatabaseManager {
    public static DatabaseManager Init(const char[] databaseName, float idleTimeoutTime = 60.0) {
        return DB_Init(databaseName, idleTimeoutTime);
    }

    property bool Connected {
        public get() {
            return _conn != null;
        }
    }

    /** Returns conn to database, if connected */
    property Database Database {
        public get() {
            return _conn;
        }
    }

    /**
     * Attempts to connect to DB, returning true on success or if already connected
     * Returns false if not connected
     */
    public bool TryConnect() {
        return DB_TryConnect();
    }

    public void Disconnect() {
        DB_Close();
    }

    public Database GetConn() {
        if(!this.Connected) {
            if(!this.TryConnect()) {
                ThrowError("Not connected to database and failed to retry");
            }
        } 
        return this.Database;
    }

	// Returns the driver for this database connection.
	property DBDriver Driver {
		public get() {
            Database db = this.GetConn();
            return db.Driver;
        }
	}

	// Sets the character set of the connection. 
	// Like SET NAMES .. in mysql, but stays after connection problems.
	// 
	// Example: "utf8", "latin1"
	//
	// @param charset       The character set string to change to.
	// @return              True, if character set was changed, false otherwise.
	public bool SetCharset(const char[] charset) {
        Database db = this.GetConn();
        return db.SetCharset(charset);
    }

	// Escapes a database string for literal insertion.  This is not needed
	// for binding strings in prepared statements.  
	//
	// Generally, database strings are inserted into queries enclosed in 
	// single quotes (').  If user input has a single quote in it, the 
	// quote needs to be escaped.  This function ensures that any unsafe 
	// characters are safely escaped according to the database engine and 
	// the database's character set.
	//
	// NOTE: SourceMod only guarantees properly escaped strings when the query
	// encloses the string in single quotes. While drivers tend to allow double
	// quotes (") instead, the string may be not be escaped (for example, on SQLite)!
	//
	// @param string        String to quote.
	// @param buffer        Buffer to store quoted string in.
	// @param maxlength     Maximum length of the buffer.
	// @param written       Optionally returns the number of bytes written.
	// @return              True on success, false if buffer is not big enough.
	//                      The buffer must be at least 2*strlen(string)+1.
	public bool Escape(const char[] string, char[] buffer, int maxlength, int &written=0) {
        Database db = this.GetConn();
        return db.Escape(string, buffer, maxlength, written);
    }

	// Returns whether a database is the same connection as another database.
	public bool IsSameConnection(Database other) {
        Database db = this.GetConn();
        return db.IsSameConnection(other);
    }

	// Executes a query via a thread. The result handle is passed through the
	// callback.
	//
	// The database handle returned through the callback is always a new Handle,
	// and if necessary, IsSameConnection() should be used to test against other
	// connections.
	//
	// The result handle returned through the callback is temporary and destroyed 
	// at the end of the callback.
	//
	// @param callback       Callback.
	// @param query          Query string.
	// @param data           Extra data value to pass to the callback.
	// @param prio           Priority queue to use.
	public void Query(SQLQueryCallback callback, const char[] query,
	                         any data = 0,
	                         DBPriority prio = DBPrio_Normal) 
    {
        Database db = this.GetConn();
        db.Query(callback, query, data, prio);
    }

	// Sends a transaction to the database thread. The transaction handle is
	// automatically closed. When the transaction completes, the optional
	// callback is invoked.
	//
	// @param txn            A transaction handle.
	// @param onSuccess      An optional callback to receive a successful transaction.
	// @param onError        An optional callback to receive an error message.
	// @param data           An optional value to pass to callbacks.
	// @param prio           Priority queue to use.
	public void Execute(Transaction txn,
	                           SQLTxnSuccess onSuccess = INVALID_FUNCTION,
	                           SQLTxnFailure onError = INVALID_FUNCTION,
	                           any data = 0,
	                           DBPriority priority = DBPrio_Normal)
    {
        Database db = this.GetConn();
        db.Execute(txn, onSuccess, onError, data, priority);
    }
}
