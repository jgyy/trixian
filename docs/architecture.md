# Architecture

Xianxia Ascension is a Godot 4.7 project written in GDScript. Every gameplay object is built from
code at runtime, so the only hand-authored scene is `scenes/main.tscn`, which attaches
`scripts/main.gd` to the root. The Tripo models are loaded through `preload()`.

## Scene tree

Built by `scripts/main.gd` when the scene enters the tree.

```mermaid
flowchart TD
    main["Main (main.gd)"] --> world["WorldEnvironment + sun"]
    main --> ground["Ground + stone path"]
    main --> scenery["Scenery props<br/>sect hall, spirit trees, jade rocks"]
    main --> decor["ValleyDecor<br/>mountains, grass, flowers, pond,<br/>bamboo, lanterns, gate, braziers"]
    main --> npcs["Npc x2<br/>Elder Wen (quest), Disciple Lin"]
    main --> beasts["SpiritBeast x3<br/>demon wolves"]
    main --> hud["Hud (CanvasLayer)"]
    main --> player["Cultivator (player)"]
    player --> visual["Visual (rigged female cultivator)"]
    player --> pivot["Yaw pivot"]
    pivot --> arm["SpringArm3D<br/>mouse wheel zoom"]
    arm --> cam["Camera3D"]
```

## Systems and their relationships

```mermaid
flowchart LR
    subgraph Core
        cultivation["Cultivation<br/>qi and realms"]
        quest["WolfQuest<br/>accept, count, turn in"]
        animator["CharacterAnimator<br/>clips and one-shot actions"]
        model_utils["ModelUtils<br/>fit, bounds, yaw"]
        input_setup["InputSetup<br/>key bindings"]
    end
    subgraph Gameplay
        player["Cultivator"]
        beast["SpiritBeast"]
        npc["Npc"]
    end
    decor["ValleyDecor<br/>procedural scenery"]
    main["Main<br/>wiring"]
    hud["Hud"]

    player -- uses --> cultivation
    player -- uses --> animator
    player -- uses --> model_utils
    beast -- uses --> animator
    beast -- uses --> model_utils
    npc -- uses --> animator
    npc -- uses --> model_utils
    main -- owns --> quest
    main -- registers --> input_setup
    main -- builds --> decor
    main -- builds --> player
    main -- builds --> beast
    main -- builds --> npc
    player -- message / stats_changed / prompt_changed --> hud
    beast -- died(qi_reward) --> main
    npc -- talked --> main
    main -- update_stats / set_quest --> hud
```

## Class overview

```mermaid
classDiagram
    class Cultivation {
        +int realm_index
        +float qi
        +realm_name() String
        +qi_required() float
        +gain_qi(amount)
        +try_breakthrough() bool
    }
    class WolfQuest {
        +Step step
        +int slain
        +record_kill()
        +talk() float
        +objective_text() String
    }
    class CharacterAnimator {
        +play(state)
        +play_action(state) bool
        +has_clip(state) bool
    }
    class Cultivator {
        +float hp
        +bool is_meditating
        +Cultivation cultivation
        +CharacterAnimator animator
        +attack()
        +take_damage(amount)
    }
    class SpiritBeast {
        +float hp
        +CharacterAnimator animator
        +take_damage(amount)
    }
    class Npc {
        +String display_name
        +PackedStringArray lines
        +CharacterAnimator animator
        +prompt_text() String
        +interact(player)
        +next_line() String
    }
    class Hud {
        +update_stats(hp, max_hp, realm, qi, qi_required, at_peak)
        +set_quest(text, complete)
        +show_message(text, duration)
    }
    class ModelUtils {
        <<static>>
        +fit_to_height(root, height) AABB
        +yaw_towards(direction) float
    }
    class ValleyDecor {
        <<static>>
        +build(root)
    }
    class Main {
        -WolfQuest _quest
    }
    Cultivator *-- Cultivation : owns
    Cultivator *-- CharacterAnimator : drives
    SpiritBeast *-- CharacterAnimator : drives
    Npc *-- CharacterAnimator : drives
    Cultivator ..> SpiritBeast : strikes
    SpiritBeast ..> Cultivator : attacks
    Npc ..> Cultivator : interacts with
    Main *-- WolfQuest : owns
    Main o-- Cultivator
    Main o-- SpiritBeast
    Main o-- Npc
    Main o-- Hud
    Main ..> ValleyDecor : builds
```

## Quest state

`WolfQuest` holds the rules, and `Main` shows the dialogue. Every wolf slain is counted, including
wolves killed before the quest was accepted. Talking to Elder Wen accepts the quest and turns it in
on the same visit when enough wolves are already slain.

```mermaid
stateDiagram-v2
    [*] --> NotStarted
    NotStarted --> Active: talk to Elder Wen (accept)
    NotStarted --> Complete: talk after 2 wolves slain (accept and turn in, +150 qi)
    Active --> Active: talk before 2 wolves are slain
    Active --> Complete: talk after 2 wolves are slain (+150 qi)
    Complete --> [*]
```

## Animation states

`CharacterAnimator` plays the preset clips baked into each rigged Tripo model. Looping states keep
playing until the state changes. One-shot actions play once and then return to the looping state.
A missing clip falls back to a procedural effect or to the nearest clip.

```mermaid
stateDiagram-v2
    [*] --> Idle
    Idle --> Run: moving
    Run --> Idle: stopped or meditating
    Idle --> Slash: attack (J or left click)
    Run --> Slash: attack
    Slash --> Idle: clip finished
    Idle --> Hurt: took damage
    Run --> Hurt: took damage
    Hurt --> Idle: clip finished
```

Each model has its own set of clips. The female cultivator has idle, walk, run, slash and hurt.
The elder has idle, walk and greet. The wolf has only walk, so it holds the first frame of that
cycle while idle and flinches or lunges procedurally when hit or striking.

## Cultivation progression

Breaking through costs the realm's qi requirement, which doubles with every realm. The final
realm has no further breakthrough.

```mermaid
flowchart LR
    qc["Qi Condensation<br/>needs 100 qi"] -- B --> fe["Foundation Establishment<br/>needs 200 qi"]
    fe -- B --> cf["Core Formation<br/>needs 400 qi"]
    cf -- B --> ns["Nascent Soul<br/>needs 800 qi"]
    ns -- B --> st["Soul Transformation<br/>final realm"]
```

## Combat and meditation

```mermaid
sequenceDiagram
    participant P as Cultivator
    participant B as SpiritBeast
    participant M as Main
    participant H as Hud

    Note over P,B: Beasts chase the player within 11 m
    B->>P: move towards player
    B->>P: take_damage(8) every 1.4 s within 2 m
    P->>P: attack() on J or left click, 0.45 s cooldown
    P->>B: take_damage(25) if inside the 2.6 m cone
    B-->>M: died(40 qi)
    M->>M: count the kill, grant qi
    M->>H: show_message("Spirit beast slain")
```

Meditation (`F`) is a toggle. While it is active the cultivator gains 12 qi per second and
regenerates health. Moving cancels it, and so does taking a hit.

## Input

| Action | Keys |
| --- | --- |
| Move | `W A S D` or arrow keys |
| Look | Mouse (captured on start, `Esc` releases) |
| Zoom | Mouse wheel (clamped between 1.8 m and 9 m) |
| Jump | `Space` |
| Attack | `J` or left mouse button |
| Meditate | `F` |
| Break through | `B` |
| Talk | `E` |

Bindings are registered in code by `InputSetup` so they stay readable and need no hand-edited
`project.godot` entries.

## Model handling

Tripo exports vary in scale and origin. `ModelUtils.fit_to_height` measures the union of the
model's mesh bounds, scales it uniformly to the requested height, and sits it on the ground.
Solid props use the same measured bounds for a box collider. Visual front faces are aligned
with `ModelUtils.FORWARD_OFFSET`.

GLB textures are embedded in the GLB. Godot's import setting `gltf/embedded_image_handling=2`
compresses them into the imported scene, so no texture files are extracted next to the models.

## Testing and CI

```mermaid
flowchart LR
    push["Push or pull request"] --> lint["lint job<br/>gdlint + gdformat --check"]
    push --> test["test job<br/>Godot 4.7.2 headless"]
    test --> import["godot --import"]
    import --> run["run_tests.gd<br/>cultivation, quest, animation,<br/>model fitting, scene boot"]
    lint --> result{"All checks pass?"}
    run --> result
```

Run the suite locally with:

```bash
godot --headless --path . --import
godot --headless --path . --script res://tests/run_tests.gd
```
