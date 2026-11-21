extends RefCounted
const Balance=preload("res://simulation/core/balance.gd")
static func validate(b: Dictionary) -> String:
	if not Balance.fields(b.get("migration"),["sender_cap","receiver_cap","regional_cap"]):return "invalid_migration_config"
	if b.migration.sender_cap<1 or b.migration.receiver_cap<1 or b.migration.regional_cap<1:return "invalid_migration_caps"
	if not Balance.fields(b.get("market"),["duration","minimum_remaining","contract_limit","booking_micro","minimum_need_micro","quote_seconds","selection_seconds","zero_seconds","cooldown","expiry_warning"]):return "invalid_market_config"
	for key in ["duration","minimum_remaining","contract_limit","booking_micro","minimum_need_micro","quote_seconds","selection_seconds","zero_seconds","cooldown"]:
		if b.market[key]<1:return "invalid_market_bounds"
	if not b.market.get("prices") is Dictionary:return "invalid_prices"
	for kind in ["electricity","recyclable","organic"]:
		if not Balance.fields(b.market.prices.get(kind),["minimum","maximum","step","standard"]):return "invalid_price_config"
		var p: Dictionary=b.market.prices[kind]
		if p.minimum<=0 or p.step<=0 or p.minimum>p.maximum or p.standard<p.minimum or p.standard>p.maximum or (p.standard-p.minimum)%p.step!=0:return "invalid_price_bounds"
	if not b.get("events") is Array or b.events.size()!=4:return "invalid_events"
	var names: Array=[]
	for event in b.events:
		if not Balance.fields(event,["warning","start","end"]) or typeof(event.get("id"))!=TYPE_STRING or event.id in names:return "invalid_event"
		if event.warning>=event.start or event.start>=event.end or event.end>1200 or not event.get("modifiers") is Dictionary:return "invalid_event_boundary"
		for key in event.modifiers:
			if key not in ["household_percent","factory_percent","commerce_percent","air_percent","municipal_E","uncollected_penalty_micro"] or typeof(event.modifiers[key])!=TYPE_INT or event.modifiers[key]<0 or event.modifiers[key]>1000000:return "invalid_event_modifier"
		names.append(event.id)
	return ""
