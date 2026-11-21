extends "res://tests/support/harness.gd"
## Fixed-price service contracts with escrow and payment for real delivery only.
const Market = preload("res://simulation/systems/market.gd")
const Waste = preload("res://simulation/systems/waste.gd")
const INDUSTRIAL = 0
const CIRCULAR = 1
const ENERGY = 2
const INVESTMENT = 3

func _initialize() -> void:
	electricity()
	limits()
	treatment()
	finish("Market")

func offer_id(m: RefCounted, seller: int) -> int:
	return m._state.market.offers.filter(func(o): return o.seller == seller)[-1].id

func contract(m: RefCounted, id: int) -> Dictionary:
	return Market.find(m._state.market.contracts, id)

func electricity() -> void:
	var m = fixture()
	eq(act(m, ENERGY, "publish_offer", {"type": "electricity", "rate": 10 * U}), "insufficient_seller_capacity", "no spare capacity is demonstrated before the first tick")
	eq(act(m, ENERGY, "publish_offer", {"type": "electricity", "rate": 41 * U}), "invalid_rate", "electricity offers are capped at 40 E")
	eq(act(m, ENERGY, "publish_offer", {"type": "electricity", "rate": 10 * U}), "applied", "a city with 112 E spare offers 10 E")
	var offer: int = offer_id(m, ENERGY)
	eq(m._state.market.offers[0].price_micro, 220000, "electricity sells at 0.22 per E-minute")
	var buyer: Dictionary = city(m, INVESTMENT)
	set_cash(buyer, 1000 * U)
	for i in range(3):
		place(m, buyer, "factory")
	eq(act(m, INVESTMENT, "accept_offer", {"id": offer, "duration": 120}), "applied", "accept for 120 s")
	var k: Dictionary = m._state.market.contracts[0]
	eq([k.escrow_micro, k.start_tick, k.end_tick], [4400000, 3, 123], "escrow holds 10 E x 2 minutes x 0.22")
	eq(m._state.market.offers.size(), 0, "an accepted offer leaves the board")
	var held: int = Finance.reserved(city(m, INVESTMENT), Market.escrow_id(k))
	eq(held, k.escrow_micro - k.paid_micro, "escrow holds the maximum fee less what is already paid")
	eq(Finance.available(city(m, INVESTMENT)), city(m, INVESTMENT).money_micro - held, "escrow is held out of available cash")
	eq([city(m, INVESTMENT).power.imports_micro_E, city(m, ENERGY).power.exports_micro_E], [10 * U, 10 * U], "power is delivered the tick it is accepted")
	advance(m, 59)
	k = contract(m, k.id)
	eq([k.delivered_micro, k.paid_micro], [600 * U, 2200000], "one minute of 10 E costs 2.2")
	eq(city(m, ENERGY).finance.totals.contract_income, city(m, INVESTMENT).finance.totals.contract_payments, "the seller receives exactly what the buyer pays")
	eq(Finance.reserved(city(m, INVESTMENT), Market.escrow_id(k)), 2200000, "escrow shrinks by each payment")
	advance(m, 60)
	k = contract(m, k.id)
	eq([k.status, k.paid_micro, Finance.reserved(city(m, INVESTMENT), Market.escrow_id(k))], ["expired", 4400000, 0], "expiry releases the escrow")
	check(not city(m, INVESTMENT).finance.reserved.has(Market.escrow_id(k)), "no escrow survives a closed contract")
	var idle = fixture()
	advance(idle, 1)
	eq(act(idle, ENERGY, "publish_offer", {"type": "electricity", "rate": 10 * U}), "applied", "offer to a buyer without a deficit")
	eq(act(idle, INVESTMENT, "accept_offer", {"id": offer_id(idle, ENERGY)}), "applied", "default duration")
	k = idle._state.market.contracts[0]
	advance(idle, 5)
	k = contract(idle, k.id)
	eq([k.end_tick - k.start_tick, k.delivered_micro, k.paid_micro], [120, 0, 0], "no buyer load, nothing delivered or billed")
	eq(act(idle, ENERGY, "cancel_contract", {"id": k.id}), "applied", "the seller may cancel")
	eq([contract(idle, k.id).status, Finance.reserved(city(idle, INVESTMENT), Market.escrow_id(k))], ["cancelled", 0], "cancellation releases escrow")

func limits() -> void:
	var m = fixture()
	advance(m, 1)
	for seat in range(4):
		set_cash(city(m, seat), 1000 * U)
	for i in range(3):
		eq(act(m, ENERGY, "publish_offer", {"type": "electricity", "rate": 5 * U}), "applied", "offer %d" % i)
	eq(act(m, ENERGY, "publish_offer", {"type": "electricity", "rate": 5 * U}), "offer_limit", "three open offers per city")
	var offers: Array = m._state.market.offers.map(func(o): return o.id)
	eq(act(m, ENERGY, "accept_offer", {"id": offers[0]}), "self_contract", "no contract with yourself")
	eq(act(m, INVESTMENT, "accept_offer", {"id": offers[0], "duration": 59}), "invalid_duration", "at least 60 s")
	eq(act(m, INVESTMENT, "accept_offer", {"id": offers[0], "duration": 301}), "invalid_duration", "at most 300 s")
	eq(act(m, INDUSTRIAL, "withdraw_offer", {"id": offers[0]}), "offer_not_owned", "only the seller withdraws")
	eq(act(m, INVESTMENT, "accept_offer", {"id": offers[0]}), "applied", "first contract")
	eq(act(m, INVESTMENT, "accept_offer", {"id": offers[1]}), "duplicate_contract", "one live contract per buyer, seller and service")
	eq(act(m, INDUSTRIAL, "cancel_contract", {"id": m._state.market.contracts[0].id}), "contract_not_owned", "outsiders cannot cancel")
	eq(act(m, ENERGY, "withdraw_offer", {"id": offers[2]}), "applied", "the seller withdraws an offer")
	eq(act(m, ENERGY, "publish_offer", {"type": "electricity", "rate": 5 * U}), "applied", "a withdrawn offer frees a slot")
	var poor = fixture()
	advance(poor, 1)
	eq(act(poor, ENERGY, "publish_offer", {"type": "electricity", "rate": 40 * U}), "applied", "large offer")
	set_cash(city(poor, INVESTMENT), 1 * U)
	eq(act(poor, INVESTMENT, "accept_offer", {"id": offer_id(poor, ENERGY), "duration": 300}), "insufficient_funds", "the full fee must fit in escrow")
	poor._state.tick = 1150
	eq(act(poor, CIRCULAR, "accept_offer", {"id": offer_id(poor, ENERGY), "duration": 60}), "not_enough_time", "a contract must fit before the match ends")
	var gate = fixture()
	advance(gate, 1)
	eq(act(gate, ENERGY, "publish_offer", {"type": "electricity", "rate": 5 * U}), "applied", "offer")
	eq(act(gate, INVESTMENT, "accept_offer", {"id": offer_id(gate, ENERGY)}), "applied", "buy power")
	eq(gate.preview(INVESTMENT, "construct", {"building_type": "recycling_center", "size": "S"}), "requires_collection_center", "contracts never unlock construction")

func treatment() -> void:
	var m = fixture()
	set_cash(city(m, CIRCULAR), 2000 * U)
	set_cash(city(m, INVESTMENT), 2000 * U)
	place(m, city(m, CIRCULAR), "recycling_center")
	place(m, city(m, INVESTMENT), "collection_center")
	place(m, city(m, INVESTMENT), "sorting_center")
	advance(m, 5)
	eq(act(m, CIRCULAR, "publish_offer", {"type": "recyclable", "rate": 5 * U}), "applied", "a city with spare recycling offers treatment")
	eq(m._state.market.offers[0].price_micro, 750000, "recyclable treatment costs 0.75 per unit")
	eq(act(m, INVESTMENT, "accept_offer", {"id": offer_id(m, CIRCULAR)}), "applied", "a city with sorted stock but no recycler buys treatment")
	advance(m, 60)
	var k: Dictionary = m._state.market.contracts[0]
	var buyer: Dictionary = city(m, INVESTMENT)
	var seller: Dictionary = city(m, CIRCULAR)
	check(k.delivered_micro > 0 and k.delivered_micro <= A.mul(5 * U, 61, 60), "delivery never exceeds the reserved rate")
	eq([buyer.waste.totals.exported, seller.waste.totals.imported], [k.delivered_micro, k.delivered_micro], "exported mass equals imported mass")
	eq(k.paid_micro, A.ceil_mul(k.delivered_micro, 750000), "payment is exactly delivered units x 0.75, rounded up")
	check(seller.waste.totals.recycled >= k.delivered_micro, "the seller recycles imports with its own plant")
	eq(m.waste.validate_city(buyer) + m.waste.validate_city(seller), "", "both cities conserve mass")
	eq(of_type(buyer, "recycling_center").size(), 0, "the buyer gained no plant")
