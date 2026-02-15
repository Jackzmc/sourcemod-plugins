static char STORE_KEY[] = "SpeedBoost";

void SpeedBoost_OnActivate(int apologizer, int target, const char[] eventId) {
    float speed = GetEntPropFloat(apologizer, Prop_Send, "m_flLaggedMovementValue");
    if(speed <= 1.0) speed = 1.0;
    speed += GetRandomFloat(0.2, 0.5);
    SorryStore[apologizer].SetValue(STORE_KEY, speed);

    PrintToConsoleAll("Sorry_SpeedBoost: new speed %f", speed);
    
    SetEntPropFloat(apologizer, Prop_Send, "m_flLaggedMovementValue", speed);
}