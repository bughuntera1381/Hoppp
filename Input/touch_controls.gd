
extends Control
class_name MobileHUD

## Mobile FPS HUD - Godot 4
## Multi-touch controls, floating joystick, camera drag and HUD editor.

signal settings_requested
signal hud_saved

const CFG_PATH := "user://hud.cfg"
const STICK_R := 85.0
const STICK_DEADZONE := 0.12
const SPRINT_THRESHOLD := 0.92
const BUTTON_HIT_PADDING := 10.0
const SAFE_MARGIN := 0.05

var active := false
var edit_mode := false

var hud_scale := 1.0
var sens := 1.0

var move_vec := Vector2.ZERO
var sprint := false
var look_delta := Vector2.ZERO

var buttons := {
	"fire": {
		"pos": Vector2(0.82, 0.65),
		"r": 62.0,
		"label": "FIRE",
		"look": true,
		"col": Color(1.0, 0.45, 0.1)
	},
	"fire_l": {
		"pos": Vector2(0.28, 0.45),
		"r": 44.0,
		"label": "FIRE",
		"look": false,
		"col": Color(1.0, 0.45, 0.1)
	},
	"aim": {
		"pos": Vector2(0.72, 0.45),
		"r": 38.0,
		"label": "AIM",
		"look": true,
		"col": Color(0.4, 0.8, 1.0)
	},
	"jump": {
		"pos": Vector2(0.88, 0.80),
		"r": 46.0,
		"label": "JUMP",
		"look": false,
		"col": Color.WHITE
	},
	"slide": {
		"pos": Vector2(0.88, 0.52),
		"r": 40.0,
		"label": "SLIDE",
		"look": false,
		"col": Color(0.5, 1.0, 0.6)
	},
	"reload": {
		"pos": Vector2(0.68, 0.85),
		"r": 34.0,
		"label": "RELOAD",
		"look": false,
		"col": Color.WHITE
	},
	"switch": {
		"pos": Vector2(0.58, 0.85),
		"r": 30.0,
		"label": "SWAP",
		"look": false,
		"col": Color.WHITE
	},
	"gear": {
		"pos": Vector2(0.88, 0.15),
		"r": 24.0,
		"label": "II",
		"look": false,
		"col": Color.WHITE
	},
	"save_edit": {
		"pos": Vector2(0.50, 0.15),
		"r": 35.0,
		"label": "SAVE",
		"look": false,
		"col": Color(0.2, 1.0, 0.2)
	}
}

var _defaults := {}

# finger index -> role
var _fingers := {}

# button name -> owning finger index
var _btn_finger := {}

var _stick_finger := -1
var _stick_center := Vector2.ZERO
var _stick_pos := Vector2.ZERO

var _stick_home := Vector2(0.15, 0.75)

var _jump_edge := false
var _reload_edge := false
var _switch_edge := false


# --------------------------------------------------
# BUTTON STATES
# --------------------------------------------------

var fire_held: bool:
	get:
		return _btn_finger.has("fire") or _btn_finger.has("fire_l")

var aim_held: bool:
	get:
		return _btn_finger.has("aim")

var slide_held: bool:
	get:
		return _btn_finger.has("slide")


# --------------------------------------------------
# INITIALIZATION
# --------------------------------------------------

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_defaults = buttons.duplicate(true)

	load_layout()
	queue_redraw()


func _process(_delta: float) -> void:
	if active or edit_mode:
		queue_redraw()


# --------------------------------------------------
# PUBLIC API
# --------------------------------------------------

func set_active(value: bool) -> void:
	active = value

	if not active and not edit_mode:
		reset_state()

	queue_redraw()


func begin_edit_mode() -> void:
	edit_mode = true
	reset_state()
	queue_redraw()


func end_edit_mode(save: bool = true) -> void:
	if save:
		save_layout()

	edit_mode = false
	reset_state()
	queue_redraw()


func set_sensitivity(value: float) -> void:
	sens = clampf(value, 0.3, 2.5)
	save_layout()


func set_hud_scale(value: float) -> void:
	hud_scale = clampf(value, 0.6, 1.6)
	queue_redraw()


func get_move_vector() -> Vector2:
	return move_vec


func is_sprinting() -> bool:
	return sprint


func consume_look() -> Vector2:
	var result := look_delta * sens
	look_delta = Vector2.ZERO
	return result


func consume_jump() -> bool:
	var result := _jump_edge
	_jump_edge = false
	return result


func consume_reload() -> bool:
	var result := _reload_edge
	_reload_edge = false
	return result


func consume_switch() -> bool:
	var result := _switch_edge
	_switch_edge = false
	return result


# --------------------------------------------------
# INPUT RESET
# --------------------------------------------------

func reset_state() -> void:
	_fingers.clear()
	_btn_finger.clear()

	_stick_finger = -1

	move_vec = Vector2.ZERO
	sprint = false

	look_delta = Vector2.ZERO

	_jump_edge = false
	_reload_edge = false
	_switch_edge = false

	queue_redraw()


# --------------------------------------------------
# COORDINATES
# --------------------------------------------------

func _to_local(pos: Vector2) -> Vector2:
	return make_canvas_position_local(pos)


func _center(b: Dictionary) -> Vector2:
	var p: Vector2 = b["pos"]
	return Vector2(p.x * size.x, p.y * size.y)


func _clamp_button_position(name: String, p: Vector2) -> Vector2:
	var radius := float(buttons[name]["r"]) * hud_scale
	var margin_x := (radius + BUTTON_HIT_PADDING) / maxf(size.x, 1.0)
	var margin_y := (radius + BUTTON_HIT_PADDING) / maxf(size.y, 1.0)

	var min_x := maxf(SAFE_MARGIN, margin_x)
	var max_x := minf(1.0 - SAFE_MARGIN, 1.0 - margin_x)

	var min_y := maxf(SAFE_MARGIN, margin_y)
	var max_y := minf(1.0 - SAFE_MARGIN, 1.0 - margin_y)

	if min_x > max_x:
		min_x = 0.5
		max_x = 0.5

	if min_y > max_y:
		min_y = 0.5
		max_y = 0.5

	return Vector2(
		clampf(p.x, min_x, max_x),
		clampf(p.y, min_y, max_y)
	)


# --------------------------------------------------
# BUTTON DETECTION
# --------------------------------------------------

func _hit_button(p: Vector2) -> String:
	var best := ""
	var best_d := INF

	for k in buttons.keys():

		if k == "save_edit" and not edit_mode:
			continue

		var b: Dictionary = buttons[k]

		var distance := p.distance_to(_center(b))
		var radius := float(b["r"]) * hud_scale + BUTTON_HIT_PADDING

		if distance <= radius and distance < best_d:
			best = String(k)
			best_d = distance

	return best


# --------------------------------------------------
# TOUCH INPUT
# --------------------------------------------------

func _input(event: InputEvent) -> void:

	if not (active or edit_mode):
		return

	if event is InputEventScreenTouch:

		var local_pos := _to_local(event.position)

		if event.pressed:
			_press(event.index, local_pos)
		else:
			_release(event.index)

	elif event is InputEventScreenDrag:

		var local_pos := _to_local(event.position)

		_drag(
			event.index,
			local_pos,
			event.relative
		)


# --------------------------------------------------
# PRESS
# --------------------------------------------------

func _press(idx: int, pos: Vector2) -> void:

	if _fingers.has(idx):
		return

	var bn := _hit_button(pos)

	# EDIT MODE
	if edit_mode:

		if bn == "save_edit":
			end_edit_mode(true)
			return

		if bn != "":
			_fingers[idx] = "edit:" + bn

		return

	# NORMAL BUTTON INPUT
	if bn != "":

		# Prevent two fingers from incorrectly owning one button.
		if _btn_finger.has(bn):
			return

		_btn_finger[bn] = idx
		_fingers[idx] = bn

		match bn:

			"jump":
				_jump_edge = true

			"reload":
				_reload_edge = true

			"switch":
				_switch_edge = true

			"gear":
				_btn_finger.erase(bn)
				_fingers.erase(idx)
				settings_requested.emit()

		queue_redraw()
		return

	# JOYSTICK
	if pos.x < size.x * 0.42 and _stick_finger < 0:

		_stick_finger = idx

		_stick_center = pos
		_stick_pos = pos

		_fingers[idx] = "stick"

		_update_stick()
		queue_redraw()

		return

	# CAMERA LOOK
	_fingers[idx] = "look"


# --------------------------------------------------
# DRAG
# --------------------------------------------------

func _drag(idx: int, pos: Vector2, rel: Vector2) -> void:

	if not _fingers.has(idx):
		return

	var role: String = String(_fingers[idx])

	# HUD EDITOR
	if edit_mode:

		if role.begins_with("edit:"):

			var bn := role.substr(5)

			if buttons.has(bn):
				var normalized := Vector2(
					pos.x / maxf(size.x, 1.0),
					pos.y / maxf(size.y, 1.0)
				)

				buttons[bn]["pos"] = _clamp_button_position(
					bn,
					normalized
				)

		queue_redraw()
		return

	# JOYSTICK
	if role == "stick":

		_stick_pos = pos
		_update_stick()

	# CAMERA
	elif role == "look":

		look_delta += rel

	# FIRE / AIM CAMERA DRAG
	elif buttons.has(role):

		if bool(buttons[role]["look"]):
			look_delta += rel


# --------------------------------------------------
# RELEASE
# --------------------------------------------------

func _release(idx: int) -> void:

	if not _fingers.has(idx):
		return

	var role: String = String(_fingers[idx])

	_fingers.erase(idx)

	# JOYSTICK RELEASE
	if role == "stick":

		if _stick_finger == idx:

			_stick_finger = -1

			move_vec = Vector2.ZERO
			sprint = false

	# BUTTON RELEASE
	elif _btn_finger.get(role, -1) == idx:

		_btn_finger.erase(role)

	queue_redraw()


# --------------------------------------------------
# FLOATING JOYSTICK
# --------------------------------------------------

func _update_stick() -> void:

	var radius := STICK_R * hud_scale

	var delta_pos := _stick_pos - _stick_center

	var raw := delta_pos / maxf(radius, 1.0)

	raw = raw.limit_length(1.0)

	var magnitude := raw.length()

	# Deadzone + smooth remapping
	if magnitude <= STICK_DEADZONE:

		move_vec = Vector2.ZERO

	else:

		var normalized_magnitude := (
			(magnitude - STICK_DEADZONE)
			/ (1.0 - STICK_DEADZONE)
		)

		move_vec = raw.normalized() * normalized_magnitude

	# Screen Y is inverted.
	move_vec.y *= -1.0

	move_vec = move_vec.limit_length(1.0)

	# Sprint detection
	if move_vec.length() >= SPRINT_THRESHOLD:

		sprint = true

	elif move_vec.length() < 0.35:

		sprint = false


# --------------------------------------------------
# DRAW HUD
# --------------------------------------------------

func _draw() -> void:

	if not (active or edit_mode):
		return

	var font := ThemeDB.fallback_font

	var radius := STICK_R * hud_scale

	var stick_center := Vector2(
		size.x * _stick_home.x,
		size.y * _stick_home.y
	)

	var stick_offset := Vector2.ZERO

	if _stick_finger >= 0:

		stick_center = _stick_center

		stick_offset = (
			_stick_pos - _stick_center
		).limit_length(radius)

	# JOYSTICK
	if not edit_mode:

		draw_circle(
			stick_center,
			radius,
			Color(1, 1, 1, 0.07)
		)

		var ring_color := (
			Color(1.0, 0.6, 0.15, 0.7)
			if sprint
			else Color(1, 1, 1, 0.35)
		)

		draw_arc(
			stick_center,
			radius,
			0.0,
			TAU,
			48,
			ring_color,
			2.5,
			true
		)

		draw_circle(
			stick_center + stick_offset,
			radius * 0.38,
			Color(
				1, 1, 1,
				0.45 if _stick_finger >= 0 else 0.22
			)
		)

	# BUTTONS
	var font_size := maxi(
		12,
		int(15.0 * hud_scale)
	)

	for k in buttons.keys():

		if k == "save_edit" and not edit_mode:
			continue

		var b: Dictionary = buttons[k]

		var center := _center(b)

		var button_radius := float(b["r"]) * hud_scale

		var color: Color = b["col"]

		var down: bool = _btn_finger.has(k)

		var alpha := 0.6 if edit_mode else 1.0

		var fill_alpha := (
			0.38 if down else 0.14
		) * alpha

		var border_alpha := (
			0.9 if down else 0.55
		) * alpha

		draw_circle(
			center,
			button_radius,
			Color(
				color.r,
				color.g,
				color.b,
				fill_alpha
			)
		)

		draw_arc(
			center,
			button_radius,
			0.0,
			TAU,
			40,
			Color(
				color.r,
				color.g,
				color.b,
				border_alpha
			),
			2.5,
			true
		)

		draw_string(
			font,
			center + Vector2(-button_radius, font_size * 0.35),
			String(b["label"]),
			HORIZONTAL_ALIGNMENT_CENTER,
			button_radius * 2.0,
			font_size,
			Color(1, 1, 1, 0.95 * alpha)
		)

	# EDIT MODE MESSAGE
	if edit_mode:

		draw_string(
			font,
			Vector2(0, size.y * 0.1),
			"DRAG BUTTONS TO MOVE - TAP SAVE WHEN DONE",
			HORIZONTAL_ALIGNMENT_CENTER,
			size.x,
			18,
			Color(1, 0.8, 0.3)
		)


# --------------------------------------------------
# SAVE CONFIGURATION
# --------------------------------------------------

func save_layout() -> void:

	var config := ConfigFile.new()

	for k in buttons.keys():

		if k == "save_edit":
			continue

		var p: Vector2 = buttons[k]["pos"]

		config.set_value(
			"buttons",
			String(k),
			p
		)

	config.set_value(
		"settings",
		"hud_scale",
		hud_scale
	)

	config.set_value(
		"settings",
		"sens",
		sens
	)

	var error := config.save(CFG_PATH)

	if error == OK:
		hud_saved.emit()
	else:
		push_warning("HUD configuration save failed: " + str(error))


# --------------------------------------------------
# LOAD CONFIGURATION
# --------------------------------------------------

func load_layout() -> void:

	var config := ConfigFile.new()

	var error := config.load(CFG_PATH)

	if error != OK:
		return

	for k in buttons.keys():

		if k == "save_edit":
			continue

		var default_pos: Vector2 = buttons[k]["pos"]

		var loaded: Variant = config.get_value(
			"buttons",
			String(k),
			default_pos
		)

		if loaded is Vector2 and loaded.is_finite():

			buttons[k]["pos"] = _clamp_button_position(
				String(k),
				loaded
			)

	hud_scale = clampf(
		float(config.get_value(
			"settings",
			"hud_scale",
			1.0
		)),
		0.6,
		1.6
	)

	sens = clampf(
		float(config.get_value(
			"settings",
			"sens",
			1.0
		)),
		0.3,
		2.5
	)

	queue_redraw()


# --------------------------------------------------
# RESET LAYOUT
# --------------------------------------------------

func reset_layout() -> void:

	for k in buttons.keys():

		if k == "save_edit":
			continue

		buttons[k]["pos"] = _defaults[k]["pos"]

	hud_scale = 1.0
	sens = 1.0

	reset_state()
	save_layout()

	queue_redraw()
