extends RefCounted
class_name BingoAi

const Rules = preload("res://game_core/bingo_rules.gd")

const DIFFICULTIES := ["easy", "normal", "hard"]


## Deterministic greedy AI. It only chooses normal Actions; the rules layer
## remains responsible for legality, line resolution, damage, and victory.
static func take_turn(state: Dictionary, player_index: int, config: Dictionary = Rules.DEFAULT_CONFIG, apply_damage: bool = true, difficulty: String = "normal") -> Dictionary:
    if state.is_empty() or int(state.get("current_player", -1)) != player_index:
        return {"ok": false, "error": "NOT_YOUR_TURN", "events": []}
    var board: Array = state["players"][player_index]["board"]
    var stage: String = state["action_stage"]
    if stage == "follow":
        var target = state["chain_target"][player_index]
        var candidates := _candidates(state, player_index, board, target, true)
        if candidates.is_empty():
            return Rules.skip_follow(state, player_index)
        return Rules.select_cell(state, player_index, _pick_candidate(board, candidates, difficulty), "follow", config, apply_damage)
    if stage == "second_action" and difficulty != "easy":
        var build_index := _best_build_cell(state, player_index)
        if build_index >= 0:
            return Rules.select_cell(state, player_index, build_index, "build", config, apply_damage)
    var free_candidates := _candidates(state, player_index, board, null, false)
    if free_candidates.is_empty():
        return {"ok": false, "error": "NO_FREE_CELL", "events": []}
    return Rules.select_cell(state, player_index, _pick_candidate(board, free_candidates, difficulty), "free", config, apply_damage)


static func _pick_candidate(board: Array, candidates: Array, difficulty: String) -> int:
    if difficulty == "easy":
        return int(candidates[0])
    return _pick_best(board, candidates, difficulty == "hard")


static func _candidates(state: Dictionary, player_index: int, board: Array, class_target, match_class: bool) -> Array:
    var candidates := []
    for index in range(board.size()):
        var cell: Dictionary = board[index]
        if bool(cell["claimed"]) or cell["status"] not in ["normal", "fogged"]:
            continue
        if state.get("class_seals", [{}, {}])[player_index].has(cell["class_id"]):
            continue
        if match_class and cell["class_id"] != class_target:
            continue
        candidates.append(index)
    return candidates


static func _pick_best(board: Array, candidates: Array, use_all_lines: bool = false) -> int:
    var best_index := int(candidates[0])
    var best_score := -1
    for candidate in candidates:
        var score := 0
        for line in Rules.LINES:
            if not (candidate in line):
                continue
            var claimed_count := 0
            for index in line:
                if bool(board[index]["claimed"]):
                    claimed_count += 1
            if use_all_lines:
                score += claimed_count * claimed_count
            else:
                score = maxi(score, claimed_count)
        # Deterministic tie-break is important for action replay.
        if score > best_score or (score == best_score and int(candidate) < best_index):
            best_score = score
            best_index = int(candidate)
    return best_index


static func _best_build_cell(state: Dictionary, player_index: int) -> int:
    var player: Dictionary = state["players"][player_index]
    if float(player["castle_hp"]) < 20.0:
        return -1
    var best_index := -1
    var best_level := 0
    for index in range(player["board"].size()):
        var cell: Dictionary = player["board"][index]
        if not bool(cell["claimed"]):
            continue
        if cell.get("status", "normal") != "normal":
            continue
        var level := int(cell["construction_level"])
        if level < 3 and level > best_level:
            best_level = level
            best_index = index
    return best_index
