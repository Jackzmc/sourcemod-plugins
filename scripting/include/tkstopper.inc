#if defined _tkstopper_included_
  #endinput
#endif
#define _tkstopper_included_

enum TKImmunityType {
	TKImmune_Teamkill = 1,
	TKImmune_ReverseFriendlyFire = 2
}

native void SetImmunity(int target, TKImmunityType type, bool value);

native bool IsImmunity(int target, TKImmunityType type);