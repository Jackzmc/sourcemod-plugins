// Called when a player takes two kits
forward void OnDoubleKit(int client);
// Called when a bile is thrown when no zombies around
forward void OnNoHordeBileWaste(int client, int commons);

// Called when a door is closed within range of another player. 
// Victim will be the closest victim to the door, may be incorrect.
forward void OnDoorCloseInFace(int client, int victim);
// Called on saferoom doors, with a count. Resets after 20s of no door opening.
forward void OnDoorCloseInFaceSaferoom(int client, int victim, int count);