extends RefCounted
## RECYCLING BREAKDOWN: one player's recycling line, SHREDDER -> FILTER -> PRESS, as a
## small deterministic model in integer steps of STEP_MS. The server runs it to score;
## the client runs the same file to draw and predict. It never touches the city.
##
## Shredder: a jam stops its output; the buffer to the filter then drains and the line
##   starves. Clear it by dragging the rollers back in the jam's direction, at least
##   the jam's release distance.
## Filter: pressure rises all the time and jumps on surges. Above the green band its
##   efficiency falls; at the top it blocks for a while. Three valves release small,
##   medium or large amounts; the large one, or releasing far too much, briefly slows it.
## Press: alignment drifts away from centre and its efficiency falls with the offset.
##   Calibrate by tapping while the oscillating marker is inside the safe band.
## Line efficiency = min(shredder supply, filter, press), in permille. The score is
## repairs, minus wrong interventions, plus uptime (line efficiency over time) and a
## bonus for each stretch of sustained high uptime; never below zero.
## This file is shared byte for byte with the client (tools/check_repository.py).

const STEP_MS := 100
const SHREDDER := 0
const FILTER := 1
const PRESS := 2

static func new_state() -> Dictionary:
	return {"sim_ms": 0, "next": 0, "jam_dir": -1, "jam_dist": 0, "buffer_ms": 0, "pressure": 300,
		"slow_until": 0, "block_until": 0, "align": 500, "drift": 0, "line": 1000, "uptime": 0,
		"high_ms": 0, "repairs": 0, "wrong": 0, "bonus": 0, "failures": 0}

## The phase's value of a pacing parameter: a before phase_b_ms, b before phase_c_ms, c after.
static func by_phase(p: Dictionary, ms: int, a: String, b: String, c: String) -> int:
	return p[a] if ms < p.phase_b_ms else (p[b] if ms < p.phase_c_ms else p[c])

## Machine efficiencies [shredder supply, filter, press, line] in permille.
static func efficiency(s: Dictionary, p: Dictionary) -> Array:
	var shred: int = 1000 if s.jam_dir < 0 or s.buffer_ms > 0 else 0
	var filt: int = 1000
	if s.sim_ms < s.block_until:
		filt = 0
	elif s.pressure > p.green_max:
		filt = maxi(200, 1000 - (s.pressure - p.green_max) * 800 / maxi(1, p.red_min - p.green_max))
	if s.sim_ms < s.slow_until:
		filt = mini(filt, p.slow_permille)
	var off: int = absi(s.align - 500)
	var press: int = 1000 if off <= p.align_ok else maxi(0, 1000 - (off - p.align_ok) * 1000 / maxi(1, p.align_stop - p.align_ok))
	return [shred, filt, press, mini(shred, mini(filt, press))]

## Advances the line to to_ms (rounded down to a step), applying scheduled faults.
static func advance(s: Dictionary, faults: Array, p: Dictionary, sc: Dictionary, to_ms: int) -> void:
	var target: int = mini(to_ms, p.active_ms) / STEP_MS * STEP_MS
	while s.sim_ms < target:
		while s.next < faults.size() and faults[s.next].at_ms <= s.sim_ms:
			var f: Dictionary = faults[s.next]
			match int(f.machine):
				SHREDDER:
					if s.jam_dir < 0:
						s.jam_dir = f.dir
						s.jam_dist = f.dist
						s.failures += 1
				FILTER:
					s.pressure = mini(1000, s.pressure + int(f.amount))
				PRESS:
					s.drift = int(f.rate)
			s.next += 1
		# Filter pressure rises; at the top it blocks and is vented to the amber band.
		s.pressure = mini(1000, s.pressure + by_phase(p, s.sim_ms, "pressure_a", "pressure_b", "pressure_c") * STEP_MS / 1000)
		if s.pressure >= 1000 and s.sim_ms >= s.block_until:
			s.block_until = s.sim_ms + p.block_ms
			s.pressure = p.red_min - 50
			s.failures += 1
		# Press alignment drifts while a drift is under way.
		s.align = clampi(s.align + s.drift * STEP_MS / 1000, 0, 1000)
		# The shredder feeds the buffer; jammed, the buffer drains.
		s.buffer_ms = mini(p.buffer_ms, s.buffer_ms + STEP_MS) if s.jam_dir < 0 else maxi(0, s.buffer_ms - STEP_MS)
		var e: Array = efficiency(s, p)
		s.line = e[3]
		s.uptime += e[3] * STEP_MS / 1000
		# Sustained high uptime earns a bonus each full stretch.
		if e[3] >= p.high_permille:
			s.high_ms += STEP_MS
			if s.high_ms % (sc.streak * 1000) == 0:
				s.bonus += sc.streak_bonus
		else:
			s.high_ms = 0
		s.sim_ms += STEP_MS

## The press calibration marker (0..1000) at ms: a fixed oscillation, the same for all.
static func marker(p: Dictionary, ms: int) -> int:
	var period: int = by_phase(p, ms, "marker_period_a_ms", "marker_period_a_ms", "marker_period_c_ms")
	var phase: int = ms % period
	var half: int = period / 2
	# A triangle wave from 50 to 950 and back: speed is constant, so timing is readable.
	return 50 + (phase * 900 / half if phase < half else (period - phase) * 900 / half)

static func press_band(p: Dictionary, ms: int) -> int:
	return by_phase(p, ms, "press_band_a", "press_band_a", "press_band_c")

## One intervention at t_ms (the line must already be advanced to it).
## Returns "correct", "incorrect" or a rejection ("no_fault", "invalid_choice").
static func act(s: Dictionary, p: Dictionary, machine: int, answer: int, t_ms: int) -> String:
	var e: Array = efficiency(s, p)
	match machine:
		SHREDDER:
			if s.jam_dir < 0:
				return "no_fault"
			var dir: int = answer / 1000
			var dist: int = answer % 1000
			if answer < 0 or dir > 3:
				return "invalid_choice"
			if dir != s.jam_dir or dist < s.jam_dist:
				s.wrong += 1
				return "incorrect"
			s.jam_dir = -1
			s.repairs += 1
			return "correct"
		FILTER:
			if answer < 0 or answer > 2:
				return "invalid_choice"
			# Only pressure above the green band needs relief: no preventive releases.
			if s.pressure <= p.green_max:
				return "no_fault"
			var release: int = [p.valve_small, p.valve_medium, p.valve_large][answer]
			s.pressure = maxi(0, s.pressure - release)
			if answer == 2 or s.pressure < p.overcorrect_below:
				s.slow_until = maxi(s.slow_until, t_ms + p.slow_ms)
			# Into the green band without overcorrecting: the right call. Not enough
			# relief helps but scores nothing; far too much costs throughput and points.
			if s.pressure < p.overcorrect_below:
				s.wrong += 1
				return "incorrect"
			if s.pressure <= p.green_max:
				s.repairs += 1
				return "correct"
			return "partial"
		PRESS:
			if absi(s.align - 500) <= p.align_ok and s.drift == 0:
				return "no_fault"
			if answer != 0:
				return "invalid_choice"
			if absi(marker(p, t_ms) - 500) <= press_band(p, t_ms):
				s.align = 500
				s.drift = 0
				s.repairs += 1
				return "correct"
			s.wrong += 1
			return "incorrect"
	return "invalid_choice"

static func score(s: Dictionary, sc: Dictionary) -> int:
	return maxi(0, s.repairs * sc.correct - s.wrong * sc.incorrect + s.uptime * sc.uptime_per_second / 1000 + s.bonus)
