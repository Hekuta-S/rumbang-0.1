class_name WeaponAnimSets
extends RefCounted

## Animaciones por ARMA (no por personaje) para las armas sujetas con las dos manos (solo mazmorra).
## Cada juego se animó en Blender sobre un personaje de referencia; al equiparla, build() lo adapta
## al esqueleto de cualquier personaje:
##  1. Retargeting: todos son esqueletos Mixamo importados igual (mismos nombres y ejes de hueso, Y
##     arriba, mirando a +Z), así que los giros se copian tal cual; la cadera se escala por la altura y
##     el resto de huesos conserva sus propias longitudes. (No se usa la "desviación respecto al
##     reposo": los FBX exportados desde Blender guardan otra pose de reposo que el modelo original.)
##  2. El arma deja de colgar de las manos: se calcula su trayectoria en el personaje de referencia
##     (empuñadura en la mano derecha, cañón hacia la izquierda) y se guarda como pistas de un nodo
##     "ancla" (WeaponAnchor): relativa al hombro derecho ANIMADO (el ancla cuelga de un pivote que
##     sigue a ese hombro cada fotograma) y con la distancia escalada por la longitud del brazo. Las manos del personaje van al arma
##     con IK (HandIKModifier hacia RHTarget / LHTarget, hijos del ancla). El arma se escala un poco
##     con la longitud de los brazos para que la empuñadura delantera quede a su alcance.

## model/muzzle: modelo del arma (m) y boca de fuego en sus ejes. yaw_from_body: el giro horizontal
## del arma lo da el cuerpo (bazuca al hombro, escopeta) en vez de la línea entre las dos manos.
const SETS := {
	WeaponData.WeaponType.FLAME_THROWER: {
		"hold": "res://assets/models/vangry/vangry_lz_hold.fbx",
		"fire": "res://assets/models/vangry/vangry_lz_fire.fbx",
		"blast": "res://assets/models/vangry/vangry_lz_blast.fbx",
		"model": "res://assets/models/weapons/lanzallamas.glb",
		"muzzle": Vector3(0.0, 0.03, -0.86),
		"yaw_from_body": false,
	},
	WeaponData.WeaponType.SPORE_BAZOOKA: {
		"hold": "res://assets/models/bronch/bronch_bz_hold.fbx",
		"fire": "res://assets/models/bronch/bronch_bz_fire.fbx",
		"blast": "res://assets/models/bronch/bronch_bz_blast.fbx",
		"model": "res://assets/models/weapons/bazuca_esporas.glb",
		"muzzle": Vector3(0.0, 0.13, -0.66),
		"yaw_from_body": true,
	},
	WeaponData.WeaponType.TRI_SHOTGUN: {
		"hold": "res://assets/models/riva/riva_es_hold.fbx",
		"fire": "res://assets/models/riva/riva_es_fire.fbx",
		"model": "res://assets/models/weapons/escopeta_humo.glb",
		"muzzle": Vector3(0.0, 0.09, -0.74),
		"yaw_from_body": true,
	},
}
const CLIPS := ["hold", "fire", "blast"]

## Acciones de cuerpo entero por ARMA (OneShot), animadas sobre un personaje de referencia y
## adaptadas a cualquier esqueleto con el mismo retargeting (sin ancla ni IK: la mano libre o la
## lanza enganchada a la mano derecha). Los nombres son los que usan las estrategias de las armas.
const ACTION_SETS := {
	WeaponData.WeaponType.SPEAR_LANCE: {      # Mikeura: combo ligero de cuatro golpes + clavado con salto
		"attack1": "res://assets/models/mikeura/mikeura_ataque1.fbx",
		"attack2": "res://assets/models/mikeura/mikeura_ataque2.fbx",
		"attack3": "res://assets/models/mikeura/mikeura_ataque3.fbx",
		"attack4": "res://assets/models/mikeura/mikeura_ataque4.fbx",   # slash giratorio
	},
	WeaponData.WeaponType.DAGGERS: {          # Mikeura: tajo derecho, revés izquierdo, doble tajo y embestida
		"dagger1": "res://assets/models/mikeura/mikeura_daga1.fbx",
		"dagger2": "res://assets/models/mikeura/mikeura_daga2.fbx",
		"dagger3": "res://assets/models/mikeura/mikeura_daga3.fbx",
		"dagger_dash": "res://assets/models/mikeura/mikeura_daga_embestida.fbx",
	},
	WeaponData.WeaponType.MACE: {             # Mikeura: diagonal al suelo, barrido, helicóptero (fuera del combo), levantar y golpear, mazazo con salto
		"mace1": "res://assets/models/mikeura/mikeura_maza1.fbx",
		"mace2": "res://assets/models/mikeura/mikeura_maza2.fbx",
		"mace3": "res://assets/models/mikeura/mikeura_maza3.fbx",
		"mace4": "res://assets/models/mikeura/mikeura_maza4.fbx",
		"mace_slam": "res://assets/models/mikeura/mikeura_maza_suelo.fbx",
	},
	# Espadón (clips de Mixamo, esqueleto compatible: se copian los giros tal cual). "Great Sword Slash" es un
	# solo clip de 106 fotogramas con los tres tajos seguidos: se corta en los fotogramas 33 y 77. Cada
	# acción lleva su avance en "root_motion" (el cuerpo lo recorre PlayerAnimationController, los pies no
	# patinan y los jugadores remotos ven la posición de red). El ataque al correr es otro clip entero.
	WeaponData.WeaponType.GREATSWORD: {
		"gs1": {"path": "res://assets/models/greatsword/gs_slash.fbx", "from": 0, "to": 33, "root_motion": true, "leg_scale": true},
		"gs2": {"path": "res://assets/models/greatsword/gs_slash.fbx", "from": 33, "to": 77, "root_motion": true, "leg_scale": true},
		"gs3": {"path": "res://assets/models/greatsword/gs_slash.fbx", "from": 77, "to": 106, "root_motion": true, "leg_scale": true},
		"gs_run": {"path": "res://assets/models/greatsword/gs_run_attack.fbx", "root_motion": true, "leg_scale": true},
	},
	# Espada de una mano (clips de Mixamo, como el espadón): ataque1, ataque2 y el clip "combo" (106 fotogramas)
	# con dos golpes, cortado en el fotograma 40. El ataque al correr es otro clip entero. Todos con root motion.
	WeaponData.WeaponType.SWORD: {
		"sw1": {"path": "res://assets/models/sword/sw_attack1.fbx", "root_motion": true, "leg_scale": true},
		"sw2": {"path": "res://assets/models/sword/sw_attack2.fbx", "root_motion": true, "leg_scale": true},
		"sw3": {"path": "res://assets/models/sword/sw_combo.fbx", "from": 0, "to": 40, "root_motion": true, "leg_scale": true},
		"sw4": {"path": "res://assets/models/sword/sw_combo.fbx", "from": 40, "to": 106, "root_motion": true, "leg_scale": true},
		"sw_run": {"path": "res://assets/models/sword/sw_run_attack.fbx", "root_motion": true, "leg_scale": true},
	},
	# Katana (mítica): "primer golpe" (kt1) y el mismo golpe en espejo (kt2, "mirror": izquierda <-> derecha), el clip "2 golpes" cortado en el fotograma 28 (kt3, kt4),
	# el ataque al correr y el especial (clic derecho).
	WeaponData.WeaponType.KATANA: {
		"kt1": {"path": "res://assets/models/katana/kt_attack1.fbx", "root_motion": true, "leg_scale": true},
		"kt2": {"path": "res://assets/models/katana/kt_attack1.fbx", "mirror": true, "root_motion": true, "leg_scale": true},
		"kt3": {"path": "res://assets/models/katana/kt_combo.fbx", "from": 0, "to": 28, "root_motion": true, "leg_scale": true},
		"kt4": {"path": "res://assets/models/katana/kt_combo.fbx", "from": 28, "to": 98, "root_motion": true, "leg_scale": true},
		"kt_run": {"path": "res://assets/models/katana/kt_run_attack.fbx", "root_motion": true, "leg_scale": true},
		"kt_special": {"path": "res://assets/models/katana/kt_special.fbx", "root_motion": true, "leg_scale": true},
	},
	# Arco (Mixamo, pack de arco largo): tensado completo en el fotograma 0, suelta la cuerda en el 5-6 y baja el arco
	# hasta el reposo. Se reproduce por encima de las piernas si se anda (PlayerAnimationController.play_bow_shot).
	WeaponData.WeaponType.BOW: {
		"bow_shot": {"path": "res://assets/models/bow/bow_shot.fbx", "leg_scale": true},
		# Animados en Blender sobre este mismo esqueleto (blender_sources/bow_anims.blend). Combo de tres disparos:
		# 1 rápido, 2 con el arco inclinado y la mano a la espalda a por otra flecha, 3 en postura baja con
		# sobretensado y retroceso fuerte (una sola flecha potente).
		"bow_shot_1": {"path": "res://assets/models/bow/bow_shot_1.fbx", "leg_scale": true},
		"bow_shot_2": {"path": "res://assets/models/bow/bow_shot_2.fbx", "leg_scale": true},
		"bow_shot_3": {"path": "res://assets/models/bow/bow_shot_3.fbx", "leg_scale": true},
		# Cargado: encajar y tensar (0-15), sostener con temblor (15-45, se repite en bucle) y la suelta potente
		"bow_charge_draw": {"path": "res://assets/models/bow/bow_charge.fbx", "from": 0, "to": 15, "leg_scale": true},
		"bow_charge_hold": {"path": "res://assets/models/bow/bow_charge.fbx", "from": 15, "to": 45, "leg_scale": true},
		"bow_charge_release": {"path": "res://assets/models/bow/bow_charge_release.fbx", "leg_scale": true},
	},
	WeaponData.WeaponType.DUSTS: {            # Tatan: lanzamientos y polvo a la cara
		"dust1": "res://assets/models/tatan/tatan_lanzar1.fbx",
		"dust2": "res://assets/models/tatan/tatan_lanzar2.fbx",
		"dust3": "res://assets/models/tatan/tatan_lanzar3.fbx",
		"dust_heal": "res://assets/models/tatan/tatan_curar.fbx",
		"dust_speed": "res://assets/models/tatan/tatan_velocidad.fbx",
		"dust_face": "res://assets/models/tatan/tatan_cara.fbx",
	},
	WeaponData.WeaponType.SPINNING_AXE: {     # Garri: lanzar el hacha y giros de 360°
		"axe_throw": "res://assets/models/garri/garri_axe_throw.fbx",
		"axe_spin": "res://assets/models/garri/garri_axe_spin.fbx",
		"axe_spin_power": "res://assets/models/garri/garri_axe_spin_power.fbx",
	},
	WeaponData.WeaponType.SERPENTS: {         # Joel: poses de invocación del Stand
		"gesture1": "res://assets/models/joel/joel_gesto1.fbx",
		"gesture2": "res://assets/models/joel/joel_gesto2.fbx",
		"gesture3": "res://assets/models/joel/joel_gesto3.fbx",
	},
}

## Postura de torso para llevar el arma mientras se anda, corre o espera (capa "upper" de
## PlayerAnimationController, sin ancla ni IK: las manos ya agarran el arma en el clip). Bucle.
const CARRY := {
	WeaponData.WeaponType.MACE: "res://assets/models/mikeura/mikeura_maza_hombro.fbx",   # maza al hombro
	WeaponData.WeaponType.DAGGERS: "res://assets/models/mikeura/mikeura_daga_guardia.fbx", # guardia baja
}

## Locomoción propia del arma (bucles): reposo, andar, correr y paso lateral hacia la derecha (a la izquierda se
## reproduce al revés). Sustituyen a los del personaje mientras la lleva (PlayerAnimationController).
const LOCO := {
	WeaponData.WeaponType.GREATSWORD: {
		"idle": {"path": "res://assets/models/greatsword/gs_idle.fbx", "leg_scale": true},
		# Paso pesado y corto: se alarga más que el resto para no tener que acelerarlo tanto
		"walk": {"path": "res://assets/models/greatsword/gs_walk.fbx", "leg_scale": true, "stride": {"UpLeg": 1.6, "Leg": 1.2}},
		"run": {"path": "res://assets/models/greatsword/gs_run.fbx", "leg_scale": true},
		"strafe": {"path": "res://assets/models/greatsword/gs_strafe_r.fbx", "leg_scale": true},
	},
	# Espada: andar y correr con espada y escudo de Mixamo. No hay clip de reposo: se usa la guardia con la que
	# empieza ataque1 (fotogramas 0-8, casi quietos) en ida y vuelta, así el agarre del reposo (el que congela el
	# editor de agarre) es el mismo que el de los golpes.
	WeaponData.WeaponType.SWORD: {
		# 8 fotogramas en ida y vuelta duraban ~0,27 s por sentido (respiración nerviosa): se estira x7
		"idle": {"path": "res://assets/models/sword/sw_attack1.fbx", "from": 0, "to": 8, "leg_scale": true, "pingpong": true, "time_scale": 7.0},
		"walk": {"path": "res://assets/models/sword/sw_walk.fbx", "leg_scale": true},
		"run": {"path": "res://assets/models/sword/sw_run.fbx", "leg_scale": true},
		"strafe": {"path": "res://assets/models/sword/sw_strafe.fbx", "leg_scale": true},
	},
	# Arco: reposo, andar en las cuatro direcciones con el arco listo. Sin carrera propia: al correr (tras un rato sin
	# combatir, PlayerMovementController.GAITS) se usa la del personaje. "strafe_l" y "back" son opcionales: si un
	# arma los trae, el paso a la izquierda y el retroceso usan su clip en vez de reproducir otro al revés.
	# Katana: la guardia y la locomoción del espadón
	WeaponData.WeaponType.KATANA: {
		"idle": {"path": "res://assets/models/greatsword/gs_idle.fbx", "leg_scale": true},
		"walk": {"path": "res://assets/models/greatsword/gs_walk.fbx", "leg_scale": true, "stride": {"UpLeg": 1.6, "Leg": 1.2}},
		"run": {"path": "res://assets/models/greatsword/gs_run.fbx", "leg_scale": true},
		"strafe": {"path": "res://assets/models/greatsword/gs_strafe_r.fbx", "leg_scale": true},
	},
	WeaponData.WeaponType.BOW: {
		"idle": {"path": "res://assets/models/bow/bow_idle.fbx", "leg_scale": true},
		"walk": {"path": "res://assets/models/bow/bow_walk.fbx", "leg_scale": true},
		"strafe": {"path": "res://assets/models/bow/bow_walk_r.fbx", "leg_scale": true},
		"strafe_l": {"path": "res://assets/models/bow/bow_walk_l.fbx", "leg_scale": true},
		"back": {"path": "res://assets/models/bow/bow_walk_back.fbx", "leg_scale": true},
	},
}

## Alarga (k > 1) o acorta el clip en el tiempo, multiplicando la hora de cada key. Para bucles de
## locomoción, donde el nodo del AnimationTree no tiene velocidad propia.
static func stretch_time(anim: Animation, k: float) -> void:
	if anim == null or k <= 0.0 or is_equal_approx(k, 1.0):
		return
	for i in anim.get_track_count():
		var n := anim.track_get_key_count(i)
		# Al alargar se recorre de la última a la primera para que ninguna key adelante a la siguiente
		var order: Array = range(n - 1, -1, -1) if k > 1.0 else range(n)
		for kk in order:
			anim.track_set_key_time(i, kk, anim.track_get_key_time(i, kk) * k)
	anim.length *= k

static func has_loco(weapon_type: int) -> bool:
	return LOCO.has(weapon_type)

## Clips de locomoción del arma adaptados al esqueleto `dst`: {"idle", "walk", "run", "strafe": Animation} en bucle.
static func build_loco(weapon_type: int, dst: Skeleton3D, skel_path: NodePath) -> Dictionary:
	var specs: Dictionary = LOCO.get(weapon_type, {})
	var out: Dictionary = _build_actions_from(specs, dst, skel_path)
	for clip in out:
		var spec: Variant = specs.get(clip)
		var pingpong: bool = spec is Dictionary and bool((spec as Dictionary).get("pingpong", false))
		(out[clip] as Animation).loop_mode = Animation.LOOP_PINGPONG if pingpong else Animation.LOOP_LINEAR
		if spec is Dictionary and (spec as Dictionary).has("time_scale"):
			stretch_time(out[clip] as Animation, float((spec as Dictionary)["time_scale"]))
		var widen: Variant = (spec as Dictionary).get("stride", STRIDE_WIDEN.get(clip)) if spec is Dictionary else STRIDE_WIDEN.get(clip)
		if widen is Dictionary:
			widen_stride(out[clip] as Animation, widen)
	return out

## Zancada más larga: amplía el balanceo de los muslos (y algo el de las rodillas) alrededor de su giro medio
## en el clip. Los clips de Mixamo dan pasos cortos para la velocidad del juego; para no patinar había que
## reproducirlos muy acelerados (cadencia de 4-6 pasos/s, se veía embalado). Con más zancada el pie apoyado
## recorre más por ciclo y la velocidad de reproducción necesaria baja.
## Por clip: {hueso: factor}. Al correr se amplía más (es donde más falta zancada).
const STRIDE_WIDEN := {
	"walk": {"UpLeg": 1.3, "Leg": 1.12},
	"run": {"UpLeg": 1.45, "Leg": 1.15},
	"fast": {"UpLeg": 1.45, "Leg": 1.15},
}

static func widen_stride(anim: Animation, widen: Dictionary) -> void:
	if anim == null or anim.has_meta("stride_widened"):
		return
	anim.set_meta("stride_widened", true)
	for i in anim.get_track_count():
		if anim.track_get_type(i) != Animation.TYPE_ROTATION_3D:
			continue
		var bone := String(anim.track_get_path(i).get_concatenated_subnames()).trim_prefix("mixamorig_")
		var side := bone.trim_prefix("Left").trim_prefix("Right")
		if side == bone or not widen.has(side):
			continue
		var k: float = widen[side]
		var n := anim.track_get_key_count(i)
		if n < 2:
			continue
		# Giro medio del muslo en el ciclo (cuaterniones en el mismo hemisferio)
		var first: Quaternion = anim.track_get_key_value(i, 0)
		var acc := Vector4.ZERO
		for j in n:
			var q: Quaternion = anim.track_get_key_value(i, j)
			if q.dot(first) < 0.0:
				q = -q
			acc += Vector4(q.x, q.y, q.z, q.w)
		acc = acc.normalized()
		var mean := Quaternion(acc.x, acc.y, acc.z, acc.w)
		for j in n:
			var q: Quaternion = anim.track_get_key_value(i, j)
			var d := (mean.inverse() * q).normalized()
			if d.w < 0.0:
				d = -d
			var angle := d.get_angle()
			if angle < 0.0001:
				continue
			anim.track_set_key_value(i, j, (mean * Quaternion(d.get_axis().normalized(), angle * k)).normalized())

static func has_carry(weapon_type: int) -> bool:
	return CARRY.has(weapon_type)

## Postura de transporte del arma adaptada al esqueleto `dst` (o null).
static func build_carry(weapon_type: int, dst: Skeleton3D, skel_path: NodePath) -> Animation:
	if not CARRY.has(weapon_type):
		return null
	var anim: Animation = _build_actions_from({"carry": CARRY[weapon_type]}, dst, skel_path).get("carry")
	if anim:
		anim.loop_mode = Animation.LOOP_LINEAR
	return anim

## Acciones comunes a todos los personajes, sea cual sea el arma: guardia del parry y voltereta de
## la esquiva. Animadas sobre Mikeura y adaptadas igual que las de las armas.
const COMMON_ACTIONS := {
	"parry": "res://assets/models/mikeura/mikeura_parry.fbx",
	"roll": "res://assets/models/mikeura/mikeura_roll.fbx",
}

static func has_actions(weapon_type: int) -> bool:
	return ACTION_SETS.has(weapon_type)

## Acciones del arma adaptadas al esqueleto `dst`: {nombre: Animation}.
static func build_actions(weapon_type: int, dst: Skeleton3D, skel_path: NodePath) -> Dictionary:
	return _build_actions_from(ACTION_SETS.get(weapon_type, {}), dst, skel_path)

## Acciones comunes (COMMON_ACTIONS) adaptadas al esqueleto `dst`.
static func build_common_actions(dst: Skeleton3D, skel_path: NodePath) -> Dictionary:
	return _build_actions_from(COMMON_ACTIONS, dst, skel_path)

static func _build_actions_from(paths: Dictionary, dst: Skeleton3D, skel_path: NodePath) -> Dictionary:
	var out := {}
	for action_name in paths:
		# Cada entrada es la ruta del FBX, o {"path", ["from", "to" (fotogramas a 30 fps)], ["root_motion"]}
		var spec: Variant = paths[action_name]
		var scene := load(spec["path"] if spec is Dictionary else String(spec)) as PackedScene
		if scene == null:
			continue
		var inst := scene.instantiate()
		var src := _find(inst, "Skeleton3D") as Skeleton3D
		var ap := _find(inst, "AnimationPlayer") as AnimationPlayer
		if src != null and ap != null and not ap.get_animation_list().is_empty():
			var anim: Animation = ap.get_animation(ap.get_animation_list()[0]).duplicate(true)
			if spec is Dictionary and spec.has("from"):
				slice_animation(anim, float(spec["from"]) / SAMPLE_FPS, float(spec["to"]) / SAMPLE_FPS)
			if spec is Dictionary and spec.get("reverse", false):
				reverse_animation(anim)
			if spec is Dictionary and spec.get("mirror", false):
				mirror_animation(anim, src)
			_retarget_bones(anim, src, dst, skel_path, spec is Dictionary and spec.get("leg_scale", false))
			if spec is Dictionary and spec.get("root_motion", false):
				extract_root_motion(anim, skel_path)
			anim.loop_mode = Animation.LOOP_NONE
			out[action_name] = anim
		inst.free()
	return out

## Se queda con el tramo [t0, t1] de la animación (en segundos): las claves de los cortes se interpolan para que
## el primer y el último fotograma sean exactamente los de esos instantes, y el tiempo vuelve a empezar en 0.
static func slice_animation(anim: Animation, t0: float, t1: float) -> void:
	for i in anim.get_track_count():
		var type := anim.track_get_type(i)
		if not type in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D]:
			continue
		var first: Variant
		var last: Variant
		match type:
			Animation.TYPE_POSITION_3D:
				first = anim.position_track_interpolate(i, t0)
				last = anim.position_track_interpolate(i, t1)
			Animation.TYPE_ROTATION_3D:
				first = anim.rotation_track_interpolate(i, t0)
				last = anim.rotation_track_interpolate(i, t1)
			_:
				first = anim.scale_track_interpolate(i, t0)
				last = anim.scale_track_interpolate(i, t1)
		var inner: Array = []
		for k in anim.track_get_key_count(i):
			var t := anim.track_get_key_time(i, k)
			if t > t0 + 0.0001 and t < t1 - 0.0001:
				inner.append([t - t0, anim.track_get_key_value(i, k)])
		for k in range(anim.track_get_key_count(i) - 1, -1, -1):
			anim.track_remove_key(i, k)
		anim.track_insert_key(i, 0.0, first)
		for kv in inner:
			anim.track_insert_key(i, float(kv[0]), kv[1])
		anim.track_insert_key(i, t1 - t0, last)
	anim.length = t1 - t0

## Invierte la animación en el tiempo (la key en t pasa a length - t). Antes de _retarget_bones / root motion: el
## avance de la cadera también se invierte, así que el golpe al revés retrocede lo que el original avanzaba.
static func reverse_animation(anim: Animation) -> void:
	var length := anim.length
	for i in anim.get_track_count():
		var n := anim.track_get_key_count(i)
		if n == 0:
			continue
		var keys: Array = []
		for k in n:
			keys.append([length - anim.track_get_key_time(i, k), anim.track_get_key_value(i, k)])
		for k in range(n - 1, -1, -1):
			anim.track_remove_key(i, k)
		for kv in keys:
			anim.track_insert_key(i, maxf(float(kv[0]), 0.0), kv[1])

## Refleja la animación en espejo (izquierda <-> derecha, plano X = 0 del esqueleto de origen). Antes de
## _retarget_bones. Cada hueso toma el movimiento de su gemelo del otro lado reflejado, medido como desviación
## respecto al reposo, así no hace falta que los ejes locales de los huesos izquierdos y derechos sean simétricos.
static func mirror_animation(anim: Animation, src: Skeleton3D) -> void:
	var tracks := _bone_tracks(anim, src)
	var m := Basis.from_scale(Vector3(-1, 1, 1))
	var n := src.get_bone_count()
	var twin: Array[int] = []
	for b in n:
		var nm := src.get_bone_name(b)
		var other := nm.replace("Left", "@").replace("Right", "Left").replace("@", "Right")
		var t := src.find_bone(other)
		twin.append(t if t >= 0 else b)
	# Pistas de rotación que faltan en un gemelo (el original las tiene en el otro lado)
	for b in n:
		var tb: Dictionary = tracks.get(b, {})
		var tw: int = twin[b]
		if tb.has(Animation.TYPE_ROTATION_3D) and not (tracks.get(tw, {}) as Dictionary).has(Animation.TYPE_ROTATION_3D):
			var path := String(anim.track_get_path(tb[Animation.TYPE_ROTATION_3D]))
			var i := anim.add_track(Animation.TYPE_ROTATION_3D)
			anim.track_set_path(i, NodePath(path.get_slice(":", 0) + ":" + src.get_bone_name(tw)))
			anim.track_insert_key(i, 0.0, src.get_bone_rest(tw).basis.get_rotation_quaternion())
	tracks = _bone_tracks(anim, src)
	var rest_g: Array[Basis] = []
	var rest_cache := {}
	for b in n:
		rest_g.append(_global_pose(src, b, anim, {}, 0.0, rest_cache).basis.orthonormalized())
	var frames := maxi(int(round(anim.length * SAMPLE_FPS)), 1)
	var rot_keys := {}   # bone -> [[t, quat]]
	var pos_keys := {}
	for f in frames + 1:
		var t := minf(float(f) / SAMPLE_FPS, anim.length)
		var cache := {}
		var mg: Array[Transform3D] = []
		mg.resize(n)
		# Pose global reflejada de cada hueso, a partir de la de su gemelo
		for b in n:
			var tw: int = twin[b]
			var g := _global_pose(src, tw, anim, tracks, t, cache)
			var gb := g.basis.orthonormalized()
			var basis := (m * gb * m) * (m * rest_g[tw] * m).inverse() * rest_g[b]
			mg[b] = Transform3D(basis, m * g.origin)
		for b in n:
			var tr: Dictionary = tracks.get(b, {})
			if tr.is_empty():
				continue
			var parent := src.get_bone_parent(b)
			var local := mg[b] if parent < 0 else Transform3D(mg[parent].basis, mg[parent].origin).affine_inverse() * mg[b]
			if tr.has(Animation.TYPE_ROTATION_3D):
				if not rot_keys.has(b):
					rot_keys[b] = []
				rot_keys[b].append([t, local.basis.orthonormalized().get_rotation_quaternion()])
			if tr.has(Animation.TYPE_POSITION_3D) and parent < 0:
				if not pos_keys.has(b):
					pos_keys[b] = []
				# Escala del hueso raíz respecto al esqueleto: se conserva la del original
				var orig: Vector3 = anim.position_track_interpolate(tr[Animation.TYPE_POSITION_3D], t)
				pos_keys[b].append([t, Vector3(-orig.x, orig.y, orig.z)])
	for b in rot_keys:
		var i: int = tracks[b][Animation.TYPE_ROTATION_3D]
		for k in range(anim.track_get_key_count(i) - 1, -1, -1):
			anim.track_remove_key(i, k)
		for kv in rot_keys[b]:
			anim.track_insert_key(i, float(kv[0]), kv[1])
	for b in pos_keys:
		var i: int = tracks[b][Animation.TYPE_POSITION_3D]
		for k in range(anim.track_get_key_count(i) - 1, -1, -1):
			anim.track_remove_key(i, k)
		for kv in pos_keys[b]:
			anim.track_insert_key(i, float(kv[0]), kv[1])

## Saca el avance de la cadera (X, Z del esqueleto) de la animación: la pista queda quieta en horizontal (la
## altura se conserva) y el recorrido se guarda en el meta "root_motion" como {"fps", "pts": PackedVector2Array
## con el desplazamiento acumulado fotograma a fotograma, en unidades del esqueleto}. Hay que llamarla DESPUÉS de
## _retarget_bones (la pista ya está en la escala del personaje y apunta a `skel_path`).
static func extract_root_motion(anim: Animation, skel_path: NodePath) -> void:
	var track := anim.find_track(NodePath(str(skel_path) + ":" + HIPS), Animation.TYPE_POSITION_3D)
	if track < 0:
		return
	var n := maxi(int(ceil(anim.length * SAMPLE_FPS)), 1)
	var base: Vector3 = anim.position_track_interpolate(track, 0.0)
	var pts := PackedVector2Array()
	for s in range(n + 1):
		var p: Vector3 = anim.position_track_interpolate(track, minf(float(s) / SAMPLE_FPS, anim.length))
		pts.append(Vector2(p.x - base.x, p.z - base.z))
	for k in anim.track_get_key_count(track):
		var v: Vector3 = anim.track_get_key_value(track, k)
		anim.track_set_key_value(track, k, Vector3(0.0, v.y, 0.0))
	anim.set_meta("root_motion", {"fps": SAMPLE_FPS, "pts": pts})
const SAMPLE_FPS := 30.0
const RH := "mixamorig_RightHand"
const RH_MID := "mixamorig_RightHandMiddle1"
const LH := "mixamorig_LeftHand"
const HIPS := "mixamorig_Hips"
const R_SHOULDER := "mixamorig_RightArm"
const WEAPON_SCALE_MIN := 0.65
const WEAPON_SCALE_MAX := 1.2

static func supports(weapon_type: int) -> bool:
	return SETS.has(weapon_type)

## Todos los archivos de un arma (para precargarlos con el personaje).
static func asset_paths(weapon_type: int) -> Array[String]:
	var out: Array[String] = []
	if SETS.has(weapon_type):
		for key in CLIPS + ["model"]:
			if SETS[weapon_type].has(key):
				out.append(SETS[weapon_type][key])
	for action_name in ACTION_SETS.get(weapon_type, {}):
		var spec: Variant = ACTION_SETS[weapon_type][action_name]
		var file: String = spec["path"] if spec is Dictionary else String(spec)
		if not out.has(file):
			out.append(file)
	if CARRY.has(weapon_type):
		out.append(CARRY[weapon_type])
	for loco_name in LOCO.get(weapon_type, {}):
		out.append(LOCO[weapon_type][loco_name]["path"])
	return out

## Construye las animaciones del arma para el esqueleto `dst`. Las rutas son relativas al nodo raíz
## del AnimationPlayer. Devuelve {"hold": Animation, "fire": Animation, ["blast": Animation],
## "weapon_scale": float (tamaño del arma respecto a su modelo en metros)}.
static func build(weapon_type: int, dst: Skeleton3D, skel_path: NodePath, anchor_path: NodePath,
		rh_path: NodePath, lh_path: NodePath) -> Dictionary:
	var out := {}
	if not SETS.has(weapon_type):
		return out
	var cfg: Dictionary = SETS[weapon_type]
	var dst_world_scale := dst.global_transform.basis.get_scale().x
	out["weapon_scale"] = 1.0
	for clip in CLIPS:
		if not cfg.has(clip):
			continue
		var scene := load(cfg[clip]) as PackedScene
		if scene == null:
			continue
		var inst := scene.instantiate()
		var src := _find(inst, "Skeleton3D") as Skeleton3D
		var ap := _find(inst, "AnimationPlayer") as AnimationPlayer
		if src == null or ap == null or ap.get_animation_list().is_empty():
			inst.free()
			continue
		var anim: Animation = ap.get_animation(ap.get_animation_list()[0]).duplicate(true)
		var src_world_scale := _source_world_scale(inst, src)
		var k_arm := _arm_length(dst) / maxf(_arm_length(src), 0.000001)
		# Tamaño del arma: proporcional al brazo (en el mundo), sin pasarse
		out["weapon_scale"] = clampf(_arm_length(dst) * dst_world_scale / maxf(_arm_length(src) * src_world_scale, 0.000001), WEAPON_SCALE_MIN, WEAPON_SCALE_MAX)
		# Las piezas del arma (empuñaduras) se escalan igual que el arma, en unidades del destino
		var hand_k: float = out["weapon_scale"] * src_world_scale / maxf(dst_world_scale, 0.000001)
		_add_weapon_tracks(anim, src, dst, cfg.get("yaw_from_body", false), k_arm, hand_k,
			anchor_path, rh_path, lh_path)
		_retarget_bones(anim, src, dst, skel_path)
		anim.loop_mode = Animation.LOOP_NONE if clip == "blast" else Animation.LOOP_LINEAR
		out[clip] = anim
		inst.free()
	return out

# ───────────────────────────── Retargeting de huesos ─────────────────────────────

## leg_scale: la cadera se escala por el largo de las piernas en vez de por la altura cadera-cabeza. Para clips
## de Mixamo, cuya cadera va a la altura de SUS piernas: con otras proporciones (torso más largo) flotarían.
static func _retarget_bones(anim: Animation, src: Skeleton3D, dst: Skeleton3D, skel_path: NodePath, leg_scale: bool = false) -> void:
	var k := _leg_length(dst) / maxf(_leg_length(src), 0.0001) if leg_scale else _height(dst) / maxf(_height(src), 0.0001)
	for i in range(anim.get_track_count() - 1, -1, -1):
		var path := anim.track_get_path(i)
		var bone := path.get_concatenated_subnames()
		if bone == "":
			continue     # pistas de nodos (ancla del arma): ya están en su sitio
		var sb := src.find_bone(bone)
		var db := dst.find_bone(bone)
		if sb < 0 or db < 0:
			anim.remove_track(i)   # huesos que este personaje no tiene (p. ej. dedos)
			continue
		anim.track_set_path(i, NodePath(str(skel_path) + ":" + bone))
		match anim.track_get_type(i):
			Animation.TYPE_POSITION_3D:
				var d_o := dst.get_bone_rest(db).origin
				for key in anim.track_get_key_count(i):
					if bone == HIPS:
						# Altura absoluta (los esqueletos tienen el origen en los pies) escalada por la
						# altura del personaje. No se resta el reposo: el de los FBX exportados desde
						# Blender no coincide con el del modelo original y hundía al personaje.
						var v: Vector3 = anim.track_get_key_value(i, key)
						anim.track_set_key_value(i, key, v * k)
					else:
						anim.track_set_key_value(i, key, d_o)
			Animation.TYPE_SCALE_3D:
				anim.remove_track(i)

# ───────────────────────────── Trayectoria del arma ─────────────────────────────

## Pistas del ancla (posición/giro de la empuñadura en espacio del esqueleto) y de los objetivos
## de las manos (en ejes del ancla), muestreadas sobre el personaje de referencia.
static func _add_weapon_tracks(anim: Animation, src: Skeleton3D, dst: Skeleton3D, yaw_from_body: bool,
		k_arm: float, hand_k: float, anchor_path: NodePath, rh_path: NodePath, lh_path: NodePath) -> void:
	var tracks := _bone_tracks(anim, src)
	var rh := src.find_bone(RH)
	var mid := src.find_bone(RH_MID)
	var lh := src.find_bone(LH)
	if rh < 0 or lh < 0:
		return
	# La empuñadura se separa del hombro derecho según la longitud del brazo
	var sh := src.find_bone(R_SHOULDER)
	var body_fwd := Vector3(0.0, 0.0, 1.0)   # los personajes miran a +Z en espacio del esqueleto
	var t_anchor_p := anim.add_track(Animation.TYPE_POSITION_3D)
	anim.track_set_path(t_anchor_p, anchor_path)
	var t_anchor_r := anim.add_track(Animation.TYPE_ROTATION_3D)
	anim.track_set_path(t_anchor_r, anchor_path)
	var t_rh := anim.add_track(Animation.TYPE_POSITION_3D)
	anim.track_set_path(t_rh, rh_path)
	var t_lh := anim.add_track(Animation.TYPE_POSITION_3D)
	anim.track_set_path(t_lh, lh_path)
	var n := maxi(int(ceil(anim.length * SAMPLE_FPS)), 1)
	for s in range(n + 1):
		var t := minf(float(s) / SAMPLE_FPS, anim.length)
		var cache := {}
		var p_rh := _global_pose(src, rh, anim, tracks, t, cache).origin
		var p_mid := _global_pose(src, mid, anim, tracks, t, cache).origin if mid >= 0 else p_rh
		var p_lh := _global_pose(src, lh, anim, tracks, t, cache).origin
		var grip := p_rh.lerp(p_mid, 0.5)
		var fwd := p_lh - grip
		if fwd.length_squared() < 0.000001:
			fwd = body_fwd
		fwd = fwd.normalized()
		if yaw_from_body:
			var flat := Vector2(fwd.x, fwd.z).length()
			var bf := Vector3(body_fwd.x, 0.0, body_fwd.z).normalized()
			fwd = (bf * flat + Vector3(0.0, fwd.y, 0.0)).normalized()
		var up := Vector3.UP if absf(fwd.dot(Vector3.UP)) < 0.98 else Vector3.FORWARD
		var basis := Basis.looking_at(fwd, up)
		# Al destino: posición del ancla respecto al hombro, mismo giro
		var sh_t := _global_pose(src, sh, anim, tracks, t, cache).origin
		anim.position_track_insert_key(t_anchor_p, t, (grip - sh_t) * k_arm)
		anim.rotation_track_insert_key(t_anchor_r, t, basis.get_rotation_quaternion())
		# Manos en ejes del arma (no dependen de los ejes del esqueleto), en metros → unidades destino
		anim.position_track_insert_key(t_rh, t, basis.inverse() * (p_rh - grip) * hand_k)
		anim.position_track_insert_key(t_lh, t, basis.inverse() * (p_lh - grip) * hand_k)

## {hueso: {tipo: índice de pista}} de las pistas de huesos del esqueleto fuente.
static func _bone_tracks(anim: Animation, src: Skeleton3D) -> Dictionary:
	var out := {}
	for i in anim.get_track_count():
		var bone := anim.track_get_path(i).get_concatenated_subnames()
		var b := src.find_bone(bone)
		if b < 0:
			continue
		if not out.has(b):
			out[b] = {}
		out[b][anim.track_get_type(i)] = i
	return out

## Pose global (espacio del esqueleto) del hueso en el instante t, a partir de las pistas.
static func _global_pose(skel: Skeleton3D, bone: int, anim: Animation, tracks: Dictionary, t: float, cache: Dictionary) -> Transform3D:
	if cache.has(bone):
		return cache[bone]
	var rest := skel.get_bone_rest(bone)
	var pos := rest.origin
	var rot := rest.basis.get_rotation_quaternion()
	var scl := rest.basis.get_scale()
	var tr: Dictionary = tracks.get(bone, {})
	if tr.has(Animation.TYPE_POSITION_3D):
		pos = anim.position_track_interpolate(tr[Animation.TYPE_POSITION_3D], t)
	if tr.has(Animation.TYPE_ROTATION_3D):
		rot = anim.rotation_track_interpolate(tr[Animation.TYPE_ROTATION_3D], t)
	if tr.has(Animation.TYPE_SCALE_3D):
		scl = anim.scale_track_interpolate(tr[Animation.TYPE_SCALE_3D], t)
	var local := Transform3D(Basis(rot).scaled(scl), pos)
	var parent := skel.get_bone_parent(bone)
	var g := local if parent < 0 else _global_pose(skel, parent, anim, tracks, t, cache) * local
	cache[bone] = g
	return g

# ───────────────────────────── Medidas del esqueleto ─────────────────────────────

## Ejes del personaje en espacio del esqueleto (derecha, arriba, atrás). Todos miran a +Z con Y arriba;
## el lado se toma de los hombros del reposo solo para saber hacia dónde queda la derecha.
static func _frame(skel: Skeleton3D) -> Basis:
	var right := _rest_pos(skel, "mixamorig_RightArm") - _rest_pos(skel, "mixamorig_LeftArm")
	var side := 1.0 if right.x >= 0.0 else -1.0
	return Basis(Vector3(side, 0, 0), Vector3.UP, Vector3(0, 0, -1) if side > 0.0 else Vector3(0, 0, -1))

## Largo del brazo derecho (hombro → muñeca, unidades del esqueleto).
static func _arm_length(skel: Skeleton3D) -> float:
	var fa := skel.find_bone("mixamorig_RightForeArm")
	var ha := skel.find_bone(RH)
	if fa < 0 or ha < 0:
		return 0.0001
	return skel.get_bone_rest(fa).origin.length() + skel.get_bone_rest(ha).origin.length()

## Largo de la pierna: de la cadera al tobillo (unidades del esqueleto).
static func _leg_length(skel: Skeleton3D) -> float:
	return maxf(_rest_pos(skel, HIPS).y - _rest_pos(skel, "mixamorig_LeftFoot").y, 0.0001)

## Altura de la cadera a la coronilla (unidades del esqueleto).
static func _height(skel: Skeleton3D) -> float:
	var top := skel.find_bone("mixamorig_HeadTop_End")
	var b := top if top >= 0 else skel.find_bone("mixamorig_Head")
	return maxf(_rest_pos(skel, skel.get_bone_name(b)).y - _rest_pos(skel, HIPS).y, 0.0001)

static func _rest_pos(skel: Skeleton3D, bone: String) -> Vector3:
	var b := skel.find_bone(bone)
	return skel.get_bone_global_rest(b).origin if b >= 0 else Vector3.ZERO

## Escala con la que el juego dibuja al personaje de referencia (como _fit_model: 1.62 m de alto).
static func _source_world_scale(inst: Node, src: Skeleton3D) -> float:
	var mi := _find(inst, "MeshInstance3D") as MeshInstance3D
	if mi == null or mi.mesh == null:
		return 1.0
	var h := maxf(mi.mesh.get_aabb().size.y, 0.001)
	# Escala acumulada desde la raíz del FBX hasta el esqueleto (nodos intermedios incluidos)
	var chain := 1.0
	var n: Node = src
	while n != null and n != inst:
		if n is Node3D:
			chain *= (n as Node3D).transform.basis.get_scale().x
		n = n.get_parent()
	return (1.62 / h) * chain

static func _find(n: Node, cls: String) -> Node:
	if n.is_class(cls):
		return n
	for c in n.get_children():
		var r := _find(c, cls)
		if r:
			return r
	return null
