#include "accept/FreeRevive.sp"
#include "accept/UltimateSacrifice.sp"

#include "neutral/UnoReverse.sp"
#include "neutral/ThirdParty.sp"

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
	// ACCEPT
	ResponseBuilder(Sorry_AcceptFreeRevive, Type_Accept, FreeRevive_OnActivate);

	// NEUTRAL
	ResponseBuilder(Sorry_ThirdParty, Type_Neutral, ThirdParty_OnActivate);
	ResponseBuilder(Sorry_UnoReverse, Type_Neutral, UnoReverse_OnActivate);

	// REJECT
	ResponseBuilder(Sorry_RejectGnome, Type_Reject, Gnome_OnActivate)
		.OnPlayerRunCmd(Gnome_OnPlayerRunCmd)
		.OnClientSayCommand(Gnome_OnClientSayCommand);
    ResponseBuilder(Sorry_RejectBecomeDisgruntled, Type_Reject, BecomeDisgruntled_OnActivate)
		.OnClientSayCommand(BecomeDisgruntled_OnClientSayCommand);
}