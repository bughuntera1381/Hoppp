extends Node3D
## Match flow: menu -> match (1v1 or training) -> result. Owns world, UI, scoring and respawns.
## Combat uses a simple take_damage(amount, attacker, hit_pos) interface so the same
## logic can later move to a server-authoritative model.

const ArenaScript = preload("res://Arena/arena.gd")
const FxScript = preload("res://Effects/effects.gd")
const PlayerScript = preload("res://Player/player.gd")
const EnemyScript = preload("res://Enemies/enemy.gd")
const TouchScript = preload("res://Input/touch_controls.gd")
const HudScript = preload("res://UI/hud.gd")

const MATCH_TIME := 240.0
const RESPAWN_DELAY := 2.0

enum State { MENU, PLAYING, ENDED }

var state: int = State.MENU
var training := false
var time_left := MATCH_TIME
var player_score := 0
var enemy_score := 0
var player_respawn := -1.0
var enemy_respawn := -1.0
var shadows_on := true

var arena
var fx
var player
var enemy
var touch
var hud
var ui: CanvasLayer
var menu_panel: Control
var pause_panel: Control
var end_panel: Control
var edit_bar: Control
var end_label: Label
var scale_label: Label
var sens_label: Label
var shadow_btn: Button

func _ready() -> void:
	randomize()
	arena = ArenaScript.new()
	add_child(arena)
	fx = FxScript.new()
	add_child(fx)
	player = PlayerScript.new()
	add_child(player)
	enemy = EnemyScript.new()
	add_child(enemy)
	_build_ui()
	player.touch = touch
	player.setup_fx(fx)
	enemy.target = player
	enemy.fx = fx
	enemy.waypoints = arena.waypoints
	player.died.connect(_on_player_died)
	enemy.died.connect(_on_enemy_died)
	player.damaged.connect(hud.on_player_damaged)
	player.hit_marker.connect(hud.on_hit_marker)
	hud.game = self
	hud.player = player
	hud.enemy = enemy
	hud.arena = arena
	touch.load_layout()
	touch.settings_requested.connect(_open_pause)
	player.global_position = Vector3(0, 1, 25)
	enemy.global_position = Vector3(0, 1, -25)
	_update_labels()
	_show_menu()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		_open_pause()

func _process(delta: float) -> void:
	if state != State.PLAYING:
		return
	if not training:
		time_left -= delta
		if time_left <= 0.0:
			time_left = 0.0
			_end_match()
			return
	if player_respawn > 0.0:
		player_respawn -= delta
		if player_respawn <= 0.0:
			var ps: Vector3 = _pick_spawn(enemy.global_position)
			player.respawn(ps, _yaw_to_center(ps))
	if enemy_respawn > 0.0:
		enemy_respawn -= delta
		if enemy_respawn <= 0.0:
			var es: Vector3 = _pick_spawn(player.global_position)
			enemy.respawn(es, _yaw_to_center(es))

# ------------------------------------------------------------------ match
func _pick_spawn(from: Vector3) -> Vector3:
	var best: Vector3 = arena.spawn_points[0]
	var best_d := -1.0
	for sp in arena.spawn_points:
		var d: float = from.distance_to(sp) + randf() * 8.0
		if d > best_d:
			best_d = d
			best = sp
	return best

func _yaw_to_center(p: Vector3) -> float:
	var d := Vector3.ZERO - p
	return atan2(-d.x, -d.z)

func _start_match(train: bool) -> void:
	training = train
	player_score = 0
	enemy_score = 0
	time_left = MATCH_TIME
	player_respawn = -1.0
	enemy_respawn = -1.0
	enemy.can_shoot = not train
	player.weapon.infinite_ammo = train
	var ps: Vector3 = arena.spawn_points[randi() % arena.spawn_points.size()]
	player.respawn(ps, _yaw_to_center(ps))
	var es: Vector3 = _pick_spawn(ps)
	enemy.respawn(es, _yaw_to_center(es))
	state = State.PLAYING
	menu_panel.hide()
	end_panel.hide()
	pause_panel.hide()
	hud.visible = true
	touch.visible = true
	touch.active = true
	get_tree().paused = false
	hud.show_banner("FIGHT!", Color(1, 0.7, 0.2))

func _on_player_died(_killer) -> void:
	enemy_score += 1
	player_respawn = RESPAWN_DELAY
	hud.show_banner("ELIMINATED", Color(1, 0.3, 0.25))

func _on_enemy_died(_killer) -> void:
	player_score += 1
	enemy_respawn = RESPAWN_DELAY
	player.weapon.add_reserve(28)
	hud.show_banner("ENEMY DOWN  +1", Color(1, 0.8, 0.2))

func _end_match() -> void:
	state = State.ENDED
	touch.active = false
	touch.reset_state()
	player.frozen = true
	enemy.frozen = true
	var res := "DRAW"
	if player_score > enemy_score:
		res = "VICTORY"
	elif player_score < enemy_score:
		res = "DEFEAT"
	end_label.text = "%s\n%d  -  %d" % [res, player_score, enemy_score]
	end_panel.show()

# ------------------------------------------------------------------ pause / settings
func _open_pause() -> void:
	if state != State.PLAYING or get_tree().paused:
		return
	get_tree().paused = true
	touch.active = false
	touch.reset_state()
	_update_labels()
	pause_panel.show()

func _close_pause() -> void:
	get_tree().paused = false
	pause_panel.hide()
	touch.active = true

func _adj_scale(d: float) -> void:
	touch.hud_scale = clampf(touch.hud_scale + d, 0.6, 1.6)
	touch.save_layout()
	_update_labels()

func _adj_sens(d: float) -> void:
	touch.sens = clampf(touch.sens + d, 0.3, 2.5)
	touch.save_layout()
	_update_labels()

func _toggle_shadows() -> void:
	shadows_on = not shadows_on
	arena.sun.shadow_enabled = shadows_on
	_update_labels()

func _reset_layout() -> void:
	touch.reset_layout()
	_update_labels()

func _enter_edit() -> void:
	pause_panel.hide()
	edit_bar.show()
	touch.edit_mode = true

func _exit_edit() -> void:
	touch.edit_mode = false
	touch.save_layout()
	edit_bar.hide()
	pause_panel.show()

func _quit_to_menu() -> void:
	get_tree().paused = false
	state = State.MENU
	player.frozen = true
	enemy.frozen = true
	pause_panel.hide()
	end_panel.hide()
	_show_menu()

func _update_labels() -> void:
	scale_label.text = "%.1f" % touch.hud_scale
	sens_label.text = "%.1f" % touch.sens
	shadow_btn.text = "SHADOWS: " + ("ON" if shadows_on else "OFF")

func _show_menu() -> void:
	touch.active = false
	touch.reset_state()
	hud.visible = false
	touch.visible = false
	menu_panel.show()

# ------------------------------------------------------------------ UI construction
func _btn(parent: Node, text: String, cb: Callable, w := 380, h := 70, fs := 28) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, h)
	b.add_theme_font_size_override("font_size", fs)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b

func _label(parent: Node, text: String, fs: int, col := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(l)
	return l

func _panel(title: String) -> Array:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.05, 0.82)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	center.add_child(vb)
	_label(vb, title, 46, Color(1, 0.6, 0.15))
	ui.add_child(root)
	root.hide()
	return [root, vb]

func _row(vb: Node, title: String, minus: Callable, plus: Callable) -> Label:
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 14)
	vb.add_child(hb)
	var t := Label.new()
	t.text = title
	t.custom_minimum_size = Vector2(240, 0)
	t.add_theme_font_size_override("font_size", 24)
	hb.add_child(t)
	_btn(hb, "-", minus, 70, 56, 30)
	var v := Label.new()
	v.custom_minimum_size = Vector2(70, 0)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_theme_font_size_override("font_size", 26)
	hb.add_child(v)
	_btn(hb, "+", plus, 70, 56, 30)
	return v

func _build_ui() -> void:
	ui = CanvasLayer.new()
	ui.layer = 10
	ui.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(ui)
	hud = HudScript.new()
	ui.add_child(hud)
	touch = TouchScript.new()
	ui.add_child(touch)

	var m := _panel("APEX ARENA")
	menu_panel = m[0]
	_label(m[1], "Slide  -  Slide Jump  -  Bunny Hop  -  Strafe", 20, Color(1, 1, 1, 0.7))
	_btn(m[1], "1v1 MATCH  (4:00)", func(): _start_match(false))
	_btn(m[1], "TRAINING", func(): _start_match(true))
	_btn(m[1], "QUIT", func(): get_tree().quit(), 380, 56, 24)

	var p := _panel("PAUSED")
	pause_panel = p[0]
	_btn(p[1], "RESUME", _close_pause)
	scale_label = _row(p[1], "HUD SCALE", _adj_scale.bind(-0.1), _adj_scale.bind(0.1))
	sens_label = _row(p[1], "LOOK SENSITIVITY", _adj_sens.bind(-0.1), _adj_sens.bind(0.1))
	shadow_btn = _btn(p[1], "SHADOWS", _toggle_shadows, 380, 56, 24)
	_btn(p[1], "EDIT HUD LAYOUT", _enter_edit, 380, 56, 24)
	_btn(p[1], "RESET HUD LAYOUT", _reset_layout, 380, 56, 24)
	_btn(p[1], "QUIT TO MENU", _quit_to_menu, 380, 56, 24)

	var e := _panel("")
	end_panel = e[0]
	end_label = _label(e[1], "", 54, Color.WHITE)
	_btn(e[1], "PLAY AGAIN", func(): _start_match(training))
	_btn(e[1], "MENU", _quit_to_menu, 380, 56, 24)

	edit_bar = Control.new()
	edit_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	edit_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var done := Button.new()
	done.text = "DONE"
	done.custom_minimum_size = Vector2(220, 64)
	done.add_theme_font_size_override("font_size", 28)
	done.position = Vector2(530, 20)
	done.pressed.connect(_exit_edit)
	edit_bar.add_child(done)
	ui.add_child(edit_bar)
	edit_bar.hide()
