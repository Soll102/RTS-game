extends RefCounted
## Original/human-selected portraits; RTS stats, skills and formulas are authored.
const REVISION=1
const SOURCE_PATH="res://data/commander-source.json"
const FACTIONS=["wei","shu","wu"]
const MAX_FORMATIONS=6
const SKILLS={
	"guan_yu":["Azure Dragon Sweep","sweep",140,80,55,120,0,"Strike enemies in a forward arc."],
	"zhang_fei":["Changban Roar","roar",25,75,75,160,0,"Reduce the morale of nearby enemies."],
	"zhao_yun":["Dragon Advance","speed",150,0,0,140,60,"Increase this formation's movement speed for 6 seconds."],
	"zhuge_liang":["Eight Trigrams","defense_aura",125,90,90,200,80,"Protect nearby allied formations for 8 seconds."],
	"cao_cao":["Heroic Command","rally",20,90,90,180,0,"Restore the morale of nearby allies."],
	"xiahou_dun":["Unbroken Vanguard","defense",140,0,0,200,80,"Protect this formation for 8 seconds."],
	"sun_ce":["Little Conqueror","attack",140,0,0,160,60,"Increase this formation's battle damage for 6 seconds."],
	"zhou_yu":["Fire Volley","volley",120,120,45,180,0,"Strike the target and nearby enemies."],
	"zhang_liao":["Hefei Assault","attack",135,0,0,160,60,"Increase this formation's battle damage for 6 seconds."],
	"cao_ren":["Iron Rampart","defense_aura",120,80,80,200,80,"Protect nearby allied formations for 8 seconds."],
	"xu_huang":["Steady Advance","attack",130,0,0,160,60,"Increase this formation's battle damage for 6 seconds."],
	"xiahou_yuan":["Swift Volley","volley",110,120,35,180,0,"Strike the target and nearby enemies."],
	"xu_chu":["Tiger Guard","defense",140,0,0,200,80,"Protect this formation for 8 seconds."],
	"dian_wei":["Twin Halberds","sweep",130,80,50,140,0,"Strike enemies in a forward arc."],
	"liu_bei":["Benevolent Rally","rally",18,90,90,180,0,"Restore the morale of nearby allies."],
	"ma_chao":["Western Charge","attack",140,0,0,160,60,"Increase this formation's battle damage for 6 seconds."],
	"huang_zhong":["Veteran Volley","volley",120,120,40,180,0,"Strike the target and nearby enemies."],
	"sun_quan":["River Command","rally",18,90,90,180,0,"Restore the morale of nearby allies."],
	"gan_ning":["Night Raid","attack",140,0,0,160,60,"Increase this formation's battle damage for 6 seconds."],
	"lu_meng":["White Robes","defense",135,0,0,200,80,"Protect this formation for 8 seconds."],
	"lu_xun":["Burning Front","volley",115,120,45,180,0,"Strike the target and nearby enemies."],
	"huang_gai":["Resolute Guard","defense",135,0,0,200,80,"Protect this formation for 8 seconds."],
	"taishi_ci":["Piercing Volley","volley",125,120,30,180,0,"Strike the target and nearby enemies."]}
const INITIAL_ASSIGNMENTS={"wei-infantry":"cao_cao","wei-archers":"xiahou_yuan","wei-cavalry":"zhang_liao","wei-siege":"cao_ren",
	"shu-infantry":"guan_yu","shu-archers":"huang_zhong","shu-cavalry":"zhao_yun","shu-siege":"zhuge_liang",
	"wu-infantry":"sun_ce","wu-archers":"zhou_yu","wu-cavalry":"gan_ning","wu-siege":"lu_meng"}
static var DEFINITIONS: Dictionary=_load_definitions()

static func _load_definitions() -> Dictionary:
	var data=JSON.parse_string(FileAccess.get_file_as_string(SOURCE_PATH))
	if not data is Dictionary or not data.get("officers") is Dictionary:return {}
	var result: Dictionary={}
	for id in SKILLS:
		if not data.officers.get(id) is Dictionary:continue
		var source: Dictionary=data.officers[id];var skill: Array=SKILLS[id]
		var definition: Dictionary=source.duplicate(true)
		definition.str=int(definition.str);definition.lead=int(definition.lead)
		definition.merge({"skill":skill[0],"effect":skill[1],"power":skill[2],"range":skill[3],"radius":skill[4],"cooldown":skill[5],"duration":skill[6],"description":skill[7]},true)
		result[id]=definition
	return result

static func choices_for(faction: String) -> Array:
	var result: Array=[]
	for id in SKILLS:
		if DEFINITIONS.has(id) and DEFINITIONS[id].faction==faction:result.append(id)
	return result

static func stat_percent(value: int) -> int:
	return 50+clampi(value,0,100)

static func skill_power(id: String) -> int:
	if not DEFINITIONS.has(id):return 0
	var d: Dictionary=DEFINITIONS[id];var percent: int=stat_percent(int(d.str))
	if d.effect in ["speed","attack","defense","defense_aura"]:return 100+int(d.power-100)*percent/100
	return maxi(1,int(d.power)*percent/100)

static func source_hash() -> String:
	return FileAccess.get_sha256(SOURCE_PATH)

static func create_roster() -> Dictionary:
	var result: Dictionary={}
	for id in DEFINITIONS:result[id]={"army_id":"","reserved_army":"","cooldown_until":0}
	return result
