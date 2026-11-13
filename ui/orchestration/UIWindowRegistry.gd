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
	register("codex_window", "res://ui/windows/CodexDiaryWindow/CodexDiaryWindow.tscn", UITypes.WindowCategory.GAME_WINDOW)
	register("party_frames", "res://ui/components/PartyFrames/PartyFrames.tscn", UITypes.WindowCategory.HUD)
	register("marketplace_window", "res://ui/windows/MarketplaceWindow/MarketplaceWindow.tscn", UITypes.WindowCategory.GAME_WINDOW)


func register(id: String, scene_path: String, category: int) -> void:
	var meta = UITypes.WindowMetadata.new(id, scene_path, category)
	_registry[id] = meta
	print("[UIWindowRegistry] Registrada ventana: ", id)

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
