class_name PlotBuildVisuals
extends RefCounted

static func create(spec: Dictionary, ghost := false, valid := true, support_depth_m := PlotBuildLayout.MIN_SUPPORT_DEPTH_M) -> Node3D:
	if spec.has("visual"):
		var equipment := preload("res://scripts/port/building/plot_build_equipment.gd").new()
		equipment.spec = spec
		equipment.preview = ghost
		equipment.valid = valid
		return equipment
	var root := Node3D.new()
	var size := Vector3(float(spec.cells[0])*2.0, float(spec.height_m), float(spec.cells[1])*2.0)
	var platform: bool=spec.get("anchor", "base")=="top"
	if platform and str(spec.id)!="pier":
		size.y=minf(1.0,support_depth_m) if ghost else support_depth_m
	var material: Material
	if ghost:
		var ghost_material := StandardMaterial3D.new()
		ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		ghost_material.albedo_color = Color(0.28,1.0,0.57,0.38) if valid else Color(1.0,0.22,0.16,0.44)
		ghost_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ghost_material.no_depth_test = true
		ghost_material.render_priority = 12
		material = ghost_material
	else:
		material = SurfaceMaterialLibrary.material(str(spec.material),Color(str(spec.colour)))
	# Every root is on the same deck plane; structure extends below or above it.
	_box(root, size, Vector3(0,-size.y/2 if platform else size.y/2,0), material, not ghost)
	if str(spec.id) in ["warehouse","workshop"]:
		var roof_material := material if ghost else SurfaceMaterialLibrary.material("roof_enamel",Color("424f53"))
		_box(root, Vector3(size.x,.25,size.z), Vector3(0,size.y-.125,0),roof_material,false)
	if str(spec.id) == "pier" and not ghost:
		var post_height := maxf(.1,support_depth_m-size.y)
		for x in [-size.x/2+.25,size.x/2-.25]:
			for z in [-size.z/2+.25,size.z/2-.25]:
				_box(root,Vector3(.3,post_height,.3),Vector3(x,-size.y-post_height/2,z),material,false)
	return root

static func _box(root: Node3D, size: Vector3, center: Vector3, material: Material, collision: bool) -> void:
	var mesh := MeshInstance3D.new()
	var shape := BoxMesh.new()
	shape.size = size
	mesh.mesh = shape
	mesh.position = center
	mesh.material_override = material
	root.add_child(mesh)
	if collision:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.set_meta("plot_build_visual", root)
		var collider := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		collider.shape = box
		collider.position = center
		body.add_child(collider)
		root.add_child(body)

static func plot_overlay(layout: WorldLayout, bounds: Rect2, grid: bool, floor_y: float = NAN, step := Vector2(2,2), origin := Vector2.ZERO) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	material.render_priority = 10
	var line_material: Material = material
	if grid:
		var grid_material := ShaderMaterial.new()
		grid_material.shader=preload("res://resources/shaders/plot_build_grid.gdshader")
		grid_material.render_priority=10
		line_material=grid_material
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, line_material)
	# The working grid matches the selected piece's rotated footprint and origin.
	if grid:
		var colour := Color(0.82,0.98,0.91,.24)
		for offset in range(roundi(fposmod(origin.x,step.x)),int(bounds.size.x)+1,roundi(step.x)):
			_line(mesh,layout,bounds.position+Vector2(offset,0),bounds.position+Vector2(offset,bounds.size.y),colour,floor_y)
		for offset in range(roundi(fposmod(origin.y,step.y)),int(bounds.size.y)+1,roundi(step.y)):
			_line(mesh,layout,bounds.position+Vector2(0,offset),bounds.position+Vector2(bounds.size.x,offset),colour,floor_y)
	var a := bounds.position
	var b := bounds.end
	for edge in [[a,Vector2(b.x,a.y)],[Vector2(b.x,a.y),b],[b,Vector2(a.x,b.y)],[Vector2(a.x,b.y),a]]:
		_line(mesh,layout,edge[0],edge[1],Color(.1,1.0,.46,.95),floor_y)
	mesh.surface_end()
	var result := MeshInstance3D.new()
	result.mesh = mesh
	result.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if grid:
		result.set_meta("base_y",floor_y)
	return result

static func _line(mesh: ImmediateMesh, layout: WorldLayout, a: Vector2, b: Vector2, colour: Color, floor_y: float = NAN) -> void:
	var count := ceili(a.distance_to(b)/4.0)
	for i in count:
		for at in [a.lerp(b,float(i)/count),a.lerp(b,float(i+1)/count)]:
			mesh.surface_set_color(colour)
			var y: float = floor_y if is_finite(floor_y) else maxf(WaveSurface.WATER_LEVEL,
				WorldTerrainStreamer.sample_render_terrain_height(layout,at))+.18
			mesh.surface_add_vertex(Vector3(at.x,y,at.y))
