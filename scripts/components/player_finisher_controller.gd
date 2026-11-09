class_name PlayerFinisherController
extends Node

## Remates al estilo God of War (solo mazmorra). Un enemigo con la barra de aturdimiento llena
## (DungeonGoblin.State.STUNNED) muestra "REMATE" sobre la cabeza; a menos de RANGE, el botón de
## ataque (ratón, gatillo o botón táctil) lanza el remate en lugar del golpe normal:
##  - el personaje se lanza hacia él a cámara lenta, golpea (slam si el arma lo tiene) y el
##    impacto congela la imagen con onda, chispas y temblor fuerte;
##  - los enemigos normales mueren en el acto; los jefes pierden finish_damage_frac de su vida;
##  - cura HEAL_FRACTION de la vida máxima y es invulnerable mientras dura.
## Mientras dura no se puede atacar, esquivar ni hacer parry (lo comprueba Player).

const RANGE := 3.2
const DURATION := 0.7                 ## s de juego de principio a fin
const STRIKE_AT := 0.3                ## s de juego hasta el impacto
const STAND_OFF := 1.0                ## distancia a la que se queda del enemigo (m)
const SLOWMO_SCALE := 0.4
const SLOWMO_TIME := 0.32             ## s reales de cámara lenta antes del impacto
const HEAL_FRACTION := 0.12
const RETARGET_TIME := 4.0            ## no remata dos veces al mismo (las copias en red tardan en enterarse)
const COLOR := Color(1.0, 0.82, 0.3)
const FloatingDamage = preload("res://scripts/objects/floating_damage.gd")

var player: CharacterBody3D
var _target: DungeonGoblin
var _t := -1.0
var _struck := false
var _recent: Dictionary = {}          ## enemigo -> instante (ms) de su último remate
var _prompt: Label3D

func _ready() -> void:
	player = get_parent() as CharacterBody3D
	_prompt = Label3D.new()
	_prompt.text = "REMATE"
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.no_depth_test = true
	_prompt.fixed_size = true
	_prompt.pixel_size = 0.0011
	_prompt.font_size = 30
	_prompt.outline_size = 10
	_prompt.modulate = COLOR
	_prompt.outline_modulate = Color(0.15, 0.05, 0.0)
	_prompt.top_level = true
	_prompt.visible = false
	player.add_child.call_deferred(_prompt)

func is_active() -> bool:
	return _t >= 0.0

## Enemigo que se puede rematar ahora (el más cercano a menos de RANGE), o null.
func candidate() -> DungeonGoblin:
	if GameData.game_mode != "dungeon":
		return null
	var best: DungeonGoblin = null
	var best_d := RANGE
	var now := Time.get_ticks_msec()
	for e in EnemyRegistry.all():
		var g := e as DungeonGoblin
		if g == null or not is_instance_valid(g) or not g.can_be_finished():
			continue
		if now - int(_recent.get(g, -100000)) < int(RETARGET_TIME * 1000.0):
			continue
		var d := Vector2(g.global_position.x - player.global_position.x, g.global_position.z - player.global_position.z).length()
		if d < best_d:
			best_d = d
			best = g
	return best

## Lanza el remate si hay a quién. true si empezó (el ataque normal no debe salir).
func try_finish() -> bool:
	if is_active():
		return true
	var g := candidate()
	if g == null:
		return false
	var mc = player.get("movement_controller")
	if mc and mc.is_dodging():
		return false
	_target = g
	_recent[g] = Time.get_ticks_msec()
	_t = 0.0
	_struck = false
	_prompt.visible = false
	var hc = player.get("health_comp")
	if hc and hc.has_method("set_invincibility"):
		hc.set_invincibility(DURATION + 0.4)
	var pc = player.get("parry_controller")
	if pc:
		pc.cancel()
	# Se lanza hasta quedarse a STAND_OFF del enemigo, mirándolo
	var to := g.global_position - player.global_position
	to.y = 0.0
	var dir: Vector3 = to.normalized() if to.length_squared() > 0.0001 else -player.mesh.global_transform.basis.z
	player.mesh.rotation.y = atan2(-dir.x, -dir.z)
	if mc:
		mc.face_lock_until = Time.get_ticks_msec() / 1000.0 + DURATION
		var dist := maxf(to.length() - STAND_OFF, 0.0)
		# Frenada constante (DASH_DECEL): v = √(2·a·d) recorre justo `dist`
		mc.add_dash(dir * sqrt(2.0 * PlayerMovementController.DASH_DECEL * dist))
	var ac = player.get("animation_controller")
	if ac:
		ac.cancel_action()
		if ac.can_slam():
			ac.play_slam()
		else:
			ac.play_attack()
	AudioManager.play("melee_swing", -2.0, 0.7)
	HitFeedback.slowmo(SLOWMO_TIME, SLOWMO_SCALE)
	return true

func _process(delta: float) -> void:
	if is_active():
		_t += delta
		if not _struck and _t >= STRIKE_AT:
			_struck = true
			_strike()
		if _t >= DURATION:
			_t = -1.0
			_target = null
		return
	var g := candidate()
	_prompt.visible = g != null
	if g:
		_prompt.global_position = g.global_position + Vector3(0, g.model_height + 0.75, 0)
		_prompt.scale = Vector3.ONE * (1.0 + 0.08 * sin(Time.get_ticks_msec() / 90.0))

func _strike() -> void:
	if not is_instance_valid(_target) or _target.is_dead():
		return
	var to := _target.global_position - player.global_position
	to.y = 0.0
	var dir := to.normalized() if to.length_squared() > 0.0001 else Vector3.FORWARD
	var at := _target.global_position + Vector3(0, _target.model_height * 0.55, 0)
	HitFeedback.weapon_tag = player.current_weapon() if player.has_method("current_weapon") else -1
	_target.receive_finisher(dir * 18.0)
	MetaProgress.record("finishers")
	if player.has_method("notify_equipment"):
		player.notify_equipment("finisher")
	HitFeedback.freeze(0.12)
	HitFeedback.shake(0.85)
	AudioManager.play_at("kill_burst", at, 0.0, 0.75)
	AudioManager.play_at("impact_blunt", at, 0.0, 0.5)
	if player.has_method("heal") and player.get("health_comp"):
		player.heal(player.health_comp.max_hp * (HEAL_FRACTION + DungeonRunes.finisher_heal_bonus()))
	var root := player.get_tree().current_scene
	if root == null:
		return
	NecroVFX.shockwave(root, Vector3(_target.global_position.x, _target.global_position.y + 0.05, _target.global_position.z), 3.2, COLOR)
	var s := DustVFX.sparkles(34, 0.55, 0.25, 0.08, 0.22, COLOR)
	s.one_shot = true
	s.explosiveness = 1.0
	s.initial_velocity_min = 4.0
	s.initial_velocity_max = 8.0
	s.spread = 80.0
	root.add_child(s)
	s.global_position = at
	s.emitting = true
	root.get_tree().create_timer(1.0).timeout.connect(s.queue_free)
	FloatingDamage.spawn(root, at + Vector3(0, 0.9, 0), 0.0, COLOR, true, "¡REMATE!")
