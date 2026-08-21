# 織城戰線｜Woven Rampart

Godot 4.x project for the Woven Rampart mobile game. The implementation starts with
the single-player core and keeps the rules in a scene-independent GDScript
domain layer so the later PvP server can reuse it.

## Current milestone

Phase 0 is scaffolded and the Phase 1 core slice is playable:

- `game_core/bingo_rules.gd` contains seeded board generation, turns, follow-color,
  building, per-line DEF resolution, all eight class passives, and simultaneous
  attack cancellation.
- `game_core/map_catalog.gd` and `game_core/weather_system.gd` implement all 11 maps,
  terrain modifiers, scheduled weather, the apocalypse cycle, and all eight weather
  effects with the same deterministic RNG used by replay.
- `game_core/item_system.gd` implements all 20 items, per-match inventory, weather
  counters/summons, disruption and recovery effects, target validation, and item replay.
- `game_core/profile_store.gd`, `progression.gd`, and `campaign_catalog.gd` provide
  versioned local saves, corrupt-save recovery, castle/training economy, first/repeat
  clear rewards, v1-to-v2 progress migration, sequential unlocks, and all 46 campaign stages.
- `game_core/pve_session.gd` and `ai/bingo_ai.gd` connect the rules to a deterministic
  local PvE loop with easy/normal/hard parameters, exact action logging, automatic
  follow skips, and replay verification.
- `tests/core_smoke.gd` contains 23 deterministic golden-style suites covering the
  turn state machine, formula cases, construction safety, attack cancellation, AI,
  class passives, maps, weather, every item, saves, progression, campaign, and replay.
- `main.tscn` launches a mobile-sized client slice with two 5×5 boards, unknown
  opponent cells, free selection, building, follow-color, automatic AI turns,
  an attack overlay (including central power cancellation), map and AI difficulty
  selection, all 20 usable items, live weather/round status, replay verification,
  main hub, scrollable 46-stage campaign selection, next-stage flow, results/rewards,
  and castle/training upgrades.
- `data/balance.json` stores versioned starting balance values.
- `export_presets.cfg` documents desktop, Android, iOS, and headless server targets.

## Run locally

Install Godot 4.x, then run the client:

```sh
godot --editor --path .
godot --path .
```

Run the no-graphics core test command:

```sh
godot --headless --path . --script res://tests/core_smoke.gd
```

The project has been smoke-tested with Godot 4.7.1 headless: all 23 core test
suites pass and the main scene starts successfully. Full touch and visual QA
still needs a real Android/iOS device.
