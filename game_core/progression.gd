extends RefCounted
class_name Progression

const Rules = preload("res://game_core/bingo_rules.gd")


static func castle_hp(level: int) -> float:
    return 100.0 + float(clampi(level, 1, 40) - 1) * 25.0


static func castle_def(level: int) -> float:
    return 10.0 + float(clampi(level, 1, 40) - 1) * 3.0


static func castle_upgrade_cost(current_level: int) -> int:
    return 50 * (current_level + 1)


static func training_upgrade_cost(current_level: int) -> int:
    return 30 * (current_level + 1)


static func experience_for_next_level(current_level: int) -> int:
    return 100 * current_level


static func clear_rounds(clear_turns: int) -> int:
    # A displayed battle round contains one completed turn from each side.
    return maxi(1, int(ceili(float(maxi(0, clear_turns)) / 2.0)))


static func stars_for_clear(stage: Dictionary, clear_turns: int) -> int:
    var targets: Dictionary = stage.get("starTargets", {})
    var three_star_max := int(targets.get("threeStarMaxRounds", 0))
    var two_star_max := int(targets.get("twoStarMaxRounds", 0))
    if three_star_max <= 0 or two_star_max < three_star_max:
        return 1
    var completed := clear_rounds(clear_turns)
    if completed <= three_star_max:
        return 3
    if completed <= two_star_max:
        return 2
    return 1


static func upgrade_castle(profile: Dictionary) -> Dictionary:
    var level := int(profile.get("castle_level", 1))
    if level >= 40:
        return _failure("MAX_CASTLE_LEVEL")
    var cost := castle_upgrade_cost(level)
    if int(profile.get("merit_points", 0)) < cost:
        return _failure("INSUFFICIENT_MERIT")
    profile["merit_points"] = int(profile["merit_points"]) - cost
    profile["castle_level"] = level + 1
    return {"ok": true, "cost": cost, "level": level + 1}


static func upgrade_training(profile: Dictionary, class_id: String) -> Dictionary:
    if class_id not in Rules.ALL_CLASSES:
        return _failure("UNKNOWN_CLASS")
    var levels: Dictionary = profile["class_training"]
    var level := int(levels.get(class_id, 1))
    if level >= 10:
        return _failure("MAX_TRAINING_LEVEL")
    var cost := training_upgrade_cost(level)
    if int(profile.get("merit_points", 0)) < cost:
        return _failure("INSUFFICIENT_MERIT")
    profile["merit_points"] = int(profile["merit_points"]) - cost
    levels[class_id] = level + 1
    return {"ok": true, "cost": cost, "level": level + 1, "class_id": class_id}


static func award_stage_clear(profile: Dictionary, stage: Dictionary, clear_turns: int) -> Dictionary:
    var stage_key := str(int(stage.get("id", 0)))
    var progress: Dictionary = profile["campaign_progress"]
    var previous: Dictionary = progress.get(stage_key, {})
    var first_clear := not bool(previous.get("cleared", false))
    var base_merit := int(stage.get("meritReward", 0))
    var merit_earned := base_merit if first_clear else int(floor(float(base_merit) * 0.5))
    var exp_earned := 50 if first_clear else 0
    profile["merit_points"] = int(profile.get("merit_points", 0)) + merit_earned
    profile["exp"] = int(profile.get("exp", 0)) + exp_earned
    _refresh_player_level(profile)
    var best_turns := clear_turns
    if int(previous.get("best_clear_turns", 0)) > 0:
        best_turns = mini(best_turns, int(previous["best_clear_turns"]))
    var earned_stars := stars_for_clear(stage, clear_turns)
    var best_stars := maxi(int(previous.get("stars", 0)), earned_stars)
    progress[stage_key] = {"cleared": true, "stars": best_stars, "best_clear_turns": best_turns}
    if first_clear:
        var unlocked_class = stage.get("unlocksClass", null)
        if unlocked_class != null and unlocked_class not in profile["unlocked_classes"]:
            profile["unlocked_classes"].append(unlocked_class)
        for class_id in stage.get("unlocksClasses", []):
            if class_id not in profile["unlocked_classes"]:
                profile["unlocked_classes"].append(class_id)
        var next_stage := int(stage.get("nextStage", 0))
        if next_stage > 0 and next_stage not in profile["unlocked_stages"]:
            profile["unlocked_stages"].append(next_stage)
            profile["unlocked_stages"].sort()
    return {
        "ok": true,
        "first_clear": first_clear,
        "merit_earned": merit_earned,
        "exp_earned": exp_earned,
        "level": int(profile["level"]),
        "stars_earned": earned_stars,
        "stars": best_stars,
        "clear_rounds": clear_rounds(clear_turns),
        "unlocked_stage": int(stage.get("nextStage", 0)) if first_clear else 0,
    }


static func _refresh_player_level(profile: Dictionary) -> void:
    var level := 1
    var remaining := int(profile.get("exp", 0))
    while level < 30 and remaining >= experience_for_next_level(level):
        remaining -= experience_for_next_level(level)
        level += 1
    profile["level"] = level


static func _failure(error_code: String) -> Dictionary:
    return {"ok": false, "error": error_code}
