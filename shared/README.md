# Protocol v1

`protocol_v1.gd` validates client messages and engine payload shapes. `strict_json.gd` decodes bounded integer-only JSON, rejecting duplicate keys, trailing commas, fractional or exponent numbers, unsafe integers and invalid Unicode. `protocol_v1.schema.json` is the language-neutral wire schema. Nested view visibility is defined by the recursive allowlists in `simulation/projections/player_view.gd`.

The protocol carries one UTF-8 JSON object per WebSocket text message. Every client message has `v`, `type` and `correlation_id`; actions also have a client-generated `action_id`. Marketplace `payload.request_id` is an engine marketplace identifier and never a protocol correlation identifier. The server derives seat, match, engine command ID, sequence and receipt tick.

Client message types are `hello`, `create_lobby`, `join_lobby`, `set_ready`, `start_match`, `choose_foundation`, `submit_action` and `rejoin`. Server messages include negotiation, lobby/draft state, action acknowledgments, filtered player views, draft cancellation and final results. Exact required fields and all supported gameplay payloads are in the schema.

Rejoin credentials are private, rotate after successful use and bind to one lobby seat. A disconnected player retains their seat during play. During Foundation drafting, the server allows a configurable reconnection grace period, then cancels and cleans the incomplete draft rather than selecting a Foundation or converting the human to a bot.
