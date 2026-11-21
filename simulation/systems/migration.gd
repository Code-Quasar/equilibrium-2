extends RefCounted
## Pairwise migration from a frozen post-tick snapshot. Every ordered pair whose
## Satisfaction gap exceeds the threshold may move floor(rate * (gap - threshold))
## residents from the lower to the higher city. Pairs are served by decreasing gap,
## then destination, then source, within per-city send/receive limits, the sender
## floor and the receiver's free housing. Residents are never created or destroyed.
const A = preload("res://simulation/core/arithmetic.gd")

static func due(m: Dictionary, end_tick: int) -> bool:
	return end_tick >= m.first and end_tick <= m.last and (end_tick - m.first) % m.interval == 0

static func pulse(state: Dictionary, m: Dictionary, time: int) -> Dictionary:
	var scores: Array = state.cities.map(func(c): return c.satisfaction_micro)
	var before: Array = state.cities.map(func(c): return c.population)
	var housing: Array = state.cities.map(func(c): return c.capacity.housing)
	var pairs: Array = []
	for source in range(4):
		for target in range(4):
			var gap: int = scores[target] - scores[source]
			if source != target and gap > m.min_gap:
				pairs.append({"source": source, "target": target, "gap": gap})
	pairs.sort_custom(func(x, y):
		if x.gap != y.gap: return x.gap > y.gap
		if x.target != y.target: return x.target < y.target
		return x.source < y.source)
	var sent: Array = [0, 0, 0, 0]
	var received: Array = [0, 0, 0, 0]
	var moves: Array = []
	for pair in pairs:
		var s: int = pair.source
		var t: int = pair.target
		var proposed: int = A.mul(pair.gap - m.min_gap, m.per_gap_point, A.S * A.S)
		var count: int = mini(proposed, m.source_max - sent[s])
		count = mini(count, before[s] - sent[s] - m.source_min)
		count = mini(count, m.target_max - received[t])
		count = mini(count, housing[t] - before[t] - received[t])
		if count <= 0:
			continue
		sent[s] += count
		received[t] += count
		moves.append({"from": s, "to": t, "residents": count})
	for i in range(4):
		state.cities[i].population = before[i] - sent[i] + received[i]
	return {"time": time, "satisfaction_micro": scores, "before": before, "housing": housing,
		"moves": moves, "after": state.cities.map(func(c): return c.population), "transferred": A.total(sent)}

## Final order: population, then exact Satisfaction, Environment and cash. Exact ties share a rank.
static func ranking(state: Dictionary) -> Array:
	var keys: Array = ["population", "satisfaction_micro", "environment_micro", "money_micro"]
	var cities: Array = state.cities.duplicate()
	cities.sort_custom(func(x, y):
		for key in keys:
			if x[key] != y[key]: return x[key] > y[key]
		return x.city_id < y.city_id)
	var result: Array = []
	var previous: Array = []
	var rank: int = 0
	for c in cities:
		var score: Array = keys.map(func(key): return c[key])
		if score != previous:
			rank = result.size() + 1
		result.append({"rank": rank, "city_id": c.city_id, "population": c.population,
			"satisfaction_micro": c.satisfaction_micro, "environment_micro": c.environment_micro, "money_micro": c.money_micro})
		previous = score
	return result
