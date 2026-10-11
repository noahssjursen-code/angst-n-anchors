@tool
class_name PortFacilityVisual
extends RefCounted

const KIT := preload("res://scripts/port/harbour_environment_kit.gd")
const ROOT := "res://resources/models/parts/port_facilities/"

static func part(parent: Node3D,id: String,position: Vector3,yaw: float=0.0) -> Node3D:
	return KIT.model(parent,ROOT+id+".glb",position,yaw)

static func build(parent: Node3D,record: Dictionary,top: float) -> Node3D:
	var root := Node3D.new()
	root.name = str(record.id)
	parent.add_child(root)
	root.position = Vector3(record.origin[0],top,record.origin[1])
	root.rotation.y=float(record.get("rotation_y",0.0))
	root.set_meta("facility_record",record.duplicate(true))
	var size := Vector2(record.size_m[0],record.size_m[1])
	var kind := str(record.kind)
	if kind=="office":
		office(root,size)
		return root
	fence(root,size)
	# Unmarked manoeuvring aisle: highway centre stripes don't belong inside yards.
	match kind:
		"general","fishing":
			for side in [-1,1]:
				var x: float = side*(size.x*.25)
				var z: float = size.y*.5-6
				pallet_storage(root,Vector3(x,0,-size.y*.5+11),side)
				if kind=="general" and side==-1 and size.y>=30:
					var warehouse := KIT.model(root,"warehouse_12x18",Vector3(x,0,size.y*.5-11),PI)
					KIT.solid(warehouse,Vector3(0,2.7,0),Vector3(12,5.4,18))
					continue
				var shelter := part(root,"cargo_shelter_8m",Vector3(x,0,z))
				for sx in [-3.7,3.7]:
					for sz in [-3.7,3.7]: KIT.solid(shelter,Vector3(sx,2.5,sz),Vector3(.20,5,.20))
				for i in 2:
					var rack := part(root,"loaded_storage_rack",Vector3(x-1.8+i*3.6,0,z+2))
					KIT.solid(rack,Vector3(0,2.4,0),Vector3(3.1,4.8,1.3))
				if kind=="fishing":
					var poses: Array[Transform3D] = []
					for i in 3: poses.append(Transform3D(Basis.IDENTITY,Vector3(x-2+i*2,.01,z-2)))
					KIT.repeated(root,"drain_2m",poses)
				storage_bays(root,x,size.y)
		"bulk_ore":
			for side in [-1,1]:
				var x: float=side*size.x*.27
				var segments := 3 if size.x>=40 else 2
				for z in [-size.y*.25,size.y*.25]:
					for i in segments:
						var wall := part(root,"bulk_divider_4m",Vector3(x-(segments-1)*2+i*4,0,z))
						KIT.solid(wall,Vector3(0,1.35,0),Vector3(4,2.7,.32))
				# Close the outside edge: paired bays open toward the handling lane.
				var count := maxi(1,int(round(size.y*.5/4)))
				var pitch := size.y*.5/count
				for i in count:
					var wall := part(root,"bulk_divider_4m",Vector3(x+side*segments*2,0,-size.y*.25+(i+.5)*pitch),PI*.5)
					wall.scale.x=pitch/4
					KIT.solid(wall,Vector3(0,1.35,0),Vector3(4,2.7,.32))
		"bulk_grain","diesel","crude_oil","lng":
			if size.x>=56:
				industrial_storage(root,size,kind)
				return root
			var model := "grain_silo" if kind=="bulk_grain" else "insulated_gas_vessel" if kind=="lng" else "liquid_tank"
			for side in [-1,1]:
				var node := part(root,model,Vector3(side*size.x*.27,0,2))
				if kind=="bulk_grain":
					KIT.solid(node,Vector3(0,6.5,0),Vector3(5.1,8,5.1))
					for i in 6:
						var a := i*TAU/6
						KIT.solid(node,Vector3(cos(a)*2.2,1.8,sin(a)*2.2),Vector3(.2,3.6,.2))
				elif kind=="lng": KIT.solid(node,Vector3(0,2.1,0),Vector3(3.2,3.2,8.1))
				else: KIT.solid(node,Vector3(0,3.2,0),Vector3(6,6.4,6))
			if kind!="bulk_grain":
				for side in [-1,1]:
					for i in range(maxi(1,int(size.y/4)-2)):
						var wall := part(root,"bulk_divider_4m",Vector3(side*(size.x*.5-2),0,-size.y*.5+5+i*4),PI*.5)
						KIT.solid(wall,Vector3(0,1.35,0),Vector3(4,2.7,.32))
		"container":
			# Reserve real freight slots; decorative container stock was dropped.
			for side in [-1,1]:
				for i in range(maxi(1,int((size.x*.5-5)/3))):
					var node := Node3D.new(); root.add_child(node)
					node.position=Vector3(side*(6+i*3),0,1)
					outline(node,Vector2(2.6,12.4))
	var label := Label3D.new()
	label.text = kind.replace("_"," ").to_upper()+"\n"+", ".join(record.commodity_ids)
	label.font_size = 40
	label.pixel_size = .014
	label.position = Vector3(-size.x*.5+4,2.3,-size.y*.5+1)
	label.modulate = Color(.88,.85,.7)
	root.add_child(label)
	return root

static func outline(root: Node3D,size: Vector2,open_front: bool=false) -> void:
	var p := [Vector3(-size.x*.5,.015,-size.y*.5),Vector3(size.x*.5,.015,-size.y*.5),Vector3(size.x*.5,.015,size.y*.5),Vector3(-size.x*.5,.015,size.y*.5)]
	for i in 4:
		if i==0 and open_front:
			KIT.line(root,p[0],Vector3(-3.5,.015,-size.y*.5),.10)
			KIT.line(root,Vector3(3.5,.015,-size.y*.5),p[1],.10)
		else: KIT.line(root,p[i],p[(i+1)%4],.10)

static func storage_bays(root: Node3D,x: float,depth: float) -> void:
	for i in range(maxi(1,int((depth-14)/6))):
		var node := Node3D.new(); root.add_child(node)
		node.position = Vector3(x,0,-depth*.5+4+i*6)
		# Corner marks identify storage bays without turning the yard into graph paper.
		for sx in [-1,1]:
			for sz in [-1,1]:
				var corner := Vector3(sx*3.5,.015,sz*2.5)
				KIT.line(node,corner,corner-Vector3(sx*.8,0,0),.12)
				KIT.line(node,corner,corner-Vector3(0,0,sz*.8),.12)

static func fence(root: Node3D,size: Vector2) -> void:
	var poses: Array[Transform3D] = []
	var w := size.x-2
	var d := size.y-2
	var nx := maxi(1,int(w/4))
	for i in nx: poses.append(Transform3D(Basis.IDENTITY.scaled(Vector3(w/nx/4,1,1)),Vector3(-w*.5+(i+.5)*w/nx,0,d*.5)))
	var nz := maxi(1,int(d/4))
	for side in [-1,1]:
		for i in nz: poses.append(Transform3D(Basis(Vector3.UP,PI*.5).scaled_local(Vector3(d/nz/4,1,1)),Vector3(side*w*.5,0,-d*.5+(i+.5)*d/nz)))
	KIT.repeated(root,ROOT+"yard_fence_4m.glb",poses)
	# Rails/fence bodies are intentional obstacles; the frontage stays open.
	KIT.solid(root,Vector3(0,1.1,d*.5),Vector3(w,2.2,.1))
	for side in [-1,1]: KIT.solid(root,Vector3(side*w*.5,1.1,0),Vector3(.1,2.2,d))

static func office(root: Node3D,size: Vector2) -> void:
	var large := size.x>=38 and size.y>=40
	var back := size.y*.5-(8 if large else 5)
	var building := part(root,"harbour_authority_20m" if large else "harbour_office",Vector3(0,0,back),PI)
	building.set_meta("office_shell",true)
	building.set_meta("front_wall",7.0 if large else 4.0)
	KIT.solid(building,Vector3(0,6.5 if large else 1.75,0),Vector3(20,13,14) if large else Vector3(12,3.5,8))
	KIT.solid(building,Vector3(0,.1,8.4) if large else Vector3(0,.11,4.85),Vector3(5,.2,2.8) if large else Vector3(2.5,.22,1.6))
	if large: back-=3.5 # Forecourt and kerbs respect the deeper building frontage.
	root.set_meta("staff_local",Vector3(0,0,back-8))
	for side in [-1,1]:
		var count := maxi(1,int((size.x*.5-(6 if side<0 else 4))/2.8))
		for i in count:
			var x: float=side*(4.5+i*2.8)
			var z: float=-size.y*.5+9
			var bay := Node3D.new();root.add_child(bay);bay.position=Vector3(x,0,z)
			KIT.line(bay,Vector3(-1.3,.018,-2.6),Vector3(-1.3,.018,2.6),.10)
			KIT.line(bay,Vector3(1.3,.018,-2.6),Vector3(1.3,.018,2.6),.10)
			KIT.line(bay,Vector3(-1.3,.018,2.6),Vector3(1.3,.018,2.6),.10)
			var stop := part(bay,"wheel_stop",Vector3(0,0,2.1))
			KIT.solid(stop,Vector3(0,.085,0),Vector3(1.65,.17,.17))
	# Public footway sits beside vehicle circulation and joins the office forecourt.
	var walk_x := -size.x*.5+1.5
	var walk_end := back-5.4
	var walk_start := -size.y*.5
	paving_patch(root,Vector3(walk_x,.04,(walk_start+walk_end)*.5),Vector2(2.4,walk_end-walk_start),Color(.12,.13,.125))
	paving_patch(root,Vector3(0,.04,back-6.0),Vector2(size.x-3,4.0),Color(.12,.13,.125))
	kerb_run(root,Vector3(-size.x*.5+.2,0,-size.y*.5),Vector3(-size.x*.5+.2,0,back-5))
	kerb_run(root,Vector3(size.x*.5-.2,0,-size.y*.5),Vector3(size.x*.5-.2,0,back-5))
	for side in [-1,1]:
		kerb_run(root,Vector3(side*4,0,-size.y*.5),Vector3(side*(size.x*.5-(2.8 if side<0 else .2)),0,-size.y*.5))
	for side in [-1,1]:
		var light := KIT.model(root,"quay_light",Vector3(side*(size.x*.5-2),0,-size.y*.5+2),PI)
		KIT.solid(light,Vector3(0,3.75,0),Vector3(.24,7.5,.24))
	if large:
		# The enlarged office forecourt is outside the entrance-corner lamps'
		# reach. Give its pedestrian approach its own paired fixtures, keeping
		# the central entrance and vehicle lanes clear.
		for side in [-1,1]:
			var light := KIT.model(root,"quay_light",Vector3(side*8,0,back-12),PI)
			KIT.solid(light,Vector3(0,3.75,0),Vector3(.24,7.5,.24))
	for side in [-1,1]:
		for i in 2:
			var kerb := part(root,"kerb_2m",Vector3(side*(2.6+i*2),0,back-6.0))
			KIT.solid(kerb,Vector3(0,.10,0),Vector3(2,.20,.22))

static func paving_patch(root: Node3D,center: Vector3,size: Vector2,color: Color) -> void:
	var node := MeshInstance3D.new()
	node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var plane := PlaneMesh.new(); plane.size=size
	node.mesh=plane
	var material := KIT.paving().duplicate() as ShaderMaterial
	material.set_shader_parameter("pavement_color",Vector3(color.r,color.g,color.b))
	node.material_override=material
	root.add_child(node); node.position=center
	KIT.solid(root,center-Vector3(0,.025,0),Vector3(size.x,.05,size.y))

static func kerb_run(root: Node3D,a: Vector3,b: Vector3) -> void:
	var length := a.distance_to(b)
	var count := maxi(1,int(ceil(length/2)))
	var direction := (b-a).normalized()
	for i in count:
		var node := part(root,"kerb_2m",a+direction*((i+.5)*length/count),-atan2(direction.z,direction.x))
		node.scale.x=length/count/2
		KIT.solid(node,Vector3(0,.1,0),Vector3(2,.2,.22))

static func site_boundary(root: Node3D,plan: Dictionary,top: float) -> void:
	var outline_points := PortFacilityPlan.points(plan.get("boundary",[]))
	if outline_points.size()<4: return
	var poses: Array[Transform3D] = []
	# Inland perimeter only; quays and the waterfront remain open for operations.
	for i in range(outline_points.size()/2,outline_points.size()-1):
		var a := outline_points[i]; var b := outline_points[i+1]
		var length := a.distance_to(b)
		var direction := (b-a).normalized()
		var count := maxi(1,int(ceil(length/4)))
		for j in count:
			var p := a.lerp(b,(j+.5)/count)
			var entrance := false
			for route in plan.get("routes",[]):
				if route.id!="land_access": continue
				if p.distance_to(Vector2(route.b[0],route.b[1]))<8: entrance=true
			if entrance: continue
			var basis := Basis(Vector3.UP,-atan2(direction.y,direction.x))
			poses.append(Transform3D(basis.scaled_local(Vector3(length/count/4,1,1)),Vector3(p.x,top,p.y)))
			var body := Node3D.new(); root.add_child(body)
			body.position=Vector3(p.x,top,p.y); body.basis=basis
			KIT.solid(body,Vector3(0,1.1,0),Vector3(length/count,2.2,.1))
	KIT.repeated(root,ROOT+"yard_fence_4m.glb",poses)

static func pallet_storage(root: Node3D,origin: Vector3,side: int) -> void:
	var poses: Array[Transform3D]=[]
	for column in 5:
		for row in 3:
			var height := 6+(column+row*3)%7
			var p := origin+Vector3((column-2)*1.6,0,row*1.2)
			for level in height:
				poses.append(Transform3D(Basis(Vector3.UP,.018*side*(level%3)),p+Vector3(0,level*.20,0)))
			KIT.solid(root,p+Vector3(0,height*.1,0),Vector3(1.2,height*.2,.8))
	KIT.repeated(root,ROOT+"yard_pallet.glb",poses)

static func industrial_storage(root: Node3D,size: Vector2,kind: String) -> void:
	var model := "lng_terminal_tank_24m" if kind=="lng" else "grain_silo" if kind=="bulk_grain" else "liquid_tank"
	for side in [-1,1]:
		var x: float=side*size.x*.25
		if kind=="bulk_grain":
			for row in 3:
				var silo := part(root,model,Vector3(x,0,-size.y*.15+row*10))
				silo.scale=Vector3(1.4,1.7,1.4)
				KIT.solid(silo,Vector3(0,5.5,0),Vector3(5.1,11,5.1))
		else:
			var tank := part(root,model,Vector3(x,0,2))
			if kind=="lng": round_collision(tank,12,22,11)
			else:
				# Existing vertical tank family, scaled as an industrial tank rather than a yard drum.
				tank.scale=Vector3(3,2.5,3)
				round_collision(tank,3,6.4,3.2)
			var rows := int((size.y-8)/4)
			for i in rows:
				var wall := part(root,"bulk_divider_4m",Vector3(side*(size.x*.5-3),0,-size.y*.5+6+i*4),PI*.5)
				KIT.solid(wall,Vector3(0,1.35,0),Vector3(4,2.7,.32))

static func round_collision(parent: Node3D,radius: float,height: float,center_y: float) -> void:
	var body := StaticBody3D.new()
	parent.add_child(body)
	var collider := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius=radius
	shape.height=height
	collider.shape=shape
	collider.position.y=center_y
	body.add_child(collider)
