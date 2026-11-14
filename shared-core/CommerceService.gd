extends Node
## CommerceService — monedas, Tienda de Prismas y Pase de batalla (UI v2.4 Paso 9, §2.2).
## Referencias: design_ref/pantallas_html/MMO-Tienda.html y MMO-Pase.html.
##
## Dos monedas: Oro (#f5c35b, se gana jugando y NO se compra) y Prismas (#7ee8ff, dinero
## real). Tienda y Pase están EN CONSTRUCCIÓN: la estructura existe y todo el contenido
## viene de datos, pero comprar/desbloquear devuelve `under_construction`.
##
## Reglas validadas por código (por validar con el roadmap, §2.2):
## - La tienda solo vende apariencia («cosmetic») y comodidad («comfort»). Cualquier
##   objeto con estadísticas o poder de combate se RECHAZA al cargar (cero pay-to-win).
## - El pase da XP con CUALQUIER actividad y lo ganado no caduca: al cerrar la temporada,
##   las recompensas alcanzadas y no reclamadas se entregan solas.
##
## Instanciable con `.new()` y autoload `CommerceService`.

const DEFAULT_SEED_PATH := "res://config/commerce/commerce_seed.json"
const DEFAULT_ALLOWED_KINDS: Array[String] = ["cosmetic", "comfort"]
const DEFAULT_FORBIDDEN_FIELDS: Array[String] = ["stats", "power", "damage", "armor", "item_level", "combat", "xp_boost", "attributes"]
const TRACK_FREE := "free"
const TRACK_PREMIUM := "premium"

signal wallet_changed(gold: int, prisms: int)
signal prisms_purchase_requested(pack_id: String)
signal pass_xp_gained(amount: int, activity: String)
signal pass_level_up(level: int)
signal pass_reward_claimed(level: int, track: String, reward: String)

var gold: int = 0
var prisms: int = 0

# --- Tienda ---------------------------------------------------------------
var shop_under_construction := true
var shop_banner: String = ""
var shop_policy: String = ""
var shop_categories: Array[Dictionary] = []
var shop_items: Array[Dictionary] = []
var shop_packs: Array[Dictionary] = []
## Objetos rechazados al cargar por dar poder (QA / auditoría).
var rejected_items: Array[Dictionary] = []
var allowed_kinds: Array[String] = []
var forbidden_fields: Array[String] = []

# --- Pase de batalla --------------------------------------------------------
var pass_under_construction := true
var pass_banner: String = ""
var pass_policy: String = ""
var season: int = 1
var season_name: String = ""
var days_left: int = 0
var max_level: int = 50
var xp_per_level: int = 1000
var level: int = 1
var xp: int = 0
var premium_unlocked := false
var premium_price: int = 0
var activity_xp: Dictionary = {}
var milestones: Dictionary = {}       # level -> {free, premium}
var filler: Dictionary = {}
var challenges: Array[Dictionary] = []
var claimed: Dictionary = {}          # "level:track" -> true
## Recompensas propias, permanentes (no caducan con la temporada).
var owned_rewards: Array[Dictionary] = []


func _init() -> void:
	reset()


func _ready() -> void:
	if shop_categories.is_empty() and FileAccess.file_exists(DEFAULT_SEED_PATH):
		load_seed(DEFAULT_SEED_PATH)


func reset() -> void:
	gold = 0
	prisms = 0
	shop_categories.clear()
	shop_items.clear()
	shop_packs.clear()
	rejected_items.clear()
	allowed_kinds = DEFAULT_ALLOWED_KINDS.duplicate()
	forbidden_fields = DEFAULT_FORBIDDEN_FIELDS.duplicate()
	milestones.clear()
	challenges.clear()
	claimed.clear()
	owned_rewards.clear()
	activity_xp = {"default": 50}
	level = 1
	xp = 0


func load_seed(path: String = DEFAULT_SEED_PATH) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var data = JSON.parse_string(f.get_as_text())
	if not (data is Dictionary):
		push_warning("[CommerceService] Seed inválido: %s" % path)
		return false
	load_from_dict(data)
	return true


func load_from_dict(data: Dictionary) -> void:
	reset()
	var w: Dictionary = data.get("wallet", {})
	gold = int(w.get("gold", 0))
	prisms = int(w.get("prisms", 0))
	var shop: Dictionary = data.get("shop", {})
	shop_under_construction = bool(shop.get("under_construction", true))
	shop_banner = str(shop.get("banner", ""))
	shop_policy = str(shop.get("policy", ""))
	if shop.has("allowed_kinds"):
		allowed_kinds.clear()
		for k in shop["allowed_kinds"]:
			allowed_kinds.append(str(k))
	if shop.has("forbidden_fields"):
		forbidden_fields.clear()
		for k in shop["forbidden_fields"]:
			forbidden_fields.append(str(k))
	for c in shop.get("categories", []):
		shop_categories.append((c as Dictionary).duplicate(true))
	for it in shop.get("items", []):
		var item: Dictionary = (it as Dictionary).duplicate(true)
		var why := power_violation(item)
		if why != "":
			item["rejected_reason"] = why
			rejected_items.append(item)
			push_warning("[CommerceService] Objeto rechazado (pay-to-win): %s (%s)" % [item.get("id", "?"), why])
			continue
		shop_items.append(item)
	for p in shop.get("packs", []):
		shop_packs.append((p as Dictionary).duplicate(true))

	var bp: Dictionary = data.get("battle_pass", {})
	pass_under_construction = bool(bp.get("under_construction", true))
	pass_banner = str(bp.get("banner", ""))
	pass_policy = str(bp.get("policy", ""))
	season = int(bp.get("season", 1))
	season_name = str(bp.get("name", ""))
	days_left = int(bp.get("days_left", 0))
	max_level = int(bp.get("max_level", 50))
	xp_per_level = maxi(1, int(bp.get("xp_per_level", 1000)))
	level = clampi(int(bp.get("level", 1)), 1, max_level)
	xp = int(bp.get("xp", 0))
	premium_unlocked = bool(bp.get("premium_unlocked", false))
	premium_price = int(bp.get("premium_price_prisms", 0))
	activity_xp = (bp.get("activity_xp", {"default": 50}) as Dictionary).duplicate()
	filler = (bp.get("filler", {}) as Dictionary).duplicate()
	for m in bp.get("milestones", []):
		milestones[int(m["level"])] = {"free": str(m.get("free", "")), "premium": str(m.get("premium", ""))}
	for c in bp.get("challenges", []):
		challenges.append((c as Dictionary).duplicate(true))
	wallet_changed.emit(gold, prisms)


# ==========================================================================
# Monedas
# ==========================================================================
func spend_gold(amount: int) -> bool:
	if amount < 0 or amount > gold:
		return false
	gold -= amount
	wallet_changed.emit(gold, prisms)
	return true


func add_gold(amount: int) -> void:
	gold += maxi(0, amount)
	wallet_changed.emit(gold, prisms)


## «+» de Prismas: abre los paquetes. La compra real (dinero) aún no existe.
func request_prisms(pack_id: String = "") -> Dictionary:
	prisms_purchase_requested.emit(pack_id)
	if shop_under_construction:
		return {"ok": false, "reason": "under_construction", "packs": shop_packs.size()}
	return {"ok": false, "reason": "payment_provider_missing"}


## El oro NO se puede comprar con Prismas ni con dinero real.
func buy_gold(_amount: int) -> Dictionary:
	return {"ok": false, "reason": "gold_not_purchasable"}


# ==========================================================================
# Tienda
# ==========================================================================
## "" si el objeto es válido; si no, el motivo (tipo no permitido o campo de poder).
func power_violation(item: Dictionary) -> String:
	var kind := str(item.get("kind", ""))
	if not allowed_kinds.has(kind):
		return "kind:" + kind
	for f in forbidden_fields:
		if item.has(f) and _is_meaningful(item[f]):
			return "field:" + f
	return ""


static func _is_meaningful(v: Variant) -> bool:
	if v is Dictionary or v is Array:
		return not v.is_empty()
	if v is int or v is float:
		return float(v) != 0.0
	if v is bool:
		return v
	if v is String:
		return v != ""
	return v != null


func is_pay_to_win(item: Dictionary) -> bool:
	return power_violation(item) != ""


func list_shop_items(category: String = "destacado") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for it in shop_items:
		if category == "" or category == "todo":
			out.append(it)
		elif category == "destacado":
			if bool(it.get("featured", false)):
				out.append(it)
		elif it.get("category", "") == category:
			out.append(it)
	return out


func get_shop_item(id: String) -> Dictionary:
	for it in shop_items:
		if it["id"] == id:
			return it
	return {}


static func kind_label(kind: String) -> String:
	match kind:
		"cosmetic":
			return "Apariencia"
		"comfort":
			return "Comodidad"
	return kind


func buy_item(id: String) -> Dictionary:
	var it := get_shop_item(id)
	if it.is_empty():
		return {"ok": false, "reason": "unknown_item"}
	if shop_under_construction:
		return {"ok": false, "reason": "under_construction"}
	var price := int(it.get("price_prisms", 0))
	if price > prisms:
		return {"ok": false, "reason": "not_enough_prisms"}
	prisms -= price
	wallet_changed.emit(gold, prisms)
	return {"ok": true, "prisms": prisms}


# ==========================================================================
# Pase de batalla
# ==========================================================================
func xp_for_activity(activity: String) -> int:
	return int(activity_xp.get(activity, activity_xp.get("default", 50)))


## Cualquier actividad da XP (las que no están en la tabla usan "default").
func add_activity_xp(activity: String, units: int = 1) -> Dictionary:
	var gained := xp_for_activity(activity) * maxi(1, units)
	return add_pass_xp(gained, activity)


func add_pass_xp(amount: int, activity: String = "") -> Dictionary:
	if amount <= 0:
		return {"ok": false, "reason": "invalid_amount"}
	var before := level
	xp += amount
	while xp >= xp_per_level and level < max_level:
		xp -= xp_per_level
		level += 1
		pass_level_up.emit(level)
	if level >= max_level:
		xp = mini(xp, xp_per_level)
	pass_xp_gained.emit(amount, activity)
	return {"ok": true, "gained": amount, "level": level, "levels_gained": level - before}


func pass_ratio() -> float:
	return clampf(float(xp) / float(xp_per_level), 0.0, 1.0)


func is_milestone(lvl: int) -> bool:
	return milestones.has(lvl)


func get_level_rewards(lvl: int) -> Dictionary:
	if milestones.has(lvl):
		var m: Dictionary = milestones[lvl]
		return {"level": lvl, "free": m["free"], "premium": m["premium"], "milestone": true}
	return {"level": lvl, "free": str(filler.get("free", "")), "premium": str(filler.get("premium", "")), "milestone": false}


func get_pass_levels() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for l in range(1, max_level + 1):
		var r := get_level_rewards(l)
		r["reached"] = l <= level
		r["claimed_free"] = claimed.has("%d:%s" % [l, TRACK_FREE])
		r["claimed_premium"] = claimed.has("%d:%s" % [l, TRACK_PREMIUM])
		out.append(r)
	return out


func claim_reward(lvl: int, track: String = TRACK_FREE) -> Dictionary:
	if lvl < 1 or lvl > max_level:
		return {"ok": false, "reason": "invalid_level"}
	if lvl > level:
		return {"ok": false, "reason": "level_not_reached"}
	if track == TRACK_PREMIUM and not premium_unlocked:
		return {"ok": false, "reason": "premium_locked"}
	var key := "%d:%s" % [lvl, track]
	if claimed.has(key):
		return {"ok": false, "reason": "already_claimed"}
	var reward := str(get_level_rewards(lvl).get(track, ""))
	claimed[key] = true
	owned_rewards.append({"season": season, "level": lvl, "track": track, "reward": reward})
	pass_reward_claimed.emit(lvl, track, reward)
	return {"ok": true, "reward": reward}


func unclaimed_count() -> int:
	var n := 0
	for l in range(1, level + 1):
		if not claimed.has("%d:%s" % [l, TRACK_FREE]):
			n += 1
		if premium_unlocked and not claimed.has("%d:%s" % [l, TRACK_PREMIUM]):
			n += 1
	return n


func unlock_premium() -> Dictionary:
	if pass_under_construction:
		return {"ok": false, "reason": "under_construction", "price": premium_price}
	if premium_unlocked:
		return {"ok": false, "reason": "already_unlocked"}
	if prisms < premium_price:
		return {"ok": false, "reason": "not_enough_prisms"}
	prisms -= premium_price
	premium_unlocked = true
	wallet_changed.emit(gold, prisms)
	return {"ok": true}


## Cierra la temporada: lo alcanzado y no reclamado se entrega (nada caduca) y lo
## ya reclamado sigue siendo tuyo. Empieza la siguiente temporada desde el nivel 1.
func end_season(next_name: String = "") -> Dictionary:
	var auto: Array = []
	for l in range(1, level + 1):
		for track in [TRACK_FREE, TRACK_PREMIUM]:
			if track == TRACK_PREMIUM and not premium_unlocked:
				continue
			if not claimed.has("%d:%s" % [l, track]):
				var r := claim_reward(l, track)
				if r.get("ok", false):
					auto.append(r["reward"])
	var kept := owned_rewards.size()
	season += 1
	season_name = next_name
	level = 1
	xp = 0
	claimed.clear()
	premium_unlocked = false
	return {"ok": true, "auto_granted": auto, "owned_total": kept, "season": season}
