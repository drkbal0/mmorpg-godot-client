extends Node
## TradeService — Trato cara a cara P2P con doble confirmación simétrica (UI v2.4 Paso 11).
## Referencia: design_ref/pantallas_html/MMO-Trato.html · PROMPT_ANTIGRAVITY §2.2 y §2.3.
##
## - Sesión entre el jugador local («local») y la contraparte («remote»): cada lado ofrece
##   objetos (id + cantidad) y oro.
## - Valor de mercado de cada oferta con los precios canónicos del seed
##   (`config/trade/trade_seed.json`) y balance (`balance() > 0` = a favor del jugador local).
## - Máscara del Códice (§2.3.2): lo que la contraparte ofrece y el jugador no conoce en su
##   Códice (`KnowledgeService.is_known`) se muestra como «???» con el borde de su rareza y
##   «Objeto que no has descubierto · épico». Se revela si la contraparte lo enseña
##   (`request_reveal` → `reveal_remote_item`) o al completar el trato (entra al Códice).
## - «Mapa del hallazgo»: quien lo recibe aprende el secreto (ubicación en su mapa y Códice).
## - Seguridad: estados EDITING → CONFIRMED_LOCAL / CONFIRMED_REMOTE → LOCKED_BOTH → COMPLETED.
##   Regla estricta: si cualquiera modifica su oferta (añade/quita objeto, cambia cantidad u
##   oro) se borran AMBAS confirmaciones y hay 3 s de espera antes de poder confirmar.
##   Con LOCKED_BOTH las ofertas quedan bloqueadas hasta cerrar (`complete`) o cancelar.
##
## Instanciable con `.new()` (tests, reloj manual con `tick`) y como autoload `TradeService`.

const DEFAULT_SEED_PATH := "res://config/trade/trade_seed.json"
const LOCAL := "local"
const REMOTE := "remote"
const SIDES: Array[String] = [LOCAL, REMOTE]
const MASK := "???"
const DEFAULT_COOLDOWN_S := 3.0

enum State { EDITING, CONFIRMED_LOCAL, CONFIRMED_REMOTE, LOCKED_BOTH, COMPLETED, CANCELLED }
const STATE_KEYS: Array[String] = ["EDITING", "CONFIRMED_LOCAL", "CONFIRMED_REMOTE", "LOCKED_BOTH", "COMPLETED", "CANCELLED"]

const RARITIES := {
	"common": {"name": "común", "color": "#b8c3ca"},
	"uncommon": {"name": "poco común", "color": "#4fe39a"},
	"rare": {"name": "raro", "color": "#5aa9ff"},
	"epic": {"name": "épico", "color": "#b47bff"},
	"legendary": {"name": "legendario", "color": "#f5a742"},
	"secret": {"name": "secreto", "color": "#c39bff"},
	"gold": {"name": "oro", "color": "#f5c35b"},
}
const COLOR_MASK_NAME := Color("#c39bff")
const COLOR_GOOD := Color("#4fe39a")
const COLOR_MUTED := Color("#9aa6ae")

signal session_started(target_name: String)
signal offer_changed(side: String)
signal confirmations_reset(by_side: String)
signal state_changed(state: int)
signal cooldown_changed(remaining: float)
signal reveal_requested(item_ids: Array)
signal item_revealed(item_id: String)
signal trade_completed(result: Dictionary)
signal trade_cancelled(by_side: String)

## Catálogo con precio canónico: id -> {name, rarity, price, kind, codex_id, secret_id…}
var items: Dictionary = {}
var demo_session: Dictionary = {}
var cooldown_s: float = DEFAULT_COOLDOWN_S
var local_name: String = "Tú"
var local_gold: int = 0
## Códice del jugador local (inyectable). null -> /root/KnowledgeService si existe.
var knowledge: Node = null
var realtime: bool = false

var active: bool = false
var state: int = State.EDITING
var target_name: String = ""
var target_data: Dictionary = {}
var offers: Dictionary = {}
var confirmed: Dictionary = {LOCAL: false, REMOTE: false}
var cooldown_remaining: float = 0.0
var revealed: Dictionary = {}            # item_id -> true (la contraparte lo enseñó)
var reveal_pending: bool = false
var reset_count: int = 0
var last_result: Dictionary = {}
var history: Array[Dictionary] = []


func _init() -> void:
	_clear_session()


func _ready() -> void:
	if items.is_empty() and FileAccess.file_exists(DEFAULT_SEED_PATH):
		load_seed(DEFAULT_SEED_PATH)
	if get_parent() == get_tree().root and name == "TradeService":
		realtime = true
	set_process(realtime)


func _process(delta: float) -> void:
	if realtime and cooldown_remaining > 0.0:
		tick(delta)


func load_seed(path: String = DEFAULT_SEED_PATH) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		return false
	load_from_dict(data)
	return true


func load_from_dict(data: Dictionary) -> void:
	items.clear()
	for id in data.get("items", {}):
		register_item(id, data["items"][id])
	demo_session = (data.get("demo_session", {}) as Dictionary).duplicate(true)
	cooldown_s = float(data.get("cooldown_s", DEFAULT_COOLDOWN_S))
	local_name = str(data.get("local_name", "Tú"))
	local_gold = int(data.get("local_gold", 0))


func register_item(id: String, d: Dictionary) -> void:
	var it := d.duplicate(true)
	it["id"] = id
	it["name"] = str(d.get("name", id))
	it["rarity"] = str(d.get("rarity", "common"))
	it["price"] = int(d.get("price", 0))
	it["kind"] = str(d.get("kind", "item"))
	items[id] = it


func get_item(id: String) -> Dictionary:
	return items.get(id, {})


static func rarity_color(rarity: String) -> Color:
	return Color(RARITIES.get(rarity, RARITIES["common"])["color"])


static func rarity_name(rarity: String) -> String:
	return str(RARITIES.get(rarity, RARITIES["common"])["name"])


static func state_key(s: int) -> String:
	return STATE_KEYS[s] if s >= 0 and s < STATE_KEYS.size() else "UNKNOWN"


# ==========================================================================
# Sesión
# ==========================================================================
func _clear_session() -> void:
	active = false
	state = State.EDITING
	target_name = ""
	target_data = {}
	offers = {LOCAL: {"items": [], "gold": 0}, REMOTE: {"items": [], "gold": 0}}
	confirmed = {LOCAL: false, REMOTE: false}
	cooldown_remaining = 0.0
	revealed.clear()
	reveal_pending = false
	reset_count = 0
	last_result = {}
	history.clear()


## Abre un trato. `data`: distance_m, reputation, remote_offer {items, gold}, local_offer {…}.
## Si `data` está vacío se usa la sesión de demostración del seed (con `target` como nombre).
func start_session(target: String = "Sasha", data: Dictionary = {}) -> bool:
	_clear_session()
	var d := data if not data.is_empty() else demo_session.duplicate(true)
	target_name = target if target != "" else str(d.get("target_name", "Sasha"))
	target_data = d.duplicate(true)
	target_data["distance_m"] = float(d.get("distance_m", 3))
	target_data["reputation"] = str(d.get("reputation", "Desconocida"))
	for side in SIDES:
		var key := side + "_offer"
		var o: Dictionary = d.get(key, {})
		for e in o.get("items", []):
			if items.has(str(e["item_id"])):
				offers[side]["items"].append(_entry(str(e["item_id"]), int(e.get("qty", 1)), e))
		offers[side]["gold"] = max(0, int(o.get("gold", 0)))
	active = true
	_log("start", "")
	session_started.emit(target_name)
	state_changed.emit(state)
	return true


func _entry(item_id: String, qty: int, meta: Dictionary = {}) -> Dictionary:
	var e := {"item_id": item_id, "qty": max(1, qty), "tag": str(meta.get("tag", ""))}
	if meta.has("tag_text"):
		e["tag_text"] = str(meta["tag_text"])
	return e


func header_text() -> String:
	return "Trato con %s" % target_name


## «Cara a cara · a 3 m · reputación: Confiable»
func header_subtitle() -> String:
	var dist := float(target_data.get("distance_m", 0.0))
	var dtxt := ("%d" % int(dist)) if is_equal_approx(dist, round(dist)) else ("%.1f" % dist)
	return "Cara a cara · a %s m · reputación: %s" % [dtxt, str(target_data.get("reputation", "Desconocida"))]


func _log(kind: String, side: String, extra: Dictionary = {}) -> void:
	var e := {"kind": kind, "side": side, "state": state_key(state)}
	e.merge(extra)
	history.append(e)


# ==========================================================================
# Ofertas (cualquier cambio invalida ambas confirmaciones)
# ==========================================================================
func can_modify() -> bool:
	return active and (state == State.EDITING or state == State.CONFIRMED_LOCAL or state == State.CONFIRMED_REMOTE)


func get_offer(side: String) -> Dictionary:
	return offers.get(side, {})


func add_item(side: String, item_id: String, qty: int = 1, meta: Dictionary = {}) -> bool:
	if not can_modify() or not SIDES.has(side) or not items.has(item_id) or qty < 1:
		return false
	var list: Array = offers[side]["items"]
	var tag := str(meta.get("tag", ""))
	var merged := false
	for e in list:
		if e["item_id"] == item_id and e["tag"] == tag:
			e["qty"] = int(e["qty"]) + qty
			merged = true
			break
	if not merged:
		list.append(_entry(item_id, qty, meta))
	_on_modified(side, "add_item")
	return true


func remove_item(side: String, index: int) -> bool:
	if not can_modify() or not SIDES.has(side):
		return false
	var list: Array = offers[side]["items"]
	if index < 0 or index >= list.size():
		return false
	var removed: Dictionary = list[index]
	list.remove_at(index)
	revealed.erase(removed["item_id"])
	_on_modified(side, "remove_item")
	return true


func set_item_qty(side: String, index: int, qty: int) -> bool:
	if not can_modify() or not SIDES.has(side):
		return false
	var list: Array = offers[side]["items"]
	if index < 0 or index >= list.size() or qty < 1 or int(list[index]["qty"]) == qty:
		return false
	list[index]["qty"] = qty
	_on_modified(side, "set_qty")
	return true


func set_gold(side: String, amount: int) -> bool:
	if not can_modify() or not SIDES.has(side) or amount < 0:
		return false
	if side == LOCAL and amount > local_gold:
		return false
	if int(offers[side]["gold"]) == amount:
		return false
	offers[side]["gold"] = amount
	_on_modified(side, "set_gold")
	return true


## Regla estricta: se borran AMBAS confirmaciones y empieza la espera de seguridad.
func _on_modified(side: String, what: String) -> void:
	var had := bool(confirmed[LOCAL]) or bool(confirmed[REMOTE])
	confirmed[LOCAL] = false
	confirmed[REMOTE] = false
	cooldown_remaining = cooldown_s
	reset_count += 1
	var prev := state
	state = State.EDITING
	_log("modify", side, {"what": what, "had_confirmations": had})
	if had:
		confirmations_reset.emit(side)
	if prev != state:
		state_changed.emit(state)
	offer_changed.emit(side)
	cooldown_changed.emit(cooldown_remaining)


func tick(dt: float) -> void:
	if cooldown_remaining <= 0.0:
		return
	cooldown_remaining = maxf(0.0, cooldown_remaining - maxf(0.0, dt))
	if cooldown_remaining < 0.0001:
		cooldown_remaining = 0.0
	cooldown_changed.emit(cooldown_remaining)


func in_cooldown() -> bool:
	return cooldown_remaining > 0.0


# ==========================================================================
# Confirmación
# ==========================================================================
func is_empty_trade() -> bool:
	for side in SIDES:
		if not (offers[side]["items"] as Array).is_empty() or int(offers[side]["gold"]) > 0:
			return false
	return true


## "" si puede confirmar; si no, el motivo.
func confirm_block_reason(side: String) -> String:
	if not active:
		return "no_session"
	if not SIDES.has(side):
		return "invalid_side"
	if state == State.LOCKED_BOTH or state == State.COMPLETED or state == State.CANCELLED:
		return "locked"
	if bool(confirmed[side]):
		return "already_confirmed"
	if in_cooldown():
		return "cooldown"
	if is_empty_trade():
		return "empty_trade"
	return ""


func can_confirm(side: String) -> bool:
	return confirm_block_reason(side) == ""


func confirm(side: String) -> Dictionary:
	var why := confirm_block_reason(side)
	if why != "":
		return {"ok": false, "reason": why}
	confirmed[side] = true
	_update_state()
	_log("confirm", side)
	return {"ok": true, "state": state}


## Retira la confirmación propia (no es un cambio de oferta: no hay espera).
func unconfirm(side: String) -> bool:
	if not active or not SIDES.has(side) or not bool(confirmed[side]):
		return false
	if state == State.LOCKED_BOTH or state == State.COMPLETED or state == State.CANCELLED:
		return false
	confirmed[side] = false
	_update_state()
	_log("unconfirm", side)
	return true


func _update_state() -> void:
	var prev := state
	if confirmed[LOCAL] and confirmed[REMOTE]:
		state = State.LOCKED_BOTH
	elif confirmed[LOCAL]:
		state = State.CONFIRMED_LOCAL
	elif confirmed[REMOTE]:
		state = State.CONFIRMED_REMOTE
	else:
		state = State.EDITING
	if prev != state:
		state_changed.emit(state)


func is_confirmed(side: String) -> bool:
	return bool(confirmed.get(side, false))


## «Sin confirmar» · «Confirmado ✓»
func status_text(side: String) -> String:
	if state == State.COMPLETED:
		return "Hecho ✓"
	return "Confirmado ✓" if is_confirmed(side) else "Sin confirmar"


## Cierra el trato (solo con LOCKED_BOTH): intercambia, actualiza oro y Códice.
func complete() -> Dictionary:
	if state != State.LOCKED_BOTH:
		return {"ok": false, "reason": "not_locked"}
	var learned: Array[String] = []
	var ks := _knowledge()
	for e in offers[REMOTE]["items"]:
		var it := get_item(e["item_id"])
		if ks:
			var cid := str(it.get("codex_id", ""))
			if cid != "" and not ks.is_known(cid):
				ks.learn_entry(cid, str(it.get("codex_category", "objetos")), {"name": it["name"]})
				learned.append(cid)
			if it["kind"] == "discovery_map":
				var sid := str(it.get("secret_id", ""))
				if sid != "" and not ks.is_known(sid):
					ks.learn_entry(sid, str(it.get("secret_category", "lugares")), {"name": str(it.get("secret_name", sid)), "location": it.get("location", {})})
					learned.append(sid)
	var shared: Array[String] = []
	for e in offers[LOCAL]["items"]:
		var it := get_item(e["item_id"])
		if it["kind"] == "discovery_map":
			shared.append(str(it.get("secret_id", "")))
	var delta := int(offers[REMOTE]["gold"]) - int(offers[LOCAL]["gold"])
	local_gold += delta
	state = State.COMPLETED
	last_result = {
		"ok": true, "received": (offers[REMOTE]["items"] as Array).duplicate(true), "given": (offers[LOCAL]["items"] as Array).duplicate(true),
		"gold_delta": delta, "learned": learned, "maps_sold": shared, "balance": balance(),
	}
	_log("complete", "")
	state_changed.emit(state)
	trade_completed.emit(last_result)
	return last_result


func cancel(by_side: String = LOCAL) -> bool:
	if not active or state == State.COMPLETED or state == State.CANCELLED:
		return false
	state = State.CANCELLED
	confirmed[LOCAL] = false
	confirmed[REMOTE] = false
	_log("cancel", by_side)
	state_changed.emit(state)
	trade_cancelled.emit(by_side)
	return true


# ==========================================================================
# Valor de mercado
# ==========================================================================
func market_value(side: String) -> int:
	var o: Dictionary = offers.get(side, {})
	var v := int(o.get("gold", 0))
	for e in o.get("items", []):
		v += int(get_item(e["item_id"]).get("price", 0)) * int(e["qty"])
	return v


## Positivo: el trato está a favor del jugador local según el mercado.
func balance() -> int:
	return market_value(REMOTE) - market_value(LOCAL)


# ==========================================================================
# Máscara del Códice y vistas
# ==========================================================================
func _knowledge() -> Node:
	if knowledge == null and is_inside_tree():
		knowledge = get_node_or_null("/root/KnowledgeService")
	return knowledge


func knows(codex_id: String) -> bool:
	var ks := _knowledge()
	return ks != null and ks.is_known(codex_id)


func is_masked(side: String, item_id: String) -> bool:
	if side != REMOTE or state == State.COMPLETED:
		return false
	var cid := str(get_item(item_id).get("codex_id", ""))
	return cid != "" and not revealed.has(item_id) and not knows(cid)


func masked_remote_ids() -> Array[String]:
	var out: Array[String] = []
	for e in offers[REMOTE]["items"]:
		if is_masked(REMOTE, e["item_id"]) and not out.has(e["item_id"]):
			out.append(e["item_id"])
	return out


func has_masked_remote() -> bool:
	return not masked_remote_ids().is_empty()


## «Pedir que lo enseñe»: no modifica la oferta (no borra confirmaciones).
func request_reveal() -> bool:
	var ids := masked_remote_ids()
	if ids.is_empty() or not active:
		return false
	reveal_pending = true
	_log("request_reveal", LOCAL)
	reveal_requested.emit(ids)
	return true


## La contraparte enseña el objeto: el jugador ve su nombre (queda «Visto de lejos» en el Códice).
func reveal_remote_item(item_id: String) -> bool:
	if not active or revealed.has(item_id):
		return false
	var found := false
	for e in offers[REMOTE]["items"]:
		if e["item_id"] == item_id:
			found = true
	if not found:
		return false
	revealed[item_id] = true
	if masked_remote_ids().is_empty():
		reveal_pending = false
	var ks := _knowledge()
	var cid := str(get_item(item_id).get("codex_id", ""))
	if ks and cid != "" and ks.has_method("mark_seen"):
		ks.mark_seen(cid, str(get_item(item_id).get("codex_category", "objetos")), "Te lo enseñó %s en un trato" % target_name)
	_log("reveal", REMOTE, {"item_id": item_id})
	item_revealed.emit(item_id)
	return true


func _subtitle(side: String, e: Dictionary, it: Dictionary) -> Dictionary:
	if e.has("tag_text"):
		return {"text": str(e["tag_text"]), "color": COLOR_GOOD if e["tag"] == "need" else COLOR_MUTED}
	match str(e.get("tag", "")):
		"workshop":
			return {"text": "De tu taller", "color": COLOR_MUTED}
		"secret_seller":
			return {"text": "Tu secreto · %s verá la ubicación" % target_name, "color": COLOR_MUTED}
	if it["kind"] == "discovery_map":
		if side == REMOTE:
			return {"text": "Verás la ubicación en tu mapa y Códice", "color": COLOR_GOOD}
		return {"text": "Tu secreto · %s verá la ubicación" % target_name, "color": COLOR_MUTED}
	return {"text": "", "color": COLOR_MUTED}


func view_item(side: String, index: int) -> Dictionary:
	var list: Array = offers.get(side, {}).get("items", [])
	if index < 0 or index >= list.size():
		return {}
	var e: Dictionary = list[index]
	var it := get_item(e["item_id"])
	var qty := int(e["qty"])
	var masked := is_masked(side, e["item_id"])
	var v := {
		"item_id": e["item_id"], "qty": qty, "kind": it["kind"], "rarity": it["rarity"],
		"border_color": rarity_color(it["rarity"]), "value": int(it["price"]) * qty, "masked": masked, "is_gold": false,
	}
	if masked:
		v["name"] = MASK
		v["display_name"] = MASK + (" ×%d" % qty if qty > 1 else "")
		v["name_color"] = COLOR_MASK_NAME
		v["subtitle"] = "Objeto que no has descubierto · %s" % rarity_name(it["rarity"])
		v["subtitle_color"] = COLOR_MUTED
		v["icon_text"] = "?"
	else:
		v["name"] = it["name"]
		v["display_name"] = str(it["name"]) + (" ×%d" % qty if qty > 1 else "")
		v["name_color"] = Color("#eef2f4")
		var sub := _subtitle(side, e, it)
		if revealed.has(e["item_id"]) and str(sub["text"]) == "":
			sub = {"text": "Te lo enseñó %s · %s" % [target_name, rarity_name(it["rarity"])], "color": COLOR_MUTED}
		v["subtitle"] = sub["text"]
		v["subtitle_color"] = sub["color"]
		v["icon_text"] = ""
	return v


## Filas de una columna: objetos + oro (si lo hay).
func view_offer(side: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var list: Array = offers.get(side, {}).get("items", [])
	for i in list.size():
		out.append(view_item(side, i))
	var g := int(offers.get(side, {}).get("gold", 0))
	if g > 0:
		out.append({"item_id": "", "qty": g, "kind": "gold", "rarity": "gold", "border_color": rarity_color("gold"),
			"value": g, "masked": false, "is_gold": true, "name": "%s oro" % fmt(g), "display_name": "%s oro" % fmt(g),
			"name_color": Color("#eef2f4"), "subtitle": "", "subtitle_color": COLOR_MUTED, "icon_text": ""})
	return out


## Mensaje inferior dinámico.
func info_text() -> String:
	var parts: Array[String] = []
	match state:
		State.COMPLETED:
			parts.append("Trato cerrado con %s." % target_name)
			var learned: Array = last_result.get("learned", [])
			if not learned.is_empty():
				parts.append("Lo que no conocías ya está en tu Códice.")
			return " ".join(parts)
		State.CANCELLED:
			return "Trato cancelado. Nadie entregó nada."
		State.LOCKED_BOTH:
			parts.append("Los dos habéis confirmado: el trato está bloqueado y listo para cerrarse.")
	if in_cooldown() and state != State.LOCKED_BOTH:
		parts.append("La oferta cambió: las confirmaciones se borraron, espera %d s para confirmar." % int(ceil(cooldown_remaining)))
	if has_masked_remote():
		if reveal_pending:
			parts.append("Has pedido a %s que te enseñe lo que no conoces («???»)." % target_name)
		else:
			parts.append("Te ofrecen algo que no conoces («???»). Verás su nombre solo si aceptas, o si %s te lo enseña antes." % target_name)
	var b := balance()
	if b > 0:
		parts.append("El trato está %s oro a tu favor según el mercado." % fmt(b))
	elif b < 0:
		parts.append("El trato está %s oro en tu contra según el mercado." % fmt(-b))
	else:
		parts.append("El trato está equilibrado según el mercado.")
	return " ".join(parts)


static func fmt(n: int) -> String:
	var s := str(abs(n))
	var out := ""
	while s.length() > 3:
		out = "." + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out
