extends RefCounted
class_name MapCatalog

const SCHEMA_VERSION := 1
const DEFAULT_MAP_ID := "平靜草原"


static func load_maps(path: String = "res://data/maps.json") -> Dictionary:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return {}
    var parsed = JSON.parse_string(file.get_as_text())
    if typeof(parsed) != TYPE_DICTIONARY or int(parsed.get("schemaVersion", 0)) != SCHEMA_VERSION:
        return {}
    var by_id := {}
    for entry in parsed.get("maps", []):
        if entry is Dictionary and not str(entry.get("id", "")).is_empty():
            by_id[str(entry["id"])] = entry.duplicate(true)
    return by_id


static func get_map(map_id: String, maps: Dictionary = {}) -> Dictionary:
    var source := maps if not maps.is_empty() else load_maps()
    if source.has(map_id):
        return source[map_id].duplicate(true)
    return source.get(DEFAULT_MAP_ID, {"id": DEFAULT_MAP_ID, "mainWeather": null, "bonuses": {}, "penalties": {}}).duplicate(true)


static func map_ids(maps: Dictionary = {}) -> Array:
    var source := maps if not maps.is_empty() else load_maps()
    return source.keys()


static func class_modifier(map_data: Dictionary, class_id: String, personal_exclusive = null) -> float:
    var terrain := 0.0
    if map_data.get("bonuses", {}).has(class_id):
        terrain = float(map_data["bonuses"][class_id])
    elif map_data.get("penalties", {}).has(class_id):
        terrain = float(map_data["penalties"][class_id])
    var personal := 0.15 if personal_exclusive != null and str(personal_exclusive) == class_id else 0.0
    # PvP deliberately takes the stronger modifier instead of stacking them.
    return maxf(terrain, personal) if personal > 0.0 else terrain


static func modifiers_for_player(map_data: Dictionary, classes: Array, personal_exclusive = null) -> Dictionary:
    var modifiers := {}
    for class_id in classes:
        modifiers[str(class_id)] = class_modifier(map_data, str(class_id), personal_exclusive)
    return modifiers
