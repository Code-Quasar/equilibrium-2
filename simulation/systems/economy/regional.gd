extends "res://simulation/systems/economy/local.gd"
const Market = preload("res://simulation/systems/market.gd")
var market: RefCounted
func _init(config: Dictionary,buildings: RefCounted) -> void:
	super(config,buildings)
	market=Market.new(balance,catalogue,waste)
func power_dependency(state: Dictionary,_ctx: Dictionary,_rng: RefCounted) -> String:
	return market.power(state)
