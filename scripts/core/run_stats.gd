class_name RunStats
extends RefCounted

## Números de la partida de supervivencia para el resumen final (pantallas de victoria y caída):
## daño por arma, muertes, élites, eventos y santuarios. Lo reinicia GameState.reset_session().
## El daño lo suma EnemyData.take_damage() con el arma que marcó HitFeedback.weapon_tag.

static var damage_by_weapon: Dictionary = {}   ## WeaponType (o -1: otros) -> daño
static var kills: int = 0
static var elites: int = 0
static var events: int = 0
static var shrines: int = 0
static var boss_killed := false
static var endless_from: float = -1.0          ## segundo en que empezó el modo infinito (-1: no)

static func reset() -> void:
	damage_by_weapon.clear()
	kills = 0
	elites = 0
	events = 0
	shrines = 0
	boss_killed = false
	endless_from = -1.0

static func add_damage(weapon: int, amount: float) -> void:
	if amount > 0.0:
		damage_by_weapon[weapon] = float(damage_by_weapon.get(weapon, 0.0)) + amount

## Líneas del resumen. `winv` (PlayerWeaponInventory) da los nombres (evolucionados) y las sinergias.
static func summary_lines(winv) -> Array:
	var lines: Array = []
	lines.append("ENEMIGOS %d     ELITES %d" % [kills, elites])
	lines.append("EVENTOS %d     SANTUARIOS %d" % [events, shrines])
	if endless_from >= 0.0:
		var t := int(GameState.get_instance().elapsed_time - endless_from)
		lines.append("MODO INFINITO %d:%02d" % [t / 60, t % 60])
	var total := 0.0
	for w in damage_by_weapon:
		total += float(damage_by_weapon[w])
	if total > 0.0:
		var order: Array = damage_by_weapon.keys()
		order.sort_custom(func(a, b): return damage_by_weapon[a] > damage_by_weapon[b])
		for w in order.slice(0, 4):
			var name := "Otros" if int(w) < 0 else (WeaponSynergies.weapon_name(winv, w) if winv else str(WeaponData.weapon_names.get(w, "Arma")))
			lines.append("%s  %d  (%d%%)" % [name, int(damage_by_weapon[w]), int(round(100.0 * float(damage_by_weapon[w]) / total))])
	if winv:
		var syn: Array = WeaponSynergies.active(winv.weapon_slots)
		if not syn.is_empty():
			lines.append("Mejor sinergia: " + WeaponSynergies.describe(syn[0]))
	return lines
