#!/usr/bin/env python3
"""Re-unwraps a Tripo GLB and moves its textures into the new UV layout.

usage: rebake_textures.py IN.glb OUT.glb [SOURCE.glb]

Tripo's auto-unwrap splits clothing and skin into many small, badly stretched islands. This
script unwraps the same triangles with xatlas (stretch-minimising charts, padded), giving the head
HEAD_SCALE times the linear texel density of the body so that faces stay sharp up close. Skins,
animations and everything else in the GLB are carried over untouched.

Without SOURCE.glb the baked maps are moved across: each triangle keeps its identity, so the old
UV of any texel is the barycentric blend of the triangle's old corner UVs. That can only keep the
detail the 2048 px export already has, so it is used for props.

With SOURCE.glb, Tripo's full-resolution model (1.4 million triangles, 4096 px textures), the maps
are baked from it instead, by tools/bake_hires_maps.py running in Blender. Every texel then
gets the detail of the full model and the head's extra density turns into real sharpness.
"""

import copy
import io
import json
import os
import shutil
import struct
import subprocess
import sys
import tempfile

import numpy as np
import xatlas
from PIL import Image, ImageFilter

ATLAS_SIZE = 2048
HIRES_ATLAS_SIZE = 4096
HIRES_NORMAL_SIZE = 2048
HIRES_MR_SIZE = 512
MAP_SIZE = 1024
PADDING = 4
HIRES_PADDING = 8
# Linear texel density of the head relative to the body. 3 gives the head nine times the area
# per unit of surface and about a third of the atlas.
HEAD_SCALE = 3.0
# Tripo's normal bakes are speckled at 512 px. Blurring them keeps the broad folds and
# drops the grain that reads as garbage up close.
NORMAL_BLUR_RADIUS = 2.0
# The source bake comes from a real 1.4M-triangle surface, so it only needs a touch of smoothing.
HIRES_NORMAL_BLUR_RADIUS = 0.6
# See guard_base: the largest average colour difference, in 0..1, a baked triangle may have.
GUARD_LIMIT = 0.2
# See fix_tiny_triangles: a triangle covering fewer texels than this takes its neighbour's colour.
TINY_TEXELS = 2
WELD_EPSILON = 1e-5
COMPONENT = {
    5120: np.int8,
    5121: np.uint8,
    5122: np.int16,
    5123: np.uint16,
    5125: np.uint32,
    5126: np.float32,
}
NCOMP = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}
ARRAY_BUFFER = 34962
ELEMENT_ARRAY_BUFFER = 34963


def read_glb(path):
    with open(path, "rb") as handle:
        data = handle.read()
    _, _, length = struct.unpack_from("<III", data, 0)
    offset = 12
    doc = None
    binary = b""
    while offset < length:
        chunk_len, chunk_type = struct.unpack_from("<II", data, offset)
        chunk = data[offset + 8 : offset + 8 + chunk_len]
        if chunk_type == 0x4E4F534A:
            doc = json.loads(chunk.decode("utf-8"))
        elif chunk_type == 0x004E4942:
            binary = chunk
        offset += 8 + chunk_len
    return doc, binary


def read_accessor(doc, binary, index):
    accessor = doc["accessors"][index]
    view = doc["bufferViews"][accessor["bufferView"]]
    dtype = np.dtype(COMPONENT[accessor["componentType"]]).newbyteorder("<")
    width = NCOMP[accessor["type"]]
    base = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    stride = view.get("byteStride", dtype.itemsize * width)
    array = np.ndarray(
        shape=(accessor["count"], width),
        dtype=dtype,
        buffer=binary,
        offset=base,
        strides=(stride, dtype.itemsize),
    )
    return array.copy()


def read_image(doc, binary, index):
    image = doc["images"][index]
    view = doc["bufferViews"][image["bufferView"]]
    start = view.get("byteOffset", 0)
    raw = binary[start : start + view["byteLength"]]
    return np.asarray(Image.open(io.BytesIO(raw)).convert("RGB"), dtype=np.float64) / 255.0


def sample_bilinear(texture, uv):
    """Samples an HxWxC texture at Nx2 glTF UVs (v grows down the image)."""
    height, width = texture.shape[:2]
    x = uv[:, 0] * width - 0.5
    y = uv[:, 1] * height - 0.5
    x0 = np.floor(x).astype(np.int64)
    y0 = np.floor(y).astype(np.int64)
    fx = (x - x0)[:, None]
    fy = (y - y0)[:, None]
    xa = np.clip(x0, 0, width - 1)
    xb = np.clip(x0 + 1, 0, width - 1)
    ya = np.clip(y0, 0, height - 1)
    yb = np.clip(y0 + 1, 0, height - 1)
    top = texture[ya, xa] * (1 - fx) + texture[ya, xb] * fx
    bottom = texture[yb, xa] * (1 - fx) + texture[yb, xb] * fx
    return top * (1 - fy) + bottom * fy


def rasterise(corner_uv, size):
    """Returns (texel index, triangle index, barycentric weights) for every covered texel."""
    pixels = corner_uv * size
    texels = []
    triangles = []
    weights = []
    for tri in range(len(pixels)):
        p = pixels[tri]
        x0 = max(int(np.floor(p[:, 0].min())), 0)
        x1 = min(int(np.ceil(p[:, 0].max())), size - 1)
        y0 = max(int(np.floor(p[:, 1].min())), 0)
        y1 = min(int(np.ceil(p[:, 1].max())), size - 1)
        if x1 < x0 or y1 < y0:
            continue
        gx, gy = np.meshgrid(np.arange(x0, x1 + 1), np.arange(y0, y1 + 1))
        gx = gx.ravel()
        gy = gy.ravel()
        centre = np.stack([gx + 0.5, gy + 0.5], axis=1)
        e1 = p[1] - p[0]
        e2 = p[2] - p[0]
        delta = centre - p[0]
        den = e1[0] * e2[1] - e2[0] * e1[1]
        if abs(den) < 1e-12:
            continue
        b1 = (delta[:, 0] * e2[1] - e2[0] * delta[:, 1]) / den
        b2 = (e1[0] * delta[:, 1] - delta[:, 0] * e1[1]) / den
        b0 = 1.0 - b1 - b2
        inside = (b0 >= -1e-4) & (b1 >= -1e-4) & (b2 >= -1e-4)
        if not inside.any():
            continue
        texels.append(gy[inside] * size + gx[inside])
        triangles.append(np.full(int(inside.sum()), tri, dtype=np.int64))
        weights.append(np.stack([b0[inside], b1[inside], b2[inside]], axis=1))
    return np.concatenate(texels), np.concatenate(triangles), np.concatenate(weights)


def dilate(image, mask, passes):
    """Grows covered texels outwards so mip levels and bilinear taps never read empty texels."""
    image = image.copy()
    mask = mask.copy()
    for _ in range(passes):
        total = np.zeros_like(image)
        count = np.zeros(mask.shape, dtype=np.float64)
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)):
            shifted_image = shift(image, dy, dx)
            shifted_mask = shift(mask, dy, dx).astype(np.float64)
            total += shifted_image * shifted_mask[..., None]
            count += shifted_mask
        fill = (~mask) & (count > 0)
        image[fill] = total[fill] / count[fill][:, None]
        mask = mask | fill
    return image


def shift(array, dy, dx):
    """Value at (y + dy, x + dx) for every texel, edge-clamped."""
    height, width = array.shape[:2]
    pad = ((1, 1), (1, 1)) + ((0, 0),) * (array.ndim - 2)
    padded = np.pad(array, pad, mode="edge")
    return padded[1 + dy : 1 + dy + height, 1 + dx : 1 + dx + width]


def tangent_frames(corner_pos, corner_uv):
    """Per-triangle tangent (dP/du), bitangent and normal in glTF tangent-space convention.

    The bitangent points towards the top of the image (decreasing V), which is where the green
    channel of a glTF normal map points.
    """
    p0, p1, p2 = corner_pos[:, 0], corner_pos[:, 1], corner_pos[:, 2]
    edge1 = p1 - p0
    edge2 = p2 - p0
    du1 = corner_uv[:, 1, 0] - corner_uv[:, 0, 0]
    dv1 = corner_uv[:, 1, 1] - corner_uv[:, 0, 1]
    du2 = corner_uv[:, 2, 0] - corner_uv[:, 0, 0]
    dv2 = corner_uv[:, 2, 1] - corner_uv[:, 0, 1]
    det = du1 * dv2 - du2 * dv1
    det = np.where(np.abs(det) < 1e-12, 1.0, det)
    tangent = (dv2[:, None] * edge1 - dv1[:, None] * edge2) / det[:, None]
    bitangent = -((-du2[:, None] * edge1 + du1[:, None] * edge2) / det[:, None])
    normal = np.cross(edge1, edge2)
    normal /= np.maximum(np.linalg.norm(normal, axis=1), 1e-12)[:, None]
    tangent -= normal * np.sum(normal * tangent, axis=1)[:, None]
    tangent /= np.maximum(np.linalg.norm(tangent, axis=1), 1e-12)[:, None]
    bitangent -= normal * np.sum(normal * bitangent, axis=1)[:, None]
    bitangent -= tangent * np.sum(tangent * bitangent, axis=1)[:, None]
    bitangent /= np.maximum(np.linalg.norm(bitangent, axis=1), 1e-12)[:, None]
    return tangent, bitangent, normal


def transfer_normals(old_normal_map, old_frames, new_frames, texel_tri, texel_old_uv):
    old_t, old_b, normal = old_frames
    new_t, new_b, _ = new_frames
    decoded = sample_bilinear(old_normal_map, texel_old_uv) * 2.0 - 1.0
    decoded /= np.maximum(np.linalg.norm(decoded, axis=1), 1e-12)[:, None]
    tri_old_t = old_t[texel_tri]
    tri_old_b = old_b[texel_tri]
    tri_normal = normal[texel_tri]
    world = decoded[:, :1] * tri_old_t + decoded[:, 1:2] * tri_old_b + decoded[:, 2:3] * tri_normal
    out = np.stack(
        [
            np.sum(world * new_t[texel_tri], axis=1),
            np.sum(world * new_b[texel_tri], axis=1),
            np.sum(world * tri_normal, axis=1),
        ],
        axis=1,
    )
    out /= np.maximum(np.linalg.norm(out, axis=1), 1e-12)[:, None]
    return out * 0.5 + 0.5


def texel_old_uv(weights, corner_old_uv, texel_tri):
    tri_uv = corner_old_uv[texel_tri]
    return np.sum(weights[:, :, None] * tri_uv, axis=1)


def transfer_base(base_texture, corner_old_uv, corner_new_uv, size, raster=None):
    """Moves the base colour into the new layout at size x size.

    Returns the image, the mask of covered texels and the rasterisation, which can be passed back
    in to skip the slowest part of the work.
    """
    texels, tris, weights = raster or rasterise(corner_new_uv, size)
    uv_old = texel_old_uv(weights, corner_old_uv, tris)
    base = np.full((size * size, 3), 0.5)
    mask = np.zeros(size * size, dtype=bool)
    base[texels] = sample_bilinear(base_texture, uv_old)
    mask[texels] = True
    mask = mask.reshape(size, size)
    return dilate(base.reshape(size, size, 3), mask, 16), mask, (texels, tris, weights)


def bake_maps(doc, binary, corner_old_uv, corner_new_uv, corner_pos, mesh_texture_indices):
    base_texture = read_image(doc, binary, mesh_texture_indices["base"])
    normal_texture = read_image(doc, binary, mesh_texture_indices["normal"])
    mr_texture = read_image(doc, binary, mesh_texture_indices["mr"])
    old_frames = tangent_frames(corner_pos, corner_old_uv)
    new_frames = tangent_frames(corner_pos, corner_new_uv)

    # Base colour at the full atlas resolution.
    base, _, _ = transfer_base(base_texture, corner_old_uv, corner_new_uv, ATLAS_SIZE)

    # Normal and metal/roughness maps at half resolution.
    texels, tris, weights = rasterise(corner_new_uv, MAP_SIZE)
    uv_old = texel_old_uv(weights, corner_old_uv, tris)
    mask = np.zeros(MAP_SIZE * MAP_SIZE, dtype=bool)
    mask[texels] = True
    normal = np.tile(np.array([0.5, 0.5, 1.0]), (MAP_SIZE * MAP_SIZE, 1))
    normal[texels] = transfer_normals(normal_texture, old_frames, new_frames, tris, uv_old)
    normal = dilate(normal.reshape(MAP_SIZE, MAP_SIZE, 3), mask.reshape(MAP_SIZE, MAP_SIZE), 8)
    metal_rough = np.zeros((MAP_SIZE * MAP_SIZE, 3))
    metal_rough[texels] = sample_bilinear(mr_texture, uv_old)
    metal_rough = dilate(
        metal_rough.reshape(MAP_SIZE, MAP_SIZE, 3), mask.reshape(MAP_SIZE, MAP_SIZE), 8
    )
    return base, normal, metal_rough


def guard_base(baked, reference, raster, triangle_count):
    """Gives a triangle the reference colour when its baked colour disagrees with it.

    The reference is Tripo's own 2048 px export moved into the same layout: soft, but it always
    shows the outermost surface. The full model also has strands, hairpins and inner layers that
    sit under or in front of the game mesh, and a ray can land on one of them (white flecks in
    black hair, a dark strand across the forehead). Each of those paints a whole triangle the
    wrong colour, while real detail such as a pupil or a lash moves the average very little, so a
    triangle whose average colour is off by more than GUARD_LIMIT in any channel is taken from
    the reference. Returns the image and the share of triangles replaced.
    """
    texels, tris, _ = raster
    count = np.maximum(np.bincount(tris, minlength=triangle_count), 1)
    flat_baked = baked.reshape(-1, 3)[texels]
    flat_reference = reference.reshape(-1, 3)[texels]
    off = np.zeros(triangle_count, dtype=bool)
    for channel in range(3):
        mean_baked = np.bincount(tris, flat_baked[:, channel], minlength=triangle_count) / count
        mean_reference = (
            np.bincount(tris, flat_reference[:, channel], minlength=triangle_count) / count
        )
        off |= np.abs(mean_baked - mean_reference) > GUARD_LIMIT
    replaced = off[tris]
    result = baked.copy().reshape(-1, 3)
    result[texels[replaced]] = flat_reference[replaced]
    return result.reshape(baked.shape), off.mean()


def fix_tiny_triangles(vmap, indices, uv, positions, size):
    """Points triangles that cover less than a texel at their largest neighbour.

    A triangle smaller than a texel is baked with whatever colour the margin pulled in from the
    islands packed beside it. It is a sliver on the mesh, so it should look like its neighbour:
    it gets its own copies of its vertices, all placed at the middle of the neighbour's corners
    in the atlas. Returns the extended (vertex map, indices, UVs).
    """
    corner_uv = uv[indices].astype(np.float64)
    texels, tris, _ = rasterise(corner_uv, size)
    covered = np.bincount(tris, minlength=len(indices))
    tiny = np.nonzero(covered < TINY_TEXELS)[0]
    keys = np.round(positions[vmap][indices] / WELD_EPSILON).astype(np.int64)
    owners = {}
    for triangle in range(len(indices)):
        for corner in range(3):
            owners.setdefault(tuple(keys[triangle, corner]), []).append(triangle)
    new_corners = []
    new_uv = []
    for triangle in tiny:
        neighbours = {
            other
            for corner in range(3)
            for other in owners[tuple(keys[triangle, corner])]
            if covered[other] >= TINY_TEXELS
        }
        if not neighbours:
            continue
        best = max(neighbours, key=lambda other: covered[other])
        new_corners.append(triangle)
        new_uv.append(corner_uv[best].mean(axis=0))
    if not new_corners:
        return vmap, indices, uv
    new_corners = np.array(new_corners)
    first = len(vmap)
    vmap = np.concatenate([vmap, vmap[indices[new_corners]].ravel()])
    uv = np.concatenate([uv, np.repeat(np.array(new_uv, dtype=np.float32), 3, axis=0)])
    indices = indices.copy()
    indices[new_corners] = (first + np.arange(3 * len(new_corners))).reshape(-1, 3)
    print(
        "  %d triangles under %d texels now share a neighbour's colour"
        % (len(new_corners), TINY_TEXELS)
    )
    return vmap, indices, uv


def encode(image, fmt, quality=None, blur=0.0):
    pixels = np.clip(image * 255.0 + 0.5, 0, 255).astype(np.uint8)
    picture = Image.fromarray(pixels, "RGB")
    if blur > 0:
        picture = picture.filter(ImageFilter.GaussianBlur(blur))
    buffer = io.BytesIO()
    if fmt == "JPEG":
        picture.save(buffer, format=fmt, quality=quality)
    else:
        picture.save(buffer, format=fmt, optimize=True)
    return buffer.getvalue()


def write_glb(path, doc, binary, replacements, mesh_view_indexes):
    """Writes a GLB, dropping the old mesh buffers and rebuilding the binary chunk."""
    blob = bytearray()
    view_map = {}
    new_views = []

    def append(data):
        offset = len(blob)
        blob.extend(data)
        blob.extend(b"\x00" * ((4 - len(blob) % 4) % 4))
        return offset

    for index, view in enumerate(doc["bufferViews"]):
        if index in mesh_view_indexes:
            continue
        start = view.get("byteOffset", 0)
        data = binary[start : start + view["byteLength"]]
        new_view = copy.deepcopy(view)
        new_view["byteOffset"] = append(data)
        view_map[index] = len(new_views)
        new_views.append(new_view)

    accessor_map = {}
    new_accessors = []
    for index, accessor in enumerate(doc["accessors"]):
        if index in replacements["old_accessors"]:
            continue
        new_accessor = copy.deepcopy(accessor)
        new_accessor["bufferView"] = view_map[accessor["bufferView"]]
        accessor_map[index] = len(new_accessors)
        new_accessors.append(new_accessor)

    def add_view(data, target=None):
        view = {"buffer": 0, "byteLength": len(data), "byteOffset": append(data)}
        if target is not None:
            view["target"] = target
        new_views.append(view)
        return len(new_views) - 1

    def add_accessor(data, component_type, kind, extra=None, target=None):
        view_index = add_view(data.tobytes(), target)
        accessor = {
            "bufferView": view_index,
            "byteOffset": 0,
            "componentType": component_type,
            "count": int(data.shape[0]),
            "type": kind,
        }
        if extra:
            accessor.update(extra)
        new_accessors.append(accessor)
        return len(new_accessors) - 1

    primitive = doc["meshes"][0]["primitives"][0]
    attributes = {}
    for name, data in replacements["attributes"].items():
        extra = {}
        if name == "POSITION":
            extra = {"min": data.min(axis=0).tolist(), "max": data.max(axis=0).tolist()}
        if name in primitive["attributes"]:
            original = doc["accessors"][primitive["attributes"][name]]
            component_type, kind = original["componentType"], original["type"]
            if original.get("normalized"):
                extra["normalized"] = True
        else:
            component_type, kind = 5126, "VEC%d" % data.shape[1]
        attributes[name] = add_accessor(data, component_type, kind, extra, ARRAY_BUFFER)
    indices_accessor = add_accessor(
        replacements["indices"].astype(np.uint32).reshape(-1, 1),
        5125,
        "SCALAR",
        None,
        ELEMENT_ARRAY_BUFFER,
    )
    primitive["attributes"] = attributes
    primitive["indices"] = indices_accessor

    image_views = {}
    for index, image in enumerate(doc["images"]):
        if index in replacements["images"]:
            mime, data = replacements["images"][index]
            image_views[index] = add_view(data)
            image["bufferView"] = image_views[index]
            image["mimeType"] = mime
        else:
            image["bufferView"] = view_map[image["bufferView"]]

    for mesh in doc["meshes"]:
        for prim in mesh["primitives"]:
            if prim is primitive:
                continue
            raise RuntimeError("only single-primitive meshes are supported")

    for skin in doc.get("skins", []):
        if "inverseBindMatrices" in skin:
            skin["inverseBindMatrices"] = accessor_map[skin["inverseBindMatrices"]]
    for animation in doc.get("animations", []):
        for sampler in animation["samplers"]:
            sampler["input"] = accessor_map[sampler["input"]]
            sampler["output"] = accessor_map[sampler["output"]]
    for view in new_views:
        view.setdefault("buffer", 0)

    doc["accessors"] = new_accessors
    doc["bufferViews"] = new_views
    doc["buffers"][0]["byteLength"] = len(blob)

    doc_bytes = json.dumps(doc, separators=(",", ":")).encode("utf-8")
    doc_bytes += b" " * ((4 - len(doc_bytes) % 4) % 4)
    bin_bytes = bytes(blob)
    total = 12 + 8 + len(doc_bytes) + 8 + len(bin_bytes)
    with open(path, "wb") as handle:
        handle.write(struct.pack("<III", 0x46546C67, 2, total))
        handle.write(struct.pack("<II", len(doc_bytes), 0x4E4F534A))
        handle.write(doc_bytes)
        handle.write(struct.pack("<II", len(bin_bytes), 0x004E4942))
        handle.write(bin_bytes)


def head_triangles(doc, binary, attrs, indices):
    """Flags triangles with two or more corners owned mostly by a head joint."""
    if "JOINTS_0" not in attrs or not doc.get("skins"):
        return np.zeros(len(indices), dtype=bool)
    joint_names = [doc["nodes"][joint]["name"].lower() for joint in doc["skins"][0]["joints"]]
    is_head_joint = np.array(["head" in name for name in joint_names])
    joints = read_accessor(doc, binary, attrs["JOINTS_0"]).astype(np.int64)
    weights = read_accessor(doc, binary, attrs["WEIGHTS_0"]).astype(np.float64)
    dominant = joints[np.arange(len(joints)), weights.argmax(axis=1)]
    head_vertex = is_head_joint[dominant]
    return head_vertex[indices].sum(axis=1) >= 2


def pack(positions, normals, indices, size, padding):
    """Unwraps and packs with xatlas so that the atlas, padding included, fits size x size.

    Given only a resolution xatlas estimates its texel density and often overshoots (5300 px for a
    4096 px target). Shrinking the UVs afterwards would shrink the padding with them, so the
    density is measured from a first pass and the pack is repeated at a density that fits.
    """
    corner = positions[indices].astype(np.float64)
    surface = (
        0.5
        * np.linalg.norm(
            np.cross(corner[:, 1] - corner[:, 0], corner[:, 2] - corner[:, 0]), axis=1
        ).sum()
    )
    texels_per_unit = 0.0
    for attempt in range(8):
        atlas = xatlas.Atlas()
        atlas.add_mesh(positions, indices, normals)
        pack_options = xatlas.PackOptions()
        # With a density given, a resolution as well makes xatlas squeeze the charts into it and
        # overlap them, so it is only passed for the first, estimating pass.
        pack_options.resolution = 0 if texels_per_unit else size
        pack_options.padding = padding
        pack_options.bilinear = True
        pack_options.texels_per_unit = texels_per_unit
        atlas.generate(xatlas.ChartOptions(), pack_options)
        vmap, new_indices, uv = atlas.get_mesh(0)
        pixels = uv.astype(np.float64) * [atlas.width, atlas.height]
        extent = max(atlas.width, atlas.height)
        print(
            "  atlas %dx%d, charts %d, utilisation %.2f"
            % (atlas.width, atlas.height, atlas.chart_count, atlas.utilization)
        )
        if extent <= size:
            return vmap, new_indices, (pixels / size).astype(np.float32)
        corner_uv = pixels[new_indices]
        edge1 = corner_uv[:, 1] - corner_uv[:, 0]
        edge2 = corner_uv[:, 2] - corner_uv[:, 0]
        used = 0.5 * np.abs(edge1[:, 0] * edge2[:, 1] - edge1[:, 1] * edge2[:, 0]).sum()
        texels_per_unit = np.sqrt(used / surface) * size / extent * 0.97
    raise RuntimeError("could not fit the atlas into %d px" % size)


def unwrap(positions, normals, indices, head, size, padding):
    """Runs xatlas with the head enlarged; returns (vertex map, indices, UVs) for the mesh.

    The head triangles get their own copies of their vertices, scaled up about the head's centre,
    so xatlas sees them as a separate, larger surface and gives them more of the atlas. The seam
    falls where the head meets the body. Positions and normals of the real mesh are untouched.
    """
    count = len(positions)
    centre = positions[np.unique(indices[head])].mean(axis=0) if head.any() else 0.0
    head_positions = (centre + (positions - centre) * HEAD_SCALE).astype(np.float32)
    atlas_positions = np.concatenate([positions, head_positions])
    atlas_normals = np.concatenate([normals, normals])
    atlas_indices = indices + np.where(head, count, 0)[:, None].astype(np.uint32)

    used, compact = np.unique(atlas_indices, return_inverse=True)
    atlas_indices = compact.reshape(-1, 3).astype(np.uint32)

    atlas_positions = atlas_positions[used]
    atlas_normals = atlas_normals[used]
    vmap, new_indices, new_uv = pack(atlas_positions, atlas_normals, atlas_indices, size, padding)
    original = used % count
    if not np.array_equal(original[vmap[new_indices]], indices):
        raise RuntimeError("xatlas changed triangle order; transfer needs a remap")
    return original[vmap], new_indices, new_uv


def report_density(positions, indices, uv, head, size):
    """Prints texels per unit of surface for the head and the body, as a fraction of the body's."""
    corner_pos = positions[indices].astype(np.float64)
    surface = 0.5 * np.linalg.norm(
        np.cross(corner_pos[:, 1] - corner_pos[:, 0], corner_pos[:, 2] - corner_pos[:, 0]), axis=1
    )
    corner_uv = uv[indices].astype(np.float64) * size
    edge1 = corner_uv[:, 1] - corner_uv[:, 0]
    edge2 = corner_uv[:, 2] - corner_uv[:, 0]
    texels = 0.5 * np.abs(edge1[:, 0] * edge2[:, 1] - edge1[:, 1] * edge2[:, 0])
    body = texels[~head].sum() / surface[~head].sum()
    line = "  body %.0f texels per unit^2" % body
    if head.any():
        line += ", head %.1fx the body's (%.0f%% of the atlas)" % (
            texels[head].sum() / surface[head].sum() / body,
            100.0 * texels[head].sum() / (size * size),
        )
    print(line)


def bake_from_source(game_glb, source_glb, size):
    """Bakes colour, normal and roughness from the full-resolution model with Blender."""
    blender = os.environ.get("BLENDER") or shutil.which("blender")
    if not blender:
        raise RuntimeError("Blender is needed to bake from SOURCE.glb; set BLENDER or install it")
    script = os.path.join(os.path.dirname(os.path.abspath(__file__)), "bake_hires_maps.py")
    out_dir = os.path.join(os.path.dirname(os.path.abspath(game_glb)), "bake")
    command = [blender, "-b", "--python", script, "--", game_glb, source_glb, out_dir, str(size)]
    # Blender's embedded Python finds its standard library through PATH, so another python3.x
    # ahead of the system one (uv, pyenv) breaks it. Put Blender's own directory first.
    env = dict(
        os.environ,
        PATH=os.path.dirname(os.path.realpath(blender)) + os.pathsep + os.environ["PATH"],
    )
    subprocess.run(command, check=True, env=env)
    maps = {}
    for name in ("base", "normal", "roughness"):
        with Image.open(os.path.join(out_dir, name + ".png")) as picture:
            maps[name] = np.asarray(picture.convert("RGB"), dtype=np.float64) / 255.0
    return maps


def resize(image, size):
    if image.shape[0] == size:
        return image
    pixels = np.clip(image * 255.0 + 0.5, 0, 255).astype(np.uint8)
    picture = Image.fromarray(pixels, "RGB").resize((size, size), Image.LANCZOS)
    return np.asarray(picture, dtype=np.float64) / 255.0


def vertex_tangents(positions, normals, uv, indices):
    """Per-vertex glTF tangents (xyz, handedness w) from the UV layout.

    Each triangle's tangent is dP/du; a vertex takes the area-weighted sum over the triangles
    that use it, squared against its normal. Triangles with no UV area are left out. The
    bitangent is cross(normal, tangent) * w and points to the top of the image, as glTF wants.
    """
    corner_pos = positions[indices].astype(np.float64)
    corner_uv = uv[indices].astype(np.float64)
    tri_tangent, tri_bitangent, _ = tangent_frames(corner_pos, corner_uv)
    surface = 0.5 * np.linalg.norm(
        np.cross(corner_pos[:, 1] - corner_pos[:, 0], corner_pos[:, 2] - corner_pos[:, 0]), axis=1
    )
    edge1 = corner_uv[:, 1] - corner_uv[:, 0]
    edge2 = corner_uv[:, 2] - corner_uv[:, 0]
    mapped = np.abs(edge1[:, 0] * edge2[:, 1] - edge1[:, 1] * edge2[:, 0]) > 1e-14
    weight = np.where(mapped, surface, 0.0)[:, None]
    sum_tangent = np.zeros((len(positions), 3))
    sum_bitangent = np.zeros((len(positions), 3))
    for corner in range(3):
        np.add.at(sum_tangent, indices[:, corner], tri_tangent * weight)
        np.add.at(sum_bitangent, indices[:, corner], tri_bitangent * weight)
    normal = normals.astype(np.float64)
    normal /= np.maximum(np.linalg.norm(normal, axis=1), 1e-12)[:, None]
    tangent = sum_tangent - normal * np.sum(normal * sum_tangent, axis=1)[:, None]
    length = np.linalg.norm(tangent, axis=1)
    # A vertex whose triangles are all unmapped gets any direction square to its normal.
    spare = np.cross(normal, np.where(np.abs(normal[:, :1]) < 0.9, [[1.0, 0, 0]], [[0, 1.0, 0]]))
    tangent = np.where(length[:, None] > 1e-12, tangent, spare)
    tangent /= np.maximum(np.linalg.norm(tangent, axis=1), 1e-12)[:, None]
    handed = np.sum(np.cross(normal, tangent) * sum_bitangent, axis=1)
    sign = np.where(handed < 0.0, -1.0, 1.0)
    return np.concatenate([tangent, sign[:, None]], axis=1).astype(np.float32)


def tangent_space_normals(object_normals, raster, positions, normals, tangents, indices, size):
    """Re-expresses an object-space normal map in the mesh's own tangent frame.

    The frame at a texel is the one the engine builds from the file: the vertex normal and tangent
    interpolated across the triangle, squared up, with the bitangent from the handedness.
    Returns an RGB image of size x size, dilated into the margin, and the mean agreement between
    the baked normals and the mesh's interpolated normals, as a sanity check.
    """
    texels, tris, weights = raster
    corner = indices[tris]
    blend = weights[:, :, None]
    normal = np.sum(normals[corner].astype(np.float64) * blend, axis=1)
    normal /= np.maximum(np.linalg.norm(normal, axis=1), 1e-12)[:, None]
    tangent = np.sum(tangents[corner][:, :, :3].astype(np.float64) * blend, axis=1)
    tangent -= normal * np.sum(normal * tangent, axis=1)[:, None]
    tangent /= np.maximum(np.linalg.norm(tangent, axis=1), 1e-12)[:, None]
    handed = tangents[corner[:, 0], 3].astype(np.float64)[:, None]
    bitangent = np.cross(normal, tangent) * handed

    baked = object_normals.reshape(-1, 3)[texels] * 2.0 - 1.0
    # Blender's object space is glTF's with Y and Z swapped and one of them negated.
    baked = np.stack([baked[:, 0], baked[:, 2], -baked[:, 1]], axis=1)
    baked /= np.maximum(np.linalg.norm(baked, axis=1), 1e-12)[:, None]
    agreement = float(np.mean(np.sum(baked * normal, axis=1)))
    local = np.stack(
        [
            np.sum(baked * tangent, axis=1),
            np.sum(baked * bitangent, axis=1),
            np.sum(baked * normal, axis=1),
        ],
        axis=1,
    )
    local[:, 2] = np.maximum(local[:, 2], 0.05)
    local /= np.maximum(np.linalg.norm(local, axis=1), 1e-12)[:, None]
    image = np.tile(np.array([0.5, 0.5, 1.0]), (size * size, 1))
    mask = np.zeros(size * size, dtype=bool)
    image[texels] = local * 0.5 + 0.5
    mask[texels] = True
    image = dilate(image.reshape(size, size, 3), mask.reshape(size, size), 16)
    return image, agreement


def hires_images(maps, base, normal):
    """Packs the baked maps the way glTF wants them: roughness in green, metallic in blue."""
    normal = resize(normal, HIRES_NORMAL_SIZE)
    vectors = normal * 2.0 - 1.0
    vectors /= np.maximum(np.linalg.norm(vectors, axis=2, keepdims=True), 1e-6)
    normal = vectors * 0.5 + 0.5
    metal_rough = np.zeros((HIRES_MR_SIZE, HIRES_MR_SIZE, 3))
    metal_rough[..., 1] = resize(maps["roughness"], HIRES_MR_SIZE)[..., 0]
    return {
        0: ("image/jpeg", encode(normal, "JPEG", quality=95, blur=HIRES_NORMAL_BLUR_RADIUS)),
        1: ("image/jpeg", encode(base, "JPEG", quality=92)),
        2: ("image/png", encode(metal_rough, "PNG")),
    }


def main(source, destination, hires_source=None):
    doc, binary = read_glb(source)
    primitive = doc["meshes"][0]["primitives"][0]
    attrs = primitive["attributes"]
    positions = read_accessor(doc, binary, attrs["POSITION"]).astype(np.float32)
    normals = read_accessor(doc, binary, attrs["NORMAL"]).astype(np.float32)
    old_uv = read_accessor(doc, binary, attrs["TEXCOORD_0"]).astype(np.float64)
    skinned = "JOINTS_0" in attrs
    joints = read_accessor(doc, binary, attrs["JOINTS_0"]) if skinned else None
    weights = read_accessor(doc, binary, attrs["WEIGHTS_0"]) if skinned else None
    indices = read_accessor(doc, binary, primitive["indices"]).astype(np.uint32).reshape(-1, 3)

    head = head_triangles(doc, binary, attrs, indices)
    size = HIRES_ATLAS_SIZE if hires_source else ATLAS_SIZE
    padding = HIRES_PADDING if hires_source else PADDING
    vmap, new_indices, new_uv = unwrap(positions, normals, indices, head, size, padding)
    vmap, new_indices, new_uv = fix_tiny_triangles(vmap, new_indices, new_uv, positions, size)
    report_density(positions[vmap], new_indices, new_uv, head, size)

    new_tangents = None
    if hires_source:
        new_tangents = vertex_tangents(positions[vmap], normals[vmap], new_uv, new_indices)

    def replacements(images):
        new_attributes = {
            "POSITION": positions[vmap],
            "NORMAL": normals[vmap],
            "TEXCOORD_0": new_uv.astype(np.float32),
        }
        if hires_source:
            new_attributes["TANGENT"] = new_tangents
        if skinned:
            new_attributes["JOINTS_0"] = joints[vmap]
            new_attributes["WEIGHTS_0"] = weights[vmap]
        return {
            "old_accessors": set(attrs.values()) | {primitive["indices"]},
            "attributes": new_attributes,
            "indices": new_indices,
            "images": images,
        }

    mesh_views = {
        doc["accessors"][index]["bufferView"]
        for index in set(attrs.values()) | {primitive["indices"]}
    } | {doc["images"][index]["bufferView"] for index in range(len(doc["images"]))}
    corner_old_uv = old_uv[indices]
    corner_new_uv = new_uv[new_indices].astype(np.float64)

    if hires_source:
        with tempfile.TemporaryDirectory() as work:
            # Blender needs the new UV layout in a GLB; the maps in it are placeholders.
            blank = encode(np.full((4, 4, 3), 0.5), "PNG")
            placeholder = {i: ("image/png", blank) for i in range(3)}
            layout = os.path.join(work, "layout.glb")
            write_glb(layout, copy.deepcopy(doc), binary, replacements(placeholder), mesh_views)
            maps = bake_from_source(layout, hires_source, size)
        reference, _, raster = transfer_base(
            read_image(doc, binary, 1), corner_old_uv, corner_new_uv, size
        )
        base, replaced = guard_base(maps["base"], reference, raster, len(new_indices))
        print("  guard replaced the baked colour of %.1f%% of the triangles" % (100.0 * replaced))
        normal, agreement = tangent_space_normals(
            maps["normal"], raster, positions[vmap], normals[vmap], new_tangents, new_indices, size
        )
        print("  baked normals agree with the mesh normals by %.2f (mean dot)" % agreement)
        if agreement < 0.7:
            raise RuntimeError("baked normals do not line up with the mesh; check the axis swap")
        images = hires_images(maps, base, normal)
    else:
        corner_pos = positions[indices].astype(np.float64)
        base, normal, metal_rough = bake_maps(
            doc,
            binary,
            corner_old_uv,
            corner_new_uv,
            corner_pos,
            {"base": 1, "normal": 0, "mr": 2},
        )
        images = {
            0: ("image/png", encode(normal, "PNG", blur=NORMAL_BLUR_RADIUS)),
            1: ("image/jpeg", encode(base, "JPEG", quality=92)),
            2: ("image/png", encode(metal_rough, "PNG")),
        }
    write_glb(destination, doc, binary, replacements(images), mesh_views)
    print("  wrote %s (%d vertices, %d triangles)" % (destination, len(vmap), len(new_indices)))


if __name__ == "__main__":
    main(*sys.argv[1:4])
