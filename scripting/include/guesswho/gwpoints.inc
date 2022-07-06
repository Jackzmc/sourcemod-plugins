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