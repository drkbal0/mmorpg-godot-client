@tool
extends Node

## NetworkAudit
## Herramienta de auditoría para asegurar el cumplimiento de las reglas de red.
## Escanea la escena en busca de nodos HTTPRequest no autorizados.

static fn audit_scene(root: Node) -> Array[Node]:
	var illegal_nodes: Array[Node] = []
	var stack = [root]
	
	while stack.size() > 0:
		var current = stack.pop_back()
		if current is HTTPRequest:
			# Ignorar si es el propio APIClient o está marcado como exento (raro)
			if not current.get_parent().name == "APIClient":
				illegal_nodes.append(current)
		
		for child in current.get_children():
			stack.push_back(child)
	
	if illegal_nodes.size() > 0:
		printerr("[NetworkAudit] SE HAN ENCONTRADO NODOS HTTPRequest NO AUTORIZADOS:")
		for node in illegal_nodes:
			printerr("  - ", node.get_path(), " en escena: ", node.owner.name if node.owner else "N/A")
		printerr("[NetworkAudit] Por favor, migra estas llamadas a APIClient.gd para cumplir con la arquitectura del proyecto.")
	else:
		print("[NetworkAudit] Auditoría completada. No se encontraron nodos HTTPRequest ilegales.")
		
	return illegal_nodes

func _ready():
	if not Engine.is_editor_hint():
		# En tiempo de ejecución (solo en debug), realizar una auditoría rápida al inicio
		if OS.is_debug_build():
			audit_scene(get_tree().root)
