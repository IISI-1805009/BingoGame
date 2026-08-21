extends RefCounted
class_name WeatherSystem

const Rules = preload("res://game_core/bingo_rules.gd")

const WEATHER_KINDS := ["poison", "ice", "wind", "volcano", "quake", "sandstorm", "flood", "fog"]
const DISPLAY_NAMES := {
    "poison": "中毒",
    "ice": "冰山寒流",
    "wind": "狂風",
    "volcano": "火山",
    "quake": "地震",
    "sandstorm": "沙塵暴",
    "flood": "暴雨洪水",
    "fog": "迷霧",
}


static func initialize_state(state: Dictionary, map_id: String) -> void:
    state["map_id"] = map_id
    state["weather"] = {
        "kind": null,
        "rounds_left": 0,
        "affected_cells": [[], []],
        "apocalypse_pool": [],
    }
    state["weather_debuffs"] = [{}, {}]
    state["global_weather_debuff"] = 0.0
    state["weather_protections"] = [{"wind": false, "volcano": false}, {"wind": false, "volcano": false}]
    state["sunny_rounds_left"] = 0


static func display_name(kind) -> String:
    return "無" if kind == null else str(DISPLAY_NAMES.get(str(kind), kind))


static func advance_completed_round(state: Dictionary, completed_round: int, config: Dictionary, map_data: Dictionary) -> Array:
    var events := []
    var expired := _tick_active_weather(state)
    if not expired.is_empty():
        events.append(expired)

    var main_weather = map_data.get("mainWeather", null)
    if main_weather == null:
        return events
    var every := maxi(1, int(config.get("weather_trigger_every", 3)))
    var scheduled_now: bool = str(main_weather) == "apocalypse" or completed_round % every == 0
    if int(state.get("sunny_rounds_left", 0)) > 0:
        state["sunny_rounds_left"] = int(state["sunny_rounds_left"]) - 1
        if scheduled_now:
            events.append({"type": "weather_suppressed", "round": completed_round, "reason": "sunny"})
        return events
    if str(main_weather) == "apocalypse":
        events.append_array(trigger_weather(state, _next_apocalypse_weather(state), 1, config, "apocalypse"))
        return events
    if completed_round % every != 0:
        return events
    var rng := Rules.DeterministicRng.new(int(state.get("rng_state", 1)))
    var trigger_roll := rng.next_index(10000)
    var chance := float(config.get("weather_trigger_chance", 0.4))
    if trigger_roll >= int(clampf(chance, 0.0, 1.0) * 10000.0):
        state["rng_state"] = rng.state
        events.append({"type": "weather_missed", "round": completed_round})
        return events
    var selected := str(main_weather)
    var main_roll := rng.next_index(10000)
    if main_roll >= int(float(config.get("main_weather_chance", 0.7)) * 10000.0):
        var secondary := WEATHER_KINDS.duplicate()
        secondary.erase(selected)
        selected = str(secondary[rng.next_index(secondary.size())])
    state["rng_state"] = rng.state
    events.append_array(trigger_weather(state, selected, int(config.get("weather_duration", 2)), config, "scheduled"))
    return events


static func trigger_weather(state: Dictionary, kind: String, duration: int, config: Dictionary, source: String = "forced") -> Array:
    if kind not in WEATHER_KINDS:
        return []
    _clear_transient_effects(state)
    var weather: Dictionary = state["weather"]
    weather["kind"] = kind
    weather["rounds_left"] = maxi(1, duration)
    weather["affected_cells"] = [[], []]
    var rng := Rules.DeterministicRng.new(int(state.get("rng_state", 1)))
    var affected := [[], []]
    var details := {}

    match kind:
        "poison":
            var debuffs := [{}, {}]
            for player_index in range(2):
                var index := rng.next_index(Rules.BOARD_CELLS)
                affected[player_index].append(index)
                debuffs[player_index][index] = float(config.get("poison_debuff", 0.2))
            state["weather_debuffs"] = debuffs
        "ice":
            for player_index in range(2):
                affected[player_index] = _sample(rng, range(Rules.BOARD_CELLS), 3)
                for index in affected[player_index]:
                    state["players"][player_index]["board"][index]["status"] = "frozen"
        "wind":
            for player_index in range(2):
                var board: Array = state["players"][player_index]["board"]
                if bool(state.get("weather_protections", [{}, {}])[player_index].get("wind", false)):
                    state["weather_protections"][player_index]["wind"] = false
                    details["wind_protected_%d" % player_index] = true
                    continue
                var candidates := []
                for index in range(board.size()):
                    if not bool(board[index]["claimed"]) and board[index]["status"] in ["normal", "fogged"]:
                        candidates.append(index)
                affected[player_index] = _sample(rng, candidates, 5)
                _shuffle_cells(rng, board, affected[player_index])
        "volcano":
            details["killed_claimed"] = [0, 0]
            for player_index in range(2):
                var board: Array = state["players"][player_index]["board"]
                affected[player_index] = _sample(rng, range(Rules.BOARD_CELLS), 3)
                for index in affected[player_index]:
                    if bool(state.get("weather_protections", [{}, {}])[player_index].get("volcano", false)):
                        board[index]["status"] = "frozen"
                        continue
                    var construction_level := int(board[index].get("construction_level", 1))
                    if bool(board[index]["claimed"]):
                        details["killed_claimed"][player_index] += 1
                    board[index] = Rules._new_cell(rng, state.get("class_pool", Rules.DEFAULT_CLASSES), config, Rules.class_weights_from_training(state["players"][player_index].get("class_training", {}), state.get("class_pool", Rules.DEFAULT_CLASSES)))
                    board[index]["construction_level"] = construction_level
                if bool(state.get("weather_protections", [{}, {}])[player_index].get("volcano", false)):
                    state["weather_protections"][player_index]["volcano"] = false
                    details["volcano_protected_%d" % player_index] = true
        "quake":
            for player_index in range(2):
                var board: Array = state["players"][player_index]["board"]
                affected[player_index] = _sample(rng, range(Rules.BOARD_CELLS), 3)
                for index in affected[player_index]:
                    var construction_level := int(board[index].get("construction_level", 1))
                    board[index] = Rules._new_cell(rng, state.get("class_pool", Rules.DEFAULT_CLASSES), config, Rules.class_weights_from_training(state["players"][player_index].get("class_training", {}), state.get("class_pool", Rules.DEFAULT_CLASSES)))
                    board[index]["construction_level"] = construction_level
                    board[index]["status"] = "buried"
        "sandstorm":
            state["global_weather_debuff"] = float(config.get("sandstorm_debuff", 0.1))
        "flood":
            for player_index in range(2):
                var board: Array = state["players"][player_index]["board"]
                var claimed := []
                for index in range(board.size()):
                    if bool(board[index]["claimed"]):
                        claimed.append(index)
                affected[player_index] = _sample(rng, claimed, 3)
                _shuffle_cells(rng, board, affected[player_index])
        "fog":
            for player_index in range(2):
                var board: Array = state["players"][player_index]["board"]
                var unclaimed := []
                for index in range(board.size()):
                    if not bool(board[index]["claimed"]) and board[index]["status"] == "normal":
                        unclaimed.append(index)
                affected[player_index] = _sample(rng, unclaimed, 5)
                for index in affected[player_index]:
                    board[index]["status"] = "fogged"

    state["rng_state"] = rng.state
    weather["affected_cells"] = affected
    return [{
        "type": "weather_triggered",
        "kind": kind,
        "display_name": display_name(kind),
        "duration": duration,
        "affected_cells": affected,
        "source": source,
        "details": details,
    }]


static func _tick_active_weather(state: Dictionary) -> Dictionary:
    var weather: Dictionary = state.get("weather", {})
    if weather.get("kind", null) == null:
        return {}
    weather["rounds_left"] = int(weather.get("rounds_left", 0)) - 1
    if int(weather["rounds_left"]) > 0:
        return {}
    var old_kind = weather.get("kind", null)
    _clear_transient_effects(state)
    weather["kind"] = null
    weather["rounds_left"] = 0
    weather["affected_cells"] = [[], []]
    return {"type": "weather_ended", "kind": old_kind, "display_name": display_name(old_kind)}


static func _clear_transient_effects(state: Dictionary) -> void:
    var weather: Dictionary = state.get("weather", {})
    var old_kind = weather.get("kind", null)
    var affected: Array = weather.get("affected_cells", [[], []])
    if old_kind in ["ice", "fog", "volcano"]:
        var old_status := "fogged" if old_kind == "fog" else "frozen"
        for player_index in range(2):
            for index in affected[player_index]:
                var cell: Dictionary = state["players"][player_index]["board"][index]
                if cell.get("status", "normal") == old_status:
                    cell["status"] = "normal"
    state["weather_debuffs"] = [{}, {}]
    state["global_weather_debuff"] = 0.0


static func _next_apocalypse_weather(state: Dictionary) -> String:
    var weather: Dictionary = state["weather"]
    var pool: Array = weather.get("apocalypse_pool", [])
    var rng := Rules.DeterministicRng.new(int(state.get("rng_state", 1)))
    if pool.is_empty():
        pool = WEATHER_KINDS.duplicate()
        _shuffle_values(rng, pool)
    var selected := str(pool.pop_back())
    weather["apocalypse_pool"] = pool
    state["rng_state"] = rng.state
    return selected


static func _sample(rng: Rules.DeterministicRng, candidates, count: int) -> Array:
    var pool: Array = Array(candidates).duplicate()
    var picked := []
    for _index in range(mini(count, pool.size())):
        picked.append(pool.pop_at(rng.next_index(pool.size())))
    return picked


static func _shuffle_cells(rng: Rules.DeterministicRng, board: Array, indices: Array) -> void:
    if indices.size() < 2:
        return
    var contents := []
    for index in indices:
        contents.append(board[index].duplicate(true))
    _shuffle_values(rng, contents)
    for offset in range(indices.size()):
        board[indices[offset]] = contents[offset]


static func _shuffle_values(rng: Rules.DeterministicRng, values: Array) -> void:
    for index in range(values.size() - 1, 0, -1):
        var other := rng.next_index(index + 1)
        var value = values[index]
        values[index] = values[other]
        values[other] = value
