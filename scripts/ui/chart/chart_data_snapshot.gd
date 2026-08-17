class_name ChartDataSnapshot
extends RefCounted

## Immutable input for a chart session. Rendering never discovers geography or
## ports through the scene tree and preview mode never mutates PortCatalog.

const GENERATOR := preload("res://scripts/world/world_layout_generator.gd")
const PLACER := preload("res://scripts/world/coastal_port_placer.gd")

const PORT_NAMES: Array[String] = [
	"Holmvik", "Sandvær", "Bergnes", "Kloven",
	"Strandnes", "Kvamsvik", "Bremsund", "Tysneset",
	"Fjelltun", "Grønnvik", "Harberg", "Innvær",
	"Jørvika", "Kalvøy", "Lyngnes", "Molvær",
	"Nordheim", "Ostervik", "Raudvik", "Solberg",
	"Torsberg", "Urvik", "Vargnes", "Øyangen",
	"Bakkevær", "Dalsøy", "Egersund", "Fossberg",
	"Grindøy", "Hammnes", "Isfjord", "Kopervær",
	"Langøy", "Midtvik", "Nessund", "Ålvær",
	"Ravnheim", "Skarvøy", "Tjuvnes", "Ulvvær",
]

var layout: WorldLayout
var shipping_lane_network: ShippingLaneNetwork
var traffic_source: Node
var ports: Array[Dictionary] = []
var world_seed := 42
var generation_version := 0
var layout_checksum := ""
var world_size_m := 40000.0
var world_preset := "standard"
var preview := false

var _port_by_id: Dictionary = {}


static func from_live_tree(tree: SceneTree) -> ChartDataSnapshot:
	var out := ChartDataSnapshot.new()
	if tree == null:
		return out
	var world := tree.get_first_node_in_group("world")
	if world != null and world.has_method("get_world_layout"):
		out.layout = world.call("get_world_layout") as WorldLayout
	if world != null and world.has_method("get_shipping_lane_network"):
		out.shipping_lane_network = world.call("get_shipping_lane_network") as ShippingLaneNetwork
	if world != null and world.has_method("get_world_traffic_service"):
		out.traffic_source = world.call("get_world_traffic_service") as Node
	if world != null and world.has_method("get_world_context"):
		var context := world.call("get_world_context") as Dictionary
		out.world_seed = int(context.get("seed", 42))
		out.generation_version = int(context.get("generation_version", 0))
		out.layout_checksum = str(context.get("layout_checksum", ""))
		out.world_size_m = float(context.get("world_size_m", 40000.0))
		out.world_preset = str(context.get("world_preset", "standard"))
	var registry := tree.root.get_node_or_null("PortCatalog")
	if registry != null:
		for id_raw in registry.call("get_port_ids"):
			var info := (registry.call("get_port_info", str(id_raw)) as Dictionary).duplicate(true)
			out.ports.append(info)
	out._index_ports()
	## Gameplay chart path — keep field APIs aligned with the live world.
	if out.layout != null:
		LandField.initialize(out.layout)
		FishingField.initialize(out.world_seed)
		WeatherField.world_seed = out.world_seed
	return out


static func for_preview(
		seed: int,
		port_count: int = 35,
		requested_world_size_m: float = 40000.0,
		requested_world_preset: String = "standard",
) -> ChartDataSnapshot:
	var out := ChartDataSnapshot.new()
	out.preview = true
	out.world_seed = seed
	out.generation_version = int(GENERATOR.GENERATION_VERSION)
	out.world_size_m = requested_world_size_m
	out.world_preset = requested_world_preset
	out.layout = GENERATOR.generate(
		seed,
		GENERATOR.DEFAULT_CONFIG_PATH,
		requested_world_size_m,
	)
	if out.layout != null:
		out.world_size_m = out.layout.world_size_m
	out.layout_checksum = str(out.layout.layout_checksum) if out.layout != null else ""
	if out.layout == null:
		return out
	var definitions: Array = PLACER.place_ports(
		out.layout,
		maxi(port_count, 1),
		PackedStringArray(WorldPortNames.NAMES),
	)
	## BAKED BEFORE THE PORT SUMMARIES, AND THAT ORDER IS LOAD-BEARING — 2026-08-17.
	##
	## These four lines used to sit after the loop below. `PortFishingService
	## .is_eligible` samples `FishingField`, whose `open_water` term calls
	## `LandField.distance_to_land`, and `LandField` is a GLOBAL baked from a
	## WorldLayout — so summarising ports before baking it asked the fishing
	## question of whatever world was baked last. Measured over six seeds, 210
	## ports (`tests/_fish_landing_realization_probe.gd`): baked from this world's
	## layout, 137 ports advertise a fish landing; with an empty field, 139; with
	## ANOTHER world's field, **80**. The second regime is a first preview in a
	## fresh process and the third is every preview after it — a re-rolled seed, or
	## the menu re-entered after playing — so the FACILITIES line a player read
	## depended on how many times they had pressed re-roll.
	##
	## `world.gd:157` bakes the land field before it expands any port. This now
	## matches, which is what makes the preview's answer the live world's answer.
	# These are deterministic field APIs, not world scene construction.
	LandField.initialize(out.layout)
	FishingField.initialize(seed)
	WeatherField.world_seed = seed
	WeatherFrontField.initialize(seed)
	for definition in definitions:
		## Lightweight trade/size summary — full PortLayoutGenerator is too
		## expensive for the captain home-port picker (dozens of ports) and this
		## call avoids it for everything EXCEPT `has_fish_landing`, which is
		## realized infrastructure and has exactly one honest derivation: the berth
		## plan in the port's layout graph. The layout is handed over so that
		## expansion takes the same inputs the world's own `expand` takes — measured
		## as reaching the generator (the basin's arm cap moves at 70 of 70 ports)
		## but NOT as changing the fish-landing verdict on any of them, so nothing in
		## the gate would catch this argument going missing. See
		## `PortExpander.realized_fish_landing`.
		##
		## NOT MEASURED: this leaves 35 `PortData` per preview in the static
		## `PortDataCache`, which nothing clears until `world.gd._rebuild`. A player
		## who re-rolls the seed twenty times in the menu accumulates twenty worlds'
		## worth. `ChartHarbourPlan.for_port` already cached the same way, one port at
		## a time; this makes it every port, every preview.
		out.ports.append(PortExpander.chart_summary(definition, seed, out.layout))
	out._index_ports()
	return out


func is_valid() -> bool:
	return layout != null and not ports.is_empty()


func port_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for port in ports:
		ids.append(str(port.get("id", "")))
	return ids


func port_info(port_id: String) -> Dictionary:
	return (_port_by_id.get(port_id, {}) as Dictionary)


func port_position(port_id: String) -> Vector3:
	var info := port_info(port_id)
	return info.get("position", Vector3(INF, INF, INF)) as Vector3


func port_positions() -> Array[Vector3]:
	var result: Array[Vector3] = []
	for port in ports:
		var position := port.get("position", Vector3(INF, INF, INF)) as Vector3
		if position.is_finite():
			result.append(position)
	return result


func world_context() -> Dictionary:
	return {
		"seed": world_seed,
		"world_size_m": world_size_m,
		"world_preset": world_preset,
		"generation_version": generation_version,
		"layout_checksum": layout_checksum,
	}


func _index_ports() -> void:
	_port_by_id.clear()
	for port in ports:
		var id := str(port.get("id", ""))
		if not id.is_empty():
			_port_by_id[id] = port
