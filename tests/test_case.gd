class_name TestCase
extends RefCounted
## Minimal test base: call check(); runner reads `failures`.

var failures: PackedStringArray = []
var current := ""


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures.append("%s: %s" % [current, msg])


func near(a: float, b: float, eps := 1e-4) -> bool:
	return absf(a - b) <= eps
