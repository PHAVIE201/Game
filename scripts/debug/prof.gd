class_name Prof
## Tiny opt-in profiler for the automated simulations: sections add their
## elapsed microseconds; the match simulation prints ms per physics tick.
## Disabled (one static bool check) during normal play.

static var enabled := false
static var totals: Dictionary = {}


static func add(key: StringName, since_usec: int) -> void:
	totals[key] = int(totals.get(key, 0)) + Time.get_ticks_usec() - since_usec


static func take() -> Dictionary:
	var out := totals
	totals = {}
	return out
