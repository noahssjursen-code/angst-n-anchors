@tool
class_name World
extends Node3D

## Main scene root. Generates port definitions from seed, expands them to PortData,
## eagerly loads the home port, and lazy-loads all others via ProximityLoader.

## Fired once the first voyage boot finishes (layout, home port, player spawn,
## and the nearby terrain collision/visual ring). Far LOD streaming may continue.
signal boot_finished

const PLAYER_SCENE := preload("res://scenes/shared/player.tscn")
const WORLD_RENDERER_SCRIPT := preload("res://scripts/world/world_renderer.gd")
const ATMOSPHERIC_SCRIPT := preload("res://scripts/world/atmospheric_effects.gd")
const WORLD_LAYOUT_GENERATOR := preload("res://scripts/world/world_layout_generator.gd")
const WORLD_CONFIG := preload("res://scripts/world/world_config.gd")
const COASTAL_PORT_PLACER := preload("res://scripts/world/coastal_port_placer.gd")
const WORLD_TERRAIN_STREAMER := preload("res://scripts/world/world_terrain_streamer.gd")
const WORLD_FOREST_STREAMER := preload("res://scripts/world/world_forest_streamer.gd")
const IMPOSTOR_SERVICE := preload("res://scripts/core/impostor_service.gd")
const SHIPPING_LANE_NETWORK_BUILDER := preload("res://scripts/traffic/shipping_lane_network_builder.gd")
const SHIPPING_LANE_DEBUG_DRAW := preload("res://scripts/traffic/shipping_lane_debug_draw.gd")

## Match terrain mid LOD (~4.8 km) so coasts are not empty until the last moment.
const LOAD_RADIUS           : float = 4800.0
const EDITOR_PREVIEW_RADIUS : float = 600.0
const EDITOR_PREVIEW_MAX    : int   = 6
const WORLD_GENERATION_VERSION := WORLD_LAYOUT_GENERATOR.GENERATION_VERSION
const WEATHER_GENERATION_VERSION := 3

const PORT_NAMES : Array[String] = [
	"Holmvik",  "Sandvær",  "Bergnes",  "Kloven",
	"Strandnes","Kvamsvik", "Bremsund", "Tysneset",
	"Fjelltun", "Grønnvik", "Harberg",  "Innvær",
	"Jørvika",  "Kalvøy",   "Lyngnes",  "Molvær",
	"Nordheim", "Ostervik", "Raudvik",  "Solberg",
	"Torsberg", "Urvik",    "Vargnes",  "Øyangen",
	"Bakkevær", "Dalsøy",   "Egersund", "Fossberg",
	"Grindøy",  "Hammnes",  "Isfjord",  "Kopervær",
	"Langøy",   "Midtvik",  "Nessund",  "Ålvær",
	"Ravnheim", "Skarvøy",  "Tjuvnes",  "Ulvvær",
]

var _ready_complete := false
var _layout_checksum := ""
var _world_layout: WorldLayout
var _layout_generation_usec := 0
var _requested_generation_version := WORLD_GENERATION_VERSION
var _requested_weather_generation_version := WEATHER_GENERATION_VERSION
var _terrain_streamer: WorldTerrainStreamer
var _forest_streamer: WorldForestStreamer
var _shipping_lane_network: ShippingLaneNetwork
var _shipping_lane_generation_usec := 0

@export var world_seed:   int = 42:
	set(v): world_seed = v; if _ready_complete and is_inside_tree(): _rebuild()

@export var port_count: int = 35:
	set(v): port_count = v; if _ready_complete and is_inside_tree(): _rebuild()

## Square world extent in metres (10–120 km). Session/server may override via GameSettings.
@export_range(10000.0, 120000.0, 1000.0) var world_size_m: float = 40000.0:
	set(v):
		world_size_m = WORLD_CONFIG.validate_size_m(v)
		if _ready_complete and is_inside_tree():
			_rebuild()


func _ready() -> void:
	if not Engine.is_editor_hint():
		add_to_group("world")
		var settings := get_node_or_null("/root/GameSettings")
		if settings != null:
			world_seed = int(settings.get("map_generation_seed"))
			_requested_generation_version = int(settings.get("map_generation_version"))
			_requested_weather_generation_version = int(settings.get("weather_generation_version"))
			if settings.get("map_world_size_m") != null:
				world_size_m = float(settings.get("map_world_size_m"))
	_ready_complete = true
	call_deferred("_rebuild")


func _rebuild() -> void:
	PortDataCache.clear()
	BuildingCache.clear()
	LandDecorCache.clear()
	IMPOSTOR_SERVICE.clear()
	MeshBuilder.clear_material_cache()
	WORLD_LAYOUT_GENERATOR.clear_cache()
	## PortCatalog is the live world's directory. Discard stale records from a
	## previous world or any presentation scene before generating contracts.
	if not Engine.is_editor_hint():
		var port_catalog := get_node_or_null("/root/PortCatalog")
		if port_catalog != null:
			port_catalog.clear()
	if _requested_generation_version != WORLD_GENERATION_VERSION:
		push_warning(
			"World: generation version mismatch (requested %d, runtime %d) — regenerating"
			% [_requested_generation_version, WORLD_GENERATION_VERSION]
		)
		_requested_generation_version = WORLD_GENERATION_VERSION
	if _requested_weather_generation_version != WEATHER_GENERATION_VERSION:
		push_error(
			"World: weather generation version mismatch (requested %d, runtime %d)"
			% [_requested_weather_generation_version, WEATHER_GENERATION_VERSION]
		)
		return
	var t := _telemetry()
	var world_handle: int = t.mark_load_event("world.init") if t != null else 0

	for child in get_children():
		if Engine.is_editor_hint():
			child.free()
		else:
			child.queue_free()

	var layout_handle: int = t.mark_load_event("world.layout") if t != null else 0
	var layout_started := Time.get_ticks_usec()
	_world_layout = WORLD_LAYOUT_GENERATOR.generate(
		world_seed,
		WORLD_CONFIG.ARCHETYPE_PATH,
		world_size_m,
	)
	_layout_generation_usec = Time.get_ticks_usec() - layout_started
	_layout_checksum = _world_layout.layout_checksum
	if t != null:
		t.end_load_event(layout_handle)
	var settings := get_node_or_null("/root/GameSettings")
	if settings != null and settings.has_method("set_world_generation_context"):
		settings.call(
			"set_world_generation_context",
			world_seed,
			WORLD_GENERATION_VERSION,
			_layout_checksum,
			WEATHER_GENERATION_VERSION,
			world_size_m,
		)

	_add_world_renderer()
	var defs := _generate_definitions()

	if not Engine.is_editor_hint():
		var positions: Array[Vector3] = []
		for d in defs:
			positions.append(d.world_position)
		var lf_handle: int = t.mark_load_event("land_field.bake") if t != null else 0
		LandField.initialize(_world_layout)
		if t != null:
			t.end_load_event(lf_handle)
		WorldWeather.initialize(world_seed, positions, _requested_weather_generation_version)
		FishingField.initialize(world_seed)

	if Engine.is_editor_hint() and get_tree() != null:
		_add_editor_preview(defs)
		var esc := get_tree().edited_scene_root
		if esc != null:
			for child in get_children():
				_own_subtree(child)
	else:
		var flatten_zones := WORLD_TERRAIN_STREAMER.make_flatten_zones(
			defs, 0.0, world_seed, _world_layout
		)
		ForestField.initialize(_world_layout, world_seed, flatten_zones)
		_add_terrain_streamer(defs)
		_add_forest_streamer(flatten_zones)
		_add_atmospheric_effects()
		_setup_ports(defs)
		_bake_berth_lanes(t, defs)
		_build_shipping_lane_network(t, defs)
		call_deferred("_spawn_player")

	if t != null:
		t.end_load_event(world_handle)


## Cached lookup so we don't pay the `/root/Telemetry` resolve cost on
## every load-event call. Returns null in editor / tool runs that don't
## boot autoloads.
func _telemetry() -> Node:
	return get_node_or_null("/root/Telemetry")


func get_world_context() -> Dictionary:
	var preset := "standard"
	var settings := get_node_or_null("/root/GameSettings")
	if settings != null:
		preset = str(settings.get("map_world_preset"))
	return {
		"seed": world_seed,
		"world_size_m": world_size_m,
		"world_preset": preset,
		"generation_version": WORLD_GENERATION_VERSION,
		"weather_generation_version": WEATHER_GENERATION_VERSION,
		"layout_checksum": _layout_checksum,
	}


func get_world_layout() -> WorldLayout:
	return _world_layout


func get_world_generation_debug_stats() -> Dictionary:
	var stats := {
		"seed": world_seed,
		"version": WORLD_GENERATION_VERSION,
		"checksum": _layout_checksum,
		"generation_usec": _layout_generation_usec,
		"raster_resolution": _world_layout.raster_resolution if _world_layout != null else 0,
		"contour_segments": _world_layout.coastline_contours.size() if _world_layout != null else 0,
	}
	if _shipping_lane_network != null:
		var lane_stats := _shipping_lane_network.summary()
		lane_stats["generation_usec"] = _shipping_lane_generation_usec
		stats["shipping_lanes"] = lane_stats
	return stats


func get_shipping_lane_network() -> ShippingLaneNetwork:
	return _shipping_lane_network


func _build_shipping_lane_network(t: Node, defs: Array[PortDefinition]) -> void:
	var handle: int = t.mark_load_event("shipping_lanes.bake") if t != null else 0
	var started_usec := Time.get_ticks_usec()
	var ports: Array[PortData] = []
	for definition in defs:
		ports.append(PortExpander.expand(definition, world_seed, _world_layout))
	var builder := SHIPPING_LANE_NETWORK_BUILDER.new() as ShippingLaneNetworkBuilder
	_shipping_lane_network = builder.build(_world_layout, ports)
	_shipping_lane_generation_usec = Time.get_ticks_usec() - started_usec
	var debug_draw := SHIPPING_LANE_DEBUG_DRAW.new() as ShippingLaneDebugDraw
	debug_draw.name = "ShippingLaneDebugDraw"
	debug_draw.configure(_shipping_lane_network)
	add_child(debug_draw)
	var summary := _shipping_lane_network.summary()
	print(
		"Shipping lanes: %d nodes, %d edges, %d blocks, %d signals, %d queue slots, %d berths, %d passing zones, %d errors"
		% [
			int(summary.get("nodes", 0)), int(summary.get("edges", 0)),
			int(summary.get("blocks", 0)), int(summary.get("signals", 0)),
			int(summary.get("port_queue_slots", 0)), int(summary.get("berth_tokens", 0)),
			int(summary.get("passing_zones", 0)), int(summary.get("errors", 0)),
		]
	)
	if t != null:
		t.end_load_event(handle)


func _bake_berth_lanes(t: Node, defs: Array[PortDefinition]) -> void:
	var lane_handle: int = t.mark_load_event("berth_lanes.bake") if t != null else 0
	BerthApproachLanes.bake_all_ports(defs, world_seed, _world_layout)
	call_deferred("_refresh_berth_lane_debug")
	if t != null:
		t.end_load_event(lane_handle)


func _refresh_berth_lane_debug() -> void:
	_ensure_lane_debug_draw()
	BerthApproachLanesDebugDraw.refresh_if_enabled(get_tree())


func _ensure_lane_debug_draw() -> void:
	var tree := get_tree()
	if tree == null:
		return
	if tree.get_first_node_in_group("berth_lane_debug") != null:
		return
	var draw := BerthApproachLanesDebugDraw.new()
	draw.name = "BerthApproachLanesDebugDraw"
	add_child(draw)


func _add_world_renderer() -> void:
	var renderer := WORLD_RENDERER_SCRIPT.new() as Node3D
	renderer.name = "WorldRenderer"
	add_child(renderer)


func _add_atmospheric_effects() -> void:
	var fx := ATMOSPHERIC_SCRIPT.new() as Node3D
	fx.name = "AtmosphericEffects"
	add_child(fx)


func _add_terrain_streamer(defs: Array[PortDefinition]) -> void:
	_terrain_streamer = WORLD_TERRAIN_STREAMER.new() as WorldTerrainStreamer
	_terrain_streamer.name = "WorldTerrainStreamer"
	_terrain_streamer.add_to_group("world_terrain_streamer")
	add_child(_terrain_streamer)
	_terrain_streamer.configure(_world_layout, defs)


func _add_forest_streamer(flatten_zones: Array) -> void:
	_forest_streamer = WORLD_FOREST_STREAMER.new() as WorldForestStreamer
	_forest_streamer.name = "WorldForestStreamer"
	_forest_streamer.add_to_group("world_forest_streamer")
	add_child(_forest_streamer)
	_forest_streamer.configure(_world_layout, flatten_zones)


func _add_editor_preview(defs: Array[PortDefinition]) -> void:
	var count := 0
	for def in defs:
		if count >= EDITOR_PREVIEW_MAX:
			break
		if def.world_position.length() > EDITOR_PREVIEW_RADIUS:
			continue
		var data := PortExpander.expand(def, world_seed, _world_layout)
		var plot  := PortPlot.new()
		plot.name = "Port_%s" % def.port_id
		plot.configure(data)
		add_child(plot)
		plot.position = def.world_position
		count += 1


func _setup_ports(defs: Array[PortDefinition]) -> void:
	var loader  := ProximityLoader.new()
	loader.name = "ProximityLoader"
	add_child(loader)

	var port_proximity := preload("res://scripts/world/port_proximity.gd").new()
	port_proximity.name = "PortProximity"
	add_child(port_proximity)

	var registry := get_node_or_null("/root/PortCatalog")
	var home_port_id := "port-home"
	var session := get_node_or_null("/root/PlayerSession")
	if session != null and session.get("data") != null:
		var preferred := str(session.data.home_port_id).strip_edges()
		if not preferred.is_empty():
			home_port_id = preferred

	for i in range(defs.size()):
		var def  := defs[i]
		var data := PortExpander.expand(def, world_seed, _world_layout)

		if registry != null:
			registry.register_port(
				data.port_id, data.display_name, data.world_position,
				Vector3(INF, INF, INF),
				data.commodity_export, data.commodity_imports,
				data.island_width,
				data.plot_depth,
				data.layout_seed,
				data.population, data.features, data.rotation_y,
				data.berth_count, data.size,
			)

		var is_home := data.port_id == home_port_id or (i == 0 and home_port_id == "port-home")
		if is_home and get_node_or_null("HomePort") == null:
			# Captain home quay: always present so spawn/teleport have a berth.
			var plot := PortPlot.new()
			plot.name = "HomePort"
			plot.configure(data)
			add_child(plot)
			plot.global_position = def.world_position
		else:
			var captured := data
			loader.register(
				def.world_position,
				func() -> Node3D:
					var plot := PortPlot.new()
					plot.configure(captured)
					return plot,
				LOAD_RADIUS,
				data.port_id,
			)

	# Fallback if the saved home port id no longer exists in this seed.
	if get_node_or_null("HomePort") == null and not defs.is_empty():
		var fallback := PortExpander.expand(defs[0], world_seed, _world_layout)
		var plot := PortPlot.new()
		plot.name = "HomePort"
		plot.configure(fallback)
		add_child(plot)
		plot.global_position = defs[0].world_position
		if session != null and session.get("data") != null:
			session.data.home_port_id = fallback.port_id

	var freight := get_node_or_null("/root/FreightService")
	if freight != null and freight.has_method("prune_unknown_ports"):
		freight.prune_unknown_ports()



func _generate_definitions() -> Array[PortDefinition]:
	return COASTAL_PORT_PLACER.place_ports(
		_world_layout,
		maxi(port_count, 1),
		PackedStringArray(PORT_NAMES),
	)


func _spawn_player() -> void:
	# PortPlot builds its graph visualizer deferred; wait for foundation /
	# asphalt StaticBody colliders before raycasting spawn.
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().physics_frame

	var home      := get_node_or_null("HomePort") as PortPlot
	var spawn_pos := _safe_spawn_position(home)

	var player      := PLAYER_SCENE.instantiate()
	player.position = spawn_pos
	add_child(player)

	# Phase 4 — restore per-player state once the world has spawned.
	# LocalPlayerView reapplies world-clock + contract counts immediately
	# and defers ship-pose restore until the next frame so the spawn-side
	# flow has time to instantiate any active vessel.
	var view := get_node_or_null("/root/LocalPlayerView")
	if view != null and view.has_method("restore_player_state"):
		view.call("restore_player_state")

	# Phase 11 — fire the welcome hint once per captain after spawn settles.
	var tut := get_node_or_null("/root/Tutorial")
	if tut != null:
		tut.call_deferred("show", "welcome")

	# Hold LoadingGate until the spawn/collision terrain ring is built so land
	# does not keep popping in after the overlay dismisses.
	if _terrain_streamer != null:
		await _await_spawn_terrain(spawn_pos)

	# Bake far-LOD impostors while the gate is still up (buildings + village houses).
	await _warm_impostors()

	boot_finished.emit()
	var gate := get_node_or_null("/root/LoadingGate")
	if gate != null and gate.has_method("notify_world_ready"):
		gate.call("notify_world_ready")


func _warm_impostors() -> void:
	var gate := get_node_or_null("/root/LoadingGate")
	var status_cb := Callable()
	if gate != null and gate.has_method("set_detail"):
		status_cb = gate.set_detail
	elif gate != null and gate.has_method("notify_status"):
		status_cb = gate.notify_status
	await IMPOSTOR_SERVICE.warm_catalog(self, status_cb)


func _await_spawn_terrain(spawn_pos: Vector3) -> void:
	if _terrain_streamer == null:
		return
	_terrain_streamer.begin_boot_priority(spawn_pos)
	var deadline_ms := Time.get_ticks_msec() + 80000
	while not _terrain_streamer.is_ready_around(spawn_pos):
		if Time.get_ticks_msec() >= deadline_ms:
			push_warning("World: spawn terrain ring timed out; continuing boot")
			break
		await get_tree().process_frame
	_terrain_streamer.end_boot_priority()


## Resolve a safe spawn position for the player. Prefers HomePort.get_spawn_position()
## (which returns the dock's spawn anchor), but validates the result against the
## physics world to make sure we're not dropping the player into water or inside
## a collider. Falls back to a high-and-dry default so the player doesn't drown
## on the very first frame if port generation produced something unexpected.
func _safe_spawn_position(home: PortPlot) -> Vector3:
	var candidate := Vector3.ZERO
	if home != null:
		candidate = home.get_spawn_position()
	else:
		push_warning("World: home port missing at spawn time; falling back")

	# Clamp Y above the water level so we never spawn beneath the surface.
	var water_y := WaveSurface.WATER_LEVEL
	if candidate.y < water_y + 1.0:
		candidate.y = water_y + 1.5

	# Cast downward for foundation / asphalt / terrain. Probe nearby if the
	# first ray misses (spawn can sit just past an apron edge).
	var space := get_world_3d().direct_space_state
	if space != null:
		var probes: Array[Vector3] = [
			candidate,
			candidate + Vector3(0.0, 0.0, 6.0),
			candidate + Vector3(0.0, 0.0, -6.0),
			candidate + Vector3(6.0, 0.0, 0.0),
			candidate + Vector3(-6.0, 0.0, 0.0),
			candidate + Vector3(0.0, 0.0, 12.0),
		]
		var grounded := false
		for probe in probes:
			var from := probe + Vector3.UP * 8.0
			var to := probe + Vector3.DOWN * 24.0
			var q := PhysicsRayQueryParameters3D.create(from, to)
			q.collide_with_areas = false
			q.collision_mask = 1
			var hit := space.intersect_ray(q)
			if hit.is_empty():
				continue
			candidate = (hit["position"] as Vector3) + Vector3.UP * 0.6
			grounded = true
			break
		if not grounded:
			push_warning("World: no ground beneath spawn at %s; raising" % candidate)
			candidate.y = water_y + 6.0

	return candidate


## Returns the island's nominal half-width (radius before LandField padding).
func _island_radius_for_size(size: int) -> float:
	return PortSizing.island_width_m(size) * 0.5


func _own_subtree(node: Node) -> void:
	if get_tree() == null:
		return
	var esc := get_tree().edited_scene_root
	if esc == null:
		return
	node.owner = esc
	for child in node.get_children():
		_own_subtree(child)
