extends Panel
class_name InventorySlot

var inventory_type: int = 0 # 0: CHARACTER, 1: SHELTER, 2: SECURE

var slot_x: int = 0
var slot_y: int = 0
var is_occupied: bool = false
var occupied_by: InventoryItem = null
var inventory_owner: Control  # Reference to SecureSlotsUI (now InventoryUI)

func _ready():
	custom_minimum_size = Vector2(64, 64)
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.15, 0.15, 0.15, 0.9)
	if inventory_type == 2: # SECURE
		sb.bg_color = Color(0.2, 0.2, 0.1, 0.9) # Subtle gold for secure
	elif inventory_type == 1: # SHELTER
		sb.bg_color = Color(0.1, 0.2, 0.2, 0.9) # Subtle teal/blue for shelter
	
	sb.border_width_left = 0
	sb.border_width_top = 0
	sb.border_width_right = 1 # Keep only a thin separator or remove it
	sb.border_width_bottom = 1
	sb.border_color = Color(0.2, 0.2, 0.2, 0.5)
	add_theme_stylebox_override("panel", sb)
	# Allow children to overflow visually
	clip_contents = false
	
	gui_input.connect(_on_gui_input)

func _on_gui_input(event):
	if is_occupied and occupied_by:
		if occupied_by.get_parent() != self:
			# Somos un slot de desbordamiento, delegamos al ítem
			occupied_by.handle_direct_input(event)
			return
		
		# Somos el ancla, lógica normal
		if event is InputEventMouseButton and event.pressed:
			if inventory_owner and inventory_owner.has_method("request_focus"):
				inventory_owner.request_focus()

func _get_drag_data(at_position):
	if is_occupied and occupied_by:
		# Delegamos el inicio del arrastre al ítem, sin importar si somos el ancla o desbordamiento
		return occupied_by._get_drag_data(at_position)
	return null

func _can_drop_data(_pos, data):
	if data is Dictionary and data.has("type") and data["type"] == "inventory_item":
		var item_node = data.get("item_node")
		if is_instance_valid(item_node) and not item_node.is_queued_for_deletion():
			# Si el slot está ocupado por otro ítem, verificar si podemos apilarlos (Merge de stacks)
			if is_occupied and is_instance_valid(occupied_by) and occupied_by != item_node:
				if _can_merge_with(item_node, occupied_by):
					return true

			# Validación anti-circularidad: no permitir meter una mochila dentro de sí misma o sus hijos
			if item_node.is_container and inventory_owner.has_method("get_container_item_id"):
				var dest_id = inventory_owner.get_container_item_id()
				if dest_id == item_node.item_id:
					return false # No puedes meter una mochila dentro de sí misma
				# Verificar descendientes via InventoryController
				if has_node("/root/InventoryController"):
					if get_node("/root/InventoryController")._is_descendant_of(dest_id, item_node.item_id):
						return false
			return inventory_owner.can_place_item(item_node, slot_x, slot_y, inventory_type)
	return false

func _can_merge_with(src_item: InventoryItem, target_item: InventoryItem) -> bool:
	if not is_instance_valid(src_item) or not is_instance_valid(target_item):
		return false
	if src_item == target_item:
		return false
	var same_name = (src_item.item_name == target_item.item_name)
	var same_def = false
	var src_def = src_item.get_meta("item_definition_id", "")
	var target_def = target_item.get_meta("item_definition_id", "")
	if src_def != "" and target_def != "" and src_def == target_def:
		same_def = true
	if not (same_name or same_def):
		return false
	var max_st = target_item.max_stack
	if max_st <= 1:
		var sm = get_node_or_null("/root/ShelterManager")
		if sm and sm.has_method("get_item_max_stack"):
			max_st = sm.get_item_max_stack(target_item.item_name)
		else:
			max_st = 1
	return max_st > 1 and target_item.quantity < max_st

func _drop_data(_pos, data):
	var item_node = data.get("item_node")
	if is_occupied and is_instance_valid(occupied_by) and occupied_by != item_node and _can_merge_with(item_node, occupied_by):
		if has_node("/root/InventoryController"):
			get_node("/root/InventoryController").request_stack_merge(item_node, occupied_by, inventory_owner)
		return

	if has_node("/root/InventoryController"):
		get_node("/root/InventoryController").request_item_movement(data["item_node"], slot_x, slot_y, inventory_type, inventory_owner)
	else:
		# Fallback legacy
		inventory_owner.place_item(data["item_node"], slot_x, slot_y, inventory_type)

