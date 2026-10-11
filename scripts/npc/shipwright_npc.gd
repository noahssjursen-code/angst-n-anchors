@tool
class_name ShipwrightNpc
extends NpcInteractable

## Yard stock, price and payment are resolved by the company purchase authority.
func _ready() -> void:
	appearance = CharacterCatalog.appearance_preset("harbour_mechanic")
	prompt_text = "Press F — Shipwright"
	super._ready()

func _on_commission_requested(entry: Dictionary) -> void:
	var result := PortServiceDesk.request(self,"buy",{
		"stock_id":str(entry.get("prebuilt_id","")),
		"vessel_name":str(entry.get("prebuilt_name","Vessel")),
		"request_id":PlayerData.new_uuid(),
	})
	if not bool(result.get("ok",false)):
		GameMenu.notify(str(result.get("message","The yard could not complete the purchase.")))
	else:
		GameMenu.notify("Vessel purchased. Visit the harbourmaster to bring it alongside.")
