#if defined _ftt_included_
  #endinput
#endif
#define _ftt_included_
 

enum TrollModifier {
    TrollMod_Invalid = 0,
	TrollMod_Instant = 1 << 0,
	TrollMod_Constant = 1 << 1,
    TrollMod_PlayerOnly = 1 << 2, // Does the troll only work on players, not bots? If set, troll only applied on real user. If not, troll applied to both bot and idler
}

native void ApplyTroll(int victim, const char[] name, TrollModifier modifier = TrollMod_Invalid, int flags, int activator, bool silent = false);

forward void OnTrollApplied(int victim, const char[] trollName, int flags = 0, int activator = 0); 

forward void OnTrollMarked(int activator, int victim); 