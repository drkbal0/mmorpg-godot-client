extends Node
## Muerte, recap táctico y reaparición — UI v2.4 Paso 13 (design_ref/pantallas_html/MMO-Muerte.html,
## PROMPT_ANTIGRAVITY.md §3 «Muerte y reaparición»).
##
## Autoload `DeathRecapService` o instanciable con `.new()` + `load_seed()` (reloj manual: `tick`).
## Seed: res://config/death/death_recap_seed.json
##
## - Registro de daño entrante (`record_damage`) con reloj propio. Al morir (`die`) se construye el
##   recap de los últimos `window_s` (5 s): tiempo relativo («−4,8 s»), importe («1.100»), % del
##   total, barra de contribución (sobre la vida máxima) y chip «evitable» para las mecánicas.
## - Consejo táctico generado: si un defensivo listo habría absorbido la mecánica evitable más
##   grande, lo dice con su tecla («Tu escudo [Shift+4] estaba listo y habría absorbido el
##   terremoto. …»); si no, cuánto te habrías ahorrado esquivándola; si no, consejo de sangrado
##   o de daño sostenido.
## - Resurrección canalizada por un aliado («Brisa te está resucitando», % y «Listo en 1,6 s»),
##   con aceptación automática opcional.
## - Cuenta atrás para reaparecer (12 s) en el punto de control / campamento y repetición de 10 s [R].
## - Nunca hay penalización de equipo (nota de seguridad).

signal died(recap: Dictionary)
signal recap_changed(recap: Dictionary)
signal resurrection_started(caster: String)
signal resurrection_progressed(progress: float, remaining: float)
signal resurrection_ready(caster: String)
signal resurrection_cancelled(caster: String, reason: String)
signal resurrected(caster: String)
signal respawn_ready
signal respawned(point: String)
signal replay_requested(seconds: float, events: Array)
signal auto_accept_changed(enabled: bool)

const DEFAULT_SEED_PATH := "res://config/death/death_recap_seed.json"

const STATE_ALIVE := "alive"
const STATE_DEAD := "dead"
const STATE_REVIVED := "revived"
const STATE_RESPAWNED := "respawned"

const RES_NONE := ""
const RES_CASTING := "casting"
const RES_READY := "ready"          # terminada sin aceptación automática: espera a que aceptes
const RES_ACCEPTED := "accepted"
const RES_DECLINED := "declined"
const RES_CANCELLED := "cancelled"

const LOG_KEEP_S := 30.0
const DEFAULT_WINDOW_S := 5.0
const DEFAULT_REPLAY_S := 10.0
const DEFAULT_RESPAWN_S := 12.0
const DOT_TIP_SHARE := 0.30
const MINUS := "−"

const AVOIDABLE_COLOR := "#f5c35b"
const AVOIDABLE_BG := "#2a2414"
const DAMAGE_COLOR := "#ff8a8a"
const BAR_COLOR := "#e25555"
const TIP_BORDER := "#46e3c1"

var title: String = "Has caído"
var subtitle: String = ""
var context: String = "raid"
var window_s: float = DEFAULT_WINDOW_S
var replay_s: float = DEFAULT_REPLAY_S
var player_name: String = "Tú"
var max_health: int = 1
var abilities: Dictionary = {}       # ability_id -> {name, short, kind, source, avoidable, hint}
var defensives: Array[Dictionary] = []
var respawn_points: Dictionary = {}
var respawn_point: String = "checkpoint"
var respawn_seconds: float = DEFAULT_RESPAWN_S
var note: String = ""
var seed_data: Dictionary = {}

## Registro de daño: [{at, ability, name, amount, hits, avoidable, kind, source}].
var damage_log: Array[Dictionary] = []
var clock: float = 0.0
var state: String = STATE_ALIVE
var death_at: float = 0.0
var recap: Dictionary = {}
var respawn_remaining: float = 0.0
var resurrection: Dictionary = {}    # {caster, spell, duration, elapsed, auto_accept, state}
var auto_tick: bool = true
var last_replay: Dictionary = {}


func _ready() -> void:
	if seed_data.is_empty() and FileAccess.file_exists(DEFAULT_SEED_PATH):
		load_seed(DEFAULT_SEED_PATH)


func _process(delta: float) -> void:
	if auto_tick and state == STATE_DEAD:
		tick(delta)


# ==========================================================================
# Carga
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
	title = str(data.get("title", "Has caído"))
	subtitle = str(data.get("subtitle", ""))
	context = str(data.get("context", "raid"))
	window_s = maxf(0.1, float(data.get("window_s", DEFAULT_WINDOW_S)))
	replay_s = maxf(window_s, float(data.get("replay_s", DEFAULT_REPLAY_S)))
	var p: Dictionary = data.get("player", {})
	player_name = str(p.get("name", "Tú"))
	max_health = maxi(1, int(p.get("max_health", 1)))
	abilities.clear()
	for aid in (data.get("abilities", {}) as Dictionary):
		register_ability(str(aid), data["abilities"][aid])
	defensives.clear()
	for d in data.get("defensives", []):
		defensives.append({
			"id": str(d.get("id", "")), "name": str(d.get("name", "")), "key": str(d.get("key", "")),
			"glyph": str(d.get("glyph", d.get("key", ""))), "absorbs": int(d.get("absorbs", 0)),
			"ready": bool(d.get("ready", false)),
		})
	respawn_points = (data.get("respawn_points", {"checkpoint": "Reaparecer en el punto de control"}) as Dictionary).duplicate()
	var r: Dictionary = data.get("respawn", {})
	respawn_seconds = maxf(0.0, float(r.get("seconds", DEFAULT_RESPAWN_S)))
	respawn_point = str(r.get("point", "checkpoint"))
	note = str(data.get("note", ""))
	reset()


func register_ability(id: String, raw: Dictionary) -> void:
	abilities[id] = {
		"id": id,
		"name": str(raw.get("name", id)),
		"short": str(raw.get("short", str(raw.get("name", id)).to_lower())),
		"kind": str(raw.get("kind", "hit")),
		"source": str(raw.get("source", "")),
		"avoidable": bool(raw.get("avoidable", false)),
		"hint": str(raw.get("hint", "")),
	}


func reset() -> void:
	damage_log.clear()
	clock = 0.0
	state = STATE_ALIVE
	death_at = 0.0
	recap = {}
	respawn_remaining = 0.0
	resurrection = {}
	last_replay = {}


## Muestra el recap del seed (demo / captura): reproduce sus eventos y muere en t=0,
## con la resurrección y la cuenta atrás del seed.
func present_seed() -> Dictionary:
	reset()
	var base := 30.0
	clock = base
	for e in seed_data.get("events", []):
		record_damage(str(e.get("ability", "")), int(e.get("amount", 0)), int(e.get("hits", 1)), base + float(e.get("t", 0.0)))
	die(base)
	var rs: Dictionary = seed_data.get("resurrection", {})
	if not rs.is_empty():
		start_resurrection(str(rs.get("caster", "")), float(rs.get("duration_s", 4.0)), bool(rs.get("auto_accept", true)),
			float(rs.get("elapsed_s", 0.0)), str(rs.get("spell", "")))
	return recap


## Abre el recap con datos externos. Claves admitidas: events [{t, ability|name, amount, hits,
## avoidable}], max_health, defensives, resurrection, respawn {seconds, point}, title, subtitle, note.
## Vacío: si ya estás muerto se conserva el recap actual; si no, se usa el del seed.
func present(data: Dictionary = {}) -> Dictionary:
	if data.is_empty():
		return recap if state == STATE_DEAD and not recap.is_empty() else present_seed()
	var merged := seed_data.duplicate(true)
	for k in data:
		merged[k] = data[k]
	if data.has("max_health"):
		merged["player"] = {"name": player_name, "max_health": int(data["max_health"])}
	for aid in (data.get("abilities", {}) as Dictionary):
		(merged["abilities"] as Dictionary)[aid] = data["abilities"][aid]
	var keep := seed_data.duplicate(true)
	load_from_dict(merged)
	seed_data = keep
	if not data.has("resurrection"):
		merged.erase("resurrection")
	var base := 30.0
	clock = base
	for e in merged.get("events", []):
		var aid := str(e.get("ability", ""))
		if aid == "" or not abilities.has(aid):
			aid = str(e.get("name", aid if aid != "" else "desconocido")).to_snake_case()
			if not abilities.has(aid):
				register_ability(aid, {"name": str(e.get("name", aid)), "avoidable": bool(e.get("avoidable", false)),
					"kind": str(e.get("kind", "hit")), "hint": str(e.get("hint", ""))})
		record_damage(aid, int(e.get("amount", 0)), int(e.get("hits", 1)), base + float(e.get("t", 0.0)))
	die(base)
	var rs: Dictionary = merged.get("resurrection", {})
	if not rs.is_empty():
		start_resurrection(str(rs.get("caster", "")), float(rs.get("duration_s", 4.0)), bool(rs.get("auto_accept", true)),
			float(rs.get("elapsed_s", 0.0)), str(rs.get("spell", "")))
	if data.has("tip"):
		recap["tip"] = _tip_from_text(str(data["tip"]))
		recap_changed.emit(recap)
	return recap


# ==========================================================================
# Daño y recap
# ==========================================================================
func ability_info(id: String) -> Dictionary:
	if abilities.has(id):
		return abilities[id]
	return {"id": id, "name": id, "short": id, "kind": "hit", "source": "", "avoidable": false, "hint": ""}


func is_avoidable(ability_id: String) -> bool:
	return bool(ability_info(ability_id).get("avoidable", false))


## Registra un impacto entrante. `at` < 0 usa el reloj actual.
func record_damage(ability_id: String, amount: int, hits: int = 1, at: float = -1.0) -> Dictionary:
	var info := ability_info(ability_id)
	var e := {
		"at": clock if at < 0.0 else at,
		"ability": ability_id,
		"name": str(info["name"]),
		"amount": maxi(0, amount),
		"hits": maxi(1, hits),
		"avoidable": bool(info["avoidable"]),
		"kind": str(info["kind"]),
		"source": str(info["source"]),
	}
	damage_log.append(e)
	_trim_log()
	return e


func _trim_log() -> void:
	var cutoff := clock - LOG_KEEP_S
	while not damage_log.is_empty() and float(damage_log[0]["at"]) < cutoff:
		damage_log.pop_front()


## Eventos dentro de [at − seconds, at] con tiempo relativo `t` (≤ 0).
func events_between(at: float, seconds: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in damage_log:
		var t := float(e["at"]) - at
		if t <= 0.0001 and t >= -seconds - 0.0001:
			var v: Dictionary = e.duplicate()
			v["t"] = snappedf(t, 0.01)
			out.append(v)
	out.sort_custom(func(a, b): return float(a["t"]) < float(b["t"]))
	return out


func die(at: float = -1.0) -> Dictionary:
	death_at = clock if at < 0.0 else at
	clock = maxf(clock, death_at)
	state = STATE_DEAD
	respawn_remaining = respawn_seconds
	resurrection = {}
	last_replay = {}
	recap = build_recap(death_at)
	died.emit(recap)
	return recap


func build_recap(at: float) -> Dictionary:
	var evs := events_between(at, window_s)
	var total := 0
	var avoidable_total := 0
	for e in evs:
		total += int(e["amount"])
		if e["avoidable"]:
			avoidable_total += int(e["amount"])
	var rows: Array[Dictionary] = []
	for e in evs:
		var r: Dictionary = e.duplicate()
		r["percent"] = 100.0 * float(e["amount"]) / float(total) if total > 0 else 0.0
		r["bar_ratio"] = clampf(float(e["amount"]) / float(max_health), 0.0, 1.0)
		r["time_text"] = format_offset(float(e["t"]))
		r["label"] = "%s ×%d" % [e["name"], e["hits"]] if int(e["hits"]) > 1 else str(e["name"])
		r["amount_text"] = format_amount(int(e["amount"]))
		rows.append(r)
	var out := {
		"title": title,
		"subtitle": subtitle,
		"window_s": window_s,
		"events": rows,
		"total": total,
		"total_text": format_amount(total),
		"avoidable_total": avoidable_total,
		"avoidable_percent": 100.0 * avoidable_total / total if total > 0 else 0.0,
		"by_ability": _by_ability(rows, total),
		"killing_blow": rows[rows.size() - 1].duplicate() if not rows.is_empty() else {},
		"overkill": maxi(0, total - max_health),
		"max_health": max_health,
		"note": note,
	}
	out["tip"] = tactical_tip(out)
	return out


func _by_ability(rows: Array, total: int) -> Array[Dictionary]:
	var acc := {}
	var order: Array[String] = []
	for r in rows:
		var id := str(r["ability"])
		if not acc.has(id):
			acc[id] = {"ability": id, "name": r["name"], "amount": 0, "hits": 0, "avoidable": r["avoidable"]}
			order.append(id)
		acc[id]["amount"] += int(r["amount"])
		acc[id]["hits"] += int(r["hits"])
	var out: Array[Dictionary] = []
	for id in order:
		var a: Dictionary = acc[id]
		a["percent"] = 100.0 * float(a["amount"]) / float(total) if total > 0 else 0.0
		out.append(a)
	out.sort_custom(func(a, b): return int(a["amount"]) > int(b["amount"]))
	return out


func damage_percent(ability_id: String) -> float:
	for a in recap.get("by_ability", []):
		if a["ability"] == ability_id:
			return float(a["percent"])
	return 0.0


func avoidable_events() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in recap.get("events", []):
		if e["avoidable"]:
			out.append(e)
	return out


# ==========================================================================
# Consejo táctico
# ==========================================================================
func set_defensive_ready(id: String, ready: bool) -> void:
	for d in defensives:
		if d["id"] == id:
			d["ready"] = ready
	if not recap.is_empty():
		recap["tip"] = tactical_tip(recap)
		recap_changed.emit(recap)


## Genera un consejo a partir del recap. Devuelve {kind, text, segments:[{text}|{key}], ability, defensive}.
func tactical_tip(r: Dictionary) -> Dictionary:
	var evs: Array = r.get("events", [])
	var worst: Dictionary = {}
	for e in evs:
		if e["avoidable"] and (worst.is_empty() or int(e["amount"]) > int(worst["amount"])):
			worst = e
	if not worst.is_empty():
		var info := ability_info(str(worst["ability"]))
		var hint := str(info.get("hint", ""))
		var best: Dictionary = {}
		for d in defensives:
			if d["ready"] and int(d["absorbs"]) >= int(worst["amount"]):
				if best.is_empty() or int(d["absorbs"]) < int(best["absorbs"]):
					best = d
		if not best.is_empty():
			var after := " estaba listo y habría absorbido %s." % info["short"]
			if hint != "":
				after += " " + hint
			return _tip("defensive", [{"text": "Tu %s " % best["name"]}, {"key": best["glyph"], "key_text": best["key"]}, {"text": after}],
				str(worst["ability"]), str(best["id"]))
		var txt := "Esquivar %s te habría ahorrado %s de daño." % [info["short"], format_amount(int(worst["amount"]))]
		if hint != "":
			txt += " " + hint
		return _tip("avoidable", [{"text": txt}], str(worst["ability"]))
	var total := int(r.get("total", 0))
	for a in r.get("by_ability", []):
		if ability_info(str(a["ability"]))["kind"] == "dot" and total > 0 and float(a["amount"]) / total >= DOT_TIP_SHARE:
			return _tip("dot", [{"text": "%s te hizo %s en %d golpes: límpialo o pide a tu sanador que lo disipe." % [a["name"], format_amount(int(a["amount"])), int(a["hits"])]}], str(a["ability"]))
	if total == 0:
		return _tip("none", [{"text": "No recibiste daño en los últimos %s s." % _num(window_s)}], "")
	return _tip("sustained", [{"text": "Recibiste %s sin mecánicas evitables: usa un defensivo antes del golpe fuerte o avisa a tu sanador." % format_amount(total)}], "")


func _tip(kind: String, segments: Array, ability: String, defensive: String = "") -> Dictionary:
	var text := ""
	for s in segments:
		text += ("[%s]" % s["key_text"]) if s.has("key") else str(s["text"])
	return {"kind": kind, "segments": segments, "text": text, "ability": ability, "defensive": defensive}


func _tip_from_text(text: String) -> Dictionary:
	return _tip("custom", [{"text": text}], "")


# ==========================================================================
# Resurrección
# ==========================================================================
func start_resurrection(caster: String, duration: float, auto_accept: bool = true, elapsed: float = 0.0, spell: String = "") -> bool:
	if state != STATE_DEAD or caster == "":
		return false
	resurrection = {
		"caster": caster, "spell": spell, "duration": maxf(0.1, duration),
		"elapsed": clampf(elapsed, 0.0, maxf(0.1, duration)), "auto_accept": auto_accept, "state": RES_CASTING,
	}
	resurrection_started.emit(caster)
	_check_resurrection()
	return true


func is_resurrecting() -> bool:
	return str(resurrection.get("state", RES_NONE)) == RES_CASTING


func resurrection_state() -> String:
	return str(resurrection.get("state", RES_NONE))


func resurrection_progress() -> float:
	if resurrection.is_empty():
		return 0.0
	return clampf(float(resurrection["elapsed"]) / float(resurrection["duration"]), 0.0, 1.0)


func resurrection_remaining() -> float:
	if resurrection.is_empty():
		return 0.0
	return maxf(0.0, float(resurrection["duration"]) - float(resurrection["elapsed"]))


func resurrection_title() -> String:
	match resurrection_state():
		RES_CASTING:
			return "%s te está resucitando" % resurrection["caster"]
		RES_READY:
			return "%s te ha resucitado" % resurrection["caster"]
		RES_ACCEPTED:
			return "Resucitado por %s" % resurrection["caster"]
		RES_CANCELLED:
			return "%s ha dejado de resucitarte" % resurrection["caster"]
		RES_DECLINED:
			return "Rechazaste la resurrección"
	return "Nadie te está resucitando"


func resurrection_text() -> String:
	var auto := "aceptar automáticamente ✓" if bool(resurrection.get("auto_accept", false)) else "aceptar automáticamente ✗"
	match resurrection_state():
		RES_CASTING:
			return "Listo en %s s · %s" % [_num(resurrection_remaining()), auto]
		RES_READY:
			return "Pulsa Aceptar para volver al combate"
		RES_ACCEPTED:
			return "De vuelta al combate"
		RES_CANCELLED:
			return "Lanzamiento interrumpido"
	return ""


func set_auto_accept(enabled: bool) -> void:
	if resurrection.is_empty():
		return
	resurrection["auto_accept"] = enabled
	auto_accept_changed.emit(enabled)
	_check_resurrection()


func accept_resurrection() -> Dictionary:
	if resurrection_state() != RES_READY:
		return {"ok": false, "reason": "not_ready"}
	return _revive()


func decline_resurrection() -> Dictionary:
	if resurrection_state() not in [RES_CASTING, RES_READY]:
		return {"ok": false, "reason": "no_resurrection"}
	resurrection["state"] = RES_DECLINED
	resurrection_cancelled.emit(str(resurrection["caster"]), "declined")
	return {"ok": true}


## El lanzador se interrumpe (le golpean, se mueve…).
func cancel_resurrection(reason: String = "interrupted") -> bool:
	if not is_resurrecting():
		return false
	resurrection["state"] = RES_CANCELLED
	resurrection_cancelled.emit(str(resurrection["caster"]), reason)
	return true


func _check_resurrection() -> void:
	if not is_resurrecting() or resurrection_remaining() > 0.0:
		return
	if bool(resurrection["auto_accept"]):
		_revive()
	else:
		resurrection["state"] = RES_READY
		resurrection_ready.emit(str(resurrection["caster"]))


func _revive() -> Dictionary:
	resurrection["state"] = RES_ACCEPTED
	resurrection["elapsed"] = resurrection["duration"]
	state = STATE_REVIVED
	resurrected.emit(str(resurrection["caster"]))
	return {"ok": true, "caster": resurrection["caster"]}


# ==========================================================================
# Reloj, reaparición y repetición
# ==========================================================================
func tick(delta: float) -> void:
	if delta <= 0.0:
		return
	clock += delta
	if state != STATE_DEAD:
		return
	if respawn_remaining > 0.0:
		respawn_remaining = maxf(0.0, respawn_remaining - delta)
		if respawn_remaining <= 0.0:
			respawn_ready.emit()
	if is_resurrecting():
		resurrection["elapsed"] = minf(float(resurrection["duration"]), float(resurrection["elapsed"]) + delta)
		resurrection_progressed.emit(resurrection_progress(), resurrection_remaining())
		_check_resurrection()


func can_respawn() -> bool:
	return state == STATE_DEAD and respawn_remaining <= 0.0


func respawn_label() -> String:
	return str(respawn_points.get(respawn_point, "Reaparecer en el punto de control"))


func respawn_countdown_text() -> String:
	return format_countdown(respawn_remaining) if respawn_remaining > 0.0 else "Ahora"


func respawn() -> Dictionary:
	if state != STATE_DEAD:
		return {"ok": false, "reason": "not_dead"}
	if respawn_remaining > 0.0:
		return {"ok": false, "reason": "cooldown", "remaining": respawn_remaining}
	if is_resurrecting():
		cancel_resurrection("respawned")
	state = STATE_RESPAWNED
	respawned.emit(respawn_point)
	return {"ok": true, "point": respawn_point, "label": respawn_label(), "equipment_penalty": false}


func set_respawn_point(point: String) -> bool:
	if not respawn_points.has(point):
		return false
	respawn_point = point
	return true


## Repetición de los últimos `replay_s` segundos antes de morir.
func request_replay() -> Dictionary:
	if state == STATE_ALIVE:
		return {"ok": false, "reason": "alive"}
	var evs := events_between(death_at, replay_s)
	last_replay = {"ok": true, "seconds": replay_s, "events": evs, "from": death_at - replay_s, "to": death_at}
	replay_requested.emit(replay_s, evs)
	return last_replay


func replay_label() -> String:
	return "Ver repetición de %s s" % _num(replay_s)


func has_equipment_penalty() -> bool:
	return false


# ==========================================================================
# Formato
# ==========================================================================
static func _num(v: float) -> String:
	if is_equal_approx(v, roundf(v)):
		return str(roundi(v))
	return ("%.1f" % v).replace(".", ",")


## −4.8 → «−4,8 s» · −1 → «−1,0 s» · 0 → «0 s».
static func format_offset(t: float) -> String:
	if absf(t) < 0.05:
		return "0 s"
	return "%s%s s" % [MINUS if t < 0.0 else "+", ("%.1f" % absf(t)).replace(".", ",")]


## 12 → «0:12» · 75 → «1:15» (redondeo hacia arriba).
static func format_countdown(seconds: float) -> String:
	var s := int(ceil(maxf(0.0, seconds) - 0.0001))
	return "%d:%02d" % [s / 60, s % 60]


## 8200 → «8.200».
static func format_amount(value: int) -> String:
	var neg := value < 0
	var digits := str(absi(value))
	var out := ""
	var count := 0
	for idx in range(digits.length() - 1, -1, -1):
		out = digits[idx] + out
		count += 1
		if count % 3 == 0 and idx > 0:
			out = "." + out
	return ("-" if neg else "") + out
