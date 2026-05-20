class_name DialogueScript
extends RefCounted

## JSON-driven dialogue tree for NPCs whose content is mostly static.
##
## For simple NPCs (tavern keeper, customs officer, harbour gossip) the
## hardcoded screen builders in HarbourMaster / Shipwright are overkill —
## you really just want quote + options + branch. DialogueScript reads a
## tree from JSON and renders it into a `DialoguePanel`, so adding a new
## "talk-only" NPC is just (a) write the JSON, (b) instantiate the NPC
## script with the path.
##
## JSON format:
##     {
##       "title": "TAVERN KEEPER",
##       "entry": "main",
##       "screens": {
##         "main": {
##           "quote": "Welcome to the Sailor's Rest, captain.",
##           "options": [
##             {"label": "What's the news?", "goto": "news"},
##             {"label": "I'll have an ale.", "action": "buy_ale"},
##             {"label": "Goodbye.",          "action": "close"}
##           ]
##         },
##         "news": {
##           "quote": "Pirates near Bremsund — mind yourself.",
##           "options": [
##             {"label": "← Back", "goto": "main"}
##           ]
##         }
##       }
##     }
##
## Options can carry:
##   "goto"   : another screen id
##   "action" : a name registered by the NPC via `register_action(name, cb)`
##              — reserved name "close" hides the panel.
##   "enabled_if" : (optional) a condition name; if registered AND false,
##                  the option renders as disabled. NPC sets condition
##                  values via `set_condition(name, bool)`.

const RESERVED_ACTION_CLOSE := "close"

var _title:    String = ""
var _entry:    String = ""
var _screens:  Dictionary = {}   # id (String) → Dictionary (the screen)
var _actions:  Dictionary = {}   # name (String) → Callable
var _conditions: Dictionary = {} # name (String) → bool


# ── Loading ───────────────────────────────────────────────────────────────────

## Returns true on success, false on parse / IO error.
func load_from_path(path: String) -> bool:
	if not FileAccess.file_exists(path):
		push_error("DialogueScript: file not found: %s" % path)
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("DialogueScript: could not open %s" % path)
		return false
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("DialogueScript: %s is not a JSON object" % path)
		return false
	return _load_from_dict(parsed)


func _load_from_dict(data: Dictionary) -> bool:
	_title   = str(data.get("title", ""))
	_entry   = str(data.get("entry", "main"))
	_screens = data.get("screens", {})
	if not (_screens is Dictionary) or _screens.is_empty():
		push_error("DialogueScript: 'screens' missing or empty")
		return false
	if not _screens.has(_entry):
		push_error("DialogueScript: entry screen '%s' not in screens" % _entry)
		return false
	return true


func get_title() -> String:
	return _title


func get_entry() -> String:
	return _entry


# ── NPC hooks ─────────────────────────────────────────────────────────────────

## Register a callback for any option that has `"action": "<name>"` in the JSON.
## Call before render(). The reserved name "close" is wired automatically.
func register_action(name: String, callback: Callable) -> void:
	_actions[name] = callback


## Set the value of a condition flag for options that use `"enabled_if"`. NPCs
## update these before render() (e.g. set_condition("carrying_cargo", ...)).
func set_condition(name: String, value: bool) -> void:
	_conditions[name] = value


## Render the entry screen.
func render_entry(panel: DialoguePanel) -> void:
	render(panel, _entry)


## Render a specific screen by id. If the screen id is unknown, the entry
## screen is rendered instead (defensive against typos in JSON).
func render(panel: DialoguePanel, screen_id: String) -> void:
	if not _screens.has(screen_id):
		push_warning("DialogueScript: unknown screen '%s', falling back to entry" % screen_id)
		screen_id = _entry
	var screen : Dictionary = _screens[screen_id]
	panel.clear()
	var quote := str(screen.get("quote", ""))
	if not quote.is_empty():
		panel.add_quote(quote)
	for opt_v in screen.get("options", []):
		var opt := opt_v as Dictionary
		if opt == null:
			continue
		var label := str(opt.get("label", "(no label)"))
		# Disabled if enabled_if condition is registered AND false.
		var cond_name := str(opt.get("enabled_if", ""))
		if cond_name != "" and _conditions.has(cond_name) and not bool(_conditions[cond_name]):
			panel.add_disabled_option(label)
			continue
		panel.add_option(label, _option_callback(panel, opt))


func _option_callback(panel: DialoguePanel, opt: Dictionary) -> Callable:
	if opt.has("goto"):
		var target := str(opt["goto"])
		return func() -> void: render(panel, target)
	if opt.has("action"):
		var action_name := str(opt["action"])
		if action_name == RESERVED_ACTION_CLOSE:
			return func() -> void: panel.hide_panel()
		if _actions.has(action_name):
			return _actions[action_name]
		push_warning("DialogueScript: option references unregistered action '%s'" % action_name)
	return func() -> void: pass
