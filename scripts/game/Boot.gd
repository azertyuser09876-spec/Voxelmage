extends Node
## Autoload "Boot" : declare la carte des entrees au demarrage.
## Evite d'ecrire le format verbeux d'InputMap dans project.godot et garantit
## les memes actions sur Windows, Android et navigateur.

const ACTIONS := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"jump": [KEY_SPACE],
	"sneak": [KEY_SHIFT],
	"sprint": [KEY_CTRL],
	"inventory": [KEY_E],
	"chat": [KEY_T],
	"pause": [KEY_ESCAPE],
	"drop": [KEY_Q],
	"cast": [KEY_F],
	"spell_next": [KEY_C],
	"spell_prev": [KEY_X],
	"hotbar_1": [KEY_1],
	"hotbar_2": [KEY_2],
	"hotbar_3": [KEY_3],
	"hotbar_4": [KEY_4],
	"hotbar_5": [KEY_5],
	"hotbar_6": [KEY_6],
	"hotbar_7": [KEY_7],
	"hotbar_8": [KEY_8],
	"hotbar_9": [KEY_9],
}

const MOUSE_ACTIONS := {
	"attack": MOUSE_BUTTON_LEFT,
	"use": MOUSE_BUTTON_RIGHT,
}


func _enter_tree() -> void:
	for action in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key in ACTIONS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
	for action in MOUSE_ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_ACTIONS[action]
		InputMap.action_add_event(action, mb)
	# manette : deplacement + saut
	if not InputMap.has_action("jump"):
		InputMap.add_action("jump")
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_A
	InputMap.action_add_event("jump", pad)
