extends Control

@onready var progress_bar = $VBoxContainer/ProgressBar
@onready var label = $VBoxContainer/Label

const ShelterPocketScene = preload("res://ui/windows/ShelterWindow/ShelterPocket.tscn")

## Refugio de bolsillo (Anexo D): en la pantalla de carga, H lo abre y cierra.
var shelter_pocket: Control

func _ready():
	SceneManager.load_progress.connect(_on_load_progress)
	progress_bar.value = 0
	shelter_pocket = ShelterPocketScene.instantiate()
	shelter_pocket.capture_shortcut = true
	shelter_pocket.visible = false
	shelter_pocket.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	shelter_pocket.position = Vector2(get_viewport_rect().size.x - 500, 20)
	add_child(shelter_pocket)

func _on_load_progress(percent: float):
	progress_bar.value = percent
	if percent >= 100:
		label.text = "¡Listo!"
