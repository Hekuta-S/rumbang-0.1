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
	WeaponData.WeaponType.SPEAR_LANCE: {      # Mikeura: combo de tres golpes
		"attack1": "res://assets/models/mikeura/mikeura_ataque1.fbx",
		"attack2": "res://assets/models/mikeura/mikeura_ataque2.fbx",
		"attack3": "res://assets/models/mikeura/mikeura_ataque3.fbx",
	},
	WeaponData.WeaponType.DUSTS: {            # Tatan: lanzamientos y polvo a la cara
		"dust1": "res://assets/models/tatan/tatan_lanzar1.fbx",
		"dust2": "res://assets/models/tatan/tatan_lanzar2.fbx",
		"dust3": "res://assets/models/tatan/tatan_lanzar3.fbx",
		"dust_heal": "res://assets/models/tatan/tatan_curar.fbx",
		"dust_speed": "res://assets/models/tatan/tatan_velocidad.fbx",
		"dust_face": "res://assets/models/tatan/tatan_cara.fbx",
	},
	WeaponData.WeaponType.SERPENTS: {         # Joel: poses de invocación del Stand
		"gesture1": "res://assets/models/joel/joel_gesto1.fbx",
		"gesture2": "res://assets/models/joel/joel_gesto2.fbx",
		"gesture3": "res://assets/models/joel/joel_gesto3.fbx",
	},
}

static func has_actions(weapon_type: int) -> bool:
	return ACTION_SETS.has(weapon_type)

## Acciones del arma adaptadas al esqueleto `dst`: {nombre: Animation}.
static func build_actions(weapon_type: int, dst: Skeleton3D, skel_path: NodePath) -> Dictionary:
	var out := {}
	for action_name in ACTION_SETS.get(weapon_type, {}):
		var scene := load(ACTION_SETS[weapon_type][action_name]) as PackedScene
		if scene == null:
			continue
		var inst := scene.instantiate()
		var src := _find(inst, "Skeleton3D") as Skeleton3D
		var ap := _find(inst, "AnimationPlayer") as AnimationPlayer
		if src != null and ap != null and not ap.get_animation_list().is_empty():
			var anim: Animation = ap.get_animation(ap.get_animation_list()[0]).duplicate(true)
			_retarget_bones(anim, src, dst, skel_path)
			anim.loop_mode = Animation.LOOP_NONE
			out[action_name] = anim
		inst.free()
	return out
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
		out.append(ACTION_SETS[weapon_type][action_name])
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

static func _retarget_bones(anim: Animation, src: Skeleton3D, dst: Skeleton3D, skel_path: NodePath) -> void:
	var k := _height(dst) / maxf(_height(src), 0.0001)
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
