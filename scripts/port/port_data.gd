class_name PortData
extends RefCounted

## Expanded runtime port record. Initial worlds derive this from PortDefinition;
## future authoritative saves can supply the exact PortLayoutGraph.

var port_id: String = ""
var display_name: String = ""
var world_position: Vector3 = Vector3.ZERO
var size: int = 1
var site_id: String = ""
var port_generation_version := PortDefinition.CURRENT_PORT_GENERATION_VERSION
var trade_profile: PortTradeProfile
var layout_graph: PortLayoutGraph

var dock_length: float = PortSizing.dock_length_m(1)
var max_ship_class: ShipClass.Type = ShipClass.Type.COASTAL_TRADER
var has_fuel_point: bool = true
var has_lighthouse: bool = false
var has_fog_horn: bool = false

var commodity_export: String = ""
var commodity_imports: Array[String] = []

var island_width: float = PortSizing.island_width_m(1)
var plot_depth: float = PortSizing.PLOT_DEPTH_M
var layout_seed: int = 0
var rotation_y: float = 0.0
var region_kind: PortDefinition.RegionKind = PortDefinition.RegionKind.LEGACY_ISLAND
var ground_mode: PortDefinition.GroundMode = PortDefinition.GroundMode.LOCAL_ISLAND

var population: int = 0
var features: Array[String] = []
var berth_count: int = 1


func flatten_zone_records(height_m := 0.0) -> Array[Dictionary]:
	if layout_graph == null:
		return []
	return layout_graph.flatten_zone_records(world_position, rotation_y, height_m)
