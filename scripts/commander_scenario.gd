extends RefCounted
const BaseScenario=preload("res://scripts/v8_scenario.gd")
const Simulation=preload("res://scripts/battle_campaign.gd")
const FACTIONS=["wei","shu","wu"]

static func create(player_faction: String="wei") -> RefCounted:
	if player_faction not in FACTIONS:return null
	var base: RefCounted=BaseScenario.create(player_faction)
	if base==null:return null
	base.seed_value=20261101
	return base
