extends RefCounted
class_name BingoRules

## Pure-ish domain rules for the first Woven Rampart vertical slice.
##
## The methods only receive state/action data and return serialisable
## Dictionaries. No SceneTree, UI, clock, or global random source is used.

const SCHEMA_VERSION := 1
const BOARD_CELLS := 25
const BUILDER := "建築工"
const ALL_CLASSES := ["劍士", "武士", "戰士", "弓手", "騎士", "忍者", "法師", "建築工"]
const DEFAULT_CLASSES := ["劍士", "弓手", "武士", "建築工", "戰士"]
const RARITIES := ["灰", "綠", "藍", "紅", "金"]
const RARITY_WEIGHTS := [40, 30, 20, 8, 2]
const RARITY_MULTIPLIER := {
    "灰": 1.0,
    "綠": 1.2,
    "藍": 1.5,
    "紅": 2.0,
    "金": 3.0,
}
const LINES := [
    [0, 1, 2, 3, 4],
    [5, 6, 7, 8, 9],
    [10, 11, 12, 13, 14],
    [15, 16, 17, 18, 19],
    [20, 21, 22, 23, 24],
    [0, 5, 10, 15, 20],
    [1, 6, 11, 16, 21],
    [2, 7, 12, 17, 22],
    [3, 8, 13, 18, 23],
    [4, 9, 14, 19, 24],
    [0, 6, 12, 18, 24],
    [4, 8, 12, 16, 20],
]

const DEFAULT_CONFIG := {
    "base_attack": 10.0,
    "castle_hp": 100.0,
    "castle_def": 10.0,
    "first_mover_hp_bonus": 10.0,
    "hp_cap_multiplier": 2.0,
    "income": 9.0,
    "construction_cost": {2: 20.0, 3: 40.0},
    "construction_bonus": {1: 0.0, 2: 0.1, 3: 0.2},
    "same_class_multiplier": 1.3,
    "multi_line_multiplier": 1.3,
    "rarity_weights": {"灰": 40, "綠": 30, "藍": 20, "紅": 8, "金": 2},
    "rarity_multiplier": RARITY_MULTIPLIER,
    "class_level_attack_bonus": 0.1,
    "swordsman_true_damage_per_unit": 10.0,
    "samurai_pure_bonus": 0.5,
    "samurai_bonus_per_level": 0.05,
    "warrior_def_threshold": 30.0,
    "warrior_def_reduction": 0.5,
    "warrior_def_reduction_per_level": 0.05,
    "warrior_full_pierce_threshold": 50.0,
    "archer_weather_pierce": 0.3,
    "archer_pierce_per_level": 0.03,
    "knight_multiline_bonus": 0.2,
    "knight_bonus_per_level": 0.03,
    "ninja_evade_chance": 0.3,
    "ninja_evade_per_level": 0.03,
    "mage_heal_percent": 0.1,
    "mage_heal_per_level": 0.01,
    "builder_stack_bonus": 0.15,
    "weather_trigger_every": 3,
    "weather_trigger_chance": 0.4,
    "main_weather_chance": 0.7,
    "weather_duration": 2,
    "poison_debuff": 0.2,
    "sandstorm_debuff": 0.1,
}


class DeterministicRng:
    var state: int

    func _init(seed_value: int) -> void:
        state = seed_value
        if state == 0:
            state = 1

    func next_u31() -> int:
        # LCG is enough for deterministic board generation; it is not a
        # security RNG and must never be used for authoritative PvP secrecy.
        state = int((state * 1664525 + 1013904223) & 0x7fffffff)
        return state

    func next_index(max_value: int) -> int:
        if max_value <= 1:
            return 0
        return next_u31() % max_value


static func load_balance_config(path: String = "res://data/balance.json") -> Dictionary:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return DEFAULT_CONFIG.duplicate(true)
    var parsed = JSON.parse_string(file.get_as_text())
    if typeof(parsed) != TYPE_DICTIONARY:
        return DEFAULT_CONFIG.duplicate(true)
    var config: Dictionary = DEFAULT_CONFIG.duplicate(true)
    config.merge(_normalise_config(parsed), true)
    return config


static func _normalise_config(raw: Dictionary) -> Dictionary:
    # JSON object keys are strings while the core uses integer construction
    # levels. This conversion keeps the runtime rules independent of storage.
    var out := {}
    if raw.has("baseAttack"):
        out["base_attack"] = float(raw["baseAttack"])
    if raw.has("castleHp"):
        out["castle_hp"] = float(raw["castleHp"])
    if raw.has("castleDef"):
        out["castle_def"] = float(raw["castleDef"])
    if raw.has("firstMoverHpBonus"):
        out["first_mover_hp_bonus"] = float(raw["firstMoverHpBonus"])
    if raw.has("hpCapMultiplier"):
        out["hp_cap_multiplier"] = float(raw["hpCapMultiplier"])
    if raw.has("income"):
        out["income"] = float(raw["income"])
    if raw.has("sameClassMultiplier"):
        out["same_class_multiplier"] = float(raw["sameClassMultiplier"])
    if raw.has("multiLineMultiplier"):
        out["multi_line_multiplier"] = float(raw["multiLineMultiplier"])
    if raw.has("constructionCost"):
        var costs := {}
        for key in raw["constructionCost"]:
            costs[int(key)] = float(raw["constructionCost"][key])
        out["construction_cost"] = costs
    if raw.has("constructionBonus"):
        var bonuses := {}
        for key in raw["constructionBonus"]:
            bonuses[int(key)] = float(raw["constructionBonus"][key])
        out["construction_bonus"] = bonuses
    if raw.has("classPool") and raw["classPool"] is Array:
        out["class_pool"] = raw["classPool"]
    if raw.has("rarityWeights") and raw["rarityWeights"] is Dictionary:
        out["rarity_weights"] = raw["rarityWeights"].duplicate(true)
    if raw.has("rarityMultiplier") and raw["rarityMultiplier"] is Dictionary:
        out["rarity_multiplier"] = raw["rarityMultiplier"].duplicate(true)
    var passive_keys := {
        "classLevelAttackBonus": "class_level_attack_bonus",
        "swordsmanTrueDamagePerUnit": "swordsman_true_damage_per_unit",
        "samuraiPureBonus": "samurai_pure_bonus",
        "samuraiBonusPerLevel": "samurai_bonus_per_level",
        "warriorDefThreshold": "warrior_def_threshold",
        "warriorDefReduction": "warrior_def_reduction",
        "warriorDefReductionPerLevel": "warrior_def_reduction_per_level",
        "warriorFullPierceThreshold": "warrior_full_pierce_threshold",
        "archerWeatherPierce": "archer_weather_pierce",
        "archerPiercePerLevel": "archer_pierce_per_level",
        "knightMultilineBonus": "knight_multiline_bonus",
        "knightBonusPerLevel": "knight_bonus_per_level",
        "ninjaEvadeChance": "ninja_evade_chance",
        "ninjaEvadePerLevel": "ninja_evade_per_level",
        "mageHealPercent": "mage_heal_percent",
        "mageHealPerLevel": "mage_heal_per_level",
        "builderStackBonus": "builder_stack_bonus",
        "weatherTriggerChance": "weather_trigger_chance",
        "mainWeatherChance": "main_weather_chance",
        "poisonDebuff": "poison_debuff",
        "sandstormDebuff": "sandstorm_debuff",
    }
    for storage_key in passive_keys:
        if raw.has(storage_key):
            out[passive_keys[storage_key]] = float(raw[storage_key])
    if raw.has("weatherTriggerEvery"):
        out["weather_trigger_every"] = int(raw["weatherTriggerEvery"])
    if raw.has("weatherDuration"):
        out["weather_duration"] = int(raw["weatherDuration"])
    return out


static func create_match(seed_value: int, class_pool: Array = DEFAULT_CLASSES, first_player: int = 0, config: Dictionary = DEFAULT_CONFIG, player_options: Array = []) -> Dictionary:
    var rng := DeterministicRng.new(seed_value)
    var pool: Array = class_pool.duplicate()
    if pool.is_empty():
        pool = DEFAULT_CLASSES.duplicate()
    var options_0: Dictionary = player_options[0] if player_options.size() > 0 else {}
    var options_1: Dictionary = player_options[1] if player_options.size() > 1 else {}
    var board_0 := _make_board(rng, pool, config, class_weights_from_training(options_0.get("class_training", {}), pool))
    var board_1 := _make_board(rng, pool, config, class_weights_from_training(options_1.get("class_training", {}), pool))
    var hp := float(config.get("castle_hp", 100.0))
    var first_bonus := float(config.get("first_mover_hp_bonus", 10.0)) if first_player >= 0 else 0.0
    var hp_0 := hp + first_bonus if first_player == 0 else hp
    var hp_1 := hp + first_bonus if first_player == 1 else hp
    var cap := hp * float(config.get("hp_cap_multiplier", 2.0))
    return {
        "schema_version": SCHEMA_VERSION,
        "state_version": 0,
        "seed": seed_value,
        "rng_state": rng.state,
        "class_pool": pool.duplicate(),
        "first_mover": first_player,
        "current_player": first_player,
        "action_stage": "opening_free",
        "round": 1,
        "turns_completed": 0,
        "lines_completed_this_turn": 0,
        "chain_target": [null, null],
        "players": [
            _make_player("p0", board_0, hp_0, cap, config, options_0),
            _make_player("p1", board_1, hp_1, cap, config, options_1),
        ],
        "winner": -1,
        "event_log": [],
    }


static func _make_player(player_id: String, board: Array, hp: float, cap: float, config: Dictionary, options: Dictionary = {}) -> Dictionary:
    return {
        "player_id": player_id,
        "board": board,
        "castle_hp": hp,
        "castle_hp_cap": cap,
        "castle_def": float(config.get("castle_def", 10.0)),
        "class_training": _normalise_class_training(options.get("class_training", {})),
        "personal_exclusive_class": options.get("personal_exclusive_class", null),
    }


static func _normalise_class_training(raw: Dictionary) -> Dictionary:
    var levels := {}
    for class_id in ALL_CLASSES:
        levels[class_id] = maxi(1, int(raw.get(class_id, 1)))
    return levels


static func _make_board(rng: DeterministicRng, class_pool: Array, config: Dictionary = DEFAULT_CONFIG, class_weights: Dictionary = {}) -> Array:
    var board := []
    for _i in range(BOARD_CELLS):
        board.append(_new_cell(rng, class_pool, config, class_weights))
    return board


static func _new_cell(rng: DeterministicRng, class_pool: Array, config: Dictionary = DEFAULT_CONFIG, class_weights: Dictionary = {}) -> Dictionary:
    return {
        "class_id": _roll_class(rng, class_pool, class_weights),
        "rarity": _roll_rarity(rng, config),
        "claimed": false,
        "construction_level": 1,
        "status": "normal",
        "mine": false,
    }


static func class_weights_from_training(training: Dictionary, class_pool: Array) -> Dictionary:
    var weights := {}
    for class_id in class_pool:
        weights[class_id] = 100 + 15 * maxi(0, int(training.get(class_id, 1)) - 1)
    return weights


static func _roll_class(rng: DeterministicRng, class_pool: Array, class_weights: Dictionary) -> String:
    var total := 0
    for class_id in class_pool:
        total += maxi(1, int(class_weights.get(class_id, 100)))
    var roll := rng.next_index(total)
    var cumulative := 0
    for class_id in class_pool:
        cumulative += maxi(1, int(class_weights.get(class_id, 100)))
        if roll < cumulative:
            return str(class_id)
    return str(class_pool[-1])


static func _roll_rarity(rng: DeterministicRng, config: Dictionary = DEFAULT_CONFIG) -> String:
    var roll := rng.next_index(100)
    var cumulative := 0
    var weights: Dictionary = config.get("rarity_weights", {})
    for i in range(RARITIES.size()):
        cumulative += int(weights.get(RARITIES[i], RARITY_WEIGHTS[i]))
        if roll < cumulative:
            return RARITIES[i]
    return RARITIES[-1]


static func board_signature(board: Array) -> String:
    var parts := []
    for cell in board:
        parts.append("%s:%s" % [cell["class_id"], cell["rarity"]])
    return ",".join(parts)


static func find_completed_lines(board: Array, cell_index: int = -1) -> Array:
    var completed := []
    for line in LINES:
        if cell_index >= 0 and not (cell_index in line):
            continue
        var complete := true
        for index in line:
            if not bool(board[index]["claimed"]):
                complete = false
                break
        if complete:
            completed.append(line.duplicate())
    return completed


static func can_follow(state: Dictionary, player_index: int) -> bool:
    if player_index < 0 or player_index > 1:
        return false
    var target = state["chain_target"][player_index]
    if target == null:
        return false
    if state.get("class_seals", [{}, {}])[player_index].has(target):
        return false
    for cell in state["players"][player_index]["board"]:
        if not bool(cell["claimed"]) and cell["class_id"] == target and cell["status"] in ["normal", "fogged"]:
            return true
    return false


static func select_cell(state: Dictionary, player_index: int, cell_index: int, action_kind: String = "auto", config: Dictionary = DEFAULT_CONFIG, apply_damage: bool = true) -> Dictionary:
    if state.is_empty():
        return _failure("EMPTY_STATE")
    if int(state.get("winner", -1)) >= 0:
        return _failure("MATCH_ENDED")
    if player_index != int(state["current_player"]):
        return _failure("NOT_YOUR_TURN")
    if cell_index < 0 or cell_index >= BOARD_CELLS:
        return _failure("CELL_OUT_OF_RANGE")
    var stage: String = state["action_stage"]
    if action_kind == "auto":
        action_kind = "follow" if stage == "follow" else "free"
        if stage == "second_action":
            action_kind = "free"

    if action_kind == "build":
        if stage != "second_action":
            return _failure("BUILD_NOT_AVAILABLE")
        return build_cell(state, player_index, cell_index, config)
    if action_kind == "clear_rubble":
        return clear_buried_cell(state, player_index, cell_index)
    if action_kind != "free" and action_kind != "follow":
        return _failure("UNKNOWN_ACTION")
    if stage == "follow" and action_kind != "follow":
        return _failure("FOLLOW_REQUIRED")
    if stage != "follow" and action_kind == "follow":
        return _failure("FOLLOW_NOT_AVAILABLE")

    var player: Dictionary = state["players"][player_index]
    var board: Array = player["board"]
    var cell: Dictionary = board[cell_index]
    if bool(cell["claimed"]):
        return _failure("CELL_ALREADY_CLAIMED")
    if cell["status"] not in ["normal", "fogged"]:
        return _failure("CELL_UNAVAILABLE")
    if state.get("class_seals", [{}, {}])[player_index].has(cell["class_id"]):
        return _failure("CLASS_SEALED")
    if action_kind == "follow" and cell["class_id"] != state["chain_target"][player_index]:
        return _failure("WRONG_FOLLOW_CLASS")

    var selected_class := str(cell["class_id"])
    var was_fogged: bool = cell["status"] == "fogged"
    var pre_events := []
    var mine_killed := false
    if bool(cell.get("mine", false)):
        cell["mine"] = false
        if ninja_evades_kill(state, player_index, cell_index, "mine", config):
            pre_events.append({"type": "mine_evaded", "player_index": player_index, "cell_index": cell_index})
        else:
            _replace_killed_soldier(state, player_index, cell_index, config)
            mine_killed = true
            pre_events.append({"type": "mine_triggered", "player_index": player_index, "cell_index": cell_index})
    var output := {"attack_power": 0.0, "true_damage": 0.0, "attack_lines": [], "heal": 0.0, "events": []}
    if not mine_killed:
        cell = board[cell_index]
        cell["claimed"] = true
        cell["status"] = "normal"
        cell["construction_level"] = 1
        var completed := find_completed_lines(board, cell_index)
        output = resolve_completed_lines(state, player_index, completed, config)
    var events: Array = []
    if was_fogged:
        events.append({"type": "fog_revealed", "player_index": player_index, "cell_index": cell_index, "class_id": selected_class})
    events.append_array(pre_events)
    events.append_array(output["events"])
    if float(output["attack_power"]) > 0.0:
        var opponent: Dictionary = state["players"][1 - player_index]
        if apply_damage:
            var damage := 0.0
            for attack_line in output.get("attack_lines", []):
                damage += resolve_line_damage(attack_line, float(opponent["castle_def"]), config)
            opponent["castle_hp"] = maxf(0.0, float(opponent["castle_hp"]) - damage)
            events.append({
                "type": "castle_hit",
                "player_index": player_index,
                "attack_power": float(output["attack_power"]),
                "true_damage": float(output.get("true_damage", 0.0)),
                "damage": damage,
                "target_player_index": 1 - player_index,
            })
            if float(opponent["castle_hp"]) <= 0.0:
                state["winner"] = player_index
                events.append({"type": "match_won", "player_index": player_index})
        else:
            events.append({
                "type": "attack_ready",
                "player_index": player_index,
                "attack_power": float(output["attack_power"]),
                "true_damage": float(output.get("true_damage", 0.0)),
                "attack_lines": output.get("attack_lines", []).duplicate(true),
                "target_player_index": 1 - player_index,
            })
    if action_kind == "free":
        _add_hp(player, float(config.get("income", 9.0)))
        state["chain_target"][1 - player_index] = selected_class
        events.append({"type": "income", "player_index": player_index, "amount": float(config.get("income", 9.0))})
    if stage == "follow":
        # A normal turn is follow-color followed by one free/build action.
        # The opening free choice is the first mover's entire first turn.
        state["action_stage"] = "second_action"
    else:
        _end_turn(state)
    state["state_version"] += 1
    state["event_log"].append_array(events)
    return {
        "ok": true,
        "events": events,
        "state_version": state["state_version"],
        "action": {"player_index": player_index, "cell_index": cell_index, "action_kind": action_kind},
    }


static func skip_follow(state: Dictionary, player_index: int, config: Dictionary = DEFAULT_CONFIG) -> Dictionary:
    if state.is_empty() or player_index != int(state["current_player"]):
        return _failure("NOT_YOUR_TURN")
    if int(state.get("winner", -1)) >= 0:
        return _failure("MATCH_ENDED")
    if state["action_stage"] != "follow":
        return _failure("FOLLOW_NOT_REQUIRED")
    if can_follow(state, player_index):
        return _failure("LEGAL_FOLLOW_EXISTS")
    var events := [{"type": "follow_skipped", "player_index": player_index}]
    _finish_turn(state, "free")
    state["state_version"] += 1
    state["event_log"].append_array(events)
    return {
        "ok": true,
        "events": events,
        "state_version": state["state_version"],
        "action": {"player_index": player_index, "cell_index": -1, "action_kind": "skip_follow"},
    }


static func build_cell(state: Dictionary, player_index: int, cell_index: int, config: Dictionary = DEFAULT_CONFIG) -> Dictionary:
    if state.is_empty():
        return _failure("EMPTY_STATE")
    if int(state.get("winner", -1)) >= 0:
        return _failure("MATCH_ENDED")
    if player_index != int(state["current_player"]):
        return _failure("NOT_YOUR_TURN")
    if state.get("action_stage", "") != "second_action":
        return _failure("BUILD_NOT_AVAILABLE")
    if cell_index < 0 or cell_index >= BOARD_CELLS:
        return _failure("CELL_OUT_OF_RANGE")
    var player: Dictionary = state["players"][player_index]
    var cell: Dictionary = player["board"][cell_index]
    if cell.get("status", "normal") != "normal":
        return _failure("CELL_UNAVAILABLE")
    if not bool(cell["claimed"]):
        return _failure("BUILD_REQUIRES_CLAIMED_CELL")
    var level := int(cell["construction_level"])
    if level >= 3:
        return _failure("MAX_CONSTRUCTION_LEVEL")
    var costs: Dictionary = config.get("construction_cost", {2: 20.0, 3: 40.0})
    var cost := float(costs.get(level + 1, 0.0))
    if float(player["castle_hp"]) - cost < 1.0:
        return _failure("INSUFFICIENT_POWER")
    player["castle_hp"] = float(player["castle_hp"]) - cost
    cell["construction_level"] = level + 1
    _end_turn(state)
    state["state_version"] += 1
    var event := {"type": "built", "player_index": player_index, "cell_index": cell_index, "level": level + 1, "cost": cost}
    state["event_log"].append(event)
    return {
        "ok": true,
        "events": [event],
        "state_version": state["state_version"],
        "action": {"player_index": player_index, "cell_index": cell_index, "action_kind": "build"},
    }


static func clear_buried_cell(state: Dictionary, player_index: int, cell_index: int) -> Dictionary:
    if state.is_empty() or int(state.get("winner", -1)) >= 0:
        return _failure("MATCH_ENDED")
    if player_index != int(state.get("current_player", -1)):
        return _failure("NOT_YOUR_TURN")
    if cell_index < 0 or cell_index >= BOARD_CELLS:
        return _failure("CELL_OUT_OF_RANGE")
    var cell: Dictionary = state["players"][player_index]["board"][cell_index]
    if cell.get("status", "normal") != "buried":
        return _failure("CELL_NOT_BURIED")
    cell["status"] = "normal"
    _end_turn(state)
    state["state_version"] = int(state.get("state_version", 0)) + 1
    var event := {"type": "rubble_cleared", "player_index": player_index, "cell_index": cell_index}
    state["event_log"].append(event)
    return {
        "ok": true,
        "events": [event],
        "state_version": state["state_version"],
        "action": {"player_index": player_index, "cell_index": cell_index, "action_kind": "clear_rubble"},
    }


static func resolve_completed_lines(state: Dictionary, player_index: int, lines: Array, config: Dictionary = DEFAULT_CONFIG) -> Dictionary:
    if lines.is_empty():
        return {"attack_power": 0.0, "true_damage": 0.0, "attack_lines": [], "heal": 0.0, "events": []}
    var player: Dictionary = state["players"][player_index]
    var board: Array = player["board"]
    var attack_power := 0.0
    var true_damage := 0.0
    var heal := 0.0
    var attack_lines := []
    var events := []
    var line_number := int(state.get("lines_completed_this_turn", 0))
    var context := {
        "class_training": player.get("class_training", {}),
        "weather_debuffs": state.get("weather_debuffs", [{}, {}])[player_index] if state.get("weather_debuffs", []) is Array and state.get("weather_debuffs", []).size() > player_index else {},
        "global_weather_debuff": float(state.get("global_weather_debuff", 0.0)),
        "class_modifiers": state.get("class_modifiers", [{}, {}])[player_index] if state.get("class_modifiers", []) is Array and state.get("class_modifiers", []).size() > player_index else {},
    }
    for line in lines:
        line_number += 1
        var output := line_output(board, line, line_number, config, context)
        attack_power += float(output["attack_power"])
        true_damage += float(output["true_damage"])
        heal += float(output["heal"])
        if float(output["attack_power"]) > 0.0:
            attack_lines.append(output.duplicate(true))
        events.append({
            "type": "line_completed",
            "player_index": player_index,
            "line": line.duplicate(),
            "attack_power": float(output["attack_power"]),
            "true_damage": float(output["true_damage"]),
            "heal": float(output["heal"]),
            "is_multiline": line_number >= 2,
            "passives": output["passives"].duplicate(),
        })
    state["lines_completed_this_turn"] = line_number
    var rng := DeterministicRng.new(int(state["rng_state"]))
    var cleared := {}
    for line in lines:
        for index in line:
            cleared[index] = true
    for index in cleared:
        board[index] = _new_cell(rng, state.get("class_pool", DEFAULT_CLASSES), config, class_weights_from_training(state["players"][player_index].get("class_training", {}), state.get("class_pool", DEFAULT_CLASSES)))
    state["rng_state"] = rng.state
    _add_hp(state["players"][player_index], heal)
    return {"attack_power": attack_power, "true_damage": true_damage, "attack_lines": attack_lines, "heal": heal, "events": events}


static func line_output(board: Array, line: Array, line_number: int, config: Dictionary = DEFAULT_CONFIG, context: Dictionary = {}) -> Dictionary:
    var classes := {}
    for index in line:
        classes[board[index]["class_id"]] = true
    var is_pure := classes.size() == 1
    var attack_power := 0.0
    var builder_power := 0.0
    var mage_heal := 0.0
    var true_damage := 0.0
    var builder_count := 0
    var warrior_level := 0
    var knight_level := 0
    var passives := []
    var class_training: Dictionary = context.get("class_training", {})
    var weather_debuffs: Dictionary = context.get("weather_debuffs", {})
    var class_modifiers: Dictionary = context.get("class_modifiers", {})
    var global_weather_debuff := float(context.get("global_weather_debuff", 0.0))
    var rarity_multiplier: Dictionary = config.get("rarity_multiplier", RARITY_MULTIPLIER)
    for index in line:
        var cell: Dictionary = board[index]
        var class_id: String = cell["class_id"]
        var class_level := maxi(1, int(class_training.get(class_id, 1)))
        var level := int(cell["construction_level"])
        var construction_multiplier := 1.0 + float(config.get("construction_bonus", {1: 0.0, 2: 0.1, 3: 0.2}).get(level, 0.0))
        var training_multiplier := 1.0 + float(config.get("class_level_attack_bonus", 0.1)) * float(class_level - 1)
        var debuff := float(weather_debuffs.get(index, global_weather_debuff))
        if class_id == "弓手" and debuff > 0.0:
            var pierce := float(config.get("archer_weather_pierce", 0.3)) + float(config.get("archer_pierce_per_level", 0.03)) * float(class_level - 1)
            debuff *= 1.0 - clampf(pierce, 0.0, 1.0)
            if not ("弓手：穿透" in passives):
                passives.append("弓手：穿透")
        var terrain_multiplier := 1.0 + clampf(float(class_modifiers.get(class_id, 0.0)), -0.15, 0.15)
        var unit_value := float(config.get("base_attack", 10.0)) * training_multiplier * float(rarity_multiplier.get(cell["rarity"], 1.0)) * construction_multiplier * terrain_multiplier * (1.0 - clampf(debuff, 0.0, 1.0))
        if class_id == BUILDER:
            builder_count += 1
            builder_power += unit_value
        else:
            if class_id == "武士" and is_pure:
                var samurai_bonus := float(config.get("samurai_pure_bonus", 0.5)) + float(config.get("samurai_bonus_per_level", 0.05)) * float(class_level - 1)
                unit_value *= 1.0 + samurai_bonus
                if not ("武士：一擊必殺" in passives):
                    passives.append("武士：一擊必殺")
            elif class_id == "劍士":
                true_damage += float(config.get("swordsman_true_damage_per_unit", 10.0)) * training_multiplier
                if not ("劍士：居合追擊" in passives):
                    passives.append("劍士：居合追擊")
            elif class_id == "戰士":
                warrior_level = maxi(warrior_level, class_level)
                if not ("戰士：蠻力揮砍" in passives):
                    passives.append("戰士：蠻力揮砍")
            elif class_id == "騎士":
                knight_level = maxi(knight_level, class_level)
            elif class_id == "法師":
                var mage_percent := float(config.get("mage_heal_percent", 0.1)) + float(config.get("mage_heal_per_level", 0.01)) * float(class_level - 1)
                mage_heal += unit_value * mage_percent
                if not ("法師：奧術屏障" in passives):
                    passives.append("法師：奧術屏障")
            attack_power += unit_value
    var same_multiplier := float(config.get("same_class_multiplier", 1.3)) if is_pure else 1.0
    var multi_multiplier := float(config.get("multi_line_multiplier", 1.3)) if line_number >= 2 else 1.0
    if knight_level > 0 and line_number >= 2:
        var knight_bonus := float(config.get("knight_multiline_bonus", 0.2)) + float(config.get("knight_bonus_per_level", 0.03)) * float(knight_level - 1)
        attack_power *= 1.0 + knight_bonus
        passives.append("騎士：貫穿衝鋒")
    attack_power *= same_multiplier * multi_multiplier
    true_damage *= multi_multiplier
    var heal := builder_power
    if builder_count > 1:
        heal *= 1.0 + float(config.get("builder_stack_bonus", 0.15)) * float(builder_count - 1)
    heal *= same_multiplier * multi_multiplier
    heal += mage_heal * multi_multiplier
    return {
        "attack_power": attack_power,
        "true_damage": true_damage,
        "heal": heal,
        "warrior_level": warrior_level,
        "passives": passives,
    }


static func resolve_line_damage(output: Dictionary, castle_def: float, config: Dictionary = DEFAULT_CONFIG) -> float:
    var effective_def := effective_castle_def(castle_def, int(output.get("warrior_level", 0)), config)
    var base_damage := maxf(1.0, float(output.get("attack_power", 0.0)) - effective_def) if float(output.get("attack_power", 0.0)) > 0.0 else 0.0
    return base_damage + float(output.get("true_damage", 0.0))


static func effective_castle_def(castle_def: float, warrior_level: int, config: Dictionary = DEFAULT_CONFIG) -> float:
    var effective_def := castle_def
    if warrior_level > 0 and effective_def >= float(config.get("warrior_full_pierce_threshold", 50.0)):
        effective_def = 0.0
    elif warrior_level > 0 and effective_def >= float(config.get("warrior_def_threshold", 30.0)):
        var reduction := float(config.get("warrior_def_reduction", 0.5)) + float(config.get("warrior_def_reduction_per_level", 0.05)) * float(warrior_level - 1)
        effective_def *= 1.0 - clampf(reduction, 0.0, 1.0)
    return effective_def


static func ninja_evades_kill(state: Dictionary, player_index: int, cell_index: int, source: String, config: Dictionary = DEFAULT_CONFIG) -> bool:
    if source not in ["plague", "mine"] or player_index < 0 or player_index > 1 or cell_index < 0 or cell_index >= BOARD_CELLS:
        return false
    var cell: Dictionary = state["players"][player_index]["board"][cell_index]
    if cell.get("class_id", "") != "忍者":
        return false
    var training: Dictionary = state["players"][player_index].get("class_training", {})
    var class_level := maxi(1, int(training.get("忍者", 1)))
    var chance := float(config.get("ninja_evade_chance", 0.3)) + float(config.get("ninja_evade_per_level", 0.03)) * float(class_level - 1)
    var rng := DeterministicRng.new(int(state.get("rng_state", 1)))
    var roll := rng.next_index(10000)
    state["rng_state"] = rng.state
    return roll < int(clampf(chance, 0.0, 1.0) * 10000.0)


static func _replace_killed_soldier(state: Dictionary, player_index: int, cell_index: int, config: Dictionary) -> void:
    var old: Dictionary = state["players"][player_index]["board"][cell_index]
    var construction_level := int(old.get("construction_level", 1))
    var rng := DeterministicRng.new(int(state.get("rng_state", 1)))
    var fresh := _new_cell(rng, state.get("class_pool", DEFAULT_CLASSES), config, class_weights_from_training(state["players"][player_index].get("class_training", {}), state.get("class_pool", DEFAULT_CLASSES)))
    fresh["construction_level"] = construction_level
    state["players"][player_index]["board"][cell_index] = fresh
    state["rng_state"] = rng.state


static func resolve_attack_batch(power_0: float, power_1: float, castle_def_0: float = 10.0, castle_def_1: float = 10.0) -> Dictionary:
    # Both powers meet in the centre first. Castle DEF is applied only to the
    # residual power that survives the clash. Equal power annihilates both.
    var survivor_0 := maxf(power_0 - power_1, 0.0)
    var survivor_1 := maxf(power_1 - power_0, 0.0)
    var damage_to_1 := maxf(1.0, survivor_0 - castle_def_1) if survivor_0 > 0.0 else 0.0
    var damage_to_0 := maxf(1.0, survivor_1 - castle_def_0) if survivor_1 > 0.0 else 0.0
    var outcome_0 := "annihilated" if survivor_0 <= 0.0 else "survivor_attacks_castle"
    var outcome_1 := "annihilated" if survivor_1 <= 0.0 else "survivor_attacks_castle"
    return {
        "power_0": power_0,
        "power_1": power_1,
        "survivor_power_0": survivor_0,
        "survivor_power_1": survivor_1,
        "damage_to_0": damage_to_0,
        "damage_to_1": damage_to_1,
        "outcome_0": outcome_0,
        "outcome_1": outcome_1,
        "equal_power": is_equal_approx(power_0, power_1),
    }


static func _add_hp(player: Dictionary, amount: float) -> void:
    player["castle_hp"] = minf(float(player["castle_hp_cap"]), float(player["castle_hp"]) + amount)


static func _end_turn(state: Dictionary) -> void:
    _finish_turn(state, "follow")


static func _finish_turn(state: Dictionary, next_stage: String) -> void:
    state["current_player"] = 1 - int(state["current_player"])
    state["action_stage"] = next_stage
    state["turns_completed"] = int(state.get("turns_completed", 0)) + 1
    state["round"] = 1 + int(int(state["turns_completed"]) / 2)
    state["lines_completed_this_turn"] = 0


static func match_signature(state: Dictionary) -> String:
    var parts := [
        str(state.get("seed", 0)),
        str(state.get("rng_state", 0)),
        str(state.get("state_version", 0)),
        str(state.get("current_player", -1)),
        str(state.get("action_stage", "")),
        str(state.get("round", 0)),
        str(state.get("winner", -1)),
        str(state.get("map_id", "")),
        str(state.get("weather", {}).get("kind", null)),
        str(state.get("weather", {}).get("rounds_left", 0)),
        "%.4f" % float(state.get("global_weather_debuff", 0.0)),
        str(state.get("sunny_rounds_left", 0)),
    ]
    for debuffs in state.get("weather_debuffs", []):
        var debuff_keys: Array = debuffs.keys()
        debuff_keys.sort()
        for key in debuff_keys:
            parts.append("weather:%s:%.4f" % [str(key), float(debuffs[key])])
    for player_index in range(state.get("item_counts", []).size()):
        var item_counts: Dictionary = state["item_counts"][player_index]
        var item_keys: Array = item_counts.keys()
        item_keys.sort()
        for key in item_keys:
            parts.append("item:%d:%s:%d" % [player_index, str(key), int(item_counts[key])])
        var seals: Dictionary = state.get("class_seals", [{}, {}])[player_index]
        var seal_keys: Array = seals.keys()
        seal_keys.sort()
        for key in seal_keys:
            parts.append("seal:%d:%s:%d" % [player_index, str(key), int(seals[key])])
        var protections: Dictionary = state.get("weather_protections", [{}, {}])[player_index]
        parts.append("protect:%d:%d:%d" % [player_index, int(bool(protections.get("wind", false))), int(bool(protections.get("volcano", false)))])
    for player in state.get("players", []):
        parts.append("%.4f" % float(player.get("castle_hp", 0.0)))
        for cell in player.get("board", []):
            parts.append("%s:%s:%d:%d:%s:%d" % [
                str(cell.get("class_id", "")),
                str(cell.get("rarity", "")),
                1 if bool(cell.get("claimed", false)) else 0,
                int(cell.get("construction_level", 1)),
                str(cell.get("status", "normal")),
                1 if bool(cell.get("mine", false)) else 0,
            ])
    return "|".join(parts)


static func _failure(error_code: String) -> Dictionary:
    return {"ok": false, "error": error_code, "events": []}
