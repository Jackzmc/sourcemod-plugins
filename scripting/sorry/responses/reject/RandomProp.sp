#define SOUND_PIANO "plats/piano.wav"

#define NUM_RANDOM_PROPS 14
char RANDOM_PROP[NUM_RANDOM_PROPS][] = {
	"models/props_urban/plastic_flamingo001.mdl",
	"models/props_fairgrounds/swan_boat.mdl",
	"models/props_interiors/couch.mdl",
	"models/props_junk/gnome.mdl",
	"models/props_interiors/toaster.mdl",
	"models/props_junk/wood_crate002a.mdl",
	"models/props_mall/mall_bench.mdl",
	"models/props_interiors/bed.mdl",
	"models/props_furniture/piano.mdl",
	"models/props_junk/wheebarrow01a.mdl",
	"models/props_interiors/toiletpaperroll.mdl",
	"models/props_interiors/toilet.mdl",
	"models/props_foliage/urban_pot_bigplant01.mdl",
	"models/props_foliage/urban_pot_clay01.mdl"
};

void RandomProp_OnActivate(int apologizer, int target, const char[] eventId) {
    int index = GetRandomInt(0, NUM_RANDOM_PROPS - 1);
	PrecacheModel(RANDOM_PROP[index]);
	TempSetModel(apologizer, 80.0, RANDOM_PROP[index]);
}

bool Filter_IgnorePlayerOnlyPlayers(int entity, int mask, int data) {
	return entity > 0 && entity != data && entity <= MaxClients;
}

Action RandomProp_OnPlayerRunCmd(int client, int& buttons, int& impulse, float vel[3], float angles[3], int& weapon, int& subtype, int& cmdnum, int& tickcount, int& seed, int mouse[2]) {
    if(client > 0) {
		int oldButtons = GetEntProp(client, Prop_Data, "m_nOldButtons");
		bool keyUse = !(oldButtons & IN_USE) && (buttons & IN_USE);
		bool keyShove = !(oldButtons & IN_ATTACK2) && (buttons & IN_ATTACK2);
		if(keyUse || keyShove) {
			float pos[3];
			int entity = GetCursorLimited(client, 80.0, pos, Filter_IgnorePlayerOnlyPlayers);
			if(entity > 0) {
				char model[64];
				GetEntPropString(entity, Prop_Data, "m_ModelName", model, sizeof(model));
				if(StrEqual(model, "models/props_furniture/piano.mdl")) {
					PrecacheSound(SOUND_PIANO);
					EmitSoundToAll(SOUND_PIANO, -2, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_CHANGEVOL, 0.55, 100, -1, pos);
				}
			}
		}
	}
	return Plugin_Continue;
}