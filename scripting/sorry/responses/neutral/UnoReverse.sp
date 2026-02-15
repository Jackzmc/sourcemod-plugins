void UnoReverse_OnActivate(int activator, int target, const char[] eventId) {
    PrintToChatAll("%N played uno reverse sorry on %N", target, activator);
    ShowSorryAcceptMenu(target, activator, eventId);
}