extends "res://ui/windows/common/EntryWindow.gd"
## Inicio de sesión — UI v2.4 Paso 15 (design_ref/pantallas_html/MMO-Login.html).
##
## - Fondo cinemático (mapa-fondo) con velo rgba(5,8,10,0.62); «[NOMBRE]» 54 px y lema a la izquierda.
## - Tarjeta derecha de 420 px: «Bienvenido de vuelta», «Entrar con llave de acceso» (#46e3c1),
##   «o escanea con la app» con QR de 132×132 (se renueva solo al caducar), «Usar correo y
##   contraseña» (formulario desplegable con bloqueo tras 5 fallos), «Mantener la sesión en este
##   equipo» y selector de reino («Reino Umbral · 24 ms · sin cola»).
## - Barra de accesibilidad previa al ingreso: A− · A · A+ · Alto contraste · Narrador [Ctrl Alt N]
##   · Daltonismo. Pie: «Servidores estables · v1.0.4».
##
## Teclado: Enter = llave de acceso (o enviar el formulario) · Ctrl+Alt+N narrador · Esc cierra el
## formulario de correo.

signal logged_in(method: String)

const KEY_ICON := "M4 12a4 4 0 1 0 8 0a4 4 0 1 0-8 0M12 12h9M18 12v3M21 12v2"

var logo_label: Label
var tagline_label: Label
var login_card: PanelContainer
var welcome_label: Label
var passkey_button: Button
var qr: EK.QRCode
var qr_text: Label
var qr_timer: Label
var credentials_link: Button
var credentials_box: VBoxContainer
var email_input: LineEdit
var password_input: LineEdit
var submit_button: Button
var error_label: Label
var keep_check: EK.CheckSquare
var keep_label: Label
var realm_button: Button
var realm_name: Label
var realm_status: Label
var footer_label: Label
var credentials_open := false

var _last_dynamic := ""


func _screen_id() -> String:
	return "login"


func _screen() -> String:
	return AuthScript.SCREEN_LOGIN


func _veil_base() -> float:
	return T.LOGIN_VEIL.a


func _screen_title() -> String:
	return "Inicio de sesión. Bienvenido de vuelta"


func _service_signals() -> Array:
	return ["session_changed", "login_failed", "qr_refreshed"]


func initialize_window(params: Dictionary) -> void:
	super.initialize_window(params)
	if service.qr_expired():
		service.start_qr_login()
	refresh()


func _ready() -> void:
	super._ready()
	if service.qr_expired():
		service.start_qr_login()
	refresh()


func _process(_delta: float) -> void:
	if _built and visible:
		_refresh_dynamic()


# ==========================================================================
# API
# ==========================================================================
func login_passkey() -> Dictionary:
	return _after_login(service.login_with_passkey())


func login_credentials(email: String = "", password: String = "") -> Dictionary:
	var e := email if email != "" else email_input.text
	var p := password if password != "" else password_input.text
	return _after_login(service.login_with_credentials(e, p))


## Simula la app móvil leyendo el QR actual («Entrar en el PC»).
func scan_qr_from_mobile(code: String = "") -> Dictionary:
	return _after_login(service.confirm_qr_from_mobile(code if code != "" else service.qr_code))


func toggle_credentials() -> void:
	credentials_open = not credentials_open
	refresh()
	if credentials_open and email_input.is_inside_tree():
		email_input.grab_focus()


func set_keep_session(on: bool) -> void:
	service.set_keep_session(on)
	refresh()


func cycle_realm() -> String:
	var i := -1
	for k in service.servers.size():
		if str(service.servers[k]["id"]) == service.selected_realm:
			i = k
	var next: Dictionary = service.servers[(i + 1) % service.servers.size()]
	service.select_realm(str(next["id"]))
	refresh()
	return service.selected_realm


func _after_login(r: Dictionary) -> Dictionary:
	if r.get("ok", false):
		password_input.text = ""
		logged_in.emit(str(r["method"]))
		navigate("character_select")
	else:
		refresh()
	return r


func _handle_key(code: int, _ev: InputEventKey) -> bool:
	match code:
		KEY_ENTER, KEY_KP_ENTER:
			if credentials_open and (email_input.has_focus() or password_input.has_focus()):
				login_credentials()
			else:
				login_passkey()
			return true
		KEY_ESCAPE:
			if credentials_open:
				toggle_credentials()
				return true
	return false


# ==========================================================================
# Construcción
# ==========================================================================
func _build() -> void:
	var left := EK.vbox("Brand", 14)
	place(left, 70, 220, -1, -1, 560)
	logo_label = Kit.label(service.game_short, T.LOGIN_LOGO_SIZE, T.ACCENT_DEFAULT, "bold")
	logo_label.name = "Logo"
	var fv := FontVariation.new()
	fv.base_font = T.font("bold")
	fv.spacing_glyph = 10
	logo_label.add_theme_font_override("font", fv)
	left.add_child(logo_label)
	tagline_label = Kit.shadow(Kit.label(service.tagline, 20, T.ENTRY_TEXT_SOFT))
	tagline_label.name = "Tagline"
	tagline_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tagline_label.custom_minimum_size.x = 560
	left.add_child(tagline_label)

	login_card = EK.card("LoginCard", 28)
	place(login_card, -1, T.LOGIN_CARD_TOP, T.LOGIN_CARD_RIGHT, -1, T.LOGIN_CARD_WIDTH)
	var v := EK.vbox("Body", 16)
	login_card.add_child(v)
	welcome_label = Kit.label("Bienvenido de vuelta", 26, T.TEXT, "bold")
	welcome_label.name = "Welcome"
	v.add_child(welcome_label)
	passkey_button = EK.button("PasskeyButton", "Entrar con llave de acceso", 48, 16)
	EK.primary(passkey_button)
	passkey_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var ic = Kit.Icon.new(KEY_ICON, Vector2(18, 18))
	ic.name = "KeyIcon"
	ic.stroke = T.ENTRY_PRIMARY_TEXT
	ic.icon_size = 18
	ic.width = 2.4
	ic.position = Vector2(74, 15)
	passkey_button.add_child(ic)
	passkey_button.pressed.connect(login_passkey)
	v.add_child(passkey_button)
	var div := EK.hbox("Divider", 10)
	v.add_child(div)
	for i in 2:
		var line := ColorRect.new()
		line.color = T.ENTRY_DIVIDER
		line.custom_minimum_size = Vector2(0, 1)
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		div.add_child(line)
		if i == 0:
			var dl := Kit.label("o escanea con la app", 12, T.TEXT_MUTED)
			dl.name = "Text"
			div.add_child(dl)
	var qrow := EK.hbox("QR", 16)
	v.add_child(qrow)
	qr = EK.QRCode.new()
	qr.name = "QRCode"
	qrow.add_child(qr)
	var qv := EK.vbox("Text", 8)
	qv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	qv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	qrow.add_child(qv)
	qr_text = Kit.label("Abre la app en tu móvil, toca «Entrar en el PC» y apunta aquí. No escribes nada.", 13, T.TEXT_SECONDARY)
	qr_text.name = "Help"
	qr_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	qv.add_child(qr_text)
	qr_timer = Kit.label("", 12, T.TEXT_MUTED)
	qr_timer.name = "Timer"
	qv.add_child(qr_timer)
	credentials_link = EK.link("CredentialsLink", "Usar correo y contraseña", 14)
	credentials_link.pressed.connect(toggle_credentials)
	v.add_child(credentials_link)
	credentials_box = EK.vbox("Credentials", 8)
	v.add_child(credentials_box)
	email_input = _make_input("Email", "Correo")
	credentials_box.add_child(email_input)
	password_input = _make_input("Password", "Contraseña")
	password_input.secret = true
	password_input.text_submitted.connect(func(_t: String) -> void: login_credentials())
	credentials_box.add_child(password_input)
	submit_button = EK.button("Submit", "Entrar", 40, 15)
	submit_button.pressed.connect(func() -> void: login_credentials())
	credentials_box.add_child(submit_button)
	error_label = Kit.label("", 13, Color("#ff8a8a"), "semibold")
	error_label.name = "Error"
	error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(error_label)
	var keep := EK.hbox("KeepSession", 10)
	keep.mouse_filter = Control.MOUSE_FILTER_STOP
	v.add_child(keep)
	keep_check = EK.CheckSquare.new()
	keep_check.name = "Check"
	keep_check.toggled.connect(set_keep_session)
	keep.add_child(keep_check)
	keep_label = Kit.label("Mantener la sesión en este equipo", 14, T.TEXT)
	keep_label.name = "Text"
	keep.add_child(keep_label)
	realm_button = Button.new()
	realm_button.name = "Realm"
	realm_button.focus_mode = Control.FOCUS_ALL
	realm_button.custom_minimum_size = Vector2(0, 38)
	realm_button.tooltip_text = "Cambiar de reino"
	for st in ["normal", "hover", "pressed", "focus"]:
		var sb := Kit.box(T.ENTRY_SUB_BG if st != "hover" else T.ENTRY_SUB_BG.lightened(0.05), 12)
		if st == "focus":
			sb = Kit.box(T.ENTRY_SUB_BG, 12, 2, T.ACCENT_DEFAULT)
		realm_button.add_theme_stylebox_override(st, sb)
	realm_button.pressed.connect(cycle_realm)
	v.add_child(realm_button)
	var rh := EK.hbox("Row", 4)
	rh.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rh.offset_left = 12
	rh.offset_right = -12
	realm_button.add_child(rh)
	var rl := Kit.label("Reino", 13, T.TEXT)
	rl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rh.add_child(rl)
	realm_name = Kit.label("", 13, T.TEXT, "bold")
	realm_name.name = "Name"
	realm_name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rh.add_child(realm_name)
	rh.add_child(EK.spacer())
	realm_status = Kit.label("", 13, T.ENTRY_STEP_DONE)
	realm_status.name = "Status"
	realm_status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rh.add_child(realm_status)

	var bar := build_a11y_bar()
	place(bar, 40, -1, -1, 30)
	footer_label = Kit.shadow(Kit.label("", 13, T.TEXT_SECONDARY))
	footer_label.name = "FooterStatus"
	footer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	place(footer_label, -1, -1, 40, 38, 400)


func _make_input(node_name: String, placeholder: String) -> LineEdit:
	var e := LineEdit.new()
	e.name = node_name
	e.placeholder_text = placeholder
	e.custom_minimum_size = Vector2(0, 40)
	e.add_theme_font_override("font", T.font("medium"))
	e.add_theme_font_size_override("font_size", 15)
	e.add_theme_color_override("font_color", T.TEXT)
	e.add_theme_color_override("font_placeholder_color", T.TEXT_MUTED)
	var sb := Kit.box(T.ENTRY_SUB_BG, 10, 1, Color(1, 1, 1, 0.08))
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	e.add_theme_stylebox_override("normal", sb)
	var fs := Kit.box(T.ENTRY_SUB_BG, 10, 2, T.ACCENT_DEFAULT)
	fs.content_margin_left = 12
	fs.content_margin_right = 12
	e.add_theme_stylebox_override("focus", fs)
	return e


# ==========================================================================
# Refresco
# ==========================================================================
func refresh() -> void:
	if not _built or service == null:
		return
	passkey_button.disabled = not bool(service.login_cfg.get("passkey_registered", false))
	credentials_box.visible = credentials_open
	credentials_link.text = "Ocultar correo y contraseña" if credentials_open else "Usar correo y contraseña"
	submit_button.disabled = service.is_locked()
	var err: Dictionary = service.last_login_error
	error_label.text = str(err.get("message", ""))
	error_label.visible = not err.is_empty()
	error_label.add_theme_color_override("font_color", Color(service.status_color("bad")))
	keep_check.on = service.keep_session
	var r: Dictionary = service.realm()
	realm_name.text = str(r.get("name", ""))
	realm_status.text = service.realm_line()
	realm_status.add_theme_color_override("font_color", Color(service.server_color(r)) if not r.is_empty() else T.TEXT_SECONDARY)
	footer_label.text = service.footer_status_text()
	refresh_a11y_bar()
	_refresh_dynamic(true)
	apply_accessibility()


func _refresh_dynamic(force: bool = false) -> void:
	var key := "%s|%d|%s" % [service.qr_code, ceili(service.qr_remaining), str(service.is_locked())]
	if key == _last_dynamic and not force:
		return
	_last_dynamic = key
	qr.modules = service.qr_matrix()
	qr.expired = service.qr_expired()
	qr.set_meta("code", service.qr_code)
	qr_timer.text = "Código %s · se renueva en %s" % [service.qr_code, AuthScript.fmt_clock(service.qr_remaining)] if not service.qr_expired() else "Generando un código nuevo…"
	if service.is_locked():
		error_label.text = "Demasiados intentos. Espera %d s" % ceili(service.lockout_remaining)
		error_label.visible = true
	submit_button.disabled = service.is_locked()
