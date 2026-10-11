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


func freight_berths() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if layout_graph == null: return out
	var plan: Dictionary = layout_graph.initial_attributes.get("berth_plan", {})
	for key in ["quay_stations", "asphalt_stations"]:
		for station in plan.get(key, []):
			var faces: Array = station.get("sides", []) if str(station.get("layout", "")) == "twin_joined" else [station]
			for face in faces:
				var commodities: Array = face.get("commodities", []).duplicate()
				var commodity := str(face.get("commodity_id", ""))
				if not commodity.is_empty() and not commodities.has(commodity): commodities.append(commodity)
				for zone in face.get("zones", []):
					commodity = str(zone.get("commodity_id", ""))
					if not commodity.is_empty() and not commodities.has(commodity): commodities.append(commodity)
				out.append({"length_m":float(station.get("length_m", 0.0)), "commodities":commodities})
	return out
var has_fuel_point: bool = true
var has_lighthouse: bool = false
var has_fog_horn: bool = false
var has_fish_landing: bool = false

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


## Chart / menu dossier fields (no layout mesh data).
func to_chart_dict() -> Dictionary:
	var region := "coastal"
	match region_kind:
		PortDefinition.RegionKind.MAINLAND:
			region = "mainland"
		PortDefinition.RegionKind.FJORD:
			region = "fjord"
		PortDefinition.RegionKind.ARCHIPELAGO:
			region = "archipelago"
		_:
			region = "coastal"
	return {
		"id": port_id,
		"display_name": display_name,
		"position": world_position,
		"size": size,
		"region": region,
		"commodity_export": commodity_export,
		"commodity_imports": commodity_imports.duplicate(),
		"population": population,
		"berth_count": maxi(berth_count, 1),
		"features": features.duplicate(),
		"max_ship_class": int(max_ship_class),
		"max_ship_class_name": str(ShipClass.DISPLAY_NAME.get(max_ship_class, "Vessel")),
		"has_lighthouse": has_lighthouse,
		"has_fog_horn": has_fog_horn,
		"has_fish_landing": has_fish_landing,
	}


func flatten_zone_records(height_m := 0.0) -> Array[Dictionary]:
	if layout_graph == null:
		return []
	return layout_graph.flatten_zone_records(world_position, rotation_y, height_m)
