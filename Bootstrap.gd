extends Control

## Bootstrap.gd - Application Entry Point
## Orchestrates initial patching and hands off to Login.

@onready var status_label = $StatusLabel
@onready var progress_bar = $ProgressBar

func _ready():
	print("Bootstrap: Starting initialization...")
	
	# Initial UI State
	status_label.text = "Checking client integrity..."
	progress_bar.value = 0
	progress_bar.visible = false
	
	# 0. Anti-Tamper & Cryptographic Integrity Check
	var integrity = ClientSecurity.verify_integrity()
	if not integrity.get("valid", false):
		status_label.text = "ERROR DE SEGURIDAD: Paquete alterado o corrupto."
		printerr("Bootstrap ALERTA: ", integrity.get("error", "Fallo de integridad"))
		return

	status_label.text = "Checking for updates..."
	
	# 1. Connect to UpdateManager signals
	UpdateManager.update_started.connect(_on_update_started)
	UpdateManager.update_progress.connect(_on_update_progress)
	UpdateManager.update_finished.connect(_on_update_finished)
	
	# 2. Check for updates
	var success = await UpdateManager.check_for_updates()
	if not success:
		status_label.text = "Error: Could not reach update server. Skipping..."
		await get_tree().create_timer(2.0).timeout
		_proceed_to_login()
		return
		
	# 3. Process mandatory updates
	await UpdateManager.process_mandatory_updates()
	
func _on_update_started(total_size):
	status_label.text = "Downloading updates..."
	progress_bar.max_value = total_size
	progress_bar.visible = true

func _on_update_progress(downloaded, total):
	progress_bar.value = downloaded
	var percent = int((float(downloaded) / total) * 100)
	status_label.text = "Downloading updates... %d%%" % percent

func _on_update_finished():
	status_label.text = "Updates ready. Starting game..."
	await get_tree().create_timer(1.0).timeout
	_proceed_to_login()

func _proceed_to_login():
	# Standard handoff to Login Screen
	get_tree().change_scene_to_file("res://login_screen.tscn")

func _on_repair_button_pressed():
	status_label.text = "Cleaning cache and repairing files..."
	ItemManager.clear_cache()
	# UpdateManager could also have a clear_local_metadata() if it stores PCK hashes
	if UpdateManager.has_method("clear_local_metadata"):
		UpdateManager.clear_local_metadata()
	
	await get_tree().create_timer(1.0).timeout
	status_label.text = "Cache cleared. Re-checking for updates..."
	_ready() # Restart bootstrap process
