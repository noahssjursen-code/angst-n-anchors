extends SceneTree

const Store := preload("res://scripts/player/local_captain_store.gd")
const Bootstrap := preload("res://scripts/world/world_bootstrap.gd")
const Service := preload("res://scripts/player/captain_service.gd")
const TestReport := preload("res://tests/support/test_report.gd")


func _initialize() -> void:
	var t := TestReport.new("onboarding_store_test")
	var root_path := "user://onboarding_overhaul_test_save"
	_wipe(root_path)
	Store.root_override = root_path
	PlayerSaveStore.storage_root_override = ""
	Store.active_id = ""

	# Legacy migrate: write old single-slot file before index exists.
	DirAccess.make_dir_recursive_absolute(root_path)
	PlayerSaveStore.storage_root_override = root_path
	var legacy := PlayerData.new()
	legacy.account_id = "legacy-captain-1"
	legacy.display_name = "Legacy Skipper"
	legacy.home_port_id = "port-home"
	legacy.world_context = {"seed": 99, "generation_version": 4, "layout_checksum": ""}
	t.check("legacy single-slot player saves", PlayerSaveStore.save_player(legacy))
	PlayerSaveStore.storage_root_override = ""

	Store.ensure_migrated()
	var listed := Store.list_captains()
	if not t.equal("migration yields one captain", listed.size(), 1):
		t.finish(self)
		return
	t.equal("migrated captain keeps its display name", str(listed[0].get("display_name", "")), "Legacy Skipper")
	t.equal("migrated captain keeps its world seed", int(listed[0].get("world_seed", 0)), 99)

	# Create second slot + delete
	t.check("second slot is created", Store.create_slot("captain-two", {
		"display_name": "Second",
		"home_port_id": "port-3",
		"world_seed": 12345,
	}))
	PlayerSaveStore.storage_root_override = Store.captain_dir("captain-two")
	var second := PlayerData.new()
	second.account_id = "captain-two"
	second.display_name = "Second"
	second.home_port_id = "port-3"
	second.world_context = {"seed": 12345}
	t.check("second captain saves", PlayerSaveStore.save_player(second))
	Store.touch_index_from_player(second)
	t.equal("roster lists both captains", Store.list_captains().size(), 2)
	t.check("second captain deletes", Store.delete_captain("captain-two"))
	t.equal("roster drops back to one captain", Store.list_captains().size(), 1)

	# Corrupt/legacy title autosaves could leave index-only "Captain" rows.
	# They are not save slots and must be repaired out of the roster.
	Store._upsert_index_entry({
		"id": "orphan-title-autosave",
		"display_name": "Captain",
		"world_seed": 0,
	})
	t.equal("orphan index row is not listed as a captain", Store.list_captains().size(), 1)
	t.equal("orphan index row is repaired out of the index", Store._read_index().size(), 1)

	# Seed policy
	var seed_a := Bootstrap.roll_seed()
	var seed_b := Bootstrap.roll_seed()
	t.check("rolled seeds are positive", seed_a > 0 and seed_b > 0)
	Bootstrap.apply_seed(777)
	var settings: Node = root.get_node_or_null("GameSettings")
	if settings != null:
		t.equal("apply_seed writes the map generation seed", int(settings.get("map_generation_seed")), 777)

	var player := PlayerData.new()
	player.world_context = {"seed": 555, "generation_version": 4, "layout_checksum": "abc"}
	Bootstrap.apply_player_world_context(player)
	if settings != null:
		t.equal("player world context overrides the seed", int(settings.get("map_generation_seed")), 555)

	var service := Service.new()
	service.configure_local()
	t.equal("local captain service sees one entry", service.entries().size(), 1)
	Store.clear_active()
	service.select("legacy-captain-1")
	t.check("selecting without a slot leaves no active captain", not Store.has_active())

	_wipe(root_path)
	Store.root_override = ""
	PlayerSaveStore.storage_root_override = ""
	t.finish(self)


func _wipe(path: String) -> void:
	if DirAccess.dir_exists_absolute(path):
		PlayerSaveStore._remove_tree(path)
