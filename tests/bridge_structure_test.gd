extends Node

class SlopedGround extends WorldLayout:
	func sample_height(at: Vector2) -> float: return 10+at.x*.3+at.y*.5
	func sample_signed_distance(_at: Vector2) -> float: return -100

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var slope := SlopedGround.new()
	var direction := Vector2(.6,.8)
	var foundation := BridgeStructurePlan.foundation_base(slope,Vector2.ZERO,direction,22,10)
	for x in [-11.0,0.0,11.0]:
		for z in [-5.0,0.0,5.0]:
			var ground := WorldTerrainStreamer.sample_render_terrain_height(slope,direction*z+direction.orthogonal()*x)
			assert(foundation<=ground-BridgeStructurePlan.FOUNDATION_EMBED_M,"Footprint foundation must bury below visible sloping ground")
	assert(foundation<=WorldTerrainStreamer.sample_render_terrain_height(slope,Vector2(-200,-200))-BridgeStructurePlan.FOUNDATION_EMBED_M,"Coarse terrain LOD must not expose support bottoms")
	if OS.get_cmdline_user_args().has("--foundations-only"):
		print("BRIDGE FOUNDATION FOOTPRINT AND LOD PASS")
		get_tree().quit()
		return
	var deck_mesh := BridgeAssembler.part("deck_20m")
	assert(is_equal_approx(deck_mesh.get_aabb().size.z,20))
	assert(is_equal_approx(deck_mesh.get_aabb().size.x,12))
	for example in [[160,"girder"],[350,"arch"],[700,"cantilever"],[1100,"suspension"]]:
		var length := float(example[0])
		var crossing := {"a_xz":Vector2.ZERO,"b_xz":Vector2(length,0),"a_ground":10.0,"b_ground":14.0}
		var plan := BridgeStructurePlan.design(crossing)
		assert(plan.accepted and plan.family==example[1])
		var bridge := BridgeAssembler.build(plan)
		add_child(bridge)
		assert(bridge.get_node("BridgeCollision").get_child_count()>2)
		var meshes := bridge.find_children("*","MeshInstance3D",true,false)
		assert(meshes.size()==4,"Four material batches, independent of span length")
		for mesh: MeshInstance3D in meshes:
			assert(mesh.mesh.get_aabb().size.is_finite())
			assert(mesh.mesh.get_surface_count()>0)
		for i in 2:
			var end := Vector3(length*i,plan.deck_y,0)
			var at: Vector3 = plan.approaches[i]
			assert(absf(at.y-end.y)/Vector2(at.x-end.x,at.z-end.z).length()<=BridgeStructurePlan.MAX_GRADE)
		await get_tree().physics_frame
		await get_tree().physics_frame
		var ray := PhysicsRayQueryParameters3D.create(Vector3(length*.5,plan.deck_y+10,0),Vector3(length*.5,plan.deck_y-1,0))
		assert(not get_viewport().world_3d.direct_space_state.intersect_ray(ray).is_empty(),"Deck must be physical")
		bridge.queue_free()
		await get_tree().process_frame
		print("BRIDGE FAMILY PASS ",example[1])
	for seed_value in [42,1850239324,1212599375]:
		var layout := WorldLayoutGenerator.generate(seed_value)
		var ports := CoastalPortPlacer.place_ports(layout)
		var candidates := CoastalBridgePlan.build(layout,ports)
		var shortcuts:=0
		for crossing:Dictionary in candidates.bridges:
			if crossing.component_a==crossing.component_b:
				shortcuts+=1
				assert(crossing.span_m<=CoastalBridgePlan.MAX_MAINLAND_GAP+2*CoastalBridgePlan.LANDING_INSET+1)
		assert(shortcuts<=CoastalBridgePlan.MAX_MAINLAND_SHORTCUTS)
		var accepted := 0
		var rejected := {}
		for crossing: Dictionary in candidates.bridges:
			var plan := BridgeStructurePlan.design(crossing,layout)
			if not plan.accepted:
				rejected[plan.reason]=rejected.get(plan.reason,0)+1
				continue
			accepted+=1
			for i in plan.supports.size():
				assert(plan.deck_y>plan.bases[i])
				var axis: Vector2 = (plan.b-plan.a).normalized()
				for offset in [-10.0,0.0,10.0] if plan.family=="suspension" else [-2.5,0.0,2.5]:
					var at: Vector2 = plan.a+axis*plan.supports[i]+axis.orthogonal()*offset
					assert(plan.bases[i]<=WorldTerrainStreamer.sample_render_terrain_height(layout,at)-4.9)
				for channel in plan.channels: assert(absf(plan.supports[i]-channel)>=60)
			for approach: Vector3 in plan.approaches:
				assert(layout.sample_height(Vector2(approach.x,approach.z))>WaveSurface.WATER_LEVEL)
		print("BRIDGE WORLD seed=",seed_value," accepted=",accepted," rejected=",rejected)
		assert(accepted>0,"Physical bridge placement must survive real terrain validation")
		if seed_value==42:
			var live := CoastalBridges.new()
			live.configure(layout,ports)
			add_child(live)
			var timeout := Time.get_ticks_msec()+120000
			while live.is_processing() and Time.get_ticks_msec()<timeout:
				await get_tree().create_timer(.05).timeout
			assert(not live.is_processing(),"World bridge worker must finish")
			assert(not live.report.structures.is_empty(),"World must retain useful bridges")
			var checked:Array=[]
			for structure:Dictionary in live.report.structures:
				assert(not CoastalBridges.conflicts_with(structure,checked),"Bridge corridors overlap")
				checked.append(structure)
			assert(live.get_child_count()==live.report.structures.size()+1,"Physical bridges appear with gizmos disabled")
			assert(not live.get_node("BridgeCandidates").visible)
			live.queue_free()
			await get_tree().process_frame
	print("BRIDGE STRUCTURE PASS")
	get_tree().quit()
