extends Area3D
class_name GildasMerchant

## GildasMerchant.gd — NPC Tendero de Mercado P2P en el mundo 3D (Phase 9.5, ADR 037/081)
## Abre la ventana MarketplaceWindow.tscn a través del UIOrchestrator.
## Disparadores: tecla [F] (acción "interact", resuelta por Player.gd por raycast o
## proximidad dentro del grupo "interactable"), clic izquierdo (World._try_select_target)
## o picking físico directo sobre su Area3D (_input_event).

const MARKETPLACE_WINDOW_ID := "marketplace_window"

signal interacted(window: Node)

func _ready() -> void:
	if not is_in_group("interactable"):
		add_to_group("interactable")
	input_ray_pickable = true

## Abre atómicamente marketplace_window. Usa open_window (idempotente) en lugar de
## toggle para que pulsar [F] varias veces no cierre/reabra la ventana.
func interact(_player: Node3D = null) -> Node:
	print("[GildasMerchant] Interacción recibida. Abriendo Mercado P2P.")
	var sm = get_node_or_null("/root/SoundManager")
	if sm and sm.has_method("play_ui_sfx"):
		sm.play_ui_sfx(&"ui_click")

	var window: Node = null
	var ui = get_node_or_null("/root/UIOrchestrator")
	if ui:
		window = ui.open_window(MARKETPLACE_WINDOW_ID)
	interacted.emit(window)
	return window

func _input_event(_camera: Camera3D, event: InputEvent, _event_position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		interact()
		get_viewport().set_input_as_handled()
