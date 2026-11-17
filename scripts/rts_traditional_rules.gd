extends RefCounted
## Traditional RTS v1: compact cohorts with distinct equipment and field roles.
const ID="traditional-rts-v1"
const MEMBERS=4
const FORMATION_LIMIT=6
const PROFILES={
	"infantry":{"strength":100,"attack":16,"defense":30,"movement":2,"siege":4,"training":100},
	"archers":{"strength":100,"attack":14,"defense":8,"movement":2,"siege":1,"training":120},
	"cavalry":{"strength":100,"attack":22,"defense":18,"movement":4,"siege":1,"training":160},
	"siege":{"strength":80,"attack":6,"defense":12,"movement":1,"siege":28,"training":200}}
static func configure_army(a: Dictionary) -> void:
	var p: Dictionary=PROFILES[a.unit_type]
	a.attack=p.attack;a.defense=p.defense;a.movement_per_tick=p.movement;a.siege_power=p.siege
	a.traditional_unit=true
static func training(kind: String) -> int:return PROFILES[kind].training
