class_name FishingField
extends RefCounted

## Deterministic open-ocean fishing grounds from `world_seed` + world position.
## Sampled at trawl time for catch rate/value and on the sea chart for overlay.

static var world_seed: int = 0

const FEATURE_SCALE_M := 5500.0
## Trawling needs open water — harbour shelter below this is treated as barren.
const MIN_OPEN_WATER_SHELTER := 0.35

const TIERS: Array[Dictionary] = [
	{"id": "barren", "label": "Barren", "min_noise": -1.0, "price_mul": 0.75, "catch_mul": 0.65,
		"color": Color(0.10, 0.14, 0.22, 0.55)},
	{"id": "sparse", "label": "Sparse", "min_noise": -0.35, "price_mul": 0.90, "catch_mul": 0.85,
		"color": Color(0.14, 0.28, 0.38, 0.62)},
	{"id": "normal", "label": "Normal", "min_noise": -0.05, "price_mul": 1.00, "catch_mul": 1.00,
		"color": Color(0.18, 0.42, 0.52, 0.68)},
	{"id": "rich", "label": "Rich", "min_noise": 0.28, "price_mul": 1.75, "catch_mul": 1.25,
		"color": Color(0.22, 0.58, 0.42, 0.74)},
	{"id": "prolific", "label": "Prolific", "min_noise": 0.52, "price_mul": 2.50, "catch_mul": 1.50,
		"color": Color(0.72, 0.82, 0.28, 0.78)},
]

static var _ground_noise: FastNoiseLite = null
static var _initialized: bool = false


static func initialize(seed: int) -> void:
	world_seed = seed
	_initialized = true
	_ensure_noise()


static func is_initialized() -> bool:
	return _initialized


static func sample(world_pos: Vector3) -> Dictionary:
	_ensure_noise()
	var noise_val := _ground_noise.get_noise_2d(
		world_pos.x / FEATURE_SCALE_M,
		world_pos.z / FEATURE_SCALE_M
	)
	var tier := _tier_for_noise(noise_val)
	var shelter := 1.0
	if LandField.is_initialized():
		shelter = LandField.shore_shelter(world_pos)
	if shelter < MIN_OPEN_WATER_SHELTER:
		tier = TIERS[0]
		shelter = 0.0
	var price_mul: float = float(tier["price_mul"]) * shelter
	var catch_mul: float = float(tier["catch_mul"]) * shelter
	return {
		"tier_id": str(tier["id"]),
		"tier_label": str(tier["label"]),
		"price_mul": price_mul,
		"catch_mul": catch_mul,
		"noise": noise_val,
		"open_water": shelter >= MIN_OPEN_WATER_SHELTER,
	}


static func tier_color(tier_id: String) -> Color:
	for tier in TIERS:
		if str(tier["id"]) == tier_id:
			return tier["color"] as Color
	return TIERS[2]["color"] as Color


static func _tier_for_noise(noise_val: float) -> Dictionary:
	var chosen: Dictionary = TIERS[0]
	for tier in TIERS:
		if noise_val >= float(tier["min_noise"]):
			chosen = tier
	return chosen


static func _ensure_noise() -> void:
	if _ground_noise != null and _ground_noise.seed == (world_seed ^ 0x46495348):
		return
	_ground_noise = FastNoiseLite.new()
	_ground_noise.seed = world_seed ^ 0x46495348  # 'FISH'
	_ground_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_ground_noise.frequency = 1.0
	_ground_noise.fractal_octaves = 2
	_ground_noise.fractal_gain = 0.55
	_ground_noise.fractal_lacunarity = 2.0
