extends RefCounted
## City cash ledger. Every movement names a category, and the balance always equals
## the opening cash plus credits minus debits. Reservations (contract escrow)
## encumber cash without moving it; the treasury and available cash never go negative.
const CREDITS = ["taxes", "building_income", "contract_income", "material_sales", "refunds"]
const DEBITS = ["municipal_upkeep", "building_upkeep", "standby_upkeep", "construction",
	"material_purchases", "emissions_levy", "landfill_fees", "contract_payments"]

static func initialize(city: Dictionary, cash: int) -> void:
	city["money_micro"] = cash
	var totals: Dictionary = {}
	for key in CREDITS + DEBITS:
		totals[key] = 0
	city["finance"] = {"initial": cash, "totals": totals, "tick": totals.duplicate(), "reserved": {},
		"unpaid_municipal_upkeep": 0}

static func begin_tick(city: Dictionary) -> void:
	for key in city.finance.tick:
		city.finance.tick[key] = 0

static func available(city: Dictionary) -> int:
	var encumbered: int = 0
	for amount in city.finance.reserved.values():
		encumbered += amount
	return city.money_micro - encumbered

static func credit(city: Dictionary, amount: int, category: String) -> void:
	assert(amount >= 0 and category in CREDITS)
	city.money_micro += amount
	city.finance.totals[category] += amount
	city.finance.tick[category] += amount

static func debit(city: Dictionary, amount: int, category: String) -> bool:
	assert(amount >= 0 and category in DEBITS)
	if available(city) < amount:
		return false
	_take(city, amount, category)
	return true

static func reserve(city: Dictionary, id: String, amount: int) -> bool:
	if amount < 0 or city.finance.reserved.has(id) or available(city) < amount:
		return false
	city.finance.reserved[id] = amount
	return true

static func reserved(city: Dictionary, id: String) -> int:
	return city.finance.reserved.get(id, 0)

## Pays from an escrow reservation; the amount must already be held.
static func pay_reserved(city: Dictionary, id: String, amount: int, category: String) -> bool:
	assert(category in DEBITS)
	if amount < 0 or reserved(city, id) < amount:
		return false
	city.finance.reserved[id] -= amount
	_take(city, amount, category)
	return true

static func release(city: Dictionary, id: String) -> void:
	city.finance.reserved.erase(id)

static func _take(city: Dictionary, amount: int, category: String) -> void:
	city.money_micro -= amount
	city.finance.totals[category] += amount
	city.finance.tick[category] += amount

static func validate(city: Dictionary) -> String:
	var balance: int = city.finance.initial
	for key in CREDITS:
		balance += city.finance.totals[key]
	for key in DEBITS:
		balance -= city.finance.totals[key]
	for key in city.finance.totals:
		if typeof(city.finance.totals[key]) != TYPE_INT or city.finance.totals[key] < 0:
			return "invalid_financial_ledger"
	for amount in city.finance.reserved.values():
		if typeof(amount) != TYPE_INT or amount < 0:
			return "invalid_reservation"
	if balance != city.money_micro or city.money_micro < 0 or available(city) < 0:
		return "financial_conservation"
	return ""
