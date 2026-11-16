extends Node
## Entrada, autenticación y ciclo de vida del personaje — UI v2.4 Paso 15 (ADR 113).
## Pantallas: MMO-Launcher.html · MMO-Login.html · MMO-Seleccion.html · MMO-Creacion.html ·
## MMO-Carga.html (PROMPT_ANTIGRAVITY.md §2.1, §2.2, §3 «Entrada», Anexos A, B, D y F).
##
## Autoload `AuthLifecycleService` o instanciable con `.new()` + `load_seed()` (reloj manual: `tick`).
## Seed: res://config/auth/auth_lifecycle_seed.json
##
## Flujo: launcher → login → character_select ⇄ character_create → game_loading → in_world.
##
## - Launcher: temporada activa, «Qué cambia para ti» (viñetas por tipo), estado de servidores,
##   amigos activos, instalación progresiva por paquetes («Jugar ya» con lo imprescindible),
##   versión, notas del parche y comprobación de integridad.
## - Login: llave de acceso, QR para la app móvil («Entrar en el PC», caduca y se renueva),
##   correo y contraseña (bloqueo tras N fallos), «Mantener la sesión» y reino.
## - Accesibilidad previa al ingreso: A− / A / A+, alto contraste, narrador (Ctrl+Alt+N) y
##   daltonismo (protanopia, deuteranopia, tritanopia). Se guarda aunque no inicies sesión.
## - Selección: personajes (incl. especiales asignados por el equipo, Anexo F), ranuras libres,
##   «Mientras no estabas», «Continúa donde lo dejaste» y borrado con nombre tecleado.
## - Creación en 4 pasos: Origen (afinidad elemental del Anexo B) · Clase (rol, alcance, estilo,
##   maniquí de 5 min) · Apariencia chibi · Nombre (3-16 alfanuméricos, sin groserías, libre) y
##   rasgo cósmico.
## - Carga táctica: destino, objetivo, cita de lore, consejos según destino, actividades en
##   espera, grupo dentro y progreso con etapa y tiempo restante.

signal flow_changed(screen: String)
signal launcher_changed
signal install_progress(ratio: float)
signal session_changed(logged_in: bool)
signal login_failed(code: String, message: String)
signal qr_refreshed(code: String)
signal accessibility_changed
signal narrated(text: String)
signal characters_changed
signal character_selected(character_id: String)
signal character_created(character: Dictionary)
signal character_deleted(character_id: String)
signal creation_changed
signal trial_started(class_id: String)
signal trial_finished(class_id: String)
signal world_entry_requested(character: Dictionary, destination: Dictionary)
signal loading_progressed(ratio: float)
signal loading_finished(destination: Dictionary)

const DEFAULT_SEED_PATH := "res://config/auth/auth_lifecycle_seed.json"
const DEFAULT_SESSION_PATH := "user://auth_lifecycle.cfg"

const SCREEN_LAUNCHER := "launcher"
const SCREEN_LOGIN := "login"
const SCREEN_SELECT := "character_select"
const SCREEN_CREATE := "character_create"
const SCREEN_LOADING := "game_loading"
const SCREEN_WORLD := "in_world"
const SCREENS := [SCREEN_LAUNCHER, SCREEN_LOGIN, SCREEN_SELECT, SCREEN_CREATE, SCREEN_LOADING, SCREEN_WORLD]

const METHOD_PASSKEY := "passkey"
const METHOD_QR := "qr"
const METHOD_CREDENTIALS := "credentials"
const METHOD_SESSION := "session"

const ACCENT := "#46e3c1"
const TEXT := "#eef2f4"
const NEUTRAL := "#9aa6ae"
const MUTED := "#7c8992"
const SPECIAL := "#f5c35b"

## Tamaños de letra previos al ingreso: A− · A · A+.
const FONT_STEPS := [0.88, 1.0, 1.16]
const FONT_STEP_LABELS := ["A−", "A", "A+"]
const COLORBLIND_MODES := ["none", "protanopia", "deuteranopia", "tritanopia"]
const COLORBLIND_LABELS := {"none": "Daltonismo", "protanopia": "Protanopia", "deuteranopia": "Deuteranopia", "tritanopia": "Tritanopia"}
## Paletas semánticas por modo (good / warn / bad / info / neutral). «none» = colores del diseño.
const PALETTES := {
	"none": {"good": "#4fe39a", "warn": "#f5c35b", "bad": "#ff6b6b", "info": "#6cb8ff", "neutral": "#9aa6ae"},
	"protanopia": {"good": "#5aa9ff", "warn": "#f5e35b", "bad": "#c88a2b", "info": "#9ad0ff", "neutral": "#9aa6ae"},
	"deuteranopia": {"good": "#5aa9ff", "warn": "#ffb347", "bad": "#e07a2b", "info": "#9ad0ff", "neutral": "#9aa6ae"},
	"tritanopia": {"good": "#4fe3c8", "warn": "#ff8fa8", "bad": "#e2554f", "info": "#46e3c1", "neutral": "#9aa6ae"},
}
const CHANGE_KINDS := {"improvement": "good", "balance": "warn", "note": "neutral"}
const SERVER_KINDS := {"stable": "good", "ok": "good", "queue": "warn", "maintenance": "bad", "down": "bad"}
const FRIEND_KINDS := {"online": "good", "busy": "warn", "offline": "neutral"}

const STEP_LABELS := ["Origen", "Clase", "Apariencia", "Nombre"]
const STEP_NEXT_LABELS := ["Siguiente: clase", "Siguiente: apariencia", "Siguiente: nombre", "Confirmar creación"]
const APPEARANCE_KEYS := ["body", "hair_style", "hair_color", "eye_color", "outfit"]
const RATING_KEYS := ["damage", "control", "survival", "difficulty"]
const RATING_LABELS := {"damage": "Daño", "control": "Control", "survival": "Supervivencia", "difficulty": "Dificultad"}
const NAME_ACCENTED := "áéíóúüñÁÉÍÓÚÜÑ"
const LEET := {"0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t", "@": "a", "$": "s"}

const NAME_MESSAGES := {
	"ok": "Disponible ✓",
	"empty": "Escribe un nombre",
	"too_short": "Mínimo %d caracteres",
	"too_long": "Máximo %d caracteres",
	"invalid_chars": "Solo letras y números, sin espacios ni símbolos",
	"starts_with_digit": "Debe empezar por una letra",
	"profanity": "Ese nombre no está permitido",
	"reserved": "Nombre reservado",
	"taken": "Ya existe un personaje con ese nombre",
}

# --- Datos del seed ---------------------------------------------------------
var seed_data: Dictionary = {}
var game_name := "[NOMBRE DEL JUEGO]"
var game_short := "[NOMBRE]"
var tagline := ""
var version := "v1.0.4"
var patch_notes_url := ""
var launcher_tabs: Array[Dictionary] = []
var season: Dictionary = {}
var changes: Array[Dictionary] = []
var account: Dictionary = {}
var friends_playing := 0
var friends: Array[Dictionary] = []
var maintenance := ""
var download: Dictionary = {}
var packs: Array[Dictionary] = []
var servers: Array[Dictionary] = []
var login_cfg: Dictionary = {}
var max_slots := 6
var characters: Array[Dictionary] = []
var away: Array[Dictionary] = []
var nest_ready := 0
var origins: Array[Dictionary] = []
var classes: Array[Dictionary] = []
var special_classes: Array[Dictionary] = []
var roles: Dictionary = {}
var appearance_options: Dictionary = {}
var traits: Array[Dictionary] = []
var name_rules: Dictionary = {}
var trial_cfg: Dictionary = {}
var loading_cfg: Dictionary = {}

# --- Estado ------------------------------------------------------------------
var flow_screen := SCREEN_LAUNCHER
var launcher_tab := "home"
var install_paused := false
var last_integrity: Dictionary = {}

var logged_in := false
var auth_method := ""
var account_name := ""
var keep_session := true
var selected_realm := ""
var failed_attempts := 0
var lockout_remaining := 0.0
var qr_code := ""
var qr_remaining := 0.0
var qr_generation := 0
var qr_auto_refresh := true
var last_login_error: Dictionary = {}

var font_step := 1
var high_contrast := false
var narrator := false
var colorblind_mode := "none"
var announcements: Array[String] = []
var tts_enabled := true

var selected_character_id := ""
var pending_delete_id := ""

var creation_step := 0
var max_step_reached := 0
var draft: Dictionary = {}
var trial_active := false
var trial_class_id := ""
var trial_remaining := 0.0

var loading_active := false
var loading_progress := 0.0
var loading_destination: Dictionary = {}
var loading_character: Dictionary = {}
var last_world_entry: Dictionary = {}

## Reloj automático en `_process` (los tests lo apagan y llaman a `tick`).
var auto_tick := true
## Copia el personaje elegido en el autoload AuthManager al entrar al mundo.
var sync_auth_manager := true
## Ruta de persistencia (sesión «Mantener la sesión» y accesibilidad previa).
var session_path := DEFAULT_SESSION_PATH
var _created_counter := 0


func _ready() -> void:
	if seed_data.is_empty() and FileAccess.file_exists(DEFAULT_SEED_PATH):
		load_seed(DEFAULT_SEED_PATH)
		load_preferences()


func _process(delta: float) -> void:
	if auto_tick:
		tick(delta)


# ==========================================================================
# Carga del seed
# ==========================================================================
func load_seed(path: String = DEFAULT_SEED_PATH) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		return false
	load_from_dict(data)
	return true


func load_from_dict(data: Dictionary) -> void:
	seed_data = data.duplicate(true)
	game_name = str(data.get("game_name", game_name))
	game_short = str(data.get("game_short", game_short))
	tagline = str(data.get("tagline", ""))
	var l: Dictionary = data.get("launcher", {})
	version = str(l.get("version", version))
	patch_notes_url = str(l.get("patch_notes_url", ""))
	launcher_tabs = _dicts(l.get("tabs", []))
	season = (l.get("season", {}) as Dictionary).duplicate(true)
	changes = _dicts(l.get("changes", []))
	account = (l.get("account", {}) as Dictionary).duplicate(true)
	friends_playing = int(l.get("friends_playing", 0))
	friends = _dicts(l.get("friends", []))
	maintenance = str(l.get("maintenance", ""))
	download = (l.get("download", {}) as Dictionary).duplicate(true)
	packs = _dicts(l.get("packs", []))
	for p in packs:
		p["progress"] = clampf(float(p.get("progress", 0.0)), 0.0, 1.0)
	servers = _dicts(data.get("servers", []))
	login_cfg = (data.get("login", {}) as Dictionary).duplicate(true)
	max_slots = int(data.get("max_slots", 6))
	characters = _dicts(data.get("characters", []))
	for c in characters:
		_normalize_character(c)
	away = _dicts(data.get("away", []))
	nest_ready = int(data.get("nest_ready", 0))
	origins = _dicts(data.get("origins", []))
	classes = _dicts(data.get("classes", []))
	special_classes = _dicts(data.get("special_classes", []))
	roles = (data.get("roles", {}) as Dictionary).duplicate(true)
	appearance_options = (data.get("appearance", {}) as Dictionary).duplicate(true)
	traits = _dicts(data.get("traits", []))
	name_rules = (data.get("name_rules", {}) as Dictionary).duplicate(true)
	trial_cfg = (data.get("trial", {}) as Dictionary).duplicate(true)
	loading_cfg = (data.get("loading", {}) as Dictionary).duplicate(true)
	selected_realm = home_server_id()
	_sort_characters()
	selected_character_id = ""
	var first := first_playable()
	if not first.is_empty():
		selected_character_id = str(first["id"])
	_reset_draft()


static func _dicts(arr) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if arr is Array:
		for e in arr:
			if e is Dictionary:
				out.append((e as Dictionary).duplicate(true))
	return out


func _normalize_character(c: Dictionary) -> void:
	c["level"] = int(c.get("level", 1))
	c["ilvl"] = int(c.get("ilvl", 0))
	c["last_played_days"] = int(c.get("last_played_days", 0))
	c["special"] = bool(c.get("special", false))
	c["special_days_left"] = int(c.get("special_days_left", 0))
	if not c.has("appearance"):
		c["appearance"] = default_appearance()
	if not c.has("stats"):
		c["stats"] = {}


# ==========================================================================
# Reloj
# ==========================================================================
func tick(delta: float) -> void:
	if delta <= 0.0:
		return
	if flow_screen == SCREEN_LAUNCHER and not install_paused and not install_complete():
		install_tick(delta)
	if lockout_remaining > 0.0:
		lockout_remaining = maxf(0.0, lockout_remaining - delta)
		if lockout_remaining <= 0.0:
			failed_attempts = 0
	if qr_code != "" and not logged_in:
		qr_remaining = maxf(0.0, qr_remaining - delta)
		if qr_remaining <= 0.0 and qr_auto_refresh:
			start_qr_login()
	if trial_active:
		trial_remaining = maxf(0.0, trial_remaining - delta)
		if trial_remaining <= 0.0:
			end_trial()
	if loading_active:
		var dur := maxf(0.1, float(loading_destination.get("duration_s", 10.0)))
		set_loading_progress(loading_progress + delta / dur)


# ==========================================================================
# Flujo
# ==========================================================================
func go_to(screen: String) -> bool:
	if not SCREENS.has(screen):
		return false
	if flow_screen != screen:
		flow_screen = screen
		flow_changed.emit(screen)
	return true


## «Jugar ya»: con lo imprescindible instalado pasa al login (o a la selección si la sesión se mantiene).
func play() -> Dictionary:
	if not can_play():
		return {"ok": false, "code": "install_required", "message": "Faltan paquetes imprescindibles"}
	if not logged_in:
		restore_session()
	go_to(SCREEN_SELECT if logged_in else SCREEN_LOGIN)
	return {"ok": true, "screen": flow_screen}


# ==========================================================================
# Colores semánticos (daltonismo)
# ==========================================================================
func palette() -> Dictionary:
	return PALETTES.get(colorblind_mode, PALETTES["none"])


func status_color(kind: String) -> String:
	return str(palette().get(kind, NEUTRAL))


func change_color(change_kind: String) -> String:
	return status_color(str(CHANGE_KINDS.get(change_kind, "neutral")))


func server_color(s: Dictionary) -> String:
	return status_color(str(SERVER_KINDS.get(str(s.get("status", "ok")), "neutral")))


func friend_color(f: Dictionary) -> String:
	return status_color(str(FRIEND_KINDS.get(str(f.get("status", "offline")), "neutral")))


# ==========================================================================
# Launcher
# ==========================================================================
func set_launcher_tab(id: String) -> bool:
	for t in launcher_tabs:
		if str(t["id"]) == id:
			launcher_tab = id
			launcher_changed.emit()
			return true
	return false


func launcher_tab_label(id: String = "") -> String:
	var key := launcher_tab if id == "" else id
	for t in launcher_tabs:
		if str(t["id"]) == key:
			return str(t["label"])
	return ""


func window_title() -> String:
	return "%s Launcher" % game_name


func friends_playing_text() -> String:
	return "%d %s jugando ahora" % [friends_playing, "amigo" if friends_playing == 1 else "amigos"]


func account_status_text() -> String:
	if bool(login_cfg.get("passkey_registered", false)):
		return str(account.get("passkey_text", "Llave de acceso activa"))
	return "Sin llave de acceso"


func home_server_id() -> String:
	for s in servers:
		if bool(s.get("home", false)):
			return str(s["id"])
	return str(servers[0]["id"]) if not servers.is_empty() else ""


func server(id: String) -> Dictionary:
	for s in servers:
		if str(s["id"]) == id:
			return s
	return {}


func server_label(s: Dictionary) -> String:
	return "%s (tu reino)" % s["name"] if bool(s.get("home", false)) else str(s["name"])


func server_line(s: Dictionary) -> String:
	match str(s.get("status", "ok")):
		"stable":
			return "%d ms · estable" % int(s["ping_ms"])
		"queue":
			return "cola ~%d min" % int(s.get("queue_min", 0))
		"maintenance":
			return "en mantenimiento"
		"down":
			return "sin conexión"
	return "%d ms" % int(s["ping_ms"])


func packs_total_weight() -> float:
	var w := 0.0
	for p in packs:
		w += float(p.get("weight", 1))
	return maxf(w, 0.001)


func install_ratio() -> float:
	var acc := 0.0
	for p in packs:
		acc += float(p["progress"]) * float(p.get("weight", 1))
	return acc / packs_total_weight()


func install_complete() -> bool:
	for p in packs:
		if float(p["progress"]) < 1.0:
			return false
	return true


func can_play() -> bool:
	for p in packs:
		if bool(p.get("required", false)) and float(p["progress"]) < 1.0:
			return false
	return true


## Paquete que se está bajando ahora (el primero sin terminar) o {}.
func active_pack() -> Dictionary:
	for p in packs:
		if float(p["progress"]) < 1.0:
			return p
	return {}


func pack_state(p: Dictionary) -> String:
	if float(p["progress"]) >= 1.0:
		return "done"
	return "active" if p == active_pack() else "queued"


func pack_label(p: Dictionary) -> String:
	match pack_state(p):
		"done":
			return "%s ✓" % p["name"]
		"active":
			return "%s %d %%" % [p["name"], roundi(float(p["progress"]) * 100.0)]
	return "%s en cola" % p["name"]


func pack_color(p: Dictionary) -> String:
	match pack_state(p):
		"done":
			return TEXT
		"active":
			return "#5aa9ff"
	return MUTED


## Color de relleno de la barra segmentada (#46e3c1 hecho · #5aa9ff bajando · #f5b546 en cola).
func pack_fill_color(p: Dictionary) -> String:
	match pack_state(p):
		"done":
			return ACCENT
		"active":
			return "#5aa9ff"
	return "#f5b546"


func remaining_gb() -> float:
	return maxf(0.0, float(download.get("total_gb", 0.0)) - float(download.get("done_gb", 0.0)))


func remaining_minutes() -> int:
	var speed := float(download.get("speed_mbps", 0.0))
	if speed <= 0.0:
		return 0
	return ceili(remaining_gb() * 1024.0 / speed / 60.0)


func download_line() -> String:
	if install_complete():
		return "Todo instalado · %s GB" % fmt_dec(float(download.get("total_gb", 0.0)))
	var state := "En pausa" if install_paused else "Actualizando"
	return "%s · %s de %s GB · %s MB/s · %d min" % [state, fmt_dec(float(download.get("done_gb", 0.0))), fmt_dec(float(download.get("total_gb", 0.0))), fmt_dec(float(download.get("speed_mbps", 0.0))), remaining_minutes()]


func download_options_text() -> String:
	return "%s · Limitar mientras juego%s" % ["Reanudar" if install_paused else "Pausar", " ✓" if bool(download.get("limit_while_playing", false)) else ""]


func play_hint() -> String:
	var pending: Array[String] = []
	for p in packs:
		if float(p["progress"]) < 1.0 and not bool(p.get("required", false)):
			pending.append(str(p["name"]))
	if pending.is_empty():
		return "Todo listo para jugar" if install_complete() else "Instalando lo imprescindible…"
	var names := pending[0] if pending.size() == 1 else "%s y %s" % [", ".join(pending.slice(0, pending.size() - 1)), pending[-1]]
	return "%s se %s de bajar mientras juegas" % [names, "termina" if pending.size() == 1 else "terminan"]


func toggle_install_pause() -> bool:
	install_paused = not install_paused
	launcher_changed.emit()
	return install_paused


func toggle_limit_while_playing() -> bool:
	download["limit_while_playing"] = not bool(download.get("limit_while_playing", false))
	launcher_changed.emit()
	return bool(download["limit_while_playing"])


## Avanza la instalación `delta` segundos a la velocidad actual (el paquete activo primero).
func install_tick(delta: float) -> void:
	var budget := float(download.get("speed_mbps", 0.0)) * delta / 1024.0
	var total := float(download.get("total_gb", 0.0))
	if budget <= 0.0 or total <= 0.0:
		return
	var tw := packs_total_weight()
	while budget > 0.0:
		var p := active_pack()
		if p.is_empty():
			break
		var pack_gb := total * float(p.get("weight", 1)) / tw
		var need := (1.0 - float(p["progress"])) * pack_gb
		var used := minf(need, budget)
		p["progress"] = minf(1.0, float(p["progress"]) + used / maxf(pack_gb, 0.0001))
		if need - used <= 0.000001:
			p["progress"] = 1.0
		budget -= used
		download["done_gb"] = minf(total, float(download.get("done_gb", 0.0)) + used)
	if install_complete():
		download["done_gb"] = total
	install_progress.emit(install_ratio())
	launcher_changed.emit()


## Comprobación de integridad: repara los paquetes marcados como dañados.
func verify_integrity() -> Dictionary:
	var repaired: Array[String] = []
	for p in packs:
		if bool(p.get("corrupt", false)):
			p["corrupt"] = false
			repaired.append(str(p["name"]))
	var checked := 0
	for p in packs:
		if float(p["progress"]) > 0.0:
			checked += 1
	var text := "Integridad verificada · %d paquetes correctos" % checked
	if not repaired.is_empty():
		text = "Reparados: %s · %d paquetes verificados" % [", ".join(repaired), checked]
	last_integrity = {"ok": true, "checked": checked, "repaired": repaired, "text": text, "version": version}
	launcher_changed.emit()
	return last_integrity


# ==========================================================================
# Login
# ==========================================================================
func is_locked() -> bool:
	return lockout_remaining > 0.0


func login_with_passkey() -> Dictionary:
	if not bool(login_cfg.get("passkey_registered", false)):
		return _fail("no_passkey", "No hay ninguna llave de acceso en este equipo")
	return _succeed(METHOD_PASSKEY, str(account.get("title", "Tu cuenta")))


## Genera un código QR nuevo (la app móvil lo lee con «Entrar en el PC»).
func start_qr_login() -> String:
	qr_generation += 1
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s|%d" % [game_name, qr_generation])
	const ALPHA := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	var code := "UMB-"
	for i in 6:
		code += ALPHA[rng.randi_range(0, ALPHA.length() - 1)]
	qr_code = code
	qr_remaining = float(login_cfg.get("qr_ttl_s", 120))
	qr_refreshed.emit(qr_code)
	return qr_code


func qr_expired() -> bool:
	return qr_code == "" or qr_remaining <= 0.0


## Matriz `size`×`size` (true = módulo oscuro) derivada del código: 3 marcas de esquina + datos.
func qr_matrix(code: String = "", size: int = 9) -> Array[bool]:
	var c := code if code != "" else qr_code
	var out: Array[bool] = []
	var h := hash(c)
	var rng := RandomNumberGenerator.new()
	rng.seed = h
	for y in size:
		for x in size:
			var corner := -1
			if x < 3 and y < 3:
				corner = 0
			elif x >= size - 3 and y < 3:
				corner = 1
			elif x < 3 and y >= size - 3:
				corner = 2
			if corner >= 0:
				var lx := x if x < 3 else x - (size - 3)
				var ly := y if y < 3 else y - (size - 3)
				out.append(not (lx == 1 and ly == 1))
			else:
				out.append(rng.randf() < 0.5)
	return out


## La app móvil confirma el código («Entrar en el PC»): no escribes nada en el PC.
func confirm_qr_from_mobile(code: String, mobile_account: String = "") -> Dictionary:
	if qr_code == "" or code != qr_code:
		return _fail("qr_mismatch", "Ese código no corresponde a esta pantalla")
	if qr_remaining <= 0.0:
		return _fail("qr_expired", "El código caducó; escanea el nuevo")
	qr_code = ""
	qr_remaining = 0.0
	return _succeed(METHOD_QR, mobile_account if mobile_account != "" else str(account.get("title", "Tu cuenta")))


func login_with_credentials(email: String, password: String) -> Dictionary:
	if is_locked():
		return _fail("locked", "Demasiados intentos. Espera %d s" % ceili(lockout_remaining), false)
	var e := email.strip_edges()
	var re := RegEx.new()
	re.compile("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$")
	if re.search(e) == null:
		return _fail("invalid_email", "Escribe un correo válido", false)
	if password.length() < 8:
		return _fail("short_password", "La contraseña tiene al menos 8 caracteres", false)
	for a in login_cfg.get("demo_accounts", []):
		if str(a.get("email", "")).to_lower() == e.to_lower() and str(a.get("password", "")) == password:
			return _succeed(METHOD_CREDENTIALS, str(a.get("account", e)))
	failed_attempts += 1
	var max_f := int(login_cfg.get("max_failed_attempts", 5))
	if failed_attempts >= max_f:
		lockout_remaining = float(login_cfg.get("lockout_s", 30))
		return _fail("locked", "Demasiados intentos. Espera %d s" % ceili(lockout_remaining))
	return _fail("bad_credentials", "Correo o contraseña incorrectos · %d %s" % [max_f - failed_attempts, "intento restante" if max_f - failed_attempts == 1 else "intentos restantes"])


func _succeed(method: String, who: String) -> Dictionary:
	logged_in = true
	auth_method = method
	account_name = who
	failed_attempts = 0
	lockout_remaining = 0.0
	last_login_error = {}
	if keep_session:
		save_session()
	session_changed.emit(true)
	announce("Sesión iniciada")
	go_to(SCREEN_SELECT)
	return {"ok": true, "method": method, "account": who}


func _fail(code: String, message: String, _counted: bool = true) -> Dictionary:
	last_login_error = {"code": code, "message": message}
	login_failed.emit(code, message)
	announce(message)
	return {"ok": false, "code": code, "message": message}


func set_keep_session(on: bool) -> void:
	keep_session = on
	if logged_in:
		if on:
			save_session()
		else:
			_erase_session()
	session_changed.emit(logged_in)


func logout(forget: bool = true) -> void:
	logged_in = false
	auth_method = ""
	account_name = ""
	if forget:
		_erase_session()
	session_changed.emit(false)
	go_to(SCREEN_LOGIN)


func select_realm(id: String) -> bool:
	if server(id).is_empty():
		return false
	selected_realm = id
	session_changed.emit(logged_in)
	return true


func realm() -> Dictionary:
	return server(selected_realm)


func realm_line() -> String:
	var s := realm()
	if s.is_empty():
		return ""
	if str(s.get("status", "")) == "queue":
		return "cola ~%d min" % int(s.get("queue_min", 0))
	return "%d ms · sin cola" % int(s["ping_ms"])


func realm_header() -> String:
	var s := realm()
	if s.is_empty():
		return ""
	return "Reino %s · %s · %d ms · población %s" % [s["name"], s.get("language", "Español"), int(s["ping_ms"]), s.get("population", "media")]


func footer_status_text() -> String:
	var any_bad := false
	for s in servers:
		if ["maintenance", "down"].has(str(s.get("status", ""))):
			any_bad = true
	return "%s · %s" % ["Algunos servidores con incidencias" if any_bad else "Servidores estables", version]


# --- Persistencia --------------------------------------------------------------
func save_session() -> void:
	var cf := ConfigFile.new()
	cf.load(session_path)
	cf.set_value("session", "account", account_name)
	cf.set_value("session", "method", auth_method)
	cf.set_value("session", "realm", selected_realm)
	cf.save(session_path)


func _erase_session() -> void:
	var cf := ConfigFile.new()
	if cf.load(session_path) == OK and cf.has_section("session"):
		cf.erase_section("session")
		cf.save(session_path)


func has_saved_session() -> bool:
	var cf := ConfigFile.new()
	return cf.load(session_path) == OK and cf.has_section_key("session", "account")


func restore_session() -> bool:
	var cf := ConfigFile.new()
	if cf.load(session_path) != OK or not cf.has_section_key("session", "account"):
		return false
	logged_in = true
	auth_method = METHOD_SESSION
	account_name = str(cf.get_value("session", "account", ""))
	var r := str(cf.get_value("session", "realm", selected_realm))
	if not server(r).is_empty():
		selected_realm = r
	session_changed.emit(true)
	return true


func save_preferences() -> void:
	var cf := ConfigFile.new()
	cf.load(session_path)
	cf.set_value("accessibility", "font_step", font_step)
	cf.set_value("accessibility", "high_contrast", high_contrast)
	cf.set_value("accessibility", "narrator", narrator)
	cf.set_value("accessibility", "colorblind", colorblind_mode)
	cf.set_value("accessibility", "keep_session", keep_session)
	cf.save(session_path)


func load_preferences() -> bool:
	var cf := ConfigFile.new()
	if cf.load(session_path) != OK or not cf.has_section("accessibility"):
		return false
	font_step = clampi(int(cf.get_value("accessibility", "font_step", 1)), 0, FONT_STEPS.size() - 1)
	high_contrast = bool(cf.get_value("accessibility", "high_contrast", false))
	narrator = bool(cf.get_value("accessibility", "narrator", false))
	var cb := str(cf.get_value("accessibility", "colorblind", "none"))
	colorblind_mode = cb if COLORBLIND_MODES.has(cb) else "none"
	keep_session = bool(cf.get_value("accessibility", "keep_session", true))
	accessibility_changed.emit()
	return true


# ==========================================================================
# Accesibilidad previa al ingreso
# ==========================================================================
func font_scale() -> float:
	return float(FONT_STEPS[font_step])


func set_font_step(step: int) -> bool:
	var s := clampi(step, 0, FONT_STEPS.size() - 1)
	if s == font_step:
		return false
	font_step = s
	_accessibility_updated("Tamaño de letra %s" % FONT_STEP_LABELS[s])
	return true


func font_smaller() -> bool:
	return set_font_step(font_step - 1)


func font_larger() -> bool:
	return set_font_step(font_step + 1)


func set_high_contrast(on: bool) -> void:
	if high_contrast == on:
		return
	high_contrast = on
	_accessibility_updated("Alto contraste %s" % ("activado" if on else "desactivado"))


func toggle_high_contrast() -> bool:
	set_high_contrast(not high_contrast)
	return high_contrast


func set_narrator(on: bool) -> void:
	if narrator == on:
		return
	if not on:
		_say("Narrador desactivado")
	narrator = on
	_accessibility_updated("Narrador activado" if on else "")


func toggle_narrator() -> bool:
	set_narrator(not narrator)
	return narrator


func set_colorblind_mode(mode: String) -> bool:
	if not COLORBLIND_MODES.has(mode):
		return false
	if mode != colorblind_mode:
		colorblind_mode = mode
		_accessibility_updated("Modo de color: %s" % colorblind_label())
	return true


func cycle_colorblind_mode() -> String:
	var i := COLORBLIND_MODES.find(colorblind_mode)
	set_colorblind_mode(COLORBLIND_MODES[(i + 1) % COLORBLIND_MODES.size()])
	return colorblind_mode


func colorblind_label() -> String:
	return str(COLORBLIND_LABELS.get(colorblind_mode, "Daltonismo"))


## Alfa del velo sobre el fondo (más opaco con alto contraste).
func veil_alpha(base: float) -> float:
	return minf(0.94, base + 0.2) if high_contrast else base


func secondary_text_color() -> String:
	return TEXT if high_contrast else NEUTRAL


func _accessibility_updated(message: String) -> void:
	save_preferences()
	accessibility_changed.emit()
	if message != "":
		announce(message)


## El narrador lee `text` (si está activo). Guarda las últimas 30 locuciones.
func announce(text: String) -> bool:
	if not narrator or text == "":
		return false
	_say(text)
	return true


func _say(text: String) -> void:
	announcements.append(text)
	if announcements.size() > 30:
		announcements.remove_at(0)
	narrated.emit(text)
	if tts_enabled and DisplayServer.get_name() != "headless" and DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH):
		var voices := DisplayServer.tts_get_voices_for_language("es")
		if not voices.is_empty():
			DisplayServer.tts_speak(text, voices[0])


# ==========================================================================
# Selección de personaje
# ==========================================================================
func _sort_characters() -> void:
	characters.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if bool(a["special"]) != bool(b["special"]):
			return not bool(a["special"])
		return int(a["last_played_days"]) < int(b["last_played_days"]))


func character(id: String) -> Dictionary:
	for c in characters:
		if str(c["id"]) == id:
			return c
	return {}


func selected_character() -> Dictionary:
	return character(selected_character_id)


func first_playable() -> Dictionary:
	return characters[0] if not characters.is_empty() else {}


func used_slots() -> int:
	return characters.size()


func free_slots() -> int:
	return maxi(0, max_slots - used_slots())


func free_slots_text() -> String:
	var f := free_slots()
	if f == 0:
		return "sin espacios libres"
	return "%d %s" % [f, "espacio libre" if f == 1 else "espacios libres"]


func select_character(id: String) -> bool:
	if character(id).is_empty():
		return false
	if selected_character_id != id:
		selected_character_id = id
		character_selected.emit(id)
		var c := character(id)
		announce("%s, %s" % [c["name"], character_detail_line(c)])
	return true


## Carrusel: ±1 sobre la lista (circular).
func select_offset(step: int) -> bool:
	if characters.is_empty():
		return false
	var i := index_of(selected_character_id)
	var n := characters.size()
	return select_character(str(characters[posmod(i + step, n)]["id"]))


func index_of(id: String) -> int:
	for i in characters.size():
		if str(characters[i]["id"]) == id:
			return i
	return -1


func class_data(class_id: String) -> Dictionary:
	for c in classes:
		if str(c["id"]) == class_id:
			return c
	for c in special_classes:
		if str(c["id"]) == class_id:
			return c
	return {}


func origin(id: String) -> Dictionary:
	for o in origins:
		if str(o["id"]) == id:
			return o
	return {}


func trait_data(id: String) -> Dictionary:
	for t in traits:
		if str(t["id"]) == id:
			return t
	return {}


func role_label(role: String) -> String:
	return str((roles.get(role, {}) as Dictionary).get("label", role.capitalize()))


func role_color(role: String) -> String:
	return str((roles.get(role, {}) as Dictionary).get("color", "#18242b"))


func class_display_name(c: Dictionary) -> String:
	return str(class_data(str(c.get("class_id", ""))).get("name", "—"))


func last_played_text(days: int) -> String:
	if days <= 0:
		return "hoy"
	if days == 1:
		return "ayer"
	if days < 7:
		return "hace %d días" % days
	if days < 30:
		var w := days / 7
		return "hace 1 semana" if w == 1 else "hace %d semanas" % w
	var m := days / 30
	return "hace 1 mes" if m == 1 else "hace %d meses" % m


func character_subtitle(c: Dictionary) -> String:
	if bool(c["special"]):
		return "%s · personaje especial" % c.get("special_template", class_display_name(c))
	return class_display_name(c)


func character_meta_line(c: Dictionary) -> String:
	if bool(c["special"]):
		return "Asignado por el equipo · %d %s" % [int(c["special_days_left"]), "día" if int(c["special_days_left"]) == 1 else "días"]
	return "%s · %s" % [origin(str(c["origin"])).get("name", "—"), last_played_text(int(c["last_played_days"]))]


func character_color(c: Dictionary) -> String:
	if bool(c["special"]):
		return SPECIAL
	return str(origin(str(c["origin"])).get("color", NEUTRAL))


func character_level_text(c: Dictionary) -> String:
	return "" if bool(c["special"]) else str(int(c["level"]))


func character_detail_line(c: Dictionary) -> String:
	if bool(c["special"]):
		return "%s · %d días restantes" % [character_subtitle(c), int(c["special_days_left"])]
	return "%s · nivel %d · nivel de objeto %d" % [class_display_name(c), int(c["level"]), int(c["ilvl"])]


## Estadísticas básicas del personaje seleccionado: [{label, value}].
func character_stats_rows(c: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if c.is_empty():
		return out
	if bool(c["special"]):
		out.append({"label": "Plantilla", "value": str(c.get("special_template", "Especial"))})
		out.append({"label": "Duración", "value": "%d días" % int(c["special_days_left"])})
		out.append({"label": "Daño", "value": "no hace daño"})
		return out
	out.append({"label": "Nivel", "value": str(int(c["level"]))})
	out.append({"label": "Nivel de objeto", "value": str(int(c["ilvl"]))})
	var labels := {"vida": "Vida", "poder": "Poder", "defensa": "Defensa"}
	for k in ["vida", "poder", "defensa"]:
		if (c["stats"] as Dictionary).has(k):
			out.append({"label": labels[k], "value": fmt_int(int(c["stats"][k]))})
	return out


func continue_info(c: Dictionary = {}) -> Dictionary:
	var ch := c if not c.is_empty() else selected_character()
	return (ch.get("continue", {}) as Dictionary)


# --- Borrado con nombre tecleado ----------------------------------------------
func can_delete(id: String) -> bool:
	var c := character(id)
	return not c.is_empty() and not bool(c["special"])


func request_delete(id: String = "") -> Dictionary:
	var key := id if id != "" else selected_character_id
	var c := character(key)
	if c.is_empty():
		return {"ok": false, "code": "not_found", "message": "Ese personaje no existe"}
	if bool(c["special"]):
		return {"ok": false, "code": "special", "message": "Los personajes especiales los retira el equipo"}
	pending_delete_id = key
	return {"ok": true, "name": c["name"], "prompt": "ESCRIBE EL NOMBRE PARA CONFIRMAR"}


func delete_confirm_matches(typed: String) -> bool:
	var c := character(pending_delete_id)
	return not c.is_empty() and typed.strip_edges() == str(c["name"])


func cancel_delete() -> void:
	pending_delete_id = ""


func confirm_delete(typed: String) -> Dictionary:
	if pending_delete_id == "":
		return {"ok": false, "code": "no_request", "message": "Elige primero qué personaje borrar"}
	if not delete_confirm_matches(typed):
		return {"ok": false, "code": "name_mismatch", "message": "El nombre no coincide"}
	var id := pending_delete_id
	var i := index_of(id)
	var name_deleted := str(characters[i]["name"])
	characters.remove_at(i)
	pending_delete_id = ""
	if selected_character_id == id:
		selected_character_id = ""
		if not characters.is_empty():
			selected_character_id = str(characters[mini(i, characters.size() - 1)]["id"])
	character_deleted.emit(id)
	characters_changed.emit()
	announce("%s borrado" % name_deleted)
	return {"ok": true, "id": id}


# --- Entrar al mundo --------------------------------------------------------------
func enter_world() -> Dictionary:
	if not logged_in:
		return {"ok": false, "code": "not_logged_in"}
	var c := selected_character()
	if c.is_empty():
		return {"ok": false, "code": "no_character"}
	c["last_played_days"] = 0
	var cont := continue_info(c)
	var dest := begin_loading({"destination_id": str(cont.get("destination", "")), "character": c})
	if sync_auth_manager:
		var am := _auth_manager()
		if am != null:
			am.selected_character_id = str(c["id"])
			am.selected_character_name = str(c["name"])
	last_world_entry = {"character": c.duplicate(true), "destination": dest.duplicate(true)}
	world_entry_requested.emit(c, dest)
	return {"ok": true, "character": c, "destination": dest}


func _auth_manager() -> Node:
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		return (ml as SceneTree).root.get_node_or_null("AuthManager")
	return null


# ==========================================================================
# Creación de personaje (4 pasos)
# ==========================================================================
func default_appearance() -> Dictionary:
	return {"body": 1, "hair_style": 0, "hair_color": 0, "eye_color": 0, "outfit": 0}


func _reset_draft() -> void:
	draft = {"origin": str(origins[0]["id"]) if not origins.is_empty() else "", "class_id": "", "appearance": default_appearance(), "name": "", "trait_id": ""}
	creation_step = 0
	max_step_reached = 0


func begin_creation() -> Dictionary:
	if free_slots() <= 0:
		return {"ok": false, "code": "no_slots", "message": "No te quedan espacios libres"}
	_reset_draft()
	end_trial()
	go_to(SCREEN_CREATE)
	creation_changed.emit()
	announce("Creación de personaje. Paso 1 de 4: Origen")
	return {"ok": true}


func cancel_creation() -> void:
	end_trial()
	_reset_draft()
	go_to(SCREEN_SELECT)
	creation_changed.emit()


func set_origin(id: String) -> bool:
	if origin(id).is_empty():
		return false
	draft["origin"] = id
	creation_changed.emit()
	return true


func set_class(class_id: String) -> bool:
	var found := false
	for c in classes:
		if str(c["id"]) == class_id:
			found = true
	if not found:
		return false
	draft["class_id"] = class_id
	creation_changed.emit()
	return true


func recommended_class_id() -> String:
	for c in classes:
		if bool(c.get("recommended", false)):
			return str(c["id"])
	return ""


func appearance_count(key: String) -> int:
	return ((appearance_options.get(key, {}) as Dictionary).get("options", []) as Array).size()


func appearance_label(key: String) -> String:
	return str((appearance_options.get(key, {}) as Dictionary).get("label", key))


func appearance_option(key: String, index: int = -1) -> Dictionary:
	var opts: Array = (appearance_options.get(key, {}) as Dictionary).get("options", [])
	var i := index if index >= 0 else int(draft["appearance"].get(key, 0))
	if opts.is_empty():
		return {}
	return opts[clampi(i, 0, opts.size() - 1)]


func set_appearance(key: String, index: int) -> bool:
	var n := appearance_count(key)
	if n == 0 or index < 0 or index >= n:
		return false
	draft["appearance"][key] = index
	creation_changed.emit()
	return true


func cycle_appearance(key: String, step: int) -> int:
	var n := appearance_count(key)
	if n == 0:
		return -1
	var i := posmod(int(draft["appearance"].get(key, 0)) + step, n)
	set_appearance(key, i)
	return i


func randomize_appearance(rng_seed: int = 0) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed if rng_seed != 0 else Time.get_ticks_usec()
	for k in APPEARANCE_KEYS:
		var n := appearance_count(k)
		if n > 0:
			draft["appearance"][k] = rng.randi_range(0, n - 1)
	creation_changed.emit()
	return draft["appearance"]


## Colores efectivos del chibi: {body, hair, eyes, scale} (el atuendo vacío usa el color de la clase).
func appearance_colors(app: Dictionary = {}, class_id: String = "") -> Dictionary:
	var a := app if not app.is_empty() else (draft["appearance"] as Dictionary)
	var cid := class_id if class_id != "" else str(draft.get("class_id", ""))
	var outfit := str(appearance_option("outfit", int(a.get("outfit", 0))).get("color", ""))
	var body := outfit if outfit != "" else str(class_data(cid).get("body_color", "#2b4a8a"))
	return {
		"body": body,
		"hair": str(appearance_option("hair_color", int(a.get("hair_color", 0))).get("color", "#2b1d14")),
		"eyes": str(appearance_option("eye_color", int(a.get("eye_color", 0))).get("color", "#1a1a1a")),
		"scale": float(appearance_option("body", int(a.get("body", 1))).get("value", 1.0)),
		"hair_style": int(a.get("hair_style", 0)),
	}


func set_draft_name(n: String) -> Dictionary:
	draft["name"] = n
	creation_changed.emit()
	return validate_name(n)


func set_trait(id: String) -> bool:
	if trait_data(id).is_empty():
		return false
	draft["trait_id"] = id
	creation_changed.emit()
	return true


# --- Validación de nombre ---------------------------------------------------------
static func _fold(s: String) -> String:
	var out := s.to_lower()
	var from := "áéíóúüñ"
	var to := "aeiouun"
	for i in from.length():
		out = out.replace(from[i], to[i])
	return out


static func _deleet(s: String) -> String:
	var out := ""
	for ch in s:
		out += str(LEET.get(ch, ch))
	return out


static func _is_name_char(ch: String) -> bool:
	var u := ch.unicode_at(0)
	return (u >= 48 and u <= 57) or (u >= 65 and u <= 90) or (u >= 97 and u <= 122) or NAME_ACCENTED.contains(ch)


func validate_name(raw: String) -> Dictionary:
	var n := raw.strip_edges()
	var mn := int(name_rules.get("min", 3))
	var mx := int(name_rules.get("max", 16))
	var code := "ok"
	if n == "":
		code = "empty"
	elif n.length() < mn:
		code = "too_short"
	elif n.length() > mx:
		code = "too_long"
	else:
		for ch in n:
			if not _is_name_char(ch):
				code = "invalid_chars"
				break
		if code == "ok" and n.unicode_at(0) >= 48 and n.unicode_at(0) <= 57:
			code = "starts_with_digit"
		if code == "ok":
			var folded := _deleet(_fold(n))
			for w in name_rules.get("profanity", []):
				if folded.contains(_fold(str(w))):
					code = "profanity"
					break
		if code == "ok":
			for w in name_rules.get("reserved", []):
				if _fold(n) == _fold(str(w)):
					code = "reserved"
					break
		if code == "ok" and not is_name_available(n):
			code = "taken"
	var msg := str(NAME_MESSAGES[code])
	if code == "too_short":
		msg = msg % mn
	elif code == "too_long":
		msg = msg % mx
	return {"ok": code == "ok", "code": code, "message": msg, "name": n}


## Disponibilidad «en el servidor»: nombres ocupados del seed + tus personajes (sin tildes ni mayúsculas).
func is_name_available(n: String) -> bool:
	var f := _fold(n.strip_edges())
	for t in name_rules.get("taken", []):
		if _fold(str(t)) == f:
			return false
	for c in characters:
		if _fold(str(c["name"])) == f:
			return false
	return true


func suggest_name(n: String) -> String:
	var base := n.strip_edges()
	var mx := int(name_rules.get("max", 16))
	for i in range(2, 100):
		var s := str(i)
		var cand := base.substr(0, mx - s.length()) + s
		if validate_name(cand)["ok"]:
			return cand
	return ""


# --- Pasos -------------------------------------------------------------------------
func step_valid(i: int) -> bool:
	match i:
		0:
			return not origin(str(draft["origin"])).is_empty()
		1:
			return str(draft["class_id"]) != ""
		2:
			return true
		3:
			return validate_name(str(draft["name"]))["ok"] and not trait_data(str(draft["trait_id"])).is_empty()
	return false


func can_advance() -> bool:
	return step_valid(creation_step)


func step_states() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in STEP_LABELS.size():
		var st := "pending"
		if i == creation_step:
			st = "active"
		elif i < creation_step or (i <= max_step_reached and step_valid(i)):
			st = "done"
		out.append({"index": i, "label": STEP_LABELS[i], "state": st})
	return out


func next_step() -> bool:
	if creation_step >= STEP_LABELS.size() - 1 or not can_advance():
		return false
	creation_step += 1
	max_step_reached = maxi(max_step_reached, creation_step)
	creation_changed.emit()
	announce("Paso %d de 4: %s" % [creation_step + 1, STEP_LABELS[creation_step]])
	return true


func prev_step() -> bool:
	if creation_step <= 0:
		return false
	creation_step -= 1
	creation_changed.emit()
	return true


func goto_step(i: int) -> bool:
	if i < 0 or i >= STEP_LABELS.size() or i > max_step_reached:
		return false
	for k in i:
		if not step_valid(k):
			return false
	creation_step = i
	creation_changed.emit()
	return true


func primary_action_label() -> String:
	return str(STEP_NEXT_LABELS[creation_step])


func confirm_creation() -> Dictionary:
	if free_slots() <= 0:
		return {"ok": false, "code": "no_slots", "message": "No te quedan espacios libres"}
	for i in STEP_LABELS.size():
		if not step_valid(i):
			var v := validate_name(str(draft["name"]))
			var msg := "Completa el paso %d: %s" % [i + 1, STEP_LABELS[i]]
			if i == 3 and not v["ok"]:
				msg = str(v["message"])
			elif i == 3:
				msg = "Elige un rasgo cósmico"
			return {"ok": false, "code": "step_%d" % i, "message": msg}
	_created_counter += 1
	var n := str(validate_name(str(draft["name"]))["name"])
	var cls := class_data(str(draft["class_id"]))
	var o := origin(str(draft["origin"]))
	var r: Dictionary = cls.get("ratings", {})
	var c := {
		"id": "%s_%d" % [_fold(n), _created_counter],
		"name": n,
		"level": 1,
		"class_id": str(draft["class_id"]),
		"origin": str(draft["origin"]),
		"last_played_days": 0,
		"ilvl": 5,
		"special": false,
		"special_days_left": 0,
		"appearance": (draft["appearance"] as Dictionary).duplicate(),
		"trait_id": str(draft["trait_id"]),
		"stats": {"vida": 600 + 120 * int(r.get("survival", 1)), "poder": 40 + 12 * int(r.get("damage", 1)), "defensa": 20 + 10 * int(r.get("survival", 1))},
		"continue": {"title": "Primeros pasos en %s" % o.get("name", ""), "text": "%s · tu primer refugio te espera" % o.get("name", ""), "destination": str(o.get("start", loading_cfg.get("default_destination", "")))},
	}
	_normalize_character(c)
	characters.append(c)
	_sort_characters()
	selected_character_id = str(c["id"])
	end_trial()
	_reset_draft()
	character_created.emit(c)
	characters_changed.emit()
	go_to(SCREEN_SELECT)
	announce("%s creado" % n)
	return {"ok": true, "character": c}


# --- Maniquí (probar la clase 5 min) ---------------------------------------------
func trial_duration() -> float:
	return float(trial_cfg.get("duration_s", 300))


func try_dummy(class_id: String = "") -> Dictionary:
	var cid := class_id if class_id != "" else str(draft["class_id"])
	if class_data(cid).is_empty() or special_classes.any(func(s): return str(s["id"]) == cid):
		return {"ok": false, "code": "no_class", "message": "Elige primero una clase"}
	trial_active = true
	trial_class_id = cid
	trial_remaining = trial_duration()
	trial_started.emit(cid)
	creation_changed.emit()
	return {"ok": true, "class_id": cid, "duration_s": trial_duration(), "arena": str(trial_cfg.get("arena", "Arena del maniquí"))}


func end_trial() -> void:
	if not trial_active:
		return
	var cid := trial_class_id
	trial_active = false
	trial_remaining = 0.0
	trial_class_id = ""
	trial_finished.emit(cid)
	creation_changed.emit()


func trial_button_text() -> String:
	if trial_active:
		return "En el maniquí · %s" % fmt_clock(trial_remaining)
	return "Probar en el maniquí (%d min)" % roundi(trial_duration() / 60.0)


# ==========================================================================
# Pantalla de carga táctica
# ==========================================================================
## dest: {"destination_id"} y/o campos que sobrescriben los del seed (name, universe, objective,
## quote, quote_source, tips, activities, party_inside, party_size, duration_s, character).
func begin_loading(dest: Dictionary = {}) -> Dictionary:
	var dests: Dictionary = loading_cfg.get("destinations", {})
	var id := str(dest.get("destination_id", ""))
	if id == "" or not dests.has(id):
		id = str(loading_cfg.get("default_destination", ""))
	var d: Dictionary = (dests.get(id, {}) as Dictionary).duplicate(true)
	for k in dest:
		if k != "character":
			d[k] = dest[k]
	d["destination_id"] = id
	loading_character = (dest.get("character", selected_character()) as Dictionary)
	loading_destination = d
	loading_progress = 0.0
	loading_active = true
	go_to(SCREEN_LOADING)
	loading_progressed.emit(0.0)
	announce("Viajando a %s" % d.get("name", ""))
	return d


func set_loading_progress(p: float) -> void:
	if loading_destination.is_empty():
		return
	var was := loading_progress
	loading_progress = clampf(p, 0.0, 1.0)
	if loading_progress != was:
		loading_progressed.emit(loading_progress)
	if loading_progress >= 1.0 and loading_active:
		loading_active = false
		go_to(SCREEN_WORLD)
		loading_finished.emit(loading_destination)


func loading_percent() -> int:
	return floori(loading_progress * 100.0 + 0.0001)


func loading_remaining_s() -> int:
	return ceili((1.0 - loading_progress) * float(loading_destination.get("duration_s", 10.0)) - 0.0001)


func loading_eta_text() -> String:
	if loading_progress >= 1.0:
		return "100 % · listo"
	var s := loading_remaining_s()
	return "%d %% · %s" % [loading_percent(), "casi listo" if s <= 1 else "unos %d s" % s]


func loading_stage_text() -> String:
	if loading_progress >= 1.0:
		return "Listo · entrando en %s" % loading_destination.get("name", "")
	var text := ""
	for st in loading_cfg.get("stages", []):
		text = str(st.get("text", ""))
		if loading_progress < float(st.get("until", 1.0)):
			break
	return text.format({
		"realm": realm().get("name", ""),
		"character": loading_character.get("name", "tu personaje"),
		"universe": loading_destination.get("universe", ""),
		"destination": loading_destination.get("name", ""),
	})


func loading_subtitle() -> String:
	return "%s · tu objetivo: %s" % [loading_destination.get("universe", ""), loading_destination.get("objective", "")]


## Siempre 3 consejos: los del destino y, si faltan, los generales.
func loading_tips() -> Array[Dictionary]:
	var out := _dicts(loading_destination.get("tips", []))
	for t in _dicts(loading_cfg.get("general_tips", [])):
		if out.size() >= 3:
			break
		out.append(t)
	return out.slice(0, 3)


## Chips «Mientras carga»: atajos útiles + estado del grupo («Tu grupo: 3/5 ya dentro»).
func loading_activities() -> Array[Dictionary]:
	var out := _dicts(loading_destination.get("activities", []))
	var size := int(loading_destination.get("party_size", 1))
	if size > 1:
		out.append({"text": "Tu grupo:", "value": "%d/%d" % [int(loading_destination.get("party_inside", 0)), size], "suffix": "ya dentro", "party": true})
	return out


func set_party_inside(n: int) -> void:
	loading_destination["party_inside"] = clampi(n, 0, int(loading_destination.get("party_size", 1)))
	loading_progressed.emit(loading_progress)


# ==========================================================================
# Formato
# ==========================================================================
## 18.4 → «18,4» · 42.0 → «42».
static func fmt_dec(v: float) -> String:
	var r := snappedf(v, 0.1)
	if is_equal_approx(r, roundf(r)):
		return str(int(roundf(r)))
	return ("%.1f" % r).replace(".", ",")


## 4820 → «4.820».
static func fmt_int(v: int) -> String:
	var s := str(absi(v))
	var out := ""
	while s.length() > 3:
		out = "." + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if v < 0 else "") + s + out


static func fmt_clock(seconds: float) -> String:
	var s := maxi(0, ceili(seconds))
	return "%d:%02d" % [s / 60, s % 60]
