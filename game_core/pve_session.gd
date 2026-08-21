extends RefCounted
class_name PveSession

const Rules = preload("res://game_core/bingo_rules.gd")
const Ai = preload("res://ai/bingo_ai.gd")
const Maps = preload("res://game_core/map_catalog.gd")
const Weather = preload("res://game_core/weather_system.gd")
const Items = preload("res://game_core/item_system.gd")
const Progression = preload("res://game_core/progression.gd")

var state: Dictionary
var action_log: Array = []
var config: Dictionary
var initial_seed: int
var ai_difficulty: String
var map_id: String
var map_data: Dictionary
var item_catalog: Dictionary
var stage_config: Dictionary
var profile_snapshot: Dictionary


func _init(seed_value: int = 20260821, difficulty: String = "normal", selected_map_id: String = Maps.DEFAULT_MAP_ID, player_profile: Dictionary = {}, selected_stage: Dictionary = {}) -> void:
    initial_seed = seed_value
    action_log.clear()
    config = Rules.load_balance_config()
    stage_config = selected_stage.duplicate(true)
    profile_snapshot = player_profile.duplicate(true)
    ai_difficulty = str(stage_config.get("aiDifficulty", difficulty))
    if ai_difficulty not in Ai.DIFFICULTIES:
        ai_difficulty = "normal"
    map_id = str(stage_config.get("mapId", selected_map_id))
    if stage_config.has("rarityWeights"):
        config["rarity_weights"] = stage_config["rarityWeights"].duplicate(true)
    if bool(stage_config.get("tutorial", false)):
        config["weather_trigger_chance"] = 0.0
    var class_pool: Array = stage_config.get("classes", config.get("class_pool", Rules.DEFAULT_CLASSES)).duplicate()
    var training: Dictionary = profile_snapshot.get("class_training", {})
    state = Rules.create_match(seed_value, class_pool, 0, config, [{"class_training": training}, {}])
    _apply_campaign_castles()
    map_data = Maps.get_map(map_id)
    map_id = str(map_data.get("id", Maps.DEFAULT_MAP_ID))
    Weather.initialize_state(state, map_id)
    item_catalog = Items.load_items()
    Items.initialize_state(state, item_catalog)
    _configure_ai_items()
    state["class_modifiers"] = [
        Maps.modifiers_for_player(map_data, state["class_pool"], state["players"][0].get("personal_exclusive_class", null)),
        Maps.modifiers_for_player(map_data, state["class_pool"], state["players"][1].get("personal_exclusive_class", null)),
    ]
    state["mode"] = "pve"
    state["ai_player_index"] = 1
    state["stage_id"] = int(stage_config.get("id", 0))
    state["boss"] = bool(stage_config.get("boss", false))
    state["ai_item_used_turn"] = -1


func restart(seed_value: int = 20260821) -> void:
    _init(seed_value, ai_difficulty, map_id, profile_snapshot, stage_config)


func submit_player_action(cell_index: int, action_kind: String = "auto") -> Dictionary:
    if int(state.get("winner", -1)) >= 0:
        return {"ok": false, "error": "MATCH_ENDED", "events": []}
    var all_events := []
    var round_before := int(state.get("round", 1))
    var player_result: Dictionary = Rules.select_cell(state, 0, cell_index, action_kind, config, false)
    if not bool(player_result.get("ok", false)):
        return player_result
    _record_action(player_result)
    all_events.append_array(player_result.get("events", []))
    _append_round_weather_events(round_before, all_events)
    var advance := _advance_automatic_actions()
    all_events.append_array(advance.get("events", []))
    if not bool(advance.get("ok", false)):
        return {"ok": false, "error": advance.get("error", "AUTO_ACTION_FAILED"), "events": all_events}
    var resolved_events := _resolve_pending_attacks(all_events)
    all_events.append_array(resolved_events)
    return {
        "ok": true,
        "events": all_events,
        "state_version": int(state["state_version"]),
        "winner": int(state.get("winner", -1)),
    }


func can_player_act() -> bool:
    return int(state.get("winner", -1)) < 0 and int(state.get("current_player", -1)) == 0


func submit_player_item(item_id: String, target: Dictionary = {}) -> Dictionary:
    var result := Items.use_item(state, 0, item_id, target, config, item_catalog)
    if not bool(result.get("ok", false)):
        return result
    _record_action(result)
    var events: Array = result.get("events", []).duplicate()
    var advance := _advance_automatic_actions()
    events.append_array(advance.get("events", []))
    if not bool(advance.get("ok", false)):
        return {"ok": false, "error": advance.get("error", "AUTO_ACTION_FAILED"), "events": events}
    var resolved_events := _resolve_pending_attacks(events)
    events.append_array(resolved_events)
    return {"ok": true, "events": events, "state_version": int(state["state_version"]), "winner": int(state.get("winner", -1))}


func snapshot() -> Dictionary:
    return state.duplicate(true)


func export_replay() -> Dictionary:
    var player_actions := []
    for entry in action_log:
        if int(entry.get("player_index", -1)) == 0 and entry.get("action_kind", "") != "skip_follow":
            player_actions.append(entry.duplicate(true))
    return {
        "schema_version": 1,
        "seed": initial_seed,
        "ai_difficulty": ai_difficulty,
        "map_id": map_id,
        "stage_config": stage_config.duplicate(true),
        "player_profile": profile_snapshot.duplicate(true),
        "player_actions": player_actions,
        "expected_signature": Rules.match_signature(state),
    }


static func replay(replay_data: Dictionary) -> Dictionary:
    if int(replay_data.get("schema_version", 0)) != 1:
        return {"ok": false, "error": "UNSUPPORTED_REPLAY_VERSION"}
    var replayed := PveSession.new(
        int(replay_data.get("seed", 1)),
        str(replay_data.get("ai_difficulty", "normal")),
        str(replay_data.get("map_id", Maps.DEFAULT_MAP_ID)),
        replay_data.get("player_profile", {}),
        replay_data.get("stage_config", {}),
    )
    for entry in replay_data.get("player_actions", []):
        var result: Dictionary
        if entry.get("action_kind", "") == "use_item":
            result = replayed.submit_player_item(str(entry.get("item_id", "")), entry.get("target", {}))
        else:
            result = replayed.submit_player_action(
                int(entry.get("cell_index", -1)),
                str(entry.get("action_kind", "auto")),
            )
        if not bool(result.get("ok", false)):
            return {"ok": false, "error": result.get("error", "REPLAY_ACTION_FAILED")}
    var signature := Rules.match_signature(replayed.state)
    return {
        "ok": true,
        "state": replayed.snapshot(),
        "action_log": replayed.action_log.duplicate(true),
        "signature": signature,
        "matches_expected": signature == str(replay_data.get("expected_signature", signature)),
    }


func _record_action(result: Dictionary) -> void:
    var entry: Dictionary = result.get("action", {}).duplicate(true)
    entry["state_version"] = int(state["state_version"])
    action_log.append(entry)


func _advance_automatic_actions() -> Dictionary:
    var events := []
    # Normally this runs two AI actions at most. The guard also covers a rare
    # chain of automatic follow skips without risking a locked session.
    for _step in range(64):
        if int(state.get("winner", -1)) >= 0:
            return {"ok": true, "events": events}
        var current := int(state.get("current_player", -1))
        var result: Dictionary
        var round_before := int(state.get("round", 1))
        if current == 0:
            if state.get("action_stage", "") != "follow" or Rules.can_follow(state, 0):
                return {"ok": true, "events": events}
            result = Rules.skip_follow(state, 0, config)
        elif current == 1:
            _maybe_ai_use_item(events)
            result = Ai.take_turn(state, 1, config, false, ai_difficulty)
        else:
            return {"ok": false, "error": "INVALID_CURRENT_PLAYER", "events": events}
        if not bool(result.get("ok", false)):
            return {"ok": false, "error": result.get("error", "AUTO_ACTION_FAILED"), "events": events}
        _record_action(result)
        events.append_array(result.get("events", []))
        _append_round_weather_events(round_before, events)
    return {"ok": false, "error": "AUTO_ACTION_GUARD_EXCEEDED", "events": events}


func _append_round_weather_events(previous_round: int, events: Array) -> void:
    var current_round := int(state.get("round", previous_round))
    for completed_round in range(previous_round, current_round):
        var weather_events := Weather.advance_completed_round(state, completed_round, config, map_data)
        events.append_array(weather_events)
        state["event_log"].append_array(weather_events)
        if bool(state.get("boss", false)):
            for event in weather_events:
                if event.get("type", "") == "weather_triggered":
                    var boss: Dictionary = state["players"][1]
                    var heal := float(boss["castle_hp_cap"]) * 0.05
                    var before := float(boss["castle_hp"])
                    boss["castle_hp"] = minf(float(boss["castle_hp_cap"]), before + heal)
                    var actual := float(boss["castle_hp"]) - before
                    var boss_event := {"type": "boss_weather_heal", "player_index": 1, "amount": actual}
                    events.append(boss_event)
                    state["event_log"].append(boss_event)
        var item_events := Items.advance_completed_round(state)
        events.append_array(item_events)
        state["event_log"].append_array(item_events)


func _apply_campaign_castles() -> void:
    if stage_config.is_empty() and profile_snapshot.is_empty():
        return
    var player_level := int(profile_snapshot.get("castle_level", 1))
    var player_base_hp := Progression.castle_hp(player_level)
    var first_bonus := float(config.get("first_mover_hp_bonus", 10.0))
    state["players"][0]["castle_hp"] = player_base_hp + first_bonus
    state["players"][0]["castle_hp_cap"] = player_base_hp * float(config.get("hp_cap_multiplier", 2.0))
    state["players"][0]["castle_def"] = Progression.castle_def(player_level)
    var ai_level := int(stage_config.get("aiCastleLevel", 1))
    var ai_base_hp := Progression.castle_hp(ai_level)
    state["players"][1]["castle_hp"] = ai_base_hp
    state["players"][1]["castle_hp_cap"] = ai_base_hp * float(config.get("hp_cap_multiplier", 2.0))
    state["players"][1]["castle_def"] = Progression.castle_def(ai_level)


func _configure_ai_items() -> void:
    var allowed: Array = stage_config.get("aiItems", [])
    for item_id in state["item_counts"][1]:
        state["item_counts"][1][item_id] = 1 if item_id in allowed else 0


func _maybe_ai_use_item(events: Array) -> void:
    if int(state.get("current_player", -1)) != 1:
        return
    var turn_key := int(state.get("turns_completed", 0))
    if int(state.get("ai_item_used_turn", -1)) == turn_key:
        return
    state["ai_item_used_turn"] = turn_key
    for item_id in stage_config.get("aiItems", []):
        if int(state["item_counts"][1].get(item_id, 0)) <= 0:
            continue
        var target := {}
        if item_id == "職業封印":
            target["class_id"] = str(state.get("chain_target", [null, null])[0]) if state.get("chain_target", [null, null])[0] != null else str(state["class_pool"][0])
        elif item_id == "換防令":
            var target_index := -1
            for index in range(state["players"][1]["board"].size()):
                if bool(state["players"][1]["board"][index]["claimed"]):
                    target_index = index
                    break
            if target_index < 0:
                continue
            target["cell_index"] = target_index
        var result := Items.use_item(state, 1, str(item_id), target, config, item_catalog)
        if bool(result.get("ok", false)):
            _record_action(result)
            events.append_array(result.get("events", []))
            return


func _resolve_pending_attacks(events: Array) -> Array:
    var powers := [0.0, 0.0]
    var true_damage := [0.0, 0.0]
    var attack_lines := [[], []]
    var warrior_levels := [0, 0]
    var has_attack := [false, false]
    for event in events:
        if event.get("type", "") != "attack_ready":
            continue
        var player_index := int(event.get("player_index", 0))
        powers[player_index] += float(event.get("attack_power", 0.0))
        true_damage[player_index] += float(event.get("true_damage", 0.0))
        var event_lines: Array = event.get("attack_lines", [])
        attack_lines[player_index].append_array(event_lines)
        for line_output in event_lines:
            warrior_levels[player_index] = maxi(warrior_levels[player_index], int(line_output.get("warrior_level", 0)))
        has_attack[player_index] = true
    if not has_attack[0] and not has_attack[1]:
        return []

    var resolved := []
    if has_attack[0] and has_attack[1]:
        var clash := Rules.resolve_attack_batch(
            float(powers[0]),
            float(powers[1]),
            Rules.effective_castle_def(float(state["players"][0]["castle_def"]), warrior_levels[1], config),
            Rules.effective_castle_def(float(state["players"][1]["castle_def"]), warrior_levels[0], config),
        )
        if float(clash["survivor_power_0"]) > 0.0:
            clash["damage_to_1"] = float(clash["damage_to_1"]) + float(true_damage[0])
        if float(clash["survivor_power_1"]) > 0.0:
            clash["damage_to_0"] = float(clash["damage_to_0"]) + float(true_damage[1])
        _apply_damage(0, float(clash["damage_to_0"]))
        _apply_damage(1, float(clash["damage_to_1"]))
        resolved.append({
            "type": "attack_batch_resolved",
            "power_0": float(clash["power_0"]),
            "power_1": float(clash["power_1"]),
            "survivor_power_0": float(clash["survivor_power_0"]),
            "survivor_power_1": float(clash["survivor_power_1"]),
            "damage_to_0": float(clash["damage_to_0"]),
            "damage_to_1": float(clash["damage_to_1"]),
            "true_damage_0": float(true_damage[0]),
            "true_damage_1": float(true_damage[1]),
            "equal_power": bool(clash["equal_power"]),
        })
    else:
        var attacker := 0 if has_attack[0] else 1
        var target := 1 - attacker
        var damage := 0.0
        for line_output in attack_lines[attacker]:
            damage += Rules.resolve_line_damage(line_output, float(state["players"][target]["castle_def"]), config)
        if attack_lines[attacker].is_empty():
            damage = maxf(1.0, float(powers[attacker]) - float(state["players"][target]["castle_def"])) + float(true_damage[attacker])
        _apply_damage(target, damage)
        resolved.append({
            "type": "single_attack_resolved",
            "player_index": attacker,
            "attack_power": float(powers[attacker]),
            "damage": damage,
            "true_damage": float(true_damage[attacker]),
            "target_player_index": target,
        })
    state["event_log"].append_array(resolved)
    return resolved


func _apply_damage(target_player_index: int, damage: float) -> void:
    var target: Dictionary = state["players"][target_player_index]
    target["castle_hp"] = maxf(0.0, float(target["castle_hp"]) - damage)
    if float(target["castle_hp"]) <= 0.0 and int(state.get("winner", -1)) < 0:
        state["winner"] = 1 - target_player_index
