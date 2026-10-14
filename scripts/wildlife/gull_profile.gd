class_name GullProfile
extends Resource
## Persistent identity/appearance, independent of scene nodes and flock membership.
## Age starts at fledging: chicks need their own anatomy and ground behaviour.

@export var bird_id: int = 1
@export var species := "herring_gull"
@export_range(0.5, 12.0, 0.1) var age_years: float = 4.0
@export_range(0.75, 1.25, 0.01) var size_scale: float = 1.0
@export_range(0.5, 3.5, 0.05) var flap_hz: float = 1.65
@export_range(4.0, 18.0, 0.1) var cruise_speed_mps: float = 9.0
@export var phase_offset: float = 0.0

func maturity() -> float:
	return smoothstep(0.5, 4.0, age_years)

func to_record() -> Dictionary:
	return {"bird_id": bird_id, "species": species, "age_years": age_years,
		"size_scale": size_scale, "flap_hz": flap_hz,
		"cruise_speed_mps": cruise_speed_mps, "phase_offset": phase_offset}

static func from_record(record: Dictionary) -> GullProfile:
	var result := GullProfile.new()
	var species_id := str(record.get("species", "herring_gull"))
	result.species = species_id if species_id in ["herring_gull", "white_tailed_eagle", "arctic_tern"] else "herring_gull"
	result.bird_id = int(record.get("bird_id", 1))
	result.age_years = clampf(float(record.get("age_years", 4.0)), 0.5, 12.0)
	result.size_scale = clampf(float(record.get("size_scale", 1.0)), 0.75, 1.25)
	result.flap_hz = clampf(float(record.get("flap_hz", 1.65)), 0.5, 3.5)
	result.cruise_speed_mps = clampf(float(record.get("cruise_speed_mps", 9.0)), 4.0, 18.0)
	result.phase_offset = fposmod(float(record.get("phase_offset", 0.0)), TAU)
	return result

static func seeded(seed_value: int, index: int, mean_age: float, mean_size: float, variation: float) -> GullProfile:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + index * 104729
	return from_record({"bird_id": index, "age_years": mean_age + rng.randf_range(-3.0, 3.0) * variation,
		"size_scale": mean_size + rng.randf_range(-0.2, 0.2) * variation,
		"flap_hz": 1.65 + rng.randf_range(-0.25, 0.25),
		"cruise_speed_mps": 9.0 + rng.randf_range(-1.0, 1.0),
		"phase_offset": rng.randf_range(0.0, TAU)})
