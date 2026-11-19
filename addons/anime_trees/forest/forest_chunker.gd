@tool
class_name ForestChunker
extends RefCounted


static func cell_of(pos: Vector3, cell_size: float) -> Vector2i:
	return Vector2i(floori(pos.x / cell_size), floori(pos.z / cell_size))


## -> { Vector2i cell: { variant_index: Array[Transform3D] } }
static func chunk(data: ForestData, cell_size: float) -> Dictionary:
	var cells := {}
	for i in data.count():
		var c := cell_of(data.position(i), cell_size)
		var per_variant: Dictionary = cells.get_or_add(c, {})
		var list: Array = per_variant.get_or_add(data.variant(i), [])
		list.append(data.transform(i))
	return cells
