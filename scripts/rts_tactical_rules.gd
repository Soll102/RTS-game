extends RefCounted
## Current combat/control rules. Earlier save formats keep their own ruleset.
const ID="tactical-command-v2"
const FORMAT=14
const REVISION=7
const WALL_HP=1200
const CITY_HP=800
const CITY_GARRISON=400
const CAPTURE_TICKS=150
const GUARD_RANGE=220
const GUARD_INTERVAL=20
const GUARD_TARGETS=6
const ARCHER_INTERVAL=20
const FIELD_POWER_PERCENT=65
const ACQUIRE_RANGE=80
const MAX_WAYPOINTS=16
const REPATH_TICKS=3

## Damage dealt to EACH targeted formation by one city volley. Fortified cities
## fire at up to GUARD_TARGETS attackers at once, so assaults need real losses.
static func guard_power(city: Dictionary) -> int:
	var power: int=clampi(int(city.garrison)/80+2,2,6)
	return maxi(1,power/2) if city.food==0 else power

static func city_phase(city: Dictionary) -> String:
	if city.capture_ticks>0:return "Occupying %d%%"%(int(city.capture_ticks)*100/capture_duration(city))
	if city.wall_hp>0:return "Walls intact"
	if city.garrison>0:return "Breach — defenders fighting"
	if city.city_hp>0:return "Breach — inner defenses"
	return "Ready to occupy"

static func capture_duration(city: Dictionary) -> int:return CAPTURE_TICKS if city.kind=="city" else 50
