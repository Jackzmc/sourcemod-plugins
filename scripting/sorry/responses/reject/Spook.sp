void SpookPlayer(int player, int spookType) {
	float pos[3];
	char model[64];
	GetHorizontalPositionFromClient(player, 60.0, pos);
	if(spookType == 1) {
		strcopy(model, sizeof(model), "models/infected/witch.mdl");
	} else {
		strcopy(model, sizeof(model), MODEL_PEANUT);
	}
	PrecacheModel(model);
	float ang[3];
	GetClientEyeAngles(player, ang);
	if(ang[0] < -10.0 || ang[0] > 10.0) {
		ang[0] = 0.0;
		TeleportEntity(player, NULL_VECTOR, ang, NULL_VECTOR);
		// SetAbsAngles(player, ang);
	}
	ang[0] = 0.0;
	ang[1] -= 180.0;
	int prop = CreateProp("prop_dynamic_override", model, pos, ang, NULL_VECTOR);
	L4D2_SetEntityGlow(prop, L4D2Glow_Constant, 100, 0, { 255, 0, 0 }, false);
	SetEntityRenderColor(prop, 255, 0, 0, 255);
	
	if(spookType == 1) {
		PrecacheSound("npc/witch/voice/attack/female_distantscream1.wav");
		EmitSoundToClient(player, "npc/witch/voice/attack/female_distantscream1.wav", .volume = 1.0);
	} else {
		PrecacheSound("level/lowscore.wav");
		EmitSoundToClient(player, "level/lowscore.wav", .volume = 1.0);
		EmitSoundToClient(player, "level/lowscore.wav", .volume = 1.0);
		EmitSoundToClient(player, "level/lowscore.wav", .volume = 1.0);
		EmitSoundToClient(player, "level/lowscore.wav", .volume = 1.0);
		EmitSoundToClient(player, "level/lowscore.wav", .volume = 1.0);
	}

	CreateTimer(1.5, Timer_KillEntity, EntIndexToEntRef(prop));
}