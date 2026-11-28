class_name ItemEffects
extends Node

## Efectos de los objetos de supervivencia que no son stats planos (ItemDB "kind"):
##  - "passive": reaccionan a eventos (golpe acertado, baja, daño recibido, subida de nivel) o al estado
##    del jugador (quieto, enemigos pegados).
##  - "active": un solo hueco; la tecla E (Player.activate_skill) lo usa en lugar del Berserk.
## Todos los efectos visuales son dibujos entintados 2D (ToonFX, tools/make_item_fx.py → objetos.png).
## Vive como hijo del jugador (solo fuera de la mazmorra). EnemyData.take_damage avisa de cada golpe
## directo y de cada baja con métodos estáticos (no hay que buscar al jugador en cada golpe).
## Los bonus temporales de stats (Hamaca, Garrafón) los suma PlayerStatBlock._total con stat_total().

signal active_used(item_id: String)

const TOTUMA_HEAL := 0.25
const TOTUMA_INVULN := 2.0
const LLORONA_RADIUS := 6.0
const LLORONA_STUN := 1.5
const LLORONA_PUSH := 14.0
const LLORONA_CD := 8.0
const LLORONA_COLOR := Color(0.65, 0.85, 1.0)
const TEJO_EVERY := 8
const TEJO_RADIUS := 3.2
const TEJO_DAMAGE := 18.0          ## base, × multiplicador de daño; +50 % por copia extra
const TEJO_ELITE_FRAC := 0.06      ## mínimo contra cualquiera: fracción de su vida máxima
const TEJO_COLOR := Color(1.0, 0.55, 0.15)
const VUELTIAO_EVERY := 15
const VUELTIAO_RADIUS := 5.0
const VUELTIAO_DAMAGE := 25.0
const VUELTIAO_COLOR := Color(0.95, 0.9, 0.7)
const VINE_CHANCE := 0.25
const VINE_MAX := 8
const CANDILEJA_RADIUS := 2.6
const CANDILEJA_DPS := 6.0
const CANDILEJA_TICK := 0.5
const CANDILEJA_COLOR := Color(1.0, 0.5, 0.15)
const HAMACA_STILL := 1.5           ## s quieto para que empiece
const HAMACA_HEAL := 1.5            ## vida por segundo
const HAMACA_ARMOR := 0.20
const PATASOLA_HP := 0.5
const PATASOLA_INVULN := 2.0
const PATASOLA_COLOR := Color(0.55, 1.0, 0.6)
const DUENDE_CHANCE := 0.15         ## por copia; la suerte suma la mitad de su valor
const POLVORA_RANGE := 22.0
const POLVORA_RADIUS := 5.0
const POLVORA_DAMAGE := 45.0
const POLVORA_FRAC := 0.12
const TAMAL_HEAL := 0.40
const TROMPO_TIME := 5.0
const MACHETE_DIST := 8.0
const MACHETE_WIDTH := 1.6
const MACHETE_DAMAGE := 40.0
const MACHETE_COLOR := Color(0.7, 0.9, 1.0)
const GARRAFON_TIME := 6.0
const GARRAFON_SPEED := 0.5
const GARRAFON_ARMOR := -0.15
const CAMPANA_RADIUS := 12.0
const CAMPANA_FREEZE := 2.0
const CAMPANA_COLOR := Color(1.0, 0.85, 0.35)

static var _inst: ItemEffects = null

var player: Node3D
var _llorona_ready := 0.0
var _tejo_hits := 0
var _kills := 0
var _candileja_t := 0.0
var _candileja_fx_t := 0.0
var _still_t := 0.0
var _furia_until := 0.0
var _coin_fx_t := -10.0
var _hamaca_fx_t := -10.0
var _anger: Sprite3D
var _active_cd := 0.0             ## segundos que faltan para poder usar la activa
var _in_proc := false             ## evita que las explosiones de objetos cuenten como golpe

func _ready() -> void:
	_inst = self
	if player == null:
		player = get_parent() as Node3D
	var xp: Node = player.get("experience_comp") if player else null
	if xp and xp.has_signal("leveled_up"):
		xp.leveled_up.connect(func(_lvl): _on_level_up())
	var inv: InventoryComponent = _inventory()
	if inv:
		inv.item_added.connect(func(id: String):
			if ItemDB.is_active(id):
				_active_cd = 0.0   # la activa nueva llega lista
		)

func _exit_tree() -> void:
	if _inst == self:
		_inst = null

func _process(delta: float) -> void:
	if _active_cd > 0.0:
		_active_cd = maxf(0.0, _active_cd - delta)
	if player == null:
		return
	_tick_hamaca(delta)
	_tick_candileja(delta)

func _inventory() -> InventoryComponent:
	return player.get("inventory") as InventoryComponent if player else null

func count(id: String) -> int:
	var inv := _inventory()
	return inv.count_item(id) if inv else 0

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func _root() -> Node:
	return get_tree().current_scene if is_inside_tree() else null

func _damage_mult() -> float:
	var sb = player.get("stat_block") if player else null
	return sb.damage_mult() if sb else 1.0

## Dibujo de objetos.png que salta sobre el jugador (todos los efectos son 2D entintados, ToonFX).
func _pop(frame: int, size: float = 1.0, height: float = 2.3, tint: Color = Color.WHITE) -> void:
	var root := _root()
	if root and player:
		ToonFX.item_pop(root, player.global_position + Vector3(0, height, 0), frame, size, 0.6, 0.35, tint)

## Enemigos vivos a `radius` m (en el plano) de `center`.
func _enemies_near(center: Vector3, radius: float) -> Array:
	var out: Array = []
	for e in EnemyRegistry.all():
		if not (e is EnemyData) or e.recycled:
			continue
		var off: Vector3 = e.global_position - center
		if absf(off.y) > 3.0:
			continue
		if Vector2(off.x, off.z).length() <= radius:
			out.append(e)
	return out

# ───────────────────────────── Stats temporales ─────────────────────────────

## Lo suma PlayerStatBlock._total: bonus de la Hamaca (quieto) y del Garrafón (furia).
static func stat_total(stat: String) -> float:
	if _inst == null:
		return 0.0
	return _inst._stat(stat)

func _stat(stat: String) -> float:
	var t := 0.0
	match stat:
		"armor":
			if hamaca_on():
				t += HAMACA_ARMOR
			if furia_on():
				t += GARRAFON_ARMOR
		"attack_speed":
			if furia_on():
				t += GARRAFON_SPEED
	return t

func furia_on() -> bool:
	return _now() < _furia_until

func hamaca_on() -> bool:
	return _still_t >= HAMACA_STILL and count("hamaca_abuelo") > 0

# ───────────────────────────── Pasivas ─────────────────────────────

## Lo llama EnemyData.take_damage en cada golpe directo (no en el daño continuo).
static func on_enemy_hit(enemy: EnemyData, _amount: float) -> void:
	if _inst != null and not _inst._in_proc:
		_inst._on_hit(enemy)

## Lo llama EnemyData.take_damage cuando el enemigo cae (también por daño continuo).
static func on_enemy_killed(enemy: EnemyData) -> void:
	if _inst != null:
		_inst._on_kill(enemy)

func _on_hit(enemy: EnemyData) -> void:
	var tejo := count("mecha_tejo")
	if tejo <= 0:
		return
	_tejo_hits += 1
	if _tejo_hits < TEJO_EVERY:
		return
	_tejo_hits = 0
	var dmg := TEJO_DAMAGE * (1.0 + 0.5 * float(tejo - 1)) * _damage_mult()
	_blast(enemy.global_position, TEJO_RADIUS, dmg, TEJO_ELITE_FRAC, TEJO_COLOR)
	RunLog.proc("item:mecha_tejo")

func _on_kill(enemy: EnemyData) -> void:
	if count("collar_madremonte") > 0 and randf() < VINE_CHANCE \
			and get_tree().get_nodes_in_group("vine_patches").size() < VINE_MAX:
		var root := _root()
		if root:
			VinePatch.spawn(root, enemy.global_position)
	if count("sombrero_vueltiao") > 0:
		_kills += 1
		if _kills >= VUELTIAO_EVERY:
			_kills = 0
			_whirlwind.call_deferred()   # no dañar dentro del take_damage de otro enemigo

func _whirlwind() -> void:
	if player == null:
		return
	var center := player.global_position
	_in_proc = true
	for e in _enemies_near(center, VUELTIAO_RADIUS).duplicate():
		var off: Vector3 = e.global_position - center
		off.y = 0.0
		var dir := off.normalized() if off.length() > 0.05 else Vector3.FORWARD
		e.take_damage(VUELTIAO_DAMAGE * _damage_mult(), dir * 16.0)
	_in_proc = false
	var root := _root()
	if root:
		ToonFX.ring_burst(root, center + Vector3(0, 0.3, 0), VUELTIAO_RADIUS * 1.5, VUELTIAO_COLOR, 0.5)
		# Remolino dibujado en el suelo que gira y se abre
		var whirl := ToonFX.item_decal(ToonFX.ITEM_FX_WHIRL, VUELTIAO_RADIUS * 2.0)
		root.add_child(whirl)
		whirl.global_position = center + Vector3(0, 0.12, 0)
		whirl.scale = Vector3.ONE * 0.3
		var tw := whirl.create_tween().set_parallel(true)
		tw.tween_property(whirl, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(whirl, "rotation:y", whirl.rotation.y - TAU, 0.6)
		tw.chain().tween_property(whirl, "scale", Vector3.ZERO, 0.15)
		tw.chain().tween_callback(whirl.queue_free)
		ToonFX.puff_burst(root, center + Vector3(0, 0.4, 0), VUELTIAO_COLOR, 10, 5.0, 0.6)
	AudioManager.play("kill_burst", -6.0, 0.8)
	RunLog.proc("item:sombrero_vueltiao")

## Daño en área (tejo, totumo). Devuelve a cuántos dio.
func _blast(center: Vector3, radius: float, dmg: float, frac: float, col: Color) -> int:
	_in_proc = true
	var hits := 0
	for e in _enemies_near(center, radius).duplicate():
		var off: Vector3 = e.global_position - center
		off.y = 0.0
		var d := off.length()
		var dir := off / d if d > 0.05 else Vector3.FORWARD
		e.take_damage(maxf(dmg, e.max_hp * frac) * lerpf(1.0, 0.6, d / radius), dir * 6.0)
		hits += 1
	_in_proc = false
	var root := _root()
	if root:
		ToonFX.ring_burst(root, center + Vector3(0, 0.15, 0), radius * 1.4, col, 0.35)
		ToonFX.impact_pop(root, center + Vector3(0, 0.8, 0), col, 1.4)
	AudioManager.play_at("explosion", center, -6.0, randf_range(1.05, 1.25))
	HitFeedback.shake(0.15)
	return hits

## Lo llama Player.take_damage cuando el golpe entra.
func on_hurt() -> void:
	_still_t = 0.0                 # un golpe te saca de la hamaca
	if count("ruana_llorona") <= 0 or _now() < _llorona_ready:
		return
	_llorona_ready = _now() + LLORONA_CD
	var center := player.global_position
	for e in _enemies_near(center, LLORONA_RADIUS):
		var off: Vector3 = e.global_position - center
		off.y = 0.0
		var d := off.length()
		e.apply_slow(LLORONA_STUN, 0.0)
		e.set_knockback((off / d if d > 0.05 else Vector3.FORWARD) * LLORONA_PUSH)
	var root := _root()
	if root:
		ToonFX.ring_burst(root, center, LLORONA_RADIUS, LLORONA_COLOR, 0.45)
	_pop(ToonFX.ITEM_FX_GHOST, 1.3)
	AudioManager.play("boss_sting", -10.0, 1.8)
	RunLog.proc("item:ruana_llorona")

## Lo llama el damage_taking del jugador con el daño final: si te mataría y llevas el Pacto de la
## Patasola, lo rompe y devuelve el daño que te deja a PATASOLA_HP de la vida (negativo = cura).
func on_incoming(amount: float) -> float:
	var hc: Node = player.get("health_comp")
	if hc == null or float(hc.hp) - amount > 0.0 or count("pacto_patasola") <= 0:
		return amount
	_inventory().remove_item("pacto_patasola")
	hc.set_invincibility(PATASOLA_INVULN)
	var root := _root()
	if root:
		ToonFX.ring_burst(root, player.global_position, 8.0, PATASOLA_COLOR, 0.5)
		ToonFX.puff_burst(root, player.global_position + Vector3(0, 0.6, 0), PATASOLA_COLOR, 12, 4.0, 0.6)
	_pop(ToonFX.ITEM_FX_LEG, 1.4)
	EquipmentPickup.toast(player, "¡EL PACTO TE SALVA!", PATASOLA_COLOR)
	AudioManager.play("boss_sting", -6.0, 1.2)
	RunLog.proc("item:pacto_patasola")
	return float(hc.hp) - float(hc.max_hp) * PATASOLA_HP

func _on_level_up() -> void:
	if count("totuma_chicha") <= 0:
		return
	var hc: Node = player.get("health_comp")
	if hc == null:
		return
	player.heal(float(hc.max_hp) * TOTUMA_HEAL)
	hc.set_invincibility(TOTUMA_INVULN)
	_pop(ToonFX.ITEM_FX_HEAL, 0.9)
	RunLog.proc("item:totuma_chicha")

## Robo de vida de objetos (Sangre de Mohán), sumado al de las mejoras de arma en Player.on_damage_dealt.
func lifesteal() -> float:
	return 0.02 * float(count("sangre_mohan"))

## Multiplicador de una gema de XP al recogerla (Moneda del Duende: a veces vale el doble).
static func xp_roll() -> float:
	if _inst == null:
		return 1.0
	var n := _inst.count("moneda_duende")
	if n <= 0:
		return 1.0
	var sb = _inst.player.get("stat_block")
	var luck: float = sb.luck() if sb else 0.0
	if randf() >= DUENDE_CHANCE * float(n) + luck * 0.5:
		return 1.0
	if _inst._now() - _inst._coin_fx_t > 0.6:
		_inst._coin_fx_t = _inst._now()
		_inst._pop(ToonFX.ITEM_FX_COIN, 0.7, 2.1)
	return 2.0

func _tick_hamaca(delta: float) -> void:
	if count("hamaca_abuelo") <= 0:
		_still_t = 0.0
		return
	var v: Vector3 = player.get("velocity") if "velocity" in player else Vector3.ZERO
	if Vector2(v.x, v.z).length() > 0.3:
		_still_t = 0.0
		return
	_still_t += delta
	if hamaca_on():
		var hc: Node = player.get("health_comp")
		if hc and float(hc.hp) > 0.0 and float(hc.hp) < float(hc.max_hp):
			hc.hp = minf(float(hc.max_hp), float(hc.hp) + HAMACA_HEAL * delta)
			if _now() - _hamaca_fx_t > 2.0:
				_hamaca_fx_t = _now()
				_pop(ToonFX.ITEM_FX_HEAL, 0.5, 2.0)
			if Engine.get_process_frames() % 15 == 0:
				hc._emit_stats()

func _tick_candileja(delta: float) -> void:
	if count("ojo_candileja") <= 0:
		return
	_candileja_t += delta
	if _candileja_t < CANDILEJA_TICK:
		return
	_candileja_t = 0.0
	var near := _enemies_near(player.global_position, CANDILEJA_RADIUS)
	for e in near:
		StatusEffects.apply_to(e, "burn", CANDILEJA_DPS * _damage_mult(), 1.2, player)
	if not near.is_empty() and _now() - _candileja_fx_t > 1.2:
		_candileja_fx_t = _now()
		var root := _root()
		if root:
			ToonFX.ring_burst(root, player.global_position + Vector3(0, 0.15, 0), CANDILEJA_RADIUS * 1.2, CANDILEJA_COLOR, 0.3)
			ToonFX.flame_column(root, (near[0] as EnemyData).global_position, 0.5, CANDILEJA_COLOR)

# ───────────────────────────── Activa ─────────────────────────────

func active_id() -> String:
	var inv := _inventory()
	return inv.active_item() if inv else ""

func has_active() -> bool:
	return active_id() != ""

func cooldown_left() -> float:
	return _active_cd

func cooldown_total() -> float:
	return float(ItemDB.get_item(active_id()).get("cooldown", 1.0))

## Fracción 0..1 lista (1 = se puede usar).
func ready_fraction() -> float:
	var total := cooldown_total()
	return 1.0 if total <= 0.0 else clampf(1.0 - _active_cd / total, 0.0, 1.0)

## Usa la activa. false si no llevas ninguna o está recargando.
func use_active() -> bool:
	var id := active_id()
	if id == "" or _active_cd > 0.0:
		return false
	var root := _root()
	match id:
		"totumo_polvora":
			var at := _aim_ground()
			_blast(at, POLVORA_RADIUS, POLVORA_DAMAGE * _damage_mult(), POLVORA_FRAC, TEJO_COLOR)
			if root:
				ToonFX.flame_column(root, at, POLVORA_RADIUS * 0.6, TEJO_COLOR)
			HitFeedback.shake(0.3)
		"silbido_mohan":
			for orb in get_tree().get_nodes_in_group("xp_orbs"):
				if orb.has_method("pull_to"):
					orb.pull_to(player, MapPickup.MAGNET_SPEED)
			if root:
				ToonFX.ring_burst(root, player.global_position, 10.0, Color(0.45, 0.85, 1.0), 0.6)
			_pop(ToonFX.ITEM_FX_NOTE, 1.0)
			AudioManager.play("kill_burst", -6.0, 1.6)
		"tamal_emergencia":
			var hc: Node = player.get("health_comp")
			if hc:
				player.heal(float(hc.max_hp) * TAMAL_HEAL)
			if root:
				ToonFX.ring_burst(root, player.global_position, 3.0, Color(0.4, 1.0, 0.45), 0.4)
				ToonFX.puff_burst(root, player.global_position + Vector3(0, 0.8, 0), Color(0.5, 1.0, 0.5), 8, 2.5, 0.4)
			_pop(ToonFX.ITEM_FX_HEAL, 1.0)
			AudioManager.play("kill_burst", -6.0, 1.4)
		"trompo_guerra":
			if root:
				WarTop.spawn(root, player, TROMPO_TIME, _damage_mult())
		"machete_relampago":
			_machete_dash()
		"garrafon_aguardiente":
			_furia_until = _now() + GARRAFON_TIME
			var sb = player.get("stat_block")
			if sb:
				sb.stats_recalculated.emit()
			EquipmentPickup.toast(player, "¡FURIA!", Color(1.0, 0.45, 0.2))
			_show_anger()
			AudioManager.play("boss_sting", -8.0, 1.5)
		"campana_iglesia":
			for e in _enemies_near(player.global_position, CAMPANA_RADIUS):
				e.apply_slow(CAMPANA_FREEZE, 0.0)
			if root:
				ToonFX.ring_burst(root, player.global_position, CAMPANA_RADIUS, CAMPANA_COLOR, 0.5)
				ToonFX.ring_burst(root, player.global_position, CAMPANA_RADIUS * 0.55, Color(0.55, 0.85, 1.0), 0.35)
			_pop(ToonFX.ITEM_FX_BELL, 1.5, 2.6)
			AudioManager.play("boss_sting", -4.0, 2.2)
		_:
			return false
	_active_cd = cooldown_total()
	active_used.emit(id)
	RunLog.proc("item:" + id)
	return true

## Marca de furia (dibujo de manga) que late sobre la cabeza mientras dura el Garrafón.
func _show_anger() -> void:
	if is_instance_valid(_anger):
		_anger.queue_free()
	_anger = ToonFX.item_sprite(ToonFX.ITEM_FX_ANGER, 0.7)
	if _anger.texture == null:
		return
	player.add_child(_anger)
	_anger.position = Vector3(0.35, 2.2, 0)
	var tw := _anger.create_tween().set_loops(int(GARRAFON_TIME / 0.4))
	tw.tween_property(_anger, "scale", Vector3.ONE * 1.25, 0.1)
	tw.tween_property(_anger, "scale", Vector3.ONE, 0.3)
	var a := _anger
	get_tree().create_timer(GARRAFON_TIME).timeout.connect(func():
		if is_instance_valid(a):
			a.queue_free()
	)

## Embestida: avanza hasta MACHETE_DIST m (para en las paredes) y corta a los que hay en el camino.
func _machete_dash() -> void:
	var dir: Vector3 = player.get_attack_forward_dir() if player.has_method("get_attack_forward_dir") else -player.global_transform.basis.z
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
	var from := player.global_position
	if player is CharacterBody3D:
		(player as CharacterBody3D).move_and_collide(dir * MACHETE_DIST)
	else:
		player.global_position = from + dir * MACHETE_DIST
	var to := player.global_position
	var seg := Vector2(to.x - from.x, to.z - from.z)
	var seg_len := maxf(seg.length(), 0.01)
	_in_proc = true
	for e in _enemies_near(from.lerp(to, 0.5), seg_len * 0.5 + MACHETE_WIDTH).duplicate():
		var rel := Vector2(e.global_position.x - from.x, e.global_position.z - from.z)
		var t := clampf(rel.dot(seg) / (seg_len * seg_len), 0.0, 1.0)
		if (rel - seg * t).length() <= MACHETE_WIDTH:
			e.take_damage(MACHETE_DAMAGE * _damage_mult(), dir * 8.0)
	_in_proc = false
	var hc: Node = player.get("health_comp")
	if hc:
		hc.set_invincibility(0.4)
	var root := _root()
	if root:
		# Tajo dibujado a lo largo del recorrido (recorte plano de pie, orientado al avance)
		var slash := ToonFX.item_sprite(ToonFX.ITEM_FX_SLASH, maxf(from.distance_to(to), 2.0) * 1.2, false)
		root.add_child(slash)
		slash.global_position = from.lerp(to, 0.5) + Vector3(0, 1.0, 0)
		slash.rotation.y = atan2(-dir.z, dir.x)
		var tw := slash.create_tween()
		tw.tween_interval(0.12)
		tw.tween_property(slash, "scale:y", 0.0, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(slash.queue_free)
		ToonFX.puff_burst(root, from + Vector3(0, 0.3, 0), Color(0.85, 0.8, 0.7), 6, 2.0, 0.45)
	AudioManager.play("kill_burst", -8.0, 1.8)
	HitFeedback.shake(0.15)

## Punto del suelo al que apuntas, a POLVORA_RANGE m como mucho.
func _aim_ground() -> Vector3:
	var from := player.global_position
	var aim: Vector3 = player.get_camera_aim_point() if player.has_method("get_camera_aim_point") else Vector3.ZERO
	if aim == Vector3.ZERO:
		return from + (-player.global_transform.basis.z) * 6.0
	var off := aim - from
	off.y = 0.0
	if off.length() > POLVORA_RANGE:
		off = off.normalized() * POLVORA_RANGE
	return Vector3(from.x + off.x, from.y, from.z + off.z)
