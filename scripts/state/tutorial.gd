extends Node

## Autoload — register as "Tutorial".
## First-time hint chain. Each hint fires at most once per captain; seen
## state is persisted in PlayerData.tutorial_seen so reload doesn't replay.
##
## Callers fire a hint by id:
##   Tutorial.show("welcome")
## If the hint hasn't been seen, the HintOverlay surfaces it and the id is
## marked seen (and saved). Otherwise it's a no-op.

signal hint_requested(text: String, duration_s: float)

const DEFAULT_DURATION : float = 6.0

const HINTS := {
	"welcome": {
		"text": "Welcome aboard, Captain. Walk over to the Harbour Master to request a berth.",
		"duration": 8.0,
	},
	"first_berth": {
		"text": "Your vessel is at the dock. Step aboard and press F on the captain's chair to take the helm.",
		"duration": 8.0,
	},
	"first_helm": {
		"text": "W/S adjusts throttle, A/D steers. Press F again to leave the helm. Sea chart on [M].",
		"duration": 9.0,
	},
	"first_journal": {
		"text": "Cargo accepted. Press [J] any time to review your active contracts.",
		"duration": 7.0,
	},
	"low_fuel": {
		"text": "Fuel running low. Return to a port with a pump and ask the Harbour Master to refuel.",
		"duration": 7.0,
	},
}


func show(hint_id: String) -> void:
	if not HINTS.has(hint_id):
		return
	var session := get_node_or_null("/root/PlayerSession")
	if session == null or session.data == null:
		return
	var data: PlayerData = session.data
	if data.tutorial_seen.get(hint_id, false):
		return
	data.tutorial_seen[hint_id] = true
	if session.has_method("save_now"):
		session.call_deferred("save_now")
	var entry: Dictionary = HINTS[hint_id]
	hint_requested.emit(str(entry.get("text", "")), float(entry.get("duration", DEFAULT_DURATION)))


## Test helper — wipe seen state so the chain plays again. Bound to no UI yet,
## but useful from the debug console and obviously needed if we ever ship a
## "replay tutorial" toggle in Settings.
func reset() -> void:
	var session := get_node_or_null("/root/PlayerSession")
	if session == null or session.data == null:
		return
	session.data.tutorial_seen.clear()
	if session.has_method("save_now"):
		session.call("save_now")
