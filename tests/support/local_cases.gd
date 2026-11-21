extends RefCounted
const Protocol=preload("res://simulation/interfaces/local_protocol.gd")
static func run(check: Callable) -> void:
	for count in [2,3,4]:
		var p=Protocol.new()
		check.call(p.initialize(42,count,false)=="","local seats")
		check.call(p.dispatch({"op":"command","player_id":0,"kind":"select_foundation","payload":{"foundation":"industrial_legacy"}}).status=="select_seat_first","explicit active seat")
		while p.session.game.engine==null:
			var player: int=p.session.game.draft.order[p.session.game.draft.turn]
			check.call(p.dispatch({"op":"seat","seat":player}).status=="seat_selected","seat select")
			for card in p.session.game.CARDS:
				if card not in p.session.game.draft.choices:
					check.call(p.dispatch({"op":"command","player_id":player,"kind":"select_foundation","payload":{"foundation":card}}).status=="applied","local draft");break
		p.dispatch({"op":"seat","seat":0})
		check.call(p.dispatch({"op":"command","player_id":1,"kind":"construct","payload":{"building_type":"factory"}}).status=="unauthorized_player","cannot forge city")
		check.call(p.dispatch({"op":"command","player_id":0,"kind":"construct","payload":{"building_type":"factory"}}).status=="queued","authoritative queued build")
		check.call(p.dispatch({"op":"advance","seconds":1}).status=="advanced","local advance")
		check.call(p.dispatch({"op":"snapshot"}).state.tick==1,"authoritative snapshot")
		if count<4:check.call(p.dispatch({"op":"seat","seat":3}).status=="seat_not_locally_controlled","scripted seat protected")
		check.call(p.dispatch({"op":"advance","seconds":"nonsense"}).status=="invalid_seconds","malformed time")
		check.call(p.dispatch({"op":"preview","kind":"set_reduce_waste","payload":{"enabled":"maybe"}}).status=="invalid_payload","policy validation")
		for seat in [-1,4,"0",true]:
			check.call(p.dispatch({"op":"seat","seat":seat}).status!="seat_selected","invalid seat")
		for raw in [null,[],{}, {"v":2,"id":1,"op":"snapshot"},{"v":1,"id":"1","op":"snapshot"}]:
			check.call(p.request(raw).status!="ok","malformed protocol")
		var saved: String=p.session.game.engine.serialize()
		p.dispatch({"op":"preview","kind":"construct","payload":{"building_type":"factory"}})
		p.dispatch({"op":"snapshot"})
		check.call(p.session.game.engine.serialize()==saved,"queries do not mutate state RNG or pending commands")
		var response: Dictionary=p.request({"v":1,"id":42,"op":"snapshot"})
		check.call(response.v==1 and response.id==42,"protocol response identity")
