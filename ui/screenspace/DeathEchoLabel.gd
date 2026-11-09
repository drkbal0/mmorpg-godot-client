extends Control
class_name DeathEchoLabel

## DeathEchoLabel.gd - Screen-Space 2D Loot & Death Echo Indicator
## Floating high-contrast label with distance cue and interaction prompt.

@onready var header_label: Label = $PanelContainer/VBoxContainer/HeaderLabel
@onready var prompt_label: Label = $PanelContainer/VBoxContainer/PromptLabel
@onready var panel: PanelContainer = $PanelContainer

var _base_y: float = 0.0
var _anim_time: float = 0.0

func _ready() -> void:
	custom_minimum_size = Vector2(160, 42)
	size = custom_minimum_size

func setup_loot(owner_name: String = "", item_count: int = 1) -> void:
	if owner_name.is_empty():
		header_label.text = "☠️ ECO DE MUERTE (%d)" % item_count
	else:
		header_label.text = "☠️ RESTOS: %s (%d)" % [owner_name, item_count]
	prompt_label.text = "Pulsa [F] para Saquear"

func _process(delta: float) -> void:
	_anim_time += delta * 3.0
	# Subtle hover bobbing
	panel.position.y = sin(_anim_time) * 3.0
