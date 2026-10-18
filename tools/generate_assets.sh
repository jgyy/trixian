#!/usr/bin/env bash
# Regenerates the Tripo models used in the valley and optimises them for Godot.
#
# Requires the tripo CLI (`npm install -g tripo-cli`) and an authenticated account (`tripo login`).
# Generating costs credits: about 20 per text-to-model, 10 per convert, 25 per rig and 10 per
# animation preset.
#
#   tools/generate_assets.sh                # generate every asset
#   tools/generate_assets.sh elder          # generate a single asset
#   DRY_RUN=1 tools/generate_assets.sh      # validate every prompt; spends no credits
set -euo pipefail

cd "$(dirname "$0")/.."
OUT_DIR="assets/models"
WORK_DIR="${WORK_DIR:-.tripo-work}"
TEXTURE_SIZE=2048

# name | prompt | extra tripo make arguments
ASSETS=(
	"female_cultivator|xianxia female cultivator heroine, long black hair with silver hairpin, flowing pale jade and white robes, holding a sword, full body, game character, T-pose|-p texture_quality=detailed"
	"hero|xianxia cultivator hero in flowing white and blue robes, holding a sword, full body, game character, T-pose|-p texture_quality=detailed"
	"elder|xianxia sect elder, old Taoist master with long white beard, grey flowing robes, holding a wooden staff, full body, game character, T-pose|"
	"demon_wolf|xianxia demonic spirit beast, fierce wolf with glowing red eyes and black qi aura, full body, game creature|"
	"sect_hall|xianxia Chinese sect temple hall, multi-tiered curved tile roof, red wooden pillars, stone base, single building, game environment asset|"
	"spirit_tree|ancient spirit peach tree with pink blossoms, twisted trunk, stylized game environment asset|"
	"jade_rock|glowing jade spirit stone, green crystal rock formation emitting qi energy, game prop|"
)

# Characters that are rigged and animated. Biped characters use the v1.0 rig, whose
# preset:biped:* clips are the ones the game plays; the quadruped wolf uses the default v2.0 rig.
declare -A RIG_TYPE=(
	[female_cultivator]=biped
	[hero]=biped
	[elder]=biped
	[demon_wolf]=quadruped
)
declare -A ANIMATIONS=(
	[female_cultivator]="preset:biped:idle preset:biped:walk preset:biped:run preset:biped:slash preset:biped:hurt"
	[hero]="preset:biped:idle preset:biped:walk preset:biped:slash preset:biped:hurt"
	[elder]="preset:biped:idle preset:biped:walk preset:biped:greet_01"
	[demon_wolf]="preset:quadruped:walk"
)

# Imports the generated GLB and converts it to a 2048 px optimised GLB in the repo.
convert_final() {
	local name="$1" task_id="$2"
	echo "opt   $name"
	local out="$WORK_DIR/$name/optimised"
	tripo model convert --yes --no-open --quiet --format GLTF --texture-size "$TEXTURE_SIZE" \
		--face-limit 30000 -o "$out" "$task_id" >/dev/null
	mkdir -p "$OUT_DIR"
	cp "$(find "$out" -name model.glb | head -n 1)" "$OUT_DIR/$name.glb"
	echo "saved $OUT_DIR/$name.glb"
}

# Rigs a generated model, plays its preset animations in place and converts the result.
rig_and_animate() {
	local name="$1" generate_task="$2"
	local work="$WORK_DIR/$name"
	local rig_args=()
	if [[ "${RIG_TYPE[$name]}" == "biped" ]]; then
		rig_args=(-p model=rig-v1.0)
	fi

	echo "rig   $name"
	local rig_task
	rig_task=$(tripo anim rig --yes --no-open --quiet --json --rig-type "${RIG_TYPE[$name]}" \
		--out-format glb "${rig_args[@]}" -o "$work/rig" "$generate_task" | jq -r '.task_id')

	echo "anim  $name"
	local anim_task
	# shellcheck disable=SC2086
	anim_task=$(tripo anim retarget --yes --no-open --quiet --json --animate-in-place \
		--out-format glb -o "$work/anim" --animation ${ANIMATIONS[$name]} "$rig_task" |
		jq -r '.task_id')

	convert_final "$name" "$anim_task"
}

generate() {
	local name="$1" prompt="$2" extra="$3"
	local work="$WORK_DIR/$name"

	if [[ -n "${DRY_RUN:-}" ]]; then
		# shellcheck disable=SC2086
		tripo make --dry-run --name "$name" $extra "$prompt" >/dev/null
		echo "ok    $name (dry run)"
		return
	fi

	echo "make  $name"
	local task_id
	# shellcheck disable=SC2086
	task_id=$(tripo make --yes --no-open --quiet --json --name "$name" -o "$work/raw" $extra "$prompt" |
		jq -r '.source_task_id // .task_id')

	if [[ -n "${RIG_TYPE[$name]:-}" ]]; then
		rig_and_animate "$name" "$task_id"
	else
		convert_final "$name" "$task_id"
	fi
}

only="${1:-}"
for entry in "${ASSETS[@]}"; do
	IFS='|' read -r name prompt extra <<<"$entry"
	if [[ -z "$only" || "$only" == "$name" ]]; then
		generate "$name" "$prompt" "$extra"
	fi
done
