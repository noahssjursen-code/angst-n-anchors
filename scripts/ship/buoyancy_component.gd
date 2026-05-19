@tool
class_name BuoyancyComponent
extends Node3D

## DEPRECATED — replaced by StripBuoyancyComponent (strip-theory hull integration).
##
## This class is preserved as an inert shim so legacy .tscn scenes that still reference
## `BuoyancyComponent` continue to load without errors. It applies no forces. The actual
## buoyancy work is done by StripBuoyancyComponent, which ShipBuilder constructs.
##
## To migrate a legacy scene: replace this node with a StripBuoyancyComponent and let
## ShipBuilder build the ship instead of using the .tscn directly.

func _ready() -> void:
	if not Engine.is_editor_hint():
		push_warning(
			"BuoyancyComponent is deprecated — this node does nothing. " +
			"Use StripBuoyancyComponent (built by ShipBuilder) for proper buoyancy."
		)
