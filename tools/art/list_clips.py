"""Say what is inside model files: the movements with their lengths, the bones, the size and the paints.

Run with Blender and no window, before a keeper's behaviour is designed, so that the design uses movements the
model really has:

    /Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python tools/art/list_clips.py -- FILE... [--json OUT]
"""

import json
import sys
from pathlib import Path

import bpy


def look(path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(path))
    rigs = [o for o in bpy.data.objects if o.type == "ARMATURE"]
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    low = [min((o.matrix_world @ v.co)[k] for o in meshes for v in o.data.vertices) for k in range(3)] if meshes else [0, 0, 0]
    high = [max((o.matrix_world @ v.co)[k] for o in meshes for v in o.data.vertices) for k in range(3)] if meshes else [0, 0, 0]
    paints = []
    for paint in bpy.data.materials:
        shader = paint.node_tree.nodes.get("Principled BSDF") if paint.use_nodes else None
        colour = [round(c, 3) for c in shader.inputs["Base Color"].default_value[:3]] if shader else None
        picture = bool(shader and shader.inputs["Base Color"].is_linked)
        paints.append({"name": paint.name, "colour": colour, "picture": picture})
    return {
        "file": path.name,
        "clips": [{"name": a.name, "frames": [round(a.frame_range[0]), round(a.frame_range[1])]} for a in bpy.data.actions],
        "fps": bpy.context.scene.render.fps,
        "bones": sum(len(r.data.bones) for r in rigs),
        "triangles": sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in meshes),
        "size": [round(high[k] - low[k], 3) for k in range(3)],
        "paints": paints,
    }


def main():
    rest = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = None
    if "--json" in rest:
        out = Path(rest[rest.index("--json") + 1])
        rest = [r for k, r in enumerate(rest) if r != "--json" and (k == 0 or rest[k - 1] != "--json")]
    found = [look(Path(r)) for r in rest]
    for f in found:
        clips = ", ".join(f"{c['name']} {c['frames'][1] - c['frames'][0]}" for c in f["clips"])
        print(f"MODEL {f['file']}: {f['bones']} bones, {f['triangles']} triangles, size {f['size']}, paints {[p['name'] for p in f['paints']]}, clips: {clips}")
    if out:
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps(found, indent=1) + "\n")


main()
