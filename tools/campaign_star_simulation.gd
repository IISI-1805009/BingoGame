extends SceneTree

## Reproducible PvE benchmark for campaign star targets. It drives the same
## PveSession, map/weather/items, and deterministic AI used by the client.

const Ai = preload("res://ai/bingo_ai.gd")
const Campaign = preload("res://game_core/campaign_catalog.gd")
const Profiles = preload("res://game_core/profile_store.gd")
const Progression = preload("res://game_core/progression.gd")
const Session = preload("res://game_core/pve_session.gd")

const SAMPLES_PER_STAGE := 120
const MAX_PLAYER_ACTIONS := 240
const PLAYER_DIFFICULTY := "normal"


func _init() -> void:
    var stages := Campaign.load_stages()
    if stages.size() != 46:
        push_error("Campaign data must expand to 46 stages before simulation.")
        quit(1)
        return
    var requested_stage_ids: Array = []
    var samples := SAMPLES_PER_STAGE
    for argument in OS.get_cmdline_user_args():
        if argument.begins_with("--samples="):
            samples = clampi(int(argument.trim_prefix("--samples=")), 1, 2000)
        elif int(argument) >= 1 and int(argument) <= 46:
            requested_stage_ids.append(int(argument))
    if requested_stage_ids.is_empty():
        requested_stage_ids = Campaign.stage_ids(stages)
    print("stage,chapter,wins,losses,timeouts,one_star,two_star,three_star,samples,win_rate,round_p25,round_p50,round_p75,hp_pct_p25,hp_pct_p50,hp_pct_p75")
    for stage_id in requested_stage_ids:
        var result := _simulate_stage(stages[stage_id], samples)
        print("%d,%d,%d,%d,%d,%d,%d,%d,%d,%.3f,%d,%d,%d,%.3f,%.3f,%.3f" % [
            stage_id,
            int(stages[stage_id]["chapter"]),
            int(result["wins"]),
            int(result["losses"]),
            int(result["timeouts"]),
            int(result["one_star"]),
            int(result["two_star"]),
            int(result["three_star"]),
            samples,
            float(result["win_rate"]),
            int(result["round_p25"]),
            int(result["round_p50"]),
            int(result["round_p75"]),
            float(result["hp_pct_p25"]),
            float(result["hp_pct_p50"]),
            float(result["hp_pct_p75"]),
        ])
    quit(0)


func _simulate_stage(stage: Dictionary, samples: int) -> Dictionary:
    var clear_rounds: Array = []
    var hp_percentages: Array = []
    var losses := 0
    var timeouts := 0
    var star_counts := [0, 0, 0, 0]
    for sample_index in range(samples):
        var profile := Profiles.default_profile()
        # Equal castle levels isolate execution quality from long-term economy.
        profile["castle_level"] = int(stage["aiCastleLevel"])
        var session := Session.new(500000 + int(stage["id"]) * 1000 + sample_index, "hard", "平靜草原", profile, stage)
        _auto_play(session)
        if int(session.state.get("winner", -1)) != 0:
            if int(session.state.get("winner", -1)) == 1:
                losses += 1
            else:
                timeouts += 1
            continue
        clear_rounds.append(_completed_rounds(session.state))
        var player: Dictionary = session.state["players"][0]
        hp_percentages.append(float(player["castle_hp"]) / maxf(1.0, float(player["castle_hp_cap"])))
        var stars := Progression.stars_for_clear(stage, int(session.state.get("turns_completed", 0)))
        star_counts[stars] = int(star_counts[stars]) + 1
    clear_rounds.sort()
    hp_percentages.sort()
    return {
        "wins": clear_rounds.size(),
        "losses": losses,
        "timeouts": timeouts,
        "one_star": star_counts[1],
        "two_star": star_counts[2],
        "three_star": star_counts[3],
        "win_rate": float(clear_rounds.size()) / float(samples),
        "round_p25": _percentile_int(clear_rounds, 0.25),
        "round_p50": _percentile_int(clear_rounds, 0.50),
        "round_p75": _percentile_int(clear_rounds, 0.75),
        "hp_pct_p25": _percentile_float(hp_percentages, 0.25),
        "hp_pct_p50": _percentile_float(hp_percentages, 0.50),
        "hp_pct_p75": _percentile_float(hp_percentages, 0.75),
    }


func _auto_play(session: Session) -> void:
    for _step in range(MAX_PLAYER_ACTIONS):
        if int(session.state.get("winner", -1)) >= 0:
            return
        if not session.can_player_act():
            return
        var preview: Dictionary = session.state.duplicate(true)
        var planned := Ai.take_turn(preview, 0, session.config, false, PLAYER_DIFFICULTY)
        if not bool(planned.get("ok", false)):
            return
        var action: Dictionary = planned.get("action", {})
        var kind := str(action.get("action_kind", ""))
        if kind == "skip_follow":
            return
        var applied := session.submit_player_action(int(action.get("cell_index", -1)), kind)
        if not bool(applied.get("ok", false)):
            return


func _completed_rounds(state: Dictionary) -> int:
    return maxi(1, int(ceili(float(int(state.get("turns_completed", 0))) / 2.0)))


func _percentile_int(values: Array, percentile: float) -> int:
    if values.is_empty():
        return 0
    return int(values[clampi(int(floor(float(values.size() - 1) * percentile)), 0, values.size() - 1)])


func _percentile_float(values: Array, percentile: float) -> float:
    if values.is_empty():
        return 0.0
    return float(values[clampi(int(floor(float(values.size() - 1) * percentile)), 0, values.size() - 1)])
