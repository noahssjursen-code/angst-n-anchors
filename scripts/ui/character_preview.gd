class_name CharacterPreview
extends Node3D

## Turntable NpcBase for menus and the character creator SubViewport.

const TURN_SPEED := 0.55

var _pivot: Node3D
var _npc: NpcBase
var _spin_enabled: bool = true
var _pending_appearance: CharacterAppearance = null


func _ready() -> void:
	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	add_child(_pivot)
	_npc = NpcBase.new()
	_npc.name = "PreviewNpc"
	_pivot.add_child(_npc)
	if _pending_appearance != null:
		apply_appearance(_pending_appearance)
		_pending_appearance = null


func _process(delta: float) -> void:
	if not _spin_enabled or _pivot == null:
		return
	_pivot.rotation.y += delta * TURN_SPEED


func apply_appearance(appearance: CharacterAppearance) -> void:
	if _npc == null:
		_pending_appearance = appearance
		return
	if appearance == null:
		appearance = CharacterAppearance.default_appearance()
	appearance.apply_to_npc(_npc)


func set_spin_enabled(enabled: bool) -> void:
	_spin_enabled = enabled


static func camera_transform() -> Transform3D:
	var cam_pos := Vector3(0.0, 1.42, 2.35)
	var target := Vector3(0.0, 1.05, 0.0)
	var xf := Transform3D.IDENTITY
	xf.origin = cam_pos
	return xf.looking_at(target, Vector3.UP)
