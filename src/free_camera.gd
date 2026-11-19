## Fly-through camera: WASD moves, Space/Shift rises and sinks, mouse looks.
## Escape frees the cursor; clicking the view captures it again.
class_name FreeCamera
extends Camera3D

## Metres per second.
@export var speed := 6.0

## Radians of rotation per pixel of mouse movement.
@export var mouse_sensitivity := 0.002

## Pitch limit in radians, just short of straight up/down, so the view cannot roll.
const PITCH_LIMIT := 1.5

var _looking := false


func _ready() -> void:
	_set_looking(true)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and _looking:
		rotate_y(-event.relative.x * mouse_sensitivity)
		rotation.x = clampf(
			rotation.x - event.relative.y * mouse_sensitivity, -PITCH_LIMIT, PITCH_LIMIT)
	elif event.is_action_pressed(&"ui_cancel"):
		_set_looking(false)
	elif event is InputEventMouseButton and event.pressed:
		_set_looking(true)


func _process(delta: float) -> void:
	var dir := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		dir -= Vector3(transform.basis.z.x, 0.0, transform.basis.z.z).normalized()
	if Input.is_physical_key_pressed(KEY_S):
		dir += Vector3(transform.basis.z.x, 0.0, transform.basis.z.z).normalized()
	if Input.is_physical_key_pressed(KEY_A):
		dir -= transform.basis.x
	if Input.is_physical_key_pressed(KEY_D):
		dir += transform.basis.x
	if Input.is_physical_key_pressed(KEY_SPACE):
		dir.y += 1.0
	if Input.is_physical_key_pressed(KEY_SHIFT):
		dir.y -= 1.0
	if dir != Vector3.ZERO:
		global_position += dir.normalized() * speed * delta


func _set_looking(looking: bool) -> void:
	_looking = looking
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if looking else Input.MOUSE_MODE_VISIBLE
