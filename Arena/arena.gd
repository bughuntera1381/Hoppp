extends Node3D
## Builds the low-poly arena, lighting and environment entirely from code.

const HALF := 30.0

var half := HALF
var spawn_points: Array[Vector3] = [
	Vector3(-25, 1.0, -25), Vector3(25, 1.0, 25), Vector3(-25, 1.0, 25),
	Vector3(25, 1.0, -25), Vector3(0, 1.0, -25), Vector3(0, 1.0, 25),
]
var waypoints: Array[Vector3] = [
	Vector3(-20, 0, -20), Vector3(20, 0, 20), Vector3(-20, 0, 20), Vector3(20, 0, -20),
	Vector3(0, 0, -10), Vector3(0, 0, 10), Vector3(-12, 0, 0), Vector3(12, 0, 0),
	Vector3(-12, 0, -16), Vector3(12, 0, 16), Vector3(-8, 0, -25), Vector3(8, 0, 25),
	Vector3(-26, 0, 10), Vector3(26, 0, -10),
]
var map_rects: Array[Rect2] = []
var sun: DirectionalLight3D
var _mats := {}

func _mat(c: Color) -> StandardMaterial3D:
	var key := c.to_html()
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	_mats[key] = m
	return m

func _ready() -> void:
	_build_environment()
	_build_ground()
	_build_walls()
	_build_cover()

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color(0.22, 0.42, 0.72)
	psm.sky_horizon_color = Color(0.72, 0.82, 0.92)
	psm.ground_horizon_color = Color(0.72, 0.82, 0.92)
	psm.ground_bottom_color = Color(0.35, 0.4, 0.45)
	sky.sky_material = psm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.72, 0.82, 0.92)
	env.fog_density = 0.006
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -35, 0)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 45.0
	add_child(sun)

func _build_ground() -> void:
	var img := Image.create(2, 2, false, Image.FORMAT_RGB8)
	var a := Color(0.42, 0.47, 0.4)
	var b := Color(0.36, 0.41, 0.35)
	img.set_pixel(0, 0, a)
	img.set_pixel(1, 1, a)
	img.set_pixel(1, 0, b)
	img.set_pixel(0, 1, b)
	var tex := ImageTexture.create_from_image(img)
	var gm := StandardMaterial3D.new()
	gm.albedo_texture = tex
	gm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	gm.uv1_scale = Vector3(15, 15, 1)
	gm.roughness = 1.0
	var body := StaticBody3D.new()
	body.position = Vector3(0, -0.5, 0)
	body.collision_layer = 1
	body.collision_mask = 0
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(HALF * 2.0, 1.0, HALF * 2.0)
	mi.mesh = bm
	mi.material_override = gm
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = bm.size
	cs.shape = bs
	body.add_child(mi)
	body.add_child(cs)
	add_child(body)

func add_box(pos: Vector3, size: Vector3, color: Color, yaw := 0.0, on_map := true) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation.y = yaw
	body.collision_layer = 1
	body.collision_mask = 0
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(color)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	body.add_child(mi)
	body.add_child(cs)
	add_child(body)
	if on_map:
		var sz := Vector2(size.x, size.z)
		if absf(sin(yaw)) > 0.7:
			sz = Vector2(sz.y, sz.x)
		map_rects.append(Rect2(Vector2(pos.x, pos.z) - sz * 0.5, sz))

func _stripe(pos: Vector3, size: Vector3, color: Color, yaw: float) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(color)
	mi.position = pos
	mi.rotation.y = yaw
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

func _rock(x: float, z: float, r: float, h: float) -> void:
	var body := StaticBody3D.new()
	body.position = Vector3(x, h * 0.5, z)
	body.rotation.y = randf() * TAU
	body.collision_layer = 1
	body.collision_mask = 0
	var cm := CylinderMesh.new()
	cm.top_radius = r * 0.6
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 6
	cm.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	mi.material_override = _mat(Color(0.45, 0.42, 0.4))
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = r * 0.85
	sh.height = h
	cs.shape = sh
	body.add_child(mi)
	body.add_child(cs)
	add_child(body)
	map_rects.append(Rect2(Vector2(x - r * 0.8, z - r * 0.8), Vector2(r * 1.6, r * 1.6)))

func _barrier(x: float, z: float, yaw: float) -> void:
	add_box(Vector3(x, 0.65, z), Vector3(4.0, 1.3, 0.8), Color(0.62, 0.62, 0.6), yaw)
	_stripe(Vector3(x, 1.31, z), Vector3(4.02, 0.04, 0.82), Color(0.95, 0.75, 0.1), yaw)

func _build_walls() -> void:
	var c := Color(0.3, 0.34, 0.4)
	add_box(Vector3(0, 3, -HALF - 0.5), Vector3(HALF * 2.0 + 2.0, 6, 1), c, 0.0, false)
	add_box(Vector3(0, 3, HALF + 0.5), Vector3(HALF * 2.0 + 2.0, 6, 1), c, 0.0, false)
	add_box(Vector3(HALF + 0.5, 3, 0), Vector3(1, 6, HALF * 2.0 + 2.0), c, 0.0, false)
	add_box(Vector3(-HALF - 0.5, 3, 0), Vector3(1, 6, HALF * 2.0 + 2.0), c, 0.0, false)
	var trim := Color(0.9, 0.45, 0.1)
	_stripe(Vector3(0, 0.15, -HALF + 0.02), Vector3(HALF * 2.0, 0.3, 0.05), trim, 0.0)
	_stripe(Vector3(0, 0.15, HALF - 0.02), Vector3(HALF * 2.0, 0.3, 0.05), trim, 0.0)
	_stripe(Vector3(HALF - 0.02, 0.15, 0), Vector3(0.05, 0.3, HALF * 2.0), trim, 0.0)
	_stripe(Vector3(-HALF + 0.02, 0.15, 0), Vector3(0.05, 0.3, HALF * 2.0), trim, 0.0)

func _build_cover() -> void:
	# Central hut with doors north/south
	var hut := Color(0.55, 0.5, 0.45)
	add_box(Vector3(-3.5, 1.5, -4), Vector3(3, 3, 0.6), hut)
	add_box(Vector3(3.5, 1.5, -4), Vector3(3, 3, 0.6), hut)
	add_box(Vector3(-3.5, 1.5, 4), Vector3(3, 3, 0.6), hut)
	add_box(Vector3(3.5, 1.5, 4), Vector3(3, 3, 0.6), hut)
	add_box(Vector3(-5, 1.5, 0), Vector3(0.6, 3, 8.6), hut)
	add_box(Vector3(5, 1.5, 0), Vector3(0.6, 3, 8.6), hut)
	add_box(Vector3(0, 0.6, 0), Vector3(1.5, 1.2, 1.5), Color(0.7, 0.5, 0.25))
	# Concrete barriers
	_barrier(-12, -8, 0.0)
	_barrier(12, 8, 0.0)
	_barrier(-12, 10, PI * 0.5)
	_barrier(12, -10, PI * 0.5)
	_barrier(0, -16, 0.0)
	_barrier(0, 16, 0.0)
	_barrier(-20, 0, PI * 0.5)
	_barrier(20, 0, PI * 0.5)
	# Containers
	add_box(Vector3(-16, 1.3, 8), Vector3(2.4, 2.6, 6), Color(0.2, 0.45, 0.7))
	add_box(Vector3(16, 1.3, -8), Vector3(2.4, 2.6, 6), Color(0.75, 0.3, 0.2))
	# Tall wall segments + pillars
	add_box(Vector3(-14, 1.5, -20), Vector3(6, 3, 0.6), hut)
	add_box(Vector3(14, 1.5, 20), Vector3(6, 3, 0.6), hut)
	for p in [Vector3(-9, 1.75, -9), Vector3(9, 1.75, 9), Vector3(-9, 1.75, 9), Vector3(9, 1.75, -9)]:
		add_box(p, Vector3(1.2, 3.5, 1.2), Color(0.5, 0.52, 0.58))
	# Rocks
	for r in [Vector2(-18, -14), Vector2(18, 14), Vector2(-18, 16), Vector2(18, -16), Vector2(-8, 20),
			Vector2(8, -20), Vector2(-24, -4), Vector2(24, 4), Vector2(-6, -12), Vector2(6, 12)]:
		_rock(r.x, r.y, randf_range(1.3, 1.9), randf_range(2.0, 3.2))
