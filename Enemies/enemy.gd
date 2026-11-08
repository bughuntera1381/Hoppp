extends CharacterBody3D
## Offline AI opponent: patrols waypoints, detects the player with FOV + line of sight,
## reacts, strafes, fires bursts with imperfect aim, takes damage, dies and respawns.

signal died(killer: Node)

const WALK := 4.2
const RUN := 5.6
const GRAVITY := 22.0
const EYE := 1.55
const BASE_COLOR := Color(0.75, 0.2, 0.15)

var target
var fx
var waypoints: Array[Vector3] = []
var can_shoot := true
var frozen := true
var dead := false
var health := 100.0
var damage := 7.0
var rpm := 540.0
var base_spread := 2.0
var reaction_time := 0.35
var turn_speed := 5.5
var sight_range := 55.0

var visual: Node3D
var legs: Array[Node3D] = []
var col: CollisionShape3D
var _body_mat: StandardMaterial3D
var _wp := Vector3.ZERO
var _has_wp := false
var _last_known := Vector3.ZERO
var _alert := 0.0
var _sight := 0.0
var _seen := false
var _strafe := 1.0
var _strafe_t := 1.0
var _fire_cd := 0.0
var _burst := 6
var _pause := 0.0
var _stuck_t := 0.0
var _unstick := 0.0
var _unstick_dir := Vector3.ZERO
var _invuln := 0.0
var _flash := 0.0
var _anim := 0.0

func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.8
	return m

func _part(parent: Node3D, size: Vector3, pos: Vector3, mat: StandardMaterial3D) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)

func _ready() -> void:
	add_to_group("enemy")
	collision_layer = 4
	collision_mask = 1
	floor_snap_length = 0.3
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	col = CollisionShape3D.new()
	col.shape = cap
	col.position.y = 0.9
	add_child(col)
	visual = Node3D.new()
	add_child(visual)
	_body_mat = _mat(BASE_COLOR)
	var dark := _mat(Color(0.15, 0.16, 0.2))
	var skin := _mat(Color(0.9, 0.7, 0.55))
	for sx in [-0.13, 0.13]:
		var pivot := Node3D.new()
		pivot.position = Vector3(sx, 0.8, 0.0)
		visual.add_child(pivot)
		_part(pivot, Vector3(0.2, 0.8, 0.24), Vector3(0, -0.4, 0), dark)
		legs.append(pivot)
	_part(visual, Vector3(0.52, 0.6, 0.3), Vector3(0, 1.1, 0), _body_mat)
	_part(visual, Vector3(0.28, 0.28, 0.28), Vector3(0, 1.55, 0), skin)
	_part(visual, Vector3(0.3, 0.08, 0.05), Vector3(0, 1.58, -0.15), dark)
	_part(visual, Vector3(0.13, 0.13, 0.5), Vector3(-0.28, 1.2, -0.25), _body_mat)
	_part(visual, Vector3(0.13, 0.13, 0.5), Vector3(0.2, 1.2, -0.3), _body_mat)
	_part(visual, Vector3(0.08, 0.12, 0.6), Vector3(0.08, 1.22, -0.5), dark)

func _ray(from: Vector3, to: Vector3, mask: int) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, mask)
	q.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q)

func _pick_wp() -> void:
	if waypoints.is_empty():
		return
	for i in 4:
		_wp = waypoints[randi() % waypoints.size()]
		if global_position.distance_to(_wp) > 10.0:
			break
	_has_wp = true

func _blocked(origin: Vector3, dir: Vector3, length: float) -> bool:
	return not _ray(origin, origin + dir * length, 1).is_empty()

func _steer(dir: Vector3) -> Vector3:
	if dir.length() < 0.05:
		return Vector3.ZERO
	dir = dir.normalized()
	var o := global_position + Vector3(0, 0.6, 0)
	if not _blocked(o, dir, 2.2):
		return dir
	var l := dir.rotated(Vector3.UP, 0.9)
	var r := dir.rotated(Vector3.UP, -0.9)
	var lb := _blocked(o, l, 2.2)
	var rb := _blocked(o, r, 2.2)
	if not lb and (rb or randf() < 0.5):
		return l
	if not rb:
		return r
	return dir.rotated(Vector3.UP, 2.3)

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	if frozen or dead or target == null:
		velocity.x = move_toward(velocity.x, 0.0, 30.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 30.0 * delta)
		move_and_slide()
		return
	_invuln = maxf(0.0, _invuln - delta)
	if _flash > 0.0:
		_flash -= delta
		if _flash <= 0.0:
			_body_mat.albedo_color = BASE_COLOR

	var eye: Vector3 = global_position + Vector3(0.0, EYE, 0.0)
	var chest: Vector3 = target.global_position + Vector3(0.0, 1.1, 0.0)
	var flat: Vector3 = chest - eye
	flat.y = 0.0
	var dist: float = eye.distance_to(chest)
	var los := false
	if not target.dead and dist < sight_range:
		var fwd: Vector3 = -global_transform.basis.z
		var ang: float = 0.0
		if flat.length() > 0.01:
			ang = rad_to_deg(fwd.angle_to(flat.normalized()))
		if ang < 105.0 or _alert > 0.0:
			los = _ray(eye, chest, 1).is_empty()

	var move_dir := Vector3.ZERO
	var face_dir := Vector3.ZERO
	var speed: float = WALK
	if los:
		if not _seen:
			_seen = true
			_sight = 0.0
		_sight += delta
		_last_known = target.global_position
		_alert = 5.0
		face_dir = flat
		_strafe_t -= delta
		if _strafe_t <= 0.0:
			_strafe = -_strafe
			_strafe_t = randf_range(0.7, 1.7)
		var fdir: Vector3 = flat.normalized()
		var side: Vector3 = fdir.cross(Vector3.UP) * _strafe
		var fwd_amt: float = 0.0
		if dist > 18.0:
			fwd_amt = 1.0
		elif dist < 9.0:
			fwd_amt = -1.0
		move_dir = side * 0.9 + fdir * fwd_amt
		speed = RUN
	else:
		_seen = false
		_sight = 0.0
		_alert = maxf(0.0, _alert - delta)
		if _alert > 0.0:
			var to_last: Vector3 = _last_known - global_position
			to_last.y = 0.0
			if to_last.length() < 2.0:
				_alert = 0.0
			else:
				move_dir = to_last
				face_dir = to_last
				speed = RUN
		else:
			if not _has_wp or global_position.distance_to(_wp) < 2.5:
				_pick_wp()
			var to_wp: Vector3 = _wp - global_position
			to_wp.y = 0.0
			move_dir = to_wp
			face_dir = to_wp
	if _unstick > 0.0:
		_unstick -= delta
		move_dir = _unstick_dir
		face_dir = _unstick_dir if not los else face_dir

	var dirv: Vector3 = _steer(move_dir)
	var want := Vector3.ZERO
	if move_dir.length() > 0.05:
		want = dirv * speed
	velocity.x = move_toward(velocity.x, want.x, 30.0 * delta)
	velocity.z = move_toward(velocity.z, want.z, 30.0 * delta)

	var aim_err := 0.0
	if face_dir.length() > 0.05:
		var ty: float = atan2(-face_dir.x, -face_dir.z)
		aim_err = absf(angle_difference(rotation.y, ty))
		rotation.y = lerp_angle(rotation.y, ty, clampf(turn_speed * delta, 0.0, 1.0))

	if can_shoot and los and _sight >= reaction_time and aim_err < 0.3:
		if _pause > 0.0:
			_pause -= delta
		else:
			_fire_cd -= delta
			if _fire_cd <= 0.0:
				_shoot(eye, dist)
				_fire_cd = 60.0 / rpm
				_burst -= 1
				if _burst <= 0:
					_pause = randf_range(0.35, 0.8)
					_burst = randi_range(5, 10)

	move_and_slide()
	var hs: float = Vector2(velocity.x, velocity.z).length()
	if want.length() > 1.0 and hs < 0.6:
		_stuck_t += delta
	else:
		_stuck_t = 0.0
	if _stuck_t > 0.5:
		_stuck_t = 0.0
		_unstick = 0.7
		var a := randf() * TAU
		_unstick_dir = Vector3(cos(a), 0.0, sin(a))
		_has_wp = false
		_strafe = -_strafe
	_anim += delta * hs * 2.2
	var sw: float = clampf(hs / 5.0, 0.0, 1.0) * 0.7
	legs[0].rotation.x = sin(_anim) * sw
	legs[1].rotation.x = -sin(_anim) * sw

func _shoot(eye: Vector3, dist: float) -> void:
	var aim_pt: Vector3 = target.global_position + Vector3(0.0, randf_range(0.6, 1.5), 0.0)
	var dir: Vector3 = (aim_pt - eye).normalized()
	var tv := Vector2(target.velocity.x, target.velocity.z).length()
	var spread: float = deg_to_rad(base_spread + dist * 0.04 + tv * 0.18)
	var b := Basis.looking_at(dir, Vector3.UP)
	var ang := randf() * TAU
	var r: float = sqrt(randf()) * spread
	dir = (dir + b.x * cos(ang) * r + b.y * sin(ang) * r).normalized()
	var end: Vector3 = eye + dir * 90.0
	var hit := _ray(eye, end, 3)
	var muzzle: Vector3 = eye + (-global_transform.basis.z) * 0.8 + Vector3(0.0, -0.15, 0.0)
	if not hit.is_empty():
		end = hit["position"]
		var c = hit["collider"]
		if c != null and c.has_method("take_damage"):
			c.take_damage(damage, self, end)
		elif fx:
			fx.impact(end, hit["normal"], false)
	if fx:
		fx.tracer(muzzle, end)

func take_damage(amount: float, attacker: Node, hit_pos: Vector3) -> bool:
	if dead or frozen or _invuln > 0.0:
		return false
	var a := amount
	if hit_pos.y > global_position.y + 1.42:
		a *= 1.5
	health -= a
	_flash = 0.1
	_body_mat.albedo_color = Color.WHITE
	var an := attacker as Node3D
	if an != null:
		_last_known = an.global_position
		_alert = 5.0
	if randf() < 0.4:
		_strafe = -_strafe
	if health <= 0.0:
		_die(attacker)
		return true
	return false

func _die(killer: Node) -> void:
	dead = true
	col.set_deferred("disabled", true)
	died.emit(killer)
	var tw := create_tween()
	tw.tween_property(visual, "rotation:x", PI * 0.5, 0.45).set_trans(Tween.TRANS_QUAD)
	tw.parallel().tween_property(visual, "position:y", 0.25, 0.45)

func respawn(pos: Vector3, yaw: float) -> void:
	global_position = pos
	rotation = Vector3(0.0, yaw, 0.0)
	velocity = Vector3.ZERO
	health = 100.0
	dead = false
	frozen = false
	_invuln = 1.2
	visual.rotation = Vector3.ZERO
	visual.position = Vector3.ZERO
	col.disabled = false
	_body_mat.albedo_color = BASE_COLOR
	_alert = 0.0
	_seen = false
	_has_wp = false
	_pause = 0.0
