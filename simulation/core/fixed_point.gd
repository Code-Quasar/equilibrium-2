extends RefCounted
## Rates are already micro-units/minute. Carry is serialized by the caller.
const SCALE: int = 1000000

static func per_second(rate: int, carry: int) -> Dictionary:
	assert(rate >= 0 and rate <= 9223372036854775748)
	assert(carry >= 0 and carry < 60)
	var numerator: int = rate + carry
	@warning_ignore("integer_division")
	var amount: int = numerator / 60
	return {"amount": amount, "carry": numerator % 60}
