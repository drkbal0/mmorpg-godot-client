extends Control
class_name DeathEchoLabel

## DeathEchoLabel.gd - Screen-Space 2D Loot & Death Echo Indicator
## Floating high-contrast label with distance cue and interaction prompt.

@onready var header_label: Label = $PanelContainer/VBoxContainer/HeaderLabel
@onready var prompt_label: Label = $PanelContainer/VBoxContainer/PromptLabel
@onready var panel: PanelContainer = $PanelContainer

var _base_y: float = 0.0
var _anim_time: float = 0.0

func _ensure_node_refs() -> void:
	if header_label == null:
		header_label = get_node_or_null("PanelContainer/VBoxContainer/HeaderLabel")
	if prompt_label == null:
		prompt_label = get_node_or_null("PanelContainer/VBoxContainer/PromptLabel")
	if panel == null:
		panel = get_node_or_null("PanelContainer")

func _ready() -> void:
	_ensure_node_refs()
	custom_minimum_size = Vector2(160, 42)
	size = custom_minimum_size

func setup_loot(owner_name: String = "", item_count: int = 1) -> void:
	_ensure_node_refs()
	if header_label:
		if owner_name.is_empty():
			header_label.text = "☠️ ECO DE MUERTE (%d)" % item_count
		else:
			header_label.text = "☠️ RESTOS: %s (%d)" % [owner_name, item_count]
	if prompt_label:
		prompt_label.text = "Pulsa [F] para Saquear"

func _process(delta: float) -> void:
	_anim_time += delta * 3.0
	# Subtle hover bobbing
	panel.position.y = sin(_anim_time) * 3.0

