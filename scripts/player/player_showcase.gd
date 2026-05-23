@tool
class_name PlayerShowcase
extends Node3D

## Lays out a grid of players with different character configurations (skin tones, 
## clothing styles, and hat accessories) to showcase customization and look and feel.
## Tick the `rebuild` checkbox in the inspector to refresh after any visual updates.

const WALK_ANIMATOR_SCRIPT := preload("res://scripts/npc/walk_animator.gd")

const ROW_GAP := 3.5
const COL_GAP := 2.2
const LABEL_H := 2.5

@export var rebuild: bool = false:
	set(v):
		if v and is_inside_tree():
			_rebuild()

@export_group("Display Options")
@export var show_ground_pad: bool = true:
	set(v):
		show_ground_pad = v
		if is_inside_tree():
			_rebuild()

@export var show_labels: bool = true:
	set(v):
		show_labels = v
		if is_inside_tree():
			_rebuild()

@export var animate_walking: bool = true:
	set(v):
		animate_walking = v
		# Don't trigger full rebuild; just toggle or reset animation clock
		if not animate_walking:
			_reset_limb_rotations()

@export var spin_players: bool = false:
	set(v):
		spin_players = v

@export var spin_speed: float = 0.5

# Tracks active visual animators: NpcBase -> { "animator": WalkAnimator, "distance": float }
var _animators: Dictionary = {}
var _npc_nodes: Array[NpcBase] = []
var _animation_clock: float = 0.0


func _ready() -> void:
	_rebuild()


func _process(delta: float) -> void:
	if Engine.is_editor_hint() and not is_inside_tree():
		return

	if animate_walking:
		_animation_clock += delta
		# Update procedural walk cycles for all active animators
		for npc in _animators.keys():
			if is_instance_valid(npc):
				var anim_state = _animators[npc]
				var animator = anim_state["animator"]
				if animator.is_ready():
					# Walk in-place by simulating continuous cumulative distance
					anim_state["distance"] += delta * 1.5
					animator.update(anim_state["distance"])

	if spin_players:
		var spin_delta = delta * spin_speed
		for npc in _npc_nodes:
			if is_instance_valid(npc):
				npc.rotate_y(spin_delta)


func _rebuild() -> void:
	# Clear previous preview children
	for child in get_children():
		if Engine.is_editor_hint():
			child.free()
		else:
			child.queue_free()

	_animators.clear()
	_npc_nodes.clear()
	_animation_clock = 0.0

	var grid_definition := _get_grid_definition()
	var row_count := grid_definition.size()
	var max_col_count := 0
	for row_def in grid_definition:
		max_col_count = maxi(max_col_count, row_def["columns"].size())

	# 1. Spawn a visual Ground Pad
	if show_ground_pad and row_count > 0:
		var pad := MeshInstance3D.new()
		pad.name = "GroundPad"
		var bm := BoxMesh.new()
		var pad_w := float(max_col_count) * COL_GAP + 2.0
		var pad_d := float(row_count) * ROW_GAP + 1.0
		bm.size = Vector3(pad_w, 0.12, pad_d)
		pad.mesh = bm
		pad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.12, 0.14, 0.16)
		mat.roughness = 0.85
		pad.material_override = mat
		
		# Center the pad over the rows and columns
		pad.position = Vector3(
			(float(max_col_count - 1) * COL_GAP) * 0.5,
			0.06,
			(float(row_count - 1) * ROW_GAP) * 0.5
		)
		add_child(pad)
		pad.owner = _scene_owner()

	# 2. Lay out rows and columns
	for row_idx in row_count:
		var row_def := grid_definition[row_idx] as Dictionary
		var row_label: String = row_def["name"]
		var cols: Array = row_def["columns"]
		var z_pos := float(row_idx) * ROW_GAP

		# Place a Category label on the left side of each row
		if show_labels and cols.size() > 0:
			var category_lbl := Label3D.new()
			category_lbl.text = "=== " + row_label.to_upper() + " ==="
			category_lbl.font_size = 32
			category_lbl.modulate = HudStyle.C_AMBER
			category_lbl.outline_size = 12
			category_lbl.position = Vector3(-2.0, 1.2, z_pos)
			category_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			add_child(category_lbl)
			category_lbl.owner = _scene_owner()

		for col_idx in cols.size():
			var col_def := cols[col_idx] as Dictionary
			var npc_label: String = col_def["label"]
			var appearance: CharacterAppearance = col_def["appearance"]
			var x_pos := float(col_idx) * COL_GAP

			# Instantiate physical NpcBase character representation
			var npc := NpcBase.new()
			npc.name = "Npc_%d_%d" % [row_idx, col_idx]
			add_child(npc)
			npc.position = Vector3(x_pos, 0.12, z_pos)
			npc.owner = _scene_owner()

			# Apply custom color parameters and overlays
			npc.skin_color = appearance.skin_color
			npc.clothing_color = appearance.clothing_color
			npc.trousers_color = appearance.trousers_color
			
			if not appearance.hat_id.is_empty():
				var hat_path: String = CharacterAppearance.HAT_PATHS.get(appearance.hat_id, "")
				if not hat_path.is_empty():
					npc.add_overlay("hat", hat_path)

			_npc_nodes.append(npc)

			# Set up Walk Animator to enable walking cycles in-place
			var animator = WALK_ANIMATOR_SCRIPT.new()
			animator.attach(npc)
			_animators[npc] = {
				"animator": animator,
				"distance": randf() * 10.0 # Randomize initial foot phase
			}

			# Place a floating label describing the custom character configuration
			if show_labels:
				var lbl := Label3D.new()
				lbl.text = npc_label
				lbl.font_size = 20
				lbl.modulate = Color.WHITE
				lbl.outline_size = 8
				lbl.position = Vector3(x_pos, LABEL_H, z_pos)
				lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
				add_child(lbl)
				lbl.owner = _scene_owner()


func _reset_limb_rotations() -> void:
	for npc in _npc_nodes:
		if is_instance_valid(npc) and npc.assembler != null:
			for limb in ["arm_left", "arm_right", "leg_left", "leg_right"]:
				var part := npc.assembler.get_part(limb)
				if part != null:
					part.rotation = Vector3.ZERO


func _scene_owner() -> Node:
	return get_tree().edited_scene_root if Engine.is_editor_hint() else self


func _get_grid_definition() -> Array:
	var defs = []

	# Row 1: Pre-placed Port Characters & Roles
	var row_roles = {"name": "Roles & Occupations", "columns": []}
	
	var cap_app := CharacterAppearance.default_appearance()
	cap_app.hat_id = CharacterAppearance.HAT_FLAT_CAP
	cap_app.clothing_color = Color(0.12, 0.18, 0.35) # Navy
	cap_app.trousers_color = Color(0.12, 0.12, 0.15) # Dark Grey
	row_roles["columns"].append({"label": "Captain", "appearance": cap_app})

	var hm_app := CharacterAppearance.default_appearance()
	hm_app.hat_id = CharacterAppearance.HAT_PEAKED_CAP
	hm_app.clothing_color = Color(0.10, 0.15, 0.28) # Sailor Blue
	hm_app.trousers_color = Color(0.10, 0.15, 0.28)
	row_roles["columns"].append({"label": "Harbour Master", "appearance": hm_app})

	var sw_app := CharacterAppearance.default_appearance()
	sw_app.hat_id = CharacterAppearance.HAT_NONE
	sw_app.clothing_color = Color(0.42, 0.28, 0.18) # Leather/Brown
	sw_app.trousers_color = Color(0.20, 0.16, 0.14)
	sw_app.skin_color = Color(0.85, 0.70, 0.55) # Tan
	row_roles["columns"].append({"label": "Shipwright", "appearance": sw_app})

	var warehouse_app := CharacterAppearance.default_appearance()
	warehouse_app.hat_id = CharacterAppearance.HAT_NONE
	warehouse_app.clothing_color = Color(0.80, 0.40, 0.05) # Warn Orange
	warehouse_app.trousers_color = Color(0.10, 0.10, 0.12)
	row_roles["columns"].append({"label": "Dockworker", "appearance": warehouse_app})

	var agent_app := CharacterAppearance.default_appearance()
	agent_app.hat_id = CharacterAppearance.HAT_PEAKED_CAP
	agent_app.clothing_color = Color(0.18, 0.28, 0.18) # Deep Forest Green
	agent_app.trousers_color = Color(0.15, 0.15, 0.18)
	row_roles["columns"].append({"label": "Customs Agent", "appearance": agent_app})
	
	defs.append(row_roles)

	# Row 2: Spectrum of Skin Preset Options
	var row_skins = {"name": "Skin Tones", "columns": []}
	var skin_presets := [
		Color(0.88, 0.74, 0.60), # Light peach
		Color(0.72, 0.55, 0.40), # Default mid-tan
		Color(0.58, 0.42, 0.32), # Deep bronze
		Color(0.40, 0.28, 0.20), # Dark espresso
		Color(0.95, 0.82, 0.72)  # Fair/pale
	]
	for idx in skin_presets.size():
		var app := CharacterAppearance.default_appearance()
		app.skin_color = skin_presets[idx]
		app.clothing_color = Color(0.15, 0.22, 0.45) # Static clothing to focus on skin
		row_skins["columns"].append({"label": "Skin Preset %d" % (idx + 1), "appearance": app})
	defs.append(row_skins)

	# Row 3: Hat Styles and Combos
	var row_hats = {"name": "Headwear Accessories", "columns": []}
	
	var hat_none_app := CharacterAppearance.default_appearance()
	hat_none_app.hat_id = CharacterAppearance.HAT_NONE
	row_hats["columns"].append({"label": "Bare Headed", "appearance": hat_none_app})

	var flat_app := CharacterAppearance.default_appearance()
	flat_app.hat_id = CharacterAppearance.HAT_FLAT_CAP
	flat_app.clothing_color = Color(0.35, 0.28, 0.22) # Tweedy coat
	row_hats["columns"].append({"label": "Flat Cap", "appearance": flat_app})

	var peaked_app := CharacterAppearance.default_appearance()
	peaked_app.hat_id = CharacterAppearance.HAT_PEAKED_CAP
	peaked_app.clothing_color = Color(0.12, 0.16, 0.14) # Officer dark coat
	row_hats["columns"].append({"label": "Peaked Cap", "appearance": peaked_app})

	defs.append(row_hats)

	# Row 4: Custom Color Palette Lineup
	var row_palettes = {"name": "Clothing Color Palettes", "columns": []}
	var clothing_combos = [
		{"coat": Color(0.22, 0.38, 0.60), "pants": Color(0.18, 0.18, 0.20), "lbl": "Oceanic Blue"},
		{"coat": Color(0.18, 0.38, 0.25), "pants": Color(0.28, 0.22, 0.18), "lbl": "Forest"},
		{"coat": Color(0.70, 0.15, 0.15), "pants": Color(0.10, 0.12, 0.14), "lbl": "Crimson Coat"},
		{"coat": Color(0.75, 0.65, 0.10), "pants": Color(0.18, 0.18, 0.20), "lbl": "Fisherman"},
		{"coat": Color(0.40, 0.15, 0.45), "pants": Color(0.15, 0.12, 0.16), "lbl": "Royal Purple"}
	]
	for idx in clothing_combos.size():
		var combo = clothing_combos[idx]
		var app := CharacterAppearance.default_appearance()
		app.clothing_color = combo["coat"]
		app.trousers_color = combo["pants"]
		row_palettes["columns"].append({"label": combo["lbl"], "appearance": app})
	defs.append(row_palettes)

	return defs
