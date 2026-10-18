#!/usr/bin/env python3
"""Re-unwraps a Tripo GLB and transfers its textures into the new UV layout.

usage: rebake.py IN.glb OUT.glb

Tripo's auto-unwrap splits clothing and skin into many small, badly stretched islands. This
script unwraps the same triangles with xatlas (stretch-minimising charts, 8 px padding), then
moves the baked maps across: each triangle keeps its identity, so the old UV of any texel is the
barycentric blend of the triangle's old corner UVs. Normal maps are converted through the old
and new tangent frames so their detail keeps its direction. Skins, animations and everything
else in the GLB are carried over untouched.
"""

import copy
import io
import json
import struct
import sys

import numpy as np
import xatlas
from PIL import Image, ImageFilter

ATLAS_SIZE = 2048
MAP_SIZE = 1024
PADDING = 4
# Tripo's normal bakes are speckled at 512 px. Blurring them keeps the broad folds and
# drops the grain that reads as garbage up close.
NORMAL_BLUR_RADIUS = 2.0
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
    world = (
        decoded[:, :1] * tri_old_t
        + decoded[:, 1:2] * tri_old_b
        + decoded[:, 2:3] * tri_normal
    )
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


def bake_maps(doc, binary, corner_old_uv, corner_new_uv, corner_pos, mesh_texture_indices):
    base_texture = read_image(doc, binary, mesh_texture_indices["base"])
    normal_texture = read_image(doc, binary, mesh_texture_indices["normal"])
    mr_texture = read_image(doc, binary, mesh_texture_indices["mr"])
    old_frames = tangent_frames(corner_pos, corner_old_uv)
    new_frames = tangent_frames(corner_pos, corner_new_uv)

    # Base colour at the full atlas resolution.
    texels, tris, weights = rasterise(corner_new_uv, ATLAS_SIZE)
    uv_old = texel_old_uv(weights, corner_old_uv, tris)
    base = np.full((ATLAS_SIZE * ATLAS_SIZE, 3), 0.5)
    mask = np.zeros(ATLAS_SIZE * ATLAS_SIZE, dtype=bool)
    base[texels] = sample_bilinear(base_texture, uv_old)
    mask[texels] = True
    base = dilate(base.reshape(ATLAS_SIZE, ATLAS_SIZE, 3), mask.reshape(ATLAS_SIZE, ATLAS_SIZE), 16)

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
        original = doc["accessors"][primitive["attributes"][name]]
        extra = {}
        if name == "POSITION":
            extra = {"min": data.min(axis=0).tolist(), "max": data.max(axis=0).tolist()}
        if original.get("normalized"):
            extra["normalized"] = True
        attributes[name] = add_accessor(
            data, original["componentType"], original["type"], extra, ARRAY_BUFFER
        )
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


def main(source, destination):
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

    atlas = xatlas.Atlas()
    atlas.add_mesh(positions, indices, normals)
    chart_options = xatlas.ChartOptions()
    pack_options = xatlas.PackOptions()
    pack_options.resolution = ATLAS_SIZE
    pack_options.padding = PADDING
    pack_options.bilinear = True
    atlas.generate(chart_options, pack_options)
    vmap, new_indices, new_uv = atlas.get_mesh(0)
    if not np.array_equal(vmap[new_indices], indices):
        raise RuntimeError("xatlas changed triangle order; transfer needs a remap")
    print(
        "  atlas %dx%d, charts %d, utilisation %.2f"
        % (atlas.width, atlas.height, atlas.chart_count, atlas.utilization)
    )

    corner_old_uv = old_uv[indices]
    corner_new_uv = new_uv[new_indices].astype(np.float64)
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
    new_attributes = {
        "POSITION": positions[vmap],
        "NORMAL": normals[vmap],
        "TEXCOORD_0": new_uv.astype(np.float32),
    }
    if skinned:
        new_attributes["JOINTS_0"] = joints[vmap]
        new_attributes["WEIGHTS_0"] = weights[vmap]
    replacements = {
        "old_accessors": set(attrs.values()) | {primitive["indices"]},
        "attributes": new_attributes,
        "indices": new_indices,
        "images": images,
    }
    mesh_views = {
        doc["accessors"][index]["bufferView"]
        for index in replacements["old_accessors"]
    } | {doc["images"][index]["bufferView"] for index in range(len(doc["images"]))}
    write_glb(destination, doc, binary, replacements, mesh_views)
    print("  wrote %s (%d vertices, %d triangles)" % (destination, len(vmap), len(new_indices)))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
