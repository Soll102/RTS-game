extends RefCounted
## Authored deterministic opponent. Uses the same orders and recruitment API as a player.
## No original SAN14 AI code or assets are used.

const DECISION_INTERVAL_TICKS = 20
const MAX_ACTIVE_ARMIES = 3
const RECRUIT_TROOPS = 40

static func _ids(table: Dictionary) -> Array:
	var result: Array = table.keys()
	result.sort()
	return result

static func decide(simulation, faction: String) -> void:
	var owned: Array = []
	var reserved: Dictionary = {}
	# A player/script command already queued this tick takes precedence over AI.
	for command in simulation.command_queue:
		for id in command["army_ids"]:
			reserved[id] = true
	for id in _ids(simulation.armies):
		var army: Dictionary = simulation.armies[id]
		if army["faction"] == faction and int(army["troops"]) > 0:
			owned.append(id)
	for id in owned:
		if reserved.has(id):
			continue
		var army: Dictionary = simulation.armies[id]
		var decision: Dictionary = _order(simulation, army)
		if decision.is_empty() or decision == army["order"]:
			continue
		var command_id: String = "ai-%s-%s-%d" % [faction, id, simulation.tick]
		if simulation.command_ids.has(command_id):
			continue
		simulation.submit_command({"command_id": command_id, "faction": faction, "army_ids": [id], "type": decision["type"], "target": decision["target"]})
	var planned: int = owned.size()
	for city in simulation.cities.values():
		if city["owner"] == faction:
			planned += city["production_queue"].size()
	for city_id in _ids(simulation.cities):
		var city: Dictionary = simulation.cities[city_id]
		if city["owner"] != faction or not city["recruitment_enabled"] or not city["production_queue"].is_empty() or planned >= MAX_ACTIVE_ARMIES or int(city["food"]) < RECRUIT_TROOPS + 20:
			continue
		var army_id: String = "recruit-%s-%s-%d" % [faction, city_id, simulation.tick]
		if simulation.queue_recruitment(faction, city_id, army_id, RECRUIT_TROOPS).is_empty():
			planned += 1

static func _order(simulation, army: Dictionary) -> Dictionary:
	var faction: String = army["faction"]
	# One weighted search per army decision replaces a search per city/enemy.
	var routes: Dictionary = simulation.find_routes_from(str(army["node"]))
	if int(army["food"]) <= 2 or int(army["morale"]) <= 30:
		var home: String = ""
		var best: int = 2147483647
		for city_id in _ids(simulation.cities):
			var city: Dictionary = simulation.cities[city_id]
			if city["owner"] != faction or int(city["food"]) <= 0 or simulation._city_under_siege(city):
				continue
			var path: Dictionary = simulation.route_from_tree(routes, str(city["node"]))
			if path["ok"] and int(path["distance"]) < best:
				best = int(path["distance"])
				home = str(city["node"])
		if home.is_empty():
			return {"type": "hold", "target": ""}
		if home == army["node"] and int(army["edge_progress"]) == 0:
			return {"type": "hold", "target": ""}
		return {"type": "retreat", "target": home}
	# Preserve active travel to avoid repeatedly resetting edge progress.
	if army["order"]["type"] != "hold":
		return {}
	var best_target: String = ""
	var best_distance: int = 2147483647
	for id in _ids(simulation.armies):
		var enemy: Dictionary = simulation.armies[id]
		if enemy["faction"] == faction or int(enemy["troops"]) <= 0 or int(enemy["troops"]) > int(army["troops"]):
			continue
		var path: Dictionary = simulation.route_from_tree(routes, str(enemy["node"]))
		if path["ok"] and int(path["distance"]) <= 20 and int(path["distance"]) < best_distance:
			best_target = id
			best_distance = int(path["distance"])
	if not best_target.is_empty():
		return {"type": "attack", "target": best_target}
	for id in _ids(simulation.cities):
		var city: Dictionary = simulation.cities[id]
		if city["owner"] == faction:
			continue
		var path: Dictionary = simulation.route_from_tree(routes, str(city["node"]))
		if path["ok"] and int(path["distance"]) < best_distance:
			best_target = id
			best_distance = int(path["distance"])
	if not best_target.is_empty():
		return {"type": "siege", "target": best_target}
	return {}
