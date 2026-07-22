class_name CharacterPreview
extends Node3D

## Turntable for menus and the character creator SubViewport. It deliberately
## uses the same JSON-backed CharacterVisual as gameplay NPCs and the F6
## wardrobe showcase, so onboarding can never drift back to a legacy body.

const TURN_SPEED := 0.55

var _pivot: Node3D
var _character: CharacterVisual
var _spin_enabled: bool = false
var _pending_appearance: CharacterAppearance = null


func _ready() -> void:
	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	# Character assets face local -Z (the same convention as vessel bows).
	# The menu camera looks in from +Z, so begin on the captain's front.
	_pivot.rotation.y = PI
	add_child(_pivot)
	_character = CharacterVisual.new()
	_character.name = "PreviewCharacter"
	# Body validation is the current gate. The retired wardrobe stays hidden
	# until the replacement body and complete motion set are approved.
	_character.decorated = false
	_pivot.add_child(_character)
	if _pending_appearance != null:
		apply_appearance(_pending_appearance)
		_pending_appearance = null


func _process(delta: float) -> void:
	if not _spin_enabled or _pivot == null:
		return
	_pivot.rotation.y += delta * TURN_SPEED


func apply_appearance(appearance: CharacterAppearance) -> void:
	if _character == null:
		_pending_appearance = appearance
		return
	if appearance == null:
		appearance = CharacterAppearance.default_appearance()
	_character.apply_appearance(appearance)


func set_spin_enabled(enabled: bool) -> void:
	_spin_enabled = enabled


static func camera_transform() -> Transform3D:
	var cam_pos := Vector3(0.0, 1.42, 2.35)
	var target := Vector3(0.0, 1.05, 0.0)
	var xf := Transform3D.IDENTITY
	xf.origin = cam_pos
	return xf.looking_at(target, Vector3.UP)
