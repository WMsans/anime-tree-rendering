extends Node3D
## Demo cameras. 1 = free camera (WASD, Space up, Shift down), 2 = orbit, 3 = flyover.
## Mouse looks around (mouse is captured on start; Esc releases it, click to recapture).
## Shows FPS and draw calls.

@export var walk_speed := 12.0
@export var orbit_speed := 0.08
@export var fly_speed := 25.0
@export var mouse_sensitivity := 0.003
@export var animate := true  ## perf/capture scripts turn this off for stable views

@onready var cams := {1: $CamWalk, 2: $CamOrbit, 3: $CamFly}
var _mode := 1
var _orbit_angle := 0.0
var _label := Label.new()


func _ready() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	layer.add_child(_label)
	_label.position = Vector2(12, 8)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	set_mode(1)


func set_mode(m: int) -> void:
	_mode = m
	(cams[m] as Camera3D).make_current()


func _input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and e.keycode in [KEY_1, KEY_2, KEY_3]:
		set_mode(e.keycode - KEY_0)
	elif e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif e is InputEventMouseMotion and _mode != 2 and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var c: Camera3D = cams[_mode]
		c.rotation.y -= e.relative.x * mouse_sensitivity
		c.rotation.x = clampf(c.rotation.x - e.relative.y * mouse_sensitivity, -1.5, 1.5)


func _process(dt: float) -> void:
	_label.text = "%d fps  |  %d draw calls  |  [1] free  [2] orbit  [3] flyover" % [
		Engine.get_frames_per_second(),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)]
	if not animate:
		return
	if _mode == 1:
		var c: Camera3D = cams[1]
		var dir := Vector3.ZERO
		for k in [[KEY_W, Vector3.FORWARD], [KEY_S, Vector3.BACK], [KEY_A, Vector3.LEFT], [KEY_D, Vector3.RIGHT]]:
			if Input.is_physical_key_pressed(k[0]):
				dir += k[1]
		var up := 1.0 if Input.is_physical_key_pressed(KEY_SPACE) else 0.0
		up -= 1.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 0.0
		c.position += (c.global_basis * dir.normalized() + Vector3.UP * up) * walk_speed * dt
	elif _mode == 2:
		_orbit_angle += orbit_speed * dt
		var c: Camera3D = cams[2]
		c.look_at_from_position(Vector3(sin(_orbit_angle), 0.0, cos(_orbit_angle)) * 60.0 + Vector3(0, 14, 0), Vector3(0, 10, 0))
	elif _mode == 3:
		var c: Camera3D = cams[3]
		c.position += -c.global_basis.z.slide(Vector3.UP).normalized() * fly_speed * dt
