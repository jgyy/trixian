#!/usr/bin/env python3
"""Repairs a Tripo rigged character GLB: facing, bind pose, skin weights and animation clips.

usage: fix_character_rig.py IN.glb OUT.glb [--kind biped|quadruped]

What it fixes, and why:

  Facing      Tripo's humanoids face +X, but glTF and the game expect +Z. The armature node gets
              a yaw so every character faces +Z.
  Bind pose   The mesh is re-posed from Tripo's T-pose into a relaxed standing pose and bound
              there, so every clip is a small move away from the bind pose.
  Weights     Vertices bound to the dummy "neutral_bone" are re-skinned, then triangles that
              stretch past a limit in any clip are found by skinning the mesh through every pose
              and the weights around them are smoothed until they stop (rig_skin.py).
  Clips       Tripo's preset clips are replaced by short authored ones (rig_clips.py): idle, walk,
              run, slash, hurt and greet for a biped, and idle, walk, run, slash (a bite) and
              hurt for the wolf. Textures, UVs and the material are not touched.

Run it once, on the output of rebake_textures.py and tune_character_materials.py. The result is
marked in the GLB and a second run is refused unless --force is given.
"""

import argparse
import copy
import sys

import numpy as np

import rig_clips
import rig_skin
from glb_rig import (
    ARRAY_BUFFER,
    ELEMENT_ARRAY_BUFFER,
    GlbWriter,
    Rig,
    matrix_to_quat,
    read_glb,
)
from rig_poser import Poser

FPS = 30


def detect_forward(rig):
    """Horizontal direction the character faces, snapped to the nearest world axis."""
    t, r = rig.rest_pose()
    world = rig.world_matrices(t, r)
    total = np.zeros(3)
    if "L_ToeBase" in rig.names:
        for side in "LR":
            total += (
                world[rig.find(side + "_ToeBase")][:3, 3] - world[rig.find(side + "_Foot")][:3, 3]
            )
    else:
        total = world[rig.find("tripo::Head_0")][:3, 3] - world[rig.find("tripo::Spine_0")][:3, 3]
    total[1] = 0.0
    axis = np.argmax(np.abs(total))
    forward = np.zeros(3)
    forward[axis] = 1.0 if total[axis] > 0 else -1.0
    return forward


def biped_clips(kind):
    return rig_clips.QUADRUPED_CLIPS if kind == "quadruped" else rig_clips.CLIPS


def clip_poses(biped, names):
    clips = {}
    for name in names:
        clips[name] = rig_clips.sample(biped, name, FPS)
    return clips


def stack_quats(rotations):
    """(K, N, 3, 3) matrices to (K, N, 4) quaternions, flipped to stay in one hemisphere."""
    quats = matrix_to_quat(rotations)
    for k in range(1, len(quats)):
        flip = np.sum(quats[k] * quats[k - 1], axis=1) < 0
        quats[k][flip] *= -1.0
    return quats


def rebind(rig, stand_t, stand_r, weights, joints):
    """Skins the mesh into the stand pose.

    Returns positions, normals, tangents (None when the mesh has none) and new inverse binds.
    """
    world = rig.world_matrices(stand_t, stand_r)
    skin = rig.skin_matrices(world)
    blended = np.einsum("vk,vkij->vij", weights, skin[joints])
    homogeneous = np.concatenate([rig.positions, np.ones((len(rig.positions), 1))], axis=1)
    positions = np.einsum("vij,vj->vi", blended, homogeneous)[:, :3]
    linear = blended[:, :3, :3]
    normals = np.einsum("vji,vj->vi", np.linalg.inv(linear), rig.normals)
    normals /= np.linalg.norm(normals, axis=1, keepdims=True)
    tangents = None
    if rig.tangents is not None:
        # A tangent runs along the surface, so it turns with the blended transform itself.
        turned = np.einsum("vij,vj->vi", linear, rig.tangents[:, :3])
        turned /= np.linalg.norm(turned, axis=1, keepdims=True)
        tangents = np.concatenate([turned, rig.tangents[:, 3:]], axis=1)
    return positions, normals, tangents, np.linalg.inv(world[rig.joints])


def write_rig(
    rig,
    doc,
    binary,
    path,
    forward,
    stand,
    clips,
    positions,
    normals,
    tangents,
    ibm,
    weights,
    joints,
    indices,
):
    doc = copy.deepcopy(doc)
    writer = GlbWriter(doc, binary)
    stand_t, stand_r = stand
    stand_q = matrix_to_quat(stand_r)
    for index, node in enumerate(doc["nodes"]):
        if index in rig.joint_of_node:
            node["translation"] = [float(v) for v in stand_t[index]]
            node["rotation"] = [float(v) for v in stand_q[index]]
    # Turn the whole armature so the character faces +Z.
    heading = -np.arctan2(forward[0], forward[2])
    armature = next(i for i, p in enumerate(rig.parent) if p < 0 and "Armature" in rig.names[i])
    if abs(heading) > 1e-6:
        doc["nodes"][armature]["rotation"] = [
            0.0,
            float(np.sin(heading / 2)),
            0.0,
            float(np.cos(heading / 2)),
        ]

    primitive = doc["meshes"][0]["primitives"][0]
    attrs = primitive["attributes"]
    original = {name: dict(doc["accessors"][index]) for name, index in attrs.items()}
    for name, data in (("POSITION", positions), ("NORMAL", normals)):
        extra = {}
        if name == "POSITION":
            extra = {"min": data.min(axis=0).tolist(), "max": data.max(axis=0).tolist()}
        attrs[name] = writer.add_accessor(
            data.astype(np.float32), 5126, "VEC3", ARRAY_BUFFER, extra
        )
    if tangents is not None:
        attrs["TANGENT"] = writer.add_accessor(
            tangents.astype(np.float32), 5126, "VEC4", ARRAY_BUFFER
        )
    attrs["TEXCOORD_0"] = writer.copy_accessor(attrs["TEXCOORD_0"])
    joint_type = original["JOINTS_0"]["componentType"]
    attrs["JOINTS_0"] = writer.add_accessor(joints, joint_type, "VEC4", ARRAY_BUFFER)
    attrs["WEIGHTS_0"] = writer.add_accessor(weights.astype(np.float32), 5126, "VEC4", ARRAY_BUFFER)
    primitive["indices"] = writer.add_accessor(
        indices.astype(np.uint32).reshape(-1, 1), 5125, "SCALAR", ELEMENT_ARRAY_BUFFER
    )
    for index, image in enumerate(doc["images"]):
        image["bufferView"] = writer.copy_view(image["bufferView"])
    doc["skins"][0]["inverseBindMatrices"] = writer.add_accessor(
        ibm.transpose(0, 2, 1).reshape(-1, 16).astype(np.float32), 5126, "MAT4"
    )

    animations = []
    for name, (times, translations, rotations) in clips.items():
        quats = stack_quats(rotations)
        samplers = []
        channels = []
        time_accessor = writer.add_accessor(
            times.astype(np.float32).reshape(-1, 1),
            5126,
            "SCALAR",
            extra={"min": [float(times[0])], "max": [float(times[-1])]},
        )
        for node in rig.joints:
            if rig.names[node] == "neutral_bone":
                continue
            samplers.append(
                {
                    "input": time_accessor,
                    "interpolation": "LINEAR",
                    "output": writer.add_accessor(quats[:, node], 5126, "VEC4"),
                }
            )
            channels.append(
                {"sampler": len(samplers) - 1, "target": {"node": node, "path": "rotation"}}
            )
            moving = np.abs(translations[:, node] - translations[0, node]).max() > 1e-7
            if moving:
                samplers.append(
                    {
                        "input": time_accessor,
                        "interpolation": "LINEAR",
                        "output": writer.add_accessor(translations[:, node], 5126, "VEC3"),
                    }
                )
                channels.append(
                    {"sampler": len(samplers) - 1, "target": {"node": node, "path": "translation"}}
                )
        animations.append({"name": name, "samplers": samplers, "channels": channels})
    doc["animations"] = animations
    doc["asset"].setdefault("extras", {})[MARKER] = True
    writer.write(path)


MARKER = "xianxiaRigFix"


def main(source, destination, kind, names, limit, cut, force):
    doc, binary = read_glb(source)
    if doc["asset"].get("extras", {}).get(MARKER) and not force:
        sys.exit("%s was already repaired; run this on the rebaked Tripo output" % source)
    rig = Rig(doc, binary)
    forward = detect_forward(rig)
    print("  facing %s" % forward)
    poser = Poser(rig, forward)
    biped = rig_clips.Quadruped(poser) if kind == "quadruped" else rig_clips.Biped(poser)
    stand = biped.stand()
    clips = clip_poses(biped, names or list(biped_clips(kind)))

    skin = rig_skin.SkinWeights(rig)
    dummy = [rig.names[j] for j in rig.joints].index("neutral_bone")
    print("  re-skinned %d orphan vertices" % skin.fix_orphans(dummy))
    stand_world = rig.world_matrices(*stand)
    pose_worlds = []
    for times, translations, rotations in clips.values():
        for frame in range(0, len(times), 3):
            pose_worlds.append(rig.world_matrices(translations[frame], rotations[frame]))
    worst = rig_skin.repair(rig, skin, stand_world, pose_worlds, limit, rounds=40)
    joints, weights = skin.per_vertex()
    keep = worst <= cut
    print(
        "  stretch after repair: %d triangles over %.1fx, %d over %.1fx removed"
        % ((worst > limit).sum(), limit, (~keep).sum(), cut)
    )
    positions, normals, tangents, ibm = rebind(rig, stand[0], stand[1], weights, joints)
    write_rig(
        rig,
        doc,
        binary,
        destination,
        forward,
        stand,
        clips,
        positions,
        normals,
        tangents,
        ibm,
        weights,
        joints,
        rig.indices[keep],
    )
    print("  wrote %s" % destination)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("source")
    parser.add_argument("destination")
    parser.add_argument("--kind", default="biped", choices=["biped", "quadruped"])
    parser.add_argument("--clips", default="", help="comma separated; default is every clip")
    parser.add_argument("--limit", type=float, default=2.0, help="stretch that triggers smoothing")
    parser.add_argument(
        "--cut", type=float, default=4.0, help="stretch above which a triangle is dropped"
    )
    parser.add_argument("--force", action="store_true", help="repair an already repaired file")
    args = parser.parse_args()
    clips = [name for name in args.clips.split(",") if name]
    main(args.source, args.destination, args.kind, clips, args.limit, args.cut, args.force)
