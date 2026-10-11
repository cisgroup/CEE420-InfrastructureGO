"""Build a small figure with a skeleton and two movements inside Blender and write one USDZ per movement.

The figure is made here and needs no download. It exists to answer one question before any art is converted:
does the iPhone simulator load a file with a skeleton from the app, play a named movement and fade from one
movement to the next. Run it with Blender and no window:

    /Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python tools/art/probe_rig.py -- --out DIR
"""

import math
import sys
from pathlib import Path

import bpy


def arguments():
    rest = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = Path(rest[rest.index("--out") + 1]) if "--out" in rest else Path("build/probe")
    return out


def build():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=16, radius=0.1, location=(0, 0, 0.14))
    body = bpy.context.object
    body.name = "Body"
    body.scale = (1.0, 0.9, 1.4)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    bpy.ops.object.shade_smooth()
    paint = bpy.data.materials.new("Glaze")
    paint.use_nodes = True
    shader = paint.node_tree.nodes["Principled BSDF"]
    shader.inputs["Base Color"].default_value = (0.25, 0.55, 0.32, 1)
    shader.inputs["Roughness"].default_value = 0.35
    body.data.materials.append(paint)

    bpy.ops.object.armature_add(enter_editmode=True, location=(0, 0, 0))
    rig = bpy.context.object
    rig.name = "Rig"
    bones = rig.data.edit_bones
    low = bones[0]
    low.name = "low"
    low.head, low.tail = (0, 0, 0.0), (0, 0, 0.14)
    high = bones.new("high")
    high.head, high.tail = (0, 0, 0.14), (0, 0, 0.28)
    high.parent = low
    high.use_connect = True
    bpy.ops.object.mode_set(mode="OBJECT")

    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    return rig, body


def movement(rig, name, keys):
    """One action from a list of (frame, bone, rotation about x in degrees, scale along the bone, lift)."""
    action = bpy.data.actions.new(name)
    rig.animation_data_create()
    rig.animation_data.action = action
    for frame, bone, turn, stretch, lift in keys:
        pose = rig.pose.bones[bone]
        pose.rotation_mode = "XYZ"
        pose.rotation_euler = (math.radians(turn), 0, 0)
        pose.scale = (1 / math.sqrt(stretch), stretch, 1 / math.sqrt(stretch))
        pose.location = (0, lift, 0)
        for path in ("rotation_euler", "scale", "location"):
            pose.keyframe_insert(path, frame=frame)
    return action


def export(rig, body, action, target):
    rig.animation_data.action = action
    first, last = (int(round(v)) for v in action.frame_range)
    scene = bpy.context.scene
    scene.frame_start, scene.frame_end = first, last
    scene.render.fps = 24
    bpy.ops.object.select_all(action="DESELECT")
    rig.select_set(True)
    body.select_set(True)
    bpy.ops.wm.usd_export(filepath=str(target), selected_objects_only=True, export_animation=True, export_armatures=True,
                          only_deform_bones=True, export_materials=True, generate_preview_surface=True,
                          root_prim_path="/probe", convert_orientation=True)
    print("wrote", target, "frames", first, "to", last)


def main():
    out = arguments()
    out.mkdir(parents=True, exist_ok=True)
    rig, body = build()
    idle = movement(rig, "idle", [(1, "high", 0, 1.0, 0), (13, "high", 8, 1.04, 0), (25, "high", 0, 1.0, 0), (37, "high", -8, 1.04, 0), (49, "high", 0, 1.0, 0),
                                  (1, "low", 0, 1.0, 0), (49, "low", 0, 1.0, 0)])
    hop = movement(rig, "hop", [(1, "low", 0, 1.0, 0), (7, "low", 0, 0.6, 0), (13, "low", 0, 1.3, 0.12), (19, "low", 0, 1.0, 0.16), (25, "low", 0, 0.7, 0), (31, "low", 0, 1.0, 0),
                                (1, "high", 0, 1.0, 0), (7, "high", 25, 0.8, 0), (13, "high", -10, 1.2, 0), (25, "high", 15, 0.9, 0), (31, "high", 0, 1.0, 0)])
    export(rig, body, idle, out / "probe_idle.usdz")
    export(rig, body, hop, out / "probe_hop.usdz")


main()
