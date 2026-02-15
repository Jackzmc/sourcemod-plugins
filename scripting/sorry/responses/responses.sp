#include "accept/FreeRevive.sp"
#include "accept/UltimateSacrifice.sp"

#include "reject/RandomProp.sp"
#include "reject/BecomeDisgruntled.sp"
#include "reject/spin.sp"
#include "reject/CarAlarm.sp"
#include "reject/Explode.sp"
#include "reject/BecomeRandomPeanut.sp"
#include "reject/RockDrop.sp"
#include "reject/Burn.sp"
#include "reject/StealItem.sp"
#include "reject/Spook.sp"
#include "reject/Kill.sp"
#include "reject/Gnome.sp"

void RegisterResponses() {
	ResponseBuilder(Sorry_RejectGnome, Type_Reject, Gnome_OnActivate)
		.OnPlayerRunCmd(Gnome_OnPlayerRunCmd)
		.OnClientSayCommand(Gnome_OnClientSayCommand);
    ResponseBuilder(Sorry_RejectBecomeDisgruntled, Type_Reject, BecomeDisgruntled_OnActivate)
		.OnClientSayCommand(BecomeDisgruntled_OnClientSayCommand);
}