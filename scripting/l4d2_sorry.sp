#pragma semicolon 1
#pragma newdecls required

#define DEBUG_SORRY 0

#define SORRY_MENU_ITEMS 14

#include <sourcemod>
#include <sdktools>
#include <left4dhooks>
#include <clientprefs>
#include <multicolors>
#include <gamemodes/ents>
#include <anymap>
#include <jutils>
#include <smlib>

#include "sorry/def.sp"
#include "sorry/util/util.sp"
#include "sorry/util/temp.sp"
#include "sorry/events.sp"
#include "sorry/cmds.sp"

#include "sorry/shared/runaway.sp"
#include "sorry/shared/return.sp"

#include "sorry/events/clown.sp"
#include "sorry/events/car_alarm.sp"

#include "sorry/responses/responses.sp"


public Plugin myinfo = {
	name =  "L4D2 Sorry",
	author = "jackzmc",
	description = "",
	version = "1.0",
	url = "https://github.com/Jackzmc/sourcemod-plugins"
};

#define DMG_HEADSHOT (1 << 30)

public void OnPluginStart() {
	EngineVersion g_Game = GetEngineVersion();
	if(g_Game != Engine_Left4Dead && g_Game != Engine_Left4Dead2) {
		SetFailState("This plugin is for L4D/L4D2 only.");
	}

	allowSelfResponse = CreateConVar("sorry_allow_self_response", "0", "Should player be able to accept/reject their own apology? If false, it acts like Accept & Assure always.", FCVAR_NONE, true, 0.0, true, 1.0);

	g_FadeUserMsgId = GetUserMessageId("Fade");
	clownLastHonked = new AnyMap();

	SorryStore_Setup();
	_registerResponses();

	g_runAwayParents = new AnyMap();

	LoadTranslations("common.phrases");
	LoadSorryResponses();

	HookEvent("triggered_car_alarm", Event_CarAlarm);

	HookEvent("charger_carry_start", Event_ChargerCarry);
	HookEvent("charger_carry_end", Event_ChargerCarry);

	HookEvent("lunge_pounce", Event_HunterPounce);
	HookEvent("pounce_end", Event_HunterPounce);
	HookEvent("pounce_stopped", Event_HunterPounce);

	HookEvent("choke_start", Event_SmokerChoke);
	HookEvent("choke_end", Event_SmokerChoke);
	HookEvent("choke_stopped", Event_SmokerChoke);

	HookEvent("jockey_ride", Event_JockeyRide);
	HookEvent("jockey_ride_end", Event_JockeyRide);

	HookEvent("player_incapacitated_start", Event_PlayerIncap);
	HookEvent("infected_death", Event_InfectedDeath);
	HookEvent("player_death", Event_PlayerDeath);

	RegConsoleCmd("sm_sorry", Command_Apologize);
	RegAdminCmd("sm_sorrymenu", Command_ApologizeMenu, ADMFLAG_GENERIC);
	#if defined DEBUG_SORRY
	RegAdminCmd("sm_sorryh", Command_Debug_SorryHandler, ADMFLAG_ROOT);
    RegAdminCmd("sm_sorrys", Command_Debug_Store, ADMFLAG_GENERIC);
    RegAdminCmd("sm_sorryl", Command_Debug_List, ADMFLAG_GENERIC);
	#endif

	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientInGame(i)) {
			OnClientPutInServer(i);
		}
	}
}

// This loads id -> name, chance
void LoadSorryResponses() {
	if(g_sorryResponses != null) {
		delete g_sorryResponses;
	}
	g_sorryResponses = new ArrayList(sizeof(SorryResponse));
	SorryResponse res;

	KeyValues kv = new KeyValues("Responses");

	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "data/sorry_responses.cfg");
	if(!FileExists(sPath)) {
		delete kv;
		PrintToServer("[Custom] Missing file at %s", sPath);
		return;
	} else if(!kv.ImportFromFile(sPath)) {
		delete kv;
		PrintToServer("[Custom] Could not load sorry responses from data/sorry_responses.cfg");
		return;
	}

	kv.GotoFirstSubKey();
	char buffer[32];
	do {
		kv.GetSectionName(buffer, sizeof(buffer));
		res.id = StringToInt(buffer);
		if(res.id < sorryBounds[0]) {
			sorryBounds[0] = res.id;
		} else if(res.id > sorryBounds[1]) {
			sorryBounds[1] = res.id;
		}

		kv.GetString("label", res.label, sizeof(res.label), "");
		if(res.label[0] == '\0') {
			PrintToServer("[Custom] Missing label for response %d", res.id);
			continue;
		}
		kv.GetString("event", res.eventId, EVENT_ID_LENGTH, "");
		res.chance = kv.GetFloat("chance", 1.0);

		g_sorryResponses.PushArray(res);
	} while(kv.GotoNextKey(true));
	delete kv;
	PrintToServer("[Custom] Loaded %d responses. Bounds[%d,%d]", g_sorryResponses.Length, sorryBounds[0], sorryBounds[1]);
}

void PushSorry(int client, SorryData sorry) {
	if(!sorry.hurtTime) sorry.hurtTime = GetGameTime();
	for(int i = SORRY_NSLOT; i > 0; i--) {
		TransferSorry(client, sorryData[client][i], i-1);
	}
	TransferSorry(client, sorry, SORRY_NSLOT);
}
void TransferSorry(int client, SorryData sorry, int toIndex) {
	sorryData[client][toIndex].victimUserid = sorry.victimUserid;
	sorryData[client][toIndex].eventId = sorry.eventId;
	sorryData[client][toIndex].hurtTime = sorry.hurtTime;
	sorryData[client][toIndex].dmgType = sorry.dmgType;
	strcopy(sorryData[client][toIndex].hurtType, 32, sorry.hurtType);
}
void TransferSorryOut(int client, int fromIndex, SorryData sorry) {
	sorry.victimUserid = sorryData[client][fromIndex].victimUserid;
	sorry.eventId = sorryData[client][fromIndex].eventId;
	sorry.hurtTime = sorryData[client][fromIndex].hurtTime;
	sorry.dmgType = sorryData[client][fromIndex].dmgType;
	strcopy(sorry.hurtType, sizeof(sorry.hurtType), sorryData[client][fromIndex].hurtType);
}

int GetSorrysCount(int client) {
	int count = 0;
	for(int i = SORRY_NSLOT; i >= 0; i--) {
		if(sorryData[client][i].IsValid()) {
			count++;
		}
	}
	return count;
}

bool PopSorry(int client, SorryData sorry) {
	for(int i = SORRY_NSLOT; i >= 0; i--) {
		if(sorryData[client][i].IsValid()) {
			TransferSorryOut(client, i, sorry);
			// sorry = sorryData[client][i];
			sorryData[client][i].Reset();
			return true;
		}
	}
	return false;
}

#define SORRY_MERGE_TIME 8.0

bool UpdateExistingSorryIndex(int attacker, int victimUserId, int dmgType) {
	float time = GetGameTime();
	for(int i = SORRY_NSLOT; i >= 0; i--) {
		if(sorryData[attacker][i].victimUserid == victimUserId
			&& time - sorryData[attacker][i].hurtTime <= SORRY_MERGE_TIME
			&& sorryData[attacker][i].dmgType == dmgType
		) {
			sorryData[attacker][i].hurtTime = time;
			return true;
		}
	}
	return false;
}

void OnTakeDamagePost(int victim, int attacker, int inflictor, float damage, int dmgType, int weapon, const float damageForce[3], const float damagePosition[3], int damagecustom) {
	//&& !IsFakeClient(victim)
	if(attacker > 0 && victim > 0 && attacker <= MaxClients && victim <= MaxClients && attacker != victim && !IsFakeClient(victim) && !IsFakeClient(attacker) && GetClientTeam(attacker) == 2 && GetClientTeam(victim) == 2) {
		// Ignore when charged, doesn't count
		if(isUnderAttack[victim]) return;
		int victimUserid = GetClientUserId(victim);

		// Ignore multiple FF events on same victim within time frame, of same damage type
		if(UpdateExistingSorryIndex(attacker, victimUserid, dmgType)) {
			return;
		}
		SorryData sorry;

		if(dmgType & DMG_BURN || dmgType & DMG_DIRECT) {
			sorry.hurtType = "I burned you";
		} else if(IsValidEntity(weapon)) {
			static char weaponName[32];
			GetEntityClassname(weapon, weaponName, sizeof(weaponName));
			// GetClientWeapon(attacker, weapon, sizeof(weapon));
			if(dmgType & DMG_BLAST || StrEqual(weaponName, "weapon_grenade_launcher")) {
				sorry.hurtType = "I blasted you";
			} else if(dmgType & DMG_CLUB || StrEqual(weaponName, "weapon_melee")) {
				if(GetURandomFloat() < 0.3)
					sorry.hurtType = "I sliced you";
				else if(GetURandomFloat() < 0.3)
					sorry.hurtType = "I batted you";
				else if(GetURandomFloat() < 0.3)
					sorry.hurtType = "I stabbed you";
				else
					sorry.hurtType = "I smacked you";
			} else if(dmgType & DMG_BULLET || dmgType & DMG_PREVENT_PHYSICS_FORCE ) {
				if(dmgType & DMG_HEADSHOT) {
					if(GetURandomFloat() < 0.5)
						sorry.hurtType = "I shot you in the head";
					else
						sorry.hurtType = "I headshotted you";
				} else if(dmgType & DMG_BUCKSHOT && GetURandomFloat() > 0.5) {
					sorry.hurtType = "I shotgunned you";
				} else if(GetURandomFloat() < 0.1) {
					sorry.hurtType = "I put a bullet in you";
				} else if(GetURandomFloat() < 0.01) {
					sorry.hurtType = "I shot you in the eyeball";
				} else if(GetURandomFloat() < 0.1) {
					sorry.hurtType = "I shot you in the stomach";
				} else if(GetURandomFloat() < 0.1) {
					sorry.hurtType = "I shot you in the spleen";
				} else {
					sorry.hurtType = "I shot you";
				}
			}
		}
		// Fallback if dmg was none of the above
		if(sorry.hurtType[0] == '\0') {
			if(GetURandomFloat() < 0.3)
				sorry.hurtType = "I somehow managed to hurt you";
			else if(GetURandomFloat() < 0.3)
				sorry.hurtType = "that I managed to hurt you";
			else
				sorry.hurtType = "I hurt you with magic";
		}

		sorry.victimUserid = victimUserid;
		sorry.dmgType = dmgType;
		PushSorry(attacker, sorry);
	}
}

void SendApology(int client, int target, const char[] hurtType, const char[] eventId = "") {
	CPrintToChatAll("(Survivor) {blue}%N{default} : sorry %s %N", client, hurtType, target);
	LogAction(client, target, "\"%L\" apologizes to \"%L\" with \"%s\"", client, target, hurtType);
	if(IsFakeClient(target)) {
		if(GetClientTeam(client) == GetClientTeam(target) && GetURandomFloat() > 0.5) {
			PrintHintText(client, "%N accepted your apology.", target);
			EmitSoundToAll("ui/survival_playerrec.wav", client);
			// ClientCommand(client, "play ui/survival_playerrec.wav");
		} else if(GetURandomFloat() < 0.01) {
			float vel[3] = { 1000.0, 1000.0, 1000.0 };
			PrintToChatAll("%N accepts %N's apology and commits death.", target, client);
			SDKHooks_TakeDamage(target, target, target, 20000.0, DMG_BLAST, -1, vel);
			CreateTimer(0.1, Timer_KillPlayer, target);
		} else if(GetURandomFloat() < 0.5) {
			float vel[3] = { 1000.0, 1000.0, 1000.0 };
			PrintToChatAll("%N rejects %N's apology.", target, client);
			SDKHooks_TakeDamage(client, client, client, 20000.0, DMG_BLAST, -1, vel);
			CreateTimer(0.1, Timer_KillPlayer, client);
		} else if(GetURandomFloat() < 0.5) {
			// random Accept
			sorryResponseValues response = view_as<sorryResponseValues>(GetRandomInt(0, sorryBounds[1]));
			HandleApologyResponse(client, target, eventId, response);
		} else {
			// random Reject
			sorryResponseValues response = view_as<sorryResponseValues>(GetRandomInt(sorryBounds[0], 0));
			HandleApologyResponse(client, target, eventId, response);
		}
	} else if(!allowSelfResponse.BoolValue && target == client) {
		// Accept & Assure
		PrintHintText(target, "It's okay to accept yourself.");
		EmitSoundToAll("ui/survival_playerrec.wav", target);	
	} else {
		ShowSorryAcceptMenu(client, target, eventId);
	}
}

/// client apologizes to target
void ShowSorryAcceptMenu(int client, int target, const char[] eventId = "", int onBehalf = -1) {
	Menu menu = new Menu(ApologizeHandler);
	if(onBehalf > 0) {
		menu.SetTitle("%N apologizes to %N", client, onBehalf);
	} else {
		menu.SetTitle("%N apologizes", client);
	}
	char id[24];
	// Menu can only show 7 per page, so only show 2 pages
	if(g_sorryResponses == null) {
		PrintToChat(target, "Could not load apology list.");
		LogError("g_sorryResponses is null");
		return;
	} else if(g_sorryResponses.Length == 0) {
		LogError("CreateRandomSequence returned length 0 params(0, %d, 20)", g_sorryResponses.Length);
		PrintToChat(client, "Could not create apology list for player.");
		return;
	}
	ArrayList list = GetRandomSorryList(SORRY_MENU_ITEMS);
	SorryResponse res;
	for(int i = 0; i < list.Length; i++) {
		list.GetArray(i, res);

		// If event matches or if the configured sorry response event is none
		if(res.eventId[0] == '\0' || StrEqual(res.eventId, eventId)) {
			if(onBehalf > 0)
				Format(id, sizeof(id), "%d|%d|%d|%d", GetClientUserId(client), eventId, res.id, GetClientUserId(onBehalf));
			else
				Format(id, sizeof(id), "%d|%d|%d|-1", GetClientUserId(client), eventId, res.id);
			menu.AddItem(id, res.label);
		}
	}
	// delete seq;
	menu.Display(target, 50);
	delete list;
}

/**
 * Generate an array of upto n size randomly sorted SorryResponse
 * Each item has a chance to be added
 */
ArrayList GetRandomSorryList(int size) {
	ArrayList list = new ArrayList(sizeof(SorryResponse));
	SorryResponse res;
	// Loop ALL entries but 100% responses, and try their % chance
	for(int i = 0; i < g_sorryResponses.Length; i++) {
		g_sorryResponses.GetArray(i, res);
		// Do not include 100%, we add it later
		if(res.chance < 1.0 && GetURandomFloat() <= res.chance) {
			list.PushArray(res, sizeof(res));
		}
	}
	// Add all 100% chance responses
	for(int i = 0; i < g_sorryResponses.Length; i++) {
		g_sorryResponses.GetArray(i, res);
		if(res.chance == 1.0) {
			list.PushArray(res, sizeof(res));
		}
	}

	// Sort in random order, for when we truncate
	list.Sort(Sort_Random, Sort_Integer); // Sort_Integer doesnt do anything for Sort_Random

	// Truncuate the list if more than requested
	if(size < list.Length) 
		list.Resize(size);

	// Sort one more time to sort the 100% responses
	list.Sort(Sort_Random, Sort_Integer); // Sort_Integer doesnt do anything for Sort_Random
	return list;
}

int ApologizePlayerHandler(Menu menu, MenuAction action, int client, int param2) {
	if (action == MenuAction_Select) {
		static char info[8];
		menu.GetItem(param2, info, sizeof(info));
		int target = GetClientOfUserId(StringToInt(info));
		SendApology(client, target, "I shot you");
	} else if (action == MenuAction_End)
		delete menu;
	return 0;
}



void HandleApologyResponse(int activator, int target, const char[] eventId, sorryResponseValues response) {
	if(response == Sorry_UnoReverse) {
		PrintToChatAll("%N played uno reverse sorry on %N", target, activator);
		ShowSorryAcceptMenu(target, activator, eventId);
	} else if(response == Sorry_ThirdParty) {
		int player = GetRandomRealPlayer(target, activator);
		if(player == -1) {
			PrintToChat(target, "Sorry no players found to pass off to");
			ShowSorryAcceptMenu(activator, target, eventId);
		} else {
			PrintToChat(player, "%N chooses you to accept or reject %N's apology on their behalf.", target, activator);
			ShowSorryAcceptMenu(activator, player, eventId, target);
		}
	} else if(view_as<int>(response) > 0) {
		EmitSoundToAll("ui/survival_playerrec.wav", target);
		EmitSoundToAll("ui/survival_playerrec.wav", activator);

		if((!_debugSorry && target == activator) || response == Sorry_AcceptAssure) {
			PrintHintText(activator, "It's okay to accept yourself.");
			if(target == activator) return;
		} else {
			PrintHintText(activator, "%N accepted your apology.", target);
			PrintHintText(target, "Accepted %N's apology.", activator);
		}

		if(response == Sorry_AcceptSlap) {
			SlapPlayer(activator, 0, true);
		} else if(response == Sorry_AcceptHealth) {
			PrintHintText(activator, "%N's gave you their health (+30). How sweet.", target);
			SDKHooks_TakeDamage(target, target, target, 30.0, DMG_GENERIC, -1);
			SetEntityHealth(activator, GetClientHealth(activator) + 32);
		} else if(response == Sorry_FakeAccept) {
			float time = GetRandomFloat(3.0, 12.0);
			DataPack pack;
			CreateDataTimer(time, Timer_RandomApology, pack);
			pack.WriteCell(GetClientUserId(activator));
			pack.WriteCell(GetClientUserId(target));
			pack.WriteCell(-1);
			return;
		} else if(response == Sorry_AcceptImmune) {
			SDKHook(activator, SDKHook_OnTakeDamage, Hook_Godmode);
			float time = GetRandomFloat(30.0, 80.0);
			CreateTimer(time, Timer_RevertGod);
			PrintToChat(activator, "%N has granted you godmode for %.0f seconds", target, time);
		} else if(response == Sorry_AcceptBecomePeanut) {
			float time = IsAllAdmins() ? GetRandomFloat(120.0, 240.0) : GetRandomFloat(20.0, 30.0);
			PrecacheModel(MODEL_PEANUT);
			TempSetModel(activator, time, MODEL_PEANUT);
		} else if(response == Sorry_AcceptUltimateSacrifice) {
			PrintToChat(target, "For your information... you're the sacrifice.");
			DataPack pack;
			CreateDataTimer(4.0, Timer_UltimateSacrifice, pack);
			pack.WriteCell(GetClientUserId(activator));
			pack.WriteCell(GetClientUserId(target));
		} else if(response == Sorry_Accept || response == Sorry_AcceptAssure) {
			return; // handled
		} else if(!HandleResponse(response, Type_Accept, activator, target, eventId)) {
			PrintToChat(target, "That response is not supported (#%d), tell jackz bad", view_as<int>(response));
		}
		LogAction(target, activator, "\"%L\" accepted \"%L\"'s apology (response = %d)", target, activator, response);
	} else {
		if(!_debugSorry && target == activator) {
			PrintHintText(activator, "It's okay to accept yourself.");
			EmitSoundToAll("ui/survival_playerrec.wav", activator);
			LogAction(target, activator, "\"%L\" accepted \"%L\"'s apology (response = %d)", target, activator, response);
		} else {
			// if(StrEqual(eventId, "car_alarm")) {
			// 	if(!IsPlayerAlive(activator)) {
			// 		float pos[3];
			// 		GetClientAbsOrigin(activator, pos);
			// 		L4D_RespawnPlayer(activator);
			// 		TeleportEntity(activator, pos, NULL_VECTOR, NULL_VECTOR);
			// 	}
			// }

			EmitSoundToAll("player/orch_hit_csharp_short.wav", target);
			EmitSoundToAll("player/orch_hit_csharp_short.wav", activator);
			PrintHintText(target, "Rejected %N's apology.", activator);
			PrintToChatAll("%N refused %N's apology. ", target, activator);

			if(response == Sorry_Reject) {
				// nothing, handled from above
			} else if(response == Sorry_RejectIncap) {
				float vel[3] = { 1000.0, 1000.0, 1000.0 };
				SDKHooks_TakeDamage(activator, activator, activator, 1000.0, DMG_BLAST, -1, vel);
			} else if(response == Sorry_RejectKill) {
				KillPlayerAndRevert(activator, 5.0);
			} else if(response == Sorry_RejectSlap) {
				SlapPlayer(activator, 0, true);
			} else if(response == Sorry_RejectCrush) {
				SpawnPropAbovePlayer(activator, MODEL_CAR);
			} else if(response == Sorry_RejectStealHealth) {
				float vel[3] = { 1000.0, 1000.0, 1000.0 };
				PrintHintText(activator, "%N's stole your health (-30).", target);
				SDKHooks_TakeDamage(activator, activator, activator, 30.0, DMG_GENERIC, -1, vel);
				SetEntityHealth(target, GetClientHealth(target) + 32);
			} else if(response == Sorry_RejectRockDrop) {
				RockDropEntity(activator);
			} else if(response == Sorry_RejectSwapPosition) {
				float posA[3], posB[3];
				GetClientAbsOrigin(activator, posA);
				GetClientAbsOrigin(target, posB);
				TeleportEntity(activator, posB, NULL_VECTOR, NULL_VECTOR);
				TeleportEntity(target, posA, NULL_VECTOR, NULL_VECTOR);
			} else if(response == Sorry_RejectStealItem) {
				Menu stealMenu = new Menu(StealItemMenuHandler);
				char display[32];
				char info[16];
				Format(info, sizeof(info), "%d|-1|-1", GetClientUserId(activator));
				stealMenu.AddItem(info, "Random");
				for(int slot = 0; slot <= 5; slot++) {
					int item = GetClientWeaponNameSmart2(activator, slot, display, sizeof(display));
					if(item > -1) {
						Format(info, sizeof(info), "%d|%d|%d", GetClientUserId(activator), item, slot);
						stealMenu.AddItem(info, display);
					}
				}
				stealMenu.Display(target, 0);
			} else if(response == Sorry_RejectVomit) {
				L4D2_CTerrorPlayer_OnHitByVomitJar(activator, activator);
			} else if(response == Sorry_RejectIdle) {
				L4D_GoAwayFromKeyboard(activator);
			} else if(response == Sorry_RejectCharge) {
				L4D2_Charger_ThrowImpactedSurvivor(activator, activator);
			} else if(response == Sorry_RejectRewind) {
				float pos[3];
				float curFlow = L4D2Direct_GetFlowDistance(activator);
				GetRandomNearbyPos(curFlow, pos, -300.0, 150.0, 75.0);
				TeleportEntity(activator, pos, NULL_VECTOR, NULL_VECTOR);
			} else if(response == Sorry_RejectConfuse) {
				float ang[3];
				ang[0] = (GetURandomFloat() * 360.0) - 180.0;
				ang[1] = (GetURandomFloat() * 360.0) - 180.0;
				// ang[2] = (GetURandomFloat() * 360.0) - 180.0;
				TeleportEntity(activator, NULL_VECTOR, ang, NULL_VECTOR);
			} else if(response == Sorry_RejectStealAmmo) {
				int targetWpn = GetPlayerWeaponSlot(activator, 0);
				int ourWpn = GetPlayerWeaponSlot(target, 0);
				if(targetWpn == -1) {
					PrintToChat(target, "Player has no gun :(");
					ShowSorryAcceptMenu(activator, target, eventId);
				} else if(ourWpn == -1) {
					PrintToChat(target, "You don't have a gun....");
					ShowSorryAcceptMenu(activator, target, eventId);
				} else {
					int targetAmmo = GetSecondaryAmmo(activator, targetWpn);
					int ourAmmo = GetSecondaryAmmo(target, ourWpn);
					int ammoToSteal = GetRandomInt(20, targetAmmo);
					SetSecondaryAmmo(activator, targetWpn, targetAmmo - ammoToSteal);
					SetSecondaryAmmo(target, ourWpn, ourAmmo + ammoToSteal);
					if(GetEntProp(ourWpn, Prop_Send, "m_iClip1") < 20) {
						SetEntProp(ourWpn, Prop_Send, "m_iClip1", 20);
					}
					PrintToChat(target, "Stole %d/%d of their ammos. That's rude", ammoToSteal, targetAmmo);
				}
			} else if(response == Sorry_RejectBoxDrop) {
				// bias 1 box heavier
				int count = GetRandomInt(14, 32);

				for(int i = 0; i < count; i++) {
					int crate = SpawnPropAbovePlayer(activator, GetRandomFloat() > 0.70 ? MODEL_CRATE2 : MODEL_CRATE, 0.0);
					if(GetURandomFloat() < 0.1) //10% chance not to break
						AcceptEntityInput(crate, "Break");
				}
			} else if(response == Sorry_RejectBurn) {
				int count = GetURandomFloat() > 0.001 ? GetRandomInt(0, 15) : GetRandomInt(15, 100);
				while(count >= 0) {
					CreateTimer(1.0 + float(count), Timer_BurnPlayer, activator);
					count--;
				}
			} else if(response == Sorry_RejectSpecial) {
				char buf[16];
				Format(buf, sizeof(buf), "#%d", GetClientUserId(activator));
				CheatCommand(target, "sm_inface", buf, "random");
				SlapPlayer(target);
				PrintToChat(target, "You get slapped because it's rude to spawn a special on them.");
			} else if(response == Sorry_RejectMakeClown) {
				TempSetModel(activator, 45.0,  "models/infected/common_male_clown.mdl");
			} else if(response == Sorry_RejectTimeout) {
				if(!foundSaferoomPos) {
					PrintToChat(target, "Could not find saferoom.");
					ShowSorryAcceptMenu(activator, target, eventId);
				} else {
					float returnTime = GetRandomFloat(2.0, 18.0);
					ReturnPlayerTimeout(returnTime, activator);

					PrintToChat(activator, "You've been put in timeout. Walk back in shame.");
					TeleportEntity(activator, saferoomPos, NULL_VECTOR, NULL_VECTOR);
				}
			} else if(response == Sorry_RejectGivePitchfork) {
				int wpn = GetPlayerWeaponSlot(activator, 1);

				if(wpn > 0) {
					SpawnWeaponThief(activator, wpn);
				}
				CheatCommand(activator, "give", "pitchfork", "");
			} else if(response == Sorry_RejectDropAll) {
				float pos[3];
				GetHorizontalPositionFromClient(activator, 60.0, pos);
				for(int i = 0; i < 5; i++) {
					int ent = GetPlayerWeaponSlot(activator, i);
					if(ent > 0) {
						SDKHooks_DropWeapon(activator, ent, pos, NULL_VECTOR);
					}
				}
			} else if(response == Sorry_RejectHorde) {
				int victimId = GetClientUserId(activator);
				float pos[3];
				GetClientAbsOrigin(activator, pos);

				bool spawnClowns = currentMap[0] == 'c' && currentMap[1] == '2';
				if(spawnClowns) {
					PrecacheModel("models/infected/common_male_clown.mdl");
					SpawnZombiesNearby(pos, 40, victimId, "models/infected/common_male_clown.mdl");
				} else {
					SpawnZombiesNearby(pos, 40, victimId);
				}
			} else if(response == Sorry_RejectCarAlarm) {
				PrecacheSound(SOUND_CAR_ALARM);
				EmitSoundToAll(SOUND_CAR_ALARM, activator, SNDCHAN_USER_BASE, SNDLEVEL_SNOWMOBILE, SND_NOFLAGS, 1.0, 100, activator);
				SetEntityRenderMode(activator, RENDER_TRANSALPHA);
				SetEntityRenderColor(activator, 255, 255, 0);
				L4D2_SetEntityGlow(activator, L4D2Glow_Constant, 0, 0, { 255, 255, 0 }, true);
				Handle timer = CreateTimer(1.0, Timer_CarAlarmFlash, GetClientUserId(activator), TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
				DataPack pack;
				CreateDataTimer(15.0, Timer_StopAlarm, pack);
				pack.WriteCell(GetClientUserId(activator));
				pack.WriteCell(timer);
			} else if(response == Sorry_FakeReject) {
				float time = GetRandomFloat(3.0, 12.0);
				DataPack pack;
				CreateDataTimer(time, Timer_RandomApology, pack);
				pack.WriteCell(GetClientUserId(activator));
				pack.WriteCell(GetClientUserId(target));
				pack.WriteCell(1);
				return;
			} else if(response == Sorry_RejectCloset) {
				Address nav = FindNearestNav(activator, NAV_SPAWN_RESCUE_CLOSET);
				if(nav == Address_Null) nav = FindNearestNav(activator, NAV_SPAWN_CHECKPOINT);
				if(nav != Address_Null) {
					float orgPos[3];
					GetClientAbsOrigin(activator, orgPos);
					float pos[3];
					L4D_FindRandomSpot(view_as<int>(nav), pos);

					float distance = L4D2_NavAreaTravelDistance(pos, orgPos, false);
					PrintToConsoleAll("sorry closet distance = %f (%.0f,%.0f,%.0f)->(%.0f,%.0f,%.0f)", distance, pos[0], pos[1],pos[2],orgPos[0],orgPos[1],orgPos[2]);
					// If closet is far, or they cannot return
					if(distance > 3000.0) {
						ReturnPlayerTimeout(20.0, activator);
						PrintToChat(activator, "You've been put in timeout. Walk back in shame.");
					}
					TeleportEntity(activator, pos, NULL_VECTOR, NULL_VECTOR);
				} else {
					PrintToChat(target, "Sorry, could not find closet");
					ShowSorryAcceptMenu(activator, target, eventId);
				}
			} else if(response == Sorry_RejectSpin) {
				DataPack pack;
				CreateDataTimer(0.1, Timer_Spin, pack);
				pack.WriteCell(GetClientUserId(activator));
				pack.WriteCell(0);
			} else if(response == Sorry_RejectBanishToVoid) {
				ReturnPlayerTimeout(12.0, activator);

				float pos[3];
				TeleportEntity(activator, pos, NULL_VECTOR, NULL_VECTOR);
				SDKHook(activator, SDKHook_OnTakeDamage, Hook_Godmode);
				CreateTimer(12.0, Timer_RevertGod);
			} else if(response == Sorry_RejectInconvenientHealth) {
				char activeWpnId[32];
				if(!GetClientWeaponName(activator, 3, activeWpnId, sizeof(activeWpnId)) && !StrEqual(activeWpnId, "weapon_first_aid_kit")) {
					// check kit slot for kit, if not - give a kit
					CheatCommand(activator, "give", "first_aid_kit", "");
					ClientCommand(activator, "slot3");
				} else if(!GetClientWeaponName(activator, 4, activeWpnId, sizeof(activeWpnId))) {
					// check adr/pills slot for items / pills, if not - give
					CheatCommand(activator, "give", GetRandomFloat() > 0.5 ? "adrenaline" : "pain_pills", "");
					ClientCommand(activator, "slot4");
				} else {
					// Otherwise, they have both a kit and adr/pills, switch slot:
					GetClientWeapon(activator, activeWpnId, sizeof(activeWpnId));
					ClientCommand(activator, StrEqual(activeWpnId, "weapon_first_aid_kit") ? "slot3" : "slot4");
				}
			} else if(response == Sorry_RejectExplode) {
				PrintHintText(activator, "Beep");
				PrecacheSound(SOUND_EXPLODE_BOMB);
				EmitSoundToAll(SOUND_EXPLODE_BOMB, activator, SNDCHAN_USER_BASE, SNDLEVEL_SNOWMOBILE, SND_NOFLAGS, 1.0, 30, activator);
				L4D2_SetEntityGlow(activator, L4D2Glow_Constant, 0, 0, { 255, 0, 0 }, true);
				// TODO:
				DataPack pack;
				CreateDataTimer(4.0, Timer_ExplodeBomb, pack);
				pack.WriteCell(GetClientUserId(activator));
				pack.WriteCell(0);
				pack.WriteCell(GetRandomInt(30, 45)); // random duration (# ticks)
			} else if(response == Sorry_RejectDraw4) {
				PrintToChat(activator, "Draw 4.");
				ArrayList players = new ArrayList();
				for(int i = 1; i <= MaxClients; i++) {
					if(IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == 2 && !IsFakeClient(i)) {
						// PrintToConsoleAll("draw4: add %d %N", i, i);
						players.Push(i); // happens in a tick don't worry about index
						// weigh all other survivors higher than themselves
						if(i != activator) {
							players.Push(i);
						}
					}
				}
				if(players.Length == 0) {
					PrintToChat(activator, "There was no one to apologize to, failed. :(");
				} else {
					for(int i = 0; i < 4; i++) {
						int index = GetRandomInt(0, players.Length - 1);
						int player = players.Get(index);
						SendApology(activator, player, "drew 4");
					}
				}
				delete players;
			} else if(response == Sorry_RejectSpook) {
				SpookPlayer(activator, GetRandomInt(0, 1));
			} else if(!HandleResponse(response, Type_Reject, activator, target, eventId)) {
				PrintToChat(target, "That response is not supported (#%d), tell jackz bad", view_as<int>(response));
			}
			LogAction(target, activator, "\"%L\" rejected \"%L\"'s apology (response = %d)", target, activator, response);
		}
	}
}


Action Timer_RandomApology(Handle h, DataPack pack) {
	pack.Reset();
	int activator = GetClientOfUserId(pack.ReadCell());
	int target = GetClientOfUserId(pack.ReadCell());
	if(activator > 0 && target > 0) {
		sorryResponseValues response;
		PrintToChat(activator, "%N's apology was fake...", target);
		if(pack.ReadCell() > 0) {
			// Was fake reject, give an accept:
			response = view_as<sorryResponseValues>(GetRandomInt(1, sorryBounds[1]));
		} else {
			// Was fake accept, give a reject:
			response = view_as<sorryResponseValues>(GetRandomInt(sorryBounds[0], 0));
		}
		HandleApologyResponse(activator, target, "", response);
	}
	return Plugin_Handled;
}

int ApologizeHandler(Menu menu, MenuAction action, int target, int param2) {
	if (action == MenuAction_Select) {
		// userid(int)|eventId(str)|responseId(int)|behalfOf(int)
		static char info[32];
		menu.GetItem(param2, info, sizeof(info));
		static char str[4][EVENT_ID_LENGTH];
		ExplodeString(info, "|", str, 4, EVENT_ID_LENGTH, false);
		int activator = GetClientOfUserId(StringToInt(str[0])); // apologizer
		sorryResponseValues response = view_as<sorryResponseValues>(StringToInt(str[2])); // 0: reject, 1 : approve
		int behalfOf = GetClientOfUserId(StringToInt(str[3]));
		if(behalfOf > 0) target = behalfOf; // temp
		if(activator == 0) {
			ReplyToCommand(target, "Player has disconnected");
			return 0;
		}
		HandleApologyResponse(activator, target, str[1], response);
	} else if(action == MenuAction_Cancel) {
	} else if (action == MenuAction_End)
		delete menu;
	return 0;
}

public void OnMapEnd() {
	for(int i = 1; i <= MaxClients; i++) {
		for(int j = 0; j < MAX_SORRY_DATA; j++) {
			sorryData[i][j].Reset();
		}
	}
	clownLastHonked.Clear();
	foundSaferoomPos = false;
}


public Action OnPlayerRunCmd(int client, int& buttons, int& impulse, float vel[3], float angles[3], int& weapon, int& subtype, int& cmdnum, int& tickcount, int& seed, int mouse[2]) {
	for(int i = 0; i < g_onPlayerRunCmdForwards.Length; i++) {
		PrivateForward fwd = g_onPlayerRunCmdForwards.Get(i);

		Call_StartForward(fwd);
		Call_PushCell(client);
		Call_PushCellRef(buttons);
		Call_PushCellRef(impulse);
		Call_PushArray(vel, 3);
		Call_PushArray(angles, 3);
		Call_PushCellRef(weapon);
		Call_PushCellRef(subtype);
		Call_PushCellRef(cmdnum);
		Call_PushCellRef(tickcount);
		Call_PushCellRef(seed);
		Call_PushArray(mouse, 2);
		// Stop chain if handler wants to
		Action ret;
		if(Call_Finish(ret) == SP_ERROR_NONE && ret != Plugin_Continue) {
			return ret;
		}
	}
	return Plugin_Continue;
}

public Action OnTakeDamage(int victim, int& attacker, int& inflictor, float& damage, int& damagetype) {
	for(int i = 0; i < g_onTakeDamageForwards.Length; i++) {
		PrivateForward fwd = g_onTakeDamageForwards.Get(i);

		Call_StartForward(fwd);
		Call_PushCell(victim);
		Call_PushCellRef(attacker);
		Call_PushCellRef(inflictor);
		Call_PushCellRef(damage);
		Call_PushCellRef(damagetype);
		// Stop chain if handler wants to
		Action ret;
		if(Call_Finish(ret) == SP_ERROR_NONE && ret != Plugin_Continue) {
			return ret;
		}
	}
	return Plugin_Continue;
}


// TODO: migrate everything under here

typedef SorryResponseHandler = function void (int apologizer, int target, const char[] eventId);
typedef OnPlayerRunCmd = function Action (int client, int& buttons, int& impulse, float vel[3], float angles[3], int& weapon, int& subtype, int& cmdnum, int& tickcount, int& seed, int mouse[2]);
typedef OnClientSayCommand = function Action (int client, const char[] command, const char[] sArgs);
typedef OnTakeDamage = function Action (int victim, int& attacker, int& inflictor, float& damage, int& damagetype);

enum SorryResponseType {
	Type_Reject = -1,
	Type_Neutral = 0,
	Type_Accept = 1
}

enum struct SorryHandlerData {
	SorryResponseType type;
	PrivateForward OnActivate;
	PrivateForward OnPlayerRunCmd;
	PrivateForward OnClientSayCommand;
	PrivateForward OnTakeDamage;
}

methodmap ResponseBuilder {
	public ResponseBuilder(sorryResponseValues id, SorryResponseType type, SorryResponseHandler handler) {
		SorryHandlerData data;
		data.type = type;
		data.OnActivate = new PrivateForward(ET_Event, Param_Cell, Param_Cell, Param_String);
		data.OnActivate.AddFunction(INVALID_HANDLE, handler);
		g_sorryResponseHandlers.SetArray(id, data, sizeof(data));
		PrintToServer("[Sorry] Registered response %d type=%d", id, type);
		return view_as<ResponseBuilder>(id);
	}

	/** Registers an OnPlayerRunCmd handler for this response */
	public ResponseBuilder OnPlayerRunCmd(OnPlayerRunCmd func) {
		SorryHandlerData data;
		g_sorryResponseHandlers.GetArray(this, data, sizeof(data));
		if(data.OnPlayerRunCmd == null) data.OnPlayerRunCmd = new PrivateForward(ET_Event, Param_Cell, Param_CellByRef, Param_CellByRef, Param_Array, Param_Array, Param_CellByRef, Param_CellByRef, Param_CellByRef, Param_CellByRef, Param_CellByRef, Param_Array);
		data.OnPlayerRunCmd.AddFunction(INVALID_HANDLE, func);
		g_sorryResponseHandlers.SetArray(this, data, sizeof(data));
		return this;
	}

	/** Registers an OnPlayerSayCommand handler for this response */
	public ResponseBuilder OnClientSayCommand(OnClientSayCommand func) {
		SorryHandlerData data;
		g_sorryResponseHandlers.GetArray(this, data, sizeof(data));
		if(data.OnClientSayCommand == null) data.OnClientSayCommand = new PrivateForward(ET_Event, Param_Cell, Param_String, Param_String);
		data.OnClientSayCommand.AddFunction(INVALID_HANDLE, func);
		g_sorryResponseHandlers.SetArray(this, data, sizeof(data));
		return this;
	}

	/** Registers an OnTakeDamage handler for this response */
	public ResponseBuilder OnTakeDamage(OnTakeDamage func) {
		SorryHandlerData data;
		g_sorryResponseHandlers.GetArray(this, data, sizeof(data));
		if(data.OnTakeDamage == null) data.OnTakeDamage = new PrivateForward(ET_Event, Param_Cell, Param_CellByRef, Param_CellByRef, Param_CellByRef, Param_CellByRef);
		data.OnTakeDamage.AddFunction(INVALID_HANDLE, func);
		g_sorryResponseHandlers.SetArray(this, data, sizeof(data));
		return this;
	}
}

bool HandleResponse(sorryResponseValues id, SorryResponseType type, int activator, int target, const char[] eventId) {
	SorryHandlerData data;
	if(g_sorryResponseHandlers.GetArray(id, data, sizeof(data)) && data.type == type) {
		Call_StartForward(data.OnActivate);
		Call_PushCell(activator);
		Call_PushCell(target);
		Call_PushString(eventId);
		// TODO: custom return type?
		if(Call_Finish() == SP_ERROR_NONE) {
			return true;
		}
	}
	return false;
}

void _registerResponses() {
	if(g_sorryResponseHandlers != null) ThrowError("_registerResponses already called");
	g_sorryResponseHandlers = new AnyMap();

	RegisterResponses();
	_collectForwards();
}

void _collectForwards() {
	g_onPlayerRunCmdForwards = new ArrayList();
	g_onClientSayCommandForwards = new ArrayList();
	g_onTakeDamageForwards = new ArrayList();

	AnyMapSnapshot snapshot = g_sorryResponseHandlers.Snapshot();
	SorryHandlerData data;
	for(int i = 0; i < snapshot.Length; i++) {
		sorryResponseValues id = view_as<sorryResponseValues>(snapshot.GetKey(i));
		if(!g_sorryResponseHandlers.GetArray(id, data, sizeof(data))) {
			ThrowError("array missing elem i=%d id=%d", i, id);
		}
		if(data.OnPlayerRunCmd != null) {
			g_onPlayerRunCmdForwards.Push(data.OnPlayerRunCmd);
		}
		if(data.OnClientSayCommand != null) {
			g_onClientSayCommandForwards.Push(data.OnClientSayCommand);
		}
		if(data.OnTakeDamage != null) {
			g_onTakeDamageForwards.Push(data.OnTakeDamage);
		}
	}
	delete snapshot;
}


// used by internal
Action Timer_KillPlayer(Handle h, int activator) {
	float vel[3] = { 10000.0, 10000.0, 1000.0 };
	SDKHooks_TakeDamage(activator, activator, activator, 1000.0, DMG_BLAST, -1, vel);
	return Plugin_Handled;
}

public void OnMapStart() {
	PrecacheSound("ui/survival_playerrec.wav");
	PrecacheSound("player/orch_hit_csharp_short.wav");
	g_iLaserIndex = PrecacheModel("materials/sprites/laserbeam.vmt");
	g_HaloSprite = PrecacheModel("materials/sprites/glow01.vmt");
}

public void OnClientPutInServer(int client) {
	isInSaferoom[client] = false;
	// Damage handler for responses, should be all players
	SDKHook(client, SDKHook_OnTakeDamageAlive, OnTakeDamage);
	
	if(!IsFakeClient(client)) {
		// Damage detection to mark an auto apology
		SDKHook(client, SDKHook_OnTakeDamagePost, OnTakeDamagePost);
	}
}


public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs) {
   	for(int i = 0; i < g_onClientSayCommandForwards.Length; i++) {
		PrivateForward fwd = g_onClientSayCommandForwards.Get(i);

		Call_StartForward(fwd);
		Call_PushCell(client);
		Call_PushString(command);
		Call_PushString(sArgs);
		// Stop chain if handler wants to
		Action ret;
		if(Call_Finish(ret) == SP_ERROR_NONE && ret != Plugin_Continue) {
			return ret;
		}
	}
	
	return Plugin_Continue;
}

public void OnClientDisconnect(int client) {
	SorryStore[client].Clear();
	for(int i = 0; i < MAX_SORRY_DATA; i++) {
		sorryData[client][i].Reset();
	}
}

