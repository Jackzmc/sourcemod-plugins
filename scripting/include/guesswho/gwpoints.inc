enum struct LocationMeta {
	float pos[3];
	float ang[3];
	bool runto;
	bool jump;
	int attempts; // # of attempts player has moved until they will try to manage
}

// Game settings
LocationMeta activeBotLocations[MAXPLAYERS+1];

methodmap MovePoints < ArrayList {
    public MovePoints() {
	    return view_as<MovePoints>(new ArrayList(sizeof(LocationMeta)));
    }

    public bool SaveMap(const char[] map, const char[] set = "default") {
        char buffer[256];
        // guesswho folder should be created by ReloadMapDB
        BuildPath(Path_SM, buffer, sizeof(buffer), "data/guesswho/%s", map);
        CreateDirectory(buffer, FOLDER_PERMS);
        BuildPath(Path_SM, buffer, sizeof(buffer), "data/guesswho/%s/%s.txt", map, set);
        File file = OpenFile(buffer, "w+");
        if(file != null) {
            file.WriteLine("px\tpy\tpz\tax\tay\taz");
            LocationMeta meta;
            for(int i = 0; i < movePoints.Length; i++) {
                movePoints.GetArray(i, meta);
                file.WriteLine("%.1f %.1f %.1f %.1f %.1f %.1f", meta.pos[0], meta.pos[1], meta.pos[2], meta.ang[0], meta.ang[1], meta.ang[2]);
            }
            PrintToServer("[GuessWho] Saved %d locations to %s/%s.txt", movePoints.Length, map, set);
            file.Flush();
            delete file;
            return true;
        }
        PrintToServer("[GuessWho] OpenFile(w+) returned null for %s", buffer);
        return false;
    }

    public static MovePoints LoadMap(const char[] map, const char[] set = "default") {
        char buffer[256];
        BuildPath(Path_SM, buffer, sizeof(buffer), "data/guesswho/%s/%s.txt", map, set);
        LoadConfigForMap(map);
        File file = OpenFile(buffer, "r+");
        if(file != null) {
            char line[64];
            char pieces[16][6];
            file.ReadLine(line, sizeof(line)); // Skip header
            float min = L4D2Direct_GetMapMaxFlowDistance();
            float max = 0.0;
            MovePoints points = new MovePoints(); 
            while(file.ReadLine(line, sizeof(line))) {
                ExplodeString(line, " ", pieces, 6, 16, false);
                LocationMeta meta;
                meta.pos[0] = StringToFloat(pieces[0]);
                meta.pos[1] = StringToFloat(pieces[1]);
                meta.pos[2] = StringToFloat(pieces[2]);
                meta.ang[0] = StringToFloat(pieces[3]);
                meta.ang[1] = StringToFloat(pieces[4]);
                meta.ang[2] = StringToFloat(pieces[5]);

                // Calculate the flow bounds
                Address nav = L4D2Direct_GetTerrorNavArea(meta.pos);
                if(nav == Address_Null) {
                    nav = L4D_GetNearestNavArea(meta.pos);
                    if(nav == Address_Null) {
                        PrintToServer("[GuessWho] WARN: POINT AT (%f,%f,%f) IS INVALID (NO NAV AREA); skipping", meta.pos[0], meta.pos[1], meta.pos[2]);
                        continue;
                    }
                }
                float flow = L4D2Direct_GetTerrorNavAreaFlow(nav);
                if(flow < min) min = flow;
                else if(flow > max) max = flow;

                points.AddPoint(meta);
            }
            // Give some buffer space, to not trigger TOO FAR
            min -= FLOW_BOUND_BUFFER;
            max += FLOW_BOUND_BUFFER;

            movePoints.SetBounds(flowMin, flowMax);

            PrintToServer("[GuessWho] Loaded %d locations (bounds (%.0f, %.0f)) for %s/%s", movePoints.Length, min, max, map, set);
            delete file;
            return points;
        }
        PrintToServer("[GuessWho] OpenFile(r+) returned null for %s", buffer);
        return null;
    }

    property float MinFlow {
        public get() { return flowMin; }
    }
    property float MaxFlow {
        public get() { return flowMax; }
    }

    public void SetBounds(float min, float max) {
        flowMin = min;
        flowMax = max;
    }

    public void GetRandomPoint(LocationMeta meta) {
        meta.runto = GetURandomFloat() < BOT_MOVE_RUN_CHANCE;
        meta.attempts = 0;
        this.GetArray(GetURandomInt() % this.Length, meta);
        #if defined DEBUG_SHOW_POINTS
        Effect_DrawBeamBoxRotatableToAll(meta.pos, DEBUG_POINT_VIEW_MIN, DEBUG_POINT_VIEW_MAX, NULL_VECTOR, g_iLaserIndex, 0, 0, 0, 150.0, 0.1, 0.1, 0, 0.0, {255, 0, 255, 120}, 0);
        #endif
    }

    public bool GetRandomPointFar(const float src[3], float pos[3], float distanceAway = 100.0, int tries = 3) {
        while(tries-- > 0) {
            this.GetArray(GetURandomInt() % this.Length, pos);
            if(FloatAbs(GetVectorDistance(src, pos)) > distanceAway) {
                return true;
            }
        }
        return false;
    }

    public bool AddPoint(LocationMeta meta) {
        bool hitLimit = false;
        if(this.Length + 1 > MAX_VALID_LOCATIONS) {
            PrintToServer("[GuessWho] Hit MAX_VALID_LOCATIONS (%d), clearing some locations", MAX_VALID_LOCATIONS);
            this.Sort(Sort_Random, Sort_Float);
            this.Erase(RoundFloat(MAX_VALID_LOCATIONS * MAX_VALID_LOCATIONS_KEEP_PERCENT));
            hitLimit = true;
        }
        this.PushArray(meta);
        return hitLimit;
    }
}