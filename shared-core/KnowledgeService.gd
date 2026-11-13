extends Node
## KnowledgeService — estado de conocimiento por jugador (UI v2.4, PROMPT_ANTIGRAVITY §2.3 y §4).
##
## Servicio ÚNICO: todas las vistas (Códice, tooltips, mapa, chat, inventario) lo
## consultan; ninguna decide por su cuenta si algo es conocido.
##
## Estados canónicos de visibilidad:
##   UNKNOWN (0)       No descubierto. `display_name()` = «???».
##   SEEN (1)          «Visto de lejos»: categoría y pista conocidas; nombre «???».
##   KNOWN_SECRET (2)  Descubierto y guardado en secreto: nombre, ubicación y
##                     «Mapas del hallazgo» vendibles.
##   PUBLISHED (3)     Publicado en la wiki web (mmo.elbalo.lol/wiki). PERMANENTE.
##
## Flujo: `discover_entry()` -> bandeja «Por decidir» (secreto provisional) ->
## `decide_entry(id, publish)` -> KNOWN_SECRET o PUBLISHED (+ oro y título pionero).
##
## También lleva el panel de Inversiones del Códice (§2.3.7-8): participaciones en
## PNJ/tiendas descubiertas, ingresos por transacción, histórico de 14 días y cobro
## al almacén del refugio.
##
## Registrado como autoload `KnowledgeService`; también se puede instanciar con
## `.new()` (tests, previsualizaciones) porque no depende de otros autoloads.

const GameConfigScript = preload("res://config/game_config.gd")

enum Visibility { UNKNOWN = 0, SEEN = 1, KNOWN_SECRET = 2, PUBLISHED = 3 }

const UNKNOWN := Visibility.UNKNOWN
const SEEN := Visibility.SEEN
const KNOWN_SECRET := Visibility.KNOWN_SECRET
const PUBLISHED := Visibility.PUBLISHED

const MASK := "???"
const VISIBILITY_KEYS := ["unknown", "seen", "known_secret", "published"]
const DEFAULT_PUBLISH_BONUS := 500
const DEFAULT_PIONEER_TITLE := "Pionero"
const HISTORY_DAYS := 14
const OFFER_THINK_DAYS := 7
const DEFAULT_SEED_PATH := "res://config/knowledge/codex_seed.json"
const WIKI_PUBLISH_ENDPOINT := "/api/wiki/publish"

## Categorías del Códice (sub-navegación «Entradas»). Abierta: el seed puede añadir más.
const DEFAULT_CATEGORIES: Array[Dictionary] = [
	{"id": "criaturas", "label": "Criaturas"},
	{"id": "objetos", "label": "Objetos"},
	{"id": "lugares", "label": "Lugares"},
	{"id": "formulas", "label": "Fórmulas"},
	{"id": "pnj", "label": "PNJ"},
]

signal visibility_changed(id: String, old_visibility: int, new_visibility: int)
signal entry_discovered(id: String)
signal entry_decided(id: String, published: bool)
signal pending_changed(count: int)
signal gold_awarded(amount: int, reason: String)
signal discovery_map_generated(map_item: Dictionary)
signal wiki_publish_requested(id: String, payload: Dictionary)
signal notice_added(notice: Dictionary)
signal investments_changed
signal payout_collected(amount: int)

## Nombre con el que firma el jugador en la wiki (pionero).
var player_name: String = "Tú"
## Si es true, publicar hace POST a la wiki web. En headless/tests queda apagado.
var wiki_sync_enabled: bool = DisplayServer.get_name() != "headless"
## Reloj inyectable (segundos Unix) para tests deterministas. < 0 = reloj real.
var clock_override: int = -1

var categories: Array[Dictionary] = []
## Oro total concedido por el servicio (publicaciones + cobros). El saldo real vive
## en el servicio de economía; aquí queda el registro para la UI y QA.
var gold_earned: int = 0
var transactions: Array[Dictionary] = []
var notices: Array[Dictionary] = []
var titles: Array[String] = []

var _entries: Dictionary = {}     # id -> Dictionary
var _pending: Array[String] = []  # ids en «Por decidir», orden de llegada
var _map_serial: int = 0

# Inversiones
var investments: Array[Dictionary] = []
var offers: Array[Dictionary] = []
var pending_payout: int = 0
var total_collected: int = 0
var map_sales: Dictionary = {"listed": 0, "sold": 0, "gold": 0}


func _init() -> void:
	reset()


func _ready() -> void:
	if _entries.is_empty() and FileAccess.file_exists(DEFAULT_SEED_PATH):
		load_seed(DEFAULT_SEED_PATH)


## Vacía todo el estado (tests, cambio de personaje).
func reset() -> void:
	categories.clear()
	for c in DEFAULT_CATEGORIES:
		categories.append(c.duplicate())
	_entries.clear()
	_pending.clear()
	_map_serial = 0
	gold_earned = 0
	transactions.clear()
	notices.clear()
	titles.clear()
	investments.clear()
	offers.clear()
	pending_payout = 0
	total_collected = 0
	map_sales = {"listed": 0, "sold": 0, "gold": 0}


# ==========================================================================
# Consulta (API canónica §4)
# ==========================================================================
func get_visibility(id: String) -> int:
	var e: Dictionary = _entries.get(id, {})
	return int(e.get("visibility", UNKNOWN))


## Alias de §4: `visibility(id)` devuelve la clave textual.
func visibility_key(id: String) -> String:
	return VISIBILITY_KEYS[get_visibility(id)]


func is_known(id: String) -> bool:
	var v := get_visibility(id)
	return v == KNOWN_SECRET or v == PUBLISHED


func is_pending(id: String) -> bool:
	return _pending.has(id)


func is_pioneer(id: String) -> bool:
	return get_visibility(id) == PUBLISHED and bool(_entries[id].get("is_pioneer", false))


## «???» si UNKNOWN o SEEN. Si es conocido: nombre registrado, o `fallback_name`, o el id.
func display_name(id: String, fallback_name: String = "") -> String:
	if not is_known(id):
		return MASK
	var n := str(_entries[id].get("name", ""))
	if n != "":
		return n
	return fallback_name if fallback_name != "" else id


## Pista para «Visto de lejos» (p. ej. «Visto en un cofre de Ferrum»). Vacía si UNKNOWN.
func display_hint(id: String) -> String:
	var v := get_visibility(id)
	if v == UNKNOWN:
		return ""
	return str(_entries[id].get("hint", ""))


## Descripción: solo si se conoce.
func display_description(id: String) -> String:
	return str(_entries[id].get("description", "")) if is_known(id) else MASK


## Categoría: visible desde SEEN (silueta), oculta si UNKNOWN.
func display_category(id: String) -> String:
	if get_visibility(id) == UNKNOWN:
		return MASK
	return str(_entries[id].get("category", ""))


func category_label(category_id: String) -> String:
	for c in categories:
		if c["id"] == category_id:
			return str(c["label"])
	return category_id.capitalize()


## Vista segura de una entrada (los campos sensibles se enmascaran según visibilidad).
func get_entry_view(id: String) -> Dictionary:
	var v := get_visibility(id)
	var e: Dictionary = _entries.get(id, {})
	var known := v >= KNOWN_SECRET
	var view := {
		"id": id,
		"visibility": v,
		"visibility_key": VISIBILITY_KEYS[v],
		"name": display_name(id),
		"category": display_category(id),
		"hint": display_hint(id),
		"description": display_description(id),
		"subtitle": str(e.get("subtitle", "")) if known else str(e.get("hint", "")),
		"pending": is_pending(id),
		"is_pioneer": is_pioneer(id),
		"exclusive": bool(e.get("exclusive", true)),
		"discovered_at": int(e.get("discovered_at", 0)),
		"published_at": int(e.get("published_at", 0)),
		"pioneer_name": str(e.get("pioneer_name", "")) if v == PUBLISHED else "",
		"publish_bonus": int(e.get("publish_bonus", DEFAULT_PUBLISH_BONUS)),
		"pioneer_title": str(e.get("pioneer_title", DEFAULT_PIONEER_TITLE)),
		"wiki_synced": bool(e.get("wiki_synced", false)),
		"wiki_url": wiki_url(id) if v == PUBLISHED else "",
		"location": (e.get("location", {}) as Dictionary).duplicate(true) if known else {},
	}
	return view


## Entradas del jugador (SEEN o más). Nunca devuelve entradas UNKNOWN.
## `category` "" = todas; `query` filtra por nombre visible.
func list_entries(category: String = "", query: String = "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var q := query.strip_edges().to_lower()
	for id in _entries:
		var v := get_visibility(id)
		if v == UNKNOWN:
			continue
		if category != "" and str(_entries[id].get("category", "")) != category:
			continue
		var view := get_entry_view(id)
		if q != "" and not str(view["name"]).to_lower().contains(q):
			continue
		out.append(view)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["discovered_at"] != b["discovered_at"]:
			return a["discovered_at"] > b["discovered_at"]
		return str(a["id"]) < str(b["id"]))
	return out


## Descubrimientos PROPIOS por categoría (conocidos). Regla de diseño: nunca se
## expone el total del mundo; este servicio no tiene método para ello.
func count_discovered(category: String = "") -> int:
	var n := 0
	for id in _entries:
		if not is_known(id):
			continue
		if category == "" or str(_entries[id].get("category", "")) == category:
			n += 1
	return n


func get_status_counts() -> Dictionary:
	var c := {"secrets": 0, "published": 0, "pioneer": 0, "seen": 0, "pending": _pending.size()}
	for id in _entries:
		match get_visibility(id):
			SEEN:
				c["seen"] += 1
			KNOWN_SECRET:
				if not is_pending(id):
					c["secrets"] += 1
			PUBLISHED:
				c["published"] += 1
				if is_pioneer(id):
					c["pioneer"] += 1
	return c


func get_secrets() -> Array[Dictionary]:
	return _filter_views(func(id: String) -> bool: return get_visibility(id) == KNOWN_SECRET and not is_pending(id))


func get_published() -> Array[Dictionary]:
	var out := _filter_views(func(id: String) -> bool: return get_visibility(id) == PUBLISHED)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["published_at"] > b["published_at"])
	return out


func get_pending() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in _pending:
		out.append(get_entry_view(id))
	return out


func get_pending_ids() -> Array[String]:
	return _pending.duplicate()


# ==========================================================================
# Mutación
# ==========================================================================
## Registra una entidad del mundo (catálogo). No la descubre: queda UNKNOWN salvo
## que se pase otra visibilidad (carga de partida guardada).
func register_entry(id: String, category: String, data: Dictionary = {}, visibility: int = UNKNOWN) -> void:
	var e: Dictionary = _entries.get(id, {})
	e["id"] = id
	e["category"] = category
	for k in data:
		e[k] = data[k]
	if not e.has("visibility"):
		e["visibility"] = UNKNOWN
	_entries[id] = e
	if visibility != UNKNOWN:
		_set_visibility(id, visibility)


## «Visto de lejos». Solo sube de UNKNOWN a SEEN.
func mark_seen(id: String, category: String = "", hint: String = "") -> bool:
	if get_visibility(id) != UNKNOWN:
		return false
	_ensure(id, category)
	if hint != "":
		_entries[id]["hint"] = hint
	_set_visibility(id, SEEN)
	return true


## Descubre una entrada y la deja en «Por decidir» como secreto provisional.
## `metadata`: name, subtitle, description, location {zone, coords:[x,y,z]},
## publish_bonus, pioneer_title, tags…
func discover_entry(id: String, category: String, metadata: Dictionary = {}) -> Dictionary:
	if id == "":
		return {"ok": false, "reason": "invalid_id"}
	if is_known(id):
		return {"ok": false, "reason": "already_known", "visibility": get_visibility(id)}
	_ensure(id, category)
	var e: Dictionary = _entries[id]
	for k in metadata:
		e[k] = metadata[k]
	if category != "":
		e["category"] = category
	e["discovered_at"] = now()
	e["exclusive"] = bool(metadata.get("exclusive", true))
	if not _pending.has(id):
		_pending.append(id)
	_set_visibility(id, KNOWN_SECRET)
	entry_discovered.emit(id)
	pending_changed.emit(_pending.size())
	return {"ok": true, "id": id, "visibility": KNOWN_SECRET, "pending": true}


## Resuelve la decisión. publish=false -> KNOWN_SECRET consolidado.
## publish=true -> PUBLISHED, bonus de oro y título de pionero. Publicar es
## permanente: con publish=false sobre algo publicado devuelve error.
## Un secreto ya consolidado puede publicarse cuando quiera el jugador.
func decide_entry(id: String, publish: bool) -> Dictionary:
	var v := get_visibility(id)
	if v == PUBLISHED:
		return {"ok": false, "reason": "already_published" if publish else "published_is_permanent", "visibility": PUBLISHED}
	if v != KNOWN_SECRET:
		return {"ok": false, "reason": "not_discovered", "visibility": v}
	var was_pending := _pending.has(id)
	_pending.erase(id)
	var result := {"ok": true, "id": id, "gold": 0, "title": ""}
	if publish:
		var e: Dictionary = _entries[id]
		var bonus := int(e.get("publish_bonus", DEFAULT_PUBLISH_BONUS))
		var title := str(e.get("pioneer_title", DEFAULT_PIONEER_TITLE))
		e["published_at"] = now()
		e["is_pioneer"] = true
		e["pioneer_name"] = player_name
		e["wiki_synced"] = false
		_set_visibility(id, PUBLISHED)
		_award_gold(bonus, "publish:" + id)
		if title != "" and not titles.has(title):
			titles.append(title)
		result["gold"] = bonus
		result["title"] = title
		result["wiki_url"] = wiki_url(id)
		_request_wiki_publish(id)
	result["visibility"] = get_visibility(id)
	if was_pending:
		pending_changed.emit(_pending.size())
	entry_decided.emit(id, publish)
	return result


func publish_entry(id: String) -> Dictionary:
	return decide_entry(id, true)


## Aprende algo sin ser descubridor (Mapa del hallazgo comprado, Hoja de
## descubrimiento): KNOWN_SECRET directo, sin bandeja ni pionero.
func learn_entry(id: String, category: String = "", metadata: Dictionary = {}) -> Dictionary:
	if is_known(id):
		return {"ok": false, "reason": "already_known", "visibility": get_visibility(id)}
	_ensure(id, category)
	for k in metadata:
		_entries[id][k] = metadata[k]
	_entries[id]["discovered_at"] = now()
	_entries[id]["exclusive"] = false
	_set_visibility(id, KNOWN_SECRET)
	return {"ok": true, "id": id, "visibility": KNOWN_SECRET}


## Cambio directo de visibilidad (sincronización con servidor). Nunca rebaja PUBLISHED.
func set_visibility(id: String, v: int) -> bool:
	if v < UNKNOWN or v > PUBLISHED:
		return false
	if get_visibility(id) == PUBLISHED and v != PUBLISHED:
		return false
	_ensure(id, "")
	if v < KNOWN_SECRET and _pending.has(id):
		_pending.erase(id)
		pending_changed.emit(_pending.size())
	_set_visibility(id, v)
	return true


## Otro jugador encontró el secreto: deja de ser exclusivo (baja el valor de los mapas).
func mark_secret_shared(id: String, by_player: String = "") -> bool:
	if get_visibility(id) != KNOWN_SECRET or not bool(_entries[id].get("exclusive", true)):
		return false
	_entries[id]["exclusive"] = false
	_add_notice("secret_shared", id, "Tu secreto ya no es exclusivo",
		"Otro jugador%s encontró «%s». Tu mapa del hallazgo bajó de precio." % [
			(" (" + by_player + ")") if by_player != "" else "", display_name(id)])
	return true


## Otro jugador publicó antes: pasa a PUBLISHED sin título de pionero ni bonus.
func mark_published_by_other(id: String, pioneer_name: String) -> bool:
	var v := get_visibility(id)
	if v == PUBLISHED:
		return false
	_ensure(id, "")
	var was_secret := v == KNOWN_SECRET
	if _pending.has(id):
		_pending.erase(id)
		pending_changed.emit(_pending.size())
	_entries[id]["is_pioneer"] = false
	_entries[id]["pioneer_name"] = pioneer_name
	_entries[id]["published_at"] = now()
	_entries[id]["wiki_synced"] = true
	_set_visibility(id, PUBLISHED)
	if was_secret:
		_add_notice("pioneer_lost", id, "Otro jugador publicó tu secreto",
			"%s publicó «%s» en la wiki antes que tú: ya no puedes ser su pionero." % [pioneer_name, display_name(id)])
	return true


# ==========================================================================
# Mapa del hallazgo
# ==========================================================================
## Genera el ítem comercializable con las coordenadas exactas. Solo sobre
## secretos conocidos (KNOWN_SECRET, ya decididos o provisionales).
func generate_discovery_map(id: String) -> Dictionary:
	var v := get_visibility(id)
	if v == PUBLISHED:
		return {"ok": false, "reason": "already_published"}
	if v != KNOWN_SECRET:
		return {"ok": false, "reason": "not_a_known_secret"}
	var e: Dictionary = _entries[id]
	var loc: Dictionary = e.get("location", {})
	if loc.is_empty() or not loc.has("coords"):
		return {"ok": false, "reason": "no_location"}
	_map_serial += 1
	var exclusive := bool(e.get("exclusive", true))
	var base_price := int(e.get("map_base_price", 300))
	var item := {
		"id": "discovery_map_%s_%d" % [id, _map_serial],
		"item_type": "discovery_map",
		"display_name": "Mapa del hallazgo: %s" % display_name(id),
		"entry_id": id,
		"category": str(e.get("category", "")),
		"zone": str(loc.get("zone", "")),
		"coords": (loc["coords"] as Array).duplicate(),
		"exclusive": exclusive,
		"tradeable": true,
		"suggested_price": base_price if exclusive else int(base_price * 0.5),
		"created_by": player_name,
		"created_at": now(),
		"icon_path": "res://assets/icons/items/scroll1x1.png",
		"grid_width": 1,
		"grid_height": 1,
	}
	e["maps_created"] = int(e.get("maps_created", 0)) + 1
	map_sales["listed"] = int(map_sales["listed"]) + 1
	discovery_map_generated.emit(item)
	return {"ok": true, "item": item}


## Venta de un mapa del hallazgo en el mercado (contabilidad del panel Inversiones).
func record_map_sale(price: int) -> void:
	map_sales["sold"] = int(map_sales["sold"]) + 1
	map_sales["gold"] = int(map_sales["gold"]) + max(0, price)
	_award_gold(max(0, price), "map_sale")


# ==========================================================================
# Wiki web
# ==========================================================================
func wiki_url(id: String) -> String:
	return "%s/wiki/%s" % [GameConfigScript.get_web_url(), id.uri_encode()]


func wiki_payload(id: String) -> Dictionary:
	var e: Dictionary = _entries.get(id, {})
	return {
		"slug": id,
		"name": display_name(id),
		"category": str(e.get("category", "")),
		"description": str(e.get("description", "")),
		"zone": str((e.get("location", {}) as Dictionary).get("zone", "")),
		"pioneer": str(e.get("pioneer_name", player_name)),
		"discovered_at": int(e.get("discovered_at", 0)),
		"published_at": int(e.get("published_at", 0)),
		"status": "published",
	}


func mark_wiki_synced(id: String, synced: bool = true) -> void:
	if _entries.has(id):
		_entries[id]["wiki_synced"] = synced


func _request_wiki_publish(id: String) -> void:
	var payload := wiki_payload(id)
	wiki_publish_requested.emit(id, payload)
	if not wiki_sync_enabled or not is_inside_tree():
		return
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(_r: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
		mark_wiki_synced(id, code >= 200 and code < 300)
		http.queue_free())
	var err := http.request(GameConfigScript.get_web_url() + WIKI_PUBLISH_ENDPOINT,
		["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(payload))
	if err != OK:
		http.queue_free()


# ==========================================================================
# Inversiones (§2.3.7-8)
# ==========================================================================
## data: id, name, zone, share (0.02 = 2 %), status ("active"|"low_traffic"|"paused"|"mission"),
## traffic (0..1), history (Array de hasta 14 ingresos diarios; el último es «hoy»),
## mission_step / mission_steps, market_value.
func add_investment(data: Dictionary) -> void:
	var inv := data.duplicate(true)
	inv["share"] = float(inv.get("share", 0.0))
	inv["status"] = str(inv.get("status", "active"))
	inv["traffic"] = clampf(float(inv.get("traffic", 0.0)), 0.0, 1.0)
	var hist: Array = inv.get("history", [])
	var norm: Array[int] = []
	for i in HISTORY_DAYS:
		var src := hist.size() - HISTORY_DAYS + i
		norm.append(int(hist[src]) if src >= 0 else 0)
	inv["history"] = norm
	for i in investments.size():
		if investments[i]["id"] == inv["id"]:
			investments[i] = inv
			investments_changed.emit()
			return
	investments.append(inv)
	investments_changed.emit()


func get_investment(inv_id: String) -> Dictionary:
	for inv in investments:
		if inv["id"] == inv_id:
			return inv
	return {}


func is_investment_earning(inv: Dictionary) -> bool:
	return inv.get("status", "") in ["active", "low_traffic"] and float(inv.get("share", 0.0)) > 0.0


## Transacción de CUALQUIER jugador con ese PNJ. Devuelve la parte del socio.
func record_transaction(inv_id: String, amount: int) -> int:
	var inv := get_investment(inv_id)
	if inv.is_empty() or amount <= 0 or not is_investment_earning(inv):
		return 0
	var cut := int(floor(amount * float(inv["share"])))
	if cut <= 0:
		return 0
	var h: Array = inv["history"]
	h[HISTORY_DAYS - 1] = int(h[HISTORY_DAYS - 1]) + cut
	pending_payout += cut
	transactions.append({"type": "investment", "investment": inv_id, "amount": amount, "cut": cut, "at": now()})
	investments_changed.emit()
	return cut


## Cierra el día: desplaza el histórico de todas las inversiones.
func advance_day() -> void:
	for inv in investments:
		var h: Array = inv["history"]
		h.pop_front()
		h.append(0)
	for o in offers:
		o["expires_in_days"] = int(o.get("expires_in_days", OFFER_THINK_DAYS)) - 1
	offers.assign(offers.filter(func(o: Dictionary) -> bool: return int(o["expires_in_days"]) > 0))
	investments_changed.emit()


## Serie diaria agregada de los últimos 14 días (último = hoy).
func get_earnings_history() -> Array[int]:
	var out: Array[int] = []
	out.resize(HISTORY_DAYS)
	out.fill(0)
	for inv in investments:
		var h: Array = inv["history"]
		for i in HISTORY_DAYS:
			out[i] += int(h[i])
	return out


func get_investment_summary() -> Dictionary:
	var hist := get_earnings_history()
	var today := hist[HISTORY_DAYS - 1]
	var yesterday := hist[HISTORY_DAYS - 2]
	var week := 0
	for i in range(HISTORY_DAYS - 7, HISTORY_DAYS):
		week += hist[i]
	var active := 0
	var value := 0
	for inv in investments:
		if is_investment_earning(inv):
			active += 1
		value += int(inv.get("market_value", 0))
	var change := 0.0
	if yesterday > 0:
		change = float(today - yesterday) / float(yesterday) * 100.0
	return {
		"today": today, "yesterday": yesterday, "change_pct": change, "week": week,
		"active_count": active, "portfolio_value": value, "pending_payout": pending_payout,
		"total_collected": total_collected, "history": hist,
		"published_count": get_status_counts()["published"],
	}


## «Cobrar al Refugio»: envía lo pendiente al almacén del refugio.
func collect_to_shelter() -> Dictionary:
	if pending_payout <= 0:
		return {"ok": false, "reason": "nothing_to_collect", "amount": 0}
	var amount := pending_payout
	pending_payout = 0
	total_collected += amount
	_award_gold(amount, "investment_payout")
	payout_collected.emit(amount)
	investments_changed.emit()
	return {"ok": true, "amount": amount, "destination": "shelter_storage"}


func add_offer(offer: Dictionary) -> void:
	var o := offer.duplicate(true)
	o["expires_in_days"] = int(o.get("expires_in_days", OFFER_THINK_DAYS))
	offers.append(o)
	investments_changed.emit()


# ==========================================================================
# Persistencia / seed (todo dirigido por datos)
# ==========================================================================
func load_seed(path: String = DEFAULT_SEED_PATH) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var data = JSON.parse_string(f.get_as_text())
	if not (data is Dictionary):
		push_warning("[KnowledgeService] Seed inválido: %s" % path)
		return false
	load_from_dict(data)
	return true


func load_from_dict(data: Dictionary) -> void:
	if data.has("player_name"):
		player_name = str(data["player_name"])
	if data.has("categories"):
		categories.clear()
		for c in data["categories"]:
			categories.append({"id": str(c["id"]), "label": str(c["label"])})
	for raw in data.get("entries", []):
		var e: Dictionary = (raw as Dictionary).duplicate(true)
		var vis = e.get("visibility", UNKNOWN)
		var v: int = VISIBILITY_KEYS.find(vis) if vis is String else int(vis)
		e.erase("visibility")
		var pending := bool(e.get("pending", false))
		e.erase("pending")
		register_entry(str(e["id"]), str(e.get("category", "")), e, maxi(v, UNKNOWN))
		if pending and v == KNOWN_SECRET and not _pending.has(e["id"]):
			_pending.append(str(e["id"]))
	for inv in data.get("investments", []):
		add_investment(inv)
	for o in data.get("offers", []):
		add_offer(o)
	for n in data.get("notices", []):
		notices.append((n as Dictionary).duplicate())
	pending_payout = int(data.get("pending_payout", pending_payout))
	if data.has("map_sales"):
		map_sales = (data["map_sales"] as Dictionary).duplicate()
	pending_changed.emit(_pending.size())
	investments_changed.emit()


func to_dict() -> Dictionary:
	var entries: Array = []
	for id in _entries:
		var e: Dictionary = (_entries[id] as Dictionary).duplicate(true)
		e["visibility"] = VISIBILITY_KEYS[int(e.get("visibility", UNKNOWN))]
		e["pending"] = _pending.has(id)
		entries.append(e)
	return {
		"player_name": player_name, "categories": categories.duplicate(true), "entries": entries,
		"investments": investments.duplicate(true), "offers": offers.duplicate(true),
		"notices": notices.duplicate(true), "pending_payout": pending_payout,
		"map_sales": map_sales.duplicate(),
	}


func now() -> int:
	return clock_override if clock_override >= 0 else int(Time.get_unix_time_from_system())


static func format_date(unix: int) -> String:
	if unix <= 0:
		return "—"
	var d := Time.get_date_dict_from_unix_time(unix)
	const MONTHS := ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"]
	return "%d %s %d" % [d["day"], MONTHS[int(d["month"]) - 1], d["year"]]


# ==========================================================================
# Internos
# ==========================================================================
func _ensure(id: String, category: String) -> void:
	if not _entries.has(id):
		_entries[id] = {"id": id, "category": category, "visibility": UNKNOWN}
	elif category != "" and str(_entries[id].get("category", "")) == "":
		_entries[id]["category"] = category


func _set_visibility(id: String, v: int) -> void:
	var old := int(_entries[id].get("visibility", UNKNOWN))
	if old == v:
		return
	_entries[id]["visibility"] = v
	visibility_changed.emit(id, old, v)


func _award_gold(amount: int, reason: String) -> void:
	if amount <= 0:
		return
	gold_earned += amount
	transactions.append({"type": "gold", "amount": amount, "reason": reason, "at": now()})
	gold_awarded.emit(amount, reason)


func _add_notice(kind: String, id: String, title: String, body: String) -> void:
	var n := {"kind": kind, "entry_id": id, "title": title, "body": body, "at": now()}
	notices.push_front(n)
	notice_added.emit(n)


func _filter_views(pred: Callable) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in _entries:
		if pred.call(id):
			out.append(get_entry_view(id))
	return out
