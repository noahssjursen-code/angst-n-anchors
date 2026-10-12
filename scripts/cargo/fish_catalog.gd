class_name FishCatalog
extends RefCounted

## The catchable item pool. Numbers are game balance, not fisheries advice.
static var _data: Dictionary = {}

static func all() -> Dictionary:
	if _data.is_empty(): _data = JsonUtil.load("res://resources/data/fishing/species.json")
	return _data

static func species(id: String) -> Dictionary:
	return all().get(id, {})

static func fish_ids() -> Array[String]:
	var ids: Array[String] = []
	for id: String in all():
		# Swimming fish carry a habitat zone. The crab model is a catch mesh, not a school.
		if all()[id].has("model") and all()[id].has("zone"): ids.append(id)
	return ids

static func specimen(id: String, rng: RandomNumberGenerator) -> Dictionary:
	var entry := species(id)
	# Common sizes dominate; a small trophy tail makes searching worthwhile.
	var size_roll := pow(rng.randf(), 1.8)
	var trophy := rng.randf() < .025
	if trophy: size_roll = rng.randf_range(.88, 1.0)
	var length := lerpf(float(entry.length_cm[0]), float(entry.length_cm[1]), size_roll)
	var relative := length / float(entry.length_cm[1])
	var mass := clampf(float(entry.mass_kg[1]) * pow(relative, 3) * rng.randf_range(.9, 1.08), float(entry.mass_kg[0]), float(entry.mass_kg[1]))
	return {"species_id":id, "mass_kg":snappedf(mass,.01), "length_cm":snappedf(length,.1), "specimen":true, "size_grade":"Trophy" if size_roll >= .88 else ("Large" if size_roll >= .65 else "Standard")}

static func model(id: String) -> Node3D:
	var path := str(species(id).get("model", ""))
	if path.is_empty(): return null
	return (load(path) as PackedScene).instantiate() as Node3D


static func hooked_transform(mouth: Vector3, tip: Vector3, socket: Vector3, length_m: float, roll: float = 0.0) -> Transform3D:
	# Authored head axis is +X. Keep the lip fixed while the tail rolls/flexes;
	# looking_at() assumes -Z and would drag these fish sideways or tail first.
	var head := (tip-mouth).normalized()
	if head.length_squared()<.5:head=Vector3.RIGHT
	var reference_up := Vector3.UP if absf(head.dot(Vector3.UP))<.98 else Vector3.FORWARD
	var side := head.cross(reference_up).normalized()
	var up := side.cross(head).normalized()
	var basis := Basis(head,up,side).rotated(head,roll).scaled(Vector3.ONE*maxf(.001,length_m))
	return Transform3D(basis,mouth-basis*socket)
