extends Node
## WorldMapService — mapa del mundo, niebla de guerra y viajes (UI v2.4 Paso 9).
## Referencias: design_ref/pantallas_html/MMO-Mapa.html y MMO-Viajes.html.
##
## - Regiones con niebla: las no exploradas se muestran como «???» y ocultan sus
##   puntos de interés (salvo tus secretos: lo que sabes, lo sabes).
## - Marcadores: PNJ (Gildas, Torin), jefes (Val'Gorath), entrada a El Nido, postas,
##   portales, mazmorras y secretos personales leídos de `KnowledgeService`.
## - Viajes SIN teletransporte: cada destino se alcanza con un modo (caravana, montura,
##   atajo a pie, dirigible o la puerta de El Nido desde zona segura). Tiempo, coste en
##   oro y riesgo se calculan de forma determinista a partir de los datos:
##     minutos = ceil(distancia_km × factor_camino / velocidad_kmh × 60)   (o fixed_min)
##     coste   = coste_base + round(coste_por_km × distancia_km)
##     riesgo  = riesgo_modo + (riesgo_brecha si cruza una brecha y no va escoltado)
##
## Instanciable con `.new()` y registrado como autoload `WorldMapService`.

const DEFAULT_SEED_PATH := "res://config/world/world_map_seed.json"
const KNOWN_SECRET := 2
const RISK_SAFE_MAX := 0.15
const RISK_MEDIUM_MAX := 0.35
const MARKER_KINDS: Array[String] = ["quest", "npc", "boss", "shelter", "secret", "post", "portal", "dungeon"]

signal map_changed
signal region_explored(region_id: String)
signal travel_booked(trip: Dictionary)
signal travel_arrived(destination_id: String)

var map_size := Vector2(2000, 1300)
var world_origin := Vector2(1000, 860)
var world_scale := 1.2
var breach_risk := 0.1
var current_location: String = ""

var regions: Array[Dictionary] = []
var pois: Array[Dictionary] = []
var labels: Array[Dictionary] = []
var modes: Array[Dictionary] = []
var locations: Array[Dictionary] = []
var destinations: Array[Dictionary] = []
var events: Array[Dictionary] = []
var active_trip: Dictionary = {}
var trip_log: Array[Dictionary] = []

var _knowledge: Node = null


func _init() -> void:
	reset()


func _ready() -> void:
	if regions.is_empty() and FileAccess.file_exists(DEFAULT_SEED_PATH):
		load_seed(DEFAULT_SEED_PATH)
	if _knowledge == null:
		var ks := get_node_or_null("/root/KnowledgeService")
		if ks:
			connect_knowledge(ks)


func reset() -> void:
	regions.clear()
	pois.clear()
	labels.clear()
	modes.clear()
	locations.clear()
	destinations.clear()
	events.clear()
	active_trip = {}
	trip_log.clear()
	current_location = ""


func load_seed(path: String = DEFAULT_SEED_PATH) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var data = JSON.parse_string(f.get_as_text())
	if not (data is Dictionary):
		push_warning("[WorldMapService] Seed inválido: %s" % path)
		return false
	load_from_dict(data)
	return true


func load_from_dict(data: Dictionary) -> void:
	reset()
	var ms: Array = data.get("map_size", [2000, 1300])
	map_size = Vector2(float(ms[0]), float(ms[1]))
	var w2m: Dictionary = data.get("world_to_map", {})
	var o: Array = w2m.get("origin", [map_size.x * 0.5, map_size.y * 0.5])
	world_origin = Vector2(float(o[0]), float(o[1]))
	world_scale = float(w2m.get("scale", 1.0))
	breach_risk = float(data.get("breach_risk", 0.1))
	current_location = str(data.get("current_location", ""))
	for key in ["regions", "pois", "labels", "modes", "locations", "destinations", "events"]:
		var target: Array[Dictionary] = get(key)
		for it in data.get(key, []):
			target.append((it as Dictionary).duplicate(true))
	map_changed.emit()


func connect_knowledge(ks: Node) -> void:
	if ks == null or ks == _knowledge:
		return
	_knowledge = ks
	for sig in ["entry_discovered", "visibility_changed"]:
		if ks.has_signal(sig):
			var cb := Callable(self, "_on_knowledge_changed")
			if not ks.is_connected(sig, cb):
				ks.connect(sig, cb)
	map_changed.emit()


func _on_knowledge_changed(_a = null, _b = null, _c = null) -> void:
	map_changed.emit()


func _is_known(entry_id: String) -> bool:
	return _knowledge != null and _knowledge.is_known(entry_id)


# ==========================================================================
# Coordenadas
# ==========================================================================
## Coordenadas del mundo 3D (x, y, z) → plano del mapa (x, z).
func world_to_map(coords: Array) -> Vector2:
	if coords.size() < 2:
		return Vector2.ZERO
	var z: float = float(coords[2]) if coords.size() >= 3 else float(coords[1])
	return world_origin + Vector2(float(coords[0]), z) * world_scale


func map_bounds() -> Rect2:
	return Rect2(Vector2.ZERO, map_size)


static func _rect_of(r: Dictionary) -> Rect2:
	var a: Array = r.get("rect", [0, 0, 0, 0])
	return Rect2(float(a[0]), float(a[1]), float(a[2]), float(a[3]))


# ==========================================================================
# Regiones y niebla de guerra
# ==========================================================================
func get_region(id: String) -> Dictionary:
	for r in regions:
		if r["id"] == id:
			return r
	return {}


func region_at(pos: Vector2) -> String:
	for r in regions:
		if _rect_of(r).has_point(pos):
			return str(r["id"])
	return ""


func is_explored(region_id: String) -> bool:
	return bool(get_region(region_id).get("explored", false))


func is_point_explored(pos: Vector2) -> bool:
	var rid := region_at(pos)
	return rid != "" and is_explored(rid)


## Vista de regiones para el lienzo: nombre real si está explorada, «???» si no.
func get_regions_view() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r in regions:
		var ex := bool(r.get("explored", false))
		out.append({
			"id": r["id"], "rect": _rect_of(r), "explored": ex,
			"display_name": str(r["name"]) if ex else "???",
			"universe": str(r.get("universe", "")), "kind": str(r.get("kind", "")),
			"explored_pct": int(r.get("explored_pct", 100 if ex else 0)),
			"color": Color(str(r.get("color", "#2a3a40"))),
		})
	return out


func explore_region(id: String) -> bool:
	var r := get_region(id)
	if r.is_empty() or bool(r.get("explored", false)):
		return false
	r["explored"] = true
	r["explored_pct"] = maxi(int(r.get("explored_pct", 0)), 5)
	region_explored.emit(id)
	map_changed.emit()
	return true


func explored_ratio() -> float:
	if regions.is_empty():
		return 0.0
	var n := 0
	for r in regions:
		if bool(r.get("explored", false)):
			n += 1
	return float(n) / float(regions.size())


# ==========================================================================
# Marcadores
# ==========================================================================
func get_poi(id: String) -> Dictionary:
	for p in pois:
		if p["id"] == id:
			return p
	return {}


func _poi_marker(p: Dictionary) -> Dictionary:
	var a: Array = p.get("pos", [0, 0])
	return {
		"id": p["id"], "kind": str(p.get("kind", "post")), "name": str(p.get("name", "")),
		"subtitle": str(p.get("subtitle", "")), "region": str(p.get("region", "")),
		"pos": Vector2(float(a[0]), float(a[1])),
	}


## Secretos personales con ubicación (KNOWN_SECRET en el Códice).
func get_secret_markers() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _knowledge == null:
		return out
	for e in _knowledge.list_entries():
		if int(e.get("visibility", 0)) != KNOWN_SECRET:
			continue
		var loc: Dictionary = e.get("location", {})
		var coords: Array = loc.get("coords", [])
		if coords.size() < 2:
			continue
		var pos := world_to_map(coords)
		out.append({
			"id": str(e["id"]), "kind": "secret", "name": str(e["name"]),
			"subtitle": "Secreto tuyo · %s" % str(loc.get("zone", "")), "region": region_at(pos),
			"pos": pos, "pending": bool(e.get("pending", false)),
		})
	return out


## Marcadores visibles. `layers` (kind -> bool) filtra; sin clave = visible.
## La niebla oculta los PDI de regiones no exploradas; los secretos propios se ven siempre.
func get_markers(layers: Dictionary = {}) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p in pois:
		var m := _poi_marker(p)
		if not bool(layers.get(m["kind"], true)):
			continue
		if m["region"] != "" and not is_explored(m["region"]):
			continue
		out.append(m)
	if bool(layers.get("secret", true)):
		out.append_array(get_secret_markers())
	return out


func find_marker(id: String) -> Dictionary:
	for m in get_markers():
		if m["id"] == id:
			return m
	return {}


## Posición de un PDI o de una entrada del Códice con ubicación. null si no se conoce.
func resolve_poi(poi_id: String) -> Variant:
	if poi_id == "":
		return null
	var p := get_poi(poi_id)
	if not p.is_empty():
		if p.get("region", "") != "" and not is_explored(str(p["region"])):
			return null
		return _poi_marker(p)["pos"]
	if _knowledge != null and _knowledge.is_known(poi_id):
		var coords: Array = (_knowledge.get_entry_view(poi_id).get("location", {}) as Dictionary).get("coords", [])
		if coords.size() >= 2:
			return world_to_map(coords)
	return null


func get_labels() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for l in labels:
		if l.get("region", "") != "" and not is_explored(str(l["region"])):
			continue
		var a: Array = l["pos"]
		out.append({"text": str(l["text"]), "pos": Vector2(float(a[0]), float(a[1]))})
	return out


# ==========================================================================
# Viajes (sin teletransporte)
# ==========================================================================
func get_location(id: String) -> Dictionary:
	for l in locations:
		if l["id"] == id:
			return l
	return {}


func is_origin_safe() -> bool:
	return bool(get_location(current_location).get("safe", false))


func set_current_location(id: String) -> void:
	current_location = id
	map_changed.emit()


func get_mode(id: String) -> Dictionary:
	for m in modes:
		if m["id"] == id:
			return m
	return {}


func get_destination(id: String) -> Dictionary:
	for d in destinations:
		if d["id"] == id:
			return d
	return {}


## Destinos visibles: los secretos (atajos) solo si los conoces.
func list_destinations() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for d in destinations:
		var secret := str(d.get("secret", ""))
		if secret != "" and not _is_known(secret):
			continue
		out.append(d)
	return out


static func risk_label(risk: float) -> String:
	if risk < RISK_SAFE_MAX:
		return "Segura"
	if risk < RISK_MEDIUM_MAX:
		return "Riesgo medio"
	return "Riesgo alto"


static func risk_level(risk: float) -> String:
	if risk < RISK_SAFE_MAX:
		return "safe"
	if risk < RISK_MEDIUM_MAX:
		return "medium"
	return "high"


## Calcula una ruta. Siempre devuelve el cálculo; `available` dice si se puede usar
## ahora y `reason` por qué no.
func compute_route(dest_id: String, mode_id: String) -> Dictionary:
	var d := get_destination(dest_id)
	var m := get_mode(mode_id)
	if d.is_empty():
		return {"ok": false, "reason": "unknown_destination"}
	if m.is_empty():
		return {"ok": false, "reason": "mode_required"}
	var flags: Array = d.get("flags", [])
	var only := str(m.get("only_for_flag", ""))
	if only != "" and not flags.has(only):
		return {"ok": false, "reason": "mode_not_applicable"}
	if flags.has("nest") and only != "nest":
		return {"ok": false, "reason": "mode_not_applicable"}
	var need_flag := str(m.get("requires_destination_flag", ""))
	if need_flag != "" and not flags.has(need_flag):
		return {"ok": false, "reason": "mode_not_applicable"}
	var dist := float(d.get("distance_km", 0.0))
	var minutes: int
	if m.has("fixed_min"):
		minutes = int(m["fixed_min"])
	else:
		var speed := maxf(0.1, float(m.get("speed_kmh", 1.0)))
		minutes = maxi(1, int(ceil(dist * float(m.get("path_factor", 1.0)) / speed * 60.0 - 0.0001)))
	var cost := int(m.get("cost_base", 0)) + int(round(float(m.get("cost_per_km", 0.0)) * dist))
	var risk := float(m.get("risk", 0.0))
	var breach := bool(d.get("crosses_breach", false))
	if breach and not bool(m.get("escorted", false)):
		risk += breach_risk
	var available := true
	var reason := ""
	var secret := str(m.get("requires_secret", ""))
	if secret != "" and not _is_known(secret):
		available = false
		reason = "secret_unknown"
	if bool(m.get("requires_safe_origin", false)) and not is_origin_safe():
		available = false
		reason = "origin_not_safe"
	var departure := int(m.get("next_departure_min", 0))
	return {
		"ok": true, "destination": dest_id, "mode": mode_id, "name": str(m.get("name", mode_id)),
		"desc": str(m.get("desc", "")), "distance_km": dist, "time_min": minutes, "cost": cost,
		"risk": snappedf(risk, 0.001), "risk_label": risk_label(risk), "risk_level": risk_level(risk),
		"departure_min": departure, "crosses_breach": breach, "escorted": bool(m.get("escorted", false)),
		"available": available, "reason": reason, "color": Color(str(m.get("color", "#46e3c1"))),
		"segments": _segments(minutes, departure, breach and not bool(m.get("escorted", false)), risk),
	}


## Tramos de la barra de la ruta: espera (gris) · seguro · tramo de riesgo.
func _segments(minutes: int, departure: int, risky_breach: bool, risk: float) -> Array:
	var segs: Array = []
	var wait_ratio := 0.0
	if departure > 0:
		wait_ratio = clampf(float(departure) / float(departure + minutes), 0.06, 0.15)
		segs.append({"kind": "wait", "ratio": wait_ratio})
	var rest := 1.0 - wait_ratio
	if risky_breach:
		var lvl := risk_level(risk)
		var r_ratio := 0.22 if lvl == "medium" else 0.44
		var before := (rest - r_ratio) * 0.7
		segs.append({"kind": "safe", "ratio": before})
		segs.append({"kind": lvl, "ratio": r_ratio})
		segs.append({"kind": "safe", "ratio": rest - r_ratio - before})
	else:
		segs.append({"kind": "safe", "ratio": rest})
	return segs


## Opciones de viaje aplicables a un destino (incluye las no disponibles con motivo).
func get_travel_options(dest_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for m in modes:
		var r := compute_route(dest_id, str(m["id"]))
		if r.get("ok", false):
			out.append(r)
	return out


## Reserva un viaje. No existe otra forma de moverse por el mapa: sin modo no hay viaje.
## `gold_available` < 0 = no comprobar saldo (lo cobra la economía).
func book_travel(dest_id: String, mode_id: String, gold_available: int = -1) -> Dictionary:
	if mode_id == "":
		return {"ok": false, "reason": "no_teleport"}
	if not active_trip.is_empty():
		return {"ok": false, "reason": "already_travelling"}
	var r := compute_route(dest_id, mode_id)
	if not r.get("ok", false):
		return r
	if not r["available"]:
		return {"ok": false, "reason": r["reason"]}
	if gold_available >= 0 and gold_available < int(r["cost"]):
		return {"ok": false, "reason": "not_enough_gold", "cost": r["cost"]}
	active_trip = r.duplicate(true)
	active_trip["elapsed_min"] = 0.0
	active_trip["total_min"] = float(r["time_min"] + r["departure_min"])
	trip_log.append({"destination": dest_id, "mode": mode_id, "cost": r["cost"], "time_min": r["time_min"]})
	travel_booked.emit(active_trip.duplicate(true))
	return {"ok": true, "cost": r["cost"], "time_min": r["time_min"], "departure_min": r["departure_min"], "risk_label": r["risk_label"]}


## Avanza el viaje en curso (minutos). Devuelve true al llegar.
func tick_travel(minutes: float) -> bool:
	if active_trip.is_empty():
		return false
	active_trip["elapsed_min"] = float(active_trip["elapsed_min"]) + minutes
	if float(active_trip["elapsed_min"]) >= float(active_trip["total_min"]):
		_arrive()
		return true
	return false


func trip_progress() -> float:
	if active_trip.is_empty():
		return 0.0
	return clampf(float(active_trip["elapsed_min"]) / maxf(1.0, float(active_trip["total_min"])), 0.0, 1.0)


## Desconexión durante un viaje escoltado (caravana/dirigible): llega a la posta y
## queda en zona segura. En montura/a pie el personaje se queda donde estaba.
func on_disconnect() -> Dictionary:
	if active_trip.is_empty():
		return {"ok": false, "reason": "not_travelling"}
	if bool(active_trip.get("escorted", false)):
		var dest := str(active_trip["destination"])
		_arrive()
		return {"ok": true, "arrived": dest, "safe": true}
	active_trip = {}
	return {"ok": true, "arrived": "", "safe": false}


func _arrive() -> void:
	var dest := str(active_trip.get("destination", ""))
	active_trip = {}
	if dest != "":
		current_location = dest
		travel_arrived.emit(dest)
		map_changed.emit()


func cancel_travel() -> bool:
	if active_trip.is_empty():
		return false
	active_trip = {}
	return true
