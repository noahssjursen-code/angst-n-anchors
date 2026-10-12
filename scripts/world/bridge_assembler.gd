class_name BridgeAssembler
extends RefCounted

## Stamps Blender modules, then merges by surface finish into a few draws per bridge.
const PATH := "res://resources/models/bridges/"
static var _parts: Dictionary = {}
var _surfaces: Dictionary = {}
var _collision: Array[Dictionary] = []
var _plan: Dictionary

static func build(plan: Dictionary) -> Node3D:
	assert(plan.get("accepted",false))
	var builder := BridgeAssembler.new()
	builder._plan=plan
	return builder._build()

static func part(name: String) -> Mesh:
	if _parts.has(name): return _parts[name]
	var scene := load(PATH+name+".glb") as PackedScene
	assert(scene!=null,"Missing Blender bridge module: "+name)
	var root := scene.instantiate()
	var meshes := root.find_children("*","MeshInstance3D",true,false)
	assert(meshes.size()==1,"One mesh per modular bridge asset")
	var mesh: Mesh = meshes[0].mesh
	_parts[name]=mesh
	root.free()
	return mesh

func _stamp(name: String, transform: Transform3D, shaped: Mesh = null) -> void:
	var mesh := part(name) if shaped==null else shaped
	for surface in mesh.get_surface_count():
		var material_name := mesh.surface_get_material(surface).resource_name
		if not _surfaces.has(material_name):
			var tool := SurfaceTool.new()
			tool.begin(Mesh.PRIMITIVE_TRIANGLES)
			_surfaces[material_name]=tool
		_surfaces[material_name].append_from(mesh,surface,transform)

func _segment(name: String, a: Vector3, b: Vector3, width: float, depth: float, native_length := 1.0) -> void:
	var direction := (b-a).normalized()
	var up := Vector3.FORWARD if absf(direction.dot(Vector3.UP))>.98 else Vector3.UP
	var basis := Basis.looking_at(direction,up).scaled_local(Vector3(width,depth,a.distance_to(b)/native_length))
	_stamp(name,Transform3D(basis,a))

func _upright(name: String, x: float, z: float, bottom: float, top: float, width: float, depth: float) -> void:
	if top<=bottom: return
	var scale := Vector3(width,top-bottom,depth)
	_stamp(name,Transform3D(Basis.from_scale(scale),Vector3(x,bottom,z)))
	_collision.append({"size":scale,"transform":Transform3D(Basis.IDENTITY,Vector3(x,(bottom+top)*.5,z))})

func _deck(a: Vector3,b: Vector3, structure := true) -> void:
	var count := ceili(a.distance_to(b)/20.0)
	for i in count:
		var p := a.lerp(b,float(i)/count)
		var q := a.lerp(b,float(i+1)/count)
		_segment("deck_20m",p,q,1,1,20)
		if structure: _segment("girder_unit",p-Vector3.UP*.9,q-Vector3.UP*.9,1,1.2)
	var basis := Basis.looking_at((b-a).normalized(),Vector3.UP)
	_collision.append({"size":Vector3(12,.9,a.distance_to(b)),"transform":Transform3D(basis,(a+b)*.5-basis.y*.45)})
	for side in [-1,1]:
		_collision.append({"size":Vector3(.15,1.25,a.distance_to(b)),"transform":Transform3D(basis,(a+b)*.5+basis.x*side*5.7+basis.y*.75)})

func _build() -> Node3D:
	var length: float = _plan.length
	var y: float = _plan.deck_y
	var root := Node3D.new()
	root.name="Bridge_"+_plan.family
	root.set_meta("bridge_plan",_plan)
	var a: Vector2 = _plan.a
	var b: Vector2 = _plan.b
	root.position=Vector3(a.x,0,a.y)
	root.basis=Basis.looking_at(Vector3(b.x-a.x,0,b.y-a.y).normalized(),Vector3.UP)
	_deck(Vector3(0,y,0),Vector3(0,y,-length),_plan.family!="cantilever")
	for i in 2:
		var local: Vector3 = root.transform.affine_inverse()*_plan.approaches[i]
		var end := Vector3(0,y,-length*i)
		_deck(local,end)
		# Landfall blocks meet actual terrain; approach viaducts end here.
		_stamp("abutment_unit",Transform3D(Basis.from_scale(Vector3(1,maxf(3,local.y-_plan.landing_bases[i]),1)),local))
		_upright("pier_unit",0,-length*i,_plan.end_bases[i],y-2.1,9,3)
		# Piers under approaches are added from terrain samples by world placement.
	for item: Dictionary in _plan.approach_piers:
		var at: Vector3 = root.transform.affine_inverse()*item.at
		_upright("pier_unit",at.x,at.z,item.base,at.y-2.0,4,3)
	for i in _plan.supports.size():
		var s: float = _plan.supports[i]
		var base: float = _plan.bases[i]
		if _plan.family=="suspension":
			var tower_top := y+maxf(35,(_plan.supports[1]-_plan.supports[0])*.14)
			for side in [-1,1]: _upright("tower_leg_unit",side*8.2,-s,base,tower_top,3.5,5)
			for h in [y-4,tower_top-3]:
				_stamp("tower_crossbeam_unit",Transform3D(Basis.from_scale(Vector3(20,3,4)),Vector3(0,h,-s)))
		else:
			_upright("pier_unit",0,-s,base,y-2.2,5,3.5)
			_stamp("pier_cap",Transform3D(Basis.IDENTITY,Vector3(0,y-.9,-s)))
	if _plan.family=="arch": _arch(length,y)
	if _plan.family=="cantilever": _cantilever(length,y)
	if _plan.family=="suspension": _suspension(length,y)
	for link: Array in _plan.get("road_links", []):
		_ground_road(link,root.transform.affine_inverse())
	for material_name: String in _surfaces:
		var spec: Array = {"Concrete":["concrete_cast",Color(.68,.69,.67)],"Asphalt":["asphalt",Color(.3,.31,.32)],"Steel":["brushed_steel",Color(.43,.47,.5)],"Marking":["roof_enamel",Color(.88,.82,.58)]}[material_name]
		var instance := MeshInstance3D.new()
		instance.mesh=_surfaces[material_name].commit()
		instance.material_override=SurfaceMaterialLibrary.material(spec[0],spec[1])
		# Bridge-wide visibility is controlled by distance to the span, not its origin.
		# Fine railings/markings disappear first; structural cables remain visible.
		instance.visibility_range_end=5000 if material_name=="Marking" else 0
		instance.visibility_range_end_margin=250
		root.add_child(instance)
		SurfaceMaterialLibrary.set_mapping(instance,Transform3D.IDENTITY)
	var body := StaticBody3D.new()
	body.name="BridgeCollision"
	root.add_child(body)
	for item in _collision:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size=item.size
		shape.shape=box; shape.transform=item.transform
		body.add_child(shape)
	return root

func _arch(length: float,y: float) -> void:
	var left: float = _plan.supports[0]
	var right: float = _plan.supports[1]
	var rise := maxf(8,y-WaveSurface.WATER_LEVEL-7)
	for side in [-1,1]:
		for i in 32:
			var t := float(i)/32
			var u := float(i+1)/32
			var a := Vector3(side*3.5,y-3-rise*pow(2*t-1,2),-lerpf(left,right,t))
			var b := Vector3(side*3.5,y-3-rise*pow(2*u-1,2),-lerpf(left,right,u))
			_segment("arch_rib_unit",a,b,2,1.8)
			_collision.append({"size":Vector3(2,1.8,a.distance_to(b)),"transform":Transform3D(Basis.looking_at((b-a).normalized(),Vector3.UP),(a+b)*.5)})
			if i%2==0: _upright("pier_unit",a.x,a.z,a.y,y-2.1,.65,.65)

func _cantilever(length: float,y: float) -> void:
	for i in ceili(length/10):
		var s := minf(length,i*10.0)
		var end := minf(length,s+10)
		var source := part("girder_unit")
		var shaped := ArrayMesh.new()
		for surface in source.get_surface_count():
			var arrays := source.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for v in vertices.size():
				var at := lerpf(s,end,-vertices[v].z)
				var nearest := length
				for support in _plan.supports: nearest=minf(nearest,absf(at-support))
				vertices[v].y*=1.5+6*pow(maxf(0,1-nearest/120),2)
			arrays[Mesh.ARRAY_VERTEX]=vertices
			shaped.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
			shaped.surface_set_material(surface,source.surface_get_material(surface))
		_stamp("girder_unit",Transform3D(Basis.from_scale(Vector3(1,1,end-s)),Vector3(0,y-.9,-s)),shaped)

func _suspension(length: float,y: float) -> void:
	var left: float = _plan.supports[0]
	var right: float = _plan.supports[1]
	var rise := maxf(35,(right-left)*.14)
	for side in [-1,1]:
		var x: float = side*6.8
		_segment("cable_unit",Vector3(x,y+2,0),Vector3(x,y+rise,-left),.6,.6)
		_segment("cable_unit",Vector3(x,y+rise,-right),Vector3(x,y+2,-length),.6,.6)
		for end in [0.0,length]:
			var ground: float = _plan.end_bases[0] if end==0 else _plan.end_bases[1]
			var height := y+3-ground
			_stamp("anchor_block",Transform3D(Basis.from_scale(Vector3(1,height/5,1)),Vector3(x,ground+height*.5,-end)))
			_collision.append({"size":Vector3(7,height,9),"transform":Transform3D(Basis.IDENTITY,Vector3(x,ground+height*.5,-end))})
		# Side spans are suspended too; hangers terminate on the deck edge.
		for interval in [[0.0,left],[right,length]]:
			var side_count := ceili((interval[1]-interval[0])/12.0)
			for i in range(1,side_count):
				var t := float(i)/side_count
				var s: float = lerpf(interval[0],interval[1],t)
				var h := lerpf(2,rise,t) if interval[0]==0 else lerpf(rise,2,t)
				_segment("cable_unit",Vector3(side*5.7,y,-s),Vector3(x,y+h,-s),.1,.1)
		var count := ceili((right-left)/12)
		for i in count:
			var t := float(i)/count
			var u := float(i+1)/count
			var a := Vector3(x,y+6+(rise-6)*pow(2*t-1,2),-lerpf(left,right,t))
			var b := Vector3(x,y+6+(rise-6)*pow(2*u-1,2),-lerpf(left,right,u))
			_segment("cable_unit",a,b,.6,.6)
			_segment("cable_unit",Vector3(side*5.7,y,a.z),a,.1,.1)



func _ground_road(sections: Array, to_local: Transform3D) -> void:
	if sections.size()<2: return
	var surface:=SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(sections.size()-1):
		var a: Vector3 = to_local*sections[i].left
		var b: Vector3 = to_local*sections[i].right
		var c: Vector3 = to_local*sections[i+1].left
		var d: Vector3 = to_local*sections[i+1].right
		var near_points:PackedVector3Array=sections[i].get("surface",PackedVector3Array([sections[i].left,sections[i].right]))
		var far_points:PackedVector3Array=sections[i+1].get("surface",PackedVector3Array([sections[i+1].left,sections[i+1].right]))
		for strip in range(near_points.size()-1):
			var p:=to_local*near_points[strip];var q:=to_local*near_points[strip+1]
			var r:=to_local*far_points[strip];var s:=to_local*far_points[strip+1]
			for triangle in [[p,r,q],[q,r,s]]:
				var normal:Vector3=(triangle[2]-triangle[0]).cross(triangle[1]-triangle[0]).normalized()
				if normal.y<0: triangle.reverse();normal=-normal
				for point:Vector3 in triangle:
					surface.set_normal(normal);surface.set_uv(Vector2(point.x,point.z)*.1);surface.add_vertex(point)
		var from:=(a+b)*.5
		var to:=(c+d)*.5
		var basis:=Basis.looking_at((to-from).normalized(),Vector3.UP)
		_collision.append({"size":Vector3(a.distance_to(b),.18,from.distance_to(to)),"transform":Transform3D(basis,(from+to)*.5-Vector3.UP*.09)})

	surface.index()
	_surfaces["Asphalt"].append_from(surface.commit(),0,Transform3D.IDENTITY)
