
extends CharacterBody3D
class_name FPSPlayer

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

# --------------------------------------------------
# MOVEMENT
# --------------------------------------------------

@export_group("Movement")

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
@export var coyote_time: float = 0.10


# --------------------------------------------------
# SLIDE
# --------------------------------------------------

@export_group("Slide")

@export var slide_min_speed: float = 6.5
@export var slide_boost: float = 1.18
@export var slide_max_speed: float = 13.0

@export var slide_friction: float = 4.2
@export var slide_max_time: float = 1.5
@export var slide_end_speed: float = 3.2
@export var slide_cooldown: float = 0.35

@export var slide_strafe_speed: float = 5.5
@export var slide_jump_boost: float = 1.12


# --------------------------------------------------
# BUNNY HOP
# --------------------------------------------------

@export_group("Bunny Hop")

@export var bhop_window: float = 0.14
@export var bhop_max_bonus: float = 0.05
@export var bhop_min_bonus: float = 0.01
@export var bhop_max_speed: float = 12.5


# --------------------------------------------------
# CAMERA
# --------------------------------------------------

@export_group("Camera")

@export var camera_smooth: float = 14.0
@export var camera_fov_smooth: float = 14.0
@export var camera_bob_amount: float = 1.0


# --------------------------------------------------
# REFERENCES
# --------------------------------------------------

var touch
var weapon

var head: Node3D
var cam: Camera3D

var capsule: CapsuleShape3D
var col: CollisionShape3D


# --------------------------------------------------
# HEALTH
# --------------------------------------------------

var max_health := 100.0
var health := 100.0

var dead := false
var frozen := true

var invuln := 0.0
var since_damage := 99.0


# --------------------------------------------------
# SLIDE STATE
# --------------------------------------------------

var sliding := false

var slide_t := 0.0
var slide_air := 0.0
var slide_cd := 0.0

var need_release := false

var slide_vel := Vector3.ZERO
var strafe_in := 0.0


# --------------------------------------------------
# JUMP STATE
# --------------------------------------------------

var was_on_floor := false

var ground_time := 0.0
var coyote := 0.0

var jump_buffer := 0.0
var since_press := 1.0

var airborne_from_jump := false
var bhop_chain := 0

var last_vy := 0.0
var hspeed := 0.0


# --------------------------------------------------
# CAMERA STATE
# --------------------------------------------------

var aiming := false

var recoil_accum := 0.0

var look_px := Vector2.ZERO

var land_dip := 0.0
var bob_t := 0.0
var shake := 0.0


# --------------------------------------------------
# INITIALIZATION
# --------------------------------------------------

func _ready() -> void:

	add_to_group("player")

	collision_layer = 2
	collision_mask = 1

	floor_snap_length = 0.3

	# Capsule
	capsule = CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = STAND_HEIGHT

	col = CollisionShape3D.new()
	col.shape = capsule
	col.position.y = STAND_HEIGHT * 0.5

	add_child(col)

	# Head
	head = Node3D.new()
	head.position.y = STAND_EYE

	add_child(head)

	# Camera
	cam = Camera3D.new()
	cam.fov = BASE_FOV
	cam.near = 0.05
	cam.far = 150.0

	head.add_child(cam)
	cam.make_current()

	# Weapon
	weapon = WeaponScript.new()
	cam.add_child(weapon)

	weapon.setup(self, cam)
	weapon.hit_enemy.connect(_on_weapon_hit)

	was_on_floor = is_on_floor()


func setup_fx(f) -> void:
	weapon.fx = f


func set_touch_controller(controller) -> void:

	touch = controller

	if touch != null:
		touch.reset_state()


func _on_weapon_hit(killed: bool, head_shot: bool) -> void:
	hit_marker.emit(killed, head_shot)


# --------------------------------------------------
# CAPSULE / STANDING CHECK
# --------------------------------------------------

func _can_stand() -> bool:

	if capsule == null or col == null:
		return false

	var query_shape := CapsuleShape3D.new()

	query_shape.radius = capsule.radius

	# Small clearance at the bottom avoids detecting the floor.
	query_shape.height = STAND_HEIGHT - 0.04

	var query := PhysicsShapeQueryParameters3D.new()

	query.shape = query_shape

	query.transform = global_transform * Transform3D(
		Basis(),
		Vector3(0.0, STAND_HEIGHT * 0.5 + 0.02, 0.0)
	)

	query.collision_mask = collision_mask
	query.exclude = [get_rid()]
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.margin = 0.0

	var space := get_world_3d().direct_space_state

	return space.intersect_shape(query, 1).is_empty()


func _set_crouch(on: bool) -> bool:

	if not on and not _can_stand():
		return false

	capsule.height = SLIDE_HEIGHT if on else STAND_HEIGHT

	col.position.y = capsule.height * 0.5

	return true


func _try_stand() -> void:

	if capsule.height < STAND_HEIGHT:
		_set_crouch(false)


# --------------------------------------------------
# PHYSICS
# --------------------------------------------------

func _physics_process(delta: float) -> void:

	if touch == null:
		return

	var on_floor := is_on_floor()

	# Landing detection
	if on_floor and not was_on_floor:

		land_dip = clampf(
			-last_vy * 0.012,
			0.0,
			0.16
		)

	was_on_floor = on_floor

	# Ground timers
	if on_floor:

		ground_time += delta
		coyote = coyote_time

		if ground_time > bhop_window:
			airborne_from_jump = false

	else:

		ground_time = 0.0
		coyote = maxf(0.0, coyote - delta)

	# Dead / frozen
	if dead or frozen:

		sliding = false
		velocity.x = move_toward(velocity.x, 0.0, 25.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 25.0 * delta)

		if not on_floor:
			velocity.y -= gravity * delta

		move_and_slide()
		return

	# Stand when enough headroom is available.
	if not sliding:
		_try_stand()

	# Jump input buffer
	if touch.consume_jump():

		jump_buffer = jump_buffer_time
		since_press = 0.0

	jump_buffer = maxf(0.0, jump_buffer - delta)
	since_press += delta

	slide_cd = maxf(0.0, slide_cd - delta)

	if not touch.slide_held:
		need_release = false

	# Movement input
	var mv: Vector2 = touch.move_vec

	var wish: Vector3 = (
		global_transform.basis
		* Vector3(mv.x, 0.0, -mv.y)
	)

	wish.y = 0.0

	var wish_len := minf(wish.length(), 1.0)

	var wish_dir := Vector3.ZERO

	if wish_len > 0.01:
		wish_dir = wish.normalized()

	var horizontal := Vector3(
		velocity.x,
		0.0,
		velocity.z
	)

	var horizontal_speed := horizontal.length()

	# --------------------------------------------------
	# START SLIDE
	# --------------------------------------------------

	if (
		not sliding
		and touch.slide_held
		and not need_release
		and on_floor
		and slide_cd <= 0.0
		and horizontal_speed >= slide_min_speed
	):

		sliding = true

		slide_t = 0.0
		slide_air = 0.0
		strafe_in = 0.0

		var boosted: float

		if airborne_from_jump:

			boosted = minf(
				horizontal_speed,
				max_air_speed
			)

		else:

			boosted = minf(
				horizontal_speed * slide_boost,
				slide_max_speed
			)

		slide_vel = horizontal.normalized() * boosted

		_set_crouch(true)

	# --------------------------------------------------
	# SLIDE MOVEMENT
	# --------------------------------------------------

	if sliding:

		slide_t += delta

		if on_floor:
			slide_air = 0.0
		else:
			slide_air += delta

		var speed := slide_vel.length()

		var duration := maxf(slide_max_time, 0.01)

		speed = maxf(
			0.0,
			speed - slide_friction * (
				0.6 + slide_t / duration
			) * delta
		)

		if slide_vel.length() > 0.001:
			slide_vel = slide_vel.normalized() * speed
		else:
			slide_vel = Vector3.ZERO

		# Slide strafing
		strafe_in = move_toward(
			strafe_in,
			mv.x,
			8.0 * delta
		)

		var cam_right := global_transform.basis.x
		cam_right.y = 0.0

		var lateral := (
			cam_right.normalized()
			* strafe_in
			* slide_strafe_speed
		)

		velocity.x = slide_vel.x + lateral.x
		velocity.z = slide_vel.z + lateral.z

		# Slide termination
		var end_slide := false

		if not touch.slide_held:

			end_slide = true

		elif slide_t >= slide_max_time or speed < slide_end_speed:

			end_slide = true
			need_release = true

		elif slide_air > 0.15:

			end_slide = true

		if end_slide:
			_end_slide()

	# --------------------------------------------------
	# NORMAL MOVEMENT
	# --------------------------------------------------

	else:

		strafe_in = move_toward(
			strafe_in,
			0.0,
			6.0 * delta
		)

		var target_speed := walk_speed

		if touch.sprint and mv.y > 0.2:
			target_speed = sprint_speed

		if aiming:
			target_speed *= 0.65

		if on_floor:

			var grace := (
				airborne_from_jump
				and ground_time < bhop_window
			)

			if wish_len > 0.01:

				var target := wish_dir * target_speed * wish_len

				if horizontal_speed > target_speed + 0.3:

					if not grace:
						horizontal = horizontal.move_toward(
							target,
							ground_friction * delta
						)

				else:

					horizontal = horizontal.move_toward(
						target,
						ground_accel * delta
					)

			elif not grace:

				horizontal = horizontal.move_toward(
					Vector3.ZERO,
					ground_decel * delta
				)

		else:

			if wish_len > 0.01:

				var current_speed := horizontal.dot(wish_dir)

				var add_speed := air_wish_speed - current_speed

				if add_speed > 0.0:

					horizontal += wish_dir * minf(
						air_accel * air_wish_speed * delta,
						add_speed
					)

			# Prevent air-control speed runaway.
			var air_speed := horizontal.length()

			if air_speed > max_air_speed:

				horizontal = (
					horizontal / air_speed
					* max_air_speed
				)

		velocity.x = horizontal.x
		velocity.z = horizontal.z

	# --------------------------------------------------
	# JUMP
	# --------------------------------------------------

	if (
		jump_buffer > 0.0
		and (on_floor or coyote > 0.0)
	):

		_do_jump()

	# Gravity
	if not on_floor:
		velocity.y -= gravity * delta

	last_vy = velocity.y

	move_and_slide()

	hspeed = Vector2(
		velocity.x,
		velocity.z
	).length()


# --------------------------------------------------
# END SLIDE
# --------------------------------------------------

func _end_slide() -> void:

	sliding = false

	slide_cd = slide_cooldown

	# If ceiling is too low, remain crouched.
	_set_crouch(false)


# --------------------------------------------------
# JUMP / BUNNY HOP
# --------------------------------------------------

func _do_jump() -> void:

	jump_buffer = 0.0
	coyote = 0.0

	var horizontal := Vector3(
		velocity.x,
		0.0,
		velocity.z
	)

	var speed := horizontal.length()

	# SLIDE JUMP
	if sliding:

		var multiplier := 1.0

		if airborne_from_jump:

			multiplier = 1.0 + bhop_min_bonus

		else:

			multiplier = slide_jump_boost

		var new_speed := minf(
			speed * multiplier,
			max_air_speed
		)

		if speed > 0.01:
			horizontal = horizontal / speed * new_speed

		_end_slide()

		velocity.y = jump_velocity * 1.05

	# NORMAL / BUNNY HOP
	else:

		if (
			airborne_from_jump
			and ground_time <= bhop_window
		):

			bhop_chain += 1

			var window := maxf(bhop_window, 0.01)

			var miss := clampf(
				(since_press + ground_time) / window,
				0.0,
				1.0
			)

			var bonus := lerpf(
				bhop_max_bonus,
				bhop_min_bonus,
				miss
			)

			var new_speed := minf(
				speed * (1.0 + bonus),
				bhop_max_speed
			)

			if speed > 0.01 and new_speed > speed:

				horizontal = (
					horizontal / speed
					* new_speed
				)

		else:

			bhop_chain = 0

		velocity.y = jump_velocity

	velocity.x = horizontal.x
	velocity.z = horizontal.z

	airborne_from_jump = true

	land_dip = -0.03


# --------------------------------------------------
# PROCESS
# --------------------------------------------------

func _process(delta: float) -> void:

	if touch == null:
		return

	invuln = maxf(0.0, invuln - delta)
	since_damage += delta

	aiming = (
		touch.aim_held
		and not dead
		and not frozen
		and not weapon.reloading
	)

	# consume_look already applies HUD sensitivity.
	look_px = touch.consume_look()

	if not dead and not frozen:

		var sensitivity := (
			LOOK_BASE
			* (0.55 if aiming else 1.0)
		)

		rotate_y(-look_px.x * sensitivity)

		head.rotation.x = clampf(
			head.rotation.x - look_px.y * sensitivity,
			-1.5,
			1.5
		)

	# Weapon actions
	var reload_input := touch.consume_reload()
	var switch_input := touch.consume_switch()

	if not dead and not frozen:

		if reload_input:
			weapon.start_reload()

		if switch_input:
			weapon.switch_next()

		# Health regeneration
		if since_damage > 5.0 and health < max_health:

			health = minf(
				max_health,
				health + 6.0 * delta
			)

	# Weapon state
	weapon.visible = not dead

	weapon.firing = (
		touch.fire_held
		and not dead
		and not frozen
	)

	weapon.aiming = aiming
	weapon.sliding = sliding
	weapon.on_floor = is_on_floor()
	weapon.move_speed = hspeed

	weapon.look_delta = look_px

	weapon.tilt_target = (
		-clampf(strafe_in, -1.0, 1.0) * TILT_MAX
		if sliding
		else 0.0
	)

	weapon.tick(delta)

	_update_camera(delta)


# --------------------------------------------------
# RECOIL
# --------------------------------------------------

func add_recoil(pitch: float, yaw: float) -> void:

	head.rotation.x = clampf(
		head.rotation.x + pitch,
		-1.5,
		1.5
	)

	rotate_y(yaw)

	recoil_accum += maxf(pitch, 0.0)


# --------------------------------------------------
# CAMERA EFFECTS
# --------------------------------------------------

func _update_camera(delta: float) -> void:

	# Recoil recovery
	if recoil_accum > 0.0001:

		var rate := 0.35 if weapon.firing else 1.4

		var recovery := minf(
			recoil_accum,
			rate * delta
		)

		head.rotation.x = clampf(
			head.rotation.x - recovery,
			-1.5,
			1.5
		)

		recoil_accum -= recovery

	# Eye height
	var eye := SLIDE_EYE if sliding else STAND_EYE

	if dead:
		eye = 0.3

	land_dip = move_toward(
		land_dip,
		0.0,
		0.7 * delta
	)

	head.position.y = lerpf(
		head.position.y,
		eye - land_dip,
		1.0 - exp(-camera_smooth * delta)
	)

	# FOV
	var fov_goal := BASE_FOV + clampf(
		(hspeed - 6.0) * 0.8,
		0.0,
		6.0
	)

	if sliding:
		fov_goal += 3.0

	if aiming:
		fov_goal = weapon.zoom_fov()

	cam.fov = lerpf(
		cam.fov,
		fov_goal,
		1.0 - exp(-camera_fov_smooth * delta)
	)

	# Camera roll
	var roll_goal := (
		-strafe_in * 0.05
		if sliding
		else 0.0
	)

	if dead:
		roll_goal = 0.9

	cam.rotation.z = lerpf(
		cam.rotation.z,
		roll_goal,
		1.0 - exp(-10.0 * delta)
	)

	# Jump / fall camera pitch
	var pitch_goal := clampf(
		velocity.y * 0.004,
		-0.05,
		0.05
	)

	cam.rotation.x = lerpf(
		cam.rotation.x,
		pitch_goal,
		1.0 - exp(-8.0 * delta)
	)

	# Head bob
	var bob := Vector3.ZERO

	if (
		is_on_floor()
		and not sliding
		and hspeed > 1.0
		and not dead
	):

		bob_t += delta * hspeed * 1.2

		var intensity := clampf(
			hspeed / 9.0,
			0.0,
			1.0
		) * camera_bob_amount

		bob = Vector3(
			cos(bob_t * 0.5) * 0.012 * intensity,
			sin(bob_t) * 0.016 * intensity,
			0.0
		)

	elif sliding:

		bob = Vector3(
			0.0,
			sin(Time.get_ticks_msec() * 0.05) * 0.003,
			0.0
		)

	# Camera shake
	shake = maxf(
		0.0,
		shake - delta * 3.0
	)

	if shake > 0.0:

		bob += Vector3(
			randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0),
			0.0
		) * shake * 0.02

	cam.position = bob


# --------------------------------------------------
# DAMAGE
# --------------------------------------------------

func take_damage(
	amount: float,
	attacker: Node,
	hit_pos: Vector3
) -> bool:

	if dead or frozen or invuln > 0.0:
		return false

	var damage_amount := amount

	# Headshot multiplier
	if (
		hit_pos.y > global_position.y + 1.42
		and not sliding
	):

		damage_amount *= 1.5

	health -= damage_amount

	since_damage = 0.0
	shake = 0.6

	var attacker_3d := attacker as Node3D

	damaged.emit(
		attacker_3d.global_position
		if attacker_3d != null
		else hit_pos
	)

	if health <= 0.0:

		health = 0.0
		dead = true

		if sliding:
			_end_slide()

		died.emit(attacker)

		return true

	return false


# --------------------------------------------------
# RESPAWN
# --------------------------------------------------

func respawn(pos: Vector3, yaw: float) -> void:

	global_position = pos

	rotation = Vector3(
		0.0,
		yaw,
		0.0
	)

	velocity = Vector3.ZERO

	head.rotation = Vector3.ZERO
	head.position.y = STAND_EYE

	cam.rotation = Vector3.ZERO
	cam.position = Vector3.ZERO
	cam.fov = BASE_FOV

	health = max_health

	dead = false
	frozen = false

	sliding = false

	slide_t = 0.0
	slide_air = 0.0
	slide_cd = 0.0

	slide_vel = Vector3.ZERO
	strafe_in = 0.0

	need_release = false

	ground_time = 0.0
	coyote = 0.0

	jump_buffer = 0.0
	since_press = 1.0

	airborne_from_jump = false
	bhop_chain = 0

	was_on_floor = false

	last_vy = 0.0
	hspeed = 0.0

	aiming = false
	recoil_accum = 0.0

	look_px = Vector2.ZERO

	land_dip = 0.0
	bob_t = 0.0
	shake = 0.0

	invuln = 1.5
	since_damage = 99.0

	_set_crouch(false)

	if touch != null:
		touch.reset_state()

	weapon.refill()

	weapon.visible = true
	weapon.firing = false
	weapon.aiming = false
	weapon.sliding = false
	weapon.on_floor = true
	weapon.move_speed = 0.0
	weapon.look_delta = Vector2.ZERO
	weapon.tilt_target = 0.0
