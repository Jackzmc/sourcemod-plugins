void ThirdParty_OnActivate(int apologizer, int target, const char[] eventId) {
    int player = GetRandomRealPlayer(target, apologizer);
    if(player == -1) {
        PrintToChat(target, "Sorry no players found to pass off to");
        ShowSorryAcceptMenu(apologizer, target, eventId);
    } else {
        PrintToChat(player, "%N chooses you to accept or reject %N's apology on their behalf.", target, apologizer);
        ShowSorryAcceptMenu(apologizer, player, eventId, target);
    }
}
