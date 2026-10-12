class_name CoastalBridgePreview
extends Node3D

## Lazy, worker-planned debug layer. Off by default and never physical.
var _layout: WorldLayout
var _settlements: Array
var _ports: Array
var _worker: Thread
var _built := false
var report: Dictionary = {}

func configure(layout: WorldLayout, ports: Array, settlements: Array = []) -> void:
	_layout=layout
	_ports=ports.duplicate()
	_settlements=settlements.duplicate(true)

func _ready() -> void:
	WorldGizmos.register(self,WorldGizmos.LAYER_BRIDGES)
	visibility_changed.connect(_maybe_start)
	_maybe_start()

func _maybe_start() -> void:
	if not is_visible_in_tree() or _built or _worker!=null or _layout==null: return
	_worker=Thread.new()
	_worker.start(CoastalBridgePlan.build.bind(_layout,_ports,_settlements))

func _process(_delta: float) -> void:
	if _worker==null or _worker.is_alive(): return
	report=_worker.wait_to_finish()
	_worker=null
	_built=true
	populate(self,report)
	print("Bridge preview: %d selected / %d candidates in %.0f ms" % [report.bridges.size(),report.candidate_count,report.build_ms])
	set_process(false)

func _exit_tree() -> void:
	if _worker!=null:
		_worker.wait_to_finish()
		_worker=null

static func populate(root: Node3D, plan: Dictionary) -> void:
	for record: Dictionary in plan.bridges:
		var a := Vector3(record.a_xz.x,record.deck_y,record.a_xz.y)
		var b := Vector3(record.b_xz.x,record.deck_y,record.b_xz.y)
		var colour := Color(1,.85,.05,.38) if record.island_component>=0 else Color(.1,1,.5,.38)
		var mesh := BoxMesh.new()
		mesh.size=Vector3(12,3,a.distance_to(b))
		var span := MeshInstance3D.new()
		span.mesh=mesh
		span.material_override=_material(colour)
		span.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(span)
		span.position=(a+b)*.5
		span.look_at_from_position(span.position,b)
		for end in [{"at":a,"ground":record.a_ground,"color":Color(.1,.8,1)},
				{"at":b,"ground":record.b_ground,"color":Color(1,.2,.65)}]:
			var sphere := SphereMesh.new()
			sphere.radius=8; sphere.height=16
			var marker := MeshInstance3D.new()
			marker.mesh=sphere; marker.material_override=_material(end.color)
			marker.position=end.at
			root.add_child(marker)
			var post := MeshInstance3D.new()
			var stem := CylinderMesh.new()
			stem.top_radius=1.5; stem.bottom_radius=1.5
			stem.height=maxf(1,record.deck_y-end.ground)
			post.mesh=stem; post.material_override=marker.material_override
			post.position=Vector3(end.at.x,end.ground+stem.height*.5,end.at.z)
			root.add_child(post)
		var label := Label3D.new()
		label.text="#%d  %s\n%.0f m span | banks %.0f / %.0f m\n35 m minimum preview deck; approaches unresolved" % [record.id,record.kind,record.span_m,record.a_ground,record.b_ground]
		if plan.has("structures"):
			for structure: Dictionary in plan.structures:
				if structure.source.id==record.id:
					label.text="#%d %s | %s | %.0f m\nDeck %.0f m; physical structure built" % [record.id,record.kind,structure.family,record.span_m,structure.deck_y]
			for rejected: Dictionary in plan.rejected:
				if rejected.id==record.id: label.text="#%d NOT BUILT\n%s" % [record.id,rejected.reason]
		label.font_size=40; label.pixel_size=.35
		label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
		label.position=(a+b)*.5+Vector3.UP*40
		root.add_child(label)

static func _material(colour: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color=colour
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	if colour.a<1: material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode=BaseMaterial3D.CULL_DISABLED
	return material
