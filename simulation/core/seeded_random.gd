extends RefCounted
## Park-Miller 16807, version 1. Products fit signed int64; no global RNG.
const MODULUS: int = 2147483647
var state: int

func _init(match_seed: int = 0) -> void:
	state = posmod(match_seed, MODULUS - 1) + 1

func next_int() -> int:
	state = (state * 16807) % MODULUS
	return state

func below(bound: int) -> int:
	assert(bound > 0 and bound <= MODULUS - 1)
	# Rejection sampling avoids modulo bias. Random draws are in [0, M-2].
	var limit: int = (MODULUS - 1) - ((MODULUS - 1) % bound)
	var sample: int = next_int() - 1
	while sample >= limit:
		sample = next_int() - 1
	return sample % bound
