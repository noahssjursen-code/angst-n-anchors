extends Node

## SCRATCH PROBE (leading underscore -> skipped by tools/gate.sh discovery).
## Lane B (.tscn), because it needs a real frame and the renderer's own counter.
##
## Settles "colour is free" on the counter STATE.md quotes, not on a bucket
## count: bake the same fixture as shipped and repainted to N distinct colours,
## photograph both from the SAME camera pose, and read
## RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME.

const FIXTURE := "res://resources/data/structures/demo_workboat.json"
const SETTLE_FRAMES := 4

var _camera: Camera3D
var _stage: Node3D


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	for child in get_tree().root.get_children():
		if child != self:
			_hide_canvas_items(child)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	light.shadow_enabled = true
	add_child(light)
	_camera = Camera3D.new()
	add_child(_camera)
	_camera.current = true

	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	var doc := raw as Dictionary

	var base := await _measure(doc, "as shipped")
	var many := _repaint(doc)
	var loud := await _measure(many, "repainted")

	print("\n=== RESULT ===")
	print("as shipped : %2d distinct colours -> %2d mesh instances, %3d draw calls, %d primitives"
		% [_distinct_colours(doc), base["meshes"], base["draw_calls"], base["primitives"]])
	print("repainted  : %2d distinct colours -> %2d mesh instances, %3d draw calls, %d primitives"
		% [_distinct_colours(many), loud["meshes"], loud["draw_calls"], loud["primitives"]])
	print("delta draw calls = ", loud["draw_calls"] - base["draw_calls"])

	## And the documented exception, on the same counter.
	var ghost := await _measure(many, "repainted GHOST", true)
	print("repainted ghost: %2d mesh instances, %3d draw calls"
		% [ghost["meshes"], ghost["draw_calls"]])
	print("ghost premium over solid = ", ghost["draw_calls"] - loud["draw_calls"], " draw calls")
	get_tree().quit(0)


func _hide_canvas_items(node: Node) -> void:
	if node is CanvasLayer:
		(node as CanvasLayer).visible = false
		return
	if node is CanvasItem:
		(node as CanvasItem).visible = false
		return
	for child in node.get_children():
		_hide_canvas_items(child)


func _measure(doc: Dictionary, label: String, ghost := false) -> Dictionary:
	if _stage != null:
		_stage.queue_free()
		await get_tree().process_frame
	_stage = Node3D.new()
	add_child(_stage)
	var plan := StructurePlan.from_dict(doc)
	var built: Node3D = StructureBaker.bake(plan, Vector3.ZERO, ghost)
	_stage.add_child(built)

	var meshes := 0
	for child in built.get_children():
		if child is MeshInstance3D:
			meshes += 1

	## One fixed pose for every measurement, so culling is identical.
	_camera.position = Vector3(28.0, 14.0, 34.0)
	_camera.look_at(Vector3(5.0, 2.0, 14.0), Vector3.UP)
	_camera.fov = 45.0
	_camera.near = 0.1
	_camera.far = 400.0

	for i in SETTLE_FRAMES:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var calls := int(RenderingServer.get_rendering_info(
		RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	var prims := int(RenderingServer.get_rendering_info(
		RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	print("[%s] meshes=%d draw_calls=%d primitives=%d" % [label, meshes, calls, prims])
	return {"meshes": meshes, "draw_calls": calls, "primitives": prims}


func _distinct_colours(doc: Dictionary) -> int:
	var seen: Dictionary = {}
	var stack: Array = [doc]
	while not stack.is_empty():
		var top = stack.pop_back()
		if top is Dictionary:
			for k in (top as Dictionary).keys():
				var v = (top as Dictionary)[k]
				if str(k) == "color" and v is Array:
					seen[str(v)] = true
				else:
					stack.append(v)
		elif top is Array:
			for v in top as Array:
				stack.append(v)
	return seen.size()


func _repaint(doc: Dictionary) -> Dictionary:
	var out := doc.duplicate(true)
	_walk(out, [0])
	return out


func _walk(node: Variant, counter: Array) -> void:
	if node is Dictionary:
		var d := node as Dictionary
		for k in d.keys():
			if str(k) == "color" and d[k] is Array:
				var i: int = counter[0]
				counter[0] = i + 1
				d[k] = [
					float((i * 37) % 64) / 64.0,
					float((i * 61) % 64) / 64.0,
					float((i * 17) % 64) / 64.0,
				]
			else:
				_walk(d[k], counter)
	elif node is Array:
		for v in node as Array:
			_walk(v, counter)
