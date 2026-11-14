extends Node

const UITypes = preload("res://ui/types/UITypes.gd")

# Dictionary[String, UITypes.WindowMetadata]
var _registry: Dictionary = {}

# Dictionary[String, Node] - Ventanas activas e instanciadas
var _instances: Dictionary = {}

func _init() -> void:
	_register_initial_windows()

# Registro de las ventanas base conocidas hasta ahora
func _register_initial_windows() -> void:
	register("inventory", "res://ui/windows/InventoryWindow/secure_slots_ui.tscn", UITypes.WindowCategory.GAME_WINDOW)
	register("admin_panel", "res://ui/windows/AdminPanel/AdminPanel.tscn", UITypes.WindowCategory.GAME_WINDOW)
	register("options_menu", "res://ui/windows/OptionsMenu/OptionsMenu.tscn", UITypes.WindowCategory.MODAL_OVERLAY)
	register("backpack", "res://ui/windows/InventoryWindow/SubInventoryContainer.gd", UITypes.WindowCategory.GAME_WINDOW)
	register("shelter_lobby", "res://ui/windows/ShelterWindow/ShelterLobby.tscn", UITypes.WindowCategory.FULL_SCREEN)
	register("loot_window", "res://ui/windows/InventoryWindow/LootContainer.gd", UITypes.WindowCategory.GAME_WINDOW)
	register("player_hud", "res://ui/components/PlayerHUD/PlayerHUD.tscn", UITypes.WindowCategory.HUD)
	register("database_admin", "res://ui/windows/DatabaseAdminWindow/DatabaseAdminWindow.tscn", UITypes.WindowCategory.GAME_WINDOW)
	register("vendor_window", "res://ui/windows/VendorWindow/VendorWindow.tscn", UITypes.WindowCategory.GAME_WINDOW)
	register("codex_window", "res://ui/windows/CodexWindow/CodexWindow.tscn", UITypes.WindowCategory.GAME_WINDOW)
	register("party_frames", "res://ui/components/PartyFrames/PartyFrames.tscn", UITypes.WindowCategory.HUD)
	register("marketplace_window", "res://ui/windows/MarketplaceWindow/MarketplaceWindow.tscn", UITypes.WindowCategory.GAME_WINDOW)
	# UI v2.4 Paso 6-7: Poderes [N] (Crisol · Atlas · Constelación · Afinidades) y oferta del pionero.
	register("powers", "res://ui/windows/PowersWindow/PowersWindow.tscn", UITypes.WindowCategory.GAME_WINDOW, [KEY_N])
	register("pioneer_offer", "res://ui/windows/PioneerOfferModal/PioneerOfferModal.tscn", UITypes.WindowCategory.MODAL_OVERLAY)


func register(id: String, scene_path: String, category: int, shortcut_keys: Array = []) -> void:
	var meta = UITypes.WindowMetadata.new(id, scene_path, category)
	meta.shortcut_keys = shortcut_keys.duplicate()
	_registry[id] = meta
	print("[UIWindowRegistry] Registrada ventana: ", id)

## Atajos de teclado (Key) declarados para una ventana. [] si no tiene o no existe.
func get_shortcut_keys(id: String) -> Array:
	var meta = _registry.get(id)
	return meta.shortcut_keys.duplicate() if meta else []

## Ventana asociada a un atajo (keycode) o "" si ninguna lo declara.
func get_window_for_key(keycode: int) -> String:
	for id in _registry:
		if _registry[id].shortcut_keys.has(keycode):
			return id
	return ""

func get_metadata(id: String) -> UITypes.WindowMetadata:
	return _registry.get(id)

func set_instance(id: String, node: Node) -> void:
	_instances[id] = node

func get_instance(id: String) -> Node:
	var instance = _instances.get(id)
	# En Godot 4 una instancia liberada compara == null, por lo que el guard
	# `instance != null` no la detectaba y el `return` tipado fallaba con
	# "previously freed instance". is_instance_valid cubre null y liberadas.
	if not is_instance_valid(instance):
		_instances.erase(id)
		return null
	return instance

func remove_instance(id: String) -> void:
	_instances.erase(id)

func has_instance(id: String) -> bool:
	return _instances.has(id)

func is_registered(id: String) -> bool:
	return _registry.has(id)

func get_all_instance_ids() -> Array:
	return _instances.keys()
