void Sideways_OnActivate(int apologizer, int target, const char[] eventId) {
    float ang[3];
    ang[2] = GetRandomFloat(0.0, 360.0);
    TeleportEntity(apologizer, NULL_VECTOR, ang, NULL_VECTOR);

    float time = GetRandomFloat(5.0, 13.0);
    CreateTimer(time, Timer_RevertSideways, GetClientUserId(apologizer));
}

Action Timer_RevertSideways(Handle h, int userid) {
    int client = GetClientOfUserId(userid);
    if(client > 0) {
        float ang[3];
        GetClientEyeAngles(client, ang);
        ang[2] = 0.0;
        TeleportEntity(client, NULL_VECTOR, ang, NULL_VECTOR);
    }
    return Plugin_Handled;
}