class_name LocalCatchStore
extends RefCounted

## Local fish custody survives quitting and redeploying; MP uses server holds.
static func key(ship: BoatBody, hold_id: String) -> String:
	return str(ship.get_meta("vessel_uid", "")) + "/" + hold_id

static func put(data: PlayerData, ship: BoatBody, hold_id: String, state: Dictionary) -> void:
	var holds: Dictionary = data.local_fishing.get("holds", {})
	holds[key(ship, hold_id)] = state.duplicate(true)
	data.local_fishing["holds"] = holds

static func restore(hold: CatchHoldComponent) -> void:
	if WorldGateway.is_remote() or not is_instance_valid(hold._boat) or PlayerSession.data == null: return
	var uid := str(hold._boat.get_meta("vessel_uid", ""))
	if uid.is_empty() or PlayerSession.data.find_owned_vessel(uid).is_empty(): return
	if hold.has_meta("local_catch_restored"): return
	hold.set_meta("local_catch_restored", true)
	var state: Dictionary = PlayerSession.data.local_fishing.get("holds", {}).get(key(hold._boat, hold.hold_id), {})
	if not state.is_empty(): hold.apply_state(state)

static func changed(hold: CatchHoldComponent) -> void:
	if WorldGateway.is_remote() or not hold.has_meta("local_catch_restored") or PlayerSession.data == null: return
	if not is_instance_valid(hold._boat) or PlayerSession.data.find_owned_vessel(str(hold._boat.get_meta("vessel_uid", ""))).is_empty(): return
	put(PlayerSession.data, hold._boat, hold.hold_id, hold.state.to_dict())
	PlayerSession._request_save()
