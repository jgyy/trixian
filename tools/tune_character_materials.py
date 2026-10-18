#!/usr/bin/env python3
"""Sets the PBR factors of a Tripo character GLB so its surfaces read as cloth and skin.

usage: tune_character_materials.py IN.glb OUT.glb [--roughness 0.55] [--metallic 0.0]

Tripo bakes a metal/roughness map that is almost fully rough (roughness about 0.9), and its
metallic channel is noisy, which turns cloth and skin into matte clay with dark metallic specks.
The maps are kept as they are. glTF multiplies each factor by its map channel, so the surface
roughness becomes roughness_factor * G and metallic becomes metallic_factor * B. Only the JSON
chunk changes, so the textures, the skin and the animations are carried over byte for byte.
"""

import argparse
import json
import struct

JSON_CHUNK = 0x4E4F534A
BIN_CHUNK = 0x004E4942


def read_chunks(path):
    with open(path, "rb") as handle:
        data = handle.read()
    _, _, length = struct.unpack_from("<III", data, 0)
    offset = 12
    chunks = []
    while offset < length:
        chunk_len, chunk_type = struct.unpack_from("<II", data, offset)
        chunks.append((chunk_type, data[offset + 8 : offset + 8 + chunk_len]))
        offset += 8 + chunk_len
    return chunks


def write_glb(path, chunks):
    body = b""
    for chunk_type, payload in chunks:
        body += struct.pack("<II", len(payload), chunk_type) + payload
    with open(path, "wb") as handle:
        handle.write(struct.pack("<III", 0x46546C67, 2, 12 + len(body)))
        handle.write(body)


def main(source, destination, roughness, metallic):
    chunks = read_chunks(source)
    patched = []
    for chunk_type, payload in chunks:
        if chunk_type == JSON_CHUNK:
            doc = json.loads(payload.decode("utf-8"))
            for material in doc.get("materials", []):
                pbr = material.setdefault("pbrMetallicRoughness", {})
                pbr["roughnessFactor"] = roughness
                pbr["metallicFactor"] = metallic
            text = json.dumps(doc, separators=(",", ":")).encode("utf-8")
            text += b" " * ((4 - len(text) % 4) % 4)
            payload = text
        patched.append((chunk_type, payload))
    write_glb(destination, patched)
    print("wrote %s (roughness %.2f, metallic %.2f)" % (destination, roughness, metallic))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("source")
    parser.add_argument("destination")
    parser.add_argument("--roughness", type=float, default=0.55)
    parser.add_argument("--metallic", type=float, default=0.0)
    args = parser.parse_args()
    main(args.source, args.destination, args.roughness, args.metallic)
