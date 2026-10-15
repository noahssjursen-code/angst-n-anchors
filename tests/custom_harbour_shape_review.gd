extends "res://tests/custom_harbour_asset_review.gd"

const IDS := ["foundation_triangle_4m","quay_triangle_4m","foundation_chamfer_4m","quay_chamfer_4m"]
var tiles: Array[Node3D] = []

func _ready() -> void:
	assert(ShipyardPlaytestMode.active())
	_setup()
	for index in IDS.size():
		var tile := _asset(IDS[index],Vector3(-9+index*6,0,0))
		assert(Library.set_foundation_depth(tile,2.0+index*1.5))
		tiles.append(tile)
		var title:=Label3D.new()
		title.text="TRIANGLE · 8 m²" if index<2 else "CHAMFER · 15.5 m²"
		title.font_size=40
		title.pixel_size=.012
		title.position=tile.position+Vector3(0,.7,2.6)
		title.billboard=BaseMaterial3D.BILLBOARD_ENABLED
		add_child(title)
	var pair_a:=_asset("foundation_triangle_4m",Vector3(0,0,8))
	var pair_b:=_asset("foundation_triangle_4m",Vector3(0,0,8),180)
	Library.set_foundation_depth(pair_a,3)
	Library.set_foundation_depth(pair_b,3)
	_shape_view(1)
	call_deferred("_verify_shapes")

func _shape_view(view: int) -> void:
	if view==1:
		target=Vector3(0,-.8,2)
		camera.position=Vector3(17,17,-23)
		label.text="AUTHORED 45° HARBOUR TILES · Fixed finished deck Y=0\n4 m grid · Triangle and 1 m corner cut · Supports extend to seabed without changing the top"
	elif view==2:
		target=Vector3(0,0,1)
		camera.position=Vector3(0,28,1.05)
		label.text="PLAN / COLLISION · The cut corners contain no invisible square\nTwo complementary triangle tiles reconstruct one 4 × 4 m square behind"
	else:
		target=Vector3(-3,-.3,0)
		camera.position=Vector3(3,2,-6)
		label.text="DIAGONAL QUAY · Flush metal edge and exact convex support\nWalking plane stays Y=0 while the lower wall extends"
	camera.look_at(target)

func _verify_shapes() -> void:
	await get_tree().physics_frame
	for index in tiles.size():
		var tile:=tiles[index]
		var spec:=Library.specification(IDS[index])
		var wanted_area:=8.0 if index<2 else 15.5
		_check(is_equal_approx(_area(spec.footprint_polygon_m),wanted_area),"Authored plan area: "+IDS[index])
		var depth:=2.0+index*1.5
		var actual:=_bounds(tile)
		_check(absf(actual.position.y+depth)<.005,"Support reaches selected depth: "+IDS[index])
		_check(absf(actual.end.y)<.005,"Deck never changes height: "+IDS[index])
		for turn in 4:
			tile.rotation.y=turn*PI*.5
			await get_tree().physics_frame
			await get_tree().physics_frame
			_check(_hit(tile,Vector2(-.8,.5)),"Solid inside at quarter turn: "+IDS[index]+str(turn))
			var outside:=Vector2(1,-1) if index<2 else Vector2(1.8,-1.8)
			_check(not _hit(tile,outside),"Cut corner stays physically empty: "+IDS[index]+str(turn))
		tile.rotation.y=0
		_check(Library.set_foundation_depth(tile,depth+8),"Runtime support update")
		_check(absf(_bounds(tile).end.y)<.005,"Deeper support keeps deck datum")
		Library.set_foundation_depth(tile,depth)
	await get_tree().physics_frame
	await get_tree().physics_frame
	for x in range(-3,4):
		for z in range(-3,4):
			var from:=Vector3(float(x)*.5,2,8+float(z)*.5)
			# A finite foot probe crosses the shared diagonal. A zero-width ray on
			# two rotated convex edges is sensitive to sin(PI) float roundoff.
			var query:=PhysicsShapeQueryParameters3D.new()
			var foot:=SphereShape3D.new()
			foot.radius=.025
			query.shape=foot
			query.collision_mask=1
			query.transform.origin=Vector3(from.x,.01,from.z)
			_check(not get_world_3d().direct_space_state.intersect_shape(query).is_empty(),"Complementary triangles support the shared seam at "+str(Vector2(x,z)))
	if OS.get_cmdline_user_args().has("--capture"):
		for view in [1,2,3]:
			_shape_view(view)
			await _capture("diagonal-tiles-"+str(view))
	print("CUSTOM HARBOUR SHAPE REVIEW ","PASS" if failures.is_empty() else "FAIL"," 4 tiles x 4 rotations; depth updates; 49 complementary samples; failures=",failures.size())
	if OS.get_cmdline_user_args().has("--capture") or OS.get_cmdline_user_args().has("--verify") or DisplayServer.get_name()=="headless":
		get_tree().quit(0 if failures.is_empty() else 1)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode>=KEY_1 and event.keycode<=KEY_3:
			_shape_view(int(event.keycode-KEY_1)+1)
		elif event.keycode==KEY_P:
			_capture("diagonal-tiles-manual")
	if event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_RIGHT:orbiting=event.pressed
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			camera.position=target+(camera.position-target)*(.9 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1.1)
	if event is InputEventMouseMotion and orbiting:
		var offset:=camera.position-target
		offset=offset.rotated(Vector3.UP,-event.relative.x*.005)
		offset=offset.rotated(camera.global_basis.x,-event.relative.y*.005)
		camera.position=target+offset
		camera.look_at(target)

func _hit(tile: Node3D,point: Vector2) -> bool:
	var from:=tile.to_global(Vector3(point.x,2,point.y))
	var to:=tile.to_global(Vector3(point.x,-15,point.y))
	return not get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from,to,1)).is_empty()

func _area(raw: Array) -> float:
	var result:=0.0
	for i in raw.size():
		var a: Array=raw[i]
		var b: Array=raw[(i+1)%raw.size()]
		result+=float(a[0])*float(b[1])-float(b[0])*float(a[1])
	return absf(result)*.5
