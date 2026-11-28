class_name AmuletActives
extends RefCounted

## Habilidades activas de los AMULETOS (ranura "amuleto" de EquipmentDB, solo mazmorra). La tecla E
## (Player.activate_skill) usa la del amuleto equipado en lugar del Berserk. Cada base de amuleto es su activa
## (mismo id en EquipmentDB.BASES["amuleto"] y en ACTIVES). Sin gasto de recurso: solo enfriamiento.
## La rareza acorta el enfriamiento (CD_MULT) y sube la fuerza (POWER).
## El estado vive en PlayerEquipment (amulet_ready_t, rabbit_armed, mirror_until); los golpes los
## resuelven LootHits.outgoing/after_hit (Pata de Conejo) y Player.take_damage (Espejo del Mohán).

const ACTIVES := {
	"pata_conejo": {"name": "Golpe de Suerte", "cd": 20.0,
		"desc": "Tu próximo golpe hace ×%s de daño y aturde"},
	"botella_aguardiente": {"name": "Trago Valiente", "cd": 60.0,
		"desc": "Cura un %s%% de tu vida y +%s%% velocidad de ataque 6 s"},
	"espejo_mohan": {"name": "Reflejo del Mohán", "cd": 30.0,
		"desc": "Durante 3 s recibes un %s%% menos de daño y devuelves ×%s a los enemigos cercanos"},
	"pluma_gallinazo": {"name": "Vuelo de Gallinazo", "cd": 12.0,
		"desc": "Te teletransportas %s m hacia la mira, invulnerable un instante"},
}
## Por rareza (Común, Poco común, Rara, Legendaria, Mítica)
const CD_MULT := [1.0, 0.92, 0.84, 0.76, 0.68]
const POWER := [1.0, 1.1, 1.2, 1.35, 1.5]

const RABBIT_MULT := 3.0
const AGUARDIENTE_HEAL := 0.30
const AGUARDIENTE_SPEED := 0.20
const AGUARDIENTE_DUR := 6.0
const MIRROR_DUR := 3.0
const MIRROR_BLOCK := 0.7          ## fracción del daño recibido que se quita
const MIRROR_REFLECT := 2.0        ## × daño recibido que se devuelve
const MIRROR_RADIUS := 4.0
const PLUMA_DIST := 7.0
const PLUMA_INVULN := 0.5
const COLOR := Color(0.55, 0.95, 0.85)
const BUFF_UID := "amuleto"        ## clave del bonus temporal en PlayerEquipment._buffs

## Icono dibujado del amuleto (tools/make_item_icons.py -> assets/ui/icons/amulets/<base>.png); null si no hay.
static func icon(item: Dictionary) -> Texture2D:
	var id := id_of(item)
	var path := "res://assets/ui/icons/amulets/%s.png" % id
	return load(path) if id != "" and ResourceLoader.exists(path) else null

static func id_of(item: Dictionary) -> String:
	if String(item.get("slot", "")) != "amuleto":
		return ""
	var id := String(item.get("base", ""))
	return id if ACTIVES.has(id) else ""

static func _rarity(item: Dictionary) -> int:
	return clampi(int(item.get("rarity", 0)), 0, POWER.size() - 1)

static func power(item: Dictionary) -> float:
	return float(POWER[_rarity(item)])

static func cooldown(item: Dictionary) -> float:
	var id := id_of(item)
	return 0.0 if id == "" else float(ACTIVES[id]["cd"]) * float(CD_MULT[_rarity(item)])

static func rabbit_mult(item: Dictionary) -> float:
	return RABBIT_MULT * power(item)

## "Golpe de Suerte (E): Tu próximo golpe hace ×3 de daño y aturde · 20 s"
static func text(item: Dictionary) -> String:
	var id := id_of(item)
	if id == "":
		return ""
	var a: Dictionary = ACTIVES[id]
	var p := power(item)
	var desc := String(a["desc"])
	match id:
		"pata_conejo":
			desc = desc % [_num(rabbit_mult(item))]
		"botella_aguardiente":
			desc = desc % [int(round(AGUARDIENTE_HEAL * p * 100.0)), int(round(AGUARDIENTE_SPEED * p * 100.0))]
		"espejo_mohan":
			desc = desc % [int(round(MIRROR_BLOCK * 100.0)), _num(MIRROR_REFLECT * p)]
		"pluma_gallinazo":
			desc = desc % [_num(PLUMA_DIST * minf(p, 1.25))]
	return "%s (E): %s · %d s" % [a["name"], desc, int(round(cooldown(item)))]

static func _num(v: float) -> String:
	return str(int(v)) if is_equal_approx(v, round(v)) else "%.1f" % v

## Usa la activa del amuleto equipado. true si salió (si no: sin amuleto o en enfriamiento).
static func use(eq: PlayerEquipment) -> bool:
	var item := eq.get_item("amuleto")
	var id := id_of(item)
	if id == "" or eq.amulet_cooldown_left() > 0.0:
		return false
	var player: Node3D = eq.player as Node3D
	if player == null or not player.is_inside_tree():
		return false
	var now := eq._now()
	var p := power(item)
	var root := player.get_tree().current_scene
	match id:
		"pata_conejo":
			eq.rabbit_armed = true
			EquipmentPickup.toast(player, "¡SUERTE!", Color(1.0, 0.9, 0.4))
			if root:
				ToonFX.ring_burst(root, player.global_position, 1.6, Color(1.0, 0.9, 0.4), 0.35)
			AudioManager.play("kill_burst", -8.0, 1.7)
		"botella_aguardiente":
			var hc: Node = player.get("health_comp")
			if hc and player.has_method("heal"):
				player.heal(float(hc.max_hp) * AGUARDIENTE_HEAL * p)
			eq._buffs[BUFF_UID] = {"stats": {"attack_speed": AGUARDIENTE_SPEED * p}, "until": now + AGUARDIENTE_DUR,
				"name": String(ACTIVES[id]["name"])}
			EquipmentPickup.toast(player, "¡SALUD!", Color(1.0, 0.55, 0.2))
			if root:
				ToonFX.puff_burst(root, player.global_position + Vector3(0, 0.8, 0), Color(0.5, 1.0, 0.5), 8, 2.5, 0.4)
			AudioManager.play("boss_sting", -10.0, 1.5)
		"espejo_mohan":
			eq.mirror_until = now + MIRROR_DUR
			EquipmentPickup.toast(player, "REFLEJO", COLOR)
			if root:
				ToonFX.ring_burst(root, player.global_position, MIRROR_RADIUS, COLOR, 0.5)
			AudioManager.play("boss_sting", -8.0, 2.0)
		"pluma_gallinazo":
			_blink(player, PLUMA_DIST * minf(p, 1.25), root)
		_:
			return false
	eq.amulet_ready_t = now + cooldown(item)
	eq.amulet_used.emit(item)
	RunLog.proc("amulet:" + id)
	return true

## Espejo activo: devuelve el daño que entra (reducido) y lo refleja a los enemigos cercanos.
static func mirror_incoming(eq: PlayerEquipment, amount: float) -> float:
	var player: Node3D = eq.player as Node3D
	var reflect := amount * MIRROR_REFLECT * power(eq.get_item("amuleto"))
	for e in LootHits._enemies_near(player, player.global_position, MIRROR_RADIUS, true):
		LootHits._pop(e, "REFLEJO", COLOR)
		LootHits._fx_damage(e, reflect)
	var root := player.get_tree().current_scene
	if root:
		ToonFX.ring_burst(root, player.global_position, MIRROR_RADIUS * 0.6, COLOR, 0.3)
	return amount * (1.0 - MIRROR_BLOCK)

## Salto corto hacia la mira (para en las paredes) con invulnerabilidad.
static func _blink(player: Node3D, dist: float, root: Node) -> void:
	var from := player.global_position
	var dir := Vector3.ZERO
	var aim: Vector3 = player.get_camera_aim_point() if player.has_method("get_camera_aim_point") else Vector3.ZERO
	if aim != Vector3.ZERO:
		dir = aim - from
	dir.y = 0.0
	if dir.length() < 0.5:
		dir = -player.global_transform.basis.z
		dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
	if root:
		ToonFX.puff_burst(root, from + Vector3(0, 0.8, 0), Color(0.15, 0.12, 0.18), 10, 2.5, 0.5)
	if player is CharacterBody3D:
		(player as CharacterBody3D).move_and_collide(dir * dist)
	else:
		player.global_position = from + dir * dist
	var hc: Node = player.get("health_comp")
	if hc and hc.has_method("set_invincibility"):
		hc.set_invincibility(PLUMA_INVULN)
	if root:
		ToonFX.puff_burst(root, player.global_position + Vector3(0, 0.8, 0), Color(0.15, 0.12, 0.18), 10, 2.5, 0.5)
	AudioManager.play("dagger_dash", -4.0, 0.9)
	HitFeedback.shake(0.1)
