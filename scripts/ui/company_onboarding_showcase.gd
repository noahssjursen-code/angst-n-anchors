extends Control


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.color = Color("07141b")
	add_child(background)
	var horizon := ColorRect.new()
	horizon.set_anchors_preset(Control.PRESET_FULL_RECT)
	horizon.anchor_top = 0.58
	horizon.color = Color("0c2c3a")
	add_child(horizon)
	var setup := CompanySetupPanel.new()
	add_child(setup)
	setup.confirmed.connect(func(company_name: String, _color: Color, starter: String) -> void:
		print("company_onboarding_showcase: %s / %s" % [company_name, starter])
	)
	setup.cancelled.connect(func() -> void: setup.open_for_captain("Ingrid"))
	setup.open_for_captain("Ingrid")
