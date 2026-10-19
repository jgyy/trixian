#!/usr/bin/env python3
"""Rewrites a Tripo character's vertex normals so cel shading draws clean shapes.

usage: anime_normals.py IN.glb OUT.glb [--head-bone Head] [--head-blend 0.6] [--smooth 3]

The game draws the characters with a two-tone cel shader (shaders/anime_toon.gdshader), whose
shade edge is wherever N.L crosses a threshold. Tripo's decimated 30,000-face mesh has noisy,
faceted normals: on the cultivator 43% of edges turn more than 32 degrees from one end to the
other, so the shade edge zigzags along triangle edges and cuts wedges into faces. This tool:

1. welds the vertices that share a position (UV seams split them) and rebuilds area-weighted
   smooth normals across the seams. Vertices whose old normals point apart, such as the two sides
   of a thin sheet of cloth, stay apart;
2. relaxes the normals over their neighbours a few times, which removes the decimation facets;
3. bends the normals of the head (vertices skinned to --head-bone) towards those of an ellipsoid
   fitted around it, the usual anime trick, so a face shades as one soft-edged shape instead of
   following every bump of the nose and cheeks. Skin weights blend it out down the neck.

Only the bytes of the NORMAL accessor change. The positions, UVs, skin, animations and textures are
carried over byte for byte, so the output stays compatible with every other repair step.
"""

import argparse

import numpy as np

from glb_rig import NCOMP, read_accessor, read_glb

JSON_CHUNK = 0x4E4F534A
BIN_CHUNK = 0x004E4942


def write_glb(path, doc_bytes, binary):
    import struct

    doc_bytes += b" " * ((4 - len(doc_bytes) % 4) % 4)
    binary = bytes(binary) + b"\0" * ((4 - len(binary) % 4) % 4)
    body = struct.pack("<II", len(doc_bytes), JSON_CHUNK) + doc_bytes
    body += struct.pack("<II", len(binary), BIN_CHUNK) + binary
    with open(path, "wb") as handle:
        handle.write(struct.pack("<III", 0x46546C67, 2, 12 + len(body)))
        handle.write(body)


def weld(positions, normals):
    """Group index per vertex: same position and old normals no more than 90 degrees apart."""
    span = float(np.ptp(positions, axis=0).max())
    keys = np.round(positions / (span * 1e-5)).astype(np.int64)
    _, by_position = np.unique(keys, axis=0, return_inverse=True)
    by_position = by_position.reshape(-1)
    group = np.arange(len(positions))
    order = np.argsort(by_position, kind="stable")
    sorted_keys = by_position[order]
    starts = np.flatnonzero(np.r_[True, sorted_keys[1:] != sorted_keys[:-1]])
    ends = np.r_[starts[1:], len(order)]
    for start, end in zip(starts, ends):
        if end - start < 2:
            continue
        members = order[start:end]
        for index in members:
            for leader in members:
                if leader >= index:
                    break
                if group[leader] == leader and normals[leader] @ normals[index] > 0.0:
                    group[index] = leader
                    break
    _, group = np.unique(group, return_inverse=True)
    return group.reshape(-1)


def normalise(vectors):
    length = np.linalg.norm(vectors, axis=1, keepdims=True)
    return vectors / np.maximum(length, 1e-12)


def smooth_normals(positions, triangles, group, rounds):
    count = group.max() + 1
    corner = positions[triangles]
    face = np.cross(corner[:, 1] - corner[:, 0], corner[:, 2] - corner[:, 0])
    summed = np.zeros((count, 3))
    for column in range(3):
        np.add.at(summed, group[triangles[:, column]], face)
    welded = normalise(summed)
    edges = group[np.concatenate([triangles[:, [0, 1]], triangles[:, [1, 2]], triangles[:, [2, 0]]])]
    edges = np.unique(np.sort(edges, axis=1), axis=0)
    edges = edges[edges[:, 0] != edges[:, 1]]
    for _ in range(rounds):
        neighbours = np.zeros_like(welded)
        np.add.at(neighbours, edges[:, 0], welded[edges[:, 1]])
        np.add.at(neighbours, edges[:, 1], welded[edges[:, 0]])
        # Keep half of each normal so thin features do not flatten out.
        welded = normalise(welded + normalise(neighbours))
    return welded[group]


def head_weight(doc, binary, primitive, head_bone):
    names = [doc["nodes"][joint].get("name", "") for joint in doc["skins"][0]["joints"]]
    if head_bone not in names:
        return None
    head = names.index(head_bone)
    joints = read_accessor(doc, binary, primitive["attributes"]["JOINTS_0"]).astype(np.int64)
    weights = read_accessor(doc, binary, primitive["attributes"]["WEIGHTS_0"]).astype(np.float64)
    weights /= np.maximum(weights.sum(axis=1, keepdims=True), 1e-12)
    return (weights * (joints == head)).sum(axis=1)


def ellipsoid_normals(positions, weight):
    core = positions[weight > 0.9]
    low = np.percentile(core, 5, axis=0)
    high = np.percentile(core, 95, axis=0)
    centre = (low + high) * 0.5
    radii = np.maximum((high - low) * 0.5, 1e-6)
    # Gradient of (p - c)^2 / r^2, the outward normal of the ellipsoid through each point.
    return normalise((positions - centre) / (radii * radii)), centre, radii


def main(source, destination, head_bone, head_blend, rounds):
    doc, binary = read_glb(source)
    binary = bytearray(binary)
    for mesh in doc["meshes"]:
        for primitive in mesh["primitives"]:
            attributes = primitive["attributes"]
            positions = read_accessor(doc, binary, attributes["POSITION"]).astype(np.float64)
            old = normalise(read_accessor(doc, binary, attributes["NORMAL"]).astype(np.float64))
            triangles = read_accessor(doc, binary, primitive["indices"]).reshape(-1, 3)
            group = weld(positions, old)
            normals = smooth_normals(positions, triangles.astype(np.int64), group, rounds)
            # A vertex whose smooth normal turned past 90 degrees sits on a crease that welding
            # could not tell apart (a fold of cloth). It keeps its old normal.
            flipped = np.einsum("ij,ij->i", normals, old) < 0.0
            normals[flipped] = old[flipped]
            report = "%d vertices, %d welded groups, %d kept" % (
                len(positions),
                group.max() + 1,
                flipped.sum(),
            )
            weight = head_weight(doc, binary, primitive, head_bone) if head_bone else None
            if weight is not None and (weight > 0.9).any():
                sphere, centre, radii = ellipsoid_normals(positions, weight)
                blend = (np.clip(weight, 0.0, 1.0) * head_blend)[:, None]
                bent = normalise(normals * (1.0 - blend) + sphere * blend)
                # Never bend a normal round to the back of its surface.
                keep = np.einsum("ij,ij->i", bent, normals) > 0.2
                normals[keep] = bent[keep]
                report += ", head of %d vertices bent towards an ellipsoid at %s, radii %s" % (
                    (weight > 0.5).sum(),
                    np.round(centre, 3).tolist(),
                    np.round(radii, 3).tolist(),
                )
            accessor = doc["accessors"][attributes["NORMAL"]]
            assert accessor["componentType"] == 5126 and NCOMP[accessor["type"]] == 3
            view = doc["bufferViews"][accessor["bufferView"]]
            base = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
            stride = view.get("byteStride", 12)
            target = np.ndarray(
                shape=(accessor["count"], 3),
                dtype="<f4",
                buffer=binary,
                offset=base,
                strides=(stride, 4),
            )
            target[:] = normals.astype(np.float32)
            print(report)
    import json

    write_glb(destination, json.dumps(doc, separators=(",", ":")).encode("utf-8"), binary)
    print("wrote %s" % destination)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("source")
    parser.add_argument("destination")
    parser.add_argument("--head-bone", default="Head", help="empty to leave the head as it is")
    parser.add_argument("--head-blend", type=float, default=0.6)
    parser.add_argument("--smooth", type=int, default=3)
    args = parser.parse_args()
    main(args.source, args.destination, args.head_bone, args.head_blend, args.smooth)
