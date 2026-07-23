class_name WorldBootstrap
extends RefCounted

## Session hand-off before entering the world.
## Input: seed + optional world context fields.
## Output: GameSettings hydrated and ready for world.tscn.

const WORLD_SCENE := "res://scenes/world.tscn"
const MAIN_MENU_SCENE := "res://scenes/ui/main_menu.tscn"
const PORT_OVERHAUL_PREVIOUS_GENERATION := 5
const TERRAIN_COAST_PREVIOUS_GENERATION := 6
const FJORD_WIDTH_PREVIOUS_GENERATION := 7


static func roll_seed() -> int:
	randomize()
	# Avoid the old hard-coded demo seed so new captains never land on 42 by accident.
	var seed_val := randi_range(1, 2_147_483_646)
	if seed_val == 42:
		seed_val = 43
	return seed_val


static func apply_seed(
		seed_val: int,
		version: int = 0,
		checksum: String = "",
		weather_version: int = 3,
		world_size_m: float = -1.0,
		preset_id: String = "",
) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	var settings: Node = tree.root.get_node_or_null("GameSettings")
	if settings == null:
		return
	var gen_version := version
	if gen_version <= 0:
		gen_version = int(settings.get("map_generation_version"))
	settings.call(
		"set_world_generation_context",
		seed_val,
		gen_version,
		checksum,
		weather_version,
		world_size_m,
		preset_id,
	)


static func apply_player_world_context(player: PlayerData) -> void:
	if player == null:
		return
	var ctx: Dictionary = player.world_context if typeof(player.world_context) == TYPE_DICTIONARY else {}
	var seed_val := int(ctx.get("seed", 0))
	if seed_val <= 0:
		push_error("WorldBootstrap: captain has no world seed; refusing to re-roll silently")
		seed_val = int(Engine.get_main_loop().root.get_node("GameSettings").get("map_generation_seed"))
		if seed_val <= 0:
			seed_val = roll_seed()
		ctx["seed"] = seed_val
		player.world_context = ctx
	var saved_version := int(ctx.get("generation_version", 0))
	if saved_version == PORT_OVERHAUL_PREVIOUS_GENERATION \
			and WorldLayoutGenerator.GENERATION_VERSION == 6:
		# v6 replaces every port footprint and operational identity. Keep the
		# captain and seed, but explicitly invalidate world-local contracts and
		# vessel calls rather than restoring them into different facilities.
		player.accepted_contracts = []
		player.port_operations_state = {}
		ctx["generation_version"] = WorldLayoutGenerator.GENERATION_VERSION
		player.world_context = ctx
	if saved_version == TERRAIN_COAST_PREVIOUS_GENERATION \
			and WorldLayoutGenerator.GENERATION_VERSION == 7:
		# v7 reshapes coast SDF and backshore grades; port sites move on the same seed.
		player.accepted_contracts = []
		player.port_operations_state = {}
		ctx["generation_version"] = WorldLayoutGenerator.GENERATION_VERSION
		player.world_context = ctx
	if saved_version == FJORD_WIDTH_PREVIOUS_GENERATION \
			and WorldLayoutGenerator.GENERATION_VERSION == 8:
		# v8 widens/meanders waterways and scales by world_size_m; harbour sites shift.
		player.accepted_contracts = []
		player.port_operations_state = {}
		ctx["generation_version"] = WorldLayoutGenerator.GENERATION_VERSION
		player.world_context = ctx
	# Legacy saves without an explicit weather version, or an older fog
	# contract, adopt the current forecast instead of keeping obsolete density.
	const CURRENT_WEATHER_VERSION := 3
	var weather_version := int(ctx.get("weather_generation_version", CURRENT_WEATHER_VERSION))
	if not ctx.has("weather_generation_version") or weather_version != CURRENT_WEATHER_VERSION:
		weather_version = CURRENT_WEATHER_VERSION
		ctx["weather_generation_version"] = weather_version
		player.world_context = ctx
	var world_size_m := float(ctx.get("world_size_m", -1.0))
	var preset_id := str(ctx.get("world_preset", ctx.get("map_world_preset", "")))
	apply_seed(
		seed_val,
		int(ctx.get("generation_version", 0)),
		str(ctx.get("layout_checksum", "")),
		weather_version,
		world_size_m,
		preset_id,
	)


static func apply_mp_world_options(options: Dictionary) -> int:
	var seed_val := int(options.get("world_seed", 0))
	if seed_val <= 0:
		push_error("WorldBootstrap: multiplayer server returned no valid world seed")
		return 0
	var preset_id := str(options.get("world_preset", options.get("map_world_preset", "")))
	var world_size_m := float(options.get("world_size_m", -1.0))
	if not preset_id.strip_edges().is_empty() and world_size_m <= 0.0:
		var WorldConfigScript := load("res://scripts/world/world_config.gd")
		world_size_m = float(WorldConfigScript.preset_size_m(preset_id))
	apply_seed(
		seed_val,
		int(options.get("generation_version", 0)),
		str(options.get("layout_checksum", "")),
		int(options.get("weather_generation_version", 3)),
		world_size_m,
		preset_id,
	)
	return seed_val


static func enter_world(
		tree: SceneTree,
		multiplayer: bool = false,
		authority_prepared: bool = false,
) -> void:
	var config := tree.root.get_node_or_null("ServerConfig")
	if config != null:
		config.set("is_multiplayer_mode", multiplayer)
	var gateway := tree.root.get_node_or_null("WorldGateway")
	if gateway != null and gateway.has_method("begin_session") and not authority_prepared:
		gateway.call("begin_session", multiplayer)
	var network := tree.root.get_node_or_null("NetworkManager")
	if network != null:
		if multiplayer and network.has_method("begin_multiplayer_session"):
			network.call("begin_multiplayer_session")
		elif network.has_method("end_multiplayer_session"):
			network.call("end_multiplayer_session", true)
	var menu := tree.root.get_node_or_null("GameMenu")
	if menu != null and menu.has_method("set_gameplay_hud_visible"):
		menu.set_gameplay_hud_visible(true)
	_go_via_loading_gate(tree, WORLD_SCENE, "Preparing voyage…")


static func return_to_title(tree: SceneTree) -> void:
	var session := tree.root.get_node_or_null("PlayerSession")
	if session != null and session.has_method("save_now"):
		session.call("save_now")
	# The title has no active persistence target. A roster selection remains
	# UI-only until Sail explicitly loads that captain.
	LocalCaptainStore.clear_active()
	var network := tree.root.get_node_or_null("NetworkManager")
	if network != null and network.has_method("end_multiplayer_session"):
		network.call("end_multiplayer_session", true)
	var gateway := tree.root.get_node_or_null("WorldGateway")
	if gateway != null and gateway.has_method("stop_session"):
		gateway.call("stop_session")
	var config := tree.root.get_node_or_null("ServerConfig")
	if config != null:
		config.set("is_multiplayer_mode", false)
	var menu := tree.root.get_node_or_null("GameMenu")
	if menu != null and menu.has_method("set_gameplay_hud_visible"):
		menu.set_gameplay_hud_visible(false)
	_go_via_loading_gate(tree, MAIN_MENU_SCENE, "Returning to harbour…")


static func _go_via_loading_gate(tree: SceneTree, scene_path: String, status: String) -> void:
	var gate := tree.root.get_node_or_null("LoadingGate")
	if gate != null and gate.has_method("begin"):
		gate.call("begin", scene_path, status)
	else:
		tree.change_scene_to_file(scene_path)
