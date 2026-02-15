void RockDropEntity(int entity, float heightOffset = 0.0) {
	float pos[3], dropPos[3];
	if(entity <= MaxClients) {
		GetClientEyePosition(entity, pos);
	} else {
		GetEntPropVector(entity, Prop_Send, "m_vecOrigin", pos);
		pos[2] += 10.0;
	}
	pos[2] += heightOffset;

	dropPos = pos;
	float ang[3];
	ang[0] = 90.0;
	L4D_TankRockPrj(0, dropPos, ang);
}