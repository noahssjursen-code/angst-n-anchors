@tool
class_name ShipwrightNpc
extends NpcInteractable

## Yard stock, price and payment are resolved by the company purchase authority.
func _ready() -> void:
	appearance = CharacterCatalog.appearance_preset("harbour_mechanic")
	prompt_text = "Press F — Shipwright"
	super._ready()

func _on_commission_requested(entry: Dictionary) -> void:
	var result: Dictionary = await PortServiceDesk.purchase(self,{
		"stock_id":str(entry.get("prebuilt_id","")),
		"vessel_name":str(entry.get("prebuilt_name","Vessel")),
		"request_id":PlayerData.new_uuid(),
		"expected_price_nok":ShipwrightPricing.commission_price(entry, HullStations.from_box(float(entry.get("loa_m",24)),float(entry.get("beam_m",8)),4,10), PlayerSession.data),
	})
	if not bool(result.get("ok",false)):
		GameMenu.notify(str(result.get("message","The yard could not complete the purchase.")))
	else:
		GameMenu.notify("Vessel purchased. Visit the harbourmaster to bring it alongside.")
