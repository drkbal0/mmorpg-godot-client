extends Node

## GameConfig.gd - Centralized Environment and Network Profiles
## Manages connection endpoints for WAN (Production), Proxmox (LAN), and Local PC (Dev).

const CLIENT_VERSION: String = "0.1.0-alpha"

const PROFILES: Dictionary = {
	"wan": {
		"id": "wan",
		"name": "Producción / WAN (play.elbalo.lol)",
		"gateway_url": "https://mmo.elbalo.lol/api",
		"udp_host": "play.elbalo.lol",
		"udp_port": 5000
	},
	"proxmox": {
		"id": "proxmox",
		"name": "Servidor Proxmox / Red Local",
		"gateway_url": "http://127.0.0.1:8080",
		"udp_host": "127.0.0.1",
		"udp_port": 5000
	},
	"local": {
		"id": "local",
		"name": "Desarrollo Local PC (127.0.0.1)",
		"gateway_url": "http://127.0.0.1:8080",
		"udp_host": "127.0.0.1",
		"udp_port": 5000
	}
}

## Returns whether client is running in production release mode
static func is_production_mode() -> bool:
	if OS.has_environment("FORCE_PRODUCTION"):
		return true
	if OS.has_environment("FORCE_DEV") or OS.has_environment("DEV_LOCAL_PC"):
		return false
	for arg in OS.get_cmdline_args():
		if arg == "--debug" or arg == "-d" or arg == "--dev" or arg == "--local" or arg == "--proxmox" or arg == "--lan":
			return false
	if OS.has_feature("editor") or OS.is_debug_build():
		return false
	return true

## Determines active profile ID: "wan", "proxmox", or "local"
static func get_active_profile_id() -> String:
	# 1. CLI Profile flags (checking both engine args and user args)
	var all_args = OS.get_cmdline_args()
	all_args.append_array(OS.get_cmdline_user_args())
	for arg in all_args:
		if arg.begins_with("--profile="):
			var p = arg.split("=")[1].to_lower()
			if PROFILES.has(p):
				return p
		elif arg == "--wan" or arg == "--prod" or arg == "--production":
			return "wan"
		elif arg == "--proxmox" or arg == "--lan":
			return "proxmox"
		elif arg == "--local" or arg == "--dev" or arg == "--pc":
			return "local"
		elif arg == "--debug" or arg == "-d":
			return "local"

	# 2. client_config.json profile key
	var cfg = _read_external_config()
	if cfg.has("profile") and str(cfg["profile"]).strip_edges() != "":
		var p = str(cfg["profile"]).strip_edges().to_lower()
		if PROFILES.has(p):
			return p

	# 3. Environment variable override
	if OS.has_environment("MMO_PROFILE"):
		var p = OS.get_environment("MMO_PROFILE").to_lower()
		if PROFILES.has(p):
			return p

	# 4. Defaults based on build context:
	# Debug/Editor defaults to Local PC (127.0.0.1) for zero-leak standalone safety
	if not is_production_mode():
		return "local"

	# Exported release build defaults to WAN (Internet)
	return "wan"

## Returns whether an explicit profile was supplied via CLI
static func has_explicit_cli_profile() -> bool:
	var all_args = OS.get_cmdline_args()
	all_args.append_array(OS.get_cmdline_user_args())
	for arg in all_args:
		if arg.begins_with("--profile=") or arg in ["--wan", "--prod", "--production", "--proxmox", "--lan", "--local", "--dev", "--pc"]:
			return true
	return false

## Returns Gateway API Base URL
static func get_gateway_url() -> String:
	# 1. Direct CLI argument override
	var all_args = OS.get_cmdline_args()
	all_args.append_array(OS.get_cmdline_user_args())
	for arg in all_args:
		if arg.begins_with("--gateway="):
			return arg.split("=")[1]

	# 2. If CLI explicitly selected a profile (e.g. --profile=wan or --proxmox), respect it
	if has_explicit_cli_profile():
		var profile_id = get_active_profile_id()
		return PROFILES[profile_id]["gateway_url"]

	# 3. Direct client_config.json override
	var cfg = _read_external_config()
	if cfg.has("gateway_url") and str(cfg["gateway_url"]).strip_edges() != "":
		return str(cfg["gateway_url"]).strip_edges()

	# 4. Environment override
	if OS.has_environment("GATEWAY_URL"):
		return OS.get_environment("GATEWAY_URL")
	if OS.is_debug_build() and OS.has_environment("DEV_GATEWAY_URL"):
		return OS.get_environment("DEV_GATEWAY_URL")

	# 5. Profile default
	var profile_id = get_active_profile_id()
	return PROFILES[profile_id]["gateway_url"]

## Returns Web Portal Base URL (for Wiki, Codex and browser interactions)
static func get_web_url() -> String:
	var profile_id = get_active_profile_id()
	if profile_id == "wan":
		return "https://mmo.elbalo.lol"
	return "http://127.0.0.1:3000"

## Returns UDP Simulation Server Host and Port Dictionary {"host": ..., "port": ...}
static func get_udp_server() -> Dictionary:
	var profile_id = get_active_profile_id()
	var target_host: String = PROFILES[profile_id]["udp_host"]
	var target_port: int = PROFILES[profile_id]["udp_port"]

	# 1. CLI argument overrides
	var all_args = OS.get_cmdline_args()
	all_args.append_array(OS.get_cmdline_user_args())
	for arg in all_args:
		if arg.begins_with("--server=") or arg.begins_with("--udp-host="):
			target_host = arg.split("=")[1]
		elif arg.begins_with("--udp-port="):
			target_port = int(arg.split("=")[1])

	# 2. If CLI explicitly selected a profile, respect the profile's host & port
	if has_explicit_cli_profile():
		return {"host": target_host, "port": target_port}

	# 3. client_config.json overrides
	var cfg = _read_external_config()
	if cfg.has("udp_host") and str(cfg["udp_host"]).strip_edges() != "":
		target_host = str(cfg["udp_host"]).strip_edges()
	if cfg.has("udp_port") and int(cfg["udp_port"]) > 0:
		target_port = int(cfg["udp_port"])

	# 4. Environment overrides in debug mode
	if OS.is_debug_build():
		if OS.has_environment("MMO_SERVER_IP"):
			target_host = OS.get_environment("MMO_SERVER_IP")
		elif OS.has_environment("DEV_UDP_HOST"):
			target_host = OS.get_environment("DEV_UDP_HOST")
		if OS.has_environment("MMO_SERVER_PORT"):
			target_port = int(OS.get_environment("MMO_SERVER_PORT"))
		elif OS.has_environment("DEV_UDP_PORT"):
			target_port = int(OS.get_environment("DEV_UDP_PORT"))

	return {"host": target_host, "port": target_port}

static func get_udp_host() -> String:
	return get_udp_server()["host"]

static func get_udp_port() -> int:
	return get_udp_server()["port"]

## Returns human-readable summary of active network configuration
static func get_active_profile_summary() -> String:
	var pid = get_active_profile_id()
	var srv = get_udp_server()
	return "%s (%s:%d)" % [pid.to_upper(), srv["host"], srv["port"]]

static func _read_external_config() -> Dictionary:
	var exe_dir = OS.get_executable_path().get_base_dir()
	var config_paths = [
		exe_dir + "/client_config.json",
		"res://client_config.json",
		"user://client_config.json"
	]
	for path in config_paths:
		if FileAccess.file_exists(path):
			var file = FileAccess.open(path, FileAccess.READ)
			if file:
				var content = file.get_as_text()
				var parsed = JSON.parse_string(content)
				if typeof(parsed) == TYPE_DICTIONARY:
					return parsed
	return {}

static func get_version() -> String:
	return CLIENT_VERSION
