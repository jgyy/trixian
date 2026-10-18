class_name Cultivation
extends RefCounted

## Pure cultivation rules: qi accumulation and realm breakthroughs.
## Kept free of scene nodes so it can be unit tested headlessly.

const REALM_NAMES: PackedStringArray = [
	"Qi Condensation",
	"Foundation Establishment",
	"Core Formation",
	"Nascent Soul",
	"Soul Transformation",
]
const BASE_QI_REQUIRED := 100.0

var realm_index := 0
var qi := 0.0


func realm_name() -> String:
	return REALM_NAMES[realm_index]


func is_max_realm() -> bool:
	return realm_index >= REALM_NAMES.size() - 1


## Qi needed to break through out of the current realm. Doubles every realm.
func qi_required() -> float:
	return BASE_QI_REQUIRED * pow(2.0, realm_index)


func progress() -> float:
	return clampf(qi / qi_required(), 0.0, 1.0)


func gain_qi(amount: float) -> void:
	if amount > 0.0:
		qi += amount


func can_breakthrough() -> bool:
	return not is_max_realm() and qi >= qi_required()


## Attempts a breakthrough. On success the qi cost is consumed and the realm advances.
func try_breakthrough() -> bool:
	if not can_breakthrough():
		return false
	qi -= qi_required()
	realm_index += 1
	return true
