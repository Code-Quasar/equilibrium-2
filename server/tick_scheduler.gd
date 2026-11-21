extends RefCounted
## Injected monotonic milliseconds; debt is retained, never skipped.
var next_ms: int = -1
const INTERVAL_MS = 1000
const MAX_CATCHUP = 4
func start(now_ms: int) -> void:
	next_ms = now_ms + INTERVAL_MS
func stop() -> void:
	next_ms = -1
func due(now_ms: int) -> int:
	if next_ms < 0 or now_ms < next_ms: return 0
	@warning_ignore("integer_division")
	var count: int = mini(MAX_CATCHUP,1 + (now_ms-next_ms)/INTERVAL_MS)
	next_ms += count*INTERVAL_MS
	return count
