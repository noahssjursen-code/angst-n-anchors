class_name Contract
extends Resource

enum State { AVAILABLE, ACCEPTED, COMPLETED }

var id: String = ""
var commodity: String = ""
var display_name: String = ""
var quantity: int = 1
var mass_per_unit_kg: float = 200.0
var reward_gold: int = 0
var origin_port_id: String = ""
var destination_port_id: String = ""
var state: State = State.AVAILABLE
var delivered_count: int = 0


func reward_per_unit() -> int:
	if quantity <= 0:
		return 0
	return int(ceil(float(reward_gold) / float(quantity)))


func is_complete() -> bool:
	return delivered_count >= quantity
