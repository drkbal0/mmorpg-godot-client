extends Area3D
class_name GildasMerchant

## GildasMerchant.gd — NPC Tendero de Mercado P2P en el mundo 3D (Phase 9.5)
## Abre la ventana MarketplaceWindow.tscn a través del UIOrchestrator.

func interact(_player: Node3D = null) -> void:
	print("[GildasMerchant] Interacción recibida. Abriendo Mercado P2P.")
	if has_node("/root/SoundManager"):
		var sm = get_node("/root/SoundManager")
		sm.play_ui_sfx(&"ui_click")

	var ui = get_node_or_null("/root/UIOrchestrator")
	if ui:
		ui.toggle_window("marketplace_window")
