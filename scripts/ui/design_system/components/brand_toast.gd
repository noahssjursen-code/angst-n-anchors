class_name BrandToast
extends BrandPanel

var _label: BrandLabel
var _hide_timer: SceneTreeTimer


func _init() -> void:
	variant = Variant.DARK_RULED
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = BrandLabel.new("", BrandLabel.Role.INVERSE_BODY)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	## A wrapping label's MINIMUM height is computed at its current width, and at
	## first layout that width is zero — so a 46-character notice reported a
	## minimum of 47 one-word lines and the `PanelContainer` above it sized
	## itself to match. Measured on `ShipHud`: **680 x 1357**, a slab reaching
	## past the bottom of a 1080 px screen and over the whole status band, with
	## the text stranded at its vertical centre. Nothing shrinks it afterwards:
	## the forced size is written back into the panel's offsets. Naming a wrap
	## width the label may never go below bounds the first measurement, which is
	## the only one that gets to be wrong.
	_label.custom_minimum_size.x = 480.0
	add_child(_label)
	visible = false


func show_message(message: String, duration_seconds: float = 3.0) -> void:
	_label.text = message
	visible = true
	modulate.a = 1.0
	BrandMotion.panel_in(self, Vector2(0.0, 8.0))
	var timer := get_tree().create_timer(duration_seconds, true, false, true)
	_hide_timer = timer
	timer.timeout.connect(func() -> void:
		if _hide_timer != timer:
			return
		var tween := BrandMotion.panel_out(self, Vector2(0.0, 8.0))
		if tween != null:
			tween.finished.connect(func() -> void: visible = false)
	)
