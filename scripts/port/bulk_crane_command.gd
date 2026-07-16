class_name BulkCraneCommand
extends RefCounted

## Per-frame crane drive. Rates are −1..1; bucket_target is 0..1 or −1 to leave unchanged.

var slew_rate: float = 0.0
var boom_rate: float = 0.0
var hoist_rate: float = 0.0
var bucket_target: float = -1.0
