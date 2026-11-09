# Clips de Mikeura para las Dagas Gemelas y la Maza Rúnica (escena Mikeura_Anims de rumbang_anims.blend).
# Ejecutar dentro de Blender: usa el texto `anim_lib` del .blend (apply_pose) y exporta cada clip a
# assets/models/mikeura/mikeura_<clip>.fbx con el formato de los demás clips de ataque.
# Estilo: exagerado a propósito (preparaciones enormes, giros de 360°, saltos), no realista.
#
# Cada fotograma clave = (frame, spec, cadera, apuntados[, giro]):
#  - spec: giros de apply_pose para columna y piernas (grados sobre ejes del MUNDO: Mikeura mira a -Y, su
#    derecha es -X, arriba +Z; z+ gira el torso a la izquierda, x+ lo inclina hacia delante; pierna
#    flexionada = UpLeg x-, Leg x+).
#  - cadera: desplazamiento en metros reales (z+ = salto).
#  - apuntados: hacia dónde apunta cada segmento del brazo, en ejes del personaje F(delante, derecha,
#    arriba). "RightArm"/"RightForeArm" orientan el hueso; "RightBlade" gira la mano para que la hoja (o el
#    mango de la maza, hacia la cabeza) apunte ahí. Con "TwoHand" la mano izquierda agarra el mango de la
#    maza MACE_LEFT_GRIP m por debajo de la derecha (IK de dos huesos).
#  - giro: el cuerpo entero gira estos grados (z+ = a la izquierda) y los apuntados giran con él. Para un
#    giro completo hacen falta claves cada <= 120° (los cuaterniones se mantienen continuos al insertarlos).
# Las ventanas de golpe de PlayerAnimationController.ATTACK_WINDOWS están en segundos de estos clips (30 fps).
import bpy, math, os
from mathutils import Matrix, Vector

ROOT = os.path.dirname(os.path.dirname(bpy.data.filepath))
OUT = os.path.join(ROOT, "assets", "models", "mikeura")

## En el .blend Mikeura mide 1 unidad de armadura; en el juego, 1,62 m (_fit_model). Las medidas del juego
## (agarre, largo del mango) se pasan a unidades de armadura con GAME_M.
GAME_M = 1.0 / 1.62
## Dirección de la hoja en ejes del hueso de cada mano (la misma que usa el juego para colgar el arma:
## PlayerWeaponVisuals.MELEE_BLADE_DIR) y punto de agarre en la palma (MELEE_GRIP_OFFSET).
BLADE_LOCAL = {"Right": Vector((0.5, 0.0, -0.87)).normalized(), "Left": Vector((-0.5, 0.0, -0.87)).normalized()}
GRIP_LOCAL = Vector((0.0, 0.08, 0.02)) * GAME_M
MACE_LEFT_GRIP = -0.34 * GAME_M   ## la mano izquierda, 34 cm (del juego) por debajo de la derecha en el mango
LEFT_ELBOW_POLE = (0.0, -0.6, -0.8)


def F(fwd, right, up):
    return Vector((-right, -fwd, up)).normalized()


def _swap(name):
    if name.startswith("Right"):
        return "Left" + name[len("Right"):]
    if name.startswith("Left"):
        return "Right" + name[len("Left"):]
    return name


def mirror(aims):
    """Mismos apuntados con los lados cambiados (derecha <-> izquierda)."""
    return {_swap(k): (Vector((-v.x, v.y, v.z)) if isinstance(v, Vector) else v) for k, v in aims.items()}


def both(right_aims):
    out = dict(right_aims)
    out.update(mirror(right_aims))
    return out


def legs(kind):
    return {
        "ready": {"RightUpLeg": [("x", -18)], "RightLeg": [("x", 28)], "LeftUpLeg": [("x", -10)], "LeftLeg": [("x", 22)]},
        "wide": {"RightUpLeg": [("x", -25), ("y", 15)], "RightLeg": [("x", 40)], "LeftUpLeg": [("x", -15), ("y", -15)], "LeftLeg": [("x", 35)]},
        "lunge": {"RightUpLeg": [("x", -55)], "RightLeg": [("x", 55)], "LeftUpLeg": [("x", 30)], "LeftLeg": [("x", 35)]},
        "deep": {"RightUpLeg": [("x", -65), ("y", 12)], "RightLeg": [("x", 95)], "LeftUpLeg": [("x", -35), ("y", -12)], "LeftLeg": [("x", 90)]},
        "tuck": {"RightUpLeg": [("x", -75)], "RightLeg": [("x", 100)], "LeftUpLeg": [("x", -60)], "LeftLeg": [("x", 105)]},
        "superman": {"RightUpLeg": [("x", -75)], "RightLeg": [("x", 25)], "LeftUpLeg": [("x", 55)], "LeftLeg": [("x", 10)]},
        "toes": {"RightFoot": [("x", 25)], "LeftFoot": [("x", 25)]},
    }[kind]


def body(leg_kind, **spine):
    s = dict(legs(leg_kind))
    s["Spine"] = [(ax, deg) for ax, deg in spine.items()]
    return s


HIPS = (0, 0, -0.05)

# ── Dagas: guardia de pelea con las dos hojas al frente ──
D_GUARD_R = {"RightArm": F(0.35, 0.3, -0.85), "RightForeArm": F(0.85, 0.05, 0.5), "RightBlade": F(0.8, -0.1, 0.6)}
D_GUARD = both(D_GUARD_R)
D_GUARD_L = mirror(D_GUARD_R)
D_WINGS = both({"RightArm": F(-0.1, 1.0, 0.05), "RightForeArm": F(0.0, 1.0, 0.1), "RightBlade": F(0.3, 0.95, 0.0)})

# ── Maza de dos manos: en guardia cruzada, la cabeza arriba por detrás del hombro derecho ──
M_GUARD = {"TwoHand": True, "RightArm": F(0.35, 0.15, -0.9), "RightForeArm": F(0.8, -0.3, 0.4),
    "RightBlade": F(-0.3, 0.35, 0.88)}


def mace(arm, fore, blade):
    return {"TwoHand": True, "RightArm": F(*arm), "RightForeArm": F(*fore), "RightBlade": F(*blade)}


CLIPS = {
    # Tajo diagonal con la derecha: se enrosca hacia atrás y suelta el brazo con un salto hacia delante
    "daga1": [
        (1, body("ready", x=10), HIPS, D_GUARD),
        (4, body("ready", z=-50, x=-5), (0, 0.05, -0.02), dict(D_GUARD_L,
            RightArm=F(-0.3, 0.7, 0.6), RightForeArm=F(-0.7, 0.4, 0.6), RightBlade=F(-0.8, 0.3, 0.5))),
        (7, body("lunge", z=45, x=25), (0, -0.25, -0.1), dict(D_GUARD_L,
            RightArm=F(0.7, -0.6, -0.2), RightForeArm=F(0.5, -0.85, -0.1), RightBlade=F(0.2, -0.9, -0.4))),
        (13, body("ready", x=10), HIPS, D_GUARD),
    ],
    # Torbellino: un giro completo con los brazos abiertos y las hojas hacia fuera (con un saltito)
    "daga3": [
        (1, body("ready", x=10), HIPS, D_GUARD),
        (4, body("wide", x=20), (0, 0, -0.12), both({"RightArm": F(0.5, -0.3, -0.3), "RightForeArm": F(0.2, -0.9, 0.1), "RightBlade": F(-0.2, -0.95, 0.1)})),
        (7, body("wide", x=5), (0, 0, 0.08), D_WINGS, -120),
        (10, body("wide", x=5), (0, 0, 0.14), D_WINGS, -240),
        (13, body("wide", x=10), (0, 0, 0.0), D_WINGS, -360),
        (19, body("ready", x=10), HIPS, D_GUARD),
    ],
    # Embestida "superhéroe": casi horizontal, una pierna estirada atrás y las hojas como alas
    "daga_embestida": [
        (1, body("ready", x=10), HIPS, D_GUARD),
        (3, body("superman", x=70), (0, -0.3, -0.25), both({"RightArm": F(-0.7, 0.6, -0.2), "RightForeArm": F(-0.9, 0.4, 0.0), "RightBlade": F(-0.9, 0.3, 0.3)})),
        (10, body("superman", x=72), (0, -0.32, -0.27), both({"RightArm": F(-0.75, 0.6, -0.15), "RightForeArm": F(-0.92, 0.38, 0.05), "RightBlade": F(-0.92, 0.3, 0.35)})),
        (15, body("ready", x=10), HIPS, D_GUARD),
    ],
    # Mazazo diagonal PESADO: la maza cuesta subirla (se hunde y carga el peso atrás), se queda un instante
    # suspendida arriba, cae de golpe (4 fotogramas), se clava en el suelo arrastrando el cuerpo y la saca
    # con esfuerzo. Golpe en los fotogramas 20-25.
    "maza1": [
        (1, body("wide", x=5), HIPS, M_GUARD),
        (7, body("wide", x=-5, z=-15), (0, 0.03, -0.09), mace((0.1, 0.35, 0.9), (-0.2, 0.1, 0.95), (-0.5, 0.3, 0.8))),
        (14, dict(legs("toes"), Spine=[("x", -25), ("z", -40)]), (0, 0.07, 0.06),
            mace((0.0, 0.2, 0.98), (-0.5, -0.1, 0.85), (-0.9, 0.3, -0.2))),
        (18, dict(legs("toes"), Spine=[("x", -29), ("z", -44)]), (0, 0.08, 0.07),
            mace((-0.05, 0.22, 0.97), (-0.55, -0.1, 0.83), (-0.95, 0.3, -0.25))),
        (22, body("lunge", x=40, z=35), (0, -0.25, -0.15), mace((0.85, -0.3, -0.3), (0.75, -0.55, -0.35), (0.6, -0.4, -0.7))),
        (24, body("lunge", x=48, z=48), (0, -0.28, -0.2), mace((0.5, -0.6, -0.6), (0.2, -0.9, -0.4), (0.0, -0.9, -0.45))),
        (32, body("lunge", x=52, z=50), (0, -0.29, -0.23), mace((0.5, -0.6, -0.6), (0.2, -0.9, -0.4), (0.0, -0.9, -0.45))),
        (42, body("wide", x=25, z=20), (0, -0.12, -0.14), mace((0.6, -0.35, -0.5), (0.55, -0.6, 0.1), (0.35, -0.5, -0.5))),
        (54, body("wide", x=5), HIPS, M_GUARD),
    ],
    # Barrido horizontal PESADO: se enrosca a la izquierda hundiéndose, aguanta la carga, barre (5 fotogramas)
    # y la inercia de la maza le arrastra más allá y le hace trastabillar antes de recuperar la guardia.
    # Golpe en los fotogramas 19-26.
    "maza2": [
        (1, body("wide", x=5), HIPS, M_GUARD),
        (9, body("wide", z=40), (0, 0.04, -0.12), mace((0.6, -0.7, 0.0), (0.0, -0.95, 0.2), (-0.6, -0.8, 0.1)), 25),
        (16, body("wide", z=55, x=-5), (0, 0.06, -0.15), mace((0.4, -0.85, 0.05), (-0.2, -0.95, 0.2), (-0.75, -0.65, 0.1)), 35),
        (21, body("wide", z=-30, x=10), (0, -0.08, -0.12), mace((0.85, 0.4, 0.0), (0.6, 0.75, 0.1), (0.45, 0.88, 0.1))),
        (25, body("wide", z=-40, x=10), (0, -0.1, -0.14), mace((0.6, 0.75, 0.0), (0.2, 0.97, 0.1), (-0.2, 0.97, 0.1)), -90),
        (34, body("wide", z=-45, x=24), (0, -0.13, -0.18), mace((0.25, 0.55, -0.8), (0.15, 0.75, -0.65), (-0.25, 0.6, -0.75)), -110),
        (48, body("wide", x=5), HIPS, M_GUARD),
    ],
    # Helicóptero PESADO: carga larga, vuelta completa con la maza estirada (más lenta que antes) y al
    # acabar la maza le arrastra hasta casi el suelo; se queda clavado un momento. Golpe en 18-35.
    "maza3": [
        (1, body("wide", x=5), HIPS, M_GUARD),
        (10, body("wide", z=50, x=10), (0, 0, -0.13), mace((0.5, -0.8, 0.1), (0.1, -0.95, 0.2), (-0.4, -0.9, 0.15)), 20),
        (16, body("wide", z=58, x=12), (0, 0, -0.16), mace((0.4, -0.88, 0.1), (0.0, -0.97, 0.2), (-0.5, -0.85, 0.15)), 32),
        (20, body("wide", x=5), (0, 0, 0.0), mace((0.9, 0.0, 0.0), (0.95, 0.0, 0.05), (0.95, -0.1, 0.0)), -60),
        (25, body("wide", x=5), (0, 0, 0.05), mace((0.9, 0.0, 0.0), (0.95, 0.0, 0.05), (0.95, -0.1, 0.0)), -170),
        (30, body("wide", x=5), (0, 0, 0.05), mace((0.9, 0.0, 0.0), (0.95, 0.0, 0.05), (0.95, -0.1, 0.0)), -280),
        (35, body("deep", x=22), (0, -0.05, -0.18), mace((0.9, 0.05, -0.25), (0.9, 0.0, -0.25), (0.8, 0.2, -0.4)), -360),
        (46, body("deep", x=26), (0, -0.06, -0.2), mace((0.85, 0.1, -0.4), (0.85, 0.0, -0.35), (0.7, 0.2, -0.6)), -360),
        (58, body("wide", x=5), HIPS, M_GUARD),
    ],
    # Levantar y golpear (cierre del combo, va tras "maza1" que acaba con la maza clavada): arranca de esa pose,
    # tira de la maza hacia arriba con esfuerzo, la sube recta por encima de la cabeza, se queda un instante
    # arriba y la deja caer en vertical delante. Golpe en los fotogramas 21-26.
    "maza4": [
        (1, body("lunge", x=52, z=50), (0, -0.29, -0.23), mace((0.5, -0.6, -0.6), (0.2, -0.9, -0.4), (0.0, -0.9, -0.45))),
        (8, body("wide", x=20, z=10), (0, -0.1, -0.12), mace((0.8, 0.0, 0.2), (0.6, 0.0, 0.7), (0.3, 0.0, 0.95))),
        (14, dict(legs("toes"), Spine=[("x", -20)]), (0, 0.05, 0.06), mace((0.0, 0.05, 1.0), (-0.4, 0.0, 0.9), (-0.95, 0.0, 0.2))),
        (18, dict(legs("toes"), Spine=[("x", -24)]), (0, 0.06, 0.07), mace((-0.05, 0.05, 1.0), (-0.5, 0.0, 0.86), (-0.98, 0.0, 0.1))),
        (22, body("lunge", x=35), (0, -0.2, -0.12), mace((0.9, 0.05, 0.3), (0.95, 0.0, 0.1), (0.7, 0.0, 0.7))),
        (24, body("deep", x=55), (0, -0.3, -0.28), mace((0.85, 0.15, -0.5), (0.85, 0.0, -0.5), (0.55, 0.0, -0.85))),
        (34, body("deep", x=52), (0, -0.3, -0.27), mace((0.85, 0.15, -0.5), (0.85, 0.0, -0.5), (0.56, 0.0, -0.84))),
        (46, body("wide", x=25), (0, -0.12, -0.14), mace((0.6, -0.2, -0.5), (0.55, -0.4, 0.1), (0.35, -0.3, -0.5))),
        (58, body("wide", x=5), HIPS, M_GUARD),
    ],
    # Especial: salto enorme con la maza a la espalda y caída clavándola en el suelo (impacto en el fotograma 19)
    "maza_suelo": [
        (1, body("wide", x=5), HIPS, M_GUARD),
        (6, body("deep", x=30), (0, 0.05, -0.22), mace((0.0, 0.5, 0.85), (-0.5, 0.3, 0.8), (-0.8, 0.2, 0.5))),
        (12, body("tuck", x=-30), (0, -0.1, 0.6), mace((-0.1, 0.15, 0.98), (-0.4, 0.0, 0.92), (-0.85, 0.0, 0.5))),
        (16, body("tuck", x=15), (0, -0.25, 0.35), mace((0.2, 0.15, 0.97), (0.3, 0.0, 0.95), (0.35, 0.0, 0.93))),
        (19, body("deep", x=55), (0, -0.35, -0.3), mace((0.85, 0.15, -0.5), (0.85, 0.0, -0.5), (0.55, 0.0, -0.85))),
        (28, body("deep", x=52), (0, -0.35, -0.29), mace((0.85, 0.15, -0.5), (0.85, 0.0, -0.5), (0.56, 0.0, -0.84))),
        (40, body("wide", x=5), HIPS, M_GUARD),
    ],
}


# Maza al hombro, a dos manos (capa de torso sobre andar/correr/reposo en el juego: solo cuentan columna,
# cuello, cabeza y brazos). Bucle con una respiración suave; piernas y cadera como en reposo.
M_CARRY = mace((0.3, 0.35, -0.88), (0.5, -0.1, 0.86), (-0.7, 0.25, 0.65))
CLIPS["maza_hombro"] = [
    (1, {"Spine": [("x", 4)]}, (0, 0, 0), M_CARRY),
    (16, {"Spine": [("x", 7)], "Spine1": [("x", 2)]}, (0, 0, 0), M_CARRY),
    (31, {"Spine": [("x", 4)]}, (0, 0, 0), M_CARRY),
]


# Dagas en guardia de pelea (misma capa de torso; en el juego la columna sale de la locomoción): asimétrica,
# la izquierda adelantada y alta (a la altura del pecho, hoja hacia delante y arriba) y la derecha atrás, junto
# a la cadera, con la hoja hacia delante; codos doblados y pegados al cuerpo. Los brazos respiran un poco.
D_CARRY_R = {"RightArm": F(0.15, 0.35, -0.92), "RightForeArm": F(0.9, -0.1, 0.12), "RightBlade": F(0.8, -0.15, 0.5)}
D_CARRY_L = {"LeftArm": F(0.45, -0.2, -0.85), "LeftForeArm": F(0.85, 0.1, 0.5), "LeftBlade": F(0.85, 0.05, 0.5)}
D_CARRY = dict(D_CARRY_R, **D_CARRY_L)
D_CARRY_IN = dict(
    {"RightArm": F(0.12, 0.37, -0.92), "RightForeArm": F(0.88, -0.1, 0.18), "RightBlade": F(0.75, -0.15, 0.58)},
    **{"LeftArm": F(0.42, -0.22, -0.86), "LeftForeArm": F(0.82, 0.1, 0.56), "LeftBlade": F(0.8, 0.05, 0.58)})
CLIPS["daga_guardia"] = [
    (1, {"Spine": [("x", 8), ("z", -12)]}, (0, 0, 0), D_CARRY),
    (16, {"Spine": [("x", 10), ("z", -14)]}, (0, 0, 0), D_CARRY_IN),
    (31, {"Spine": [("x", 8), ("z", -12)]}, (0, 0, 0), D_CARRY),
]


def _mirror_clip(keys):
    out = []
    for key in keys:
        f, spec, hips, aims = key[:4]
        s = {_swap(k): [(ax, -deg if ax in ("y", "z") else deg) for ax, deg in rots] for k, rots in spec.items()}
        out.append((f, s, (-hips[0], hips[1], hips[2]), mirror(aims)) + ((-key[4],) if len(key) > 4 else ()))
    return out


# Revés con la izquierda: espejo exacto del tajo derecho
CLIPS["daga2"] = _mirror_clip(CLIPS["daga1"])


def lib():
    ns = {}
    exec(bpy.data.texts["anim_lib"].as_string(), ns)
    return ns


def setup_proxies(ns):
    """Copias de las armas (escena Armas_Melee) en las manos, con el agarre y la escala del juego, para
    previsualizar. No se exportan."""
    sc, arm = ns["sc"], ns["arm"]
    for name, src, bone in (("DagaProxyR", "Daga", "RightHand"), ("DagaProxyL", "Daga", "LeftHand"), ("MazaProxy", "Maza", "RightHand")):
        side = "Right" if bone.startswith("Right") else "Left"
        o = sc.objects.get(name)
        if o is None:
            o = bpy.data.objects.new(name, bpy.data.objects[src].data)
            sc.collection.objects.link(o)
        o.data = bpy.data.objects[src].data
        o.parent, o.parent_type, o.parent_bone = arm, "BONE", "mixamorig:" + bone
        o.matrix_parent_inverse = Matrix.Identity(4)
        z = BLADE_LOCAL[side]
        y = Vector((0.0, 1.0, 0.0))
        rot = Matrix((y.cross(z), y, z)).transposed().to_4x4()
        o.matrix_basis = Matrix.Translation(GRIP_LOCAL) @ rot @ Matrix.Scale(GAME_M, 4)


def _rotate_about_head(ns, pb, cur, target):
    q = cur.rotation_difference(target)
    if q.angle < 1e-5:
        return
    h = pb.head.copy()
    axis = ns["RQ"].inverted() @ q.axis
    pb.matrix = Matrix.Translation(h) @ Matrix.Rotation(q.angle, 4, axis) @ Matrix.Translation(-h) @ pb.matrix
    bpy.context.view_layer.update()


def _bone(ns, name):
    return ns["arm"].pose.bones["mixamorig:" + name]


def _aim_segment(ns, key, target):
    mw = ns["arm"].matrix_world.to_3x3().normalized()
    pb = _bone(ns, key)
    _rotate_about_head(ns, pb, (mw @ (pb.tail - pb.head)).normalized(), target)


## Muñeca natural: el puño sujeta el arma casi perpendicular al antebrazo, así que no se fuerza la
## dirección pedida a cualquier precio. Se busca la orientación de la mano que más se le acerque doblando
## la muñeca como mucho WRIST_MAX_SWING y girando el antebrazo sobre sí mismo (pronación) como mucho
## WRIST_MAX_TWIST; la torsión va al antebrazo, no a la muñeca.
WRIST_MAX_SWING = 45.0
WRIST_MAX_TWIST = 90.0
_SWINGS = (0.0, 10.0, 20.0, 30.0, 40.0, 45.0)
_TWISTS = tuple(float(t) for t in range(-90, 91, 15))
_AXES = tuple(math.radians(a) for a in range(0, 360, 20))


## Giro del codo alrededor de la línea hombro-muñeca: la mano no se mueve, pero el antebrazo cambia de
## orientación (y con él hacia dónde puede apuntar el arma sin forzar la muñeca).
_SWIVELS = tuple(float(p) for p in range(-75, 76, 15))


def _aim_blade(ns, side, target, swivel=True):
    hand, fore, upper = _bone(ns, side + "Hand"), _bone(ns, side + "ForeArm"), _bone(ns, side + "Arm")
    t = (ns["RQ"].inverted() @ target).normalized()          # a ejes de la armadura
    blade = BLADE_LOCAL[side]
    f3 = fore.matrix.to_3x3().normalized()
    rel = fore.bone.matrix_local.to_3x3().inverted() @ hand.bone.matrix_local.to_3x3()
    axis = (hand.head - upper.head).normalized()
    # Precálculo de las orientaciones de la muñeca (torsión del antebrazo × flexión)
    wrist = []
    for tw in _TWISTS:
        rt = Matrix.Rotation(math.radians(tw), 3, "Y")
        for s in _SWINGS:
            for a in (_AXES if s > 0.0 else (0.0,)):
                sw = Matrix.Rotation(math.radians(s), 3, Vector((math.cos(a), 0.0, math.sin(a))))
                wrist.append((0.4 * s + 0.15 * abs(tw), tw, sw, rt @ rel @ sw @ blade))
    best = None
    for ps in (_SWIVELS if swivel else (0.0,)):
        rs = Matrix.Rotation(math.radians(ps), 3, axis)
        fs = rs @ f3
        for pen, tw, sw, local_blade in wrist:
            cost = math.degrees((fs @ local_blade).angle(t)) + pen + 0.1 * abs(ps)
            if best is None or cost < best[0]:
                best = (cost, tw, sw, ps)
    _, tw, sw, ps = best
    if ps != 0.0:
        uh = upper.head.copy()
        upper.matrix = Matrix.Translation(uh) @ Matrix.Rotation(math.radians(ps), 4, axis) @ Matrix.Translation(-uh) @ upper.matrix
        bpy.context.view_layer.update()
        f3 = fore.matrix.to_3x3().normalized()
    fh = fore.head.copy()
    fore.matrix = Matrix.Translation(fh) @ (f3 @ Matrix.Rotation(math.radians(tw), 3, "Y")).to_4x4()
    bpy.context.view_layer.update()
    hh = hand.head.copy()
    hand.matrix = Matrix.Translation(hh) @ (fore.matrix.to_3x3().normalized() @ rel @ sw).to_4x4()
    bpy.context.view_layer.update()


def _grip_world(ns, side):
    pb = _bone(ns, side + "Hand")
    return ns["arm"].matrix_world @ (pb.matrix @ GRIP_LOCAL)


def _shaft(ns):
    mw = ns["arm"].matrix_world.to_3x3().normalized()
    rh = _bone(ns, "RightHand")
    return (mw @ (rh.matrix.to_3x3().normalized() @ BLADE_LOCAL["Right"])).normalized()


def _ik_grip(ns, side, goal, blade, pole):
    """IK de dos huesos: lleva el agarre de la mano `side` a `goal` (mundo) con el arma hacia `blade`."""
    mw4 = ns["arm"].matrix_world
    target = goal.copy()
    for _ in range(6):
        sh = mw4 @ _bone(ns, side + "Arm").head
        el = mw4 @ _bone(ns, side + "ForeArm").head
        wr = mw4 @ _bone(ns, side + "Hand").head
        l1, l2 = (el - sh).length, (wr - el).length
        d = target - sh
        dist = min(max(d.length, 1e-6), (l1 + l2) * 0.999)
        dn = d.normalized()
        n = dn.cross(F(*pole))
        if n.length < 1e-6:
            n = dn.orthogonal()
        n.normalize()
        a = math.acos(max(-1.0, min(1.0, (l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist))))
        _aim_segment(ns, side + "Arm", (Matrix.Rotation(a, 3, n) @ dn).normalized())
        el = mw4 @ _bone(ns, side + "ForeArm").head
        _aim_segment(ns, side + "ForeArm", (target - el).normalized())
        _aim_blade(ns, side, blade)
        # La muñeca no es la palma: se corrige el objetivo con lo que falte hasta el agarre
        target = target + (goal - _grip_world(ns, side))


def _left_goal(ns, shaft):
    """Punto del mango para la izquierda: se desliza (de -0,22 a -0,46 m) hasta donde llega."""
    mw4 = ns["arm"].matrix_world
    s = mw4.to_scale().x
    rg = _grip_world(ns, "Right")
    sh = mw4 @ _bone(ns, "LeftArm").head
    el = mw4 @ _bone(ns, "LeftForeArm").head
    reach = (el - sh).length + ((mw4 @ _bone(ns, "LeftHand").head) - el).length
    best = None
    for k in (0.0, 0.06, -0.06, 0.12, -0.12):
        p = rg + shaft * ((MACE_LEFT_GRIP + k * GAME_M) * s)
        slack = reach * 0.95 - (p - sh).length
        if best is None or (slack >= 0.0 and best[1] < 0.0) or (best[1] < 0.0 and slack > best[1]):
            best = (p, slack)
        if slack >= 0.0:
            break
    return best[0]


RIGHT_ELBOW_POLE = (0.0, 0.6, -0.8)


def _two_hand(ns):
    """La mano izquierda agarra el mango de la maza por debajo de la derecha. Si no llega, la derecha
    también se acerca: las dos manos se encuentran a medio camino (el arma conserva su dirección)."""
    for _ in range(3):
        shaft = _shaft(ns)
        goal = _left_goal(ns, shaft)
        _ik_grip(ns, "Left", goal, shaft, LEFT_ELBOW_POLE)
        gap = goal - _grip_world(ns, "Left")
        if gap.length < 0.02 * GAME_M * ns["arm"].matrix_world.to_scale().x:
            return
        _ik_grip(ns, "Right", _grip_world(ns, "Right") - gap * 0.6, shaft, RIGHT_ELBOW_POLE)

## Con el puño cerrado el arma sale a ~90° del antebrazo (como un martillo). Si una pose pide el antebrazo
## casi paralelo al arma, la muñeca tendría que doblarse 90°: se corrige el antebrazo (en el plano que forma
## con el arma) para que quede entre FOREARM_BLADE_MIN y FOREARM_BLADE_MAX grados del arma.
FOREARM_BLADE_MIN = 70.0
FOREARM_BLADE_MAX = 110.0


def _natural_forearm(fore, blade):
    ang = math.degrees(fore.angle(blade))
    want = min(max(ang, FOREARM_BLADE_MIN), FOREARM_BLADE_MAX)
    if abs(want - ang) < 0.5:
        return fore
    perp = fore - blade * fore.dot(blade)
    if perp.length < 1e-4:
        perp = blade.orthogonal()
    perp.normalize()
    w = math.radians(want)
    return (blade * math.cos(w) + perp * math.sin(w)).normalized()


def apply_aims(ns, aims, turn=0.0):
    rot = Matrix.Rotation(math.radians(turn), 3, "Z")
    for side in ("Right", "Left"):
        for seg in ("Arm", "ForeArm"):
            if side + seg in aims:
                target = rot @ aims[side + seg]
                if seg == "ForeArm" and side + "Blade" in aims:
                    target = _natural_forearm(target, rot @ aims[side + "Blade"])
                _aim_segment(ns, side + seg, target)
        if side + "Blade" in aims:
            _aim_blade(ns, side, rot @ aims[side + "Blade"])
        if side == "Right" and aims.get("TwoHand"):
            _two_hand(ns)


def make_clip(ns, name, keys):
    arm, sc = ns["arm"], ns["sc"]
    if name in bpy.data.actions:
        bpy.data.actions.remove(bpy.data.actions[name])
    act = bpy.data.actions.new(name)
    arm.animation_data.action = act
    prev = {}
    for key in keys:
        f, spec, hips, aims = key[:4]
        turn = key[4] if len(key) > 4 else 0.0
        sc.frame_set(f)
        spec = dict(spec)
        if turn:
            spec["Hips"] = [("z", turn)]
        ns["apply_pose"](spec, hips)
        apply_aims(ns, aims, turn)
        for pb in arm.pose.bones:
            # Cuaterniones continuos: si no, un giro de 360° se interpola por el camino corto (al revés)
            q = pb.rotation_quaternion.copy()
            if pb.name in prev and prev[pb.name].dot(q) < 0.0:
                q.negate()
                pb.rotation_quaternion = q
            prev[pb.name] = q
            pb.keyframe_insert("rotation_quaternion", frame=f, group=pb.name)
            if pb.name == "mixamorig:Hips":
                pb.keyframe_insert("location", frame=f, group=pb.name)
    act.use_fake_user = True
    sc.frame_start, sc.frame_end = keys[0][0], keys[-1][0]
    return act


def build(names=None):
    ns = lib()
    acts = {}
    for name, keys in CLIPS.items():
        if names and name not in names:
            continue
        acts[name] = make_clip(ns, "mikeura_" + name, keys)
    return ns, acts


def export(ns, names=None):
    sc = ns["sc"]
    arm = ns["arm"]
    mesh = sc.objects["Mesh_0"]
    bpy.context.window.scene = sc
    for name in CLIPS:
        if names and name not in names:
            continue
        act = bpy.data.actions["mikeura_" + name]
        arm.animation_data.action = act
        # Godot toma como reposo la pose del fotograma actual: exportar desde el primero (de pie)
        sc.frame_start, sc.frame_end = int(act.frame_range[0]), int(act.frame_range[1])
        sc.frame_set(sc.frame_start)
        for o in sc.objects:
            o.select_set(False)
        arm.select_set(True)
        mesh.select_set(True)
        bpy.context.view_layer.objects.active = arm
        bpy.ops.export_scene.fbx(filepath=os.path.join(OUT, "mikeura_%s.fbx" % name), use_selection=True,
            add_leaf_bones=False, bake_anim=True, bake_anim_use_all_actions=False,
            bake_anim_use_nla_strips=False)
