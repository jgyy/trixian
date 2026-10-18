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
    main --> npc["Npc: Elder Wen"]
    main --> beasts["SpiritBeast x3<br/>demon wolves"]
    main --> hud["Hud (CanvasLayer)"]
    main --> player["Cultivator (player)"]
    player --> visual["Visual (Tripo hero model)"]
    player --> pivot["Yaw pivot"]
    pivot --> arm["SpringArm3D"]
    arm --> cam["Camera3D"]
```

## Systems and their relationships

```mermaid
flowchart LR
    subgraph Core
        cultivation["Cultivation<br/>qi and realms"]
        model_utils["ModelUtils<br/>fit, bounds, yaw"]
        input_setup["InputSetup<br/>key bindings"]
    end
    subgraph Gameplay
        player["Cultivator"]
        beast["SpiritBeast"]
        npc["Npc"]
    end
    main["Main<br/>quest and wiring"]
    hud["Hud"]

    player -- uses --> cultivation
    player -- uses --> model_utils
    beast -- uses --> model_utils
    npc -- uses --> model_utils
    main -- registers --> input_setup
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
    class Cultivator {
        +float hp
        +bool is_meditating
        +Cultivation cultivation
        +attack()
        +take_damage(amount)
    }
    class SpiritBeast {
        +float hp
        +take_damage(amount)
    }
    class Npc {
        +String display_name
        +prompt_text() String
        +interact(player)
    }
    class Hud {
        +update_stats(hp, max_hp, realm, qi, qi_required)
        +set_quest(text)
        +show_message(text, duration)
    }
    class ModelUtils {
        <<static>>
        +fit_to_height(root, height) AABB
        +yaw_towards(direction) float
    }
    class Main {
        -QuestState quest_state
        -int wolves_slain
    }
    Cultivator *-- Cultivation : owns
    Cultivator ..> SpiritBeast : strikes
    SpiritBeast ..> Cultivator : attacks
    Npc ..> Cultivator : interacts with
    Main o-- Cultivator
    Main o-- SpiritBeast
    Main o-- Npc
    Main o-- Hud
```

## Quest state

`Main` owns the quest. Killing wolves is tracked on every kill, and the reward is paid when the
player reports back to Elder Wen.

```mermaid
stateDiagram-v2
    [*] --> NotStarted
    NotStarted --> Active: talk to Elder Wen
    Active --> Active: talk before 2 wolves are slain
    Active --> Complete: talk after 2 wolves are slain (+150 qi)
    Complete --> [*]
```

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
regenerates health. Moving cancels it.

## Input

| Action | Keys |
| --- | --- |
| Move | `W A S D` or arrow keys |
| Look | Mouse (captured on start, `Esc` releases) |
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

## Testing and CI

```mermaid
flowchart LR
    push["Push or pull request"] --> lint["lint job<br/>gdlint + gdformat --check"]
    push --> test["test job<br/>Godot 4.7.2 headless"]
    test --> import["godot --import"]
    import --> run["run_tests.gd<br/>cultivation, model fitting, scene boot"]
    lint --> result{"All checks pass?"}
    run --> result
```

Run the suite locally with:

```bash
godot --headless --path . --import
godot --headless --path . --script res://tests/run_tests.gd
```
