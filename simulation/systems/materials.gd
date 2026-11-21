extends RefCounted
## The single recovered-material inventory. Recovery comes only from accounted waste
## mass (collection salvage, sorting reuse, recycling). Construction, upgrades and
## factories use stock first; any shortfall is bought externally and consumed at once,
## so purchased units never enter the inventory. Stock above the cap is sold at tick end.
const A = preload("res://simulation/core/arithmetic.gd")
const Finance = preload("res://simulation/systems/finance.gd")

static func initialize(city: Dictionary, amount: int) -> void:
	city["materials_micro"] = amount
	city["materials"] = {"initial": amount, "refunded": 0, "used": 0, "purchased": 0, "sold": 0}

## Credits needed to cover amount after using stock.
static func purchase_cost(city: Dictionary, b: Dictionary, amount: int) -> int:
	return A.ceil_mul(maxi(0, amount - city.materials_micro), b.economy.buy_price)

## Uses stock first and buys the shortfall. The caller has proven affordability.
static func consume(city: Dictionary, b: Dictionary, amount: int) -> bool:
	var from_stock: int = mini(amount, city.materials_micro)
	var bought: int = amount - from_stock
	if not Finance.debit(city, A.ceil_mul(bought, b.economy.buy_price), "material_purchases"):
		return false
	city.materials_micro -= from_stock
	city.materials.used += from_stock
	city.materials.purchased += bought
	return true

static func recover(city: Dictionary, amount: int) -> void:
	city.materials_micro += amount

static func refund(city: Dictionary, amount: int) -> void:
	city.materials_micro += amount
	city.materials.refunded += amount

static func sell(city: Dictionary, b: Dictionary, amount: int) -> void:
	assert(amount >= 0 and amount <= city.materials_micro)
	city.materials_micro -= amount
	city.materials.sold += amount
	Finance.credit(city, A.mul(amount, b.economy.sell_price), "material_sales")

## Command sell_materials {amount}: sells stocked micro-units at the external price.
static func validate_sale(state: Dictionary, command: Dictionary) -> String:
	var p: Dictionary = command.payload
	if p.size() != 1 or typeof(p.get("amount")) != TYPE_INT or p.amount <= 0:
		return "invalid_payload"
	return "" if p.amount <= state.cities[command.player_id].materials_micro else "insufficient_materials"

static func sell_overflow(city: Dictionary, b: Dictionary) -> void:
	var excess: int = city.materials_micro - b.economy.material_cap
	if excess > 0:
		sell(city, b, excess)

## Stock equals opening stock plus recovered and refunded units minus used and sold.
static func validate(city: Dictionary, recovered: int) -> String:
	var m: Dictionary = city.materials
	for value in m.values():
		if typeof(value) != TYPE_INT or value < 0:
			return "invalid_material_ledger"
	if city.materials_micro < 0 or city.materials_micro != m.initial + recovered + m.refunded - m.used - m.sold:
		return "material_conservation"
	return ""
