extends RefCounted
## Gameplay data only. Names do not imply a verified model or portrait binding.
const REVISION=1
const DEFINITIONS={
	"guan_yu":{"name":"Guan Yu","faction":"shu","skill":"Azure Dragon Sweep","effect":"sweep","power":140,"range":80,"radius":55,"cooldown":120,"duration":0,"description":"Strike nearby enemies in front of the target direction."},
	"zhang_fei":{"name":"Zhang Fei","faction":"shu","skill":"Changban Roar","effect":"roar","power":25,"range":75,"radius":75,"cooldown":160,"duration":0,"description":"Reduce nearby enemy morale."},
	"zhao_yun":{"name":"Zhao Yun","faction":"shu","skill":"Dragon Advance","effect":"speed","power":150,"range":0,"radius":0,"cooldown":140,"duration":60,"description":"Increase movement speed by 50% for 6 seconds."},
	"zhuge_liang":{"name":"Zhuge Liang","faction":"shu","skill":"Eight Trigrams","effect":"defense_aura","power":125,"range":90,"radius":90,"cooldown":200,"duration":80,"description":"Increase allied protection by 25% for 8 seconds."},
	"cao_cao":{"name":"Cao Cao","faction":"wei","skill":"Heroic Command","effect":"rally","power":20,"range":90,"radius":90,"cooldown":180,"duration":0,"description":"Restore nearby allied morale."},
	"xiahou_dun":{"name":"Xiahou Dun","faction":"wei","skill":"Unbroken Vanguard","effect":"defense","power":140,"range":0,"radius":0,"cooldown":200,"duration":80,"description":"Increase protection by 40% for 8 seconds."},
	"sun_ce":{"name":"Sun Ce","faction":"wu","skill":"Little Conqueror","effect":"attack","power":140,"range":0,"radius":0,"cooldown":160,"duration":60,"description":"Increase battle damage by 40% for 6 seconds."},
	"zhou_yu":{"name":"Zhou Yu","faction":"wu","skill":"Fire Volley","effect":"volley","power":120,"range":120,"radius":45,"cooldown":180,"duration":0,"description":"Strike an enemy and nearby enemies with a fire volley."}}
const INITIAL_ASSIGNMENTS={"wei-infantry":"cao_cao","wei-cavalry":"xiahou_dun","shu-infantry":"guan_yu","shu-cavalry":"zhao_yun","wu-infantry":"sun_ce","wu-archers":"zhou_yu"}
const PRESENTATION={"soldiers":8,"hero_additional":true,"hero_scale_proposal":135,"visual_binding":null}

static func create_roster(armies: Dictionary) -> Dictionary:
	var result: Dictionary={}
	for id in DEFINITIONS:result[id]={"army_id":"","cooldown_until":0,"defeated":false}
	for army in INITIAL_ASSIGNMENTS:
		if armies.has(army) and armies[army].troops>0 and armies[army].faction==DEFINITIONS[INITIAL_ASSIGNMENTS[army]].faction:result[INITIAL_ASSIGNMENTS[army]].army_id=army
	return result
