@tool
class_name World
extends Node3D

## Main scene root. Generates port definitions from seed, expands them to PortData,
## eagerly loads the home port, and lazy-loads all others via ProximityLoader.

const PLAYER_SCENE := preload("res://scenes/shared/player.tscn")
const WORLD_RENDERER_SCRIPT := preload("res://scripts/world/world_renderer.gd")
const ATMOSPHERIC_SCRIPT := preload("res://scripts/world/atmospheric_effects.gd")
const WORLD_LAYOUT_GENERATOR := preload("res://scripts/world/world_layout_generator.gd")
const COASTAL_PORT_PLACER := preload("res://scripts/world/coastal_port_placer.gd")
const WORLD_TERRAIN_STREAMER := preload("res://scripts/world/world_terrain_streamer.gd")
const WORLD_FOREST_STREAMER := preload("res://scripts/world/world_forest_streamer.gd")

const LOAD_RADIUS           : float = 1500.0
const EDITOR_PREVIEW_RADIUS : float = 600.0
const EDITOR_PREVIEW_MAX    : int   = 6
const WORLD_GENERATION_VERSION := WORLD_LAYOUT_GENERATOR.GENERATION_VERSION

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
var _terrain_streamer: WorldTerrainStreamer
var _forest_streamer: WorldForestStreamer

@export var world_seed:   int = 42:
	set(v): world_seed = v; if _ready_complete and is_inside_tree(): _rebuild()

@export var port_count: int = 35:
	set(v): port_count = v; if _ready_complete and is_inside_tree(): _rebuild()


func _ready() -> void:
	if not Engine.is_editor_hint():
		add_to_group("world")
		var settings := get_node_or_null("/root/GameSettings")
		if settings != null:
			world_seed = int(settings.get("map_generation_seed"))
			_requested_generation_version = int(settings.get("map_generation_version"))
	_ready_complete = true
	call_deferred("_rebuild")


func _rebuild() -> void:
	if _requested_generation_version != WORLD_GENERATION_VERSION:
		push_error(
			"World: generation version mismatch (requested %d, runtime %d)"
			% [_requested_generation_version, WORLD_GENERATION_VERSION]
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
	_world_layout = WORLD_LAYOUT_GENERATOR.generate(world_seed)
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
		WorldWeather.initialize(world_seed, positions)
		FishingField.initialize(world_seed)

	if Engine.is_editor_hint() and get_tree() != null:
		_add_editor_preview(defs)
		var esc := get_tree().edited_scene_root
		if esc != null:
			for child in get_children():
				_own_subtree(child)
	else:
		var flatten_zones := WORLD_TERRAIN_STREAMER.make_flatten_zones(defs, 0.0)
		ForestField.initialize(_world_layout, world_seed, flatten_zones)
		_add_terrain_streamer(defs)
		_add_forest_streamer(flatten_zones)
		_add_atmospheric_effects()
		_setup_ports(defs)
		_bake_berth_lanes(t, defs)
		call_deferred("_spawn_player")

	if t != null:
		t.end_load_event(world_handle)


## Cached lookup so we don't pay the `/root/Telemetry` resolve cost on
## every load-event call. Returns null in editor / tool runs that don't
## boot autoloads.
func _telemetry() -> Node:
	return get_node_or_null("/root/Telemetry")


func get_world_context() -> Dictionary:
	return {
		"seed": world_seed,
		"generation_version": WORLD_GENERATION_VERSION,
		"layout_checksum": _layout_checksum,
	}


func get_world_layout() -> WorldLayout:
	return _world_layout


func get_world_generation_debug_stats() -> Dictionary:
	return {
		"seed": world_seed,
		"version": WORLD_GENERATION_VERSION,
		"checksum": _layout_checksum,
		"generation_usec": _layout_generation_usec,
		"raster_resolution": _world_layout.raster_resolution if _world_layout != null else 0,
		"contour_segments": _world_layout.coastline_contours.size() if _world_layout != null else 0,
	}


func _bake_berth_lanes(t: Node, defs: Array[PortDefinition]) -> void:
	var lane_handle: int = t.mark_load_event("berth_lanes.bake") if t != null else 0
	BerthApproachLanes.bake_all_ports(defs, world_seed)
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
		var data := PortExpander.expand(def, world_seed)
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

	var registry := get_node_or_null("/root/ContractRegistry")

	for i in range(defs.size()):
		var def  := defs[i]
		var data := PortExpander.expand(def, world_seed)

		if registry != null:
			registry.register_port(
				data.port_id, data.display_name, data.world_position,
				Vector3(INF, INF, INF),
				data.commodity_export, data.commodity_imports,
				data.island_width, 140.0, data.layout_seed,
				data.population, data.features, data.rotation_y,
				data.berth_count, data.size,
			)

		if i == 0:
			# Home port: always present, added directly so spawn position is available.
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


func _generate_definitions() -> Array[PortDefinition]:
	return COASTAL_PORT_PLACER.place_ports(
		_world_layout,
		maxi(port_count, 1),
		PackedStringArray(PORT_NAMES),
	)


func _spawn_player() -> void:
	# PortPlot._rebuild and PortFacilities._rebuild are both deferred.
	# Two frames is enough for that chain to settle before we query spawn_pos.
	await get_tree().process_frame
	await get_tree().process_frame

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

	# Cast a short ray downward at the candidate to ensure there's ground
	# (the dock plate or terrain) beneath us. If not, raise to a safe height
	# above water so the player falls onto whatever's there.
	var space := get_world_3d().direct_space_state
	if space != null:
		var from := candidate + Vector3.UP * 5.0
		var to   := candidate + Vector3.DOWN * 20.0
		var q    := PhysicsRayQueryParameters3D.create(from, to)
		q.collide_with_areas = false
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			push_warning("World: no ground beneath spawn at %s; raising" % candidate)
			candidate.y = water_y + 6.0
		else:
			# Hit the deck/terrain — snap to slightly above it.
			candidate = (hit["position"] as Vector3) + Vector3.UP * 0.6

	return candidate


## Mirrors PortExpander.ISLAND_WIDTH_BY_SIZE so LandField can be seeded without
## paying for a full PortExpander.expand() round-trip per island at init time.
## Returns the island's nominal half-width (radius before LandField padding).
func _island_radius_for_size(size: int) -> float:
	var size_clamped := clampi(size, 0, 4)
	const HALF_WIDTHS := [30.0, 40.0, 60.0, 100.0, 170.0]  # ISLAND_WIDTH_BY_SIZE * 0.5
	return HALF_WIDTHS[size_clamped]


func _own_subtree(node: Node) -> void:
	if get_tree() == null:
		return
	var esc := get_tree().edited_scene_root
	if esc == null:
		return
	node.owner = esc
	for child in node.get_children():
		_own_subtree(child)
