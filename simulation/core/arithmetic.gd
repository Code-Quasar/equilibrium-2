extends RefCounted
const S: int = 1000000

static func divi(a: int, b: int) -> int:
	@warning_ignore("integer_division")
	var q: int = a / b
	return q

# Exact nonnegative multiply/divide with an overflow-safe fallback.
static func product(a: int, b: int, d: int) -> Dictionary:
	assert(a >= 0 and b >= 0 and d > 0)
	if b == 0 or a <= divi(9223372036854775807, b):
		return {"q": divi(a * b, d), "r": (a * b) % d}
	var q: int = 0
	var r: int = 0
	var aq: int = divi(a, d)
	var ar: int = a % d
	while b > 0:
		if b % 2 == 1:
			q += aq
			if r >= d - ar:
				q += 1
				r -= d - ar
			else:
				r += ar
		b = divi(b, 2)
		if b == 0: break
		aq *= 2
		if ar >= d - ar:
			aq += 1
			ar -= d - ar
		else:
			ar *= 2
	return {"q": q, "r": r}

static func mul(a: int, b: int, d: int = S) -> int:
	return product(a, b, d).q

static func carried(city: Dictionary, key: String, a: int, b: int, denominator: int) -> int:
	var value: Dictionary = product(a, b, denominator)
	var old: Dictionary = city.local_carries.get(key, {"r": 0, "d": denominator})
	assert(old.d == denominator)
	value.r += old.r
	value.q += divi(value.r, denominator)
	city.local_carries[key] = {"r": value.r % denominator, "d": denominator}
	return value.q

static func rate(city: Dictionary, key: String, micro_per_minute: int, efficiency: int = S) -> int:
	return carried(city, key, micro_per_minute, efficiency, 60 * S)

static func efficiency(city: Dictionary, building: Dictionary) -> int:
	return mul(city.capacity.staffing_micro, building.power_factor_micro) if building.operational else 0

static func total(values: Array) -> int:
	var result: int = 0
	for value in values: result += value
	return result

# Weights are also hard per-recipient limits. Input order owns exact remainder ties.
static func allocate(budget: int, weights: Array) -> Array:
	var sum_weights: int = total(weights)
	var used: int = mini(budget, sum_weights)
	var result: Array = []
	var remainders: Array = []
	var assigned: int = 0
	for i in range(weights.size()):
		var share: Dictionary = product(used, weights[i], sum_weights) if sum_weights > 0 else {"q": 0, "r": 0}
		result.append(share.q)
		assigned += share.q
		remainders.append({"i": i, "r": share.r})
	remainders.sort_custom(func(a, b): return a.r > b.r if a.r != b.r else a.i < b.i)
	for j in range(used - assigned): result[remainders[j].i] += 1
	return result
