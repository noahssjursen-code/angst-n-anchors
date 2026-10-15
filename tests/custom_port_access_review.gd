extends "res://scripts/port/building/custom_port_showcase.gd"

## Native review of the actual island fixture, not a substitute flat test floor.
## Run with --shipyard-playtest --capture-custom-port and an isolated APPDATA.
var audit_failures: Array[String] = []
var audit_checks := 0

func _check(ok: bool, text: String) -> void:
	audit_checks += 1
	if not ok:
		audit_failures.append(text)
		push_error(text)

func _review() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	ui.hide()
	overlays.hide()
	_set_cursor(true)
	if OS.get_cmdline_user_args().has("--survey-shore"):
		for x in [-8.0,-6.0,-4.0,-2.0,0.0,2.0,4.0]:
			for z in range(64,81,4):
				var at := SITE+Vector3(x,0,z+.1)
				var query:=PhysicsRayQueryParameters3D.create(at+Vector3.UP*20,at-Vector3.UP*30,1,[player.get_rid()])
				var hit:=get_world_3d().direct_space_state.intersect_ray(query)
				print("SHORE_SURVEY x=",x," z=",z+.1," sample_y=",WorldTerrainStreamer.sample_render_terrain_height(layout,Vector2(at.x,at.z))," collider_y=",hit.get("position",Vector3.ZERO).y," collider=",hit.get("collider","missing"))
		get_tree().quit()
		return
	# Actual imported model bounds must reach the actual triangulated seabed.
	var worst_gap := -INF
	var worst_id := ""
	for row in state.to_dict().placements:
		var spec: Dictionary = catalog[str(row.asset_id)]
		if str(spec.kind) != "platform": continue
		var node: Node3D = presenter.placement_nodes[str(row.id)]
		var bottom := INF
		for mesh in SurfaceMaterialLibrary.meshes(node):
			var bounds: AABB = mesh.global_transform * mesh.get_aabb()
			bottom = minf(bottom, bounds.position.y)
		for polygon in CustomPortPlacementRules.polygons(row,spec):
			for i in polygon.size():
				var a: Vector2 = polygon[i]
				var b: Vector2 = polygon[(i+1)%polygon.size()]
				for sample_index in 9:
					var at := Vector2(SITE.x,SITE.z)+a.lerp(b,float(sample_index)/8.0)
					var gap := bottom-_support_seabed(at)
					if gap > worst_gap:
						worst_gap=gap
						worst_id=str(row.id)
	_check(worst_gap <= .03,"Every authored foundation skirt reaches both continuous and finest-grid terrain; worst gap %.3f m at %s"%[worst_gap,worst_id])
	print("FOUNDATION_SEABED_AUDIT worst_gap_m=",worst_gap," placement=",worst_id)
	# The existing real CharacterBody walks the short shore connection in both
	# directions. This includes the game's step-up logic and 0.35 m radius.
	for lane in [-6.0,-2.0]:
		var probe := SITE+Vector3(lane,0,82)
		var floor_query:=PhysicsRayQueryParameters3D.create(probe+Vector3.UP*20,probe-Vector3.UP*30,1,[player.get_rid()])
		var floor_hit:=get_world_3d().direct_space_state.intersect_ray(floor_query)
		_check(not floor_hit.is_empty(),"Natural shore collision exists at the access lane")
		if floor_hit.is_empty():continue
		await _walk_route(Vector3(lane,floor_hit.position.y-SITE.y+.04,82),Vector3(lane,0,76),"shore to quay lane %.0f"%lane)
		await _walk_route(Vector3(lane,.04,76),Vector3(lane,0,82),"quay to shore lane %.0f"%lane)
	var entrance: Node3D=presenter.placement_nodes["warehouse-front-1"]
	_check(not bool(entrance.get_meta("door_open",false)),"Workshop entrance begins closed")
	await _walk_route(Vector3(-50,.04,47),Vector3(-50,0,51),"decorative warehouse door",false)
	_check(player.position.z < SITE.z+48.8,"Closed workshop door physically stops the player")
	_check(not CustomHarbourAssetLibrary.set_door_open(entrance,true),"Decorative entrance cannot be opened")
	await _walk_route(Vector3(-54,.04,47),Vector3(-54,0,54),"closed loading shutter",false)
	_check(player.position.z < SITE.z+48.8,"Closed loading shutter physically stops the player")
	# Keep the player out of close architectural photographs.
	player.position=SITE+Vector3(8,.1,62)
	for shot in [
		{"name":"audit-decorative-door","at":Vector3(-47,2.1,45),"look":Vector3(-50,1.3,48)},
		{"name":"audit-closed-shutter","at":Vector3(-58,1.7,44),"look":Vector3(-54,1.5,48)},
		{"name":"audit-window-and-roof-join","at":Vector3(-39,3.2,48),"look":Vector3(-42,2.1,52)},
		{"name":"audit-shore-threshold","at":Vector3(1,1.7,85),"look":Vector3(-4,.2,76)},
		{"name":"audit-tyre-and-ladder","at":Vector3(-45,.9,-3),"look":Vector3(-48,-.3,0)},
		{"name":"audit-diagonal-edge","at":Vector3(-74,1.1,-2),"look":Vector3(-70,-.25,2)}]:
		camera.position=SITE+shot.at
		camera.look_at(SITE+shot.look)
		await get_tree().create_timer(.2).timeout
		await _capture(str(shot.name))
	print("CUSTOM_PORT_ACCESS_REVIEW ","PASS" if audit_failures.is_empty() else "FAIL"," checks=",audit_checks," failures=",audit_failures.size())
	get_tree().quit(0 if audit_failures.is_empty() else 1)

func _walk_route(start: Vector3, destination: Vector3, label: String, expect_arrival := true) -> void:
	player.position=SITE+start
	player.velocity=Vector3.ZERO
	player._air_deck=null
	player.reset_physics_interpolation()
	var direction := (destination-start)*Vector3(1,0,1)
	var yaw := atan2(-direction.x,-direction.z)
	player.rotation.y=yaw
	var player_camera: Node=player.get_node("PlayerCamera")
	player_camera.shift_look_yaw(yaw-player_camera.get_look_yaw())
	Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	Input.action_release("move_forward")
	for frame in 24:
		await get_tree().physics_frame
		player._physics_process(1.0/60.0)
	Input.action_press("move_forward")
	for frame in 240:
		await get_tree().physics_frame
		player._physics_process(1.0/60.0)
		var remaining := (SITE+destination-player.position)*Vector3(1,0,1)
		if remaining.length()<.3: break
	Input.action_release("move_forward")
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	var error := ((SITE+destination-player.position)*Vector3(1,0,1)).length()
	print("PORT_WALK ",label," error_m=",error," local_end=",player.position-SITE)
	if expect_arrival:_check(error<.4,"Actual player can traverse "+label+" without jumping")
