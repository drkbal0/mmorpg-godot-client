extends Control

@onready var progress_bar = $VBoxContainer/ProgressBar
@onready var label = $VBoxContainer/Label

func _ready():
	SceneManager.load_progress.connect(_on_load_progress)
	progress_bar.value = 0

func _on_load_progress(percent: float):
	progress_bar.value = percent
	if percent >= 100:
		label.text = "¡Listo!"
