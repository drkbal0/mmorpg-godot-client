extends "res://ui/windows/common/SystemWindow.gd"
## Editor de interfaz — UI v2.4 Paso 16 · ADR 114 (design_ref/pantallas_html/MMO-Interfaz.html).
##
## Lienzo 1440×810 con la barra del menú común:
## - Vista previa editable (980 px, top 88): chips «Arrastra módulos», «Ajustar a cuadrícula ✓»,
##   «Deshacer [Ctrl Z]» y «Probar en combate simulado»; área de trabajo de 944×531 con el fondo
##   cinemático atenuado, cuadrícula de 24 px, los 9 módulos arrastrables, esquinas del módulo
##   seleccionado y guías magnéticas rosas (#ff6fa8 «alineado con Objetivo»). Pie: «Diseño: Daño ·
##   mazmorra» y «Código para compartir HUD-7QK-D2M» con «Importar».
## - Panel derecho (388 px): «Diseños por rol» (Tanque · Sanador · Daño · Explorador · Raid 20 ·
##   Streamer), «Cambiar solo según el contenido», propiedades del módulo seleccionado (Escala y
##   Opacidad fuera de combate) y accesibilidad del HUD (modo de color, texto grande, reducir
##   movimiento, narrador, avisos 3D y formas además de colores).
##
## Teclado: Ctrl Z deshacer · Ctrl Y / Ctrl Shift Z rehacer · flechas mueven el módulo (una celda
## con cuadrícula) · Tab cambia de módulo · F10 Ajustes · Esc cerrar.
##
## Estado en `UIEditorService` (inyectable como `editor`) y `SettingsService` (`settings`).

const UIEditorScript = preload("res://shared-core/UIEditorService.gd")
const S = SettingsScript

const A11Y_ROWS := [
	["large_text", "Texto grande (115 %)", "afecta a todos los módulos"],
	["reduce_motion", "Reducir movimiento", "sin destellos ni sacudidas"],
	["narrator", "Narrador de interfaz", "lee menús y alertas"],
	["directional_audio", "Avisos sonoros direccionales", "mecánicas por audio 3D"],
	["shapes_with_colors", "Formas además de colores", "rombos, triángulos, círculos"],
]

signal module_selected(module_id: String)

## Servicio del editor inyectable (tests). Si es null se usa /root/UIEditorService o uno local.
var editor: Node = null

var preview_card: PanelContainer
var drag_chip: PanelContainer
var snap_chip: Button
var undo_chip: Button
var combat_chip: Button
var canvas: Control
var canvas_scene: Control
var grid_layer: GridLayer
var modules_layer: Control
var overlay: Overlay
var module_boxes: Dictionary = {}              # id -> ModuleBox
var layout_chip: PanelContainer
var code_title: Label
var code_edit: LineEdit
var import_button: Button

var panel_card: PanelContainer
var preset_grid: GridContainer
var preset_chips: Dictionary = {}              # id -> Button
var auto_switch: SK.Switch
var content_rule_label: Label
var selected_caps: Label
var scale_slider: HSlider
var scale_value_label: Label
var opacity_slider: HSlider
var opacity_value_label: Label
var color_mode_buttons: Dictionary = {}        # mode -> Button
var a11y_switches: Dictionary = {}             # key -> Switch

var _grab_offset := Vector2.ZERO
var _code_dirty := false


func _window_id() -> String:
	return "ui_editor"


# ==========================================================================
# Ciclo de vida
# ==========================================================================
## params: {"module": "timeline", "preset": "dps", "content": "dungeon"}
func initialize_window(params: Dictionary) -> void:
	if editor == null or settings == null:
		_resolve_settings()
	if params.has("content"):
		editor.on_content_changed(str(params["content"]))
	if params.has("preset"):
		editor.apply_preset(str(params["preset"]))
	if params.has("module"):
		editor.select_module(str(params["module"]))
	visible = true
	if _built:
		refresh()


func _resolve_settings() -> void:
	super._resolve_settings()
	if editor == null and is_inside_tree():
		editor = get_node_or_null("/root/UIEditorService")
	if editor == null:
		editor = UIEditorScript.new()
		editor.name = "LocalUIEditorService"
		editor.autosave = false
		editor.load_seed()
	if editor.get_parent() == null:
		add_child(editor)
	for sig in ["layout_changed", "selection_changed", "preset_changed", "guides_changed", "history_changed",
			"combat_simulation_changed", "auto_switch_changed", "code_imported"]:
		var cb := Callable(self, "_on_editor_changed")
		if not editor.is_connected(sig, cb):
			editor.connect(sig, cb)
	var cbs := Callable(self, "_on_editor_changed")
	if not settings.is_connected("applied", cbs):
		settings.connect("applied", cbs)


func _on_editor_changed(_a = null, _b = null) -> void:
	if _built:
		refresh()


# ==========================================================================
# API (tests y atajos)
# ==========================================================================
func select_module(id: String) -> bool:
	var ok: bool = editor.select_module(id)
	if ok and id != "":
		module_selected.emit(id)
		settings.announce("%s seleccionado" % editor.module_label(id))
	return ok


## Arrastra un módulo hasta `to` (coordenadas del lienzo, esquina superior izquierda).
func drag_module(id: String, to: Vector2) -> Vector2:
	if not editor.begin_drag(id):
		return Vector2.ZERO
	var from: Vector2 = editor.module_rect(id).position
	editor.drag_to(from.lerp(to, 0.5))
	var p: Vector2 = editor.drag_to(to)
	editor.end_drag()
	module_selected.emit(id)
	return p


func set_scale_percent(pct: float) -> float:
	if editor.selected == "":
		return 0.0
	return editor.set_module_scale(editor.selected, pct / 100.0) * 100.0


func set_opacity_percent(pct: float) -> float:
	if editor.selected == "":
		return 0.0
	return editor.set_module_opacity(editor.selected, pct / 100.0) * 100.0


func choose_preset(id: String) -> bool:
	return editor.apply_preset(id)


func set_auto_switch(on: bool) -> void:
	editor.set_auto_switch(on)
	refresh()


func toggle_snap() -> bool:
	editor.set_snap(not editor.snap_to_grid)
	refresh()
	return editor.snap_to_grid


func undo() -> bool:
	return editor.undo()


func redo() -> bool:
	return editor.redo()


func toggle_combat_simulation() -> bool:
	editor.simulate_combat(not editor.simulating_combat)
	refresh()
	return editor.simulating_combat


func import_code(text: String = "") -> Dictionary:
	var code := text if text != "" else code_edit.text
	var r: Dictionary = editor.import_code(code)
	_code_dirty = not r.get("ok", false)
	if r.get("ok", false):
		settings.announce("Diseño importado: %s" % editor.preset_context())
	refresh()
	if not r.get("ok", false):
		code_title.text = str(r.get("error", "Código no válido"))
		code_title.add_theme_color_override("font_color", sem("bad"))
	return r


func share_code() -> String:
	return editor.share_code()


func set_color_mode(mode: String) -> bool:
	return settings.set_and_apply(S.CAT_ACCESSIBILITY, "color_mode", mode)


func set_a11y(key: String, on: bool) -> bool:
	return settings.set_and_apply(S.CAT_ACCESSIBILITY, key, on)


func _handle_key(ev: InputEventKey) -> bool:
	if code_edit and code_edit.has_focus():
		if ev.keycode == KEY_ESCAPE:
			code_edit.release_focus()
			return true
		if ev.keycode == KEY_ENTER or ev.keycode == KEY_KP_ENTER:
			import_code()
			return true
		return false
	if editor.handle_shortcut(ev):
		refresh()
		return true
	if ev.ctrl_pressed or ev.alt_pressed or ev.meta_pressed:
		return false
	var dir := Vector2.ZERO
	match ev.keycode:
		KEY_LEFT:
			dir = Vector2.LEFT
		KEY_RIGHT:
			dir = Vector2.RIGHT
		KEY_UP:
			dir = Vector2.UP
		KEY_DOWN:
			dir = Vector2.DOWN
		KEY_TAB:
			var ids: Array[String] = editor.visible_modules()
			if ids.is_empty():
				return true
			var i := ids.find(editor.selected)
			select_module(ids[posmod(i + (-1 if ev.shift_pressed else 1), ids.size())])
			return true
	if dir != Vector2.ZERO and editor.selected != "":
		editor.nudge(editor.selected, dir)
		return true
	return false


func _on_f10() -> void:
	var orch := _orchestrator()
	if orch != null and orch.has_method("open_settings"):
		orch.open_settings(S.CAT_INTERFACE)


# ==========================================================================
# Construcción
# ==========================================================================
func _build() -> void:
	_build_preview()
	_build_panel()


func _build_preview() -> void:
	preview_card = SK.card("Preview", 18)
	place(preview_card, T.SETTINGS_LEFT_X, T.SETTINGS_TOP, T.EDITOR_LEFT_WIDTH, T.SETTINGS_CARD_HEIGHT)
	var v := SK.vbox("Body", 12)
	preview_card.add_child(v)
	var head := SK.hbox("Header", 8)
	head.custom_minimum_size.y = 28
	v.add_child(head)
	var t := Kit.label("Editor de interfaz", 18, T.TEXT, "bold")
	t.name = "Title"
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(t)
	head.add_child(_gap(4))
	drag_chip = Kit.chip("Arrastra módulos", Color(T.ACCENT_DEFAULT, 0.14), T.ACCENT_DEFAULT)
	drag_chip.name = "DragChip"
	head.add_child(drag_chip)
	snap_chip = SK.chip_button("SnapChip", "")
	snap_chip.pressed.connect(func() -> void: toggle_snap())
	head.add_child(snap_chip)
	undo_chip = SK.chip_button("UndoChip", "Deshacer")
	var uk := Kit.kbd("Ctrl Z")
	uk.name = "Kbd"
	undo_chip.add_child(uk)
	undo_chip.custom_minimum_size.x = 118
	undo_chip.alignment = HORIZONTAL_ALIGNMENT_LEFT
	undo_chip.pressed.connect(func() -> void: undo())
	SK.a11y_name(undo_chip, "Deshacer (Ctrl Z)")
	head.add_child(undo_chip)
	head.add_child(SK.expand())
	combat_chip = SK.chip_button("CombatChip", "Probar en combate simulado")
	combat_chip.pressed.connect(func() -> void: toggle_combat_simulation())
	head.add_child(combat_chip)

	canvas = Control.new()
	canvas.name = "Canvas"
	canvas.custom_minimum_size = T.EDITOR_CANVAS_SIZE
	canvas.clip_contents = true
	canvas.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_child(canvas)
	canvas_scene = EK.scene_rect("Scene")
	canvas_scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(canvas_scene)
	var cveil := ColorRect.new()
	cveil.name = "Veil"
	cveil.color = T.EDITOR_CANVAS_VEIL
	cveil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cveil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(cveil)
	grid_layer = GridLayer.new()
	grid_layer.name = "Grid"
	grid_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(grid_layer)
	modules_layer = Control.new()
	modules_layer.name = "Modules"
	modules_layer.mouse_filter = Control.MOUSE_FILTER_PASS
	modules_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(modules_layer)
	for id in UIEditorScript.MODULE_IDS:
		var mb := ModuleBox.new()
		mb.name = "Module_" + id
		mb.module_id = id
		mb.host = self
		SK.a11y_name(mb, editor.module_label(id))
		modules_layer.add_child(mb)
		module_boxes[id] = mb
	overlay = Overlay.new()
	overlay.name = "Overlay"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(overlay)

	var foot := SK.hbox("Footer", 8)
	foot.custom_minimum_size.y = 30
	v.add_child(foot)
	var dl := Kit.label("Diseño:", 13, T.TEXT_SECONDARY)
	dl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(dl)
	layout_chip = Kit.chip("", T.BUTTON_BG, T.TEXT, 26)
	layout_chip.name = "LayoutChip"
	layout_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(layout_chip)
	foot.add_child(SK.expand())
	code_title = Kit.label("Código para compartir", 13, T.TEXT_SECONDARY)
	code_title.name = "CodeTitle"
	code_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(code_title)
	code_edit = LineEdit.new()
	code_edit.name = "Code"
	code_edit.custom_minimum_size = Vector2(124, 26)
	code_edit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	code_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	code_edit.select_all_on_focus = true
	var csb := Kit.box(T.BUTTON_BG, 8)
	csb.content_margin_left = 10
	csb.content_margin_right = 10
	code_edit.add_theme_stylebox_override("normal", csb)
	code_edit.add_theme_stylebox_override("focus", Kit.box(T.BUTTON_BG, 8, 1.5, T.ACCENT_DEFAULT))
	code_edit.add_theme_stylebox_override("read_only", csb)
	var cf := FontVariation.new()
	cf.base_font = T.font("semibold")
	cf.spacing_glyph = 1
	code_edit.add_theme_font_override("font", cf)
	code_edit.add_theme_font_size_override("font_size", 13)
	code_edit.add_theme_color_override("font_color", T.TEXT)
	SK.a11y_name(code_edit, "Código para compartir")
	code_edit.text_changed.connect(func(_t: String) -> void: _code_dirty = true)
	foot.add_child(code_edit)
	import_button = SK.button("Import", "Importar", 30, 14)
	import_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	import_button.pressed.connect(func() -> void: import_code())
	foot.add_child(import_button)


func _build_panel() -> void:
	panel_card = SK.card("Panel", 18)
	place(panel_card, T.EDITOR_PANEL_X, T.SETTINGS_TOP, T.EDITOR_PANEL_WIDTH, T.SETTINGS_CARD_HEIGHT)
	var v := SK.vbox("Body", 11)
	panel_card.add_child(v)
	v.add_child(Kit.caps("Diseños por rol"))
	preset_grid = GridContainer.new()
	preset_grid.name = "Presets"
	preset_grid.columns = 3
	preset_grid.add_theme_constant_override("h_separation", 6)
	preset_grid.add_theme_constant_override("v_separation", 6)
	v.add_child(preset_grid)
	for id in editor.preset_ids(true):
		var b := SK.chip_button("Preset_" + id, editor.preset_label(id))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var pid: String = id
		b.pressed.connect(func() -> void: choose_preset(pid))
		SK.a11y_name(b, "Diseño " + editor.preset_label(id))
		preset_grid.add_child(b)
		preset_chips[id] = b

	var auto_card := SK.sub("AutoSwitch", 12, 10)
	v.add_child(auto_card)
	var av := SK.vbox("Body", 6)
	auto_card.add_child(av)
	var ah := SK.hbox("Row", 10)
	av.add_child(ah)
	var al := Kit.label("Cambiar solo según el contenido", 14, T.TEXT, "semibold")
	al.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	al.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ah.add_child(al)
	auto_switch = SK.Switch.new()
	auto_switch.name = "Switch"
	SK.a11y_name(auto_switch, "Cambiar solo según el contenido")
	auto_switch.toggled.connect(func(on: bool) -> void: set_auto_switch(on))
	ah.add_child(auto_switch)
	content_rule_label = Kit.label("", 12, T.TEXT_SECONDARY)
	content_rule_label.name = "Rule"
	content_rule_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content_rule_label.custom_minimum_size.x = 320
	av.add_child(content_rule_label)

	selected_caps = Kit.caps("")
	selected_caps.name = "SelectedCaps"
	v.add_child(_top_gap(selected_caps, 4))
	var sc := _slider_block("Scale", "Escala", 50, 150, 5)
	scale_slider = sc["slider"]
	scale_value_label = sc["value"]
	scale_slider.value_changed.connect(func(val: float) -> void: set_scale_percent(val))
	v.add_child(sc["box"])
	var op := _slider_block("Opacity", "Opacidad fuera de combate", 0, 100, 1)
	opacity_slider = op["slider"]
	opacity_value_label = op["value"]
	opacity_slider.value_changed.connect(func(val: float) -> void: set_opacity_percent(val))
	v.add_child(op["box"])

	v.add_child(_top_gap(Kit.caps("Accesibilidad"), 6))
	v.add_child(Kit.label("Modo de color", 13, T.TEXT_SECONDARY))
	var items: Array = []
	for ch in settings.get_option(S.CAT_ACCESSIBILITY, "color_mode").get("choices", []):
		items.append([ch["value"], str(ch.get("short", ch["label"]))])
	var seg := SK.segmented("ColorMode", items, true)
	color_mode_buttons = seg["buttons"]
	for mode in color_mode_buttons:
		var m := str(mode)
		(color_mode_buttons[m] as Button).pressed.connect(func() -> void: set_color_mode(m))
		SK.a11y_name(color_mode_buttons[m], "Modo de color " + settings.choice_label(S.CAT_ACCESSIBILITY, "color_mode", m))
	v.add_child(seg["panel"])
	for row in A11Y_ROWS:
		var key: String = row[0]
		var h := SK.hbox("A11y_" + key, 10)
		var tv := SK.vbox("Text", 0)
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(tv)
		tv.add_child(Kit.label(row[1], 14, T.TEXT))
		tv.add_child(Kit.label(row[2], 12, T.TEXT_MUTED))
		var sw := SK.Switch.new()
		sw.name = "Switch"
		SK.a11y_name(sw, row[1])
		sw.toggled.connect(func(on: bool) -> void: set_a11y(key, on))
		h.add_child(sw)
		v.add_child(h)
		a11y_switches[key] = sw


func _slider_block(node_name: String, title: String, lo: float, hi: float, step: float) -> Dictionary:
	var box := SK.vbox(node_name, 6)
	var h := SK.hbox("Head", 6)
	box.add_child(h)
	var l := Kit.label(title, 13, T.TEXT)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	var val := Kit.label("", 13, T.TEXT_SECONDARY)
	val.name = "Value"
	h.add_child(val)
	var s := HSlider.new()
	s.name = "Slider"
	s.min_value = lo
	s.max_value = hi
	s.step = step
	SK.style_slider(s)
	SK.a11y_name(s, title)
	box.add_child(s)
	return {"box": box, "slider": s, "value": val}


func _gap(w: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, 0)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _top_gap(c: Control, gap: float) -> Control:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_top", int(gap))
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(c)
	return m


# ==========================================================================
# Arrastre desde el lienzo
# ==========================================================================
func _on_module_press(id: String, local: Vector2) -> void:
	_grab_offset = local
	if editor.begin_drag(id):
		module_selected.emit(id)
		settings.announce("%s seleccionado" % editor.module_label(id))


func _on_module_motion() -> void:
	if editor.is_dragging():
		editor.drag_to(canvas.get_local_mouse_position() - _grab_offset)


func _on_module_release() -> void:
	if editor.is_dragging():
		editor.end_drag()


# ==========================================================================
# Refresco
# ==========================================================================
func refresh() -> void:
	if not _built or editor == null or settings == null:
		return
	var ts: float = settings.text_scale()
	snap_chip.text = "Ajustar a cuadrícula %s" % ("✓" if editor.snap_to_grid else "✗")
	SK.set_chip_active(snap_chip, false)
	undo_chip.disabled = not editor.can_undo()
	undo_chip.modulate.a = 1.0 if editor.can_undo() else 0.6
	var kb := undo_chip.get_node("Kbd") as Control
	kb.position = Vector2(undo_chip.size.x - kb.size.x - 8, (undo_chip.size.y - kb.size.y) * 0.5)
	SK.set_chip_active(combat_chip, editor.simulating_combat)
	grid_layer.visible_grid = editor.snap_to_grid
	grid_layer.queue_redraw()
	for id in module_boxes:
		var mb: ModuleBox = module_boxes[id]
		var r: Rect2 = editor.module_rect(id)
		mb.position = r.position
		mb.size = r.size
		mb.visible = editor.is_module_visible(id)
		mb.title = editor.module_label(id)
		mb.detail = editor.module_detail(id)
		mb.selected = id == editor.selected
		mb.fill_alpha = editor.effective_opacity(id)
		mb.text_scale = ts
		mb.queue_redraw()
	overlay.guides = editor.guides
	overlay.selected_rect = editor.module_rect(editor.selected) if editor.selected != "" else Rect2()
	overlay.text_scale = ts
	overlay.queue_redraw()
	(layout_chip.find_child("Text", true, false) as Label).text = editor.preset_context() + (" · editado" if editor.is_preset_modified() else "")
	if not code_edit.has_focus() and not _code_dirty:
		code_edit.text = editor.share_code()
	if not _code_dirty:
		code_title.text = "Código para compartir"
		code_title.add_theme_color_override("font_color", T.TEXT_SECONDARY)
	for id in preset_chips:
		SK.set_chip_active(preset_chips[id], id == editor.active_preset)
	auto_switch.set_pressed_no_signal(editor.auto_switch_by_content)
	auto_switch.queue_redraw()
	content_rule_label.text = editor.content_rule_text()
	var sel: String = editor.selected
	selected_caps.text = ("Módulo seleccionado · %s" % editor.module_label(sel)).to_upper() if sel != "" else "MÓDULO SELECCIONADO · NINGUNO"
	scale_slider.editable = sel != ""
	opacity_slider.editable = sel != ""
	scale_slider.set_value_no_signal(roundf(editor.module_scale(sel) * 100.0) if sel != "" else 100.0)
	opacity_slider.set_value_no_signal(roundf(editor.module_opacity(sel) * 100.0) if sel != "" else 100.0)
	scale_value_label.text = "%d %%" % roundi(scale_slider.value)
	opacity_value_label.text = "%d %%" % roundi(opacity_slider.value)
	var mode: String = settings.color_mode()
	for m in color_mode_buttons:
		SK.set_segment_active(color_mode_buttons[m], m == mode)
	for key in a11y_switches:
		var sw: SK.Switch = a11y_switches[key]
		sw.set_pressed_no_signal(bool(settings.get_applied(S.CAT_ACCESSIBILITY, key)))
		sw.queue_redraw()
	super.refresh()


# ==========================================================================
# Controles dibujados
# ==========================================================================
## Cuadrícula magnética de 24 px (líneas blancas al 5 %).
class GridLayer extends Control:
	var visible_grid := true

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if not visible_grid:
			return
		var g := float(T.EDITOR_GRID)
		var x := 0.0
		while x <= size.x:
			draw_line(Vector2(x, 0), Vector2(x, size.y), T.EDITOR_GRID_LINE, 1.0)
			x += g
		var y := 0.0
		while y <= size.y:
			draw_line(Vector2(0, y), Vector2(size.x, y), T.EDITOR_GRID_LINE, 1.0)
			y += g


## Rectángulo de un módulo del HUD (arrastrable).
class ModuleBox extends Control:
	var module_id := ""
	var host: Node = null
	var title := ""
	var detail := ""
	var selected := false
	var fill_alpha := 1.0
	var text_scale := 1.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		focus_mode = Control.FOCUS_ALL
		mouse_default_cursor_shape = Control.CURSOR_MOVE

	func _gui_input(event: InputEvent) -> void:
		if host == null:
			return
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				host._on_module_press(module_id, get_local_mouse_position())
			else:
				host._on_module_release()
			accept_event()
		elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
			host._on_module_motion()
			accept_event()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(10)
		sb.anti_aliasing = true
		if selected:
			sb.bg_color = T.EDITOR_SELECTED_BG
			sb.border_color = T.ACCENT_DEFAULT
			sb.set_border_width_all(2)
			sb.expand_margin_left = 2
			sb.expand_margin_right = 2
			sb.expand_margin_top = 2
			sb.expand_margin_bottom = 2
		else:
			var a := lerpf(0.35, 1.0, clampf(fill_alpha, 0.0, 1.0))
			sb.bg_color = Color(T.EDITOR_MODULE_BG, T.EDITOR_MODULE_BG.a * a)
			sb.border_color = T.EDITOR_MODULE_EDGE
			sb.set_border_width_all(1)
		draw_style_box(sb, r)
		var f1 := T.font("semibold")
		var f2 := T.font("medium")
		var s1 := roundi(13 * text_scale)
		var s2 := roundi(11 * text_scale)
		var h1 := f1.get_height(s1)
		var h2 := f2.get_height(s2) if detail != "" else 0.0
		var total := h1 + (2.0 + h2 if detail != "" else 0.0)
		var y := (size.y - total) * 0.5
		var c1 := T.ACCENT_DEFAULT if selected else T.TEXT
		var w1 := f1.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, s1).x
		draw_string(f1, Vector2((size.x - w1) * 0.5, y + f1.get_ascent(s1)), title, HORIZONTAL_ALIGNMENT_LEFT, -1, s1, c1)
		if detail != "":
			var w2 := f2.get_string_size(detail, HORIZONTAL_ALIGNMENT_LEFT, -1, s2).x
			draw_string(f2, Vector2((size.x - w2) * 0.5, y + h1 + 2.0 + f2.get_ascent(s2)), detail, HORIZONTAL_ALIGNMENT_LEFT, -1, s2, T.TEXT_SECONDARY)


## Guías magnéticas (#ff6fa8) y esquinas del módulo seleccionado.
class Overlay extends Control:
	var guides: Array = []
	var selected_rect := Rect2()
	var text_scale := 1.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var f := T.font("medium")
		var fs := roundi(11 * text_scale)
		for g in guides:
			var at := float(g["at"])
			var col: Color = g.get("color", T.EDITOR_GUIDE)
			if str(g["axis"]) == "x":
				draw_line(Vector2(at + 0.5, 0), Vector2(at + 0.5, size.y), col, 1.0)
				var ly := selected_rect.end.y + 8.0 + f.get_ascent(fs)
				draw_string(f, Vector2(at + 6.0, ly), str(g["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
			else:
				draw_line(Vector2(0, at + 0.5), Vector2(size.x, at + 0.5), col, 1.0)
				draw_string(f, Vector2(selected_rect.end.x + 6.0, at - 4.0), str(g["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		if selected_rect.size != Vector2.ZERO:
			var hs := T.EDITOR_HANDLE_SIZE
			var sb := StyleBoxFlat.new()
			sb.bg_color = T.EDITOR_HANDLE
			sb.set_corner_radius_all(2)
			for p in [selected_rect.position, Vector2(selected_rect.end.x, selected_rect.position.y),
					Vector2(selected_rect.position.x, selected_rect.end.y), selected_rect.end]:
				draw_style_box(sb, Rect2(p - Vector2(hs, hs) * 0.5, Vector2(hs, hs)))
