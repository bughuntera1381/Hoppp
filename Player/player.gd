extends CharacterBody3D
## First-person controller: walk, sprint, air control, slide, slide-jump, bunny hop,
## sliding strafe and weapon tilt. All tunables are exported for quick balancing.

signal died(killer: Node)
signal damaged(from_pos: Vector3)
signal hit_marker(killed: bool, head: bool)

const WeaponScript = preload("res://Weapons/weapon.gd")

const STAND_HEIGHT := 1.8
const SLIDE_HEIGHT := 1.0
const STAND_EYE := 1.6
const SLIDE_EYE := 0.8
const LOOK_BASE := 0.0032
const TILT_MAX := 0.6
const BASE_FOV := 80.0

@export var walk_speed: float = 6.0
@export var sprint_speed: float = 9.0
@export var ground_accel: float = 55.0
@export var ground_decel: float = 40.0
@export var ground_friction: float = 14.0
@export var air_wish_speed: float = 4.0
@export var air_accel: float = 14.0
@export var max_air_speed: float = 14.0
@export var gravity: float = 22.0
@export var jump_velocity: float = 7.2
@export var jump_buffer_time: float = 0.14
# Slide
@export var slide_min_speed: float = 6.5
@export var slide_boost: float = 1.18
@export var slide_max_speed: float = 13.0
@export var slide_friction: float = 4.2
@export var slide_max_time: float = 1.5
@export var slide_end_speed: float = 3.2
@export var slide_cooldown: float = 0.35
@export var slide_strafe_speed: float = 5.5
@export var slide_jump_boost: float = 1.12
# Bunny hop
@export var bhop_window: float = 0.14
@export var bhop_max_bonus: float = 0.05
@export var bhop_min_bonus: float = 0.01
@export var bhop_max_speed: float = 12.5

var touch
var weapon
var head: Node3D
var cam: Camera3D
var capsule: CapsuleShape3D
var col: CollisionShape3D

var max_health := 100.0
var health := 100.0
var dead := false
var frozen := true
var invuln := 0.0
var since_damage := 99.0

var sliding := false
var slide_t := 0.0
var slide_air := 0.0
var slide_cd := 0.0
var need_release := false
var slide_vel := Vector3.ZERO
var strafe_in := 0.0

var was_on_floor := false
var ground_time := 0.0
var coyote := 0.0
var jump_buffer := 0.0
var since_press := 1.0
var airborne_from_jump := false
var bhop_chain := 0
var last_vy := 0.0
var hspeed := 0.0

var aiming := false
var recoil_accum := 0.0
var look_px := Vector2.ZERO
var land_dip := 0.0
var bob_t := 0.0
var shake := 0.0

func _ready() -> void:
	add_to_group("player")
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 0.3
	capsule = CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = STAND_HEIGHT
	col = CollisionShape3D.new()
	col.shape = capsule
	col.position.y = STAND_HEIGHT * 0.5
	add_child(col)
	head = Node3D.new()
	head.position.y = STAND_EYE
	add_child(head)
	cam = Camera3D.new()
	cam.fov = BASE_FOV
	cam.near = 0.05
	cam.far = 150.0
	head.add_child(cam)
	cam.make_current()
	weapon = WeaponScript.new()
	cam.add_child(weapon)
	weapon.setup(self, cam)
	weapon.hit_enemy.connect(_on_weapon_hit)

func setup_fx(f) -> void:
	weapon.fx = f

func _on_weapon_hit(killed: bool, head_shot: bool) -> void:
	hit_marker.emit(killed, head_shot)

func _set_crouch(on: bool) -> void:
	capsule.height = SLIDE_HEIGHT if on else STAND_HEIGHT
	col.position.y = capsule.height * 0.5

# ---------------------------------------------------------------- physics
func _physics_process(delta: float) -> void:
	if touch == null:
		return
	var on_floor: bool = is_on_floor()
	if on_floor and not was_on_floor:
		land_dip = clampf(-last_vy * 0.012, 0.0, 0.16)
	was_on_floor = on_floor
	if on_floor:
		ground_time += delta
		coyote = 0.1
		if ground_time > bhop_window:
			airborne_from_jump = false
	else:
		ground_time = 0.0
		coyote = maxf(0.0, coyote - delta)

	if dead or frozen:
		velocity.x = move_toward(velocity.x, 0.0, 25.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 25.0 * delta)
		if not on_floor:
			velocity.y -= gravity * delta
		move_and_slide()
		return

	if touch.consume_jump():
		jump_buffer = jump_buffer_time
		since_press = 0.0
	jump_buffer = maxf(0.0, jump_buffer - delta)
	since_press += delta
	slide_cd = maxf(0.0, slide_cd - delta)
	if not touch.slide_held:
		need_release = false

	var mv: Vector2 = touch.move_vec
	var wish: Vector3 = global_transform.basis * Vector3(mv.x, 0.0, -mv.y)
	wish.y = 0.0
	var wish_len: float = minf(wish.length(), 1.0)
	var wish_dir := Vector3.ZERO
	if wish_len > 0.01:
		wish_dir = wish.normalized()
	var h := Vector3(velocity.x, 0.0, velocity.z)
	var hs: float = h.length()

	# --- start slide (hold button while moving fast on the ground)
	if not sliding and touch.slide_held and not need_release and on_floor and slide_cd <= 0.0 and hs >= slide_min_speed:
		sliding = true
		slide_t = 0.0
		slide_air = 0.0
		strafe_in = 0.0
		var boosted: float = minf(hs, max_air_speed) if airborne_from_jump else minf(hs * slide_boost, slide_max_speed)
		slide_vel = h.normalized() * boosted
		_set_crouch(true)

	if sliding:
		slide_t += delta
		slide_air = 0.0 if on_floor else slide_air + delta
		var sp: float = slide_vel.length()
		sp = maxf(0.0, sp - slide_friction * (0.6 + slide_t / slide_max_time) * delta)
		slide_vel = slide_vel.normalized() * sp
		strafe_in = move_toward(strafe_in, mv.x, 8.0 * delta)
		var cam_right: Vector3 = global_transform.basis.x
		cam_right.y = 0.0
		var lat: Vector3 = cam_right.normalized() * strafe_in * slide_strafe_speed
		velocity.x = slide_vel.x + lat.x
		velocity.z = slide_vel.z + lat.z
		var end_slide := false
		if not touch.slide_held:
			end_slide = true
		elif slide_t >= slide_max_time or sp < slide_end_speed:
			end_slide = true
			need_release = true
		elif slide_air > 0.15:
			end_slide = true
		if end_slide:
			_end_slide()
	else:
		strafe_in = move_toward(strafe_in, 0.0, 6.0 * delta)
		var target_speed: float = walk_speed
		if touch.sprint and mv.y > 0.2:
			target_speed = sprint_speed
		if aiming:
			target_speed *= 0.65
		if on_floor:
			var grace: bool = airborne_from_jump and ground_time < bhop_window
			if wish_len > 0.01:
				var tgt: Vector3 = wish_dir * target_speed * wish_len
				if hs > target_speed + 0.3:
					if not grace:
						h = h.move_toward(tgt, ground_friction * delta)
				else:
					h = h.move_toward(tgt, ground_accel * delta)
			elif not grace:
				h = h.move_toward(Vector3.ZERO, ground_decel * delta)
		else:
			if wish_len > 0.01:
				var cur: float = h.dot(wish_dir)
				var add: float = air_wish_speed - cur
				if add > 0.0:
					h += wish_dir * minf(air_accel * air_wish_speed * delta, add)
			var hl: float = h.length()
			if hl > max_air_speed:
				h = h / hl * max_air_speed
		velocity.x = h.x
		velocity.z = h.z

	# --- jump (normal, bunny hop, slide jump)
	if jump_buffer > 0.0 and (on_floor or coyote > 0.0):
		_do_jump()

	if not on_floor:
		velocity.y -= gravity * delta
	last_vy = velocity.y
	move_and_slide()
	hspeed = Vector2(velocity.x, velocity.z).length()

func _end_slide() -> void:
	sliding = false
	slide_cd = slide_cooldown
	_set_crouch(false)

func _do_jump() -> void:
	jump_buffer = 0.0
	coyote = 0.0
	var h := Vector3(velocity.x, 0.0, velocity.z)
	var sp: float = h.length()
	if sliding:
		# Slide jump: keep momentum, extra distance. No stacking boost when chained.
		var mult: float = 1.0 + bhop_min_bonus if airborne_from_jump else slide_jump_boost
		var ns: float = minf(sp * mult, max_air_speed)
		if sp > 0.01:
			h = h / sp * ns
		_end_slide()
		velocity.y = jump_velocity * 1.05
	else:
		if airborne_from_jump and ground_time <= bhop_window:
			# Bunny hop: reward timing, hard speed cap prevents runaway acceleration
			bhop_chain += 1
			var miss: float = clampf((since_press + ground_time) / bhop_window, 0.0, 1.0)
			var bonus: float = lerpf(bhop_max_bonus, bhop_min_bonus, miss)
			var ns: float = minf(sp * (1.0 + bonus), bhop_max_speed)
			if sp > 0.01 and ns > sp:
				h = h / sp * ns
		else:
			bhop_chain = 0
		velocity.y = jump_velocity
	velocity.x = h.x
	velocity.z = h.z
	airborne_from_jump = true
	land_dip = -0.03

# ---------------------------------------------------------------- frame
func _process(delta: float) -> void:
	if touch == null:
		return
	invuln = maxf(0.0, invuln - delta)
	since_damage += delta
	aiming = touch.aim_held and not dead and not frozen and not weapon.reloading
	look_px = touch.consume_look()
	if not dead and not frozen:
		var s: float = LOOK_BASE * touch.sens * (0.55 if aiming else 1.0)
		rotate_y(-look_px.x * s)
		head.rotation.x = clampf(head.rotation.x - look_px.y * s, -1.5, 1.5)
	var rl: bool = touch.consume_reload()
	var sw: bool = touch.consume_switch()
	if not dead and not frozen:
		if rl:
			weapon.start_reload()
		if sw:
			weapon.switch_next()
		if since_damage > 5.0 and health < max_health:
			health = minf(max_health, health + 6.0 * delta)
	weapon.visible = not dead
	weapon.firing = touch.fire_held and not dead and not frozen
	weapon.aiming = aiming
	weapon.sliding = sliding
	weapon.on_floor = is_on_floor()
	weapon.move_speed = hspeed
	weapon.look_delta = look_px
	weapon.tilt_target = (-clampf(strafe_in, -1.0, 1.0) * TILT_MAX) if sliding else 0.0
	weapon.tick(delta)
	_update_camera(delta)

func add_recoil(pitch: float, yaw: float) -> void:
	head.rotation.x = clampf(head.rotation.x + pitch, -1.5, 1.5)
	rotate_y(yaw)
	recoil_accum += pitch

func _update_camera(delta: float) -> void:
	# Recoil recovery (slower while firing)
	if recoil_accum > 0.0001:
		var rate: float = 0.35 if weapon.firing else 1.4
		var rec: float = minf(recoil_accum, rate * delta)
		head.rotation.x -= rec
		recoil_accum -= rec
	# Eye height: lower while sliding, drops when dead
	var eye: float = SLIDE_EYE if sliding else STAND_EYE
	if dead:
		eye = 0.3
	land_dip = move_toward(land_dip, 0.0, 0.7 * delta)
	head.position.y = lerpf(head.position.y, eye - land_dip, 1.0 - exp(-14.0 * delta))
	# FOV: speed kick + scope zoom
	var fov_goal: float = BASE_FOV + clampf((hspeed - 6.0) * 0.8, 0.0, 6.0)
	if sliding:
		fov_goal += 3.0
	if aiming:
		fov_goal = weapon.zoom_fov()
	cam.fov = lerpf(cam.fov, fov_goal, 1.0 - exp(-14.0 * delta))
	# Roll: lean into slide strafe, fall over when dead
	var roll_goal: float = (-strafe_in * 0.05) if sliding else 0.0
	if dead:
		roll_goal = 0.9
	cam.rotation.z = lerpf(cam.rotation.z, roll_goal, 1.0 - exp(-10.0 * delta))
	# Jump/fall pitch + head bob + slide rumble
	var pitch_goal: float = clampf(velocity.y * 0.004, -0.05, 0.05)
	cam.rotation.x = lerpf(cam.rotation.x, pitch_goal, 1.0 - exp(-8.0 * delta))
	var bob := Vector3.ZERO
	if is_on_floor() and not sliding and hspeed > 1.0 and not dead:
		bob_t += delta * hspeed * 1.2
		var k: float = clampf(hspeed / 9.0, 0.0, 1.0)
		bob = Vector3(cos(bob_t * 0.5) * 0.012 * k, sin(bob_t) * 0.016 * k, 0.0)
	elif sliding:
		bob = Vector3(0.0, sin(Time.get_ticks_msec() * 0.05) * 0.003, 0.0)
	shake = maxf(0.0, shake - delta * 3.0)
	if shake > 0.0:
		bob += Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), 0.0) * shake * 0.02
	cam.position = bob

# ---------------------------------------------------------------- combat
func take_damage(amount: float, attacker: Node, hit_pos: Vector3) -> bool:
	if dead or frozen or invuln > 0.0:
		return false
	var a := amount
	if hit_pos.y > global_position.y + 1.42 and not sliding:
		a *= 1.5
	health -= a
	since_damage = 0.0
	shake = 0.6
	var an := attacker as Node3D
	damaged.emit(an.global_position if an != null else hit_pos)
	if health <= 0.0:
		health = 0.0
		dead = true
		if sliding:
			_end_slide()
		died.emit(attacker)
		return true
	return false

func respawn(pos: Vector3, yaw: float) -> void:
	global_position = pos
	rotation = Vector3(0.0, yaw, 0.0)
	head.rotation = Vector3.ZERO
	velocity = Vector3.ZERO
	health = max_health
	dead = false
	frozen = false
	sliding = false
	_set_crouch(false)
	invuln = 1.5
	since_damage = 99.0
	recoil_accum = 0.0
	airborne_from_jump = false
	weapon.refill()
