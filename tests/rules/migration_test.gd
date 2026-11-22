extends "res://tests/support/harness.gd"
## Pairwise migration and final ranking.
const Migration = preload("res://simulation/systems/migration.gd")

func _initialize() -> void:
	var rule: Dictionary = Balance.load_config().migration
	schedule(rule)
	pairs(rule)
	limits(rule)
	in_match()
	ranking()
	finish("Migration")

## Four cities: [satisfaction points, population, housing].
static func region(rows: Array) -> Dictionary:
	var cities: Array = []
	for i in range(4):
		cities.append({"city_id": i, "satisfaction_micro": int(round(rows[i][0] * 1000000.0)), "population": rows[i][1],
			"capacity": {"housing": rows[i][2]}, "environment_micro": 0, "money_micro": 0})
	return {"cities": cities}

func moved(rule: Dictionary, rows: Array) -> Array:
	var state: Dictionary = region(rows)
	var pulse: Dictionary = Migration.pulse(state, rule, 80)
	eq(A.total(pulse.after), A.total(pulse.before), "migration conserves residents")
	return pulse.after

func schedule(rule: Dictionary) -> void:
	var due: Array = range(1, 1201).filter(func(t): return Migration.due(rule, t))
	eq([due.size(), due[0], due[-1]], [56, 80, 1180], "pulses every 20 s from 80 to 1180")
	check(not Migration.due(rule, 1200), "no pulse at match end")

func pairs(rule: Dictionary) -> void:
	eq(moved(rule, [[80, 2000, 2300], [80, 2000, 2300], [80, 2000, 2300], [80, 2000, 2300]]), [2000, 2000, 2000, 2000], "equal Satisfaction: nobody moves")
	eq(moved(rule, [[86, 2000, 2300], [80, 2000, 2300], [80, 2000, 2300], [80, 2000, 2300]]), [2126, 1958, 1958, 1958], "+6 gap moves floor(8 x 5.25) = 42 from each rival")
	eq(moved(rule, [[80.75, 2000, 2300], [80, 2000, 2300], [80, 2000, 2300], [80, 2000, 2300]]), [2000, 2000, 2000, 2000], "a gap of exactly 0.75 moves nobody")
	eq(moved(rule, [[81.375, 2000, 2300], [80, 2000, 2300], [80, 2000, 2300], [80, 2000, 2300]]), [2015, 1995, 1995, 1995], "gap 1.375 moves floor(8 x 0.625) = 5 per pair")
	eq(moved(rule, [[90, 2000, 2300], [85, 2000, 2300], [80, 2000, 2300], [80, 2000, 2300]]), [2150, 1970, 1940, 1940],
		"largest gaps first: city 0 takes 60 + 60 from cities 2 and 3, then 30 from city 1 up to its 150 limit; 2 and 3 have nothing left for city 1")

func limits(rule: Dictionary) -> void:
	eq(moved(rule, [[100, 2000, 2300], [80, 2000, 2300], [80, 2000, 2300], [80, 2000, 2300]]), [2150, 1940, 1940, 1970], "60 per sender and 150 per receiver")
	eq(moved(rule, [[100, 2000, 2300], [80, 705, 2300], [99.5, 3295, 2300], [99.5, 2000, 2300]]), [2005, 700, 3295, 2000], "senders never drop below 700")
	eq(moved(rule, [[100, 2297, 2300], [80, 2000, 2300], [80, 2000, 2300], [80, 1703, 2300]]), [2300, 1997, 2000, 1703], "arrivals stop at free housing")
	eq(moved(rule, [[100, 2400, 2300], [80, 2000, 2300], [80, 2000, 2300], [80, 1600, 2300]]), [2400, 2000, 2000, 1600], "an over-full city receives nobody")

func in_match() -> void:
	var m = fixture()
	advance(m, 100)
	eq(m._state.migrations.map(func(p): return p.time), [80, 100], "pulses recorded at 80 and 100")
	eq(A.total(m._state.cities.map(func(c): return c.population)), 8000, "region keeps 8,000 residents")

func ranking() -> void:
	var state: Dictionary = {"cities": [
		{"city_id": 0, "population": 1000, "satisfaction_micro": 80, "environment_micro": 50, "money_micro": 10},
		{"city_id": 1, "population": 1100, "satisfaction_micro": 70, "environment_micro": 50, "money_micro": 10},
		{"city_id": 2, "population": 1000, "satisfaction_micro": 80, "environment_micro": 60, "money_micro": 10},
		{"city_id": 3, "population": 1000, "satisfaction_micro": 80, "environment_micro": 50, "money_micro": 10}]}
	var rows: Array = Migration.ranking(state)
	eq(rows.map(func(r): return [r.city_id, r.rank]), [[1, 1], [2, 2], [0, 3], [3, 3]], "population, then Satisfaction, Environment and cash; exact ties share a rank")
