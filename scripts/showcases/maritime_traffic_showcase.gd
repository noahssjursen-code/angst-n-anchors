extends Node2D

var _time_s := 0.0
var _font: Font


func _ready() -> void:
	_font = ThemeDB.fallback_font
	var traffic := get_node_or_null("/root/MaritimeTraffic")
	if traffic != null:
		traffic.register_holding_zones("demo_port", [[930.0, 300.0], [930.0, 390.0]])
		traffic.request_port_arrival("demo_port", "coaster-7", "general_cargo", "berth-a", 100, 0)
		traffic.request_port_arrival("demo_port", "freighter-2", "general_cargo", "berth-b", 110, 0)


func _process(delta: float) -> void:
	_time_s += delta
	var traffic := get_node_or_null("/root/MaritimeTraffic")
	if traffic != null:
		var a := Vector2(220.0 + fmod(_time_s * 28.0, 520.0), 330.0)
		var b := Vector2(800.0 - fmod(_time_s * 25.0, 520.0), 330.0)
		traffic.publish_intent({"vessel_id": "northbound", "position_xz": [a.x, a.y],
			"velocity_xz": [28.0, 0.0], "heading_deg": 90.0, "length_m": 32.0})
		traffic.publish_intent({"vessel_id": "southbound", "position_xz": [b.x, b.y],
			"velocity_xz": [-25.0, 0.0], "heading_deg": 270.0, "length_m": 28.0})
		traffic.call("_resolve_conflicts")
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), Color("07141f"))
	draw_string(_font, Vector2(50, 60), "MARITIME TRAFFIC AUTHORITY", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color("e8eee9"))
	draw_string(_font, Vector2(50, 90), "Shared vessel intents / VHF agreements / harbour queues", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("8fa39e"))
	draw_line(Vector2(110, 330), Vector2(900, 330), Color("456b75"), 38.0)
	draw_line(Vector2(110, 330), Vector2(900, 330), Color("c0aa71"), 2.0)
	var a := Vector2(220.0 + fmod(_time_s * 28.0, 520.0), 330.0)
	var b := Vector2(800.0 - fmod(_time_s * 25.0, 520.0), 330.0)
	_draw_vessel(a, Color("55b892"), "NORTHBOUND")
	_draw_vessel(b, Color("e97943"), "SOUTHBOUND")
	var traffic := get_node_or_null("/root/MaritimeTraffic")
	var agreement: Dictionary = traffic.agreement_for("northbound") if traffic != null else {}
	var message := "CLEAR - vessels proceed normally"
	if not agreement.is_empty():
		message = "VHF 16: HEAD-ON AGREEMENT - both vessels alter starboard"
	draw_string(_font, Vector2(110, 430), message, HORIZONTAL_ALIGNMENT_LEFT, -1, 18,
		Color("e97943") if not agreement.is_empty() else Color("55b892"))
	draw_string(_font, Vector2(110, 500), "DEMO PORT HOLDING QUEUE", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("e8eee9"))
	if traffic != null:
		var queue: Array = traffic.port_queue("demo_port")
		for index in range(queue.size()):
			var row := queue[index] as Dictionary
			draw_string(_font, Vector2(130, 535 + index * 30), "%d. %s  %s" % [
				index + 1, str(row.get("vessel_id", "")),
				"CLEARED" if index == 0 else "HOLD"], HORIZONTAL_ALIGNMENT_LEFT, -1, 16,
				Color("55b892") if index == 0 else Color("d7b56d"))


func _draw_vessel(position: Vector2, color: Color, vessel_name: String) -> void:
	draw_circle(position, 15.0, color)
	draw_line(position, position + Vector2(32.0 if vessel_name == "NORTHBOUND" else -32.0, 0.0), color, 3.0)
	draw_string(_font, position + Vector2(-48, -25), vessel_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, color)
