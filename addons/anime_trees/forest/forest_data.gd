@tool
class_name ForestData
extends Resource
## Placed tree instances. instances: stride 5 = variant_index, x, y, z, yaw. scales: one per instance.

@export var variant_scenes: Array[PackedScene] = []
@export var instances := PackedFloat32Array()
@export var scales := PackedFloat32Array()


func add(variant: int, pos: Vector3, yaw: float, scale: float) -> void:
	instances.append_array([variant, pos.x, pos.y, pos.z, yaw])
	scales.append(scale)


func count() -> int:
	return scales.size()


func clear() -> void:
	instances = PackedFloat32Array()
	scales = PackedFloat32Array()


func variant(i: int) -> int:
	return int(instances[i * 5])


func position(i: int) -> Vector3:
	return Vector3(instances[i * 5 + 1], instances[i * 5 + 2], instances[i * 5 + 3])


func transform(i: int) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, instances[i * 5 + 4]).scaled(Vector3.ONE * scales[i]), position(i))
