class_name CaptainService
extends RefCounted

## Unified captain roster facade for singleplayer and multiplayer.
## UI talks only to this service; storage backends stay swappable.

enum Mode { LOCAL, REMOTE }

signal roster_changed(entries: Array)
signal captain_selected(entry: Dictionary)
signal captain_created(entry: Dictionary)
signal captain_deleted(captain_id: String)
signal error_message(message: String)

var mode: Mode = Mode.LOCAL
var remote := RemoteCaptainClient.new()
var selected_id: String = ""
var _entries: Array = []


func configure_local() -> void:
	mode = Mode.LOCAL
	selected_id = ""
	refresh()


func configure_remote(host: Node, base_url: String) -> void:
	mode = Mode.REMOTE
	selected_id = ""
	remote.setup(host, base_url)
	if not remote.captains_listed.is_connected(_on_remote_listed):
		remote.captains_listed.connect(_on_remote_listed)
	if not remote.captain_created.is_connected(_on_remote_created):
		remote.captain_created.connect(_on_remote_created)
	if not remote.captain_deleted.is_connected(_on_remote_deleted):
		remote.captain_deleted.connect(_on_remote_deleted)
	if not remote.captain_updated.is_connected(_on_remote_updated):
		remote.captain_updated.connect(_on_remote_updated)
	if not remote.request_failed.is_connected(_on_remote_failed):
		remote.request_failed.connect(_on_remote_failed)
	refresh()


func refresh() -> void:
	if mode == Mode.LOCAL:
		_entries = _local_entries()
		roster_changed.emit(_entries)
	else:
		remote.list_captains()


func entries() -> Array:
	return _entries.duplicate(true)


func select(captain_id: String) -> Dictionary:
	var id := captain_id.strip_edges()
	for entry_raw in _entries:
		if typeof(entry_raw) != TYPE_DICTIONARY:
			continue
		var entry := entry_raw as Dictionary
		if str(entry.get("id", "")) != id:
			continue
		selected_id = id
		# Selecting a roster row must not redirect persistence. The slot only
		# becomes active when Sail loads that captain into PlayerSession.
		captain_selected.emit(entry)
		return entry
	return {}


func delete_selected_or(captain_id: String) -> void:
	var id := captain_id.strip_edges()
	if id.is_empty():
		return
	if mode == Mode.LOCAL:
		if LocalCaptainStore.delete_captain(id):
			if selected_id == id:
				selected_id = ""
			captain_deleted.emit(id)
			refresh()
		else:
			error_message.emit("Failed to delete local captain.")
	else:
		remote.delete_captain(id)


func create_local(
	display_name: String,
	appearance: CharacterAppearance,
	home_port_id: String,
	world_seed: int,
) -> PlayerData:
	var tree := Engine.get_main_loop() as SceneTree
	var session: Node = null
	if tree != null and tree.root != null:
		session = tree.root.get_node_or_null("PlayerSession")
	if session == null:
		error_message.emit("PlayerSession missing.")
		return null
	var account_id := PlayerData.new_uuid()
	LocalCaptainStore.create_slot(account_id, {
		"display_name": display_name,
		"home_port_id": home_port_id,
		"world_seed": world_seed,
		"last_played_unix": int(Time.get_unix_time_from_system()),
	})
	session.begin_new_captain(display_name, appearance, home_port_id, account_id, world_seed)
	LocalCaptainStore.touch_index_from_player(session.data)
	selected_id = account_id
	var entry := {
		"id": account_id,
		"display_name": session.data.display_name,
		"home_port_id": session.data.home_port_id,
		"world_seed": world_seed,
		"marks": session.data.marks,
		"source": "local",
	}
	captain_created.emit(entry)
	refresh()
	return session.data


func create_remote(display_name: String, appearance: CharacterAppearance) -> void:
	remote.create_captain(display_name, appearance)


func load_local_into_session(captain_id: String) -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	var session: Node = null
	if tree != null and tree.root != null:
		session = tree.root.get_node_or_null("PlayerSession")
	if session == null:
		return false
	if not LocalCaptainStore.activate(captain_id):
		return false
	var player := PlayerSaveStore.load_player()
	session._load_data(player.to_dict())
	session.begin_offline_voyage()
	LocalCaptainStore.touch_index_from_player(session.data)
	selected_id = captain_id
	return true


func apply_remote_selection(entry: Dictionary) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var session: Node = null
	if tree != null and tree.root != null:
		session = tree.root.get_node_or_null("PlayerSession")
	if session == null:
		return
	var id := str(entry.get("id", ""))
	var appearance := remote.parse_appearance(entry.get("appearance_json", entry.get("appearance", {})))
	session.set_captain_profile(
		id,
		str(entry.get("display_name", "Captain")),
		int(entry.get("marks", PlayerData.NEW_CAPTAIN_STARTING_MARKS)),
		appearance,
	)
	selected_id = id
	captain_selected.emit(entry)


func _local_entries() -> Array:
	var out: Array = []
	for entry in LocalCaptainStore.list_captains():
		var copy := entry.duplicate(true)
		copy["source"] = "local"
		out.append(copy)
	return out


func _on_remote_listed(captains: Array) -> void:
	_entries = []
	for raw in captains:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var cap := raw as Dictionary
		_entries.append({
			"id": str(cap.get("id", "")),
			"display_name": str(cap.get("display_name", "Captain")),
			"marks": int(cap.get("marks", 0)),
			"appearance_json": cap.get("appearance_json", ""),
			"home_port_id": str(cap.get("home_port_id", "")),
			"world_seed": 0,
			"source": "remote",
		})
	roster_changed.emit(_entries)


func _on_remote_created(captain: Dictionary) -> void:
	var entry := {
		"id": str(captain.get("id", "")),
		"display_name": str(captain.get("display_name", "Captain")),
		"marks": int(captain.get("marks", PlayerData.NEW_CAPTAIN_STARTING_MARKS)),
		"appearance_json": captain.get("appearance_json", ""),
		"source": "remote",
	}
	selected_id = str(entry.get("id", ""))
	apply_remote_selection(entry)
	captain_created.emit(entry)
	refresh()


func _on_remote_deleted(captain_id: String) -> void:
	if selected_id == captain_id:
		selected_id = ""
	captain_deleted.emit(captain_id)
	refresh()


func _on_remote_updated(_captain: Dictionary) -> void:
	refresh()


func _on_remote_failed(_action: String, message: String) -> void:
	error_message.emit(message)
