#!/usr/bin/env bash
# Runs the whole offline repair chain on one character that tools/generate_assets.sh produced.
#
#   tools/repair_character.sh female_cultivator           # a biped
#   tools/repair_character.sh demon_wolf quadruped        # the wolf
#
# It reads two GLBs from the work directory, both written by generate_assets.sh:
#   NAME/optimised   the 30,000-face, 2048 px export. Its mesh, rig and clips are the ones kept.
#   NAME/anim        the full-resolution animated model, about 1.4 million triangles and 4096 px
#                    textures. Every map is baked from it, so the face keeps its detail.
# and writes assets/models/NAME.glb after rebake_textures.py (UV layout with a dense head, then a
# Blender bake from the full model), tune_character_materials.py and fix_character_rig.py.
#
# Needs Blender (set BLENDER if it is not on PATH) and `pip install xatlas numpy pillow`. No
# Tripo account or credits are used.
set -euo pipefail

cd "$(dirname "$0")/.."
name="${1:?usage: tools/repair_character.sh NAME [biped|quadruped]}"
kind="${2:-biped}"
work="${WORK_DIR:-.tripo-work}/$name"
out="assets/models/$name.glb"

find_model() {
	find "$1" -name model.glb | head -n 1
}
game="$(find_model "$work/optimised")"
source="$(find_model "$work/anim")"
if [[ -z "$game" || -z "$source" ]]; then
	echo "missing $work/optimised or $work/anim; run tools/generate_assets.sh $name first" >&2
	exit 1
fi

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

echo "rebake  $name"
python3 tools/rebake_textures.py "$game" "$scratch/rebaked.glb" "$source"
echo "tune    $name"
python3 tools/tune_character_materials.py "$scratch/rebaked.glb" "$scratch/tuned.glb"
echo "rig     $name"
python3 tools/fix_character_rig.py "$scratch/tuned.glb" "$out" --kind "$kind"
echo "saved $out"
