extends Control
class_name BaseWindow

# BaseWindow.gd - Clase base estandarizada para todas las ventanas del juego
# Proporciona: arrastre por cabecera, clamping a pantalla, cierre unificado y foco en UIOrchestrator.

@export var window_id: String = ""
@export var is_draggable: bool = true

var _is_dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO

@onready var close_button: Button = find_child("CloseButton", true, false)
@onready var title_label: Label = find_child("TitleLabel", true, false)
@onready var header: Control = find_child("Header", true, false)

func _ready() -> void:
	if close_button and not close_button.pressed.is_connected(_on_close_pressed):
		close_button.pressed.connect(_on_close_pressed)
	
	if header:
		header.gui_input.connect(_on_header_gui_input)
	
	gui_input.connect(_on_window_gui_input)
	
	# Centrar automáticamente en pantalla para evitar ventanas descuadradas
	if global_position.x <= 150.0 and global_position.y <= 120.0:
		call_deferred("center_on_screen")

func center_on_screen() -> void:
	var vp_size = get_viewport_rect().size
	var target_x = max(20.0, (vp_size.x - size.x) * 0.5)
	var target_y = max(20.0, (vp_size.y - size.y) * 0.5)
	global_position = Vector2(target_x, target_y)

# Llamado por UIOrchestrator al instanciar o abrir con parámetros
func initialize_window(_params: Dictionary) -> void:
	pass

func set_title(new_title: String) -> void:
	if title_label:
		title_label.text = new_title

func _on_close_pressed() -> void:
	if window_id != "" and has_node("/root/UIOrchestrator"):
		get_node("/root/UIOrchestrator").close_window(window_id)
	else:
		visible = false

func _on_window_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_request_orchestrator_focus()

func _on_header_gui_input(event: InputEvent) -> void:
	if not is_draggable: return
	
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_is_dragging = true
				_drag_offset = get_global_mouse_position() - global_position
				_request_orchestrator_focus()
			else:
				_is_dragging = false
	elif event is InputEventMouseMotion and _is_dragging:
		var new_pos = get_global_mouse_position() - _drag_offset
		var vp_size = get_viewport_rect().size
		var win_size = size
		
		# Clamping a los bordes de la pantalla
		new_pos.x = clamp(new_pos.x, 0.0, max(0.0, vp_size.x - win_size.x))
		new_pos.y = clamp(new_pos.y, 0.0, max(0.0, vp_size.y - win_size.y))
		global_position = new_pos

func _request_orchestrator_focus() -> void:
	if has_node("/root/UIOrchestrator"):
		var orch = get_node("/root/UIOrchestrator")
		if window_id != "":
			orch.focus_manager.request_focus(window_id)
