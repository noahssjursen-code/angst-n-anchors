extends "res://tests/boat_physics_validation.gd"

func _ready() -> void:
	assert(ShipyardPlaytestMode.active())
	_test_query_texel_centres()
	_test_water_query_and_staleness()
	WaveSurface.fft_system=null
	WaveSurface.clear_sample_cache()
	assert(_failures.is_empty(),str(_failures))
	print("WATER QUERY PASS: GPU texel-centre convention, wrapped seams, velocity and stale-query fallback")
	get_tree().quit()
