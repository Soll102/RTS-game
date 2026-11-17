extends RefCounted
## Original strategic combat rules. All modifiers are integer percentages.
const UNIT_TYPES = ["infantry", "cavalry", "archers", "siege"]
const STANCES = ["balanced", "aggressive", "defensive"]
const TERRAINS = ["plain", "forest", "hill", "road", "ford"]

static func lead_percent(army: Dictionary) -> int:
	return 50+clampi(int(army.get("commander_lead",50)),0,100)

static func has_food(army: Dictionary) -> bool:
	return int(army["food"])>0 or (not str(army.get("resident_city","")).is_empty() and army.get("supplied",false))

static func counter_percent(attacker: String, defender: String, traditional: bool=false) -> int:
	if (attacker == "infantry" and defender == "cavalry") or (attacker == "cavalry" and defender == "archers") or (attacker == "archers" and defender == "infantry"):
		return 180 if traditional else 125
	if attacker == "siege": return 35 if traditional else 60
	if defender == "siege": return 180 if traditional else 125
	return 100

static func defense(army: Dictionary, terrain: String, settlement_bonus: int) -> int:
	var value: int = int(army["defense"]) + settlement_bonus
	if army.get("routed",false): return 0
	if army["stance"] == "defensive": value += 30
	elif army["stance"] == "aggressive": value = maxi(0,value-10)
	if terrain == "forest": value += 20
	elif terrain == "hill": value += 25
	elif terrain == "ford": value = maxi(0,value-15)
	return value

static func casualties(attacker: Dictionary, defender: Dictionary, terrain: String, settlement_bonus: int = 0) -> int:
	var morale: int = maxi(25,int(attacker["morale"]))
	var power: int = maxi(1,int(attacker["troops"])*int(attacker["attack"])*morale/10000)
	var modifier: int = counter_percent(attacker["unit_type"],defender["unit_type"],attacker.get("traditional_unit",false))
	if attacker["stance"] == "aggressive": modifier = modifier*120/100
	elif attacker["stance"] == "defensive": modifier = modifier*80/100
	if attacker["unit_type"] == "cavalry" and terrain in ["forest","hill","ford"]: modifier = modifier*70/100
	if not has_food(attacker): modifier = modifier*75/100
	if defender.get("routed",false): modifier = modifier*250/100
	power = maxi(1,power*modifier/100)
	power=maxi(1,power*lead_percent(attacker)/100)
	return maxi(1,power*100/(100+defense(defender,terrain,settlement_bonus)))

static func siege_damage(army: Dictionary) -> int:
	var value: int = int(army["siege_power"])
	if army["unit_type"] == "siege": value *= 2
	elif army["unit_type"] == "cavalry": value = maxi(1,value/2)
	if not has_food(army): value = maxi(1,value/2)
	return maxi(1,value*lead_percent(army)/100)
