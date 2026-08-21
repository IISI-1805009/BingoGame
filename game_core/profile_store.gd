extends RefCounted
class_name ProfileStore

const Rules = preload("res://game_core/bingo_rules.gd")
const SCHEMA_VERSION := 2
const FINAL_CAMPAIGN_STAGE := 46
const DEFAULT_PATH := "user://woven_rampart_profile.json"


static func default_profile() -> Dictionary:
    var training := {}
    for class_id in Rules.ALL_CLASSES:
        training[class_id] = 1
    return {
        "schema_version": SCHEMA_VERSION,
        "player_id": "local-player",
        "display_name": "城主",
        "level": 1,
        "exp": 0,
        "merit_points": 0,
        "honor_points": 0,
        "castle_level": 1,
        "class_training": training,
        "unlocked_classes": ["劍士", "弓手", "武士", "建築工"],
        "campaign_progress": {},
        "unlocked_stages": [1],
        "recovered_from_corrupt": false,
    }


static func load_profile(path: String = DEFAULT_PATH) -> Dictionary:
    if not FileAccess.file_exists(path):
        return default_profile()
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        var unavailable := default_profile()
        unavailable["recovered_from_corrupt"] = true
        return unavailable
    var parser := JSON.new()
    if parser.parse(file.get_as_text()) != OK or typeof(parser.data) != TYPE_DICTIONARY:
        var recovered := default_profile()
        recovered["recovered_from_corrupt"] = true
        return recovered
    return migrate_and_validate(parser.data)


static func save_profile(profile: Dictionary, path: String = DEFAULT_PATH) -> bool:
    var clean := migrate_and_validate(profile)
    clean["recovered_from_corrupt"] = false
    var temporary_path := path + ".tmp"
    var file := FileAccess.open(temporary_path, FileAccess.WRITE)
    if file == null:
        return false
    file.store_string(JSON.stringify(clean, "  "))
    file.close()
    var absolute_path := ProjectSettings.globalize_path(path)
    var absolute_temporary_path := ProjectSettings.globalize_path(temporary_path)
    if FileAccess.file_exists(path):
        DirAccess.remove_absolute(absolute_path)
    return DirAccess.rename_absolute(absolute_temporary_path, absolute_path) == OK


static func migrate_and_validate(raw: Dictionary) -> Dictionary:
    var profile := default_profile()
    var version := int(raw.get("schema_version", raw.get("schemaVersion", 0)))
    if version <= 0:
        raw = _migrate_legacy(raw)
        version = int(raw.get("schema_version", 1))
    if version < 2:
        raw = _migrate_v1_to_v2(raw)
    for key in profile:
        if raw.has(key):
            profile[key] = raw[key]
    profile["schema_version"] = SCHEMA_VERSION
    profile["level"] = clampi(int(profile["level"]), 1, 30)
    profile["exp"] = maxi(0, int(profile["exp"]))
    profile["merit_points"] = maxi(0, int(profile["merit_points"]))
    profile["honor_points"] = maxi(0, int(profile["honor_points"]))
    profile["castle_level"] = clampi(int(profile["castle_level"]), 1, 40)
    var training: Dictionary = profile["class_training"] if profile["class_training"] is Dictionary else {}
    for class_id in Rules.ALL_CLASSES:
        training[class_id] = clampi(int(training.get(class_id, 1)), 1, 10)
    profile["class_training"] = training
    if not (profile["unlocked_classes"] is Array):
        profile["unlocked_classes"] = ["劍士", "弓手", "武士", "建築工"]
    if not (profile["campaign_progress"] is Dictionary):
        profile["campaign_progress"] = {}
    if not (profile["unlocked_stages"] is Array):
        profile["unlocked_stages"] = [1]
    var unlocked_stages: Array = []
    for raw_stage_id in profile["unlocked_stages"]:
        var stage_id := int(raw_stage_id)
        if stage_id >= 1 and stage_id <= FINAL_CAMPAIGN_STAGE and stage_id not in unlocked_stages:
            unlocked_stages.append(stage_id)
    if 1 not in unlocked_stages:
        unlocked_stages.append(1)
    unlocked_stages.sort()
    profile["unlocked_stages"] = unlocked_stages
    return profile


static func _migrate_legacy(raw: Dictionary) -> Dictionary:
    var migrated := raw.duplicate(true)
    var key_map := {
        "meritPoints": "merit_points",
        "castleLevel": "castle_level",
        "classTraining": "class_training",
        "campaignProgress": "campaign_progress",
        "unlockedRepresentativeStages": "unlocked_representative_stages",
    }
    for old_key in key_map:
        if migrated.has(old_key) and not migrated.has(key_map[old_key]):
            migrated[key_map[old_key]] = migrated[old_key]
    migrated["schema_version"] = 1
    return migrated


static func _migrate_v1_to_v2(raw: Dictionary) -> Dictionary:
    var migrated := raw.duplicate(true)
    var unlocked: Array = [1]
    var legacy_unlocked = migrated.get("unlocked_representative_stages", [1])
    if legacy_unlocked is Array:
        for raw_stage_id in legacy_unlocked:
            var stage_id := int(raw_stage_id)
            if stage_id >= 1 and stage_id <= FINAL_CAMPAIGN_STAGE and stage_id not in unlocked:
                unlocked.append(stage_id)
    var progress = migrated.get("campaign_progress", {})
    if progress is Dictionary:
        for raw_stage_key in progress:
            var result = progress[raw_stage_key]
            if result is Dictionary and bool(result.get("cleared", false)):
                var cleared_stage := int(raw_stage_key)
                if cleared_stage >= 1 and cleared_stage < FINAL_CAMPAIGN_STAGE and cleared_stage + 1 not in unlocked:
                    unlocked.append(cleared_stage + 1)
    unlocked.sort()
    migrated["unlocked_stages"] = unlocked
    migrated.erase("unlocked_representative_stages")
    migrated["schema_version"] = 2
    return migrated
