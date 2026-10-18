#!/usr/bin/env python3
"""Opens the doorway in the sect hall's east wall by removing the wall triangles in a box.

usage: carve_hall_doorway.py IN.glb OUT.glb

The hall is fitted to 18 m the same way ModelUtils.fit_to_height fits it in Godot, so the box below
is in the hall's own space (origin at the centre of its footprint, y = 0 on the ground). Every
triangle whose centre is inside the box is removed, including the corridor floor there, so the
hall's main.gd ramp can replace it. The ground inside the cella is below the box and stays. The
visible mesh and the collision both come from the carved GLB, so the doorway is open in both.

Requires the rebake helpers: pip install xatlas numpy pillow
"""

import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rebake_textures as rebake  # noqa: E402

HALL_HEIGHT = 18.0
# The east wall of the cella, between the entry gallery and the inner room.
BOX_MIN = np.array([1.0, 1.5, -2.3])
BOX_MAX = np.array([2.2, 7.5, 1.3])


def main(source, destination):
    doc, binary = rebake.read_glb(source)
    primitive = doc["meshes"][0]["primitives"][0]
    attrs = primitive["attributes"]
    positions = rebake.read_accessor(doc, binary, attrs["POSITION"]).astype(np.float64)
    normals = rebake.read_accessor(doc, binary, attrs["NORMAL"]).astype(np.float32)
    uvs = rebake.read_accessor(doc, binary, attrs["TEXCOORD_0"]).astype(np.float32)
    indices = rebake.read_accessor(doc, binary, primitive["indices"]).astype(np.uint32).reshape(-1, 3)

    low = positions.min(axis=0)
    high = positions.max(axis=0)
    scale = HALL_HEIGHT / (high[1] - low[1])
    centre = np.array([(low[0] + high[0]) * 0.5, low[1], (low[2] + high[2]) * 0.5])
    corners = (positions[indices] - centre) * scale
    print(
        "  hall bounds x %.2f..%.2f  y %.2f..%.2f  z %.2f..%.2f"
        % (
            corners[..., 0].min(), corners[..., 0].max(),
            corners[..., 1].min(), corners[..., 1].max(),
            corners[..., 2].min(), corners[..., 2].max(),
        )
    )

    centroid = corners.mean(axis=1)
    drop = np.all((centroid >= BOX_MIN) & (centroid <= BOX_MAX), axis=1)
    print("  removed %d of %d triangles" % (int(drop.sum()), len(indices)))

    replacements = {
        "old_accessors": set(attrs.values()) | {primitive["indices"]},
        "attributes": {
            "POSITION": positions.astype(np.float32),
            "NORMAL": normals,
            "TEXCOORD_0": uvs,
        },
        "indices": indices[~drop],
        "images": {},
    }
    mesh_views = {doc["accessors"][index]["bufferView"] for index in replacements["old_accessors"]}
    rebake.write_glb(destination, doc, binary, replacements, mesh_views)
    print("  wrote %s" % destination)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
