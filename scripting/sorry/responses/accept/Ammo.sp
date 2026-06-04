void Ammo_OnActivate(int apologizer, int target, const char[] eventId) {
    int wpn = GetClientWeaponEntIndex(apologizer, 0);
    if(wpn == 0) {
        PrintToChat(target, "They have no weapon");
        ShowSorryAcceptMenu(apologizer, target, eventId);
        return;
    }
    SetSecondaryAmmo(apologizer, wpn, 666);

    // Now take some from target
    int targetWpn = GetClientWeaponEntIndex(target, 0);
    int targetAmmoCount = GetSecondaryAmmo(target, targetWpn);
    if(targetAmmoCount > 0 && GetRandomFloat() < 0.2) {
        SetSecondaryAmmo(target, targetWpn, targetAmmoCount / 20); // floors
        PrintToChat(target, "There's a 20% tax...");
    }
}