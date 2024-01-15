const char WEAPON_GUN_GROUPS = [][] {
	"rifle",
	"sniper",
	"smg",
	"shotgun"
}
enum WEAPON_TYPES {
	Weapon_Rifle,
	Weapon_Sniper,
	Weapon_SMG,
	Weapon_Shotgun
}

const char WEAPONS_RIFLE = []


stock bool IsPrimaryWeapon(const char[] wpnName) {
	return StrContains(wpnName, "rifle") > -1 
		|| StrContains(wpnName, "smg") > -1 
		|| StrContains(wpnName, "weapon_grenade_launcher") > -1 
		|| StrContains(wpnName, "sniper") > -1
		|| StrContains(wpnName, "shotgun") > -1;
}
stock int GetClientWeaponEntIndex(int client, int slot) {
	if(slot >= 0 && slot <= 4) {
		int wpnRef = GetPlayerWeaponSlot(client, slot);
		if(wpnRef != -1) {
			int wpn = EntRefToEntIndex(wpnRef);
			if(wpn != INVALID_ENT_REFERENCE) {
				return wpn;
			}else{
				return -1;
			}
		}else{
			return -1;
		}
	}else{
		return -1;
	}
}
stock int GetClientSecondaryWeapon(int client) {
	return GetClientWeaponEntIndex(client, 1);
}
stock bool GetClientWeaponName(int client, int slot, char[] name, int nameSize) {
	int wpn = GetClientWeaponEntIndex(client, slot);
	if(wpn > -1) {
		GetEntityClassname(wpn, name, nameSize);
		return true;
	}else{
		return false;
	}
}
stock bool DoesClientHaveWeapon(int client, int slot, const char[] name) {
	char wpn[32];
	if(GetClientWeaponName(client, slot, wpn, sizeof(wpn))) {
		return StrEqual(wpn, name, false);
	}else{
		return false;
	}
}

stock bool DoesClientHaveMelee(int client) {
	int wpnEnt = GetClientSecondaryWeapon(client);
	if(wpnEnt > -1) {
		char wpn[16];
		GetEdictClassname(wpnEnt, wpn, sizeof(wpn));
		return StrEqual(wpn, "weapon_melee");
	}else{
		return false;
	}
}