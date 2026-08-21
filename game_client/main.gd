extends Control

## Phase 1 client slice: two readable boards, local PvE actions, attack
## presentation, result modal, and deterministic restart.

const PveSession = preload("res://game_core/pve_session.gd")
const Maps = preload("res://game_core/map_catalog.gd")
const Weather = preload("res://game_core/weather_system.gd")
const Items = preload("res://game_core/item_system.gd")
const Rules = preload("res://game_core/bingo_rules.gd")
const Campaign = preload("res://game_core/campaign_catalog.gd")
const Profiles = preload("res://game_core/profile_store.gd")
const Progression = preload("res://game_core/progression.gd")

var state: Dictionary = {}
var session: PveSession
var player_grid: GridContainer
var opponent_grid: GridContainer
var status_label: Label
var hp_label: Label
var action_button: Button
var difficulty_selector: OptionButton
var map_selector: OptionButton
var replay_button: Button
var item_selector: OptionButton
var item_class_selector: OptionButton
var use_item_button: Button
var attack_overlay: Control
var attack_label: Label
var result_overlay: Control
var result_label: Label
var result_button: Button
var attack_tween: Tween
var seed_value := 20260821
var action_mode := "free"
var is_animating := false
var pending_result := false
var pending_target_item := ""
var profile: Dictionary = {}
var campaign_stages: Dictionary = {}
var current_stage: Dictionary = {}
var result_awarded := false
var hub_overlay: Control
var hub_profile_label: Label
var hub_training_selector: OptionButton
var campaign_overlay: Control
var campaign_list: VBoxContainer
var result_campaign_button: Button
var result_next_button: Button


func _ready() -> void:
    profile = Profiles.load_profile()
    campaign_stages = Campaign.load_stages()
    _build_shell()
    _build_hub_overlay()
    _build_campaign_overlay()
    _new_preview_match()
    _show_hub()


func _build_shell() -> void:
    var background := ColorRect.new()
    background.color = Color("101827")
    background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(background)

    var margin := MarginContainer.new()
    margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    margin.add_theme_constant_override("margin_left", 12)
    margin.add_theme_constant_override("margin_top", 20)
    margin.add_theme_constant_override("margin_right", 12)
    margin.add_theme_constant_override("margin_bottom", 20)
    add_child(margin)

    var content := VBoxContainer.new()
    content.add_theme_constant_override("separation", 10)
    margin.add_child(content)

    var title := Label.new()
    title.text = "織城戰線 Woven Rampart"
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.add_theme_font_size_override("font_size", 28)
    content.add_child(title)

    var phase := Label.new()
    phase.text = "Phase 2｜完整單機戰役 46 關"
    phase.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    phase.add_theme_color_override("font_color", Color("9fb7d4"))
    content.add_child(phase)

    var difficulty_row := HBoxContainer.new()
    difficulty_row.alignment = BoxContainer.ALIGNMENT_CENTER
    difficulty_row.add_theme_constant_override("separation", 8)
    content.add_child(difficulty_row)
    var difficulty_label := Label.new()
    difficulty_label.text = "AI 難度"
    difficulty_row.add_child(difficulty_label)
    difficulty_selector = OptionButton.new()
    difficulty_selector.add_item("簡單", 0)
    difficulty_selector.set_item_metadata(0, "easy")
    difficulty_selector.add_item("一般", 1)
    difficulty_selector.set_item_metadata(1, "normal")
    difficulty_selector.add_item("困難", 2)
    difficulty_selector.set_item_metadata(2, "hard")
    difficulty_selector.select(1)
    difficulty_selector.item_selected.connect(_on_difficulty_selected)
    difficulty_row.add_child(difficulty_selector)

    var map_row := HBoxContainer.new()
    map_row.alignment = BoxContainer.ALIGNMENT_CENTER
    map_row.add_theme_constant_override("separation", 8)
    content.add_child(map_row)
    var map_label := Label.new()
    map_label.text = "戰場地圖"
    map_row.add_child(map_label)
    map_selector = OptionButton.new()
    var map_ids := Maps.map_ids()
    for index in range(map_ids.size()):
        map_selector.add_item(str(map_ids[index]), index)
        map_selector.set_item_metadata(index, str(map_ids[index]))
        if str(map_ids[index]) == Maps.DEFAULT_MAP_ID:
            map_selector.select(index)
    map_selector.item_selected.connect(_on_map_selected)
    map_row.add_child(map_selector)

    var item_row := HBoxContainer.new()
    item_row.alignment = BoxContainer.ALIGNMENT_CENTER
    item_row.add_theme_constant_override("separation", 6)
    content.add_child(item_row)
    var item_label := Label.new()
    item_label.text = "道具"
    item_row.add_child(item_label)
    item_selector = OptionButton.new()
    var item_ids: Array = Items.load_items().keys()
    for index in range(item_ids.size()):
        item_selector.add_item(str(item_ids[index]), index)
        item_selector.set_item_metadata(index, str(item_ids[index]))
    item_selector.item_selected.connect(_on_item_selected)
    item_row.add_child(item_selector)
    use_item_button = Button.new()
    use_item_button.text = "使用"
    use_item_button.pressed.connect(_use_selected_item)
    item_row.add_child(use_item_button)

    var item_target_row := HBoxContainer.new()
    item_target_row.alignment = BoxContainer.ALIGNMENT_CENTER
    item_target_row.add_theme_constant_override("separation", 6)
    content.add_child(item_target_row)
    var target_label := Label.new()
    target_label.text = "封印職業"
    item_target_row.add_child(target_label)
    item_class_selector = OptionButton.new()
    for index in range(Rules.ALL_CLASSES.size()):
        item_class_selector.add_item(str(Rules.ALL_CLASSES[index]), index)
        item_class_selector.set_item_metadata(index, str(Rules.ALL_CLASSES[index]))
    item_target_row.add_child(item_class_selector)

    status_label = Label.new()
    status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    status_label.custom_minimum_size = Vector2(0, 58)
    content.add_child(status_label)

    hp_label = Label.new()
    hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    hp_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    content.add_child(hp_label)

    var boards_row := HBoxContainer.new()
    boards_row.alignment = BoxContainer.ALIGNMENT_CENTER
    boards_row.add_theme_constant_override("separation", 8)
    boards_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    content.add_child(boards_row)

    var player_column := VBoxContainer.new()
    player_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    boards_row.add_child(player_column)
    var player_title := Label.new()
    player_title.text = "我方城堡"
    player_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    player_column.add_child(player_title)
    player_grid = _create_grid()
    player_column.add_child(player_grid)

    var opponent_column := VBoxContainer.new()
    opponent_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    boards_row.add_child(opponent_column)
    var opponent_title := Label.new()
    opponent_title.text = "敵方城堡"
    opponent_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    opponent_column.add_child(opponent_title)
    opponent_grid = _create_grid()
    opponent_column.add_child(opponent_grid)

    var hint := Label.new()
    hint.text = "敵方未認領格＝未知；敵方已認領格公開角色與建設等級。"
    hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    hint.add_theme_color_override("font_color", Color("9fb7d4"))
    content.add_child(hint)

    action_button = Button.new()
    action_button.text = "第二動作：自由選擇"
    action_button.pressed.connect(_toggle_action_mode)
    content.add_child(action_button)

    var reset_button := Button.new()
    reset_button.text = "重新開始本局"
    reset_button.pressed.connect(_new_preview_match)
    content.add_child(reset_button)

    replay_button = Button.new()
    replay_button.text = "驗證本局重播"
    replay_button.pressed.connect(_verify_replay)
    content.add_child(replay_button)

    var footer := Label.new()
    footer.text = "連線後會顯示出擊演出；勝負後可重新開始"
    footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    footer.add_theme_color_override("font_color", Color("7185a0"))
    content.add_child(footer)

    _build_attack_overlay()
    _build_result_overlay()


func _create_grid() -> GridContainer:
    var grid := GridContainer.new()
    grid.columns = 5
    grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    grid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    return grid


func _build_attack_overlay() -> void:
    attack_overlay = Control.new()
    attack_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    attack_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
    attack_overlay.visible = false
    add_child(attack_overlay)

    var shade := ColorRect.new()
    shade.color = Color(0.02, 0.04, 0.08, 0.9)
    shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    attack_overlay.add_child(shade)

    var center := CenterContainer.new()
    center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    attack_overlay.add_child(center)

    var panel := PanelContainer.new()
    panel.custom_minimum_size = Vector2(300, 180)
    center.add_child(panel)
    var box := VBoxContainer.new()
    box.add_theme_constant_override("separation", 12)
    panel.add_child(box)

    var title := Label.new()
    title.text = "連線出擊"
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.add_theme_font_size_override("font_size", 24)
    box.add_child(title)

    attack_label = Label.new()
    attack_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    attack_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    box.add_child(attack_label)

    var skip := Button.new()
    skip.text = "跳過演出"
    skip.pressed.connect(_hide_attack_overlay)
    box.add_child(skip)


func _build_result_overlay() -> void:
    result_overlay = Control.new()
    result_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    result_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
    result_overlay.visible = false
    add_child(result_overlay)

    var shade := ColorRect.new()
    shade.color = Color(0.02, 0.04, 0.08, 0.94)
    shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    result_overlay.add_child(shade)

    var center := CenterContainer.new()
    center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    result_overlay.add_child(center)

    var panel := PanelContainer.new()
    panel.custom_minimum_size = Vector2(300, 200)
    center.add_child(panel)
    var box := VBoxContainer.new()
    box.add_theme_constant_override("separation", 14)
    panel.add_child(box)

    var title := Label.new()
    title.text = "戰鬥結算"
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.add_theme_font_size_override("font_size", 26)
    box.add_child(title)

    result_label = Label.new()
    result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    box.add_child(result_label)

    result_button = Button.new()
    result_button.text = "再來一場"
    result_button.pressed.connect(_on_result_restart)
    box.add_child(result_button)

    result_next_button = Button.new()
    result_next_button.text = "挑戰下一關"
    result_next_button.pressed.connect(_on_result_next_stage)
    box.add_child(result_next_button)

    result_campaign_button = Button.new()
    result_campaign_button.text = "返回戰役地圖"
    result_campaign_button.pressed.connect(_show_campaign)
    box.add_child(result_campaign_button)


func _build_hub_overlay() -> void:
    hub_overlay = Control.new()
    hub_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    hub_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
    add_child(hub_overlay)
    var shade := ColorRect.new()
    shade.color = Color("101827")
    shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    hub_overlay.add_child(shade)
    var center := CenterContainer.new()
    center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    hub_overlay.add_child(center)
    var panel := PanelContainer.new()
    panel.custom_minimum_size = Vector2(360, 560)
    center.add_child(panel)
    var box := VBoxContainer.new()
    box.add_theme_constant_override("separation", 12)
    panel.add_child(box)
    var title := Label.new()
    title.text = "織城戰線｜主城"
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.add_theme_font_size_override("font_size", 28)
    box.add_child(title)
    hub_profile_label = Label.new()
    hub_profile_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    hub_profile_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    box.add_child(hub_profile_label)
    var campaign_button := Button.new()
    campaign_button.text = "進入戰役"
    campaign_button.pressed.connect(_show_campaign)
    box.add_child(campaign_button)
    var castle_button := Button.new()
    castle_button.text = "升級城堡"
    castle_button.pressed.connect(_upgrade_castle)
    box.add_child(castle_button)
    var training_label := Label.new()
    training_label.text = "職業訓練所"
    training_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    box.add_child(training_label)
    hub_training_selector = OptionButton.new()
    for index in range(Rules.ALL_CLASSES.size()):
        hub_training_selector.add_item(str(Rules.ALL_CLASSES[index]), index)
        hub_training_selector.set_item_metadata(index, str(Rules.ALL_CLASSES[index]))
    hub_training_selector.item_selected.connect(_on_hub_training_selected)
    box.add_child(hub_training_selector)
    var training_button := Button.new()
    training_button.text = "升級選定職業"
    training_button.pressed.connect(_upgrade_training)
    box.add_child(training_button)
    var quick_button := Button.new()
    quick_button.text = "自由測試戰鬥"
    quick_button.pressed.connect(_start_free_battle)
    box.add_child(quick_button)
    var note := Label.new()
    note.text = "星級以完成輪數評定；各關的二、三星目標可在戰役地圖查看。"
    note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    note.add_theme_color_override("font_color", Color("9fb7d4"))
    box.add_child(note)


func _build_campaign_overlay() -> void:
    campaign_overlay = Control.new()
    campaign_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    campaign_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
    campaign_overlay.visible = false
    add_child(campaign_overlay)
    var shade := ColorRect.new()
    shade.color = Color("101827")
    shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    campaign_overlay.add_child(shade)
    var center := CenterContainer.new()
    center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    campaign_overlay.add_child(center)
    var panel := PanelContainer.new()
    panel.custom_minimum_size = Vector2(440, 680)
    center.add_child(panel)
    var margin := MarginContainer.new()
    margin.add_theme_constant_override("margin_left", 14)
    margin.add_theme_constant_override("margin_top", 14)
    margin.add_theme_constant_override("margin_right", 14)
    margin.add_theme_constant_override("margin_bottom", 14)
    panel.add_child(margin)
    var layout := VBoxContainer.new()
    layout.add_theme_constant_override("separation", 10)
    margin.add_child(layout)
    var title := Label.new()
    title.text = "戰役地圖｜全 46 關"
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.add_theme_font_size_override("font_size", 26)
    layout.add_child(title)
    var scroll := ScrollContainer.new()
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    layout.add_child(scroll)
    campaign_list = VBoxContainer.new()
    campaign_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    campaign_list.add_theme_constant_override("separation", 10)
    scroll.add_child(campaign_list)
    var back := Button.new()
    back.text = "返回主城"
    back.pressed.connect(_show_hub)
    layout.add_child(back)


func _refresh_hub() -> void:
    var castle_level := int(profile.get("castle_level", 1))
    var selected_class := "劍士"
    if hub_training_selector != null:
        selected_class = str(hub_training_selector.get_item_metadata(hub_training_selector.selected))
    var training_level := int(profile.get("class_training", {}).get(selected_class, 1))
    hub_profile_label.text = "%s｜玩家 Lv.%d｜經驗 %d\n戰功 %d｜城堡 Lv.%d（HP %.0f／DEF %.0f）\n%s訓練 Lv.%d｜下次費用 %d" % [
        str(profile.get("display_name", "城主")), int(profile.get("level", 1)), int(profile.get("exp", 0)),
        int(profile.get("merit_points", 0)), castle_level, Progression.castle_hp(castle_level), Progression.castle_def(castle_level),
        selected_class, training_level, Progression.training_upgrade_cost(training_level),
    ]


func _refresh_campaign() -> void:
    for child in campaign_list.get_children():
        campaign_list.remove_child(child)
        child.queue_free()
    var unlocked: Array = profile.get("unlocked_stages", [1])
    var progress: Dictionary = profile.get("campaign_progress", {})
    var current_chapter := 0
    for stage_id in Campaign.stage_ids(campaign_stages):
        var stage: Dictionary = campaign_stages[stage_id]
        var chapter := int(stage.get("chapter", 0))
        if chapter != current_chapter:
            current_chapter = chapter
            var chapter_label := Label.new()
            chapter_label.text = "第 %d 章｜%s" % [chapter, str(stage.get("chapterTitle", ""))]
            chapter_label.add_theme_font_size_override("font_size", 20)
            chapter_label.add_theme_color_override("font_color", Color("f0c674"))
            campaign_list.add_child(chapter_label)
        var button := Button.new()
        var stage_result: Dictionary = progress.get(str(stage_id), {})
        var cleared := bool(stage_result.get("cleared", false))
        var locked := int(stage_id) not in unlocked
        var targets: Dictionary = stage.get("starTargets", {})
        button.text = "Stage %02d｜%s｜AI Lv.%d%s\n★3 ≤ %d 輪｜★2 ≤ %d 輪" % [
            int(stage_id), str(stage["name"]), int(stage["aiCastleLevel"]), "｜%s" % _star_text(int(stage_result.get("stars", 0))) if cleared else ("｜未解鎖" if locked else ""),
            int(targets.get("threeStarMaxRounds", 0)), int(targets.get("twoStarMaxRounds", 0)),
        ]
        button.tooltip_text = "%s｜首通戰功 %d｜二星 ≤ %d 輪｜三星 ≤ %d 輪｜%d 個 AI 道具" % [
            str(stage["mapId"]), int(stage.get("meritReward", 0)), int(targets.get("twoStarMaxRounds", 0)), int(targets.get("threeStarMaxRounds", 0)), stage.get("aiItems", []).size(),
        ]
        button.disabled = locked
        button.pressed.connect(_start_stage.bind(int(stage_id)))
        campaign_list.add_child(button)


func _show_hub() -> void:
    result_overlay.visible = false
    campaign_overlay.visible = false
    hub_overlay.visible = true
    difficulty_selector.disabled = false
    map_selector.disabled = false
    _refresh_hub()


func _show_campaign() -> void:
    result_overlay.visible = false
    hub_overlay.visible = false
    campaign_overlay.visible = true
    _refresh_campaign()


func _start_free_battle() -> void:
    current_stage = {}
    hub_overlay.visible = false
    difficulty_selector.disabled = false
    map_selector.disabled = false
    _new_preview_match()


func _start_stage(stage_id: int) -> void:
    current_stage = Campaign.get_stage(stage_id, campaign_stages)
    if current_stage.is_empty():
        return
    campaign_overlay.visible = false
    difficulty_selector.disabled = true
    map_selector.disabled = true
    _new_preview_match()


func _upgrade_castle() -> void:
    var result := Progression.upgrade_castle(profile)
    if bool(result.get("ok", false)):
        Profiles.save_profile(profile)
    _refresh_hub()
    if not bool(result.get("ok", false)):
        hub_profile_label.text += "\n升級失敗：%s" % result.get("error", "UNKNOWN_ERROR")


func _upgrade_training() -> void:
    var class_id := str(hub_training_selector.get_item_metadata(hub_training_selector.selected))
    var result := Progression.upgrade_training(profile, class_id)
    if bool(result.get("ok", false)):
        Profiles.save_profile(profile)
    _refresh_hub()
    if not bool(result.get("ok", false)):
        hub_profile_label.text += "\n升級失敗：%s" % result.get("error", "UNKNOWN_ERROR")


func _on_hub_training_selected(_index: int) -> void:
    _refresh_hub()


func _new_preview_match() -> void:
    _hide_attack_overlay()
    result_overlay.visible = false
    pending_result = false
    pending_target_item = ""
    result_awarded = false
    seed_value += 1
    var difficulty := "normal"
    if difficulty_selector != null:
        difficulty = str(difficulty_selector.get_item_metadata(difficulty_selector.selected))
    var selected_map := Maps.DEFAULT_MAP_ID
    if map_selector != null:
        selected_map = str(map_selector.get_item_metadata(map_selector.selected))
    session = PveSession.new(seed_value, difficulty, selected_map, profile, current_stage)
    state = session.snapshot()
    action_mode = "free"
    _refresh()


func _toggle_action_mode() -> void:
    if is_animating:
        return
    action_mode = "build" if action_mode == "free" else "free"
    _refresh()


func _on_difficulty_selected(_index: int) -> void:
    if session != null:
        _new_preview_match()


func _on_map_selected(_index: int) -> void:
    if session != null:
        _new_preview_match()


func _verify_replay() -> void:
    if session == null or is_animating:
        return
    var replayed := PveSession.replay(session.export_replay())
    if bool(replayed.get("ok", false)) and bool(replayed.get("matches_expected", false)):
        status_label.text = "重播驗證成功：相同 seed 與 Action log 得到完全相同局面。"
    else:
        status_label.text = "重播驗證失敗：%s" % replayed.get("error", "STATE_MISMATCH")


func _on_item_selected(_index: int) -> void:
    if state.is_empty():
        return
    _refresh()


func _use_selected_item() -> void:
    if session == null or is_animating or item_selector.item_count == 0:
        return
    var item_id := str(item_selector.get_item_metadata(item_selector.selected))
    if item_id == "換防令":
        pending_target_item = item_id
        _refresh()
        status_label.text = "換防令：請點選一個己方已認領格。"
        return
    var target := {}
    if item_id == "職業封印":
        target["class_id"] = str(item_class_selector.get_item_metadata(item_class_selector.selected))
    _submit_item(item_id, target)


func _submit_item(item_id: String, target: Dictionary) -> void:
    var result := session.submit_player_item(item_id, target)
    state = session.snapshot()
    pending_target_item = ""
    if not bool(result.get("ok", false)):
        _refresh()
        status_label.text = "道具無法使用：%s" % result.get("error", "UNKNOWN_ERROR")
        return
    var events: Array = result.get("events", [])
    _refresh(events)
    if int(state.get("winner", -1)) >= 0:
        _show_result_overlay()


func _on_cell_pressed(cell_index: int) -> void:
    if state.is_empty() or is_animating or not session.can_player_act():
        return
    if not pending_target_item.is_empty():
        _submit_item(pending_target_item, {"cell_index": cell_index})
        return
    var requested_mode := action_mode
    var selected_cell: Dictionary = state["players"][0]["board"][cell_index]
    if selected_cell.get("status", "normal") == "buried":
        requested_mode = "clear_rubble"
    elif state["action_stage"] == "opening_free":
        requested_mode = "free"
    elif state["action_stage"] == "follow":
        requested_mode = "follow"
    var result: Dictionary = session.submit_player_action(cell_index, requested_mode)
    state = session.snapshot()
    if not bool(result.get("ok", false)):
        _refresh()
        status_label.text = "尚不能操作：%s" % result.get("error", "UNKNOWN_ERROR")
        return
    var events: Array = result.get("events", [])
    _refresh(events)
    if _has_attack_event(events):
        pending_result = int(state.get("winner", -1)) >= 0
        _show_attack_overlay(events)
    elif int(state.get("winner", -1)) >= 0:
        _show_result_overlay()


func _refresh(events: Array = []) -> void:
    if state.is_empty():
        return
    _render_board(player_grid, state["players"][0]["board"], false)
    _render_board(opponent_grid, state["players"][1]["board"], true)

    var current := int(state["current_player"])
    var stage: String = state["action_stage"]
    var target = state["chain_target"][0]
    var target_text := "無（開局自由選擇）" if target == null else str(target)
    var weather: Dictionary = state.get("weather", {})
    var weather_text := Weather.display_name(weather.get("kind", null))
    if weather.get("kind", null) != null:
        weather_text += "（剩 %d 輪）" % int(weather.get("rounds_left", 0))
    status_label.text = "%s｜第 %d 輪｜天氣：%s\n階段：%s｜目前玩家：%d｜跟色：%s" % [
        str(state.get("map_id", Maps.DEFAULT_MAP_ID)), int(state.get("round", 1)), weather_text, stage, current, target_text,
    ]
    if bool(current_stage.get("tutorial", false)):
        status_label.text = _tutorial_instruction() + "\n" + status_label.text
    var event_summary := _summarize_events(events)
    if not event_summary.is_empty():
        status_label.text = event_summary
    hp_label.text = "我方戰力：%.0f / %.0f　｜　敵方戰力：%.0f / %.0f" % [
        float(state["players"][0]["castle_hp"]),
        float(state["players"][0]["castle_hp_cap"]),
        float(state["players"][1]["castle_hp"]),
        float(state["players"][1]["castle_hp_cap"]),
    ]
    action_button.disabled = stage != "second_action" or current != 0 or is_animating or int(state.get("winner", -1)) >= 0
    action_button.text = "第二動作：建設" if action_mode == "build" else "第二動作：自由選擇"
    var selected_item := "" if item_selector == null or item_selector.item_count == 0 else str(item_selector.get_item_metadata(item_selector.selected))
    var remaining := int(state.get("item_counts", [{}, {}])[0].get(selected_item, 0)) if not selected_item.is_empty() else 0
    use_item_button.disabled = current != 0 or remaining <= 0 or is_animating or int(state.get("winner", -1)) >= 0
    use_item_button.text = "使用（剩 %d）" % remaining


func _tutorial_instruction() -> String:
    var stage: String = state.get("action_stage", "")
    if int(state.get("turns_completed", 0)) == 0:
        return "教學 1/4：點選己方任一格，完成第一手自由選擇。"
    if stage == "follow":
        return "教學 2/4：選擇與跟色提示相同職業的格子。"
    if stage == "second_action":
        return "教學 3/4：再自由選一格，或切換成建設強化已認領格。"
    return "教學 4/4：持續累積五格連線，觀察出擊與建築工回復。"


func _render_board(grid: GridContainer, board: Array, is_opponent: bool) -> void:
    for child in grid.get_children():
        child.queue_free()
    for index in range(board.size()):
        var cell: Dictionary = board[index]
        var claimed := bool(cell["claimed"])
        var is_public: bool = (not is_opponent or claimed) and not (not claimed and cell.get("status", "normal") == "fogged")
        var button := Button.new()
        button.custom_minimum_size = Vector2(42, 56)
        button.add_theme_font_size_override("font_size", 8)
        button.text = _cell_text(cell, is_public)
        button.tooltip_text = _cell_tooltip(cell, is_public, index, is_opponent)
        if not is_opponent:
            button.pressed.connect(_on_cell_pressed.bind(index))
        button.disabled = is_opponent or not _cell_is_actionable(cell)
        button.modulate = _cell_color(cell, is_opponent, is_public)
        grid.add_child(button)


func _cell_text(cell: Dictionary, is_public: bool) -> String:
    if not is_public:
        if cell.get("status", "normal") == "fogged":
            return "?\n迷霧"
        return "?\n未知"
    var class_id := str(cell["class_id"])
    var short_class := class_id.substr(0, mini(2, class_id.length()))
    var level_mark := "◆" if int(cell["construction_level"]) > 1 else ""
    return "%s\n%s%s" % [short_class, str(cell["rarity"]).substr(0, 1), level_mark]


func _cell_tooltip(cell: Dictionary, is_public: bool, index: int, is_opponent: bool) -> String:
    if not is_public:
        if not is_opponent and cell.get("status", "normal") == "fogged":
            return "己方格子 %d｜迷霧遮蔽，選中後揭露" % (index + 1)
        return "敵方格子 %d｜未認領｜未知" % (index + 1)
    var status_text := "" if cell.get("status", "normal") == "normal" else "｜狀態 %s" % str(cell.get("status", "normal"))
    return "%s｜稀有度 %s｜建設 Lv.%d%s" % [cell["class_id"], cell["rarity"], int(cell["construction_level"]), status_text]


func _cell_color(cell: Dictionary, is_opponent: bool, is_public: bool) -> Color:
    if cell.get("status", "normal") == "frozen":
        return Color("85d7ff")
    if cell.get("status", "normal") == "buried":
        return Color("8b7355")
    if cell.get("status", "normal") == "fogged":
        return Color("70758c")
    if not is_public:
        return Color("586579")
    if bool(cell["claimed"]):
        return Color("b06cff") if is_opponent else Color("79b8ff")
    if cell["rarity"] == "金":
        return Color("ffd866")
    if cell["rarity"] == "紅":
        return Color("ff8c8c")
    return Color("d9e2ee")


func _cell_is_actionable(cell: Dictionary) -> bool:
    if is_animating or int(state.get("winner", -1)) >= 0 or int(state["current_player"]) != 0:
        return false
    var stage: String = state["action_stage"]
    var status: String = cell.get("status", "normal")
    if not pending_target_item.is_empty():
        return pending_target_item == "換防令" and bool(cell["claimed"]) and status == "normal"
    if status == "buried":
        return true
    if status not in ["normal", "fogged"]:
        return false
    if state.get("class_seals", [{}, {}])[0].has(cell["class_id"]):
        return false
    if stage == "second_action" and action_mode == "build":
        return bool(cell["claimed"]) and status == "normal"
    if stage == "follow":
        return not bool(cell["claimed"]) and cell["class_id"] == state["chain_target"][0]
    return not bool(cell["claimed"])


func _has_attack_event(events: Array) -> bool:
    for event in events:
        if event.get("type", "") in ["castle_hit", "single_attack_resolved", "attack_batch_resolved"]:
            return true
    return false


func _summarize_events(events: Array) -> String:
    var rows := []
    for event in events:
        var event_type: String = event.get("type", "")
        if event_type == "line_completed":
            var passive_text := ""
            var passives: Array = event.get("passives", [])
            if not passives.is_empty():
                passive_text = "（%s）" % "、".join(passives)
            rows.append("%s完成連線%s" % [_side_name(int(event.get("player_index", 0))), passive_text])
        elif event_type == "castle_hit":
            rows.append("%s出擊，造成 %.0f 傷害" % [_side_name(int(event.get("player_index", 0))), float(event.get("damage", 0.0))])
        elif event_type == "single_attack_resolved":
            rows.append("%s出擊，造成 %.0f 傷害" % [_side_name(int(event.get("player_index", 0))), float(event.get("damage", 0.0))])
        elif event_type == "attack_batch_resolved":
            rows.append("中央交鋒：我方 %.0f vs 敵方 %.0f" % [float(event.get("power_0", 0.0)), float(event.get("power_1", 0.0))])
            if bool(event.get("equal_power", false)):
                rows.append("戰力相等，雙方部隊同歸於盡")
            else:
                var survivor := 0 if float(event.get("survivor_power_0", 0.0)) > 0.0 else 1
                rows.append("%s倖存部隊攻城" % _side_name(survivor))
        elif event_type == "built":
            rows.append("我方完成建設 Lv.%d" % int(event.get("level", 1)))
        elif event_type == "follow_skipped":
            rows.append("%s沒有可跟色格，本回合跳過" % _side_name(int(event.get("player_index", 0))))
        elif event_type == "weather_triggered":
            rows.append("天氣觸發：%s（%d 輪）" % [str(event.get("display_name", "未知")), int(event.get("duration", 0))])
        elif event_type == "weather_ended":
            rows.append("%s結束" % str(event.get("display_name", "天氣")))
        elif event_type == "fog_revealed":
            rows.append("迷霧揭露：%s" % str(event.get("class_id", "未知")))
        elif event_type == "rubble_cleared":
            rows.append("%s清除落石" % _side_name(int(event.get("player_index", 0))))
        elif event_type == "item_used":
            rows.append("%s使用 %s" % [_side_name(int(event.get("player_index", 0))), str(event.get("item_id", "道具"))])
        elif event_type == "plague_resolved":
            rows.append("瘟疫擊殺 %d 格、忍者迴避 %d 格" % [event.get("killed", []).size(), event.get("evaded", []).size()])
        elif event_type == "class_sealed":
            rows.append("封印職業：%s" % str(event.get("class_id", "未知")))
        elif event_type == "mine_triggered":
            rows.append("踩中地雷，士兵死亡")
        elif event_type == "mine_evaded":
            rows.append("忍者避開地雷")
        elif event_type == "board_reset":
            rows.append("兵符 LV2 重整整張盤面")
        elif event_type == "boss_weather_heal":
            rows.append("終焉庇護回復 %.0f 戰力" % float(event.get("amount", 0.0)))
    return "　".join(rows)


func _side_name(player_index: int) -> String:
    return "我方" if player_index == 0 else "敵方"


func _show_attack_overlay(events: Array) -> void:
    var rows := ["城門開啟 → 部隊衝出 → 戰場演出"]
    for event in events:
        var event_type: String = event.get("type", "")
        if event_type == "attack_batch_resolved":
            rows.append("中央碰撞：我方 %.0f vs 敵方 %.0f" % [
                float(event.get("power_0", 0.0)),
                float(event.get("power_1", 0.0)),
            ])
            if bool(event.get("equal_power", false)):
                rows.append("戰力相等，雙方士兵消散，沒有城堡傷害")
            else:
                var survivor := 0 if float(event.get("survivor_power_0", 0.0)) > 0.0 else 1
                var survivor_power := float(event.get("survivor_power_0", 0.0)) if survivor == 0 else float(event.get("survivor_power_1", 0.0))
                var damage := float(event.get("damage_to_1", 0.0)) if survivor == 0 else float(event.get("damage_to_0", 0.0))
                rows.append("%s倖存 %.0f 戰力，攻城造成 %.0f 傷害" % [_side_name(survivor), survivor_power, damage])
        elif event_type == "single_attack_resolved":
            rows.append("%s部隊攻城：傷害 %.0f" % [
                _side_name(int(event.get("player_index", 0))),
                float(event.get("damage", 0.0)),
            ])
            if float(event.get("true_damage", 0.0)) > 0.0:
                rows.append("劍士追加無視 DEF 傷害 %.0f" % float(event.get("true_damage", 0.0)))
        elif event_type == "castle_hit":
            rows.append("%s部隊：戰力 %.0f，城堡傷害 %.0f" % [
                _side_name(int(event.get("player_index", 0))),
                float(event.get("attack_power", 0.0)),
                float(event.get("damage", 0.0)),
            ])
    attack_label.text = "\n".join(rows)
    is_animating = true
    attack_overlay.visible = true
    attack_overlay.modulate.a = 0.0
    attack_tween = create_tween()
    attack_tween.tween_property(attack_overlay, "modulate:a", 1.0, 0.16)
    attack_tween.tween_interval(0.9)
    attack_tween.tween_property(attack_overlay, "modulate:a", 0.0, 0.16)
    attack_tween.tween_callback(_hide_attack_overlay)


func _hide_attack_overlay() -> void:
    if attack_tween != null and attack_tween.is_valid():
        attack_tween.kill()
    attack_overlay.visible = false
    is_animating = false
    _refresh()
    if pending_result:
        pending_result = false
        _show_result_overlay()


func _show_result_overlay() -> void:
    var winner := int(state.get("winner", -1))
    if winner == 0:
        result_label.text = "勝利！\n你成功突破敵方城堡。"
        if not current_stage.is_empty() and not result_awarded:
            var reward := Progression.award_stage_clear(profile, current_stage, int(state.get("turns_completed", 0)))
            Profiles.save_profile(profile)
            result_awarded = true
            result_label.text += "\n戰功 +%d｜經驗 +%d%s" % [
                int(reward.get("merit_earned", 0)), int(reward.get("exp_earned", 0)), "｜首次通關" if bool(reward.get("first_clear", false)) else "｜重複通關",
            ]
            result_label.text += "\n%s｜完成 %d 輪" % [_star_text(int(reward.get("stars", 1))), int(reward.get("clear_rounds", 1))]
            if bool(current_stage.get("boss", false)):
                result_label.text = "終焉領主已被擊敗！\n末日天候平息，戰役完成。" + result_label.text.substr(result_label.text.find("\n戰功"))
    else:
        result_label.text = "挑戰失敗\n重新調整選格與建設，再試一次。"
    result_button.text = "重新挑戰" if not current_stage.is_empty() else "再來一場"
    result_next_button.visible = winner == 0 and int(current_stage.get("nextStage", 0)) > 0
    result_campaign_button.visible = not current_stage.is_empty()
    result_overlay.visible = true


func _on_result_restart() -> void:
    _new_preview_match()


func _on_result_next_stage() -> void:
    var next_stage_id := int(current_stage.get("nextStage", 0))
    if next_stage_id > 0:
        _start_stage(next_stage_id)


func _star_text(stars: int) -> String:
    var filled := "★".repeat(clampi(stars, 0, 3))
    var empty := "☆".repeat(3 - clampi(stars, 0, 3))
    return filled + empty
