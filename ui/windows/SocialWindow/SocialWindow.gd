extends "res://ui/windows/common/MenuWindow.gd"
## Social [O] — UI v2.4 Paso 9 (MMO-Social.html + MMO-Vecindad.html, Anexo E).
##
## Sub-pestañas:
## - Amigos: estado online/ausente/offline, nivel, zona. «Invitar al grupo» (alimenta
##   `party_frames`) y «Prestar habitante» (un secundario de tu Refugio va al de un amigo).
## - Gremio: ficha de hermandad, tu rango, miembros conectados y donación de oro al
##   cofre comunal (cobra en `CommerceService`).
## - Vecindad: edificio de El Nido con luces de quien está en casa, patio común (punto
##   de aparición), proyectos vecinales y mudanza gratis semanal.
##
## Estado en `SocialService` (+ `ShelterService` para los habitantes).

const SocialServiceScript = preload("res://shared-core/SocialService.gd")
const ShelterServiceScript = preload("res://shared-core/ShelterService.gd")

signal page_changed(page_id: String)
signal party_invited(friend_id: String, result: Dictionary)
signal inhabitant_lent(result: Dictionary)
signal donated(result: Dictionary)

const MENU_TAB_ID := "social"
const PAGES: Array[Dictionary] = [
	{"id": "amigos", "label": "Amigos"},
	{"id": "gremio", "label": "Gremio"},
	{"id": "vecindad", "label": "Vecindad"},
]
const STATUS_COLORS := {"online": Color("#4fe39a"), "away": Color("#f5c35b"), "offline": Color("#5b6770")}
const COLOR_FRIEND := Color("#46e3c1")
const COLOR_GUILD := Color("#c39bff")
const LIGHT_ON := Color("#f5c35b")

var service: Node = null
var current_page: String = ""
var page_buttons: Dictionary = {}
var pages: Dictionary = {}
var status_label: Label

# Amigos
var friends_box: VBoxContainer
var friend_rows: Dictionary = {}
var invite_buttons: Dictionary = {}
var lend_buttons: Dictionary = {}
var party_box: VBoxContainer
var loan_box: VBoxContainer
var loan_friend: String = ""
var loan_char: String = ""
var lend_button: Button
var feedback_label: Label

# Gremio
var guild_box: VBoxContainer
var members_box: VBoxContainer
var chest_label: Label
var chest_bar: Bar
var donate_buttons: Dictionary = {}
var donations_box: VBoxContainer
var guild_feedback: Label

# Vecindad
var neighborhood_header: VBoxContainer
var home_box: VBoxContainer
var building_grid: GridContainer
var building_cells: Dictionary = {}
var patio_box: HFlowContainer
var projects_box: VBoxContainer
var move_box: VBoxContainer
var hood_feedback: Label

var _built := false
var _refresh_queued := false


func _ready() -> void:
	window_id = "social_window"
	_resolve_service()
	_resolve_commerce()
	_build()
	super._ready()
	connect_menu_bar()
	if current_page == "":
		set_page("amigos")


func initialize_window(params: Dictionary) -> void:
	if _built and pages.has(str(params.get("page", ""))):
		set_page(str(params["page"]))


func _resolve_service() -> void:
	if service == null:
		service = get_node_or_null("/root/SocialService")
	if service == null:
		service = SocialServiceScript.new()
		service.name = "LocalSocialService"
		service.load_seed()
		add_child(service)
	elif service.get_parent() == null:
		add_child(service)
	if service.shelter == null:
		service.shelter = get_node_or_null("/root/ShelterService")
	if service.shelter == null:
		var s: Node = ShelterServiceScript.new()
		s.name = "LocalShelterService"
		add_child(s)
		service.shelter = s
	if not service.social_changed.is_connected(_on_service_changed):
		service.social_changed.connect(_on_service_changed)


func _on_service_changed() -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	_deferred_refresh.call_deferred()


func _deferred_refresh() -> void:
	_refresh_queued = false
	refresh()


# ==========================================================================
# Construcción
# ==========================================================================
func _build() -> void:
	if _built:
		return
	_built = true
	var col := build_frame(MENU_TAB_ID)
	var header := _hbox(10)
	header.name = "Header"
	col.add_child(header)
	var pill := PanelContainer.new()
	pill.name = "Subnav"
	var psb := T.box(T.SHELTER_CARD_BG, 12, 1, T.CODEX_CARD_BORDER)
	psb.set_content_margin_all(4)
	pill.add_theme_stylebox_override("panel", psb)
	header.add_child(pill)
	var subnav := _hbox(2)
	pill.add_child(subnav)
	for p in PAGES:
		var b := _chip_button(p["label"], 14, 30)
		b.name = "Page_" + p["id"]
		var pid: String = p["id"]
		b.pressed.connect(func() -> void: set_page(pid))
		subnav.add_child(b)
		page_buttons[pid] = b
	var title := _label("Social", 1, Color.TRANSPARENT)
	title.name = "TitleLabel"
	title.visible = false
	header.add_child(title)
	status_label = _label("", 13, T.TEXT_SECONDARY)
	status_label.name = "StatusLabel"
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(status_label)

	var root := Control.new()
	root.name = "Pages"
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(root)
	pages["amigos"] = _build_friends_page()
	pages["gremio"] = _build_guild_page()
	pages["vecindad"] = _build_hood_page()
	for id in pages:
		var pg: Control = pages[id]
		pg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		pg.visible = false
		root.add_child(pg)


func _build_friends_page() -> Control:
	var page := _hbox(12)
	page.name = "Page_amigos"
	var left := _card("FriendsCard", 16)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_child(left)
	var lv := _vbox(8)
	left.add_child(lv)
	lv.add_child(_caps("AMIGOS"))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lv.add_child(scroll)
	friends_box = _vbox(6)
	friends_box.name = "FriendList"
	friends_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(friends_box)
	feedback_label = _label("", 12, T.TEXT_SECONDARY)
	feedback_label.name = "Feedback"
	lv.add_child(feedback_label)

	var right := _card("PartyCard", 16)
	right.custom_minimum_size.x = 360
	page.add_child(right)
	var rv := _vbox(10)
	right.add_child(rv)
	party_box = _vbox(6)
	party_box.name = "Party"
	rv.add_child(party_box)
	var sep := HSeparator.new()
	sep.add_theme_stylebox_override("separator", T.box(T.DIVIDER, 0))
	rv.add_child(sep)
	loan_box = _vbox(8)
	loan_box.name = "Loan"
	loan_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rv.add_child(loan_box)
	lend_button = _primary_button("Prestar habitante")
	lend_button.name = "LendButton"
	lend_button.pressed.connect(lend_selected)
	rv.add_child(lend_button)
	return page


func _build_guild_page() -> Control:
	var page := _hbox(12)
	page.name = "Page_gremio"
	var left := _card("GuildCard", 18)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_child(left)
	var lv := _vbox(10)
	left.add_child(lv)
	guild_box = _vbox(6)
	guild_box.name = "GuildSheet"
	lv.add_child(guild_box)
	lv.add_child(_caps("MIEMBROS"))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lv.add_child(scroll)
	members_box = _vbox(4)
	members_box.name = "Members"
	members_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(members_box)

	var right := _card("ChestCard", 18)
	right.custom_minimum_size.x = 380
	page.add_child(right)
	var rv := _vbox(10)
	right.add_child(rv)
	rv.add_child(_caps("COFRE COMUNAL"))
	var ch := _hbox(8)
	rv.add_child(ch)
	ch.add_child(_dot(T.GOLD, 14))
	chest_label = _label("0", 28, T.GOLD, "bold")
	chest_label.name = "ChestGold"
	ch.add_child(chest_label)
	ch.add_child(_label("oro", 14, T.TEXT_SECONDARY))
	chest_bar = _bar(0.0, T.GOLD, 6)
	rv.add_child(chest_bar)
	var goal := _label("", 11, T.TEXT_SECONDARY)
	goal.name = "ChestGoal"
	rv.add_child(goal)
	rv.add_child(_caps("DONAR ORO"))
	var drow := _hbox(8)
	drow.name = "DonateRow"
	rv.add_child(drow)
	for amount in service.guild.get("donation_presets", [100, 500, 1000]):
		var b := _ghost_button("+%s" % fmt(int(amount)))
		b.name = "Donate_%d" % int(amount)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_color_override("font_color", T.GOLD)
		var a := int(amount)
		b.pressed.connect(func() -> void: donate(a))
		drow.add_child(b)
		donate_buttons[a] = b
	rv.add_child(_wrap_label("El oro se gana jugando y no se puede comprar: cada donación sale de tu bolsa.", 11, T.TEXT_MUTED))
	guild_feedback = _label("", 12, T.TEXT_SECONDARY)
	guild_feedback.name = "GuildFeedback"
	rv.add_child(guild_feedback)
	rv.add_child(_caps("DONACIONES RECIENTES"))
	donations_box = _vbox(4)
	donations_box.name = "Donations"
	rv.add_child(donations_box)
	return page


func _build_hood_page() -> Control:
	var page := _hbox(12)
	page.name = "Page_vecindad"
	var left := _card("HomeCard", 16)
	left.custom_minimum_size.x = 270
	page.add_child(left)
	var lv := _vbox(8)
	left.add_child(lv)
	neighborhood_header = _vbox(2)
	neighborhood_header.name = "HoodHeader"
	lv.add_child(neighborhood_header)
	lv.add_child(_caps("VECINOS CONECTADOS"))
	home_box = _vbox(6)
	home_box.name = "AtHome"
	lv.add_child(home_box)

	var center := _card("BuildingCard", 14, Color("#0a0f13"))
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_child(center)
	var cv := _vbox(8)
	center.add_child(cv)
	var top := _hbox(8)
	cv.add_child(top)
	top.add_child(_caps("EL NIDO · EDIFICIO"))
	top.add_child(_spacer(Vector2.ZERO, true))
	for leg in [[LIGHT_ON, "en casa"], [COLOR_FRIEND, "amigo"], [COLOR_GUILD, "gremio"]]:
		top.add_child(_dot(leg[0], 8))
		top.add_child(_label(leg[1], 11, T.TEXT_SECONDARY))
	building_grid = GridContainer.new()
	building_grid.name = "Building"
	building_grid.add_theme_constant_override("h_separation", 6)
	building_grid.add_theme_constant_override("v_separation", 6)
	building_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cv.add_child(building_grid)
	var patio_cap := _hbox(8)
	cv.add_child(patio_cap)
	patio_cap.add_child(_caps("EL PATIO", T.ACCENT_DEFAULT))
	patio_cap.add_child(_label("Aquí aparecen todos al entrar al juego · zona segura", 11, T.TEXT_SECONDARY))
	patio_box = HFlowContainer.new()
	patio_box.name = "Patio"
	patio_box.add_theme_constant_override("h_separation", 6)
	patio_box.add_theme_constant_override("v_separation", 6)
	cv.add_child(patio_box)

	var right := _card("ProjectsCard", 16)
	right.custom_minimum_size.x = 310
	page.add_child(right)
	var rv := _vbox(8)
	right.add_child(rv)
	rv.add_child(_caps("PROYECTOS VECINALES"))
	projects_box = _vbox(8)
	projects_box.name = "Projects"
	rv.add_child(projects_box)
	rv.add_child(_spacer(Vector2.ZERO, false, true))
	rv.add_child(_caps("MUDANZA"))
	move_box = _vbox(6)
	move_box.name = "Move"
	rv.add_child(move_box)
	hood_feedback = _label("", 11, T.TEXT_SECONDARY)
	hood_feedback.name = "HoodFeedback"
	hood_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rv.add_child(hood_feedback)
	return page


# ==========================================================================
# API
# ==========================================================================
func set_page(page_id: String) -> void:
	if not pages.has(page_id):
		return
	current_page = page_id
	for id in pages:
		(pages[id] as Control).visible = id == page_id
		(page_buttons[id] as Button).set_pressed_no_signal(id == page_id)
	refresh()
	page_changed.emit(page_id)


func invite(friend_id: String) -> Dictionary:
	var r: Dictionary = service.invite_to_party(friend_id)
	var fr: Dictionary = service.get_friend(friend_id)
	if r.get("ok", false):
		feedback_label.text = "%s se ha unido a tu grupo." % fr.get("name", friend_id)
	else:
		feedback_label.text = _reason_text(str(r.get("reason", "")))
	party_invited.emit(friend_id, r)
	refresh()
	return r


func choose_loan_friend(friend_id: String) -> void:
	loan_friend = friend_id
	if loan_char == "":
		var opts: Array = service.get_lendable_inhabitants()
		if not opts.is_empty():
			loan_char = str(opts[0]["id"])
	refresh()


func choose_loan_inhabitant(char_id: String) -> void:
	loan_char = char_id
	refresh()


func lend_selected() -> Dictionary:
	if loan_friend == "" or loan_char == "":
		feedback_label.text = "Elige un amigo con «Prestar habitante» y a quién mandar."
		return {"ok": false, "reason": "no_selection"}
	var r: Dictionary = service.lend_inhabitant(loan_friend, loan_char)
	if r.get("ok", false):
		feedback_label.text = "Prestado a %s durante %d h: volverá solo a tu Refugio." % [r["friend"], int(r["hours"])]
		loan_char = ""
	else:
		feedback_label.text = _reason_text(str(r.get("reason", "")))
	inhabitant_lent.emit(r)
	refresh()
	return r


## Dona oro al cofre comunal y lo cobra de tu bolsa.
func donate(amount: int) -> Dictionary:
	var gold := int(commerce.gold) if commerce else -1
	var r: Dictionary = service.donate_to_guild(amount, gold)
	if r.get("ok", false):
		if commerce:
			commerce.spend_gold(amount)
		guild_feedback.text = "Has donado %s de oro al cofre. ¡Gracias!" % fmt(amount)
	else:
		guild_feedback.text = _reason_text(str(r.get("reason", "")))
	donated.emit(r)
	refresh()
	return r


func contribute(project_id: String, amount: int) -> Dictionary:
	var r: Dictionary = service.contribute_project(project_id, amount)
	hood_feedback.text = ("Aportación registrada." if not r.get("done", false) else "¡Proyecto completado!") if r.get("ok", false) else _reason_text(str(r.get("reason", "")))
	refresh()
	return r


func move_to(neighborhood_id: String) -> Dictionary:
	var r: Dictionary = service.move_to(neighborhood_id)
	if r.get("ok", false):
		hood_feedback.text = "Te mudaste a %s. Tu depa viajó contigo tal cual." % r["neighborhood"]
	else:
		hood_feedback.text = _reason_text(str(r.get("reason", "")))
		if r.get("reason", "") == "weekly_limit":
			hood_feedback.text = "La mudanza gratis es una vez por semana: vuelve en %d días." % int(r["days_left"])
	refresh()
	return r


static func _reason_text(reason: String) -> String:
	match reason:
		"offline":
			return "Está desconectado: no puede unirse ahora."
		"already_in_party":
			return "Ya está en tu grupo."
		"party_full":
			return "Tu grupo está completo."
		"main_character":
			return "Tu personaje principal no se presta."
		"borrowed_from_other":
			return "Ese habitante ya es prestado: vuelve con su dueño."
		"already_lent":
			return "Ya está prestado."
		"busy":
			return "Está de expedición."
		"not_enough_gold":
			return "No tienes oro suficiente."
		"no_free_units":
			return "No quedan depas libres allí."
		"already_done":
			return "Ese proyecto ya está terminado."
	return "No se pudo completar la acción."


# ==========================================================================
# Refresco
# ==========================================================================
func refresh() -> void:
	if not _built:
		return
	status_label.text = "%d amigos en línea · gremio %s · %s" % [service.count_online(), str(service.guild.get("name", "—")), str(service.neighborhood.get("name", ""))]
	(page_buttons["amigos"] as Button).text = "Amigos %d" % service.friends.size()
	_refresh_friends()
	_refresh_guild()
	_refresh_hood()


func _refresh_friends() -> void:
	_clear(friends_box)
	friend_rows.clear()
	invite_buttons.clear()
	lend_buttons.clear()
	for fr in service.list_friends():
		var row := _sub_card("Friend_" + str(fr["id"]), 10)
		if fr["id"] == loan_friend:
			var sel_sb := T.box(T.SHELTER_SUB_BG, 12, 1, Color(T.ACCENT_DEFAULT, 0.8))
			sel_sb.set_content_margin_all(10)
			row.add_theme_stylebox_override("panel", sel_sb)
		friends_box.add_child(row)
		var h := _hbox(10)
		row.add_child(h)
		var avatar := PanelContainer.new()
		avatar.custom_minimum_size = Vector2(34, 34)
		avatar.add_theme_stylebox_override("panel", T.box(Color(str(fr.get("color", "#9aa6ae"))).darkened(0.55), 17, 2, Color(str(fr.get("color", "#9aa6ae")))))
		var ini := _label(str(fr["name"]).substr(0, 1), 14, T.TEXT, "bold")
		ini.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ini.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		avatar.add_child(ini)
		avatar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(avatar)
		var v := _vbox(2)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		h.add_child(v)
		var nh := _hbox(6)
		v.add_child(nh)
		var dot := _dot(STATUS_COLORS.get(fr["status"], Color.GRAY), 8)
		dot.name = "StatusDot"
		nh.add_child(dot)
		nh.add_child(_label(str(fr["name"]), 14, T.TEXT if fr["online"] else T.TEXT_SECONDARY, "semibold"))
		var lvl := _label("Nv %d" % int(fr["level"]), 11, T.TEXT_SECONDARY, "semibold")
		lvl.name = "Level"
		nh.add_child(lvl)
		if fr.get("guild", false):
			nh.add_child(_badge("Gremio", COLOR_GUILD))
		var sub := _label("%s · %s" % [str(fr["activity"]), str(fr["zone"])] if fr["status"] != "offline" else str(fr["activity"]), 11, T.TEXT_SECONDARY)
		sub.name = "Zone"
		v.add_child(sub)
		var inv := _ghost_button("En tu grupo" if fr["in_party"] else "Invitar al grupo", 12, 30)
		inv.name = "Invite"
		inv.disabled = fr["in_party"] or not fr["online"]
		var fid: String = fr["id"]
		inv.pressed.connect(func() -> void: invite(fid))
		h.add_child(inv)
		var lend := _ghost_button("Prestar habitante", 12, 30)
		lend.name = "Lend"
		lend.pressed.connect(func() -> void: choose_loan_friend(fid))
		h.add_child(lend)
		friend_rows[fid] = row
		invite_buttons[fid] = inv
		lend_buttons[fid] = lend

	_clear(party_box)
	var members: Array = service.get_party_members_data()
	var ph := _hbox(6)
	party_box.add_child(ph)
	ph.add_child(_caps("TU GRUPO"))
	ph.add_child(_spacer(Vector2.ZERO, true))
	ph.add_child(_label("%d/%d" % [members.size() + 1, int(service.max_party)], 12, T.TEXT_SECONDARY, "semibold"))
	party_box.add_child(_party_line(str(service.player.get("name", "Tú")) + " (tú)", int(service.player.get("level", 1)), T.ACCENT_DEFAULT))
	for m in members:
		var fr2: Dictionary = service.get_friend(str(m["friend_id"]))
		party_box.add_child(_party_line(str(m["name"]), int(m["level"]), Color(str(fr2.get("color", "#9aa6ae")))))

	_clear(loan_box)
	loan_box.add_child(_caps("PRESTAR HABITANTE"))
	var target: Dictionary = service.get_friend(loan_friend)
	loan_box.add_child(_wrap_label(("Mandar a alguien al Refugio de %s durante %d h. Trabaja allí y vuelve solo." % [target["name"], int(service.loan_hours)]) if not target.is_empty() else "Pulsa «Prestar habitante» en un amigo para elegir a quién ayudar.", 12, T.TEXT_KEY))
	var chips := HFlowContainer.new()
	chips.name = "Inhabitants"
	chips.add_theme_constant_override("h_separation", 6)
	chips.add_theme_constant_override("v_separation", 6)
	loan_box.add_child(chips)
	for ch in service.get_lendable_inhabitants():
		var cb := _chip_button("%s · %s" % [ch["name"], ch.get("role", "")], 12, 28)
		cb.name = "Inh_" + str(ch["id"])
		cb.button_pressed = ch["id"] == loan_char
		var cid: String = ch["id"]
		cb.pressed.connect(func() -> void: choose_loan_inhabitant(cid))
		chips.add_child(cb)
	if not service.loans.is_empty():
		loan_box.add_child(_caps("PRESTADOS AHORA"))
		for l in service.loans:
			loan_box.add_child(_label("%s → %s · %d h" % [l["char_name"], l["friend_name"], int(ceil(float(l["hours_left"])))], 12, T.TEXT))
	lend_button.disabled = target.is_empty() or loan_char == ""
	lend_button.text = "Prestar a %s" % target["name"] if not target.is_empty() else "Prestar habitante"


func _party_line(nm: String, lvl: int, color: Color) -> HBoxContainer:
	var h := _hbox(8)
	h.add_child(_dot(color, 10))
	var l := _label(nm, 13, T.TEXT, "semibold")
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	h.add_child(_label("Nv %d" % lvl, 11, T.TEXT_SECONDARY))
	return h


func _refresh_guild() -> void:
	var g: Dictionary = service.guild
	_clear(guild_box)
	if g.is_empty():
		guild_box.add_child(_label("No perteneces a ningún gremio.", 14, T.TEXT_MUTED))
		return
	var nm := _label(str(g["name"]), 24, T.TEXT, "bold")
	nm.name = "GuildName"
	guild_box.add_child(nm)
	var online: Array = service.guild_members_online()
	var info := _label("Nivel de gremio %d · %d en línea de %d miembros" % [int(g.get("level", 1)), int(g.get("online_total", online.size())), int(g.get("members_total", 0))], 13, T.TEXT_SECONDARY)
	info.name = "GuildInfo"
	guild_box.add_child(info)
	guild_box.add_child(_wrap_label("«%s»" % g.get("motto", ""), 12, T.TEXT_KEY))
	var row := _hbox(8)
	guild_box.add_child(row)
	var rank := _badge("Tu rango: %s" % g.get("rank", ""), T.ACCENT_DEFAULT)
	rank.name = "Rank"
	row.add_child(rank)
	if str(g.get("event", "")) != "":
		row.add_child(_badge(str(g["event"]), T.GOLD))
	_clear(members_box)
	var members: Array = (g.get("members", []) as Array).duplicate()
	members.sort_custom(func(a, b) -> bool: return bool(a["online"]) and not bool(b["online"]))
	for m in members:
		var h := _hbox(10)
		h.name = "Member"
		members_box.add_child(h)
		h.add_child(_dot(STATUS_COLORS["online"] if m["online"] else STATUS_COLORS["offline"], 8))
		var l := _label(str(m["name"]), 13, T.TEXT if m["online"] else T.TEXT_SECONDARY, "semibold")
		l.custom_minimum_size.x = 140
		h.add_child(l)
		var rk := _label(str(m["rank"]), 12, COLOR_GUILD if m["rank"] in ["Maestre", "Oficial"] else T.TEXT_SECONDARY)
		rk.custom_minimum_size.x = 100
		h.add_child(rk)
		h.add_child(_label(str(m.get("zone", "")) if m["online"] else "Desconectado", 12, T.TEXT_SECONDARY))
	chest_label.text = fmt(int(g.get("chest_gold", 0)))
	chest_bar.ratio = float(g.get("chest_gold", 0)) / maxf(1.0, float(g.get("chest_goal", 1)))
	var goal := chest_bar.get_parent().get_node_or_null("ChestGoal") as Label
	if goal:
		goal.text = "Meta: %s · %s / %s" % [g.get("chest_goal_label", ""), fmt(int(g.get("chest_gold", 0))), fmt(int(g.get("chest_goal", 0)))]
	var gold := int(commerce.gold) if commerce else 1 << 30
	for a in donate_buttons:
		(donate_buttons[a] as Button).disabled = int(a) > gold
	_clear(donations_box)
	var dons: Array = g.get("donations", [])
	for i in mini(5, dons.size()):
		var h2 := _hbox(6)
		donations_box.add_child(h2)
		var l2 := _label(str(dons[i]["name"]), 12, T.TEXT)
		l2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h2.add_child(l2)
		h2.add_child(_label("+%s oro" % fmt(int(dons[i]["amount"])), 12, T.GOLD, "semibold"))


func _refresh_hood() -> void:
	var n: Dictionary = service.neighborhood
	_clear(neighborhood_header)
	var at_home: Array = service.neighbors_at_home()
	var hn := _label(str(n.get("name", "")), 18, T.TEXT, "bold")
	hn.name = "HoodName"
	neighborhood_header.add_child(hn)
	neighborhood_header.add_child(_label("%d depas · %d vecinos · %d en casa" % [int(n.get("floors", 0)) * int(n.get("units_per_floor", 0)), int(n.get("neighbors_total", 0)), at_home.size()], 12, T.TEXT_SECONDARY))
	neighborhood_header.add_child(_label("Tu gremio vive aquí: %d" % int(n.get("guild_neighbors", 0)), 12, COLOR_GUILD))
	_clear(home_box)
	for r in n.get("residents_online", []):
		var h := _hbox(8)
		home_box.add_child(h)
		h.add_child(_dot(COLOR_FRIEND if r.get("friend", false) else (COLOR_GUILD if r.get("guild", false) else LIGHT_ON), 8))
		var v := _vbox(0)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(v)
		v.add_child(_label(str(r["name"]), 13, T.TEXT, "semibold"))
		v.add_child(_label(str(r["where"]), 11, T.TEXT_SECONDARY))
		h.add_child(_ghost_button(str(r["action"]), 11, 26))

	_clear(building_grid)
	building_cells.clear()
	var grid: Array = service.get_building()
	building_grid.columns = int(n.get("units_per_floor", 4))
	for fi in range(grid.size() - 1, -1, -1):
		for cell in grid[fi]:
			building_grid.add_child(_apartment(cell))

	_clear(patio_box)
	for p in n.get("patio", []):
		var c := _sub_card("Patio_" + str(p["id"]), 8)
		var v2 := _vbox(0)
		c.add_child(v2)
		v2.add_child(_label(str(p["name"]), 12, T.TEXT, "semibold"))
		v2.add_child(_label(str(p["note"]), 10, T.TEXT_SECONDARY))
		patio_box.add_child(c)

	_clear(projects_box)
	for pr in service.list_projects():
		var c2 := _sub_card("Project_" + str(pr["id"]), 10)
		projects_box.add_child(c2)
		var v3 := _vbox(5)
		c2.add_child(v3)
		v3.add_child(_label(str(pr["name"]), 13, T.TEXT, "semibold"))
		v3.add_child(_bar(float(pr["ratio"]), T.ACCENT_DEFAULT if not pr["done"] else T.DELTA_UP, 5))
		v3.add_child(_wrap_label("%d %% · %s" % [int(round(float(pr["ratio"]) * 100.0)), pr["reward"]], 11, T.TEXT_SECONDARY))
		var b := _ghost_button("Aportar 100 de %s" % pr["resource"], 12, 28)
		b.name = "Contribute"
		b.disabled = pr["done"]
		var pid: String = pr["id"]
		b.pressed.connect(func() -> void: contribute(pid, 100))
		v3.add_child(b)

	_clear(move_box)
	move_box.add_child(_wrap_label("¿Tus amigos viven en otra vecindad? Puedes mudarte gratis una vez por semana; tu depa viaja contigo tal cual.", 11, T.TEXT_KEY))
	var free_move: bool = service.can_move_free()
	var st := _label("Mudanza gratis disponible" if free_move else "Próxima mudanza gratis en %d días" % service.days_until_free_move(), 12, T.DELTA_UP if free_move else T.GOLD, "semibold")
	st.name = "MoveStatus"
	move_box.add_child(st)
	for o in n.get("other_neighborhoods", []):
		var h3 := _hbox(6)
		move_box.add_child(h3)
		var friends_txt := ", ".join(o.get("friends", [])) if not (o.get("friends", []) as Array).is_empty() else "sin amigos"
		var v4 := _vbox(0)
		v4.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h3.add_child(v4)
		v4.add_child(_label(str(o["name"]), 12, T.TEXT, "semibold"))
		v4.add_child(_label("%s · %d libres" % [friends_txt, int(o.get("free_units", 0))], 10, T.TEXT_SECONDARY))
		var mb := _ghost_button("Mudarme", 11, 26)
		mb.name = "Move_" + str(o["id"])
		mb.disabled = not free_move or int(o.get("free_units", 0)) <= 0
		var oid: String = o["id"]
		mb.pressed.connect(func() -> void: move_to(oid))
		h3.add_child(mb)


func _apartment(cell: Dictionary) -> PanelContainer:
	var home: bool = cell["home"]
	var friend: bool = cell.get("friend", false)
	var guild: bool = cell.get("guild", false)
	var me: bool = cell["is_player"]
	var rent: bool = cell.get("rent", false)
	var bg := Color("#2a2416") if home else Color("#11171b")
	if me:
		bg = Color(T.ACCENT_DEFAULT, 0.18)
	var border := Color(1, 1, 1, 0.06)
	if friend:
		border = COLOR_FRIEND
	elif guild:
		border = COLOR_GUILD
	if me:
		border = T.ACCENT_DEFAULT
	var p := PanelContainer.new()
	p.name = "Apt_%d_%d" % [int(cell["floor"]), int(cell["unit"])]
	var sb := T.box(bg, 8, 1 if not (friend or guild or me) else 2, border)
	sb.set_content_margin_all(6)
	if rent:
		sb = T.box(Color(0, 0, 0, 0), 8, 1, Color(1, 1, 1, 0.18))
		sb.set_content_margin_all(6)
	p.add_theme_stylebox_override("panel", sb)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	p.custom_minimum_size = Vector2(90, 40)
	var h := _hbox(6)
	p.add_child(h)
	var win := PanelContainer.new()
	win.name = "Window"
	win.custom_minimum_size = Vector2(12, 16)
	win.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	win.add_theme_stylebox_override("panel", T.box(LIGHT_ON if home else Color("#1b2329"), 3))
	h.add_child(win)
	var v := _vbox(0)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(v)
	var owner_text := "Se renta" if rent else str(cell["owner"])
	var ol := _label(owner_text, 12, T.TEXT if home else T.TEXT_SECONDARY, "semibold")
	ol.name = "Owner"
	ol.clip_text = true
	v.add_child(ol)
	var sub := "Invita a un amigo" if rent else ("Confort %d · piso %d" % [int(cell.get("comfort", 0)), int(cell["floor"]) + 1] if me else ("Luz encendida" if home else "Fuera, en el mundo"))
	v.add_child(_label(sub, 10, T.TEXT_MUTED))
	building_cells["%d:%d" % [int(cell["floor"]), int(cell["unit"])]] = p
	return p
