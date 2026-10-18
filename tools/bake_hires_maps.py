"""Bakes a game mesh's texture maps from Tripo's full-resolution model, in Blender (Cycles, GPU).

usage: blender -b --python bake_hires_maps.py -- GAME.glb SOURCE.glb OUT_DIR SIZE

GAME.glb is the 30k-face mesh whose UVs are already laid out (rebake_textures.py writes it).
SOURCE.glb is Tripo's own model: about 1.4 million triangles and 4096 px textures. For every texel
of the game mesh's UV layout, Blender casts a ray out to the source surface and writes down

  base.png       the source base colour (diffuse colour pass)
  normal.png     the source shading normal in object space. It is turned into a tangent-space
                 normal map by rebake_textures.py, against the game mesh's own normals and
                 tangents, so that the nose, lips and eye sockets of the 1.4M-triangle mesh
                 come back as normal-map detail that Godot lights the way it was baked
  roughness.png  the source roughness, as a grey image

rebake_textures.py runs this itself when it is given a source model.
"""

import os
import sys

import bpy

# The models are normalised to one unit tall, so these are fractions of the character's height.
CAGE_EXTRUSION = 0.004
MAX_RAY_DISTANCE = 0.012
MARGIN = 16
SAMPLES = 16


def import_glb(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    created = [obj for obj in bpy.data.objects if obj not in before]
    for obj in created:
        if obj.type == "ARMATURE":
            # Skinned models import with their first animation frame applied.
            obj.data.pose_position = "REST"
    # The importer also adds an Icosphere as a bone shape; the model is the biggest mesh.
    meshes = [obj for obj in created if obj.type == "MESH"]
    return max(meshes, key=lambda obj: len(obj.data.vertices))


def world_bounds(obj):
    depsgraph = bpy.context.evaluated_depsgraph_get()
    mesh = obj.evaluated_get(depsgraph)
    corners = [mesh.matrix_world @ v.co for v in mesh.data.vertices]
    low = [min(c[i] for c in corners) for i in range(3)]
    high = [max(c[i] for c in corners) for i in range(3)]
    return low, high


def enable_gpu(scene):
    prefs = bpy.context.preferences.addons["cycles"].preferences
    for kind in ("OPTIX", "CUDA", "HIP", "ONEAPI"):
        try:
            prefs.compute_device_type = kind
        except TypeError:
            continue
        prefs.get_devices()
        devices = [d for d in prefs.devices if d.type != "CPU"]
        if devices:
            for device in prefs.devices:
                device.use = device.type != "CPU"
            scene.cycles.device = "GPU"
            print("bake device: %s (%s)" % (kind, ", ".join(d.name for d in devices)))
            return
    print("bake device: CPU")


def bake(scene, game, source, kind, name, size, colour_space, out_dir, passes=None):
    image = bpy.data.images.new(name, size, size, alpha=False)
    image.colorspace_settings.name = colour_space
    material = game.active_material
    tree = material.node_tree
    node = tree.nodes.new("ShaderNodeTexImage")
    node.image = image
    tree.nodes.active = node

    bpy.ops.object.select_all(action="DESELECT")
    source.select_set(True)
    game.select_set(True)
    bpy.context.view_layer.objects.active = game

    bake_settings = scene.render.bake
    bake_settings.use_selected_to_active = True
    bake_settings.cage_extrusion = CAGE_EXTRUSION
    bake_settings.max_ray_distance = MAX_RAY_DISTANCE
    bake_settings.margin = MARGIN
    bake_settings.margin_type = "EXTEND"
    bake_settings.use_clear = True
    bake_settings.target = "IMAGE_TEXTURES"
    if passes is not None:
        bake_settings.use_pass_direct = False
        bake_settings.use_pass_indirect = False
        bake_settings.use_pass_color = True
    if kind == "NORMAL":
        # Blender's own tangent space follows its automatic vertex normals, which are not the
        # normals stored in the GLB, so the tangent basis is applied afterwards instead.
        bake_settings.normal_space = "OBJECT"
    bpy.ops.object.bake(type=kind)

    image.filepath_raw = os.path.join(out_dir, name + ".png")
    image.file_format = "PNG"
    image.save()
    tree.nodes.remove(node)
    print("baked %s" % image.filepath_raw)


def main():
    game_path, source_path, out_dir, size = sys.argv[sys.argv.index("--") + 1 :]
    size = int(size)
    os.makedirs(out_dir, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    game = import_glb(game_path)
    source = import_glb(source_path)
    for label, obj in (("game", game), ("source", source)):
        low, high = world_bounds(obj)
        print("%s bounds %s %s" % (label, [round(v, 3) for v in low], [round(v, 3) for v in high]))

    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = SAMPLES
    scene.cycles.use_denoising = False
    enable_gpu(scene)

    bake(scene, game, source, "DIFFUSE", "base", size, "sRGB", out_dir, passes=("COLOR",))
    bake(scene, game, source, "NORMAL", "normal", size, "Non-Color", out_dir)
    bake(scene, game, source, "ROUGHNESS", "roughness", size, "Non-Color", out_dir)


main()
