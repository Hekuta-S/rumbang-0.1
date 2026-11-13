class_name MetaProgress
extends RefCounted

## Progresión entre partidas: logros con recompensa permanente y el códice de evoluciones.
## Los contadores y lo descubierto se guardan en SaveManager.meta (user://soul_knight_save.json).
## Los logros se comprueban al sumar (record / record_max) y avisan con un cartel al desbloquearse.
##  stat: contador de SaveManager.meta que mide el progreso · goal: lo que hace falta
##  reward: lo que da (lo leen GameState, DungeonEncounter y DungeonShop con bonus())

const ACHIEVEMENTS := {
	"evolucionista": {"name": "Evolucionista", "desc": "Descubre una evolución de arma",
		"stat": "evolutions_found", "goal": 1, "reward": "+1 volver a tirar por partida"},
	"coleccionista": {"name": "Coleccionista", "desc": "Descubre 5 evoluciones distintas",
		"stat": "evolutions_found", "goal": 5, "reward": "+1 descartar por partida"},
	"matanecros": {"name": "Mata-nigromantes", "desc": "Vence al Nigromante en supervivencia",
		"stat": "survival_boss_kills", "goal": 1, "reward": "+1 volver a tirar por partida"},
	"infinito": {"name": "Sin final", "desc": "Aguanta 3 minutos en el modo infinito",
		"stat": "best_endless_s", "goal": 180, "reward": "+1 descartar por partida"},
	"verdugo": {"name": "Verdugo", "desc": "Remata a 50 enemigos en la mazmorra",
		"stat": "finishers", "goal": 50, "reward": "Empiezas la mazmorra con un tomo"},
	"retador": {"name": "Retador", "desc": "Supera 5 desafíos de la mazmorra",
		"stat": "challenges_won", "goal": 5, "reward": "Forja desde el nivel 1"},
	# Armas de supervivencia que empiezan bloqueadas (WEAPON_UNLOCKS): salen en las cartas al desbloquearlas.
	"w_serpientes": {"name": "Domador", "desc": "Juega 2 partidas de supervivencia",
		"stat": "survival_runs", "goal": 2, "reward": "Desbloquea: Serpientes", "weapon": WeaponData.WeaponType.SERPENTS},
	"w_brazo": {"name": "Veterano", "desc": "Juega 5 partidas de supervivencia",
		"stat": "survival_runs", "goal": 5, "reward": "Desbloquea: Brazo zombi", "weapon": WeaponData.WeaponType.ZOMBIE_ARM},
	"w_polvos": {"name": "Alquimista", "desc": "Llega al nivel 10 en supervivencia",
		"stat": "best_level", "goal": 10, "reward": "Desbloquea: Polvos", "weapon": WeaponData.WeaponType.DUSTS},
	"w_esporas": {"name": "Micólogo", "desc": "Llega al nivel 15 en supervivencia",
		"stat": "best_level", "goal": 15, "reward": "Desbloquea: Bazuca de esporas", "weapon": WeaponData.WeaponType.SPORE_BAZOOKA},
	"w_elementos": {"name": "Elementalista", "desc": "Llega al nivel 20 en supervivencia",
		"stat": "best_level", "goal": 20, "reward": "Desbloquea: Ciclo elemental", "weapon": WeaponData.WeaponType.ELEMENTS_CYCLE},
	"w_espadon": {"name": "Matagigantes", "desc": "Vence al Nigromante en supervivencia",
		"stat": "survival_boss_kills", "goal": 1, "reward": "Desbloquea: Espadón", "weapon": WeaponData.WeaponType.GREATSWORD},
	"w_railgun": {"name": "Francotirador", "desc": "Llega al nivel 30 en supervivencia",
		"stat": "best_level", "goal": 30, "reward": "Desbloquea: Cañón de riel", "weapon": WeaponData.WeaponType.RAILGUN},
}
const COLOR := Color(1.0, 0.84, 0.3)

static func stat(name: String) -> int:
	return int(SaveManager.meta.get(name, 0))

static func unlocked(id: String) -> bool:
	var a: Dictionary = ACHIEVEMENTS[id]
	return stat(a["stat"]) >= int(a["goal"])

## Suma `amount` a un contador (y guarda).
static func record(name: String, amount: int = 1) -> void:
	_store(name, stat(name) + amount)

## Guarda el máximo (récords como el tiempo en el modo infinito).
static func record_max(name: String, value: int) -> void:
	if value > stat(name):
		_store(name, value)

static func _store(name: String, value: int) -> void:
	var before: Array = ACHIEVEMENTS.keys().filter(func(id): return unlocked(id))
	SaveManager.meta[name] = value
	SaveManager.save()
	for id in ACHIEVEMENTS:
		if not before.has(id) and unlocked(id):
			_toast(ACHIEVEMENTS[id])

## Una evolución usada por primera vez entra en el códice.
static func discover_evolution(weapon: int) -> void:
	var found: Array = SaveManager.meta.get("evolutions", [])
	if found.has(weapon):
		return
	found.append(weapon)
	SaveManager.meta["evolutions"] = found
	record("evolutions_found")

static func evolution_known(weapon: int) -> bool:
	return (SaveManager.meta.get("evolutions", []) as Array).has(weapon)

## Ventajas desbloqueadas que se usan al jugar.
## Un arma sin logro asociado está siempre disponible; con logro, solo al cumplirlo.
static func weapon_unlocked(weapon: int) -> bool:
	for id in ACHIEVEMENTS:
		var a: Dictionary = ACHIEVEMENTS[id]
		if a.has("weapon") and int(a["weapon"]) == weapon:
			return unlocked(id)
	return true

## Fin de una partida de supervivencia: cuenta la partida y el mejor nivel (una sola vez por partida).
static func record_survival_run(level: int) -> void:
	if RunStats.run_recorded:
		return
	RunStats.run_recorded = true
	record_max("best_level", level)
	record("survival_runs")

static func bonus_rerolls() -> int:
	return int(unlocked("evolucionista")) + int(unlocked("matanecros"))

static func bonus_banishes() -> int:
	return int(unlocked("coleccionista")) + int(unlocked("infinito"))

static func starting_rune() -> bool:
	return unlocked("verdugo")

static func early_forge() -> bool:
	return unlocked("retador")

static func _toast(a: Dictionary) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.current_scene == null:
		return
	var layer := CanvasLayer.new()
	layer.layer = 95
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	var l := Label.new()
	l.text = "LOGRO: %s\n%s" % [String(a["name"]).to_upper(), a["reward"]]
	l.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	l.grow_horizontal = Control.GROW_DIRECTION_BOTH
	l.grow_vertical = Control.GROW_DIRECTION_BEGIN
	l.offset_bottom = -150.0
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.theme = RumbangStyle.get_theme()
	RumbangStyle.style_title(l, 18, COLOR, RumbangStyle.NEON_CYAN)
	layer.add_child(l)
	tree.current_scene.add_child(layer)
	l.modulate.a = 0.0
	var tw := l.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(l, "modulate:a", 1.0, 0.3)
	tw.tween_interval(3.0)
	tw.tween_property(l, "modulate:a", 0.0, 0.6)
	tw.tween_callback(layer.queue_free)
	AudioManager.play("level-up", -4.0, 0.9)
