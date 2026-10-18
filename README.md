# Xianxia Ascension

A 3D xianxia cultivation prototype built in Godot 4.7. The valley, buildings, spirit stones and
characters are generated from text prompts with the Tripo CLI. The characters are rigged, and their
facing, skin weights and animation clips are repaired offline so they walk the right way, keep their
textures while they move and play clips that fit a game. Their textures are baked from Tripo's
full-size 4096 px model, with extra room for the head, so faces stay sharp up close. You play as a female cultivator.

![Valley overview](docs/screenshots/valley_overview.png)

## Screenshots

| Third-person view at the sect gate | Sect hall |
| --- | --- |
| ![Third-person view](docs/screenshots/third_person_spawn.png) | ![Sect hall](docs/screenshots/sect_hall.png) |

| Sect hall entrance |
| --- |
| ![Sect hall entrance](docs/screenshots/sect_hall_entrance.png) |

| Meditating and gathering qi |
| --- |
| ![Meditation](docs/screenshots/meditation_breakthrough.png) |

| Running | Sword strike |
| --- | --- |
| ![Running](docs/screenshots/player_running.png) | ![Sword strike](docs/screenshots/player_slash.png) |

| A demon wolf charging the cultivator |
| --- |
| ![Wolf charge](docs/screenshots/wolf_charge.png) |

### Faces, before and after the texture bake

![The cultivator's face in the valley, before and after](docs/texture-fix/in_game_face.png)

Left: the 2048 px export, where the face was a 100 px patch of the atlas. Right: baked from Tripo's
full model into a layout that gives the head nine times the area per unit of surface. The
[asset pipeline](docs/asset-pipeline.md#sharp-faces-bake-from-the-full-model) explains why the old
face was soft and how the bake works. The new shot is `player_face_closeup.png`, taken with a
camera closer than the game's zoom goes.

### Animation, before and after the rig repair

![Tripo's walk against the repaired run](docs/rig-fix/before_after_player.png)

Top: Tripo's own `walk`, in profile and torn by its skin weights. Bottom: the repaired `run`. The
[asset pipeline](docs/asset-pipeline.md#rig-repair) explains what was wrong and how it was fixed.

## Features

- **Explore** the Azure Cloud Sect valley in third person, with a mouse-look camera and a
  scroll-wheel zoom.
- **Cultivate.** Meditate to gather qi and break through five realms. Each breakthrough costs
  twice the qi of the one before.
- **Fight** demon wolves with sword strikes that hit in a cone in front of you. The cut lands when
  the blade does, a quarter of a second after the key press. Wolves charge, flinch when hit and
  bite.
- **Quest.** Elder Wen sends you after two wolves and rewards you with qi when you return. Wolves
  slain before you accept the quest count towards it.
- **Meet the sect.** Disciple Lin at the gate shares advice when you talk to her.
- **Enter the sect hall.** The hall is twice the height of the other buildings. Climb the stairs on
  its east side, walk along the entry gallery and drop into the cella. Its walls, pillars and
  stairs block you exactly where they are drawn.

## Controls

| Action | Keys |
| --- | --- |
| Move | `W` `A` `S` `D` or arrow keys |
| Look | Mouse (captured on start; `Esc` releases it, a click recaptures it) |
| Zoom camera | Mouse wheel |
| Jump | `Space` |
| Attack | `J` or left mouse button |
| Meditate (toggle) | `F` |
| Break through | `B` |
| Talk to an NPC | `E` |

## Running the game

Requires Godot 4.7 or newer. The project is tested with 4.7.2.

```bash
godot --headless --path . --import   # first time: import the GLB models
godot --path .                       # launch the game
```

## Tests and lint

```bash
godot --headless --path . --import
godot --headless --path . --script res://tests/run_tests.gd   # 93 headless checks
pip install "gdtoolkit==4.5.0"
gdlint scripts tests tools
gdformat --check scripts tests tools
```

CI runs the same lint and test steps on every pull request. The workflow is in
`.github/workflows/ci.yml`.

## Generating assets with Tripo

`tools/generate_assets.sh` regenerates the models with the Tripo CLI, including the rigging and
animation steps. `tools/rebake_textures.py` then re-unwraps each model's UVs, which removes the
stretched texture islands Tripo's own unwrap produces. For the characters it also gives the head
nine times the texture area and bakes every map from Tripo's full-size 4096 px model in Blender
(`tools/bake_hires_maps.py`), so faces stay sharp when you zoom in. `tools/repair_character.sh NAME`
runs the whole character chain.
`tools/tune_character_materials.py` sets the characters' material factors so they read as cloth and
skin rather than clay, and `tools/fix_character_rig.py` turns each character to face +Z, re-skins
its pinned vertices, smooths the weights that tear and replaces Tripo's preset clips with short
authored ones. `tools/carve_hall_doorway.py` opens the sect hall's east doorway. See
[docs/asset-pipeline.md](docs/asset-pipeline.md) for the prompts, credit costs, the rebake steps
and the texture bake.

## Project layout

```
assets/models/       Tripo GLB models (rigged, 4096 px character textures) and their Godot import sidecars
scenes/main.tscn     root scene; builds the valley from code
scripts/core/        cultivation rules, quest rules, animation driver, model fitting, input
scripts/player/      the cultivator (player)
scripts/enemies/     spirit beast enemy AI
scripts/npc/         NPC interaction base
scripts/world/       procedural valley decoration
scripts/ui/          HUD
tests/               headless test runner
tools/               asset generation, UV rebake and screenshot capture scripts
docs/                architecture, asset pipeline, screenshots
```

## Documentation

- [Architecture](docs/architecture.md): scene tree, systems, quest and animation state diagrams,
  and combat sequence.
- [Asset pipeline](docs/asset-pipeline.md): Tripo workflow, rigging, asset table and previews.

## License

See [LICENSE](LICENSE).
