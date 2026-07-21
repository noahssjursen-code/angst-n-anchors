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


static func for_preview(seed: int, port_count: int = 35) -> ChartDataSnapshot:
	var out := ChartDataSnapshot.new()
	out.preview = true
	out.world_seed = seed
	out.generation_version = int(GENERATOR.GENERATION_VERSION)
	out.layout = GENERATOR.generate(seed)
	out.layout_checksum = str(out.layout.layout_checksum) if out.layout != null else ""
	if out.layout == null:
		return out
	var definitions: Array = PLACER.place_ports(
		out.layout,
		maxi(port_count, 1),
		PackedStringArray(PORT_NAMES),
	)
	for definition in definitions:
		## Lightweight trade/size summary — full PortLayoutGenerator is too
		## expensive for the captain home-port picker (dozens of ports).
		out.ports.append(PortExpander.chart_summary(definition, seed))
	out._index_ports()
	# These are deterministic field APIs, not world scene construction.
	LandField.initialize(out.layout)
	FishingField.initialize(seed)
	WeatherField.world_seed = seed
	WeatherFrontField.initialize(seed)
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
		"generation_version": generation_version,
		"layout_checksum": layout_checksum,
	}


func _index_ports() -> void:
	_port_by_id.clear()
	for port in ports:
		var id := str(port.get("id", ""))
		if not id.is_empty():
			_port_by_id[id] = port
