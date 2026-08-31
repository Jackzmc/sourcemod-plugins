MutationOptions <-
{
    CommonLimit = 0
    MegaMobSize = 0
 	WanderingZombieDensityModifier = 0
 	MaxSpecials  = 0
 	TankLimit    = 0
 	WitchLimit   = 0
	BoomerLimit  = 0
 	ChargerLimit = 0
    HunterLimit  = 0
    JockeyLimit  = 0
    SpitterLimit = 0
    SmokerLimit  = 0
	cm_NoSurvivorBots = true
	SurvivorMaxIncapacitatedCount = 0
	
	function AllowWeaponSpawn(weaponName) {
		return false
	}
	
	function GetDefaultItem( idx ) {
		return 0
	}

}

// MutationState is controlled by the plugin - I don't want to code in squirrel.

MutationState <-
{
	State = 0 //0=pending; 1=hiding time; 2=seeking; 3=props win; 4=seeker win 
	Tick = 0
	MaxTime = 100
}

function HUDUpdate() {
	switch (SessionState.State) {
		case 0: // start up
			return "Waiting to start"
			break
		case 1: // hiding
			return "Hiding. " + (SessionState.MaxTime - SessionState.Tick) + " s left"
			break
		case 2: // seeker hunting
			local rs = SessionState.MaxTime-SessionState.Tick
			local m = rs/60
			local s = rs - m*60
			if(s < 10)
				return m + ":0" + s
			else
				return m + ":" + s
		case 3: // props win
			return "Times up! Props win"
		case 4: // Seeker Wins
			return "Seeker has won"
		default:
			break
	}
	return ""
}

function SetupModeHUD( ) {
	ModeHUD <- {
    	Fields = {
			infoBox = {slot = HUD_MID_TOP, name = "mutation_name", datafunc = HUDUpdate}
        }
	}
	HUDSetLayout( ModeHUD )
}

function Update() {
	SessionState.Tick++;
}