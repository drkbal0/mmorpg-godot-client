extends Control

@onready var username_input = $VBoxContainer/Username
@onready var password_input = $VBoxContainer/Password
@onready var status_label = $VBoxContainer/StatusLabel

func _ready():
	AuthManager.auth_success.connect(_on_auth_success)
	AuthManager.auth_failed.connect(_on_auth_failed)
	AuthManager.password_updated.connect(_on_password_updated)
	
	$VBoxContainer/LoginButton.pressed.connect(_on_login_pressed)
	$VBoxContainer/RegisterButton.pressed.connect(_on_register_pressed)
	
	# CLI Token jump
	if AuthManager.auth_token != "":
		print("Auto-logging in via CLI token...")
		SceneManager.change_scene_async("res://ui/windows/ShelterWindow/ShelterLobby.tscn")

func _on_login_pressed():
	status_label.text = "Conectando..."
	AuthManager.login(username_input.text, password_input.text)

func _on_register_pressed():
	# For simplicity, we'll use same inputs for registration, email placeholder
	status_label.text = "Registrando..."
	AuthManager.register(username_input.text, username_input.text + "@mmo.com", password_input.text)

func _on_auth_success():
	# Transition to Shelter first as per new flow
	SceneManager.change_scene_async("res://ui/windows/ShelterWindow/ShelterLobby.tscn")

func _on_auth_failed(message):
	status_label.text = message

func _on_update_password_pressed():
	if username_input.text == "" or password_input.text == "":
		status_label.text = "Ingresa usuario y la NUEVA contraseña"
		return
	status_label.text = "Actualizando..."
	var success = await AuthManager.update_password(username_input.text, password_input.text)
	if success:
		status_label.text = "Contraseña actualizada. Intenta logear."

func _on_password_updated():
	status_label.text = "Contraseña actualizada. Intenta logear."
	status_label.add_theme_color_override("font_color", Color(0, 1, 0)) # Green
