extends Node3D
## Modular weapon controller: 3D viewmodels, hitscan, recoil, reload, switching, tilt.
## Stats live in weapon_data.gd. Owner (player) sets the input fields each frame, then calls tick().

signal fired
signal hit_enemy(killed: bool, head: bool)

const Data = preload("res://Weapons/weapon_data.gd")
const SWITCH_TIME := 0.38

var player
var cam: Camera3D
var fx
var target_mask := 5          # world (1) + enemy layer (4)
var infinite_ammo := false

var current := 0
var ammo: Array[int] = []
var reserve: Array[int] = []
var reloading := false
var reload_t := 0.0
var switch_t := SWITCH_TIME
var pending := -1
var cooldown := 0.0
var bloom := 0.0
var was_firing := false
var spread_now := 0.0

# Inputs written by the owner every frame
var firing := false
var aiming := false
var sliding := false
var on_floor := true
var move_speed := 0.0
var look_delta := Vector2.ZERO
var tilt_target := 0.0       # radians; + = tilt left, - = tilt right

var models: Array[Node3D] = []
var base_pos := Vector3(0.23, -0.23, -0.48)
var ads_t := 0.0
var roll := 0.0
var kick := 0.0
var sway := Vector2.ZERO
var bob_t := 0.0
var slide_pose := 0.0
var flash_t := 0.0
var _mats := {}

func _mat(c: Color) -> StandardMaterial3D:
	var key := c.to_html()
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.55
	m.metallic = 0.25
	_mats[key] = m
	return m

func _box(parent: Node3D, size: Vector3, pos: Vector3, col: Color, rot_deg := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(col)
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

func _flash_node(parent: Node3D, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.055
	sm.height = 0.11
	sm.radial_segments = 6
	sm.rings = 3
	mi.mesh = sm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.85, 0.35)
	mi.material_override = m
	mi.position = pos
	mi.visible = false
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

func _build_rifle() -> Node3D:
	var m := Node3D.new()
	var dark := Color(0.14, 0.15, 0.17)
	var mid := Color(0.26, 0.28, 0.31)
	var orange := Color(0.95, 0.45, 0.1)
	var glove := Color(0.12, 0.12, 0.13)
	_box(m, Vector3(0.07, 0.1, 0.5), Vector3(0, 0, 0), mid)
	_box(m, Vector3(0.075, 0.075, 0.28), Vector3(0, -0.005, -0.36), dark)
	_box(m, Vector3(0.025, 0.025, 0.28), Vector3(0, 0.02, -0.6), dark)
	_box(m, Vector3(0.06, 0.12, 0.22), Vector3(0, -0.02, 0.33), dark)
	_box(m, Vector3(0.05, 0.12, 0.06), Vector3(0, -0.1, 0.1), dark, Vector3(15, 0, 0))
	_box(m, Vector3(0.04, 0.05, 0.14), Vector3(0, 0.075, -0.04), dark)
	_box(m, Vector3(0.02, 0.02, 0.02), Vector3(0, 0.1, -0.1), orange)
	_box(m, Vector3(0.072, 0.02, 0.22), Vector3(0, 0.055, -0.2), orange)
	_box(m, Vector3(0.09, 0.09, 0.09), Vector3(0, -0.07, -0.34), glove)
	_box(m, Vector3(0.07, 0.1, 0.1), Vector3(0, -0.12, 0.1), glove)
	var mag := _box(m, Vector3(0.05, 0.17, 0.08), Vector3(0, -0.13, -0.06), dark)
	var muzzle := Node3D.new()
	muzzle.position = Vector3(0, 0.02, -0.76)
	m.add_child(muzzle)
	var fl := _flash_node(m, Vector3(0, 0.02, -0.8))
	m.set_meta("mag", mag)
	m.set_meta("mag_y", mag.position.y)
	m.set_meta("muzzle", muzzle)
	m.set_meta("flash", fl)
	m.set_meta("ads_y", 0.1)
	return m

func _build_pistol() -> Node3D:
	var m := Node3D.new()
	var dark := Color(0.14, 0.15, 0.17)
	var mid := Color(0.3, 0.32, 0.36)
	var orange := Color(0.95, 0.45, 0.1)
	var glove := Color(0.12, 0.12, 0.13)
	_box(m, Vector3(0.05, 0.06, 0.24), Vector3(0, 0.0, -0.05), mid)
	_box(m, Vector3(0.045, 0.04, 0.2), Vector3(0, -0.05, -0.04), dark)
	_box(m, Vector3(0.045, 0.11, 0.06), Vector3(0, -0.1, 0.07), dark, Vector3(15, 0, 0))
	_box(m, Vector3(0.052, 0.015, 0.1), Vector3(0, 0.035, -0.05), orange)
	_box(m, Vector3(0.07, 0.1, 0.09), Vector3(0, -0.1, 0.07), glove)
	var mag := _box(m, Vector3(0.04, 0.09, 0.05), Vector3(0, -0.12, 0.06), dark)
	var muzzle := Node3D.new()
	muzzle.position = Vector3(0, 0.0, -0.18)
	m.add_child(muzzle)
	var fl := _flash_node(m, Vector3(0, 0.0, -0.22))
	m.set_meta("mag", mag)
	m.set_meta("mag_y", mag.position.y)
	m.set_meta("muzzle", muzzle)
	m.set_meta("flash", fl)
	m.set_meta("ads_y", 0.045)
	return m

func setup(p, c: Camera3D) -> void:
	player = p
	cam = c
	for w in Data.WEAPONS:
		ammo.append(int(w["mag"]))
		reserve.append(int(w["reserve"]))
	models.append(_build_rifle())
	models.append(_build_pistol())
	for m in models:
		add_child(m)
	_show_only(0)
	position = base_pos

func _show_only(i: int) -> void:
	for j in models.size():
		models[j].visible = (j == i)

func refill() -> void:
	for i in ammo.size():
		ammo[i] = int(Data.WEAPONS[i]["mag"])
		reserve[i] = int(Data.WEAPONS[i]["reserve"])
	reloading = false
	switch_t = SWITCH_TIME
	pending = -1
	bloom = 0.0

func add_reserve(n: int) -> void:
	reserve[current] = mini(reserve[current] + n, int(Data.WEAPONS[current]["reserve"]) * 2)

func zoom_fov() -> float:
	return float(Data.WEAPONS[current]["zoom_fov"])

func weapon_name() -> String:
	return String(Data.WEAPONS[current]["name"])

func reload_progress() -> float:
	if not reloading:
		return 0.0
	return clampf(reload_t / float(Data.WEAPONS[current]["reload"]), 0.0, 1.0)

func start_reload() -> void:
	var w: Dictionary = Data.WEAPONS[current]
	if reloading or switch_t < SWITCH_TIME:
		return
	if ammo[current] >= int(w["mag"]):
		return
	if reserve[current] <= 0 and not infinite_ammo:
		return
	reloading = true
	reload_t = 0.0

func switch_next() -> void:
	if switch_t < SWITCH_TIME:
		return
	reloading = false
	pending = (current + 1) % models.size()
	switch_t = 0.0

func _finish_reload() -> void:
	reloading = false
	var w: Dictionary = Data.WEAPONS[current]
	var need: int = int(w["mag"]) - ammo[current]
	var take: int = need if infinite_ammo else mini(need, reserve[current])
	ammo[current] += take
	if not infinite_ammo:
		reserve[current] -= take

func tick(delta: float) -> void:
	var w: Dictionary = Data.WEAPONS[current]
	cooldown = maxf(0.0, cooldown - delta)
	bloom = maxf(0.0, bloom - float(w["bloom_recover"]) * delta)
	flash_t -= delta
	var model := models[current]
	(model.get_meta("flash") as MeshInstance3D).visible = flash_t > 0.0

	# Switching
	if switch_t < SWITCH_TIME:
		switch_t += delta
		if pending >= 0 and switch_t >= SWITCH_TIME * 0.5:
			current = pending
			pending = -1
			_show_only(current)
			w = Data.WEAPONS[current]
			model = models[current]

	# Reloading
	if reloading:
		reload_t += delta
		if reload_t >= float(w["reload"]):
			_finish_reload()

	# Firing
	var can_act: bool = switch_t >= SWITCH_TIME and not reloading
	if firing and can_act and cooldown <= 0.0:
		if bool(w["auto"]) or not was_firing:
			if ammo[current] > 0:
				_shoot(w)
			elif not was_firing:
				start_reload()
	was_firing = firing

	var spread_deg: float = float(w["spread_ads"]) if aiming else float(w["spread_hip"])
	spread_now = spread_deg + bloom + move_speed * 0.02
	_animate(delta, w, model)

func _shoot(w: Dictionary) -> void:
	ammo[current] -= 1
	cooldown = 60.0 / float(w["rpm"])
	bloom = minf(bloom + float(w["bloom"]), float(w["bloom_max"]))
	var b := cam.global_transform.basis
	var ang := randf() * TAU
	var r: float = sqrt(randf()) * deg_to_rad(spread_now)
	var dir: Vector3 = (-b.z + b.x * cos(ang) * r + b.y * sin(ang) * r).normalized()
	var origin := cam.global_position
	var rng: float = float(w["range"])
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * rng, target_mask)
	q.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var muzzle := models[current].get_meta("muzzle") as Node3D
	var end: Vector3 = origin + dir * 80.0
	if not hit.is_empty():
		end = hit["position"]
		var col = hit["collider"]
		if col != null and col.has_method("take_damage"):
			var head: bool = false
			var cn := col as Node3D
			if cn != null:
				head = end.y - cn.global_position.y > 1.42
			var killed: bool = col.take_damage(float(w["damage"]), player, end)
			hit_enemy.emit(killed, head)
			if fx:
				fx.impact(end, hit["normal"], true)
		elif fx:
			fx.impact(end, hit["normal"], false)
	if fx:
		fx.tracer(muzzle.global_position, end)
	flash_t = 0.045
	var fl := models[current].get_meta("flash") as MeshInstance3D
	fl.rotation.z = randf() * TAU
	fl.scale = Vector3.ONE * randf_range(0.8, 1.4)
	kick += 0.035
	var pitch: float = deg_to_rad(float(w["recoil_pitch"]))
	var yaw: float = deg_to_rad(float(w["recoil_yaw"])) * randf_range(-1.0, 1.0)
	player.add_recoil(pitch, yaw)
	fired.emit()

func _animate(delta: float, w: Dictionary, model: Node3D) -> void:
	var a: float = 1.0 if (aiming and not reloading) else 0.0
	ads_t = move_toward(ads_t, a, delta * 9.0)
	var ads_pos := Vector3(0.0, -float(model.get_meta("ads_y")), -0.42)
	var p := base_pos.lerp(ads_pos, ads_t)
	var sway_goal := Vector2(-look_delta.x, look_delta.y) * 0.0009
	sway_goal = sway_goal.limit_length(0.04)
	sway = sway.lerp(sway_goal, 1.0 - exp(-12.0 * delta))
	p += Vector3(sway.x, sway.y, 0.0)
	if on_floor and move_speed > 1.0 and not sliding:
		bob_t += delta * move_speed * 1.4
		p += Vector3(cos(bob_t * 0.5) * 0.006, sin(bob_t) * 0.006, 0.0) * (1.0 - ads_t * 0.8)
	kick = lerpf(kick, 0.0, 1.0 - exp(-16.0 * delta))
	p.z += kick * (1.0 - ads_t * 0.5)
	slide_pose = move_toward(slide_pose, 1.0 if sliding else 0.0, delta * 6.0)
	p += Vector3(0.04, -0.05, 0.02) * slide_pose * (1.0 - ads_t)
	var rx := kick * 1.2
	# Reload / switch animations
	if reloading:
		var u := clampf(reload_t / float(w["reload"]), 0.0, 1.0)
		var dip := sin(u * PI)
		p.y -= dip * 0.1
		p.x -= dip * 0.05
		rx += dip * 0.55
		var mag := model.get_meta("mag") as Node3D
		var mu := sin(clampf((u - 0.2) / 0.55, 0.0, 1.0) * PI)
		mag.position.y = float(model.get_meta("mag_y")) - 0.22 * mu
	else:
		(model.get_meta("mag") as Node3D).position.y = float(model.get_meta("mag_y"))
	if switch_t < SWITCH_TIME:
		var sd := sin(clampf(switch_t / SWITCH_TIME, 0.0, 1.0) * PI)
		p.y -= sd * 0.3
		rx += sd * 0.6
	# Signature slide tilt: weapon rolls toward strafe direction, returns smoothly
	roll = lerpf(roll, tilt_target, 1.0 - exp(-9.0 * delta))
	position = p
	rotation = Vector3(rx, roll * 0.25 + sway.x * 2.0, roll)
