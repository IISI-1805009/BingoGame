extends RefCounted
class_name CampaignCatalog

const SCHEMA_VERSION := 2
const FINAL_STAGE_ID := 46


static func load_stages(path: String = "res://data/campaign.json") -> Dictionary:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return {}
    var parsed = JSON.parse_string(file.get_as_text())
    if typeof(parsed) != TYPE_DICTIONARY or int(parsed.get("schemaVersion", 0)) != SCHEMA_VERSION:
        return {}
    var stages := {}
    var overrides: Dictionary = parsed.get("stageOverrides", {})
    for chapter in parsed.get("chapters", []):
        if not (chapter is Dictionary):
            return {}
        var stage_range: Array = chapter.get("stageRange", [])
        var names: Array = chapter.get("stageNames", [])
        var castle_levels: Array = chapter.get("aiCastleLevels", [])
        var star_targets: Array = chapter.get("starTargetsByStage", [])
        if stage_range.size() != 2:
            return {}
        var first_stage := int(stage_range[0])
        var final_stage := int(stage_range[1])
        var stage_count := final_stage - first_stage + 1
        if stage_count <= 0 or names.size() != stage_count or castle_levels.size() != stage_count or star_targets.size() != stage_count:
            return {}
        var item_sets: Array = chapter.get("aiItemsByStage", [])
        if not item_sets.is_empty() and item_sets.size() != stage_count:
            return {}
        for offset in range(stage_count):
            var stage_id := first_stage + offset
            if stage_id in stages:
                return {}
            var stage_star_targets = star_targets[offset]
            if not (stage_star_targets is Array) or stage_star_targets.size() != 2:
                return {}
            var three_star_rounds := int(stage_star_targets[0])
            var two_star_rounds := int(stage_star_targets[1])
            if three_star_rounds <= 0 or two_star_rounds < three_star_rounds:
                return {}
            var stage := {
                "id": stage_id,
                "chapter": int(chapter.get("chapter", 0)),
                "chapterTitle": str(chapter.get("title", "")),
                "stageInChapter": offset + 1,
                "name": str(names[offset]),
                "mapId": str(chapter.get("mapId", "")),
                "aiCastleLevel": int(castle_levels[offset]),
                "aiDifficulty": str(chapter.get("aiDifficulty", "normal")),
                "classes": chapter.get("classes", []).duplicate(true),
                "rarityWeights": chapter.get("rarityWeights", {}).duplicate(true),
                "aiItems": item_sets[offset].duplicate(true) if not item_sets.is_empty() else [],
                "meritReward": int(chapter.get("meritReward", 0)),
                "starTargets": {"threeStarMaxRounds": three_star_rounds, "twoStarMaxRounds": two_star_rounds},
            }
            if stage_id < FINAL_STAGE_ID:
                stage["nextStage"] = stage_id + 1
            var override: Dictionary = overrides.get(str(stage_id), {})
            stage.merge(override, true)
            stages[stage_id] = stage
    if stages.size() != FINAL_STAGE_ID:
        return {}
    for stage_id in range(1, FINAL_STAGE_ID + 1):
        if stage_id not in stages:
            return {}
    return stages


static func get_stage(stage_id: int, stages: Dictionary = {}) -> Dictionary:
    var source := stages if not stages.is_empty() else load_stages()
    return source.get(stage_id, {}).duplicate(true)


static func stage_ids(stages: Dictionary = {}) -> Array:
    var source := stages if not stages.is_empty() else load_stages()
    var ids: Array = source.keys()
    ids.sort()
    return ids


## Kept as a source-compatible alias for older callers and replay tools.
static func representative_ids(stages: Dictionary = {}) -> Array:
    return stage_ids(stages)
