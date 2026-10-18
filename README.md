# Xianxia Ascension

A 3D xianxia cultivation prototype built in Godot 4.7. The valley, buildings, spirit stones and
characters are generated from text prompts with the Tripo CLI.

![Valley overview](docs/screenshots/valley_overview.png)

## Screenshots

| Third-person view at the sect gate | Sect hall |
| --- | --- |
| ![Third-person view](docs/screenshots/third_person_spawn.png) | ![Sect hall](docs/screenshots/sect_hall.png) |

| Meditating and gathering qi |
| --- |
| ![Meditation](docs/screenshots/meditation_breakthrough.png) |

## Features

- **Explore** the Azure Cloud Sect valley in third person, with a mouse-look camera.
- **Cultivate.** Meditate to gather qi and break through five realms. Each breakthrough costs
  twice the qi of the one before.
- **Fight** demon wolves with sword strikes that hit in a cone in front of you.
- **Quest.** Elder Wen sends you after two wolves and rewards you with qi when you return.

## Controls

| Action | Keys |
| --- | --- |
| Move | `W` `A` `S` `D` or arrow keys |
| Look | Mouse (captured on start; `Esc` releases it, a click recaptures it) |
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
godot --headless --path . --script res://tests/run_tests.gd   # 20 headless checks
pip install "gdtoolkit==4.5.0"
gdlint scripts tests tools
gdformat --check scripts tests tools
```

CI runs the same lint and test steps on every pull request. The workflow is in
`.github/workflows/ci.yml`.

## Generating assets with Tripo

`tools/generate_assets.sh` regenerates the models with the Tripo CLI. See
[docs/asset-pipeline.md](docs/asset-pipeline.md) for the prompts, credit costs and the optimisation
step that keeps each GLB at about 1.5 MB.

## Project layout

```
assets/models/       Tripo GLB models (optimised) and their Godot import sidecars
scenes/main.tscn     root scene; builds the valley from code
scripts/core/        cultivation rules, model fitting helpers, input bindings
scripts/player/      the cultivator (player)
scripts/enemies/     spirit beast enemy AI
scripts/npc/         NPC interaction base
scripts/ui/          HUD
tests/               headless test runner
tools/               asset generation script and screenshot capture
docs/                architecture, asset pipeline, screenshots
```

## Documentation

- [Architecture](docs/architecture.md): scene tree, systems, quest and cultivation state
  diagrams, and combat sequence.
- [Asset pipeline](docs/asset-pipeline.md): Tripo workflow, asset table and previews.

## License

See [LICENSE](LICENSE).
