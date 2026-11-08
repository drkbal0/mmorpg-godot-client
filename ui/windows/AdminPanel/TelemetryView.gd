extends VBoxContainer

# TelemetryView.gd - Admin-only stats dashboard

@onready var total_deaths_label = find_child("TotalDeathsValue", true, false)
@onready var total_damage_label = find_child("TotalDamageValue", true, false)
@onready var items_extracted_label = find_child("ItemsExtractedValue", true, false)

var _is_refreshing = false

func _ready():
	visibility_changed.connect(_on_visibility_changed)
	refresh_stats()

func _on_visibility_changed():
	if is_visible_in_tree():
		refresh_stats()

func refresh_stats():
	if _is_refreshing: return
	_is_refreshing = true
	
	print("[TelemetryView] Fetching stats from backend...")
	var url = "http://127.0.0.1:8088/admin/telemetry/stats"
	
	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_request_completed)
	
	var err = http_request.request(url)
	if err != OK:
		print("[TelemetryView] Error starting HTTP request: ", err)
		_is_refreshing = false
		http_request.queue_free()

func _on_request_completed(result, response_code, headers, body):
	_is_refreshing = false
	var http_request = get_child(get_child_count() - 1)
	if http_request is HTTPRequest:
		http_request.queue_free()
		
	if response_code != 200:
		print("[TelemetryView] HTTP Error: ", response_code)
		return
		
	var json = JSON.new()
	var parse_err = json.parse(body.get_string_from_utf8())
	if parse_err != OK:
		print("[TelemetryView] JSON Parse Error: ", json.get_error_message())
		return
		
	var data = json.get_data()
	_update_ui(data)

func _update_ui(data: Dictionary):
	if total_deaths_label:
		total_deaths_label.text = str(data.get("total_deaths", 0))
	if total_damage_label:
		total_damage_label.text = "%.1f" % data.get("total_damage", 0.0)
	if items_extracted_label:
		items_extracted_label.text = str(data.get("items_extracted", 0))
	
	print("[TelemetryView] Stats updated.")
