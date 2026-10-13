extends Node
func _ready() -> void:
	var drawing := preload("res://scripts/network/replication_drawing_service.gd").new()
	add_child(drawing)
	var ship := Node3D.new()
	drawing.add_child(ship)
	drawing._visible_entities["ship-test"] = {"node":ship,"meta":"vid=vessel-test","type":"ship_hull_24x8"}
	var nodes := {}
	drawing.apply_vessel_storage("vessel-test", {"state":{"status":"released","reason":"stored_at_port"}}, nodes)
	assert(not drawing._visible_entities.has("ship-test"), "Storage removes replica immediately")
	drawing.apply_entities([{"id":"ship-test","type":"ship_hull_24x8","meta":"vid=vessel-test","payload":[0,0,0,0,0,0],"format":6}],"self",nodes,[],Time.get_ticks_msec(),15000)
	assert(not drawing._visible_entities.has("ship-test"), "Late UDP cannot resurrect stored vessel")
	drawing.apply_vessel_storage("vessel-test", {"state":{"status":"assigned"}},nodes)
	assert(not drawing._stored_vessels.has("vessel-test"),"New deployment permits replication again")
	print("REMOTE STORAGE VISIBILITY PASS")
	get_tree().quit()
