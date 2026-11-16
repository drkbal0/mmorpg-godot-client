extends "res://ui/windows/common/EntryWindow.gd"
## Launcher — UI v2.4 Paso 15 (design_ref/pantallas_html/MMO-Launcher.html).
##
## - Lienzo 1440×810: barra de ventana simulada «[NOMBRE DEL JUEGO] Launcher» con – □ ×.
## - Barra lateral (230 px): Inicio · Novedades · Notas del parche · Instalación · Soporte, tarjeta
##   de cuenta («Llave de acceso activa», amigos jugando) con botón de amigos, versión y
##   «Comprobar integridad».
## - Portada (330 px) con degradado cinemático: «Temporada 1 · ya disponible», «La Brecha de Ferrum».
## - 3 tarjetas (1,3 · 1 · 1): «Qué cambia para ti» (viñetas #4fe39a / #f5c35b / #9aa6ae),
##   «Servidores» (ping, cola, mantenimiento) y «Amigos» (avatar con aro de estado).
## - Pie (120 px): instalación progresiva por paquetes, «Pausar · Limitar mientras juego» y
##   «Jugar ahora» (#46e3c1): con lo imprescindible ya se puede jugar.
##
## Teclado: Enter juega · 1-5 cambian de pestaña · Ctrl+Alt+N narrador.

signal play_requested(screen: String)
signal patch_notes_requested(url: String)
signal window_action(action: String)

const KEY_ICON := "M4 12a4 4 0 1 0 8 0a4 4 0 1 0-8 0M12 12h9M18 12v3M21 12v2"

var titlebar: PanelContainer
var sidebar: PanelContainer
var tab_buttons: Dictionary = {}
var account_card: PanelContainer
var friends_button: Button
var version_label: Label
var integrity_button: Button
var integrity_label: Label
var cover: Control
var season_caps: Label
var season_title: Label
var season_text: Label
var cards_row: HBoxContainer
var changes_card: PanelContainer
var servers_card: PanelContainer
var friends_card: PanelContainer
var tab_panel: PanelContainer
var footer: PanelContainer
var download_label: Label
var pause_button: Button
var limit_button: Button
var install_bar: EK.SegmentedBar
var pack_labels: HBoxContainer
var play_button: Button
var play_hint: Label
var last_window_action := ""
var friends_highlight := false

var _last_dynamic := ""


func _screen_id() -> String:
	return "launcher"


func _screen() -> String:
	return AuthScript.SCREEN_LAUNCHER


func _use_scene_background() -> bool:
	return false


func _screen_title() -> String:
	return "Launcher. %s" % service.season.get("title", "")


func _service_signals() -> Array:
	return ["launcher_changed"]


func _process(_delta: float) -> void:
	if _built and visible:
		_refresh_dynamic()


# ==========================================================================
# API
# ==========================================================================
func play() -> Dictionary:
	var r: Dictionary = service.play()
	if r.get("ok", false):
		play_requested.emit(str(r["screen"]))
		navigate(str(r["screen"]))
	return r


func select_tab(id: String) -> bool:
	return service.set_launcher_tab(id)


func open_patch_notes() -> void:
	service.set_launcher_tab("patch_notes")
	patch_notes_requested.emit(service.patch_notes_url)


func verify_integrity() -> Dictionary:
	return service.verify_integrity()


func toggle_friends() -> void:
	friends_highlight = not friends_highlight
	_style_friends_card()


## Controles simulados de la barra de ventana: minimize · maximize · close.
func window_control(action: String) -> void:
	last_window_action = action
	window_action.emit(action)
	if action == "close":
		navigate("")


func _handle_key(code: int, _ev: InputEventKey) -> bool:
	match code:
		KEY_ENTER, KEY_KP_ENTER:
			play()
			return true
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
			var i := code - KEY_1
			if i < service.launcher_tabs.size():
				select_tab(str(service.launcher_tabs[i]["id"]))
			return true
	return false


# ==========================================================================
# Construcción
# ==========================================================================
func _build() -> void:
	_build_titlebar()
	_build_sidebar()
	_build_cover()
	_build_cards()
	_build_footer()


func _build_titlebar() -> void:
	titlebar = Kit.panel("TitleBar", Kit.box(T.LAUNCHER_TITLEBAR_BG, 0), 14, 0)
	titlebar.position = Vector2.ZERO
	titlebar.size = Vector2(T.CINEMA_DESIGN_SIZE.x, T.LAUNCHER_TITLEBAR_HEIGHT)
	titlebar.custom_minimum_size = titlebar.size
	stage.add_child(titlebar)
	var h := EK.hbox("Row", 10)
	titlebar.add_child(h)
	var name_l := Kit.label(service.game_name, 13, T.ACCENT_DEFAULT, "bold")
	name_l.name = "GameName"
	var fv := FontVariation.new()
	fv.base_font = T.font("bold")
	fv.spacing_glyph = 3
	name_l.add_theme_font_override("font", fv)
	name_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(name_l)
	var sub := Kit.label("Launcher", 13, T.TEXT_SECONDARY)
	sub.name = "Subtitle"
	sub.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(sub)
	h.add_child(EK.spacer())
	var ctr := EK.hbox("Controls", 18)
	h.add_child(ctr)
	for d in [["Minimize", "–", "minimize"], ["Maximize", "□", "maximize"], ["Close", "×", "close"]]:
		var b := EK.link(d[0], d[1], 16, T.TEXT_MUTED)
		b.custom_minimum_size = Vector2(16, 36)
		var act: String = d[2]
		b.pressed.connect(func() -> void: window_control(act))
		ctr.add_child(b)


func _build_sidebar() -> void:
	sidebar = Kit.panel("Sidebar", Kit.box(T.LAUNCHER_SIDEBAR_BG, 0, 0), 14, 18)
	sidebar.position = Vector2(0, T.LAUNCHER_TITLEBAR_HEIGHT)
	sidebar.size = Vector2(T.LAUNCHER_SIDEBAR_WIDTH, T.CINEMA_DESIGN_SIZE.y - T.LAUNCHER_TITLEBAR_HEIGHT)
	sidebar.custom_minimum_size = sidebar.size
	stage.add_child(sidebar)
	var edge := ColorRect.new()
	edge.name = "Edge"
	edge.color = Color(1, 1, 1, 0.06)
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	edge.position = Vector2(T.LAUNCHER_SIDEBAR_WIDTH - 1, T.LAUNCHER_TITLEBAR_HEIGHT)
	edge.size = Vector2(1, sidebar.size.y)
	stage.add_child(edge)
	var v := EK.vbox("Body", 4)
	sidebar.add_child(v)
	tab_buttons.clear()
	for t in service.launcher_tabs:
		var b := Button.new()
		b.name = "Tab_%s" % t["id"]
		b.text = str(t["label"])
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 38)
		b.focus_mode = Control.FOCUS_ALL
		b.add_theme_font_override("font", T.font("semibold"))
		b.add_theme_font_size_override("font_size", 15)
		var id := str(t["id"])
		b.pressed.connect(func() -> void: select_tab(id))
		v.add_child(b)
		tab_buttons[id] = b
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(sp)
	account_card = Kit.panel("Account", Kit.box(T.ENTRY_SUB_BG, 12), 12)
	v.add_child(account_card)
	var av := EK.vbox("Body", 6)
	account_card.add_child(av)
	var row := EK.hbox("Head", 10)
	av.add_child(row)
	var avatar := EK.Avatar.new(34, T.ENTRY_AVATAR_BG)
	avatar.name = "Avatar"
	row.add_child(avatar)
	var nv := EK.vbox("Names", 0)
	nv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(nv)
	var an := Kit.label("", 14, T.TEXT, "bold")
	an.name = "Title"
	nv.add_child(an)
	var ast := Kit.label("", 12, T.ENTRY_STEP_DONE)
	ast.name = "Status"
	nv.add_child(ast)
	friends_button = EK.link("FriendsButton", "", 12, T.TEXT_SECONDARY)
	friends_button.tooltip_text = "Ver amigos"
	friends_button.pressed.connect(toggle_friends)
	av.add_child(friends_button)
	var ver := EK.hbox("Version", 6)
	v.add_child(ver)
	version_label = Kit.label("", 12, T.TEXT_MUTED)
	version_label.name = "VersionLabel"
	ver.add_child(version_label)
	integrity_button = EK.link("Integrity", "Comprobar integridad", 12)
	integrity_button.pressed.connect(verify_integrity)
	ver.add_child(integrity_button)
	integrity_label = Kit.label("", 11, T.TEXT_SECONDARY)
	integrity_label.name = "IntegrityResult"
	integrity_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(integrity_label)


func _build_cover() -> void:
	var x := T.LAUNCHER_SIDEBAR_WIDTH
	var w := T.CINEMA_DESIGN_SIZE.x - x
	cover = Control.new()
	cover.name = "Cover"
	cover.clip_contents = true
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cover.position = Vector2(x, T.LAUNCHER_TITLEBAR_HEIGHT)
	cover.size = Vector2(w, T.LAUNCHER_COVER_HEIGHT)
	stage.add_child(cover)
	var img := EK.scene_rect("Art")
	img.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cover.add_child(img)
	var bg := T.LAUNCHER_BG
	var grad := EK.vgradient("Gradient", [[0.0, Color(bg, 0.1)], [0.5, Color(bg, 0.4)], [1.0, bg]])
	grad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cover.add_child(grad)
	var v := EK.vbox("Text", 8)
	cover.add_child(v)
	v.anchor_top = 1.0
	v.anchor_bottom = 1.0
	v.offset_left = 40
	v.offset_bottom = -34
	v.offset_top = -34
	v.grow_vertical = Control.GROW_DIRECTION_BEGIN
	season_caps = Kit.caps("", T.ACCENT_DEFAULT)
	season_caps.name = "Caps"
	v.add_child(season_caps)
	season_title = Kit.shadow(Kit.label("", T.LAUNCHER_TITLE_SIZE, T.TEXT, "bold"))
	season_title.name = "SeasonTitle"
	v.add_child(season_title)
	season_text = Kit.shadow(Kit.label("", 16, T.ENTRY_TEXT_SOFT))
	season_text.name = "SeasonText"
	v.add_child(season_text)


func _build_cards() -> void:
	cards_row = EK.hbox("Cards", 16)
	cards_row.position = Vector2(258, 386)
	cards_row.size = Vector2(T.CINEMA_DESIGN_SIZE.x - 258 - 28, 0)
	stage.add_child(cards_row)
	changes_card = _card_col("WhatChanges", 1.3)
	servers_card = _card_col("Servers", 1.0)
	friends_card = _card_col("Friends", 1.0)
	tab_panel = EK.card("TabPanel", 22)
	tab_panel.position = Vector2(258, 386)
	tab_panel.custom_minimum_size = Vector2(T.CINEMA_DESIGN_SIZE.x - 258 - 28, 260)
	tab_panel.visible = false
	tab_panel.add_child(EK.vbox("Body", 10))
	stage.add_child(tab_panel)


func _card_col(node_name: String, ratio: float) -> PanelContainer:
	var c := EK.card(node_name, 18)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.size_flags_stretch_ratio = ratio
	c.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	c.add_child(EK.vbox("Body", 10))
	cards_row.add_child(c)
	return c


func _build_footer() -> void:
	var x := T.LAUNCHER_SIDEBAR_WIDTH
	footer = Kit.panel("Footer", Kit.box(T.ENTRY_CARD_BG, 0), 28, 18)
	footer.position = Vector2(x, T.CINEMA_DESIGN_SIZE.y - T.LAUNCHER_FOOTER_HEIGHT)
	footer.size = Vector2(T.CINEMA_DESIGN_SIZE.x - x, T.LAUNCHER_FOOTER_HEIGHT)
	footer.custom_minimum_size = footer.size
	stage.add_child(footer)
	var top_edge := ColorRect.new()
	top_edge.name = "Edge"
	top_edge.color = Color(1, 1, 1, 0.07)
	top_edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_edge.position = footer.position
	top_edge.size = Vector2(footer.size.x, 1)
	stage.add_child(top_edge)
	var h := EK.hbox("Row", 28)
	footer.add_child(h)
	var left := EK.vbox("Install", 8)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(left)
	var line := EK.hbox("Line", 8)
	left.add_child(line)
	download_label = Kit.label("", 14, T.TEXT, "semibold")
	download_label.name = "Download"
	download_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(download_label)
	pause_button = EK.link("Pause", "Pausar", 14, T.TEXT_SECONDARY)
	pause_button.pressed.connect(func() -> void: service.toggle_install_pause())
	line.add_child(pause_button)
	var dotl := Kit.label("·", 14, T.TEXT_SECONDARY)
	line.add_child(dotl)
	limit_button = EK.link("Limit", "", 14, T.TEXT_SECONDARY)
	limit_button.pressed.connect(func() -> void: service.toggle_limit_while_playing())
	line.add_child(limit_button)
	install_bar = EK.SegmentedBar.new()
	install_bar.name = "InstallBar"
	left.add_child(install_bar)
	pack_labels = EK.hbox("Packs", 4)
	left.add_child(pack_labels)
	var right := EK.vbox("Play", 6)
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(right)
	play_button = EK.button("PlayButton", "Jugar ahora", T.LAUNCHER_PLAY_HEIGHT, 20, 48)
	EK.primary(play_button, 10, 48)
	play_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	play_button.pressed.connect(play)
	right.add_child(play_button)
	play_hint = Kit.label("", 12, T.TEXT_SECONDARY)
	play_hint.name = "PlayHint"
	play_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	right.add_child(play_hint)


# ==========================================================================
# Refresco
# ==========================================================================
func refresh() -> void:
	if not _built or service == null:
		return
	# Pestañas.
	for id in tab_buttons:
		var b: Button = tab_buttons[id]
		var on: bool = id == service.launcher_tab
		b.set_meta("active", on)
		for st in ["normal", "hover", "pressed", "focus"]:
			var bg := T.LAUNCHER_TAB_ACTIVE_BG if on else Color(0, 0, 0, 0)
			if st == "hover" and not on:
				bg = Color(1, 1, 1, 0.04)
			var sb := Kit.box(bg, 10)
			if st == "focus":
				sb = Kit.box(Color.TRANSPARENT, 10, 2, T.ACCENT_DEFAULT)
			sb.content_margin_left = 12
			sb.content_margin_right = 12
			b.add_theme_stylebox_override(st, sb)
		for fc in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			b.add_theme_color_override(fc, T.TEXT if on else T.TEXT_SECONDARY)
	# Cuenta.
	(account_card.find_child("Title", true, false) as Label).text = str(service.account.get("title", "Tu cuenta"))
	var st_l := account_card.find_child("Status", true, false) as Label
	st_l.text = service.account_status_text()
	st_l.add_theme_color_override("font_color", Color(service.status_color("good")))
	friends_button.text = service.friends_playing_text()
	version_label.text = service.version
	integrity_label.text = str(service.last_integrity.get("text", ""))
	integrity_label.visible = not service.last_integrity.is_empty()
	# Portada.
	season_caps.text = str(service.season.get("caps", "")).to_upper()
	season_title.text = str(service.season.get("title", ""))
	season_text.text = str(service.season.get("text", ""))
	# Contenido de la pestaña.
	var home: bool = service.launcher_tab == "home"
	cards_row.visible = home
	tab_panel.visible = not home
	if home:
		_rebuild_changes()
		_rebuild_servers()
		_rebuild_friends()
	else:
		_rebuild_tab_panel()
	_refresh_dynamic(true)
	apply_accessibility()


func _rebuild_changes() -> void:
	var v: VBoxContainer = changes_card.get_node("Body")
	Kit.clear(v)
	v.add_child(Kit.caps("Qué cambia para ti"))
	for i in service.changes.size():
		var c: Dictionary = service.changes[i]
		var row := EK.bullet_row("Change_%d" % i, Color(service.change_color(str(c["kind"]))), str(c["text"]), 14)
		row.set_meta("kind", c["kind"])
		v.add_child(row)
	var l := EK.link("PatchNotes", "Ver notas completas", 13)
	l.pressed.connect(open_patch_notes)
	v.add_child(l)


func _rebuild_servers() -> void:
	var v: VBoxContainer = servers_card.get_node("Body")
	Kit.clear(v)
	v.add_child(Kit.caps("Servidores"))
	for s in service.servers:
		var row := EK.hbox("Server_%s" % s["id"], 8)
		var d := EK.Dot.new(Color(service.server_color(s)), 8.0)
		d.name = "Dot"
		d.custom_minimum_size = Vector2(8, 19)
		row.add_child(d)
		var n := Kit.label(service.server_label(s), 14, T.TEXT)
		n.name = "Name"
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(n)
		var p := Kit.label(service.server_line(s), 14, T.TEXT_SECONDARY)
		p.name = "Ping"
		row.add_child(p)
		v.add_child(row)
	var m := Kit.label(service.maintenance, 12, T.TEXT_MUTED)
	m.name = "Maintenance"
	m.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(m)


func _rebuild_friends() -> void:
	var v: VBoxContainer = friends_card.get_node("Body")
	Kit.clear(v)
	v.add_child(Kit.caps("Amigos"))
	for f in service.friends:
		var row := EK.hbox("Friend_%s" % f["id"], 10)
		var av := EK.Avatar.new(28, Color(service.friend_color(f)))
		av.name = "Avatar"
		row.add_child(av)
		var nv := EK.vbox("Text", 0)
		nv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(nv)
		var n := Kit.label(str(f["name"]), 14, T.TEXT, "semibold")
		n.name = "Name"
		nv.add_child(n)
		var w := Kit.label(str(f["where"]), 12, T.TEXT_SECONDARY)
		w.name = "Where"
		nv.add_child(w)
		v.add_child(row)
	_style_friends_card()


func _style_friends_card() -> void:
	if friends_card == null:
		return
	var sb := Kit.box(T.ENTRY_CARD_BG, 18, 2.0 if friends_highlight else 1.0, T.ACCENT_DEFAULT if friends_highlight else T.ENTRY_CARD_EDGE)
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 24
	sb.shadow_offset = Vector2(0, 12)
	for k in ["left", "right", "top", "bottom"]:
		sb.set("content_margin_" + k, 18)
	friends_card.add_theme_stylebox_override("panel", sb)
	friends_card.set_meta("highlight", friends_highlight)


func _rebuild_tab_panel() -> void:
	var v: VBoxContainer = tab_panel.get_node("Body")
	Kit.clear(v)
	var tab: String = service.launcher_tab
	tab_panel.set_meta("tab", tab)
	var title := Kit.label(service.launcher_tab_label(), 22, T.TEXT, "bold")
	title.name = "Title"
	v.add_child(title)
	match tab:
		"news":
			v.add_child(Kit.caps(str(service.season.get("caps", ""))))
			var t := Kit.label("%s — %s" % [service.season.get("title", ""), service.season.get("text", "")], 15, T.TEXT_KEY)
			t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			v.add_child(t)
		"patch_notes":
			v.add_child(Kit.caps("Versión %s · qué cambia para ti" % service.version))
			for i in service.changes.size():
				var c: Dictionary = service.changes[i]
				v.add_child(EK.bullet_row("Change_%d" % i, Color(service.change_color(str(c["kind"]))), str(c["text"]), 15))
			var u := Kit.label(service.patch_notes_url, 13, T.ACCENT_DEFAULT)
			u.name = "Url"
			v.add_child(u)
		"install":
			v.add_child(Kit.caps("Paquetes"))
			for p in service.packs:
				var row := EK.hbox("Pack_%s" % p["id"], 12)
				var n := Kit.label(service.pack_label(p), 14, Color(service.pack_color(p)), "semibold")
				n.name = "Label"
				n.custom_minimum_size.x = 200
				row.add_child(n)
				var bar = Kit.Bar.new(8.0)
				bar.name = "Bar"
				bar.track = T.ENTRY_SUB_BG
				bar.fill = Color(service.pack_fill_color(p))
				bar.ratio = float(p["progress"])
				bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				row.add_child(bar)
				var req := Kit.label("imprescindible" if bool(p.get("required", false)) else "mientras juegas", 12, T.TEXT_MUTED)
				req.custom_minimum_size.x = 120
				row.add_child(req)
				v.add_child(row)
			var ib := EK.button("VerifyIntegrity", "Comprobar integridad")
			ib.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			ib.pressed.connect(verify_integrity)
			v.add_child(ib)
		_:
			for line in ["Centro de ayuda y estado de los servidores.", "Informa de un problema desde el juego con [F12]: se adjunta tu registro.", service.footer_status_text()]:
				var l := Kit.label(line, 15, T.TEXT_KEY)
				v.add_child(l)


func _refresh_dynamic(force: bool = false) -> void:
	var key := "%s|%s|%s|%s" % [service.download_line(), str(service.install_paused), str(service.can_play()), str(service.download.get("limit_while_playing", false))]
	if key == _last_dynamic and not force:
		return
	_last_dynamic = key
	download_label.text = service.download_line()
	pause_button.text = "Reanudar" if service.install_paused else "Pausar"
	pause_button.visible = not service.install_complete()
	limit_button.text = "Limitar mientras juego" + (" ✓" if bool(service.download.get("limit_while_playing", false)) else "")
	var segs: Array = []
	for p in service.packs:
		segs.append({"flex": float(p.get("weight", 1)), "ratio": float(p["progress"]), "color": Color(service.pack_fill_color(p))})
	install_bar.segments = segs
	Kit.clear(pack_labels)
	for p in service.packs:
		var l := Kit.label(service.pack_label(p), 12, Color(service.pack_color(p)))
		l.name = "Pack_%s" % p["id"]
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.size_flags_stretch_ratio = float(p.get("weight", 1))
		pack_labels.add_child(l)
	play_button.disabled = not service.can_play()
	play_hint.text = service.play_hint()
	if not force:
		EK.apply_accessibility(footer, service)
