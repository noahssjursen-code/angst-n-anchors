class_name ContainerFactory
extends RefCounted

## Builds cubed general-cargo units (provisions commodity by default).


static func make_one(
	origin_port_id: String = "",
	destination_port_id: String = "",
	commodity_id: String = "provisions",
	freight_contract_id: String = "",
) -> ContainerUnit:
	var u := ContainerUnit.create("", commodity_id)
	u.origin_port_id = origin_port_id
	u.destination_port_id = destination_port_id
	u.freight_contract_id = freight_contract_id
	return u


static func make_stack(count: int) -> Array[ContainerUnit]:
	var out: Array[ContainerUnit] = []
	for _i in range(maxi(count, 0)):
		out.append(make_one())
	return out
