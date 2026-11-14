extends Node

# Categorías de ventanas para determinar posicionamiento, capas y comportamiento base
enum WindowCategory {
	HUD,               # Persistente en pantalla (Health bars, Skill bars, Mini-map)
	GAME_WINDOW,       # Ventanas de gameplay (Inventory, Quest Log, Stats)
	MODAL_OVERLAY,     # Bloquean input al mundo, centralizadas (Options Menu, Confirmation dialogs)
	EPHEMERAL_POPUP,   # Desaparecen solas o tras interacción mínima (Death screen, Notifications)
	TOOLTIP,           # Siguen al mouse o aparecen cerca de elementos
	CONTEXT_MENU,      # Menús click derecho
	FULL_SCREEN        # Pantallas completas (Login, Character Select)
}

# Políticas de modal
enum ModalPolicy {
	NONE,          # No bloquea nada
	INPUT_ONLY,    # Bloquea input al mundo pero permite ver tras ella
	FULL_BLOCK     # Bloquea input y oscurece el fondo (dim overlay)
}

# Estructura de metadatos para registro de ventanas
class WindowMetadata:
	var id: String
	var scene_path: String
	var category: WindowCategory = WindowCategory.GAME_WINDOW
	var allow_multiple: bool = false
	var modal_policy: ModalPolicy = ModalPolicy.NONE
	var lazy_load: bool = true
	var persist_position: bool = true
	var layer: int = 0 # 0 es default, usado por orquestador para ordenar CanvasLayers
	var shortcut_keys: Array = [] # Atajos de teclado (Key) que abren/cierran la ventana

	func _init(_id: String, _path: String, _category: WindowCategory = WindowCategory.GAME_WINDOW):
		self.id = _id
		self.scene_path = _path
		self.category = _category
