extends "res://tests/custom_port_showcase_input_test.gd"

## Exercise actual shoreline earthworks; fully buried hillside pads are forbidden.
func _run() -> void:
	var workshop:=WORKSHOP.instantiate()
	add_child(workshop)
	var deadline:=Time.get_ticks_msec()+45000
	while not workshop.ready_for_review and Time.get_ticks_msec()<deadline:await get_tree().process_frame
	_check(workshop.ready_for_review,"Coastal workshop becomes ready")
	if not workshop.ready_for_review:_finish();return
	workshop.save_path="user://custom_ports/earthworks-workshop-%d.json"%Time.get_ticks_usec()
	workshop.build()
	var proposal: Dictionary={}
	var original_height:=0.0
	var rejected_buried:=false
	# Find an exposed shoreline pad, with its centre just inside the bank.
	# Also prove that a fully buried inland pad cannot trigger excavation.
	for plot in workshop.state.to_dict().plots:
		var r: Array=plot.rect_m
		for x in range(ceili(float(r[0])+8),floori(float(r[0])+float(r[2])-8),4):
			for z in range(ceili(float(r[1])+8),floori(float(r[1])+float(r[3])-8),4):
				var rough_point: Vector2=Vector2(workshop.site.x+x,workshop.site.z+z)
				var rough_height: float=workshop._foundation_ground_height(rough_point)
				if rough_height<workshop.site.y or rough_height>workshop.site.y+35:continue
				var candidate: Dictionary=workshop.editor.preview("foundation_8m",Vector3(x,0,z))
				if not candidate.ok:
					if not rejected_buried and candidate.get("message","").contains("Entire foundation"):
						var count_before:int=workshop.state.to_dict().placements.size()
						workshop.preview=candidate
						workshop._place()
						_check(workshop.state.to_dict().placements.size()==count_before,"Buried-pad click does not create a foundation")
						rejected_buried=true
					continue
				var point: Vector3=workshop.site+CustomPortCatalog.vector3(candidate.placement.position_m)
				var height:=_terrain_y(workshop,point)
				if proposal.is_empty() and height>workshop.site.y+.03 and height<workshop.site.y+35:
					proposal=candidate;original_height=height
				if not proposal.is_empty() and rejected_buried:break
			if not proposal.is_empty() and rejected_buried:break
		if not proposal.is_empty() and rejected_buried:break
	_check(rejected_buried,"The real terrain rejects fully buried foundations")
	_check(not proposal.is_empty(),"An exposed shoreline tile can still be built")
	if proposal.is_empty():workshop.queue_free();_finish();return
	var point: Vector3=workshop.site+CustomPortCatalog.vector3(proposal.placement.position_m)
	var before: Array=workshop.state.to_dict().placements.duplicate(true)
	var old_signature: String=workshop.terrain._custom_earthworks[0].geometry_signature
	workshop.painting=true
	workshop.editor.begin_edit()
	workshop.preview=proposal
	workshop._place()
	_check(workshop.state.to_dict().placements.size()==before.size()+1,"Builder accepts the partially exposed shoreline foundation")
	_check(workshop.terrain._custom_earthworks[0].geometry_signature==old_signature,"Painting coalesces terrain work until the stroke ends")
	workshop.painting=false
	workshop.editor.end_edit()
	workshop._finish_ground_update()
	_check(workshop.terrain._custom_earthworks[0].geometry_signature!=old_signature,"Ending the stroke projects the new footprint")
	workshop.walk()
	if not workshop.terrain.is_custom_port_earthworks_ready():
		_check(not workshop.player.is_physics_processing(),"Walking waits for the matching terrain collider")
	await _ground_ready(workshop)
	_check(absf(_terrain_y(workshop,point)-(workshop.site.y-.12))<.01,"Actual streamed terrain collision is cut beneath the tile")
	_check(not workshop.building and workshop.player.is_physics_processing(),"Walking resumes once the ground is ready")
	workshop.build()
	workshop.save_port()
	workshop.load_port()
	await _ground_ready(workshop)
	_check(absf(_terrain_y(workshop,point)-(workshop.site.y-.12))<.01,"Saved footprint reconstructs the same terrain cut")
	# Load deliberately resets edit history; undo is checked on a fresh adjacent
	# build, while removal of the first imported tile checks complete restoration.
	var removed: Dictionary=workshop.editor.remove(str(proposal.placement.id))
	_check(removed.ok,"Removing the new foundation is accepted")
	if removed.ok:workshop._on_state_changed(workshop.state.to_dict(),removed)
	await _ground_ready(workshop)
	_check(absf(_terrain_y(workshop,point)-original_height)<.01,"Removing the tile restores the original hillside collider")
	var restored: Dictionary=workshop.editor.undo()
	_check(restored.ok,"Undo restores the removed foundation")
	if restored.ok:workshop._on_state_changed(workshop.state.to_dict(),restored)
	await _ground_ready(workshop)
	_check(absf(_terrain_y(workshop,point)-(workshop.site.y-.12))<.01,"Undo restores the cut with the foundation")
	if OS.get_cmdline_user_args().has("--capture"):
		workshop.library.hide();workshop.overlays.hide()
		# A narrow excavation can be hidden by its intact hillside from an
		# oblique angle. Look directly into the exact tile checked by the rays.
		workshop.set_process(false)
		if is_instance_valid(workshop.ghost):workshop.ghost.hide()
		workshop.camera.position=point+Vector3(.1,maxf(45,original_height+20),.1)
		workshop.camera.look_at(point)
		workshop.camera.current=true
		workshop.camera.reset_physics_interpolation()
		for frame in 3:await get_tree().process_frame
		await workshop._capture("shoreline-foundation-restored")
	workshop.queue_free()
	await get_tree().process_frame
	_finish()

func _ground_ready(workshop: Node) -> void:
	var deadline:=Time.get_ticks_msec()+20000
	while not workshop.terrain.is_custom_port_earthworks_ready() and Time.get_ticks_msec()<deadline:
		await get_tree().process_frame
	_check(workshop.terrain.is_custom_port_earthworks_ready(),"Terrain update completes")
	await get_tree().physics_frame
	await get_tree().physics_frame
	workshop._finish_ground_update()

func _terrain_y(workshop: Node,point: Vector3) -> float:
	var excluded: Array[RID]=[workshop.player.get_rid()]
	for body in workshop.presenter.find_children("*","CollisionObject3D",true,false):excluded.append(body.get_rid())
	var query:=PhysicsRayQueryParameters3D.create(point+Vector3.UP*100,point-Vector3.UP*100,1,excluded)
	var hit: Dictionary=workshop.get_world_3d().direct_space_state.intersect_ray(query)
	return float(hit.position.y) if not hit.is_empty() else -INF

func _finish() -> void:
	for failure in failures:push_error(failure)
	print("CUSTOM PORT EARTHWORKS WORKSHOP ","PASS" if failures.is_empty() else "FAIL"," checks=",checks)
	get_tree().quit(0 if failures.is_empty() else 1)
