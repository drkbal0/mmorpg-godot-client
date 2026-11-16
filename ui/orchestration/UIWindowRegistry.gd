extends Node

const UITypes = preload("res://ui/types/UITypes.gd")

# Dictionary[String, UITypes.WindowMetadata]
var _registry: Dictionary = {}

# Dictionary[String, Node] - Ventanas activas e instanciadas
var _instances: Dictionary = {}

# Rutas por parámetro: source_id -> [{target, param}]. Si `params[param]` es verdadero,
# las llamadas a `source_id` se resuelven a `target` (compatibilidad con llamadas antiguas).
var _routes: Dictionary = {}

func _init() -> void:
	_register_initial_windows()

# Registro de las ventanas base conocidas hasta ahora
func _register_initial_windows() -> void:
	# UI v2.4 Paso 10: Equipo e inventario [C] (paperdoll, 16 stats con deltas y conjuntos F1-F3).
	# El almacén clásico (alijo/personaje/bolsa segura en cuadrícula) sigue disponible como
	# "inventory_stash": las llamadas a "inventory" con `is_shelter_context` (Refugio, Vendedor)
	# se enrutan a él para mantener la compatibilidad.
	register("inventory", "res://ui/windows/EquipmentWindow/EquipmentWindow.tscn", UITypes.WindowCategory.GAME_WINDOW, [KEY_C])
	register("inventory_stash", "res://ui/windows/InventoryWindow/secure_slots_ui.tscn", UITypes.WindowCategory.GAME_WINDOW)
	register_route("inventory", "inventory_stash", "is_shelter_context")
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
	# UI v2.4 Paso 8: Refugio «El Nido» [H] (corte lateral · Construir B · Producción · Expediciones · Pispa · Mejoras)
	# y su versión de bolsillo para colas, antesalas y pantallas de carga (Anexo D).
	register("shelter", "res://ui/windows/ShelterWindow/ShelterWindow.tscn", UITypes.WindowCategory.GAME_WINDOW, [KEY_H])
	register("shelter_pocket", "res://ui/windows/ShelterWindow/ShelterPocket.tscn", UITypes.WindowCategory.GAME_WINDOW)
	# UI v2.4 Paso 9: Misiones [L], Mapa y viajes [M], Social y vecindad [O] y Comercio [P]
	# (Tienda y Pase de batalla en construcción; se abren desde el submenú Comercio).
	register("quests_window", "res://ui/windows/QuestsWindow/QuestsWindow.tscn", UITypes.WindowCategory.GAME_WINDOW, [KEY_L])
	register("map_window", "res://ui/windows/MapWindow/MapWindow.tscn", UITypes.WindowCategory.GAME_WINDOW, [KEY_M])
	register("social_window", "res://ui/windows/SocialWindow/SocialWindow.tscn", UITypes.WindowCategory.GAME_WINDOW, [KEY_O])
	register("shop_window", "res://ui/windows/ShopWindow/ShopWindow.tscn", UITypes.WindowCategory.GAME_WINDOW)
	register("battle_pass_window", "res://ui/windows/BattlePassWindow/BattlePassWindow.tscn", UITypes.WindowCategory.GAME_WINDOW)
	# UI v2.4 Paso 11: Fabricación (se abre desde la Forja del Refugio; cola en segundo plano)
	# y Trato cara a cara P2P con doble confirmación simétrica y máscara «???» del Códice.
	register("crafting_window", "res://ui/windows/CraftingWindow/CraftingWindow.tscn", UITypes.WindowCategory.GAME_WINDOW)
	register("trade_window", "res://ui/windows/TradeWindow/TradeWindow.tscn", UITypes.WindowCategory.GAME_WINDOW)
	# UI v2.4 Paso 12: Colecciones y Diario del multiverso (desde el Códice) e Incursiones con
	# extracción (desde Misiones): bolsa segura, riesgo si mueres y preparación.
	register("collections_window", "res://ui/windows/CollectionsWindow/CollectionsWindow.tscn", UITypes.WindowCategory.GAME_WINDOW)
	register("incursions_window", "res://ui/windows/IncursionsWindow/IncursionsWindow.tscn", UITypes.WindowCategory.GAME_WINDOW)
	# UI v2.4 Paso 13: Diálogo cinematográfico con PNJ (letterbox, opciones [1]-[4], relación) y
	# Muerte y reaparición con recap táctico de los últimos 5 s, resurrección y repetición [R].
	register("dialogue_window", "res://ui/windows/DialogueWindow/DialogueWindow.tscn", UITypes.WindowCategory.GAME_WINDOW)
	register("death_window", "res://ui/windows/DeathWindow/DeathWindow.tscn", UITypes.WindowCategory.MODAL_OVERLAY)


func register(id: String, scene_path: String, category: int, shortcut_keys: Array = []) -> void:
	var meta = UITypes.WindowMetadata.new(id, scene_path, category)
	meta.shortcut_keys = shortcut_keys.duplicate()
	_registry[id] = meta
	print("[UIWindowRegistry] Registrada ventana: ", id)

## Declara que `source_id` abierto con `params[param_key]` verdadero se resuelve a `target_id`.
func register_route(source_id: String, target_id: String, param_key: String) -> void:
	if not _routes.has(source_id):
		_routes[source_id] = []
	_routes[source_id].append({"target": target_id, "param": param_key})

## Id efectivo para (id, params): la ruta que aplique o el propio id.
func resolve_route(id: String, params: Dictionary = {}) -> String:
	for r in _routes.get(id, []):
		if bool(params.get(r["param"], false)) and is_registered(r["target"]):
			return r["target"]
	return id

## Ventanas a las que puede enrutarse `id` (para is_window_open/close_window).
func get_route_targets(id: String) -> Array:
	var out: Array = []
	for r in _routes.get(id, []):
		out.append(r["target"])
	return out

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
