
Action Timer_ExplodeBomb(Handle h, DataPack pack) {
	pack.Reset();
	int userid = pack.ReadCell();
	int client = GetClientOfUserId(userid);
	int tick = pack.ReadCell();
	int maxTicks = pack.ReadCell();
	if(client > 0) {
		// finish check
		if(tick >= maxTicks) {
			// StopSound(client, SNDCHAN_USER_BASE, SOUND_EXPLODE_BOMB);
			// SetEntityRenderColor(client, 255, 255, 255);
			// SetEntityRenderMode(client, RENDER_NORMAL);
			EmitSoundToAll(SOUND_EXPLODE_BOMB, client, SNDCHAN_USER_BASE, SNDLEVEL_SNOWMOBILE,SND_NOFLAGS, 1.0, SNDPITCH_NORMAL, client);
			L4D2_RemoveEntityGlow(client);
			float pos[3];
			GetClientEyePosition(client, pos);
			// pos[2] += 10.0;
			for(int i = 0; i < 3; i++) {
				int pipe = L4D_PipeBombPrj(client, pos, NULL_VECTOR, false); 
				pos[0] += GetRandomFloat(-5.0, 5.0);
				pos[1] += GetRandomFloat(-5.0, 5.0);
				L4D_DetonateProjectile(pipe);
			}
			return Plugin_Handled;
		}
		if(tick % 4 == 0) {
			L4D2_RunScript("RushVictim(GetPlayerFromUserID(%d), %d)", userid, 2000);
		}
		if(tick % 2 == 0) {
			// SetEntityRenderColor(client, 255, 0, 0);
			L4D2_SetEntityGlow(client, L4D2Glow_Constant, 0, 0, { 255, 255, 255 }, true);
		} else {
			// SetEntityRenderColor(client, 0, 0, 0);
			L4D2_SetEntityGlow(client, L4D2Glow_Constant, 0, 0, { 255, 0, 0 }, true);
		}
		EmitSoundToAll(SOUND_EXPLODE_BOMB, client, SNDCHAN_USER_BASE, SNDLEVEL_SNOWMOBILE,SND_NOFLAGS, 1.0, SNDPITCH_NORMAL, client);
		
		// schedule next tick
		DataPack nextPack;
		float nextTime = 4.0 / Pow(8.0, 0.1 * float(tick));
		CreateDataTimer(nextTime, Timer_ExplodeBomb, nextPack);
		nextPack.WriteCell(userid);
		nextPack.WriteCell(tick + 1);
		nextPack.WriteCell(maxTicks);
	}
	return Plugin_Continue;
}