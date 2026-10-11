extends Node

## Regenerates resources/ui/angst_theme.tres from UiThemeBuilder and checks
## the project points at it. Run headless after changing UI tokens.


func _ready() -> void:
	var err := UiThemeBuilder.save()
	var ok := err == OK and ResourceLoader.exists(UiThemeBuilder.THEME_PATH)
	var configured := String(ProjectSettings.get_setting("gui/theme/custom", "")) == UiThemeBuilder.THEME_PATH
	print("UI THEME %s — saved=%s project_theme=%s" % [
		"PASS" if ok and configured else "FAIL", str(err == OK), str(configured)])
	get_tree().quit(0 if ok and configured else 1)
