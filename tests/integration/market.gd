extends SceneTree
var checks: int=0
var failures: int=0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: "+label)
func _initialize() -> void:
	preload("res://tests/support/market_cases.gd").run(check)
	preload("res://tests/support/market_cases.gd").adversarial(check)
	preload("res://tests/support/market_cases.gd").organic_and_edges(check)
	print("Marketplace: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
