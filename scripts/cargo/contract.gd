class_name Contract
extends Resource

enum State { AVAILABLE, ACCEPTED, COMPLETED }

var id: String = ""
var commodity: String = ""
var display_name: String = ""
var quantity: int = 1               # total committed by the contract (immutable post-creation)
var mass_per_unit_kg: float = 200.0
var reward_gold: int = 0            # total reward if fully delivered
var origin_port_id: String = ""
var destination_port_id: String = ""
var state: State = State.AVAILABLE
var taken_count: int = 0            # cumulative units the player has accepted (≤ quantity)
var delivered_count: int = 0        # cumulative units delivered (≤ taken_count)


func reward_per_unit() -> int:
	if quantity <= 0:
		return 0
	return int(ceil(float(reward_gold) / float(quantity)))


## Units still available to accept (not yet committed by the player).
func available_to_take() -> int:
	return maxi(quantity - taken_count, 0)


## True when units have been accepted but not yet delivered.
func is_in_transit() -> bool:
	return taken_count > delivered_count


func is_complete() -> bool:
	return delivered_count >= quantity
