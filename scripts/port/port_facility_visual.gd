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
	root.set_meta("facility_record",record.duplicate(true))
	var size := Vector2(record.size_m[0],record.size_m[1])
	var kind := str(record.kind)
	outline(root,size-Vector2(1,1),true)
	if kind=="office":
		office(root,size)
		return root
	fence(root,size)
	KIT.lane(root,Vector3(0,.013,-size.y*.5),Vector3(0,.013,size.y*.5-3),7.0)
	match kind:
		"general","fishing":
			for side in [-1,1]:
				var x: float = side*(size.x*.25)
				var z: float = size.y*.5-6
				var shelter := part(root,"cargo_shelter_8m",Vector3(x,0,z))
				for sx in [-3.7,3.7]:
					for sz in [-3.7,3.7]: KIT.solid(shelter,Vector3(sx,2.5,sz),Vector3(.20,5,.20))
				for i in 3:
					part(root,"empty_pallet",Vector3(x-2+i*1.6,0,z+2))
				if kind=="fishing":
					var poses: Array[Transform3D] = []
					for i in 3: poses.append(Transform3D(Basis.IDENTITY,Vector3(x-2+i*2,.01,z-2)))
					KIT.repeated(root,"drain_2m",poses)
				storage_bays(root,x,size.y)
		"bulk_ore":
			for side in [-1,1]:
				var x: float=side*size.x*.27
				for z in [-size.y*.25,size.y*.25]:
					for i in 2:
						var wall := part(root,"bulk_divider_4m",Vector3(x-2+i*4,0,z))
						KIT.solid(wall,Vector3(0,1.35,0),Vector3(4,2.7,.32))
				# Close the outside edge: paired bays open toward the handling lane.
				var count := maxi(1,int(round(size.y*.5/4)))
				var pitch := size.y*.5/count
				for i in count:
					var wall := part(root,"bulk_divider_4m",Vector3(x+side*4,0,-size.y*.25+(i+.5)*pitch),PI*.5)
					wall.scale.x=pitch/4
					KIT.solid(wall,Vector3(0,1.35,0),Vector3(4,2.7,.32))
		"bulk_grain","diesel","crude_oil","lng":
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
			# Empty physical-size storage slots: inventory is supplied by freight,
			# never by random decorative loaded containers.
			for side in [-1,1]:
				for i in range(maxi(1,int((size.x*.5-5)/3))):
					var node := Node3D.new(); root.add_child(node)
					node.position = Vector3(side*(6+i*3),0,1)
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
		outline(node,Vector2(7,5))

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
	var back := size.y*.5-5
	var building := part(root,"harbour_office",Vector3(0,0,back),PI)
	building.set_meta("office_shell",true)
	KIT.solid(building,Vector3(0,1.75,0),Vector3(12,3.5,8))
	KIT.solid(building,Vector3(0,.11,4.85),Vector3(2.5,.22,1.6))
	root.set_meta("staff_local",Vector3(0,0,back-8))
	for side in [-1,1]:
		var count := maxi(1,int((size.x*.5-4)/2.8))
		for i in count:
			var x: float=side*(4.5+i*2.8)
			var z: float=-size.y*.5+9
			var bay := Node3D.new();root.add_child(bay);bay.position=Vector3(x,0,z)
			outline(bay,Vector2(2.6,5.2))
			var stop := part(bay,"wheel_stop",Vector3(0,0,2.1))
			KIT.solid(stop,Vector3(0,.085,0),Vector3(1.65,.17,.17))
		KIT.line(root,Vector3(side*1.1,.018,-size.y*.5),Vector3(side*1.1,.018,back-5.9),.15)
	for side in [-1,1]:
		var light := KIT.model(root,"quay_light",Vector3(side*(size.x*.5-2),0,-size.y*.5+2),PI)
		KIT.solid(light,Vector3(0,3.75,0),Vector3(.24,7.5,.24))
	for side in [-1,1]:
		for i in 2:
			var kerb := part(root,"kerb_2m",Vector3(side*(2.6+i*2),0,back-6.0))
			KIT.solid(kerb,Vector3(0,.10,0),Vector3(2,.20,.22))
