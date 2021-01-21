enum Character {
    Character_Nick,
    Character_Ellis,
    Character_Rochelle,
    Character_Coach,
    Character_Bill,
    Character_Francis,
    Character_Zoey,
    Character_Louis
}
native int IdentityFix_SetPlayerModel(int client, int args);


static bool nativeAvailable, nativeTested;
bool UpdatePlayerIdentity(int client, Character character) {
    if(!nativeTested) {
        nativeTested = true;
        nativeAvailable = GetFeatureStatus(FeatureType_Native, "IdentityFix_SetPlayerModel") == FeatureStatus_Available;
    }
    if(nativeAvailable) {
        int result = IdentityFix_SetPlayerModel(client, view_as<int>(character));
        return result == 0;
    }else{
        return false;
    }
}

