# Tripo asset pipeline

Every 3D model in `assets/models/` was generated with the Tripo CLI from a text prompt. The
full-size GLBs that Tripo returns are about 45 MB each because of their 4K-class textures, so
each one is re-exported with 2048 px textures and at most 30,000 faces before it is committed.
The characters are also rigged and given preset animations.

## Flow

```mermaid
sequenceDiagram
    participant Dev as Developer
    participant CLI as tripo CLI
    participant API as Tripo API
    participant Repo as assets/models
    participant Godot as Godot importer

    Dev->>CLI: tripo make "prompt" --name NAME
    CLI->>API: text-to-model (v3.1, texture + PBR)
    API-->>CLI: source task, GLB about 45 MB at 4K textures
    alt static prop
        CLI->>API: model convert GLTF, 2048 px textures, 30k faces
        API-->>CLI: optimised GLB
    else character
        CLI->>API: anim rig (biped v1.0 or quadruped v2.0)
        API-->>CLI: rigged task
        CLI->>API: anim retarget, preset clips, animate in place
        API-->>CLI: animated task
        CLI->>API: model convert GLTF, 2048 px textures, 30k faces
        API-->>CLI: optimised animated GLB
    end
    CLI-->>Repo: copy as NAME.glb
    Repo->>Godot: import, embeds textures in the GLB
    Godot-->>Dev: preload() in main.gd, sized by ModelUtils
```

## Regenerating

`tools/generate_assets.sh` holds the exact prompts, rig types, animation presets and commands. It
needs the CLI and a logged-in account:

```bash
npm install -g tripo-cli
tripo login
tools/generate_assets.sh                 # every asset
tools/generate_assets.sh female_cultivator   # one asset
DRY_RUN=1 tools/generate_assets.sh       # validate prompts, spends no credits
```

Approximate credit costs from the runs that produced the committed models:

| Step | Credits |
| --- | --- |
| Text-to-model, standard texture | 20 |
| Text-to-model, `texture_quality=detailed` | 30 |
| Convert to GLTF at 2048 px | 10 |
| Rig (`anim rig`) | 25 |
| Each preset animation (`anim retarget`) | 10 |

## Rigging and animation

- Biped characters are rigged with the v1.0 rig (`-p model=rig-v1.0`). Its `preset:biped:*`
  clips are the ones the game uses: `idle`, `walk`, `run`, `slash`, `hurt` and `greet_01`.
- The wolf is quadruped and uses the default v2.0 rig. Its only usable preset here is
  `preset:quadruped:walk`. The v2.0 `idle`, `run`, `slash` and `hurt` presets were rejected for
  quadruped rigs, so the game freezes the walk cycle while the wolf is idle and flinches or lunges
  procedurally.
- Animations are baked in place (`--animate-in-place`), because the game drives movement.
- Each retarget call accepts at most five animations, and the CLI bills per animation.

## Assets

| Asset | In game | Prompt (abridged) | Tripo tasks | Credits |
| --- | --- | --- | --- | --- |
| `female_cultivator` | Player cultivator | xianxia female cultivator heroine, silver hairpin, pale jade robes, sword, T-pose | gen `444c69bb`, rig v1 `2493af58`, anim `e2c84f77` (idle, walk, run, slash, hurt), convert `33497c9d` | 30 + 25 + 50 + 10 |
| `hero` | Sect disciple Lin, NPC | cultivator in white and blue robes, sword, T-pose | gen `00bae8d2`, rig v1 `6c3b1aa4`, anim `8fde6909` (idle, walk, slash, hurt), convert `c6f3803d` | 30 + 25 + 40 + 10 |
| `elder` | Elder Wen, quest giver | old Taoist master, long white beard, staff, T-pose | gen `1d8e57ed`, rig v1 `87888fad`, anim `1b1b0663` (idle, walk, greet), convert `d472aa1d` | 20 + 25 + 30 + 10 |
| `demon_wolf` | Spirit beast enemy | demonic spirit wolf, red eyes, black qi aura | gen `a115f644`, rig v2 quadruped `2f2c99d6`, anim `eb0d61ed` (walk), convert `7c180481` | 20 + 25 + 10 + 10 |
| `sect_hall` | Scenery, solid | sect temple hall, curved tile roof, red pillars | gen `b79bd7b5`, convert `c7c2c3ef` | 20 + 10 |
| `spirit_tree` | Scenery | ancient spirit peach tree, pink blossoms | gen `757f9ef2`, convert `e71edc2f` | 20 + 10 |
| `jade_rock` | Scenery, solid, glowing | glowing jade spirit stone emitting qi | gen `7bfb9e5e`, convert `98751661` | 20 + 10 |

The first hero was exported as FBX with the `game-pc` preset (task `0655aeaa`, 5 credits). That
export was discarded in favour of GLB, so its cost is not included in the table. The 1024 px
versions of the static props were replaced by the 2048 px exports above, which cost 10 credits each.
Re-exporting the static props doubled every texture: the old maps were 256, 1024 and 512 px, and the
new ones are 512, 2048 and 1024 px.

## Previews

Tripo's own renders of each generated mesh:

| | | |
| --- | --- | --- |
| ![Female cultivator](tripo-previews/female_cultivator.webp) | ![Hero](tripo-previews/hero.webp) | ![Elder](tripo-previews/elder.webp) |
| female_cultivator | hero | elder |
| ![Demon wolf](tripo-previews/demon_wolf.webp) | ![Sect hall](tripo-previews/sect_hall.webp) | ![Spirit tree](tripo-previews/spirit_tree.webp) |
| demon_wolf | sect_hall | spirit_tree |
| ![Jade rock](tripo-previews/jade_rock.webp) | | |
| jade_rock | | |

## Using the models in Godot

- `ModelUtils.fit_to_height` scales each model to a target height in metres, so the source
  scale from Tripo does not matter.
- Solid props get a box collider built from the same measured bounds.
- Each model's front is aligned with `ModelUtils.FORWARD_OFFSET`. Change that constant if a
  new model faces the wrong way.
- `CharacterAnimator` looks up clips by name, ignoring any prefix. A clip named `preset:biped:walk`
  or `Armature|walk` both match `walk`.
- Textures are embedded in each GLB. The import setting `gltf/embedded_image_handling=2` keeps
  them inside the imported scene, so Godot does not extract texture files next to the models. An
  extracted texture that is deleted leaves a stale UID in the import cache, which produces the
  `invalid UID` warnings this setting avoids.
