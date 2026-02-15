Action Timer_Spin(Handle h, DataPack pack) {
	pack.Reset();
	int client = GetClientOfUserId(pack.ReadCell());
	int count = pack.ReadCell();
	if(client > 0 && count < 36) {
		float ang[3];
		GetClientEyeAngles(client, ang);
		ang[1] += 1;
		SetAbsAngles(client, ang);
		// TeleportEntity(client, NULL_VECTOR, ang, NULL_VECTOR);

		DataPack pack2;
		CreateDataTimer(0.1, Timer_Spin, pack2);		
		pack2.WriteCell(GetClientUserId(client));
		pack2.WriteCell(count + 1);
	}
	return Plugin_Handled;
}
