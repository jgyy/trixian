#!/usr/bin/env bash
# Regenerates the Tripo models used in the valley and optimises them for Godot.
#
# Requires the tripo CLI (`npm install -g tripo-cli`) and an authenticated account (`tripo login`).
# Generating costs credits: about 20 per text-to-model and 10 per optimised convert.
#
#   tools/generate_assets.sh                # generate every asset
#   tools/generate_assets.sh elder          # generate a single asset
#   DRY_RUN=1 tools/generate_assets.sh      # validate every prompt; spends no credits
set -euo pipefail

cd "$(dirname "$0")/.."
OUT_DIR="assets/models"
WORK_DIR="${WORK_DIR:-.tripo-work}"

# name | prompt | extra tripo make arguments
ASSETS=(
	"hero|xianxia cultivator hero in flowing white and blue robes, holding a sword, full body, game character, T-pose|-p texture_quality=detailed"
	"elder|xianxia sect elder, old Taoist master with long white beard, grey flowing robes, holding a wooden staff, full body, game character, T-pose|"
	"demon_wolf|xianxia demonic spirit beast, fierce wolf with glowing red eyes and black qi aura, full body, game creature|"
	"sect_hall|xianxia Chinese sect temple hall, multi-tiered curved tile roof, red wooden pillars, stone base, single building, game environment asset|"
	"spirit_tree|ancient spirit peach tree with pink blossoms, twisted trunk, stylized game environment asset|"
	"jade_rock|glowing jade spirit stone, green crystal rock formation emitting qi energy, game prop|"
)

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

	echo "opt   $name"
	tripo model convert --yes --no-open --quiet --format GLTF --texture-size 1024 \
		--face-limit 30000 -o "$work/optimised" "$task_id" >/dev/null

	mkdir -p "$OUT_DIR"
	cp "$(find "$work/optimised" -name model.glb | head -n 1)" "$OUT_DIR/$name.glb"
	echo "saved $OUT_DIR/$name.glb"
}

only="${1:-}"
for entry in "${ASSETS[@]}"; do
	IFS='|' read -r name prompt extra <<<"$entry"
	if [[ -z "$only" || "$only" == "$name" ]]; then
		generate "$name" "$prompt" "$extra"
	fi
done
