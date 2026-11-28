# Poses de la pistola (mazmorra): reposo apuntando (riva_pi_hold.fbx, bucle con respiración) y disparo con retroceso
# (riva_pi_fire.fbx). Parte de la postura de la escopeta (riva_es_hold.fbx: piernas y cadera) y pone los brazos con IK:
# los dos brazos estirados al frente a la altura del pecho, la mano derecha empuña y la izquierda la abraza por debajo
# (agarre a dos manos). Se hornean a fotogramas y se exportan solo con el esqueleto.
#
#   blender.exe -b --factory-startup --python tools/blender_pistol_poses.py [-- preview_dir]
#
# Ejes del esqueleto importado (escala 0,01): mira a -Y, su derecha es -X, arriba Z. Medidas en metros del personaje
# (se multiplican por S al pasar al mundo).
# El juego toma la dirección del arma del antebrazo derecho (WeaponAnimSets.SETS "aim_from_arm").
import bpy, os, sys, math
from mathutils import Vector

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "assets", "models", "riva", "riva_es_hold.fbx")
OUT = os.path.join(ROOT, "assets", "models", "riva")
PRE = "mixamorig:"
FWD, RIGHT, UP = Vector((0, -1, 0)), Vector((-1, 0, 0)), Vector((0, 0, 1))
ARM_BONES = ["RightShoulder", "RightArm", "RightForeArm", "RightHand", "LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand"]
SPINE = ["Spine", "Spine1", "Spine2", "Neck", "Head"]

args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
PREVIEW = args[0] if args else ""


def clean():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for a in list(bpy.data.actions):
        bpy.data.actions.remove(a)


def load():
    clean()
    bpy.ops.import_scene.fbx(filepath=SRC)
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    sc = bpy.context.scene
    sc.frame_set(2)
    bpy.context.view_layer.update()
    # Pose base: la del primer fotograma de la escopeta, congelada (sin acción)
    base = {pb.name: (pb.location.copy(), pb.rotation_quaternion.copy()) for pb in arm.pose.bones}
    arm.animation_data.action = None
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
        pb.location, pb.rotation_quaternion = base[pb.name]
    # Torso de frente (la escopeta lo gira): columna, cuello y cabeza rectos; brazos desde el reposo
    for b in SPINE + ARM_BONES:
        pb = arm.pose.bones[PRE + b]
        pb.rotation_quaternion = (1, 0, 0, 0)
    bpy.context.view_layer.update()
    return arm


def head(arm, b):
    return arm.matrix_world @ arm.pose.bones[PRE + b].head


def empty(name, at):
    e = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(e)
    e.location = at
    return e


def setup_ik(arm):
    S = 0.01
    sh_r, sh_l = head(arm, "RightArm"), head(arm, "LeftArm")
    center = (sh_r + sh_l) / 2
    # Muñeca derecha: al frente y algo bajo el hombro, un poco a la derecha del centro (pistola en el eje de la vista)
    rh = center + (FWD * 0.47 + UP * -0.10 + RIGHT * 0.03) * S
    lh = rh + (RIGHT * -0.045 + UP * -0.035 + FWD * -0.03) * S
    t_r, t_l = empty("T_R", rh), empty("T_L", lh)
    p_r = empty("P_R", sh_r + (RIGHT * 0.35 + UP * -0.45 + FWD * -0.1) * S)
    p_l = empty("P_L", sh_l + (RIGHT * -0.35 + UP * -0.45 + FWD * -0.1) * S)
    for side, t, p in (("Right", t_r, p_r), ("Left", t_l, p_l)):
        c = arm.pose.bones[PRE + side + "ForeArm"].constraints.new("IK")
        c.target, c.pole_target, c.chain_count = t, p, 2
        c.pole_angle = math.radians(-90)
    return t_r, t_l, S


def key_frame(arm, f):
    for pb in arm.pose.bones:
        pb.keyframe_insert("rotation_quaternion", frame=f)
        pb.keyframe_insert("location", frame=f)


def bake(arm, start, end):
    bpy.context.view_layer.objects.active = arm
    arm.select_set(True)
    bpy.ops.object.mode_set(mode="POSE")
    bpy.ops.pose.select_all(action="SELECT")
    bpy.ops.nla.bake(frame_start=start, frame_end=end, only_selected=False, visual_keying=True,
                     clear_constraints=True, use_current_action=True, bake_types={"POSE"})
    bpy.ops.object.mode_set(mode="OBJECT")


def export(arm, name, start):
    bpy.context.scene.frame_set(start)
    bpy.ops.object.select_all(action="DESELECT")
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.export_scene.fbx(filepath=os.path.join(OUT, name), use_selection=True, object_types={"ARMATURE"},
                             add_leaf_bones=False, bake_anim=True, bake_anim_use_all_actions=False,
                             bake_anim_use_nla_strips=False)
    print("EXPORTADO", name)


def preview(arm, tag):
    if not PREVIEW:
        return
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.render.resolution_x, sc.render.resolution_y = 360, 420
    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 0.021
    cam = bpy.data.objects.new("cam", cam_data)
    sc.collection.objects.link(cam)
    sc.camera = cam
    c = head(arm, "Spine1")
    views = {"front": FWD * 1 + RIGHT * 0.35, "side": RIGHT * -1, "top": UP * 1 + FWD * 0.05}
    for v, d in views.items():
        cam.location = c + d.normalized() * 0.1
        if v == "top":
            cam.rotation_euler = (0, 0, math.pi)          # mirando abajo, el frente del personaje hacia abajo de la imagen
        else:
            cam.rotation_euler = (c - cam.location).to_track_quat("-Z", "Y").to_euler()
        sc.render.filepath = os.path.join(PREVIEW, "pi_%s_%s.png" % (tag, v))
        bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam, do_unlink=True)


def build_hold():
    arm = load()
    t_r, t_l, S = setup_ik(arm)
    arm.animation_data_create()
    arm.animation_data.action = bpy.data.actions.new("pi_hold")
    base_r, base_l = t_r.location.copy(), t_l.location.copy()
    # Respiración: las manos suben y bajan 6 mm en 40 fotogramas (que no sean pistas inmóviles)
    for f in range(1, 42):
        k = math.sin((f - 1) / 40.0 * math.tau)
        t_r.location = base_r + UP * 0.006 * S * k
        t_l.location = base_l + UP * 0.006 * S * k
        t_r.keyframe_insert("location", frame=f)
        t_l.keyframe_insert("location", frame=f)
        arm.pose.bones[PRE + "Spine1"].rotation_quaternion = (1, 0.006 * k, 0, 0)
        arm.pose.bones[PRE + "Spine1"].keyframe_insert("rotation_quaternion", frame=f)
    key_frame(arm, 1)
    bake(arm, 1, 41)
    preview_at(arm, 1, "hold")
    export(arm, "riva_pi_hold.fbx", 1)


def build_fire():
    arm = load()
    t_r, t_l, S = setup_ik(arm)
    arm.animation_data_create()
    arm.animation_data.action = bpy.data.actions.new("pi_fire")
    base_r, base_l = t_r.location.copy(), t_l.location.copy()
    # Retroceso: en 2 fotogramas las manos suben 5 cm y vuelven 4 cm hacia el pecho; vuelven a apuntar hacia el 12
    kick = {1: 0.0, 2: 0.7, 3: 1.0, 5: 0.75, 8: 0.35, 11: 0.1, 14: 0.0, 16: 0.0}
    for f, k in kick.items():
        off = (UP * 0.05 + FWD * -0.04) * S * k
        t_r.location = base_r + off
        t_l.location = base_l + off
        t_r.keyframe_insert("location", frame=f)
        t_l.keyframe_insert("location", frame=f)
        arm.pose.bones[PRE + "Spine2"].rotation_quaternion = (1, -0.03 * k, 0, 0)
        arm.pose.bones[PRE + "Spine2"].keyframe_insert("rotation_quaternion", frame=f)
    key_frame(arm, 1)
    bake(arm, 1, 16)
    preview_at(arm, 3, "fire")
    export(arm, "riva_pi_fire.fbx", 1)


def preview_at(arm, f, tag):
    bpy.context.scene.frame_set(f)
    preview(arm, tag)


build_hold()
build_fire()
