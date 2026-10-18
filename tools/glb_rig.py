"""Reads, poses and rewrites the skeleton of a rigged GLB without touching its textures.

Shared by fix_character_rig.py and check_character_rig.py. Everything works on the glTF JSON and
binary chunks directly, so the images and the material come out byte for byte as they went in.
Quaternions are glTF order (x, y, z, w).
"""

import json
import struct

import numpy as np

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
JSON_CHUNK = 0x4E4F534A
BIN_CHUNK = 0x004E4942


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
        if chunk_type == JSON_CHUNK:
            doc = json.loads(chunk.decode("utf-8"))
        elif chunk_type == BIN_CHUNK:
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


class GlbWriter:
    """Collects accessors and views for a new binary chunk, then writes the GLB.

    Views and images the document still refers to are copied out of the old binary chunk, so
    anything that was replaced (old weights, old animations) drops out of the file.
    """

    def __init__(self, doc, binary):
        self.doc = doc
        self.old = binary
        self.blob = bytearray()
        self.views = []
        self.accessors = []
        self.view_map = {}

    def _append(self, data):
        while len(self.blob) % 4:
            self.blob.append(0)
        offset = len(self.blob)
        self.blob.extend(data)
        return offset

    def copy_view(self, index):
        if index not in self.view_map:
            view = self.doc["bufferViews"][index]
            start = view.get("byteOffset", 0)
            data = self.old[start : start + view["byteLength"]]
            new_view = {"buffer": 0, "byteLength": len(data), "byteOffset": self._append(data)}
            if "target" in view:
                new_view["target"] = view["target"]
            self.views.append(new_view)
            self.view_map[index] = len(self.views) - 1
        return self.view_map[index]

    def copy_accessor(self, index):
        accessor = dict(self.doc["accessors"][index])
        accessor["bufferView"] = self.copy_view(accessor["bufferView"])
        self.accessors.append(accessor)
        return len(self.accessors) - 1

    def add_accessor(self, data, component_type, kind, target=None, extra=None):
        data = np.ascontiguousarray(data, dtype=COMPONENT[component_type])
        raw = data.tobytes()
        view = {"buffer": 0, "byteLength": len(raw), "byteOffset": self._append(raw)}
        if target is not None:
            view["target"] = target
        self.views.append(view)
        accessor = {
            "bufferView": len(self.views) - 1,
            "byteOffset": 0,
            "componentType": component_type,
            "count": int(data.shape[0]),
            "type": kind,
        }
        if extra:
            accessor.update(extra)
        self.accessors.append(accessor)
        return len(self.accessors) - 1

    def write(self, path):
        doc = self.doc
        doc["accessors"] = self.accessors
        doc["bufferViews"] = self.views
        doc["buffers"] = [{"byteLength": len(self.blob)}]
        doc_bytes = json.dumps(doc, separators=(",", ":")).encode("utf-8")
        doc_bytes += b" " * ((4 - len(doc_bytes) % 4) % 4)
        bin_bytes = bytes(self.blob) + b"\0" * ((4 - len(self.blob) % 4) % 4)
        total = 12 + 8 + len(doc_bytes) + 8 + len(bin_bytes)
        with open(path, "wb") as handle:
            handle.write(struct.pack("<III", 0x46546C67, 2, total))
            handle.write(struct.pack("<II", len(doc_bytes), JSON_CHUNK))
            handle.write(doc_bytes)
            handle.write(struct.pack("<II", len(bin_bytes), BIN_CHUNK))
            handle.write(bin_bytes)


def quat_to_matrix(q):
    """(..., 4) glTF quaternions to (..., 3, 3) rotation matrices."""
    q = np.asarray(q, dtype=np.float64)
    q = q / np.linalg.norm(q, axis=-1, keepdims=True)
    x, y, z, w = q[..., 0], q[..., 1], q[..., 2], q[..., 3]
    matrix = np.empty(q.shape[:-1] + (3, 3))
    matrix[..., 0, 0] = 1 - 2 * (y * y + z * z)
    matrix[..., 0, 1] = 2 * (x * y - z * w)
    matrix[..., 0, 2] = 2 * (x * z + y * w)
    matrix[..., 1, 0] = 2 * (x * y + z * w)
    matrix[..., 1, 1] = 1 - 2 * (x * x + z * z)
    matrix[..., 1, 2] = 2 * (y * z - x * w)
    matrix[..., 2, 0] = 2 * (x * z - y * w)
    matrix[..., 2, 1] = 2 * (y * z + x * w)
    matrix[..., 2, 2] = 1 - 2 * (x * x + y * y)
    return matrix


def matrix_to_quat(matrix):
    """(..., 3, 3) rotation matrices to (..., 4) quaternions with w >= 0."""
    m = np.asarray(matrix, dtype=np.float64)
    flat = m.reshape(-1, 3, 3)
    out = np.empty((len(flat), 4))
    for index, r in enumerate(flat):
        trace = r[0, 0] + r[1, 1] + r[2, 2]
        if trace > 0:
            s = 2.0 * np.sqrt(trace + 1.0)
            q = [(r[2, 1] - r[1, 2]) / s, (r[0, 2] - r[2, 0]) / s, (r[1, 0] - r[0, 1]) / s, s / 4]
        elif r[0, 0] > r[1, 1] and r[0, 0] > r[2, 2]:
            s = 2.0 * np.sqrt(1.0 + r[0, 0] - r[1, 1] - r[2, 2])
            q = [s / 4, (r[0, 1] + r[1, 0]) / s, (r[0, 2] + r[2, 0]) / s, (r[2, 1] - r[1, 2]) / s]
        elif r[1, 1] > r[2, 2]:
            s = 2.0 * np.sqrt(1.0 + r[1, 1] - r[0, 0] - r[2, 2])
            q = [(r[0, 1] + r[1, 0]) / s, s / 4, (r[1, 2] + r[2, 1]) / s, (r[0, 2] - r[2, 0]) / s]
        else:
            s = 2.0 * np.sqrt(1.0 + r[2, 2] - r[0, 0] - r[1, 1])
            q = [(r[0, 2] + r[2, 0]) / s, (r[1, 2] + r[2, 1]) / s, s / 4, (r[1, 0] - r[0, 1]) / s]
        q = np.array(q)
        out[index] = q / np.linalg.norm(q) * (1.0 if q[3] >= 0 else -1.0)
    return out.reshape(m.shape[:-2] + (4,))


def axis_angle(axis, angle):
    """Rotation matrix about a unit [axis] by [angle] radians (right-handed)."""
    axis = np.asarray(axis, dtype=np.float64)
    axis = axis / np.linalg.norm(axis)
    x, y, z = axis
    c, s = np.cos(angle), np.sin(angle)
    t = 1 - c
    return np.array(
        [
            [t * x * x + c, t * x * y - s * z, t * x * z + s * y],
            [t * x * y + s * z, t * y * y + c, t * y * z - s * x],
            [t * x * z - s * y, t * y * z + s * x, t * z * z + c],
        ]
    )


class Rig:
    """A skinned mesh with its skeleton: rest pose, inverse bind matrices and vertex skin."""

    def __init__(self, doc, binary):
        self.doc = doc
        self.binary = binary
        nodes = doc["nodes"]
        count = len(nodes)
        self.names = [node.get("name", "node%d" % i) for i, node in enumerate(nodes)]
        self.parent = [-1] * count
        for index, node in enumerate(nodes):
            for child in node.get("children", []):
                self.parent[child] = index
        self.rest_t = np.array([node.get("translation", [0, 0, 0]) for node in nodes], float)
        self.rest_q = np.array([node.get("rotation", [0, 0, 0, 1]) for node in nodes], float)
        self.rest_s = np.array([node.get("scale", [1, 1, 1]) for node in nodes], float)
        self.order = self._topological_order()
        skin = doc["skins"][0]
        self.joints = list(skin["joints"])
        self.ibm = (
            read_accessor(doc, binary, skin["inverseBindMatrices"])
            .astype(np.float64)
            .reshape(-1, 4, 4)
            .transpose(0, 2, 1)
        )
        self.joint_of_node = {node: index for index, node in enumerate(self.joints)}
        primitive = doc["meshes"][0]["primitives"][0]
        attrs = primitive["attributes"]
        self.positions = read_accessor(doc, binary, attrs["POSITION"]).astype(np.float64)
        self.normals = read_accessor(doc, binary, attrs["NORMAL"]).astype(np.float64)
        self.tangents = (
            read_accessor(doc, binary, attrs["TANGENT"]).astype(np.float64)
            if "TANGENT" in attrs
            else None
        )
        self.skin_joints = read_accessor(doc, binary, attrs["JOINTS_0"]).astype(np.int64)
        self.skin_weights = read_accessor(doc, binary, attrs["WEIGHTS_0"]).astype(np.float64)
        if self.skin_weights.max() > 1.5:
            self.skin_weights /= 255.0 if self.skin_weights.max() <= 255 else 65535.0
        self.indices = (
            read_accessor(doc, binary, primitive["indices"]).astype(np.int64).reshape(-1, 3)
        )

    def _topological_order(self):
        order = []
        seen = set()

        def visit(index):
            if index in seen:
                return
            if self.parent[index] >= 0:
                visit(self.parent[index])
            seen.add(index)
            order.append(index)

        for index in range(len(self.parent)):
            visit(index)
        return order

    def find(self, name):
        return self.names.index(name)

    def rest_pose(self):
        """Local translation (N, 3) and rotation matrices (N, 3, 3) of every node."""
        return self.rest_t.copy(), quat_to_matrix(self.rest_q)

    def world_matrices(self, local_t, local_r):
        local = np.tile(np.eye(4), (len(local_t), 1, 1))
        local[:, :3, :3] = local_r * self.rest_s[:, None, :]
        local[:, :3, 3] = local_t
        world = np.empty_like(local)
        for index in self.order:
            parent = self.parent[index]
            world[index] = local[index] if parent < 0 else world[parent] @ local[index]
        return world

    def skin_matrices(self, world):
        return world[self.joints] @ self.ibm

    def deform(self, skin, weights=None, joints=None, positions=None):
        """Linear blend skinning. Uses the rig's own weights unless others are passed in."""
        weights = self.skin_weights if weights is None else weights
        joints = self.skin_joints if joints is None else joints
        positions = self.positions if positions is None else positions
        blended = np.einsum("vk,vkij->vij", weights, skin[joints])
        homogeneous = np.concatenate([positions, np.ones((len(positions), 1))], axis=1)
        return np.einsum("vij,vj->vi", blended, homogeneous)[:, :3]

    def triangle_stretch(self, deformed, positions=None, floor=0.004):
        """Largest ratio of a triangle's deformed edge to its rest edge, per triangle.

        Edges shorter than [floor] model units count as [floor] long, so the zero-area slivers
        Tripo leaves in its meshes do not read as infinitely stretched.
        """
        positions = self.positions if positions is None else positions
        rest = _edge_lengths(positions, self.indices)
        now = _edge_lengths(deformed, self.indices)
        return (now / np.maximum(rest, floor)).max(axis=1)


def _edge_lengths(points, tri):
    a, b, c = points[tri[:, 0]], points[tri[:, 1]], points[tri[:, 2]]
    return np.stack(
        [
            np.linalg.norm(a - b, axis=1),
            np.linalg.norm(b - c, axis=1),
            np.linalg.norm(c - a, axis=1),
        ],
        axis=1,
    )
