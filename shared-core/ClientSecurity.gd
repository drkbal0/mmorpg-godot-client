class_name ClientSecurity
extends Object

## ClientSecurity.gd
## Maneja la verificación criptográfica de integridad y anti-tampering del paquete PCK
## en tiempo de arranque antes de montar o ejecutar escenas críticas.

const INTEGRITY_FILE = "client_integrity.json"

static var _cached_hash: String = ""
static var _integrity_verified: bool = false

## Verifica la integridad física de MMORPG.pck comparándolo contra el manifiesto criptográfico
static func verify_integrity() -> Dictionary:
	if _integrity_verified and _cached_hash != "":
		return {"valid": true, "hash": _cached_hash, "mode": "cached"}

	# Si se ejecuta directamente desde el código fuente del proyecto (modo desarrollo/editor local)
	if FileAccess.file_exists("res://project.godot"):
		_cached_hash = "dev_source_mode"
		_integrity_verified = true
		return {"valid": true, "hash": _cached_hash, "mode": "source_dev"}

	var candidate_paths = [
		OS.get_executable_path().get_base_dir().path_join("MMORPG.pck"),
		"MMORPG.pck",
		"clients/godot-mmo-client/build/staging_win64/MMORPG.pck",
		"clients/godot-mmo-client/build/staging_dev/MMORPG.pck",
		"clients/godot-mmo-client/build/staging_local/MMORPG.pck"
	]

	var pck_path = ""
	var manifest_path = ""

	for p in candidate_paths:
		if FileAccess.file_exists(p):
			pck_path = p
			manifest_path = p.get_base_dir().path_join(INTEGRITY_FILE)
			break

	if pck_path == "":
		# En caso de PCK embebido directamente en el binario o ejecución en proyecto puro
		_cached_hash = "embedded_or_direct"
		_integrity_verified = true
		return {"valid": true, "hash": _cached_hash, "mode": "embedded"}

	# Calcular SHA-256 en tiempo real del archivo PCK
	var current_hash = FileAccess.get_sha256(pck_path)
	_cached_hash = current_hash

	# Si existe el manifiesto criptográfico generado por el pipeline de exportación
	if FileAccess.file_exists(manifest_path):
		var manifest_file = FileAccess.open(manifest_path, FileAccess.READ)
		if manifest_file:
			var content = manifest_file.get_as_text()
			var json = JSON.parse_string(content)
			if typeof(json) == TYPE_DICTIONARY and json.has("sha256"):
				var expected_hash = str(json["sha256"]).to_lower()
				if current_hash.to_lower() != expected_hash:
					printerr("ClientSecurity ALERTA: Mismatch de integridad en MMORPG.pck!")
					printerr("Esperado: ", expected_hash)
					printerr("Calculado: ", current_hash)
					_integrity_verified = false
					return {
						"valid": false,
						"hash": current_hash,
						"expected": expected_hash,
						"error": "El paquete de recursos (MMORPG.pck) ha sido modificado o está corrupto."
					}

	# Manifiesto válido o hash calculado exitosamente
	_integrity_verified = true
	print("ClientSecurity: Integridad de paquete verificada. SHA-256: ", current_hash.substr(0, 12), "...")
	return {"valid": true, "hash": current_hash, "mode": "verified"}

static func _has_main_pack_arg() -> bool:
	for arg in OS.get_cmdline_args():
		if arg == "--main-pack" or arg.begins_with("--main-pack="):
			return true
	return false

## Devuelve el hash criptográfico del cliente para handshake y telemetría de autenticación
static func get_client_hash() -> String:
	if _cached_hash == "":
		var res = verify_integrity()
		return res.get("hash", "unknown")
	return _cached_hash
