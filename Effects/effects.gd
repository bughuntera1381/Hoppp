extends Node3D
## Pooled hit sparks and bullet tracers (no allocations during combat).

const IMPACTS := 24
const TRACERS := 20

var _imp: Array[MeshInstance3D] = []
var _imp_life: Array[float] = []
var _imp_i := 0
var _tr: Array[MeshInstance3D] = []
var _tr_life: Array[float] = []
var _tr_i := 0
var _spark: StandardMaterial3D
var _flesh: StandardMaterial3D

func _emissive(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	return m

func _ready() -> void:
	_spark = _emissive(Color(1.0, 0.8, 0.3))
	_flesh = _emissive(Color(1.0, 0.2, 0.15))
	var tracer_mat := _emissive(Color(1.0, 0.92, 0.55))
	var sph := SphereMesh.new()
	sph.radius = 0.1
	sph.height = 0.2
	sph.radial_segments = 6
	sph.rings = 3
	for i in IMPACTS:
		var m := MeshInstance3D.new()
		m.mesh = sph
		m.visible = false
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(m)
		_imp.append(m)
		_imp_life.append(0.0)
	var bx := BoxMesh.new()
	bx.size = Vector3(0.03, 0.03, 1.0)
	for i in TRACERS:
		var t := MeshInstance3D.new()
		t.mesh = bx
		t.material_override = tracer_mat
		t.visible = false
		t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(t)
		_tr.append(t)
		_tr_life.append(0.0)

func _process(delta: float) -> void:
	for i in IMPACTS:
		if _imp_life[i] > 0.0:
			_imp_life[i] -= delta
			if _imp_life[i] <= 0.0:
				_imp[i].visible = false
			else:
				_imp[i].scale = Vector3.ONE * (_imp_life[i] / 0.2)
	for i in TRACERS:
		if _tr_life[i] > 0.0:
			_tr_life[i] -= delta
			if _tr_life[i] <= 0.0:
				_tr[i].visible = false

func impact(pos: Vector3, normal: Vector3, flesh: bool) -> void:
	var i := _imp_i
	_imp_i = (_imp_i + 1) % IMPACTS
	var m := _imp[i]
	m.material_override = _flesh if flesh else _spark
	m.global_position = pos + normal * 0.03
	m.scale = Vector3.ONE
	m.visible = true
	_imp_life[i] = 0.2

func tracer(from: Vector3, to: Vector3) -> void:
	var d := to - from
	var dist := d.length()
	if dist < 0.5:
		return
	var i := _tr_i
	_tr_i = (_tr_i + 1) % TRACERS
	var t := _tr[i]
	var up := Vector3.UP
	if absf(d.normalized().y) > 0.95:
		up = Vector3.RIGHT
	t.visible = true
	t.look_at_from_position(from + d * 0.5, to, up)
	t.scale = Vector3(1.0, 1.0, dist)
	_tr_life[i] = 0.06
