extends Node

# El índice Z más alto actual para asegurar que la ventana enfocada esté arriba
var _top_z_index: int = 100

# Registra qué ventana tiene el foco actualmente
var current_focus_id: String = ""

func request_focus(id: String, node: Node) -> void:
	if current_focus_id == id:
		# Ya tiene el foco, pero aseguramos que esté al frente por si acaso
		if node is Control:
			node.move_to_front()
		return
	
	_top_z_index += 10
	if node is Control:
		node.move_to_front()
		node.z_index = _top_z_index
		node.z_as_relative = false # Forzar absoluto para ventanas de primer nivel
	
	current_focus_id = id
	print("[UIFocusManager] FOCO -> ", id, " (Z: ", _top_z_index, ", TreeOrder: Front)")

func get_next_z_index() -> int:
	_top_z_index += 10
	return _top_z_index
