extends Node3D
## Bounded debug presentation. Uses the actual bite envelope, not a second model.
const RANGE_M := 350.0
const LIMIT := 16
var _timer := 0.0
var _lines: ImmediateMesh
var _labels: Array[Label3D] = []
var _geometry: MeshInstance3D

func _ready()->void:
	top_level=true;global_transform=Transform3D.IDENTITY
	WorldGizmos.register(self,WorldGizmos.LAYER_FISHING)
	_lines=ImmediateMesh.new();_geometry=MeshInstance3D.new();_geometry.mesh=_lines
	var material:=StandardMaterial3D.new()
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo=true;material.no_depth_test=true
	_geometry.material_override=material
	_geometry.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_geometry)

func _process(delta:float)->void:
	visible=WorldGizmos.is_layer_enabled(WorldGizmos.LAYER_FISHING) and LocalPlayerView.get_active_ship()==get_parent().get_parent()
	if not visible or FishingField.habitat==null:return
	_timer-=delta
	if _timer>0:return
	_timer=.5
	var camera:=get_viewport().get_camera_3d()
	if camera!=null:_refresh(camera.global_position)

func _line(a:Vector3,b:Vector3,color:Color)->void:
	_lines.surface_set_color(color);_lines.surface_add_vertex(a);_lines.surface_add_vertex(b)

func _ring(center:Vector3,radius:float,color:Color)->void:
	for i in 64:
		var a:=TAU*i/64;var b:=TAU*(i+1)/64
		_line(center+Vector3(cos(a),0,sin(a))*radius,center+Vector3(cos(b),0,sin(b))*radius,color)

func _refresh(at:Vector3)->void:
	var hours:=WorldClock.get_game_hours_elapsed()
	var habitat:=FishingField.habitat
	var schools:=habitat.schools_near(Vector2(at.x,at.z),hours,RANGE_M)
	schools.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return a.position.distance_squared_to(Vector2(at.x,at.z))<b.position.distance_squared_to(Vector2(at.x,at.z)))
	_lines.clear_surfaces();_lines.surface_begin(Mesh.PRIMITIVE_LINES)
	var shown:=0
	var groups:Dictionary={}
	for school:Dictionary in schools:
		if shown>=LIMIT:break
		var area:=habitat.catch_area(school,hours)
		if area.is_empty():continue
		var palette:Dictionary={"cod":Color("ffd46c"),"mackerel":Color("7edfff"),"saithe":Color("83edb1"),"pollack":Color("c3a1ff"),"haddock":Color("ffb991"),"halibut":Color("f396c6")}
		var color:Color=palette.get(school.species,Color.WHITE)
		var top:=Vector3(school.position.x,WaveSurface.WATER_LEVEL-area.min_depth_m,school.position.y)
		var bottom:=Vector3(top.x,WaveSurface.WATER_LEVEL-area.max_depth_m,top.z)
		var surface:=Vector3(top.x,WaveSurface.WATER_LEVEL+.2,top.z)
		_ring(top,area.radius_m,color);_ring(bottom,area.radius_m,color)
		_ring(surface,3,color);_line(surface,top,color)
		for i in 8:
			var offset:=Vector3(cos(i*TAU/8),0,sin(i*TAU/8))*float(area.radius_m)
			_line(top+offset,bottom+offset,color)
		for fish:Dictionary in area.members:
			var p:Vector3=fish.position
			for axis in [Vector3.RIGHT,Vector3.UP,Vector3.BACK]:_line(p-axis*.6,p+axis*.6,color)
		var group_key:=str(school.id).substr(str(school.id).find(":")+1)
		if not groups.has(group_key):groups[group_key]={"position":surface,"lines":PackedStringArray()}
		groups[group_key].lines.append("%s · %d fish · %.1f–%.1f m"%[FishCatalog.species(school.species).name,area.members.size(),area.min_depth_m,area.max_depth_m])
		shown+=1
	var label_count:=0
	for group:Dictionary in groups.values():
		if label_count>=_labels.size():
			var label:=Label3D.new();label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
			label.no_depth_test=true;label.font_size=28;label.pixel_size=.12;label.outline_size=5
			add_child(label);_labels.append(label)
		var label:=_labels[label_count];label.visible=true;label.position=group.position+Vector3.UP*8
		label.text="70 m BAIT RADIUS\n"+"\n".join(group.lines)
		label_count+=1
	var station:=get_parent().get_parent().get_node_or_null("RodFishingStation") as RodFishingStation
	if station!=null and station.working and station.session.phase in ["fishing","bite","fighting"]:
		var hook:=station._hook_at()
		var p:=Vector3(hook.x,WaveSurface.WATER_LEVEL-station.session.depth_m,hook.y)
		_ring(p,2,Color.MAGENTA)
		_line(p-Vector3.UP*3,p+Vector3.UP*3,Color.MAGENTA)
	# ImmediateMesh requires vertices even when the local water has no schools.
	_line(at,at,Color.TRANSPARENT)
	_lines.surface_end()
	for i in range(label_count,_labels.size()):_labels[i].hide()
