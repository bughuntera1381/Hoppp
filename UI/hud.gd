extends Control
## In-game HUD drawn with canvas primitives: health, ammo, timer, score, kills,
## crosshair, hit markers, damage indicators, reload ring, minimap, banners.

var game
var player
var enemy
var arena

var hit_t := 0.0
var hit_kill := false
var hit_head := false
var banner := ""
var banner_col := Color.WHITE
var banner_t := 0.0
var dmg_marks: Array = []
var font: Font

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = ThemeDB.fallback_font

func show_banner(text: String, col: Color, t := 1.6) -> void:
	banner = text
	banner_col = col
	banner_t = t

func on_hit_marker(killed: bool, head: bool) -> void:
	hit_t = 0.25
	hit_kill = killed
	hit_head = head

func on_player_damaged(from_pos: Vector3) -> void:
	dmg_marks.append([from_pos, 1.2])

func _process(delta: float) -> void:
	hit_t = maxf(0.0, hit_t - delta)
	banner_t = maxf(0.0, banner_t - delta)
	for m in dmg_marks:
		m[1] -= delta
	dmg_marks = dmg_marks.filter(func(m): return m[1] > 0.0)
	if visible:
		queue_redraw()

func _txt(text: String, pos: Vector2, fs: int, col: Color) -> void:
	draw_string(font, pos + Vector2(1.5, 1.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.6))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

func _txt_c(text: String, cx: float, y: float, fs: int, col: Color) -> void:
	draw_string(font, Vector2(cx - 300.0 + 1.5, y + 1.5), text, HORIZONTAL_ALIGNMENT_CENTER, 600.0, fs, Color(0, 0, 0, 0.6))
	draw_string(font, Vector2(cx - 300.0, y), text, HORIZONTAL_ALIGNMENT_CENTER, 600.0, fs, col)

func _draw() -> void:
	if game == null or player == null or game.state == 0:
		return
	var s := size
	var k: float = game.touch.hud_scale
	var c := s * 0.5
	if player.health < 35.0 and not player.dead:
		var a: float = (35.0 - player.health) / 35.0 * 0.35
		var red := Color(0.8, 0.0, 0.0, a)
		draw_rect(Rect2(0, 0, s.x, 40), red)
		draw_rect(Rect2(0, s.y - 40, s.x, 40), red)
		draw_rect(Rect2(0, 0, 40, s.y), red)
		draw_rect(Rect2(s.x - 40, 0, 40, s.y), red)
	_draw_crosshair(c)
	_draw_top(s, k)
	_draw_minimap(k)
	_draw_bars(s, k)
	_draw_damage(c)
	if banner_t > 0.0:
		var al: float = clampf(banner_t / 0.4, 0.0, 1.0)
		_txt_c(banner, c.x, s.y * 0.3, int(44.0 * k), Color(banner_col.r, banner_col.g, banner_col.b, al))
	if player.dead:
		draw_rect(Rect2(Vector2.ZERO, s), Color(0.35, 0.0, 0.0, 0.3))
		_txt_c("ELIMINATED", c.x, c.y, 56, Color(1, 0.3, 0.25))
		_txt_c("Respawning...", c.x, c.y + 44.0, 24, Color(1, 1, 1, 0.8))

func _draw_crosshair(c: Vector2) -> void:
	if player.dead:
		return
	var wp = player.weapon
	var gap: float = 5.0 + wp.spread_now * 5.0
	var col := Color(1, 1, 1, 0.9)
	if wp.aiming:
		gap *= 0.5
	for d in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		draw_line(c + d * gap, c + d * (gap + 9.0), col, 2.0)
	draw_circle(c, 1.5, col)
	if hit_t > 0.0:
		var hc := Color(1, 0.25, 0.2) if hit_kill else (Color(1, 0.7, 0.1) if hit_head else Color(1, 1, 1))
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			draw_line(c + d * 8.0, c + d * 16.0, hc, 3.0)
	if wp.reloading:
		draw_arc(c, 30.0, -PI * 0.5, -PI * 0.5 + TAU * wp.reload_progress(), 32, Color(1, 0.8, 0.2), 3.0, true)

func _draw_top(s: Vector2, k: float) -> void:
	var t: float = game.time_left
	var label := "TRAINING"
	if not game.training:
		label = "%02d:%02d" % [floori(t / 60.0), int(t) % 60]
	draw_rect(Rect2(s.x * 0.5 - 70.0 * k, 8, 140.0 * k, 34.0 * k), Color(0, 0, 0, 0.4))
	_txt_c(label, s.x * 0.5, 34.0 * k, int(24.0 * k), Color.WHITE)
	_txt_c("YOU  %d  -  %d  BOT" % [game.player_score, game.enemy_score], s.x * 0.5, 64.0 * k, int(18.0 * k), Color(1, 0.85, 0.4))

func _draw_minimap(k: float) -> void:
	var sz: float = 120.0 * k
	var o := Vector2(16, 16)
	draw_rect(Rect2(o, Vector2(sz, sz)), Color(0, 0, 0, 0.4))
	draw_rect(Rect2(o, Vector2(sz, sz)), Color(1, 1, 1, 0.4), false, 1.5)
	var half: float = arena.half
	var sc: float = sz / (half * 2.0)
	for r in arena.map_rects:
		var rr: Rect2 = r
		draw_rect(Rect2(o + (rr.position + Vector2(half, half)) * sc, rr.size * sc), Color(0.7, 0.7, 0.75, 0.7))
	if not enemy.dead and player.global_position.distance_to(enemy.global_position) < 35.0:
		var ep := o + (Vector2(enemy.global_position.x, enemy.global_position.z) + Vector2(half, half)) * sc
		draw_circle(ep, 4.0, Color(1, 0.2, 0.2))
	var pp := o + (Vector2(player.global_position.x, player.global_position.z) + Vector2(half, half)) * sc
	var yaw: float = player.rotation.y
	var f := Vector2(-sin(yaw), -cos(yaw))
	var rt := Vector2(-f.y, f.x)
	draw_colored_polygon(PackedVector2Array([pp + f * 7.0, pp - f * 4.0 + rt * 4.0, pp - f * 4.0 - rt * 4.0]), Color(0.3, 1, 0.5))
	_txt("KILLS %d" % game.player_score, o + Vector2(0, sz + 22.0 * k), int(18.0 * k), Color.WHITE)
	_txt("SPD %.1f" % player.hspeed, o + Vector2(0, sz + 44.0 * k), int(15.0 * k), Color(0.6, 0.9, 1.0))

func _draw_bars(s: Vector2, k: float) -> void:
	var x := s.x * 0.27
	var y := s.y - 40.0 * k
	var w: float = s.x * 0.23
	var segs := 10
	var seg_w: float = w / segs
	var frac: float = clampf(player.health / player.max_health, 0.0, 1.0)
	var col := Color(0.3, 0.9, 0.4).lerp(Color(1, 0.2, 0.15), 1.0 - frac)
	for i in segs:
		var on: bool = (float(i) + 0.5) / segs <= frac
		draw_rect(Rect2(x + i * seg_w, y, seg_w - 3.0, 12.0 * k), col if on else Color(1, 1, 1, 0.15))
	_txt("%d" % ceili(player.health), Vector2(x, y - 6.0), int(20.0 * k), Color.WHITE)
	var wp = player.weapon
	var ax: float = s.x * 0.52
	var reserve_txt := "INF" if wp.infinite_ammo else str(wp.reserve[wp.current])
	_txt("%d" % wp.ammo[wp.current], Vector2(ax, y + 12.0 * k), int(40.0 * k), Color(1, 0.85, 0.3) if wp.ammo[wp.current] > 5 else Color(1, 0.3, 0.2))
	_txt("/ " + reserve_txt, Vector2(ax + 62.0 * k, y + 12.0 * k), int(20.0 * k), Color(1, 1, 1, 0.8))
	_txt(wp.weapon_name(), Vector2(ax, y - 28.0 * k), int(14.0 * k), Color(1, 1, 1, 0.7))
	if wp.reloading:
		_txt("RELOADING", Vector2(ax, y - 46.0 * k), int(16.0 * k), Color(1, 0.8, 0.2))

func _draw_damage(c: Vector2) -> void:
	for m in dmg_marks:
		var from: Vector3 = m[0]
		var local: Vector3 = player.global_transform.basis.inverse() * (from - player.global_position)
		var a: float = atan2(local.x, -local.z) - PI * 0.5
		var al: float = clampf(float(m[1]) / 0.6, 0.0, 1.0)
		draw_arc(c, 150.0, a - 0.28, a + 0.28, 12, Color(1, 0.1, 0.1, al), 8.0, true)
