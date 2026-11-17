extends RefCounted
## Original data-only RTS rules, not reverse-engineered SAN14 gameplay.
## Distances are integer logical units; one tick is 100 ms of simulation time.

const FORMAT_VERSION = 4
const AI = preload("res://scripts/rts_ai.gd")
const Combat = preload("res://scripts/rts_combat_rules.gd")
const PriorityQueue = preload("res://scripts/rts_priority_queue.gd")
const CompactGraph = preload("res://scripts/rts_compact_graph.gd")
var _compact_graph: RefCounted
var _compact_graph_signature: int=-1
var _compact_locked_nodes: Dictionary={}
var _compact_route_trees: Dictionary={}
var _compact_paths: Dictionary={}
const TICK_US = 100000
const SUPPLY_INTERVAL_TICKS = 10
const SUPPLY_RANGE = 40
const RECRUITMENT_TICKS = 30
const MAX_RECRUITMENT_QUEUE = 3
const MAX_EVENT_HISTORY = 2048
## March cadence. Fractional carry keeps the average pace smooth without
## changing the integer unit profiles stored in campaign saves.
const MARCH_RATE = 0.65
var march_credit: Dictionary = {}
## Immutable world obstacles. Routing, click validation and group orders all
## consult this one mask; previously they disagreed about which nodes exist.
var impassable_nodes: Dictionary = {}
const VALID_ORDERS = ["move", "attack_move", "attack", "siege", "hold", "retreat", "stance"]
const VALID_SETTLEMENT_TYPES = ["city", "village"]

var nodes: Dictionary = {}
var armies: Dictionary = {}
var cities: Dictionary = {}
var tick: int = 0
var accumulator_us: int = 0
var speed: int = 1
var paused: bool = false
var seed_value: int = 1
var events: Array = []
var command_ids: Dictionary = {}
var command_queue: Array = []
var source_provenance: String = "authored; no original game data"
var ai_factions: Array = []
var victory_factions: Array = []
var winner: String = ""
var performance_metrics: Dictionary = {"supply_rebuilds": 0, "supply_node_visits": 0, "battle_nodes": 0, "battle_armies": 0}
var _supply_cache: Dictionary = {}
var _supply_dirty: bool = true
var _supply_signature: int = 0

func configure(world: Dictionary, initial_armies: Array, initial_cities: Array, initial_seed: int = 1) -> String:
	march_credit.clear()
	if initial_seed < 0:
		return "Seed must be a nonnegative integer."
	if not world.get("nodes") is Dictionary:
		return "World nodes must be a dictionary."
	var candidate_nodes: Dictionary = world.get("nodes", {}).duplicate(true)
	var error: String = _validate_graph(candidate_nodes)
	if not error.is_empty():
		return error
	var candidate_armies: Dictionary = {}
	for item in initial_armies:
		if not item is Dictionary:
			return "Army must be a dictionary."
		var army: Dictionary = item.duplicate(true)
		for key in ["id", "node", "faction"]:
			if not army.get(key) is String or army[key].is_empty():
				return "Army identity, faction or node is invalid."
		for key in ["troops", "food", "food_capacity", "morale", "movement_per_tick", "attack", "defense", "siege_power"]:
			if army.has(key) and not _integer_at_least(army[key], 0):
				return "Army numeric field is invalid: " + key
		if not army.has("troops") or int(army.get("food_capacity", 20)) < int(army.get("food", 20)) or int(army.get("morale", 100)) > 100:
			return "Army troops, food capacity or morale is invalid."
		for key in ["movement_per_tick", "attack", "siege_power"]:
			if army.has(key) and int(army[key]) < 1:
				return "Army rate must be positive: " + key
		var id: String = str(army.get("id", ""))
		if id.is_empty() or candidate_armies.has(id):
			return "Army IDs must be present and unique."
		if not candidate_nodes.has(str(army.get("node", ""))) or int(army.get("troops", -1)) < 0:
			return "Army node or troop count is invalid."
		army["id"] = id
		army["node"] = str(army["node"])
		army["troops"] = int(army["troops"])
		army["faction"] = str(army.get("faction", ""))
		army["food_capacity"] = int(army.get("food_capacity", 20))
		army["food"] = clampi(int(army.get("food", 20)), 0, army["food_capacity"])
		army["morale"] = clampi(int(army.get("morale", 100)), 0, 100)
		army["movement_per_tick"] = maxi(1, int(army.get("movement_per_tick", 2)))
		army["attack"] = maxi(1, int(army.get("attack", 10)))
		army["defense"] = maxi(0, int(army.get("defense", 10)))
		army["siege_power"] = maxi(1, int(army.get("siege_power", 2)))
		army["supplied"] = false
		army["order"] = {"type": "hold", "target": ""}
		army["route"] = []
		army["edge_progress"] = 0
		army["siege_state"] = "none"
		army["unit_type"] = army.get("unit_type", "infantry")
		army["stance"] = army.get("stance", "balanced")
		if army["unit_type"] not in Combat.UNIT_TYPES or army["stance"] not in Combat.STANCES:
			return "Army unit type or stance is invalid."
		candidate_armies[id] = army
	var candidate_cities: Dictionary = {}
	for item in initial_cities:
		if not item is Dictionary:
			return "City must be a dictionary."
		var city: Dictionary = item.duplicate(true)
		for key in ["id", "node", "owner"]:
			if not city.get(key) is String or city[key].is_empty():
				return "City identity, owner or node is invalid."
		for key in ["wall_hp", "garrison", "food", "food_per_interval", "defense_bonus"]:
			if city.has(key) and not _integer_at_least(city[key], 0):
				return "City numeric field is invalid: " + key
		if city.has("production_queue") and not city["production_queue"] is Array:
			return "City production queue must be an array."
		var id: String = str(city.get("id", ""))
		if id.is_empty() or candidate_cities.has(id):
			return "City IDs must be present and unique."
		if not candidate_nodes.has(str(city.get("node", ""))):
			return "City node is invalid."
		city["id"] = id
		city["node"] = str(city["node"])
		city["owner"] = str(city.get("owner", ""))
		city["kind"] = str(city.get("kind", "city"))
		if city["kind"] not in VALID_SETTLEMENT_TYPES:
			return "Settlement type must be city or village."
		for key in ["recruitment_enabled", "victory_point"]:
			if city.has(key) and not city[key] is bool:
				return "Settlement boolean field is invalid: " + key
		city["wall_hp"] = maxi(0, int(city.get("wall_hp", 10)))
		city["garrison"] = maxi(0, int(city.get("garrison", 10)))
		city["food"] = maxi(0, int(city.get("food", 100)))
		city["food_per_interval"] = int(city.get("food_per_interval", 1 if city["kind"] == "village" else 0))
		city["defense_bonus"] = int(city.get("defense_bonus", 4 if city["kind"] == "village" else 15))
		city["recruitment_enabled"] = bool(city.get("recruitment_enabled", city["kind"] == "city"))
		city["victory_point"] = bool(city.get("victory_point", city["kind"] == "city"))
		city["production_queue"] = city.get("production_queue", []).duplicate(true)
		for job in city["production_queue"]:
			if job is Dictionary and not job.has("unit_type"): job["unit_type"] = "infantry"
		candidate_cities[id] = city
	var queue_error: String = _validate_production(candidate_cities, candidate_armies)
	if not queue_error.is_empty():
		return queue_error
	nodes = candidate_nodes
	armies = candidate_armies
	cities = candidate_cities
	tick = 0
	accumulator_us = 0
	speed = 1
	paused = false
	seed_value = initial_seed
	source_provenance = str(world.get("source_provenance", "authored"))
	events.clear()
	command_ids.clear()
	command_queue.clear()
	ai_factions.clear()
	victory_factions.clear()
	for city in cities.values():
		if city["victory_point"] and not victory_factions.has(city["owner"]):
			victory_factions.append(city["owner"])
	victory_factions.sort()
	winner = ""
	performance_metrics = {"supply_rebuilds": 0, "supply_node_visits": 0, "battle_nodes": 0, "battle_armies": 0}
	_supply_cache.clear()
	_supply_dirty = true
	_supply_signature = 0
	return ""

func configure_ai(factions: Array) -> String:
	var candidate: Array = []
	for faction in factions:
		if not faction is String or faction.is_empty() or candidate.has(faction):
			return "AI factions must be unique nonempty strings."
		var exists: bool = false
		for city in cities.values():
			exists = exists or city["owner"] == faction
		for army in armies.values():
			exists = exists or army["faction"] == faction
		if not exists:
			return "AI faction has no army or city."
		candidate.append(faction)
	candidate.sort()
	ai_factions = candidate
	return ""

func _validate_production(city_table: Dictionary, army_table: Dictionary) -> String:
	var reserved: Dictionary = {}
	for city in city_table.values():
		var queue: Array = city["production_queue"]
		if not city["recruitment_enabled"] and not queue.is_empty():
			return "Recruitment-disabled settlement cannot have a production queue."
		if queue.size() > MAX_RECRUITMENT_QUEUE:
			return "City recruitment queue is full."
		for job in queue:
			if not job is Dictionary or not job.get("army_id") is String or job["army_id"].is_empty() or not job.get("faction") is String or job["faction"] != city["owner"]:
				return "Recruitment job identity or faction is invalid."
			if army_table.has(job["army_id"]) or reserved.has(job["army_id"]):
				return "Recruitment army ID is already in use."
			if job.get("unit_type") not in Combat.UNIT_TYPES:
				return "Recruitment unit type is invalid."
			if not _integer_at_least(job.get("troops"), 1) or not _integer_at_least(job.get("remaining_ticks"), 1) or int(job["remaining_ticks"]) > RECRUITMENT_TICKS:
				return "Recruitment troops or duration is invalid."
			reserved[job["army_id"]] = true
	return ""

func queue_recruitment(faction: String, city_id: String, army_id: String, troops: int = 40, unit_type: String = "infantry") -> String:
	## Food is paid once when accepted; capture cancels paid jobs without refund.
	if not cities.has(city_id) or cities[city_id]["owner"] != faction:
		return "Recruitment requires a friendly city."
	if army_id.is_empty() or armies.has(army_id) or troops < 1:
		return "Recruitment army ID or troop count is invalid."
	if unit_type not in Combat.UNIT_TYPES:
		return "Recruitment unit type is invalid."
	for city in cities.values():
		for job in city["production_queue"]:
			if job["army_id"] == army_id:
				return "Recruitment army ID is already reserved."
	var city: Dictionary = cities[city_id]
	if not city["recruitment_enabled"]:
		return "Recruitment is unavailable at this settlement."
	if _city_under_siege(city):
		return "Recruitment is unavailable while the city is besieged."
	if city["production_queue"].size() >= MAX_RECRUITMENT_QUEUE:
		return "City recruitment queue is full."
	if int(city["food"]) < troops:
		return "The city does not have enough food."
	city["food"] -= troops
	city["production_queue"].append({"army_id": army_id, "faction": faction, "troops": troops, "remaining_ticks": RECRUITMENT_TICKS, "unit_type":unit_type})
	_emit("recruitment_started", {"city": city_id, "army": army_id, "faction": faction, "troops": troops})
	return ""

func _validate_graph(graph: Dictionary) -> String:
	if graph.is_empty():
		return "Navigation graph is empty."
	for id in graph:
		if not id is String or id.is_empty():
			return "Navigation node IDs must be nonempty strings."
		if not graph[id] is Dictionary or not graph[id].get("edges") is Dictionary:
			return "Navigation nodes and edges must be dictionaries."
		if graph[id].has("passable") and not graph[id]["passable"] is bool:
			return "Navigation passability must be a boolean."
		if graph[id].get("terrain", "plain") not in Combat.TERRAINS:
			return "Navigation terrain type is invalid."
		for neighbor in graph[id]["edges"]:
			if not neighbor is String or not graph.has(neighbor) or not _integer_at_least(graph[id]["edges"][neighbor], 1):
				return "Navigation edge target or distance is invalid."
	return ""

func _integer_at_least(value, minimum: int) -> bool:
	if not value is int and not value is float:
		return false
	return is_finite(float(value)) and float(value) == floor(float(value)) and float(value) >= minimum

func _sorted_ids(table: Dictionary) -> Array:
	var ids: Array = table.keys()
	ids.sort()
	return ids

func _compact_navigation() -> RefCounted:
	if _compact_graph!=null and is_same(nodes,_compact_locked_nodes):return _compact_graph
	_compact_locked_nodes={}
	# Native Variant hashing observes direct graph edits and load/configure changes.
	var signature: int=hash(nodes)
	if _compact_graph==null or signature!=_compact_graph_signature:
		_compact_graph=CompactGraph.new();_compact_graph.configure(nodes);_compact_graph_signature=signature
		_compact_route_trees.clear();_compact_paths.clear()
	return _compact_graph

func _freeze_navigation_value(value) -> void:
	if value is Dictionary:
		for child in value.values():_freeze_navigation_value(child)
		value.make_read_only()
	elif value is Array:
		for child in value:_freeze_navigation_value(child)
		value.make_read_only()

func lock_navigation_topology() -> void:
	# Campaign graph geometry never changes after scenario/load. Explicitly make
	# every nested graph container immutable before skipping repeated full hashing.
	_compact_navigation();_freeze_navigation_value(nodes);_compact_locked_nodes=nodes

func is_navigation_open(id: String) -> bool:
	if not nodes.has(id):return false
	if not bool(nodes[id].get("passable",true)):return false
	return not impassable_nodes.has(id)

## Merge the immutable world obstacles with caller-supplied dynamic blockers.
## The start node is always allowed so a formation already standing on an
## obstacle (older saves) can still walk out of it.
func _navigation_avoidance(start: String, blocked: Dictionary) -> Dictionary:
	var avoided: Dictionary=blocked.duplicate()
	for id in impassable_nodes:avoided[id]=true
	avoided.erase(start)
	return avoided

func march_budget(id: String, base: int) -> int:
	var credit: float=float(march_credit.get(id,0.0))+float(maxi(0,base))*MARCH_RATE
	var whole: int=int(floor(credit))
	march_credit[id]=credit-float(whole)
	return whole

func find_path(start: String, target: String, blocked: Dictionary = {}) -> Dictionary:
	if not nodes.has(start) or not nodes.has(target) or blocked.has(target):return {"ok":false,"route":[],"distance":-1}
	var avoided: Dictionary=_navigation_avoidance(start,blocked)
	if avoided.has(target):return {"ok":false,"route":[],"distance":-1}
	var graph: RefCounted=_compact_navigation()
	var origin: int=graph.index[start];var goal: int=graph.index[target]
	var key: Array=[start,target,hash(avoided)]
	if _compact_paths.has(key) and _compact_paths[key].blocked==avoided:
		return _compact_paths[key].path.duplicate(true)
	var result: Dictionary=graph.solve([[origin,0]],avoided,{},-1,goal,true)
	if result.distance[goal]<0:return {"ok":false,"route":[],"distance":-1}
	var route: Array=[];var cursor: int=goal
	while cursor!=origin:route.append(graph.ids[cursor]);cursor=result.previous[cursor]
	route.reverse()
	var path: Dictionary={"ok":true,"route":route,"distance":int(result.distance[goal])}
	if _compact_paths.size()>=128:_compact_paths.erase(_compact_paths.keys()[0])
	_compact_paths[key]={"blocked":avoided.duplicate(true),"path":path.duplicate(true)}
	return path

func find_routes_from(start: String) -> Dictionary:
	if not nodes.has(start):return {"start":start,"distance":{},"previous":{}}
	var graph: RefCounted=_compact_navigation();var origin: int=graph.index[start]
	if _compact_route_trees.has(start):return _compact_route_trees[start].duplicate(true)
	var avoided: Dictionary=_navigation_avoidance(start,{})
	var solved: Dictionary=graph.solve([[origin,0]],avoided)
	var distance: Dictionary={};var previous: Dictionary={}
	for i in solved.discovered:
		distance[graph.ids[i]]=int(solved.distance[i])
		if i!=origin:previous[graph.ids[i]]=graph.ids[solved.previous[i]]
	var tree: Dictionary={"start":start,"distance":distance,"previous":previous}
	if _compact_route_trees.size()>=64:_compact_route_trees.erase(_compact_route_trees.keys()[0])
	_compact_route_trees[start]=tree.duplicate(true)
	return tree

func route_from_tree(tree: Dictionary, target: String) -> Dictionary:
	if not tree["distance"].has(target): return {"ok":false,"route":[],"distance":-1}
	var cursor: String = target
	var route: Array = []
	while cursor != tree["start"]:
		route.push_front(cursor)
		cursor = str(tree["previous"][cursor])
	return {"ok":true,"route":route,"distance":int(tree["distance"][target])}

func submit_command(command: Dictionary) -> String:
	if not command.get("army_ids") is Array or not command.get("command_id") is String or not command.get("faction") is String or not command.get("type") is String or not command.get("target", "") is String:
		return "Command schema is invalid."
	var id: String = str(command.get("command_id", ""))
	var faction: String = str(command.get("faction", ""))
	var kind: String = str(command.get("type", ""))
	var selected: Array = command.get("army_ids", [])
	if id.is_empty() or command_ids.has(id):
		return "Command ID is missing or already used."
	if not VALID_ORDERS.has(kind) or selected.is_empty():
		return "Order type or selection is invalid."
	var unique_armies: Dictionary = {}
	for army_id in selected:
		if not army_id is String or unique_armies.has(army_id) or not armies.has(army_id) or str(armies[army_id]["faction"]) != faction or int(armies[army_id]["troops"]) <= 0:
			return "Army is missing, defeated, or belongs to another faction."
		unique_armies[army_id] = true
	var target: String = str(command.get("target", ""))
	if kind == "stance" and target not in Combat.STANCES:
		return "Tactical stance is invalid."
	if kind == "hold" and not target.is_empty():
		return "Hold order must have an empty target."
	if kind in ["move", "retreat", "attack_move"] and not nodes.has(target):
		return "Target node does not exist."
	if kind == "attack" and (not armies.has(target) or str(armies[target]["faction"]) == faction or int(armies[target]["troops"]) <= 0):
		return "Attack target is not a living enemy army."
	if kind == "siege" and (not cities.has(target) or str(cities[target]["owner"]) == faction):
		return "Siege target is not an enemy city."
	command_ids[id] = true
	var accepted: Dictionary={"command_id":id,"faction":faction,"army_ids":selected.duplicate(),"type":kind,"target":target,"issued_tick":tick}
	if command.has("gate_node"):accepted.gate_node=command.gate_node
	command_queue.append(accepted)
	return ""

func set_speed(value: int) -> bool:
	if value not in [1, 2, 4]:
		return false
	speed = value
	return true

func advance_real_time_us(elapsed_us: int, max_ticks: int = 0) -> int:
	## Integer accumulator avoids frame partition rounding; pause consumes no time.
	if paused or elapsed_us < 0:
		return 0
	accumulator_us += elapsed_us * speed
	var processed: int = 0
	while accumulator_us >= TICK_US and (max_ticks <= 0 or processed < max_ticks):
		accumulator_us -= TICK_US
		step()
		processed += 1
	return processed

func step(count: int = 1) -> void:
	## Direct simulation API for tests/offline processing, independent of UI clock.
	for _index in range(maxi(0, count)):
		tick += 1
		if (tick - 1) % AI.DECISION_INTERVAL_TICKS == 0 and winner.is_empty():
			for faction in ai_factions:
				AI.decide(self, str(faction))
		_apply_commands()
		_move_armies()
		_update_supply(tick % SUPPLY_INTERVAL_TICKS == 0)
		_resolve_battles()
		_resolve_sieges()
		_update_production()
		_update_victory()
		# Capture/defeat can change the network this tick without waiting 1 second.
		_update_supply(false)

func _target_node(order: Dictionary) -> String:
	var kind: String = str(order["type"])
	var target: String = str(order["target"])
	if kind in ["move", "retreat", "attack_move"]:
		return target
	if kind == "attack" and armies.has(target) and int(armies[target]["troops"]) > 0:
		return str(armies[target]["node"])
	if kind == "siege" and cities.has(target):
		return str(cities[target]["node"])
	return ""

func _apply_commands() -> void:
	for command in command_queue:
		var ids: Array = command["army_ids"].duplicate()
		ids.sort()
		for id in ids:
			if int(armies[id]["troops"]) <= 0:
				continue
			var army: Dictionary = armies[id]
			if command["type"] == "stance":
				army["stance"] = command["target"]
				_emit("stance_changed", {"army":id,"stance":command["target"]})
				continue
			var order: Dictionary = {"type": command["type"], "target": command["target"]}
			if order["type"] == "hold":
				army["order"] = order
				army["route"] = []
				army["edge_progress"] = 0
				army["siege_state"] = "none"
				continue
			var path: Dictionary = find_path(str(army["node"]), _target_node(order))
			if not path["ok"]:
				_emit("order_failed", {"army": id, "command": command["command_id"], "reason": "No valid route."})
				continue
			army["order"] = order
			army["route"] = path["route"]
			army["edge_progress"] = 0
			army["siege_state"] = "approaching" if order["type"] == "siege" else "none"
	command_queue.clear()

func _move_armies() -> void:
	for id in _sorted_ids(armies):
		var army: Dictionary = armies[id]
		if int(army["troops"]) <= 0 or army["order"]["type"] == "hold":
			continue
		var destination: String = _target_node(army["order"])
		if destination.is_empty() or (army["order"]["type"] == "siege" and cities[army["order"]["target"]]["owner"] == army["faction"]):
			_hold(army)
			continue
		# Replan a moving target only when idle at a node; preserve edge progress.
		if army["route"].is_empty() and destination != str(army["node"]):
			var path: Dictionary = find_path(str(army["node"]), destination)
			if not path["ok"]:
				_emit("order_failed", {"army": id, "reason": "Target has no valid route."})
				_hold(army)
				continue
			army["route"] = path["route"]
		var budget: int = int(army["movement_per_tick"])
		while budget > 0 and not army["route"].is_empty():
			var next: String = str(army["route"][0])
			var edge_length: int = int(nodes[army["node"]]["edges"][next])
			var was_at_node: bool = int(army["edge_progress"]) == 0
			var amount: int = mini(budget, edge_length - int(army["edge_progress"]))
			army["edge_progress"] += amount
			budget -= amount
			if was_at_node and amount > 0:
				_supply_dirty = true
			if int(army["edge_progress"]) == edge_length:
				army["node"] = next
				army["route"].pop_front()
				army["edge_progress"] = 0
				_supply_dirty = true
		if army["route"].is_empty() and army["order"]["type"] in ["move", "retreat"]:
			_hold(army)

func _hold(army: Dictionary) -> void:
	army["order"] = {"type": "hold", "target": ""}
	army["route"] = []
	army["edge_progress"] = 0
	army["siege_state"] = "none"

func _blocked_nodes(faction: String) -> Dictionary:
	var blocked: Dictionary = {}
	for id in _sorted_ids(armies):
		var army: Dictionary = armies[id]
		if army["faction"] != faction and int(army["troops"]) > 0 and int(army["edge_progress"]) == 0:
			blocked[army["node"]] = true
	return blocked

func _city_under_siege(city: Dictionary) -> bool:
	for army in armies.values():
		if int(army["troops"]) > 0 and army["faction"] != city["owner"] and army["node"] == city["node"] and int(army["edge_progress"]) == 0:
			return true
	return false

func _current_supply_signature() -> int:
	# Detect direct state edits made by tests/tools as well as changes through APIs.
	var records: Array = []
	var occupants: Dictionary = _stationary_armies_by_node()
	for city_id in _sorted_ids(cities):
		var city: Dictionary = cities[city_id]
		var besieged: bool = false
		for army_id in occupants.get(city["node"], []):
			if armies[army_id]["faction"] != city["owner"]: besieged = true
		records.append(["c", city_id, city["owner"], city["node"], int(city["food"]) > 0, besieged])
	for army_id in _sorted_ids(armies):
		var army: Dictionary = armies[army_id]
		records.append(["a", army_id, army["faction"], army["node"], int(army["troops"]) > 0, int(army["edge_progress"]) == 0])
	return hash(records)

func _rebuild_supply_cache() -> void:
	_supply_cache.clear()
	performance_metrics["supply_rebuilds"] = int(performance_metrics["supply_rebuilds"]) + 1
	var factions: Dictionary = {}
	for army in armies.values():
		if int(army["troops"]) > 0:
			factions[army["faction"]] = true
	for faction in _sorted_ids(factions):
		var blocked: Dictionary = _blocked_nodes(str(faction))
		var distances: Dictionary = {}
		var sources: Dictionary = {}
		var open = PriorityQueue.new()
		for city_id in _sorted_ids(cities):
			var city: Dictionary = cities[city_id]
			var source_node: String = str(city["node"])
			if city["owner"] != faction or int(city["food"]) <= 0 or blocked.has(source_node):
				continue
			if not distances.has(source_node) or str(city_id) < str(sources[source_node]):
				distances[source_node] = 0
				sources[source_node] = city_id
				open.push(0,source_node,str(city_id))
		while not open.is_empty():
			var entry: Array = open.pop()
			var current: String = str(entry[1])
			if int(entry[0]) != int(distances[current]) or str(entry[2]) != str(sources[current]): continue
			performance_metrics["supply_node_visits"] = int(performance_metrics["supply_node_visits"]) + 1
			if int(distances[current]) >= SUPPLY_RANGE:
				continue
			for neighbor in _sorted_ids(nodes[current]["edges"]):
				if blocked.has(neighbor) or not bool(nodes[neighbor].get("passable", true)):
					continue
				var cost: int = int(distances[current]) + int(nodes[current]["edges"][neighbor])
				if cost > SUPPLY_RANGE:
					continue
				var better: bool = not distances.has(neighbor) or cost < int(distances[neighbor])
				var tied_source: bool = distances.has(neighbor) and cost == int(distances[neighbor]) and str(sources[current]) < str(sources[neighbor])
				if better or tied_source:
					distances[neighbor] = cost
					sources[neighbor] = sources[current]
					open.push(cost,str(neighbor),str(sources[current]))
		_supply_cache[faction] = {"distances": distances, "sources": sources}
	_supply_signature = _current_supply_signature()
	_supply_dirty = false

func _update_supply(consume: bool) -> void:
	var signature: int = _current_supply_signature()
	if signature != _supply_signature:
		_supply_dirty = true
	if _supply_dirty:
		_rebuild_supply_cache()
	for id in _sorted_ids(armies):
		var army: Dictionary = armies[id]
		if int(army["troops"]) <= 0:
			army["supplied"] = false
			continue
		var faction_cache: Dictionary = _supply_cache.get(army["faction"], {})
		var sources: Dictionary = faction_cache.get("sources", {})
		var connected: bool = int(army["edge_progress"]) == 0 and sources.has(army["node"])
		var source_id: String = str(sources.get(army["node"], ""))
		army["supplied"] = connected
		if not consume:
			continue
		army["food"] = maxi(0, int(army["food"]) - 1)
		if connected:
			var replenishment: int = mini(2, mini(int(cities[source_id]["food"]), int(army["food_capacity"]) - int(army["food"])))
			army["food"] += replenishment
			cities[source_id]["food"] -= replenishment
			if int(cities[source_id]["food"]) == 0:
				_supply_dirty = true
			army["morale"] = mini(100, int(army["morale"]) + 1)
		if int(army["food"]) == 0:
			army["morale"] = maxi(0, int(army["morale"]) - 2)
			army["troops"] = maxi(0, int(army["troops"]) - 1)
			if int(army["troops"]) == 0:
				_defeat(army, "starvation")

func _effective_defense(army: Dictionary) -> int:
	var result: int = int(army["defense"])
	for city in cities.values():
		if city["node"] == army["node"] and city["owner"] == army["faction"]:
			result += int(city["defense_bonus"])
	return result

func _stationary_armies_by_node() -> Dictionary:
	var node_armies: Dictionary = {}
	for id in _sorted_ids(armies):
		var army: Dictionary = armies[id]
		if int(army["troops"]) <= 0 or int(army["edge_progress"]) != 0:
			continue
		if not node_armies.has(army["node"]):
			node_armies[army["node"]] = []
		node_armies[army["node"]].append(id)
	return node_armies

func _resolve_battles() -> void:
	# Bucket by node first so the global cost is O(armies), plus only local fights.
	var node_armies: Dictionary = _stationary_armies_by_node()
	var city_bonuses: Dictionary = {}
	for city in cities.values():
		var key: Array = [city["node"],city["owner"]]
		city_bonuses[key] = int(city_bonuses.get(key,0)) + int(city["defense_bonus"])
	var damage: Dictionary = {}
	for node in _sorted_ids(node_armies):
		var ids: Array = node_armies[node]
		var factions: Dictionary = {}
		for id in ids:
			factions[armies[id]["faction"]] = true
		if factions.size() < 2:
			continue
		performance_metrics["battle_nodes"] = int(performance_metrics["battle_nodes"]) + 1
		performance_metrics["battle_armies"] = int(performance_metrics["battle_armies"]) + ids.size()
		for attacker_id in ids:
			var attacker: Dictionary = armies[attacker_id]
			var target_id: String = ""
			if attacker["order"]["type"] == "attack" and attacker["order"]["target"] in ids:
				target_id = str(attacker["order"]["target"])
				if armies[target_id]["faction"] == attacker["faction"]: target_id = ""
			var explicit_target: bool = not target_id.is_empty()
			for candidate_id in ids:
				if explicit_target: break
				var candidate: Dictionary = armies[candidate_id]
				if candidate["faction"] == attacker["faction"]:
					continue
				if target_id.is_empty() or int(candidate["troops"]) < int(armies[target_id]["troops"]) or (int(candidate["troops"]) == int(armies[target_id]["troops"]) and str(candidate_id) < target_id):
					target_id = candidate_id
			if target_id.is_empty():
				continue
			var defender: Dictionary = armies[target_id]
			var terrain: String = str(nodes[node].get("terrain","plain"))
			var bonus: int = int(city_bonuses.get([node,defender["faction"]],0))
			var dealt: int = Combat.casualties(attacker,defender,terrain,bonus)
			damage[target_id] = int(damage.get(target_id, 0)) + dealt
	for id in _sorted_ids(damage):
		var army: Dictionary = armies[id]
		var previous_troops: int = int(army["troops"])
		army["troops"] = maxi(0, int(army["troops"]) - int(damage[id]))
		var morale_loss: int = mini(15,maxi(1,int(damage[id])*100/maxi(1,previous_troops)))
		army["morale"] = maxi(0,int(army["morale"])-morale_loss)
		if int(army["troops"]) == 0:
			_defeat(army, "battle")

func _defeat(army: Dictionary, reason: String) -> void:
	_hold(army)
	army["supplied"] = false
	_supply_dirty = true
	_emit("army_defeated", {"army": army["id"], "reason": reason})

func _resolve_sieges() -> void:
	var occupants: Dictionary = _stationary_armies_by_node()
	for city_id in _sorted_ids(cities):
		var city: Dictionary = cities[city_id]
		var attackers: Array = []
		var factions: Dictionary = {}
		var defenders: bool = false
		for army_id in occupants.get(city["node"], []):
			var army: Dictionary = armies[army_id]
			if int(army["troops"]) <= 0 or army["node"] != city["node"] or int(army["edge_progress"]) != 0:
				continue
			if army["faction"] == city["owner"]:
				defenders = true
			elif army["order"]["type"] == "siege" and army["order"]["target"] == city_id:
				attackers.append(army_id)
				factions[army["faction"]] = true
		if attackers.is_empty():
			continue
		if defenders or factions.size() != 1:
			for army_id in attackers:
				armies[army_id]["siege_state"] = "contested"
			continue
		var damage: int = 0
		for army_id in attackers:
			damage += Combat.siege_damage(armies[army_id])
			armies[army_id]["siege_state"] = "besieging" if int(city["wall_hp"]) > 0 else "breached"
		if int(city["wall_hp"]) > 0:
			city["wall_hp"] = maxi(0, int(city["wall_hp"]) - damage)
		else:
			city["garrison"] = maxi(0, int(city["garrison"]) - damage)
		if int(city["wall_hp"]) == 0 and int(city["garrison"]) == 0:
			var old_owner: String = str(city["owner"])
			city["owner"] = str(armies[attackers[0]]["faction"])
			_supply_dirty = true
			for job in city["production_queue"]:
				_emit("recruitment_cancelled", {"city": city_id, "army": job["army_id"], "reason": "City captured."})
			city["production_queue"] = []
			city["food"] = int(city["food"]) / 2
			_emit("city_captured", {"city": city_id, "old_owner": old_owner, "new_owner": city["owner"]})
			for army_id in attackers:
				_hold(armies[army_id])
				armies[army_id]["siege_state"] = "captured"

func _update_production() -> void:
	for city_id in _sorted_ids(cities):
		var city: Dictionary = cities[city_id]
		if _city_under_siege(city):
			continue
		if tick % SUPPLY_INTERVAL_TICKS == 0:
			var was_empty: bool = int(city["food"]) == 0
			city["food"] += int(city["food_per_interval"])
			if was_empty and int(city["food"]) > 0:
				_supply_dirty = true
		if city["production_queue"].is_empty():
			continue
		var job: Dictionary = city["production_queue"][0]
		job["remaining_ticks"] -= 1
		if int(job["remaining_ticks"]) > 0:
			continue
		city["production_queue"].pop_front()
		var id: String = job["army_id"]
		armies[id] = {"id": id, "faction": job["faction"], "node": city["node"], "troops": int(job["troops"]), "food_capacity": 20, "food": 20, "morale": 100, "movement_per_tick": 2, "attack": 10, "defense": 10, "siege_power": 2, "supplied": false, "order": {"type": "hold", "target": ""}, "route": [], "edge_progress": 0, "siege_state": "none", "unit_type":job["unit_type"], "stance":"balanced"}
		_supply_dirty = true
		_emit("army_recruited", {"city": city_id, "army": id, "faction": job["faction"]})

func _update_victory() -> void:
	if victory_factions.size() < 2 or cities.is_empty():
		return
	var objectives: Array = []
	for city_id in _sorted_ids(cities):
		if cities[city_id]["victory_point"]:
			objectives.append(city_id)
	if objectives.is_empty():
		return
	var owner: String = str(cities[objectives[0]]["owner"])
	for city_id in objectives:
		if cities[city_id]["owner"] != owner:
			winner = ""
			return
	if winner != owner:
		winner = owner
		_emit("victory", {"faction": winner, "condition": "Control every strategic city."})

func _emit(kind: String, details: Dictionary) -> void:
	var event: Dictionary = details.duplicate(true)
	event["type"] = kind
	event["tick"] = tick
	events.append(event)
	if events.size() > MAX_EVENT_HISTORY:
		events.pop_front()

func snapshot() -> Dictionary:
	return {"format_version": FORMAT_VERSION, "nodes": nodes.duplicate(true), "armies": armies.duplicate(true), "cities": cities.duplicate(true), "tick": tick, "accumulator_us": accumulator_us, "speed": speed, "paused": paused, "seed_value": seed_value, "events": events.duplicate(true), "command_ids": command_ids.duplicate(true), "command_queue": command_queue.duplicate(true), "source_provenance": source_provenance, "ai_factions": ai_factions.duplicate(), "victory_factions": victory_factions.duplicate(), "winner": winner}

func save_json() -> String:
	return JSON.stringify(snapshot())

func _integer_data(value):
	# JSON decodes all numbers as float. This integer-only schema restores ints
	# so serialization/replay has the same representation before and after load.
	if value is float:
		return int(value)
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value:
			result[key] = _integer_data(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item in value:
			result.append(_integer_data(item))
		return result
	return value

func _contains_fractional_number(value) -> bool:
	if value is float:
		return not is_finite(value) or value != floor(value)
	if value is Dictionary:
		for item in value.values():
			if _contains_fractional_number(item):
				return true
	if value is Array:
		for item in value:
			if _contains_fractional_number(item):
				return true
	return false

func _validate_saved_order(order, graph: Dictionary, army_table: Dictionary, city_table: Dictionary) -> String:
	if not order is Dictionary or not order.get("type") is String or not order.get("target") is String or not VALID_ORDERS.has(order["type"]):
		return "Save order schema or type is invalid."
	var kind: String = order["type"]
	var target: String = order["target"]
	if kind == "stance" and target not in Combat.STANCES:
		return "Save tactical stance is invalid."
	if kind == "hold" and not target.is_empty():
		return "Hold order must have an empty target."
	if kind in ["move", "retreat", "attack_move"] and not graph.has(target):
		return "Save order node does not exist."
	if kind == "attack" and not army_table.has(target):
		return "Save order army does not exist."
	if kind == "siege" and not city_table.has(target):
		return "Save order city does not exist."
	return ""

func _validate_saved_army(id, army, state: Dictionary) -> String:
	if not id is String or id.is_empty() or not army is Dictionary:
		return "Save army identity or record is invalid."
	for key in ["id", "node", "faction", "siege_state"]:
		if not army.get(key) is String:
			return "Save army string is missing: " + key
	if army["id"] != id or army["faction"].is_empty() or not state["nodes"].has(army["node"]):
		return "Save army identity, faction or node is invalid."
	if army.get("unit_type") not in Combat.UNIT_TYPES or army.get("stance") not in Combat.STANCES:
		return "Save unit type or tactical stance is invalid."
	if army.get("order") is Dictionary and army["order"].get("type") == "stance":
		return "Stance is a queued command, not a persistent movement order."
	for key in ["troops", "food", "food_capacity", "morale", "movement_per_tick", "attack", "defense", "siege_power", "edge_progress"]:
		if not _integer_at_least(army.get(key), 0):
			return "Save army numeric field is missing or invalid: " + key
	if army["food"] > army["food_capacity"] or army["morale"] > 100 or army["movement_per_tick"] < 1 or army["attack"] < 1 or army["siege_power"] < 1:
		return "Save army numeric field is outside its range."
	if not army.get("supplied") is bool or army["siege_state"] not in ["none", "approaching", "besieging", "breached", "contested", "captured"]:
		return "Save army supply/siege state is invalid."
	if not army.get("route") is Array:
		return "Save army route must be an array."
	var error: String = _validate_saved_order(army.get("order"), state["nodes"], state["armies"], state["cities"])
	if not error.is_empty():
		return error
	var cursor: String = army["node"]
	for next in army["route"]:
		if not next is String or not state["nodes"][cursor]["edges"].has(next):
			return "Save route is disconnected."
		cursor = next
	var progress: int = army["edge_progress"]
	if army["route"].is_empty() and progress != 0:
		return "Save edge progress is invalid."
	if not army["route"].is_empty() and progress >= int(state["nodes"][army["node"]]["edges"][army["route"][0]]):
		return "Save edge progress exceeds its edge."
	if army["order"]["type"] == "hold" and (not army["route"].is_empty() or progress != 0):
		return "Held army cannot have a movement route."
	return ""

func _validate_saved_city(id, city, graph: Dictionary) -> String:
	if not id is String or id.is_empty() or not city is Dictionary:
		return "Save city identity or record is invalid."
	for key in ["id", "node", "owner", "kind"]:
		if not city.get(key) is String or city[key].is_empty():
			return "Save city string is missing or invalid: " + key
	if city["id"] != id or not graph.has(city["node"]):
		return "Save city identity or node is invalid."
	if city["kind"] not in VALID_SETTLEMENT_TYPES:
		return "Save settlement type is invalid."
	for key in ["wall_hp", "garrison", "food", "food_per_interval", "defense_bonus"]:
		if not _integer_at_least(city.get(key), 0):
			return "Save city numeric field is missing or invalid: " + key
	if not city.get("recruitment_enabled") is bool or not city.get("victory_point") is bool:
		return "Save settlement boolean field is invalid."
	if not city.get("production_queue") is Array:
		return "Save city production queue is invalid."
	return ""

func _validate_queued_command(command, state: Dictionary) -> String:
	if not command is Dictionary:
		return "Queued command is not a dictionary."
	for key in ["command_id", "faction", "type", "target"]:
		if not command.get(key) is String:
			return "Queued command string is missing: " + key
	if command["command_id"].is_empty() or command["faction"].is_empty() or not state["command_ids"].has(command["command_id"]) or not _integer_at_least(command.get("issued_tick"), 0) or command["issued_tick"] > state["tick"]:
		return "Queued command identity or issued tick is invalid."
	if not command.get("army_ids") is Array or command["army_ids"].is_empty():
		return "Queued command selection is invalid."
	var selected: Dictionary = {}
	for id in command["army_ids"]:
		if not id is String or selected.has(id) or not state["armies"].has(id) or state["armies"][id]["faction"] != command["faction"]:
			return "Queued command army is missing, duplicated or belongs to another faction."
		selected[id] = true
	return _validate_saved_order({"type": command["type"], "target": command["target"]}, state["nodes"], state["armies"], state["cities"])

func load_json(text: String) -> String:
	var parser = JSON.new()
	if parser.parse(text) != OK:
		return "Save file is not valid JSON."
	if _contains_fractional_number(parser.data):
		return "Save schema permits only integer numeric values."
	var parsed = _integer_data(parser.data)
	if not parsed is Dictionary:return "Save root must be a dictionary."
	return _load_base_data(parsed)

func _load_base_data(parsed: Dictionary, trusted_graph: bool=false) -> String:
	if not parsed is Dictionary or int(parsed.get("format_version", -1)) != FORMAT_VERSION:
		return "Save file format is invalid or unsupported."
	for key in ["nodes", "armies", "cities", "command_ids"]:
		if not parsed.get(key) is Dictionary:
			return "Save dictionary is missing: " + key
	for key in ["events", "command_queue", "ai_factions", "victory_factions"]:
		if not parsed.get(key) is Array:
			return "Save array is missing: " + key
	var error: String = ""
	if not trusted_graph:
		error = _validate_graph(parsed["nodes"])
		if not error.is_empty():
			return error
	for key in ["tick", "accumulator_us", "speed", "seed_value"]:
		if not _integer_at_least(parsed.get(key), 0):
			return "Save clock/seed field is missing or invalid: " + key
	if not parsed.get("paused") is bool or not parsed.get("source_provenance") is String:
		return "Save pause/provenance field is invalid."
	if parsed["speed"] not in [1, 2, 4]:
		return "Save clock is invalid."
	for id in parsed["armies"]:
		error = _validate_saved_army(id, parsed["armies"][id], parsed)
		if not error.is_empty():
			return error
	for id in parsed["cities"]:
		error = _validate_saved_city(id, parsed["cities"][id], parsed["nodes"])
		if not error.is_empty():
			return error
	error = _validate_production(parsed["cities"], parsed["armies"])
	if not error.is_empty():
		return error
	for key in ["ai_factions", "victory_factions"]:
		var seen: Dictionary = {}
		for faction in parsed[key]:
			if not faction is String or faction.is_empty() or seen.has(faction):
				return "Save faction list is invalid."
			seen[faction] = true
	if not parsed.get("winner") is String:
		return "Save winner must be a string."
	if not parsed["winner"].is_empty():
		if parsed["victory_factions"].size() < 2 or parsed["cities"].is_empty():
			return "Save victory condition is invalid."
		var objective_count: int = 0
		for city in parsed["cities"].values():
			if city["victory_point"]:
				objective_count += 1
			if city["victory_point"] and city["owner"] != parsed["winner"]:
				return "Save winner does not control every city."
		if objective_count == 0:
			return "Save victory condition has no strategic city."
	for id in parsed["command_ids"]:
		if not id is String or id.is_empty() or not parsed["command_ids"][id] is bool or parsed["command_ids"][id] != true:
			return "Save command ID table is invalid."
	for event in parsed["events"]:
		if not event is Dictionary or not event.get("type") is String or not _integer_at_least(event.get("tick"), 0) or event["tick"] > parsed["tick"]:
			return "Save event record is invalid."
	var queued_ids: Dictionary = {}
	for command in parsed["command_queue"]:
		error = _validate_queued_command(command, parsed)
		if not error.is_empty():
			return error
		if queued_ids.has(command["command_id"]):
			return "Queued command ID is duplicated."
		queued_ids[command["command_id"]] = true
	# Commit only after validation; malformed saves leave the previous state intact.
	nodes = parsed["nodes"]
	armies = parsed["armies"]
	cities = parsed["cities"]
	tick = int(parsed["tick"])
	accumulator_us = int(parsed["accumulator_us"])
	speed = int(parsed["speed"])
	paused = bool(parsed.get("paused", false))
	seed_value = int(parsed.get("seed_value", 1))
	events = parsed["events"]
	command_ids = parsed["command_ids"]
	command_queue = parsed["command_queue"]
	source_provenance = str(parsed.get("source_provenance", "authored"))
	ai_factions = parsed["ai_factions"]
	victory_factions = parsed["victory_factions"]
	winner = parsed["winner"]
	_supply_cache.clear()
	_supply_dirty = true
	_supply_signature = 0
	performance_metrics = {"supply_rebuilds": 0, "supply_node_visits": 0, "battle_nodes": 0, "battle_armies": 0}
	return ""
