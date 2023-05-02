#if defined _player_notes_included_
	#endinput
#endif
#define _player_notes_included_

void AddNote(int noteCreator, int noteTarget, const char[] message) { 
    char steamidCreator[32], steamidTarget[32];
    GetClientAuthId(noteCreator, AuthId_Steam2, steamidCreator, sizeof(steamidCreator));
    GetClientAuthId(noteTarget, AuthId_Steam2, steamidTarget, sizeof(steamidTarget));
    AddNoteIdentity(steamidCreator, steamidTarget, message);
}

native void AddNoteIdentity(const char noteCreator[32], const char noteTarget[32], const char[] message);