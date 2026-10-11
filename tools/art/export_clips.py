"""Turn one model of the pack into the files the game loads: one USDZ per movement, and pictures of it.

Run with Blender and no window. The model's paints are replaced by the game's own colours and given a light
glaze, so that keepers from different files look as if one hand had made them. Every movement is written as a
file of its own, named after the keeper and the game's word for the movement, because the app's bundle is flat
and RealityKit takes one movement from a file.

    Blender --background --factory-startup --python tools/art/export_clips.py -- \
        --source FILE.glb --keeper frog --out DIR --pictures DIR \
        --clips idle=Idle,duck=Duck --paints Frog_Main=6E9A3F,Frog_Secondary=31482A --portrait Idle:0 --pose Yes:12
"""

import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector


def asked():
    rest = sys.argv[sys.argv.index("--") + 1:]
    found = {}
    for k in range(0, len(rest) - 1, 2):
        found[rest[k].lstrip("-")] = rest[k + 1]
    return found


def linear(hex_colour):
    """A colour written as six hex digits, as the linear values a paint wants."""
    parts = [int(hex_colour[k:k + 2], 16) / 255 for k in (0, 2, 4)]
    return [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in parts] + [1.0]


def action_named(clip):
    for action in bpy.data.actions:
        middle = action.name.split("|")[1] if "|" in action.name else action.name
        if middle.replace("_CharacterArmature", "") == clip:
            return action
    raise SystemExit(f"the model has no movement named {clip}")


def repaint(paints, glaze):
    for paint in bpy.data.materials:
        shader = paint.node_tree.nodes.get("Principled BSDF") if paint.use_nodes else None
        if not shader:
            continue
        if paint.name in paints:
            shader.inputs["Base Color"].default_value = linear(paints[paint.name])
        shiny = paint.name.startswith("Eye")
        shader.inputs["Roughness"].default_value = 0.12 if shiny else 0.42
        shader.inputs["Metallic"].default_value = 0.0
        if "Coat Weight" in shader.inputs:
            shader.inputs["Coat Weight"].default_value = 1.0 if shiny else glaze
            shader.inputs["Coat Roughness"].default_value = 0.08


def use(rig, action):
    rig.animation_data_create()
    for track in rig.animation_data.nla_tracks:
        track.mute = True
    rig.animation_data.action = action
    first, last = (int(round(v)) for v in action.frame_range)
    scene = bpy.context.scene
    scene.frame_start, scene.frame_end = first, last
    return first, last


def picture(rig, meshes, clip, frame, target, size=640, shadow=False):
    """A picture of the model at one moment of one movement, on nothing, looked at a little from above."""
    first, _ = use(rig, action_named(clip))
    scene = bpy.context.scene
    scene.frame_set(first + frame)
    deps = bpy.context.evaluated_depsgraph_get()
    points = []
    for mesh in meshes:
        shaped = mesh.evaluated_get(deps)
        points += [shaped.matrix_world @ v.co for v in shaped.to_mesh().vertices]
    low = Vector([min(p[k] for p in points) for k in range(3)])
    high = Vector([max(p[k] for p in points) for k in range(3)])
    middle, reach = (low + high) / 2, max(high - low)
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = scene.render.resolution_y = size
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.view_transform = "Standard"
    if scene.world is None:
        world = bpy.data.worlds.new("World")
        world.use_nodes = True
        world.node_tree.nodes["Background"].inputs["Color"].default_value = (1.0, 0.97, 0.92, 1)
        world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.75
        scene.world = world
        sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
        sun.data.energy = 3.2
        sun.rotation_euler = (math.radians(48), 0, math.radians(32))
        scene.collection.objects.link(sun)
        camera = bpy.data.objects.new("Camera", bpy.data.cameras.new("Camera"))
        camera.data.lens = 70
        scene.collection.objects.link(camera)
        scene.camera = camera
    camera = scene.camera
    away = Vector((0.22, -1.0, 0.28)).normalized()
    camera.location = middle + away * reach * 2.25
    camera.rotation_euler = (middle - camera.location).to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = str(target)
    bpy.ops.render.render(write_still=True)
    print("PICTURE", target)


def main():
    want = asked()
    out = Path(want["out"])
    out.mkdir(parents=True, exist_ok=True)
    keeper = want["keeper"]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=want["source"])
    rig = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    paints = dict(pair.split("=") for pair in want.get("paints", "").split(",") if pair)
    repaint(paints, float(want.get("glaze", "0.6")))
    bpy.context.scene.render.fps = 24

    for pair in want["clips"].split(","):
        name, clip = pair.split("=")
        first, last = use(rig, action_named(clip))
        bpy.ops.object.select_all(action="DESELECT")
        rig.select_set(True)
        for mesh in meshes:
            mesh.select_set(True)
        target = out / f"{keeper}_{name}.usdz"
        bpy.ops.wm.usd_export(filepath=str(target), selected_objects_only=True, export_animation=True, export_armatures=True,
                              only_deform_bones=False, export_materials=True, generate_preview_surface=True,
                              root_prim_path=f"/{keeper}", convert_orientation=True)
        print("CLIP", target.name, "frames", last - first)

    if "pictures" in want:
        pictures = Path(want["pictures"])
        pictures.mkdir(parents=True, exist_ok=True)
        for word in ("portrait", "pose"):
            if word in want:
                clip, frame = want[word].split(":")
                picture(rig, meshes, clip, int(frame), pictures / f"{keeper}_{word}.png")


main()
