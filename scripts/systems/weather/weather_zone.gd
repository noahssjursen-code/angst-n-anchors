class_name WeatherZone
extends Resource

enum ZoneType { STORM, FOG, SQUALL, PORT_CALM }

@export var center: Vector2 = Vector2.ZERO
@export var inner_radius: float = 300.0
@export var outer_radius: float = 800.0
@export var zone_type: ZoneType = ZoneType.STORM
@export var state: WeatherState
