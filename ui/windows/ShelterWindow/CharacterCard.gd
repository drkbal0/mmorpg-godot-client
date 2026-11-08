extends PanelContainer

# CharacterCard.gd - Representación visual de un personaje en el Shelter

signal selected(char_data: Dictionary)
signal revive_requested(char_data: Dictionary)
signal delete_requested(char_data: Dictionary)

@onready var portrait = %PortraitPlaceholder
@onready var name_label = %NameLabel
@onready var status_label = %StatusLabel
@onready var vit_val = %VitValue
@onready var agi_val = %AgiValue
@onready var recover_btn = %RecoverButton
@onready var delete_btn = %DeleteButton
@onready var select_btn = %SelectButton

var character_data : Dictionary = {}

func _ready():
	select_btn.pressed.connect(_on_select_pressed)
	recover_btn.pressed.connect(_on_revive_pressed)
	delete_btn.pressed.connect(_on_delete_pressed)
	
	# Doble Click Logic
	gui_input.connect(_on_gui_input)

func setup(data: Dictionary):
	character_data = data
	name_label.text = data.get("name", "Unknown")
	
	# Stats
	vit_val.text = str(data.get("vitality", 10))
	agi_val.text = str(data.get("agility", 10))
	
	var status = data.get("status", "")
	var is_dead = status in ["Dead", "Muerto"]
	
	if is_dead:
		status_label.text = "MUERTO"
		status_label.add_theme_color_override("font_color", Color(1, 0, 0))
		portrait.color = Color(0.1, 0.1, 0.1) # Grayscale/Dark effect
		recover_btn.visible = true
		select_btn.disabled = false
		select_btn.text = "INSPECCIONAR"
	else:
		status_label.text = "VIVO"
		status_label.add_theme_color_override("font_color", Color(0, 1, 0))
		portrait.color = Color(0.2, 0.4, 0.2) # Healthy green tint
		recover_btn.visible = false
		select_btn.disabled = false
		select_btn.text = "SELECCIONAR"

func _on_select_pressed():
	selected.emit(character_data)

func _on_revive_pressed():
	revive_requested.emit(character_data)

func _on_delete_pressed():
	delete_requested.emit(character_data)

func _on_gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.double_click:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if not character_data.get("status", "") in ["Dead", "Muerto"]:
				_on_select_pressed()

func set_highlight(active: bool):
	var style = get_theme_stylebox("panel", "PanelContainer").duplicate()
	if active:
		style.border_color = Color(0, 1, 0) # Green highlight
	else:
		style.border_color = Color(0.3, 0.3, 0.3)
	add_theme_stylebox_override("panel", style)
