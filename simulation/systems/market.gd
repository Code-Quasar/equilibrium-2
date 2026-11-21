extends RefCounted
## Inter-city service contracts for electricity, recyclable treatment and organic
## treatment at fixed B2.1 prices. A seller publishes spare capacity; a buyer accepts
## for 60-300 s and pre-authorizes the maximum fee in escrow. Each second only real
## delivery is paid from escrow, and the rest is released at expiry or cancellation.
## Imported power serves the buyer's own load; imported waste is treated at once with
## the seller's plants and never stored, so nothing can be re-exported.
const A = preload("res://simulation/core/arithmetic.gd")
const Buildings = preload("res://simulation/systems/buildings.gd")
const Finance = preload("res://simulation/systems/finance.gd")
const Operations = preload("res://simulation/systems/operations.gd")
const Waste = preload("res://simulation/systems/waste.gd")
const COMMANDS = ["publish_offer", "withdraw_offer", "accept_offer", "cancel_contract"]
const SERVICES = ["electricity", "recyclable", "organic"]
var b: Dictionary
var waste: RefCounted

func _init(config: Dictionary, waste_system: RefCounted) -> void:
	b = config
	waste = waste_system

static func initialize(state: Dictionary) -> void:
	state["market"] = {"next_id": 0, "offers": [], "contracts": []}

static func find(items: Array, id: int) -> Dictionary:
	for item in items:
		if item.id == id:
			return item
	return {}

static func live(contract: Dictionary, tick: int) -> bool:
	return contract.status == "active" and tick >= contract.start_tick and tick < contract.end_tick

static func escrow_id(contract: Dictionary) -> String:
	return "contract:%d" % contract.id

## Fee denominator: electricity is priced per E-minute and delivered per second.
static func denominator(service: String) -> int:
	return 60 * A.S if service == "electricity" else A.S

func committed(state: Dictionary, seller: int, service: String) -> int:
	var amount: int = 0
	for k in state.market.contracts:
		if live(k, state.tick) and k.seller == seller and k.type == service:
			amount += k.rate_micro
	return amount

## Capacity a seller demonstrated last second beyond its own needs and existing contracts.
func spare(state: Dictionary, seller: int, service: String) -> int:
	var city: Dictionary = state.cities[seller]
	var free: int
	if service == "electricity":
		free = Operations.own_generation(city) - Operations.domestic_request(city)
	else:
		var t: Dictionary = city.waste.tick
		free = city.processing.recyclable_capacity_micro - 60 * (t.captured_recyclable - t.sorting_reuse) if service == "recyclable" \
			else city.processing.organic_capacity_micro - 60 * t.captured_organic
	return maxi(0, free - committed(state, seller, service))

func max_fee(rate: int, duration: int, service: String) -> int:
	return A.ceil_mul(rate * duration, b.market.prices[service], 60 * A.S)

func validate(state: Dictionary, command: Dictionary) -> String:
	var p: Dictionary = command.payload
	var owner: int = command.player_id
	match command.command_type:
		"publish_offer":
			if p.size() != 2 or typeof(p.get("type")) != TYPE_STRING or p.type not in SERVICES or typeof(p.get("rate")) != TYPE_INT:
				return "invalid_payload"
			if p.rate <= 0 or (p.type == "electricity" and p.rate > b.market.electricity_max):
				return "invalid_rate"
			if state.market.offers.filter(func(o): return o.seller == owner).size() >= b.market.max_offers:
				return "offer_limit"
			return "" if spare(state, owner, p.type) >= p.rate else "insufficient_seller_capacity"
		"withdraw_offer":
			if p.size() != 1 or typeof(p.get("id")) != TYPE_INT:
				return "invalid_payload"
			var offer: Dictionary = find(state.market.offers, p.id)
			if offer.is_empty():
				return "offer_unavailable"
			return "" if offer.seller == owner else "offer_not_owned"
		"accept_offer":
			if typeof(p.get("id")) != TYPE_INT or p.size() > (2 if p.has("duration") else 1):
				return "invalid_payload"
			var duration: Variant = p.get("duration", b.market.default_duration)
			if typeof(duration) != TYPE_INT or duration < b.market.min_duration or duration > b.market.max_duration:
				return "invalid_duration"
			var offer: Dictionary = find(state.market.offers, p.id)
			if offer.is_empty():
				return "offer_unavailable"
			if offer.seller == owner:
				return "self_contract"
			if state.tick + duration > b.duration:
				return "not_enough_time"
			var active: Array = state.market.contracts.filter(func(k): return k.status == "active" and k.buyer == owner)
			if active.size() >= b.market.max_contracts:
				return "contract_limit"
			if active.any(func(k): return k.seller == offer.seller and k.type == offer.type):
				return "duplicate_contract"
			if spare(state, offer.seller, offer.type) < offer.rate_micro:
				return "insufficient_seller_capacity"
			return "" if Finance.available(state.cities[owner]) >= max_fee(offer.rate_micro, duration, offer.type) else "insufficient_funds"
		"cancel_contract":
			if p.size() != 1 or typeof(p.get("id")) != TYPE_INT:
				return "invalid_payload"
			var contract: Dictionary = find(state.market.contracts, p.id)
			if contract.is_empty() or contract.status != "active":
				return "contract_unavailable"
			return "" if owner in [contract.buyer, contract.seller] else "contract_not_owned"
	return "unsupported_command"

func execute(state: Dictionary, command: Dictionary) -> String:
	var error: String = validate(state, command)
	if not error.is_empty():
		return error
	var p: Dictionary = command.payload
	var owner: int = command.player_id
	match command.command_type:
		"publish_offer":
			state.market.offers.append({"id": _next_id(state), "seller": owner, "type": p.type,
				"rate_micro": p.rate, "price_micro": b.market.prices[p.type], "created_tick": state.tick})
		"withdraw_offer":
			state.market.offers.erase(find(state.market.offers, p.id))
		"accept_offer":
			var offer: Dictionary = find(state.market.offers, p.id)
			var duration: int = p.get("duration", b.market.default_duration)
			var contract: Dictionary = {"id": _next_id(state), "buyer": owner, "seller": offer.seller,
				"type": offer.type, "rate_micro": offer.rate_micro, "price_micro": offer.price_micro,
				"start_tick": state.tick, "end_tick": state.tick + duration, "status": "active",
				"escrow_micro": max_fee(offer.rate_micro, duration, offer.type),
				"delivered_micro": 0, "paid_micro": 0, "fee_remainder": 0, "last_delivery_micro": 0,
				"closed_tick": -1, "carries": {}}
			if not Finance.reserve(state.cities[owner], escrow_id(contract), contract.escrow_micro):
				return "insufficient_funds"
			state.market.offers.erase(offer)
			state.market.contracts.append(contract)
		"cancel_contract":
			_close(state, find(state.market.contracts, p.id), "cancelled", state.tick)
	return ""

func _next_id(state: Dictionary) -> int:
	state.market.next_id += 1
	return state.market.next_id - 1

## Largest quantity whose rounded-up charge fits the remaining escrow.
func _affordable(state: Dictionary, k: Dictionary) -> int:
	var den: int = denominator(k.type)
	var escrow: Dictionary = A.product(Finance.reserved(state.cities[k.buyer], escrow_id(k)), den, k.price_micro)
	return escrow.q + A.divi(escrow.r + k.fee_remainder, k.price_micro)

## Pays exactly quantity * price / denominator over the contract's life; each
## charge rounds up and the prepaid remainder is carried to the next delivery.
func _pay(state: Dictionary, k: Dictionary, quantity: int) -> String:
	k.last_delivery_micro = quantity
	if quantity == 0:
		return ""
	var den: int = denominator(k.type)
	var owed: int = A.product(quantity, k.price_micro, 1).q - k.fee_remainder
	var charge: int = A.ceil_div(maxi(0, owed), den)
	if not Finance.pay_reserved(state.cities[k.buyer], escrow_id(k), charge, "contract_payments"):
		return "contract_payment_failed"
	Finance.credit(state.cities[k.seller], charge, "contract_income")
	k.fee_remainder = charge * den - owed
	k.paid_micro += charge
	k.delivered_micro += quantity
	return ""

static func _ordered(state: Dictionary, service: String) -> Array:
	var result: Array = state.market.contracts.filter(func(k): return live(k, state.tick) and k.type == service)
	result.sort_custom(func(x, y): return x.id < y.id)
	return result

## Phase: real power deliveries, after the seller's municipal demand and before its
## optional loads, limited to the buyer's actual deficit.
func settle_electricity(state: Dictionary, _ctx: Dictionary) -> String:
	for k in _ordered(state, "electricity"):
		var seller: Dictionary = state.cities[k.seller]
		var buyer: Dictionary = state.cities[k.buyer]
		var available: int = Operations.own_generation(seller) - seller.power.municipal_requested_micro_E - seller.power.exports_micro_E
		var deficit: int = Operations.domestic_request(buyer) - Operations.own_generation(buyer) - buyer.power.imports_micro_E
		var quantity: int = mini(mini(k.rate_micro, maxi(0, available)), mini(maxi(0, deficit), _affordable(state, k)))
		var error: String = _pay(state, k, quantity)
		if not error.is_empty():
			return error
		seller.power.exports_micro_E += quantity
		seller.power.unused_micro_E -= quantity
		buyer.power.imports_micro_E += quantity
		buyer.power.unused_micro_E += quantity
	return ""

## Phase: the buyer exports only sorted stock beyond its own treatment capacity this
## second; the seller treats it before its own stock within its throughput.
func settle_waste(state: Dictionary, _ctx: Dictionary) -> String:
	for service in ["recyclable", "organic"]:
		var stream: int = Waste.R if service == "recyclable" else Waste.O
		for k in _ordered(state, service):
			var seller: Dictionary = state.cities[k.seller]
			var buyer: Dictionary = state.cities[k.buyer]
			var surplus: int = maxi(0, buyer.sorted_micro[stream] - Waste.remaining_budget(buyer, stream))
			var allowance: int = A.per_tick(k.carries, "rate", k.rate_micro)
			var quantity: int = mini(mini(allowance, surplus), mini(Waste.remaining_budget(seller, stream), _affordable(state, k)))
			var error: String = _pay(state, k, quantity)
			if not error.is_empty():
				return error
			if quantity == 0:
				continue
			buyer.sorted_micro[stream] -= quantity
			Waste.flow(buyer, "exported", quantity)
			Waste.flow(seller, "imported", quantity)
			if waste.treat(seller, stream, quantity) != quantity:
				return "unprocessed_import"
	return ""

## Phase: contracts whose interval ends with this tick close and release escrow.
func expire(state: Dictionary, ctx: Dictionary) -> String:
	for k in state.market.contracts:
		if k.status == "active" and ctx.end_tick >= k.end_tick:
			_close(state, k, "expired", ctx.end_tick)
	return ""

func _close(state: Dictionary, k: Dictionary, status: String, tick: int) -> void:
	k.status = status
	k.closed_tick = tick
	Finance.release(state.cities[k.buyer], escrow_id(k))

func validate_state(state: Dictionary) -> String:
	var income: int = 0
	var payments: int = 0
	var imported: int = 0
	var exported: int = 0
	var power_in: int = 0
	var power_out: int = 0
	for c in state.cities:
		income += c.finance.totals.contract_income
		payments += c.finance.totals.contract_payments
		imported += c.waste.totals.imported
		exported += c.waste.totals.exported
		power_in += c.power.imports_micro_E
		power_out += c.power.exports_micro_E
		if state.market.offers.filter(func(o): return o.seller == c.city_id).size() > b.market.max_offers:
			return "offer_count"
		if state.market.contracts.filter(func(k): return k.status == "active" and k.buyer == c.city_id).size() > b.market.max_contracts:
			return "contract_count"
	if income != payments:
		return "trade_cash_conservation"
	if imported != exported or power_in != power_out:
		return "trade_mass_conservation"
	var ids: Array = []
	var pairs: Array = []
	for k in state.market.contracts:
		if k.id in ids or k.buyer == k.seller or k.rate_micro <= 0:
			return "contract_identity"
		ids.append(k.id)
		var den: int = denominator(k.type)
		if k.fee_remainder < 0 or k.fee_remainder >= den or k.paid_micro * den != k.delivered_micro * k.price_micro + k.fee_remainder:
			return "usage_charge_conservation"
		var held: int = Finance.reserved(state.cities[k.buyer], escrow_id(k))
		if k.status == "active":
			var pair: String = "%d:%d:%s" % [k.buyer, k.seller, k.type]
			if pair in pairs or held != k.escrow_micro - k.paid_micro:
				return "escrow_state"
			pairs.append(pair)
		elif state.cities[k.buyer].finance.reserved.has(escrow_id(k)):
			return "closed_contract_escrow"
	return ""
