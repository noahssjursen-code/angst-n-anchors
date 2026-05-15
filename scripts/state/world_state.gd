class_name WorldState
extends RefCounted

signal weather_changed(label: String)
signal nearest_port_changed(port_id: String)

var weather_label: String = "":
	set(v):
		weather_label = v
		weather_changed.emit(v)

## port_id of the closest port, empty string when none are nearby.
var nearest_port_id: String = "":
	set(v):
		nearest_port_id = v
		nearest_port_changed.emit(v)
