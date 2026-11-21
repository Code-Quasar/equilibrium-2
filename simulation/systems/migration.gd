extends RefCounted
const A = preload("res://simulation/core/arithmetic.gd")
const Q: int = 1000000000000

# exp(-gap/20), positive Taylor of exp(gap/320), reciprocal, four squarings.
static func weight(gap_micro: int) -> int:
	var term: int = Q
	var sum: int = Q
	for n in range(1, 21):
		term = A.mul(term, gap_micro, 320000000 * n)
		sum += term
	var result: int = A.mul(Q, Q, sum)
	for i in range(4): result = A.mul(result, result, Q)
	return result

static func rotation(match_id: String, seed_value: int, pulse: int) -> int:
	var hash_value: int = posmod(seed_value, 4)
	for byte in match_id.to_utf8_buffer(): hash_value = (hash_value * 31 + byte) % 4
	return (hash_value + pulse) % 4

# Capped proportional water filling, followed by largest remainders.
static func allocate(total: int, gaps: Array, caps: Array, rotate: int) -> Array:
	var result: Array = [0,0,0,0]
	var left: int = mini(total, A.total(caps))
	var active: Array = []
	for i in range(4):
		if gaps[i] > 0 and caps[i] > 0: active.append(i)
	while left > 0 and not active.is_empty():
		var sum: int = 0
		for i in active: sum += gaps[i]
		var bound: Array = []
		for i in active:
			if A.mul(left, gaps[i], sum) >= caps[i]: bound.append(i)
		if not bound.is_empty():
			for i in bound:
				result[i] = caps[i]
				left -= caps[i]
				active.erase(i)
			continue
		var remainders: Array = []
		var used: int = 0
		for i in active:
			var p: Dictionary = A.product(left, gaps[i], sum)
			result[i] = p.q
			used += p.q
			remainders.append({"i": i, "r": p.r})
		remainders.sort_custom(func(a,b): return a.r > b.r if a.r != b.r else posmod(a.i-rotate,4) < posmod(b.i-rotate,4))
		for j in range(left-used): result[remainders[j].i] += 1
		break
	return result

static func pulse(state: Dictionary, rules: Dictionary) -> Dictionary:
	var scores: Array = []
	var before: Array = []
	var weights: Array = []
	for c in state.cities:
		scores.append(c.satisfaction_micro)
		before.append(c.population)
	var maximum: int = scores.max()
	for s in scores: weights.append(weight(maximum-s))
	var denominator: int = A.total(weights)
	var targets: Array = []
	var offers: Array = []
	var demands: Array = []
	var send_caps: Array = []
	var receive_caps: Array = []
	var housing: Array = []
	for i in range(4):
		var c: Dictionary = state.cities[i]
		var target: int = 500*A.S + A.mul(2000*A.S, weights[i], denominator)
		targets.append(target)
		offers.append(maxi(0, c.population*A.S-target))
		demands.append(maxi(0, mini(target-c.population*A.S, (c.capacity.housing-c.population)*A.S)))
		send_caps.append(mini(rules.sender_cap, A.divi(offers[i], A.S)))
		receive_caps.append(mini(rules.receiver_cap, A.divi(demands[i], A.S)))
		housing.append(c.capacity.housing)
	var count: int = mini(rules.regional_cap, mini(A.total(send_caps), A.total(receive_caps)))
	var turn: int = rotation(state.match_id, state.seed, state.transfer_ledger.size())
	var sent: Array = allocate(count, offers, send_caps, turn)
	var received: Array = allocate(count, demands, receive_caps, turn)
	var remaining: Array = received.duplicate()
	var matrix: Array = [[0,0,0,0],[0,0,0,0],[0,0,0,0],[0,0,0,0]]
	for offset in range(4):
		var i: int = (turn+offset)%4
		var available: int = sent[i]
		for other in range(4):
			var j: int = (turn+other)%4
			if i == j: continue
			var amount: int = mini(available, remaining[j])
			matrix[i][j] = amount
			available -= amount
			remaining[j] -= amount
	var after: Array = []
	for i in range(4):
		state.cities[i].population += received[i]-sent[i]
		after.append(state.cities[i].population)
	return {"time": state.tick+1, "satisfaction_micro": scores, "weights_q12": weights,
		"target_micro": targets, "target_numerators": weights.map(func(w): return 2000*w), "target_denominator": denominator,
		"offers_micro": offers, "demands_micro": demands, "sender_quotas": send_caps, "receiver_quotas": receive_caps,
		"sent": sent, "received": received, "housing": housing, "matrix": matrix,
		"before": before, "after": after, "total": A.total(after), "transferred": count, "rotation": turn}

static func ranking(state: Dictionary) -> Array:
	var cities: Array = state.cities.duplicate()
	cities.sort_custom(func(a,b):
		for key in ["population", "satisfaction_micro", "environment_micro", "money_micro"]:
			if a[key] != b[key]: return a[key] > b[key]
		return a.city_id < b.city_id)
	var result: Array = []
	var previous: Array = []
	var rank_value: int = 0
	for c in cities:
		var score: Array = [c.population,c.satisfaction_micro,c.environment_micro,c.money_micro]
		if score != previous: rank_value = result.size()+1
		result.append({"rank": rank_value, "city_id": c.city_id, "population": c.population,
			"satisfaction_micro": c.satisfaction_micro, "environment_micro": c.environment_micro,
			"money_micro": c.money_micro, "development_micro": c.development_micro})
		previous = score
	return result
