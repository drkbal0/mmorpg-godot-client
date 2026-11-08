extends Node

signal target_changed(new_target_sid: int)

var current_target_sid: int = 0:
	set(val):
		if current_target_sid != val:
			current_target_sid = val
			target_changed.emit(val)
			print("[TargetManager] Target changed to SID: %d" % val)

func select_target(sid: int):
	current_target_sid = sid

func clear_target():
	current_target_sid = 0

func _input(event):
	if event.is_action_pressed("ui_cancel"): # ESC
		clear_target()

func is_hostile(sid: int) -> bool:
	# Protocol rule: 0x8... are NPCs/Static, but we'll need to know which are hostile.
	# For now, let's assume all NPCs (0x8) are hostile if they have the outline.
	return (sid & 0x80000000) != 0
