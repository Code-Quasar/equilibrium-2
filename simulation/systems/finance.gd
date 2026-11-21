extends RefCounted
## Reservations encumber cash; they do not debit it or create settlement.
const Fixed = preload("res://simulation/core/fixed_point.gd")
const CREDITS = ["municipal_income", "building_income", "refunds", "contract_income", "material_sales"]
const DEBITS = ["municipal_upkeep", "building_upkeep", "construction", "policy", "contract_payments", "landfill"]

static func initialize(city: Dictionary) -> void:
	city["finance"] = {"initial_cash": city.money_micro, "reserved": {}, "totals": {}, "last_tick": []}
	for key in CREDITS + DEBITS:
		city.finance.totals[key] = 0
	city.finance["materials_spent"] = 0

static func available(city: Dictionary) -> int:
	var encumbered: int = 0
	for entry in city.finance.reserved.values():
		encumbered += entry.amount
	return city.money_micro - encumbered

static func reserve(city: Dictionary, id: String, amount: int, tick: int) -> bool:
	if id.is_empty() or amount < 0 or city.finance.reserved.has(id) or available(city) < amount:
		return false
	city.finance.reserved[id] = {"amount": amount, "tick": tick}
	return true

static func consume_reserved(city: Dictionary, id: String, amount: int) -> bool:
	# Settlement adapter only: caller must first prove actual delivered service.
	if amount < 0 or not city.finance.reserved.has(id) or amount > city.finance.reserved[id].amount:
		return false
	city.finance.reserved[id].amount -= amount
	if not debit(city, amount, "contract_payments"):
		city.finance.reserved[id].amount += amount
		return false
	return true

static func release(city: Dictionary, id: String) -> void:
	city.finance.reserved.erase(id)

static func credit(city: Dictionary, amount: int, category: String, source: int = -1) -> void:
	assert(amount >= 0 and category in CREDITS)
	city.money_micro += amount
	city.finance.totals[category] += amount
	city.finance.last_tick.append({"category": category, "amount": amount, "source": source})

static func debit(city: Dictionary, amount: int, category: String, source: int = -1) -> bool:
	assert(amount >= 0 and category in DEBITS)
	if available(city) < amount:
		return false
	city.money_micro -= amount
	city.finance.totals[category] += amount
	city.finance.last_tick.append({"category": category, "amount": -amount, "source": source})
	return true

static func rate(city: Dictionary, key: String, per_minute: int, category: String, is_credit: bool) -> bool:
	var converted: Dictionary = Fixed.per_second(per_minute, city.rate_carries.get(key, 0))
	if is_credit:
		credit(city, converted.amount, category)
	elif not debit(city, converted.amount, category):
		return false
	city.rate_carries[key] = converted.carry
	return true

static func validate(city: Dictionary) -> String:
	var balance: int = city.finance.initial_cash
	for key in CREDITS:
		if typeof(city.finance.totals[key]) != TYPE_INT or city.finance.totals[key] < 0:
			return "financial_ledger_invalid"
		balance += city.finance.totals[key]
	for key in DEBITS:
		if typeof(city.finance.totals[key]) != TYPE_INT or city.finance.totals[key] < 0:
			return "financial_ledger_invalid"
		balance -= city.finance.totals[key]
	for entry in city.finance.reserved.values():
		if typeof(entry.amount) != TYPE_INT or entry.amount < 0:
			return "invalid_reservation"
	if balance != city.money_micro or available(city) < 0:
		return "financial_conservation"
	return ""
