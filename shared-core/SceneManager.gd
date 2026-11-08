extends Node

## SceneManager.gd - Asynchronous Scene Loading
## Prevents main-thread freezing to keep UDP/Heartbeats alive.

signal load_finished
signal load_progress(percent: float)

var _loading_scene_path: String = ""
var _in_progress: bool = false
var loading_screen_path: String = "res://loading_screen.tscn"

func change_scene_async(path: String):
	if _in_progress:
		print("Warning: Load already in progress")
		return
		
	_loading_scene_path = path
	_in_progress = true
	
	# Cleanup UI before transition
	if has_node("/root/UIOrchestrator"):
		get_node("/root/UIOrchestrator").close_all_windows()
	
	# Transition to loading screen first
	if loading_screen_path != "" and get_tree().current_scene.scene_file_path != loading_screen_path:
		get_tree().call_deferred("change_scene_to_file", loading_screen_path)
		# Wait a bit for the scene tree to settle
		await get_tree().process_frame
		await get_tree().process_frame
	
	var err = ResourceLoader.load_threaded_request(path)
	if err != OK:
		print("Error: Failed to request async load for ", path)
		_in_progress = false
		return
		
	set_process(true)
	print("Started async load for: ", path)

func _ready():
	set_process(false)

func _process(_delta):
	if not _in_progress:
		set_process(false)
		return
		
	var progress = []
	var status = ResourceLoader.load_threaded_get_status(_loading_scene_path, progress)
	
	match status:
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			load_progress.emit(progress[0] * 100.0)
		ResourceLoader.THREAD_LOAD_LOADED:
			var new_scene = ResourceLoader.load_threaded_get(_loading_scene_path)
			if new_scene:
				get_tree().change_scene_to_packed(new_scene)
				print("Async load complete!")
			else:
				push_error("SceneManager Error: Loaded scene is null for " + _loading_scene_path)
			
			_in_progress = false
			load_finished.emit()
			set_process(false)
		ResourceLoader.THREAD_LOAD_FAILED:
			print("Error: Async load failed for ", _loading_scene_path)
			_in_progress = false
			set_process(false)
		ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			print("Error: Invalid resource path ", _loading_scene_path)
			_in_progress = false
			set_process(false)
