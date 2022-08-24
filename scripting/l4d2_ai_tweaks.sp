#pragma semicolon 1
#pragma newdecls required

//#define DEBUG

#define PLUGIN_VERSION "1.0"

#include <sourcemod>
#include <sdktools>
#include <actions>
//#include <sdkhooks>

public Plugin myinfo = 
{
	name =  "L4D2 AI Tweaks", 
	author = "jackzmc", 
	description = "", 
	version = PLUGIN_VERSION, 
	url = "https://github.com/Jackzmc/sourcemod-plugins"
};

public void OnPluginStart() {
	EngineVersion g_Game = GetEngineVersion();
	if(g_Game != Engine_Left4Dead2) {
		SetFailState("This plugin is for L4D2 only.");	
	}
}


public void OnActionCreated( BehaviorAction action, int actor, const char[] name ) {
	/* Hooking friend healing action (when bot wants to heal someone) */
	if ( strcmp(name, "SurvivorHealFriend") == 0 )    
		action.OnStartPost = OnFriendAction;
} 

public Action OnFriendAction( BehaviorAction action, int actor, BehaviorAction priorAction, ActionResult result ) {
	// Do not allow idle bots to heal another player, unless they are black and white.
	// Do not let idle bots heal non-idle bots
	int target = action.Get(0x34) & 0xFFF; 
   	if(GetEntProp(actor, Prop_Send, "m_humanSpectatorUserID") > 0) { // If idle bot
		if(IsFakeClient(target)) {
			// If target is a bot, not idle player, ignore
			if(GetEntProp(target, Prop_Send, "m_humanSpectatorUserID") == 0) {
				result.type = DONE;
				return Plugin_Handled;
			}
		} 
		// If they are not black and white, also stop
		if(!GetEntProp(target, Prop_Send, "m_bIsOnThirdStrike")) { //If real player and not black and white, stop
			result.type = DONE;
			return Plugin_Handled;
		}
	}
	return Plugin_Continue;
} 