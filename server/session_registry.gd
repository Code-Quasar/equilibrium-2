extends RefCounted
const TTL_MS = 7200000
var crypto = Crypto.new()
var entries: Dictionary = {}
func token() -> String:
	return crypto.generate_random_bytes(32).hex_encode()
func create(seat: int, connection: int, lobby: String, now: int) -> String:
	entries[seat] = {"connection":connection,"lobby_id":lobby,"generation":0}
	return rotate(seat,now)
func rotate(seat: int, now: int) -> String:
	var secret: String = token()
	entries[seat].digest = secret.sha256_buffer()
	entries[seat].generation += 1
	entries[seat].expires = now+TTL_MS
	return secret
func authenticate(lobby: String, secret: String, now: int) -> int:
	if secret.length() != 64: return -1
	var digest: PackedByteArray = secret.sha256_buffer()
	for seat in entries:
		var e: Dictionary = entries[seat]
		if e.lobby_id == lobby and now < e.expires and crypto.constant_time_compare(e.digest,digest): return seat
	return -1
func seat_for(connection: int) -> int:
	for seat in entries:
		if entries[seat].connection == connection: return seat
	return -1
