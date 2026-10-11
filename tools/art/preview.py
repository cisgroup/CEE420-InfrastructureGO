"""Render one small picture of every model file given, so that a person can look at a whole pack at once.

    /Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python tools/art/preview.py -- --out DIR FILE...
"""

import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector


def render(path, out, size=360):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(path))
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    points = [o.matrix_world @ v.co for o in meshes for v in o.data.vertices]
    low = Vector([min(p[k] for p in points) for k in range(3)])
    high = Vector([max(p[k] for p in points) for k in range(3)])
    middle, reach = (low + high) / 2, max(high - low)

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = scene.render.resolution_y = size
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    world = bpy.data.worlds.new("World")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (1, 1, 1, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.6
    scene.world = world

    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.data.energy = 3.0
    sun.rotation_euler = (math.radians(50), 0, math.radians(35))
    scene.collection.objects.link(sun)

    camera = bpy.data.objects.new("Camera", bpy.data.cameras.new("Camera"))
    camera.data.lens = 60
    scene.collection.objects.link(camera)
    scene.camera = camera
    away = Vector((0.55, -1.0, 0.45)).normalized()
    camera.location = middle + away * reach * 2.6
    camera.rotation_euler = (middle - camera.location).to_track_quat("-Z", "Y").to_euler()

    scene.render.filepath = str(out / (path.stem + ".png"))
    bpy.ops.render.render(write_still=True)


def main():
    rest = sys.argv[sys.argv.index("--") + 1:]
    out = Path(rest[rest.index("--out") + 1])
    out.mkdir(parents=True, exist_ok=True)
    for name in [r for k, r in enumerate(rest) if r != "--out" and rest[k - 1] != "--out"]:
        render(Path(name), out)
        print("PICTURE", name)


main()
