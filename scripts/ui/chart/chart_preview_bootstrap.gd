class_name ChartPreviewBootstrap
extends RefCounted

## Isolated preview factory. It creates no nodes and never clears or registers
## ports in the gameplay ContractRegistry.

const SnapshotClass := preload("res://scripts/ui/chart/chart_data_snapshot.gd")

var snapshot


func activate(
		_host: Node,
		world_seed: int,
		port_count: int = 35,
		world_size_m: float = 40000.0,
		world_preset: String = "standard",
):
	snapshot = SnapshotClass.for_preview(
		world_seed,
		port_count,
		world_size_m,
		world_preset,
	)
	return snapshot


func deactivate() -> void:
	snapshot = null


func is_active() -> bool:
	return snapshot != null and snapshot.is_valid()
