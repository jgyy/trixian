# Xianxia Ascension

A 3D xianxia cultivation prototype built in Godot 4.7. The valley, buildings, spirit stones and
characters are generated from text prompts with the Tripo CLI. The characters are rigged and carry
preset animations, and you play as a female cultivator.

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

## Features

- **Explore** the Azure Cloud Sect valley in third person, with a mouse-look camera and a
  scroll-wheel zoom.
- **Cultivate.** Meditate to gather qi and break through five realms. Each breakthrough costs
  twice the qi of the one before.
- **Fight** demon wolves with sword strikes that hit in a cone in front of you. Wolves flinch when
  hit and lunge when they strike.
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
godot --headless --path . --script res://tests/run_tests.gd   # 45 headless checks
pip install "gdtoolkit==4.5.0"
gdlint scripts tests tools
gdformat --check scripts tests tools
```

CI runs the same lint and test steps on every pull request. The workflow is in
`.github/workflows/ci.yml`.

## Generating assets with Tripo

`tools/generate_assets.sh` regenerates the models with the Tripo CLI, including the rigging and
animation steps. `tools/rebake_textures.py` then re-unwraps each model's UVs and moves its textures
into the new layout, which removes the stretched texture islands Tripo's own unwrap produces.
`tools/tune_character_materials.py` sets the characters' material factors so they read as cloth and
skin rather than clay, and `tools/carve_hall_doorway.py` opens the sect hall's east doorway. See
[docs/asset-pipeline.md](docs/asset-pipeline.md) for the prompts, credit costs, the rebake steps
and the 2048 px texture export.

## Project layout

```
assets/models/       Tripo GLB models (rigged, 2048 px textures) and their Godot import sidecars
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
