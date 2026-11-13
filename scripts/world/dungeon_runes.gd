class_name DungeonRunes
extends RefCounted

## Fachada de compatibilidad: las runas ahora son los tomos de la mazmorra (TomeDB.DUNGEON).
## Se mantiene el nombre para los llamadores existentes; el catálogo y la lógica viven en TomeDB.

const COLOR := TomeDB.DUNGEON_COLOR

static func has(id: String) -> bool:
	return TomeDB.dungeon_has(id)

static func rune_name(id: String) -> String:
	return TomeDB.dungeon_name(id)

static func level(id: String) -> int:
	return TomeDB.dungeon_level(id)

static func can_add(id: String) -> bool:
	return TomeDB.dungeon_can_add(id)

static func add(id: String) -> void:
	TomeDB.dungeon_add(id)

static func roll(count: int) -> Array:
	return TomeDB.dungeon_roll(count)

static func option(id: String, price: int = -1) -> Dictionary:
	return TomeDB.dungeon_option(id, price)

static func stun_mult() -> float:
	return TomeDB.dungeon_stun_mult()

static func finisher_heal_bonus() -> float:
	return TomeDB.dungeon_finisher_heal_bonus()

static func apply(mods: Dictionary) -> void:
	TomeDB.dungeon_apply(mods)
