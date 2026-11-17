extends RefCounted
const Simulation=preload("res://scripts/battle_campaign.gd")
const WORLD_PATH="res://data/v8-world-next.json"
const CAMPAIGN_ID="v8-unification"
const CAMPAIGN_TITLE="Unification"
const FACTIONS=["wei","shu","wu"]

static func create(player_faction: String="wei") -> RefCounted:
	if player_faction not in FACTIONS:
		push_error("Choose Wei, Shu or Wu for the Unification campaign.")
		return null
	var path: String=WORLD_PATH
	var raw: String=FileAccess.get_file_as_string(path)
	var world=JSON.parse_string(raw)
	if not world is Dictionary: push_error("V8 world file is invalid."); return null
	world["sha256"]=FileAccess.get_sha256(path)
	# Scenario ownership is authored balance data, not a map geometry edit.
	var owners: Dictionary={"C1":"wei","C2":"shu","C3":"wei","C4":"shu","C5":"wu","C6":"wu","C7":"wei","C8":"shu","V1":"shu","V2":"wei","V3":"wu"}
	var cities: Array=[]; var armies: Array=[]; var count: Dictionary={}
	for s in world["settlements"]:
		var faction: String=owners[s["id"]]
		cities.append({"id":s["id"],"node":s["node"],"gate_nodes":s.get("gate_nodes",[s["node"]]).duplicate(),"owner":faction,"kind":s["kind"],
			"food":5000 if s["kind"]=="city" else 1500,"wall_hp":300 if s["kind"]=="city" else 0,
			"garrison":450 if s["kind"]=="city" else 100,"food_per_interval":12 if s["kind"]=="city" else 25})
		if s["kind"]!="city" or int(count.get(faction,0))>=2: continue
		var index: int=int(count.get(faction,0)); count[faction]=index+1
		for kind in ["infantry","archers"] if index==0 else ["cavalry","siege"]:
			armies.append({"id":faction+"-"+kind,"node":s["node"],"faction":faction,"unit_type":kind,
				"troops":100 if kind!="siege" else 80,"food":80,"food_capacity":120,
				"movement_per_tick":Simulation.PROFILES[kind]["movement"],"siege_power":Simulation.PROFILES[kind]["siege"],"attack":10})
	var sim=Simulation.new()
	var error: String=sim.configure(world,armies,cities,20261028)
	if not error.is_empty(): push_error(error); return null
	var opponents: Array=[]
	for faction in ["wei","shu","wu"]:
		if faction!=player_faction: opponents.append(faction)
	sim.configure_ai(opponents)
	# The first paused frame must describe real logistics without advancing time.
	sim._update_supply(false)
	return sim
