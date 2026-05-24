@tool
class_name World
extends Node3D

## Main scene root. Generates port definitions from seed, expands them to PortData,
## eagerly loads the home port, and lazy-loads all others via ProximityLoader.

const PLAYER_SCENE := preload("res://scenes/shared/player.tscn")
const WORLD_RENDERER_SCRIPT := preload("res://scripts/world/world_renderer.gd")
const ATMOSPHERIC_SCRIPT := preload("res://scripts/world/atmospheric_effects.gd")

const LOAD_RADIUS           : float = 1500.0
const EDITOR_PREVIEW_RADIUS : float = 600.0
const EDITOR_PREVIEW_MAX    : int   = 6
const MIN_PORT_SEPARATION   : float = 600.0
const SCATTER_RADIUS_PER_PORT : float = 200.0

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

@export var world_seed:   int = 42:
	set(v): world_seed = v; if is_inside_tree(): _rebuild()

@export var port_count: int = 35:
	set(v): port_count = v; if is_inside_tree(): _rebuild()


func _ready() -> void:
	call_deferred("_rebuild")


func _rebuild() -> void:
	var t := _telemetry()
	var world_handle: int = t.mark_load_event("world.init") if t != null else 0

	for child in get_children():
		if Engine.is_editor_hint():
			child.free()
		else:
			child.queue_free()

	_add_world_renderer()

	var defs := _generate_definitions()

	if not Engine.is_editor_hint():
		var positions: Array[Vector3] = []
		var islands  : Array          = []
		for d in defs:
			positions.append(d.world_position)
			var data := PortExpander.expand(d, world_seed)
			var land_pad := IslandMeshBuilder.MARGIN + IslandMeshBuilder.AMPLITUDE
			const PLOT_DEPTH_M := 140.0
			islands.append({
				"center": d.world_position,
				"half_x": data.island_width * 0.5 + land_pad,
				"half_z": PLOT_DEPTH_M * 0.5 + land_pad,
				"rotation_y": data.rotation_y,
			})
		var lf_handle: int = t.mark_load_event("land_field.bake") if t != null else 0
		LandField.initialize(islands)
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
		_add_atmospheric_effects()
		_setup_ports(defs)
		call_deferred("_spawn_player")

	if t != null:
		t.end_load_event(world_handle)


## Cached lookup so we don't pay the `/root/Telemetry` resolve cost on
## every load-event call. Returns null in editor / tool runs that don't
## boot autoloads.
func _telemetry() -> Node:
	return get_node_or_null("/root/Telemetry")


func _add_world_renderer() -> void:
	var renderer := WORLD_RENDERER_SCRIPT.new() as Node3D
	renderer.name = "WorldRenderer"
	add_child(renderer)


func _add_atmospheric_effects() -> void:
	var fx := ATMOSPHERIC_SCRIPT.new() as Node3D
	fx.name = "AtmosphericEffects"
	add_child(fx)


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
	var defs: Array[PortDefinition] = []

	var home            := PortDefinition.new()
	home.port_id        = "port-home"
	home.display_name   = "Haugsvik"
	home.world_position = Vector3.ZERO
	home.size           = 1
	defs.append(home)

	var rng       := RandomNumberGenerator.new()
	rng.seed      = world_seed
	var scatter_r := float(port_count) * SCATTER_RADIUS_PER_PORT
	var placed    : Array[Vector3] = [Vector3.ZERO]
	var i         := 0
	var tries     := 0

	while i < port_count and tries < port_count * 500:
		tries += 1
		var angle     := rng.randf() * TAU
		var dist      := sqrt(rng.randf()) * scatter_r
		var candidate := Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)

		var too_close := false
		for existing in placed:
			if candidate.distance_to(existing) < MIN_PORT_SEPARATION:
				too_close = true
				break
		if too_close:
			continue

		var p            := PortDefinition.new()
		p.port_id        = "port-%d" % (i + 1)
		p.display_name   = PORT_NAMES[i % PORT_NAMES.size()]
		p.world_position = candidate
		p.size           = rng.randi() % 5
		defs.append(p)
		placed.append(candidate)
		i += 1

	return defs


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
