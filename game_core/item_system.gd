extends RefCounted
class_name ItemSystem

const Rules = preload("res://game_core/bingo_rules.gd")
const Weather = preload("res://game_core/weather_system.gd")

const SCHEMA_VERSION := 1


static func load_items(path: String = "res://data/items.json") -> Dictionary:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return {}
    var parsed = JSON.parse_string(file.get_as_text())
    if typeof(parsed) != TYPE_DICTIONARY or int(parsed.get("schemaVersion", 0)) != SCHEMA_VERSION:
        return {}
    var items := {}
    for entry in parsed.get("items", []):
        if entry is Dictionary and not str(entry.get("id", "")).is_empty():
            items[str(entry["id"])] = entry.duplicate(true)
    return items


static func initialize_state(state: Dictionary, items: Dictionary = {}) -> void:
    var catalog := items if not items.is_empty() else load_items()
    var ids: Array = catalog.keys()
    var counts := [{}, {}]
    for player_index in range(2):
        for item_id in ids:
            counts[player_index][item_id] = 1
    state["item_pool"] = [ids.duplicate(), ids.duplicate()]
    state["item_counts"] = counts
    state["class_seals"] = [{}, {}]


static func use_item(state: Dictionary, player_index: int, item_id: String, target: Dictionary, config: Dictionary, catalog: Dictionary = {}) -> Dictionary:
    var items := catalog if not catalog.is_empty() else load_items()
    if int(state.get("winner", -1)) >= 0:
        return _failure("MATCH_ENDED")
    if player_index != int(state.get("current_player", -1)):
        return _failure("NOT_YOUR_TURN")
    if not items.has(item_id):
        return _failure("UNKNOWN_ITEM")
    if int(state.get("item_counts", [{}, {}])[player_index].get(item_id, 0)) <= 0:
        return _failure("ITEM_EXHAUSTED")

    var item: Dictionary = items[item_id]
    var effect: String = item.get("effect", "")
    var effect_events := []
    var effect_result := {"ok": true}
    match effect:
        "unfreeze_all":
            var cleared := 0
            for cell in state["players"][player_index]["board"]:
                if cell.get("status", "normal") == "frozen":
                    cell["status"] = "normal"
                    cleared += 1
            effect_events.append({"type": "item_unfrozen", "player_index": player_index, "count": cleared})
        "protect_wind":
            state["weather_protections"][player_index]["wind"] = true
        "protect_volcano":
            state["weather_protections"][player_index]["volcano"] = true
        "summon":
            effect_events.append_array(Weather.trigger_weather(state, str(item["weather"]), int(config.get("weather_duration", 2)), config, "item"))
        "sunny":
            state["sunny_rounds_left"] = int(item.get("duration", 2))
            effect_events.append({"type": "sunny_barrier_started", "rounds": int(item.get("duration", 2))})
        "plague":
            effect_events.append_array(_apply_plague(state, 1 - player_index, int(item.get("count", 5)), config))
        "class_seal":
            var class_id := str(target.get("class_id", ""))
            if class_id not in state.get("class_pool", Rules.DEFAULT_CLASSES):
                effect_result = _failure("INVALID_CLASS_TARGET")
            else:
                var expires_round := int(state.get("round", 1)) + int(item.get("duration", 2))
                state["class_seals"][1 - player_index][class_id] = expires_round
                effect_events.append({"type": "class_sealed", "target_player_index": 1 - player_index, "class_id": class_id, "expires_round": expires_round})
        "mine":
            effect_result = _place_mine(state, 1 - player_index)
            effect_events.append_array(effect_result.get("events", []))
        "reroll_unclaimed":
            effect_events.append(_reroll_unclaimed(state, player_index, int(item.get("count", 10)), config))
        "reset_board":
            effect_events.append(_reset_board(state, player_index, config))
        "repair_statuses":
            var repaired := 0
            for cell in state["players"][player_index]["board"]:
                if cell.get("status", "normal") in ["frozen", "buried"]:
                    cell["status"] = "normal"
                    repaired += 1
            effect_events.append({"type": "statuses_repaired", "player_index": player_index, "count": repaired})
        "reroll_claimed":
            effect_result = _reroll_claimed(state, player_index, int(target.get("cell_index", -1)), config)
            effect_events.append_array(effect_result.get("events", []))
        _:
            effect_result = _failure("UNKNOWN_ITEM_EFFECT")

    if not bool(effect_result.get("ok", false)):
        return effect_result
    state["item_counts"][player_index][item_id] = int(state["item_counts"][player_index][item_id]) - 1
    state["state_version"] = int(state.get("state_version", 0)) + 1
    var used_event := {"type": "item_used", "player_index": player_index, "item_id": item_id, "effect": effect}
    var events := [used_event]
    events.append_array(effect_events)
    state["event_log"].append_array(events)
    return {
        "ok": true,
        "events": events,
        "state_version": state["state_version"],
        "action": {"player_index": player_index, "cell_index": -1, "action_kind": "use_item", "item_id": item_id, "target": target.duplicate(true)},
    }


static func advance_completed_round(state: Dictionary) -> Array:
    var events := []
    var current_round := int(state.get("round", 1))
    for player_index in range(2):
        var seals: Dictionary = state.get("class_seals", [{}, {}])[player_index]
        var expired := []
        for class_id in seals:
            if int(seals[class_id]) <= current_round:
                expired.append(class_id)
        for class_id in expired:
            seals.erase(class_id)
            events.append({"type": "class_seal_ended", "player_index": player_index, "class_id": class_id})
    return events


static func is_class_sealed(state: Dictionary, player_index: int, class_id: String) -> bool:
    if player_index < 0 or player_index > 1:
        return false
    return state.get("class_seals", [{}, {}])[player_index].has(class_id)


static func _apply_plague(state: Dictionary, target_player: int, count: int, config: Dictionary) -> Array:
    var board: Array = state["players"][target_player]["board"]
    var claimed := []
    for index in range(board.size()):
        if bool(board[index]["claimed"]):
            claimed.append(index)
    var rng := Rules.DeterministicRng.new(int(state.get("rng_state", 1)))
    var picked := _sample(rng, claimed, count)
    state["rng_state"] = rng.state
    var killed := []
    var evaded := []
    for index in picked:
        if Rules.ninja_evades_kill(state, target_player, index, "plague", config):
            evaded.append(index)
            continue
        _replace_soldier(state, target_player, index, config, true, false)
        killed.append(index)
    return [{"type": "plague_resolved", "target_player_index": target_player, "killed": killed, "evaded": evaded}]


static func _place_mine(state: Dictionary, target_player: int) -> Dictionary:
    var candidates := []
    var board: Array = state["players"][target_player]["board"]
    for index in range(board.size()):
        if not bool(board[index]["claimed"]) and board[index].get("status", "normal") in ["normal", "fogged"] and not bool(board[index].get("mine", false)):
            candidates.append(index)
    if candidates.is_empty():
        return _failure("NO_MINE_TARGET")
    var rng := Rules.DeterministicRng.new(int(state.get("rng_state", 1)))
    var index := int(candidates[rng.next_index(candidates.size())])
    state["rng_state"] = rng.state
    board[index]["mine"] = true
    return {"ok": true, "events": [{"type": "mine_placed", "target_player_index": target_player, "cell_index": index}]}


static func _reroll_unclaimed(state: Dictionary, player_index: int, count: int, config: Dictionary) -> Dictionary:
    var board: Array = state["players"][player_index]["board"]
    var candidates := []
    for index in range(board.size()):
        if not bool(board[index]["claimed"]):
            candidates.append(index)
    var rng := Rules.DeterministicRng.new(int(state.get("rng_state", 1)))
    var picked := _sample(rng, candidates, count)
    state["rng_state"] = rng.state
    for index in picked:
        _replace_soldier(state, player_index, index, config, true, true)
    return {"type": "unclaimed_rerolled", "player_index": player_index, "cells": picked}


static func _reset_board(state: Dictionary, player_index: int, config: Dictionary) -> Dictionary:
    var rng := Rules.DeterministicRng.new(int(state.get("rng_state", 1)))
    var board := []
    for _index in range(Rules.BOARD_CELLS):
        board.append(Rules._new_cell(rng, state.get("class_pool", Rules.DEFAULT_CLASSES), config, Rules.class_weights_from_training(state["players"][player_index].get("class_training", {}), state.get("class_pool", Rules.DEFAULT_CLASSES))))
    state["players"][player_index]["board"] = board
    state["rng_state"] = rng.state
    return {"type": "board_reset", "player_index": player_index}


static func _reroll_claimed(state: Dictionary, player_index: int, cell_index: int, config: Dictionary) -> Dictionary:
    if cell_index < 0 or cell_index >= Rules.BOARD_CELLS:
        return _failure("CELL_OUT_OF_RANGE")
    var cell: Dictionary = state["players"][player_index]["board"][cell_index]
    if not bool(cell["claimed"]):
        return _failure("TARGET_REQUIRES_CLAIMED_CELL")
    var old_rarity := str(cell["rarity"])
    var rng := Rules.DeterministicRng.new(int(state.get("rng_state", 1)))
    cell["rarity"] = Rules._roll_rarity(rng, config)
    state["rng_state"] = rng.state
    return {"ok": true, "events": [{"type": "claimed_rerolled", "player_index": player_index, "cell_index": cell_index, "class_id": cell["class_id"], "old_rarity": old_rarity, "rarity": cell["rarity"]}]}


static func _replace_soldier(state: Dictionary, player_index: int, cell_index: int, config: Dictionary, preserve_construction: bool, preserve_status: bool) -> void:
    var old: Dictionary = state["players"][player_index]["board"][cell_index]
    var construction_level := int(old.get("construction_level", 1))
    var status := str(old.get("status", "normal"))
    var mine := bool(old.get("mine", false))
    var rng := Rules.DeterministicRng.new(int(state.get("rng_state", 1)))
    var fresh := Rules._new_cell(rng, state.get("class_pool", Rules.DEFAULT_CLASSES), config, Rules.class_weights_from_training(state["players"][player_index].get("class_training", {}), state.get("class_pool", Rules.DEFAULT_CLASSES)))
    if preserve_construction:
        fresh["construction_level"] = construction_level
    if preserve_status:
        fresh["status"] = status
        fresh["mine"] = mine
    state["players"][player_index]["board"][cell_index] = fresh
    state["rng_state"] = rng.state


static func _sample(rng: Rules.DeterministicRng, candidates: Array, count: int) -> Array:
    var pool := candidates.duplicate()
    var picked := []
    for _index in range(mini(count, pool.size())):
        picked.append(pool.pop_at(rng.next_index(pool.size())))
    return picked


static func _failure(error_code: String) -> Dictionary:
    return {"ok": false, "error": error_code, "events": []}
