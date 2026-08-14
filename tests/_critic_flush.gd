extends SceneTree

## SCRATCH PROBE (leading underscore — not a gate unit).
##
## Openings the piece fixtures cannot reach, put straight into a plate spec:
## flush with an edge, flush with the head, either side of the `has_sill`
## threshold, and a jamb exactly on the MIN_PANEL boundary. For each:
##
##   - the CLEAR RUN across the hole at mid height, measured against the slabs
##     `plate_slabs` enumerates (drawing and collision both walk it), versus the
##     width authored;
##   - whether every casing member survived;
##   - whether any slab escapes the plate's own [0,1]^2 parameter square.

const W := 4.0
const H := 2.5


func _init() -> void:
	print("%-42s %-7s %-7s %-7s %-6s %s"
		% ["case", "asked", "cut", "clear", "casing", "note"])
	_case("centred door", 1.4, 1.2, 0.0, 1.95)
	_case("flush with the LEFT edge", 0.0, 1.2, 0.0, 1.95)
	_case("flush with the RIGHT edge", W - 1.2, 1.2, 0.0, 1.95)
	_case("0.085 m of plating (under the jamb width)", 0.085, 1.2, 0.0, 1.95)
	_case("0.09 m of plating (exactly the jamb width)", 0.09, 1.2, 0.0, 1.95)
	_case("0.02 m of plating (exactly MIN_PANEL)", 0.02, 1.2, 0.0, 1.95)
	_case("widest legal hole — the whole plate", 0.0, W, 0.0, H)
	_case("head flush with the plate top", 1.4, 1.2, H - 1.95, 1.95)
	_case("sill 0.049 — under the has_sill threshold", 1.4, 1.2, 0.049, 1.2)
	_case("sill 0.051 — over the has_sill threshold", 1.4, 1.2, 0.051, 1.2)
	_case("a door AND a window in one plate", -1.0, 0.0, 0.0, 0.0)
	quit()


func _spec(off: float, w: float, sill: float, h: float) -> Dictionary:
	var openings: Array = []
	if off < 0.0:
		openings = [
			{"type": "door", "offset": 0.4, "width": 1.2, "sill": 0.0, "height": 1.95},
			{"type": "window", "offset": 2.4, "width": 1.2, "sill": 1.2, "height": 0.8},
		]
	else:
		openings = [{
			"type": "window" if sill > 0.0 else "door",
			"offset": off, "width": w, "sill": sill, "height": h,
		}]
	return {
		"corners": [[0.0, 0.0, 0.0], [W, 0.0, 0.0], [W, H, 0.0], [0.0, H, 0.0]],
		"thickness": 0.1,
		"openings": openings,
	}


func _case(label: String, off: float, w: float, sill: float, h: float) -> void:
	var spec := _spec(off, w, sill, h)
	var corners := StructureBaker.plate_corners(spec)
	var ref := StructureBaker.plate_ref_lengths(corners)
	var cut := StructureBaker.plate_openings(spec, ref)
	var slabs := StructureBaker.plate_slabs(spec)
	var panels := StructureBaker.plate_panels(spec).size()
	var frames := StructureBaker.plate_frames(spec).size()
	var outside := 0
	for slab_variant in slabs:
		var slab := slab_variant as Dictionary
		for key in ["u0", "u1", "v0", "v1"]:
			var value := float(slab[key])
			if value < -1e-9 or value > 1.0 + 1e-9:
				outside += 1
	## The widest run across the plate, at the first opening's mid height, that
	## no slab covers. This is the hole the body and the eye both see.
	var report := ""
	for opening_variant in cut:
		var opening := opening_variant as Dictionary
		var v := (float(opening["sill"]) + float(opening["h"]) * 0.5) / ref.y
		var best := 0.0
		var run := 0.0
		var u := 0.0
		while u <= ref.x:
			if _free(slabs, u / ref.x, v):
				run += 0.005
				best = maxf(best, run)
			else:
				run = 0.0
			u += 0.005
		report += "%.3f " % best
	var asked := "%.2f" % w if off >= 0.0 else "1.20+1.20"
	var got := "" if cut.is_empty() else "%.2f" % float((cut[0] as Dictionary)["w"])
	if cut.size() > 1:
		got = "%.2f+%.2f" % [float((cut[0] as Dictionary)["w"]), float((cut[1] as Dictionary)["w"])]
	print("%-42s %-7s %-7s %-7s %-6s %s"
		% [label, asked, got, report.strip_edges(), "%d/%d" % [frames, 4 if sill > 0.05 else 3],
		   "panels %d · %d slab bounds outside [0,1]" % [panels, outside]])


func _free(slabs: Array, u: float, v: float) -> bool:
	for slab_variant in slabs:
		var slab := slab_variant as Dictionary
		if u >= float(slab["u0"]) and u <= float(slab["u1"]) \
				and v >= float(slab["v0"]) and v <= float(slab["v1"]):
			return false
	return true
