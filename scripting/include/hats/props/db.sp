#define DATABASE_CONFIG_NAME "hats_editor"
Database g_db;

bool ConnectDB() {
	char error[255];
	Database db = SQL_Connect(DATABASE_CONFIG_NAME, true, error, sizeof(error));
	if (db == null) {
		LogError("Database error %s", error);
		return false;
	} else {
		PrintToServer("l4d2_hats: Connected to database %s", DATABASE_CONFIG_NAME);
		db.SetCharset("utf8mb4");
		g_db = db;
		return true;
	}
}

void DB_GetFavoritesCallback(Database db, DBResultSet results, const char[] error, int userid) {
	if(results == null) {
		PrintToServer("l4d2_hats: DB_GetFavoritesCallback returned error: \"%s\"", error);
	}
	int client = GetClientOfUserId(userid);
	if(client > 0) {
		if(results == null) {
			PrintToChat(client, "\x04[Editor]\x01 Error occurred fetching favorites");
			return;
		}
		ArrayList list = new ArrayList(sizeof(ItemData));
		ItemData item;
		while(results.FetchRow()) {
			results.FetchString(0, item.model, sizeof(item.model));
			DBResult result;
			results.FetchString(1, item.name, sizeof(item.name), result);
			if(result == DBVal_Null) {
				// No name set - use the end part of the model
				int index = FindCharInString(item.model, '/', true);
				strcopy(item.name, sizeof(item.name), item.model[index + 1]);
			}
		}
		ShowTempItemMenu(client, list, "Favorites");
	}
}

void DB_ToggleFavoriteCallback(Database db, DBResultSet results, const char[] error, DataPack pack) {
	if(results == null) {
		PrintToServer("l4d2_hats: DB_GetFavoriteCallback returned error: \"%s\"", error);
	}
	pack.Reset();
	int userid = pack.ReadCell();
	int client = GetClientOfUserId(userid);
	if(client > 0) {
		if(results == null) {
			PrintToChat(client, "\x04[Editor]\x01 Error occurred fetching favorite data");
			delete pack;
			return;
		}
		char query[256];
		char model[128];
		char steamid[32];
		GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid));
		pack.ReadString(model, sizeof(model));
		if(results.FetchRow()) {
			// Model was favorited, erase it
			g_db.Format(query, sizeof(query), "DELETE FROM editor_favorites WHERE steamid = '%s' AND model = '%s'", steamid, model);
			g_db.Query(DB_DeleteFavoriteCallback, query, userid);
		} else {
			// Model is not favorited, save it.
			char name[64];
			pack.ReadString(name, sizeof(name));
			// TODO: calculate next position automatically
			int position = 0;
			g_db.Format(query, sizeof(query), 
				"INSERT INTO editor_favorites (steamid, model, name, position) VALUES ('%s', '%s', '%s', %d)", 
				steamid, model, name, position
			);
			g_db.Query(DB_InsertFavoriteCallback, query, pack);
		}
	} else {
		// Only delete if we lost client - otherwise we will reuse it
		delete pack;
	}
}

void DB_DeleteFavoriteCallback(Database db, DBResultSet results, const char[] error, DataPack pack) {
	if(results == null) {
		PrintToServer("l4d2_hats: DB_DeleteFavoriteCallback returned error: \"%s\"", error);
	}
	pack.Reset();
	char model[128];
	char name[64];
	int client = GetClientOfUserId(pack.ReadCell());
	if(client > 0) {
		if(results == null) {
			PrintToChat(client, "\x04[Editor]\x01 Could not delete favorite");
			delete pack;
			return;
		}
		pack.ReadString(model, sizeof(model));
		pack.ReadString(name, sizeof(name));
		int index = FindCharInString(model, '/', true);
		PrintToChat(client, "\x04[Editor]\x01 Removed favorite: \"%s\" \x05(%s)", model[index], name);
	}
	delete pack;
}
void DB_InsertFavoriteCallback(Database db, DBResultSet results, const char[] error, DataPack pack) {
	if(results == null) {
		PrintToServer("l4d2_hats: DB_InsertFavoriteCallback returned error: \"%s\"", error);
	}
	pack.Reset();
	char model[128];
	char name[64];
	int client = GetClientOfUserId(pack.ReadCell());
	if(client > 0) {
		if(results == null) {
			PrintToChat(client, "\x04[Editor]\x01 Could not add favorite");
			delete pack;
			return;
		}
		pack.ReadString(model, sizeof(model));
		pack.ReadString(name, sizeof(name));
		int index = FindCharInString(model, '/', true);
		PrintToChat(client, "\x04[Editor]\x01 Added favorite: \"%s\" \x05(%s)", model[index], name);
	}
	delete pack;
}