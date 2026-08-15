extends SceneTree

## Scratch probe (leading underscore: the gate skips it). Establishes the raw
## GDScript facts the new guards' comments claim, rather than asserting them
## from memory.
##
## Already established by earlier runs of this file, and both were surprises:
##
##  1. `v as Array` where `v` is a Variant holding an int is NOT a silent empty
##     Array. It is `SCRIPT ERROR: Invalid cast: could not convert value to
##     'Array'`, and — exactly like the failed `assert()` in CONVENTIONS §2 — it
##     ABORTS the enclosing function while leaving the process alive, so
##     `quit()` is never reached and the run idles to the gate's timeout.
##  2. When that happens, everything the script printed is LOST: the pipe buffer
##     is discarded when `timeout` SIGTERMs the process. Redirect to a file.
##
## Pass the case to run as a user arg, because the fatal cast ends the run:
##   godot ... --script res://tests/_hole_facts_probe.gd -- --case=nil

func _initialize() -> void:
	var which := "fmod"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--case="):
			which = argument.trim_prefix("--case=")
	match which:
		"nil":
			var nil_v: Variant = null
			var cast: Variant = nil_v as Array
			print("FACT `null as Array` -> %s" % type_string(typeof(cast)))
			if cast is Array:
				print("     size %d" % (cast as Array).size())
		"str":
			var str_v: Variant = "islands"
			var cast: Variant = str_v as Array
			print("FACT `\"islands\" as Array` -> %s" % type_string(typeof(cast)))
		"divzero":
			## What `int(round(CHUNK_SIZE_M / step_m))` actually produced when the
			## old assert was compiled out and step_m was 0.
			var zero := 0.0
			var quotient := 1000.0 / zero
			print("FACT 1000.0 / 0.0 = %s (is_finite=%s)" % [quotient, is_finite(quotient)])
			var cells := int(round(quotient))
			print("FACT int(round(1000.0 / 0.0)) = %d" % cells)
			var side := cells + 1
			print("FACT side*side = %d  (that is the resize() argument)" % (side * side))
			## And WorldLayout's `size_m / float(resolution - 1)` at resolution 1.
			print("FACT 40000.0 / float(1 - 1) = %s" % (40000.0 / float(1 - 1)))
		_:
			print("FACT fmod(1000.0, 30.0) = %s" % fmod(1000.0, 30.0))
			print("FACT fmod(1000.0, 25.0) = %s" % fmod(1000.0, 25.0))
			print("FACT round(1000.0 / 30.0) = %s -> effective step %s" % [
				round(1000.0 / 30.0), 1000.0 / round(1000.0 / 30.0),
			])
	quit(0)
