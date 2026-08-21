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
var hub_resource_label: Label
var hub_training_selector: OptionButton
var hub_training_status_label: Label
var campaign_overlay: Control
var campaign_list: VBoxContainer
var stage_detail_overlay: Control
var stage_detail: Dictionary = {}
var stage_detail_content: VBoxContainer
var stage_detail_start_button: Button
var battle_prep_overlay: Control
var battle_prep_content: VBoxContainer
var battle_prep_start_button: Button
var result_campaign_button: Button
var result_next_button: Button


func _ready() -> void:
    profile = Profiles.load_profile()
    campaign_stages = Campaign.load_stages()
    _build_shell()
    _build_hub_overlay()
    _build_campaign_overlay()
    _build_stage_detail_overlay()
    _build_battle_prep_overlay()
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

    var sky := ColorRect.new()
    sky.color = Color("2a9ee8")
    sky.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    hub_overlay.add_child(sky)
    var horizon := ColorRect.new()
    horizon.color = Color(0.42, 0.82, 0.96, 0.18)
    horizon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    horizon.mouse_filter = Control.MOUSE_FILTER_IGNORE
    hub_overlay.add_child(horizon)
    var cloud_left := Label.new()
    cloud_left.text = "☁"
    cloud_left.position = Vector2(18, 160)
    cloud_left.add_theme_font_size_override("font_size", 120)
    cloud_left.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.32))
    cloud_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
    hub_overlay.add_child(cloud_left)
    var cloud_right := Label.new()
    cloud_right.text = "☁"
    cloud_right.position = Vector2(545, 270)
    cloud_right.add_theme_font_size_override("font_size", 150)
    cloud_right.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.24))
    cloud_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
    hub_overlay.add_child(cloud_right)

    var center := CenterContainer.new()
    center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    hub_overlay.add_child(center)
    var panel := PanelContainer.new()
    panel.custom_minimum_size = Vector2(600, 1070)
    panel.add_theme_stylebox_override("panel", _panel_style(Color("173d7d"), Color("f5d274"), 28, 3))
    center.add_child(panel)

    var margin := MarginContainer.new()
    margin.add_theme_constant_override("margin_left", 24)
    margin.add_theme_constant_override("margin_top", 22)
    margin.add_theme_constant_override("margin_right", 24)
    margin.add_theme_constant_override("margin_bottom", 22)
    panel.add_child(margin)
    var box := VBoxContainer.new()
    box.add_theme_constant_override("separation", 14)
    margin.add_child(box)

    var top_row := HBoxContainer.new()
    top_row.add_theme_constant_override("separation", 12)
    box.add_child(top_row)
    var crest_panel := PanelContainer.new()
    crest_panel.custom_minimum_size = Vector2(86, 76)
    crest_panel.add_theme_stylebox_override("panel", _panel_style(Color("1d6bce"), Color("ffd764"), 22, 3))
    top_row.add_child(crest_panel)
    var crest := Label.new()
    crest.text = "♜"
    crest.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    crest.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    crest.add_theme_font_size_override("font_size", 46)
    crest.add_theme_color_override("font_color", Color("fff4bc"))
    crest_panel.add_child(crest)
    hub_resource_label = Label.new()
    hub_resource_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    hub_resource_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    hub_resource_label.add_theme_font_size_override("font_size", 17)
    hub_resource_label.add_theme_color_override("font_color", Color("fff8d8"))
    top_row.add_child(hub_resource_label)
    var settings_badge := Label.new()
    settings_badge.text = "⚙"
    settings_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    settings_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    settings_badge.custom_minimum_size = Vector2(62, 62)
    settings_badge.add_theme_font_size_override("font_size", 34)
    settings_badge.add_theme_color_override("font_color", Color("fff0ac"))
    top_row.add_child(settings_badge)

    var title := Label.new()
    title.text = "織城戰線"
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.add_theme_font_size_override("font_size", 48)
    title.add_theme_color_override("font_color", Color("fff0ac"))
    title.add_theme_color_override("font_shadow_color", Color("16325e"))
    title.add_theme_constant_override("shadow_offset_x", 3)
    title.add_theme_constant_override("shadow_offset_y", 4)
    box.add_child(title)

    var subtitle := Label.new()
    subtitle.text = "WOVEN RAMPART  ·  王國主城"
    subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    subtitle.add_theme_font_size_override("font_size", 15)
    subtitle.add_theme_color_override("font_color", Color("c4ebff"))
    box.add_child(subtitle)

    var castle_card := PanelContainer.new()
    castle_card.custom_minimum_size = Vector2(0, 232)
    castle_card.add_theme_stylebox_override("panel", _panel_style(Color("3a92df"), Color("ffe08b"), 26, 4))
    box.add_child(castle_card)
    var castle_box := VBoxContainer.new()
    castle_box.alignment = BoxContainer.ALIGNMENT_CENTER
    castle_box.add_theme_constant_override("separation", 4)
    castle_card.add_child(castle_box)
    var castle_icon := Label.new()
    castle_icon.text = "♜"
    castle_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    castle_icon.add_theme_font_size_override("font_size", 92)
    castle_icon.add_theme_color_override("font_color", Color("fff1b0"))
    castle_box.add_child(castle_icon)
    var castle_title := Label.new()
    castle_title.text = "晨曦城堡"
    castle_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    castle_title.add_theme_font_size_override("font_size", 24)
    castle_title.add_theme_color_override("font_color", Color.WHITE)
    castle_box.add_child(castle_title)
    hub_profile_label = Label.new()
    hub_profile_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    hub_profile_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    hub_profile_label.add_theme_font_size_override("font_size", 16)
    hub_profile_label.add_theme_color_override("font_color", Color("e3f5ff"))
    castle_box.add_child(hub_profile_label)

    var campaign_button := Button.new()
    campaign_button.text = "⚔  戰役遠征\n挑戰 46 關王國戰線"
    campaign_button.custom_minimum_size = Vector2(0, 98)
    campaign_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
    campaign_button.add_theme_font_size_override("font_size", 22)
    _style_primary_button(campaign_button, Color("319c57"), Color("52bd73"), Color("fff0a7"))
    campaign_button.pressed.connect(_show_campaign)
    box.add_child(campaign_button)

    var castle_button := Button.new()
    castle_button.text = "♜  城堡養成\n提升戰力值與防禦"
    castle_button.custom_minimum_size = Vector2(0, 82)
    castle_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
    castle_button.add_theme_font_size_override("font_size", 19)
    _style_primary_button(castle_button, Color("277bc9"), Color("469ce4"), Color("d9f3ff"))
    castle_button.pressed.connect(_upgrade_castle)
    box.add_child(castle_button)

    var training_card := PanelContainer.new()
    training_card.add_theme_stylebox_override("panel", _panel_style(Color("6449a6"), Color("dcb6ff"), 20, 3))
    box.add_child(training_card)
    var training_box := VBoxContainer.new()
    training_box.add_theme_constant_override("separation", 7)
    training_card.add_child(training_box)
    hub_training_status_label = Label.new()
    hub_training_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    hub_training_status_label.add_theme_font_size_override("font_size", 18)
    hub_training_status_label.add_theme_color_override("font_color", Color("fbecff"))
    training_box.add_child(hub_training_status_label)
    hub_training_selector = OptionButton.new()
    for index in range(Rules.ALL_CLASSES.size()):
        hub_training_selector.add_item(str(Rules.ALL_CLASSES[index]), index)
        hub_training_selector.set_item_metadata(index, str(Rules.ALL_CLASSES[index]))
    hub_training_selector.item_selected.connect(_on_hub_training_selected)
    hub_training_selector.add_theme_font_size_override("font_size", 18)
    hub_training_selector.add_theme_stylebox_override("normal", _panel_style(Color("443274"), Color("e0c2ff"), 14, 2))
    training_box.add_child(hub_training_selector)
    var training_button := Button.new()
    training_button.text = "✦  升級選定職業"
    training_button.custom_minimum_size = Vector2(0, 54)
    training_button.add_theme_font_size_override("font_size", 18)
    _style_primary_button(training_button, Color("7a57bb"), Color("9473d4"), Color("fff1ff"))
    training_button.pressed.connect(_upgrade_training)
    training_box.add_child(training_button)

    var quick_button := Button.new()
    quick_button.text = "自由演練"
    quick_button.custom_minimum_size = Vector2(0, 50)
    quick_button.add_theme_font_size_override("font_size", 17)
    _style_primary_button(quick_button, Color("cf7948"), Color("e99661"), Color("fff0cf"))
    quick_button.pressed.connect(_start_free_battle)
    box.add_child(quick_button)

    var note := Label.new()
    note.text = "★ 以完成輪數評定星級，二／三星目標顯示於戰役地圖。"
    note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    note.add_theme_color_override("font_color", Color("c8eaff"))
    box.add_child(note)

    var navigation := HBoxContainer.new()
    navigation.add_theme_constant_override("separation", 8)
    box.add_child(navigation)
    for entry in [["⌂\n主城", Color("2d88d5")], ["▤\n收藏", Color("8a6b50")], ["⚙\n設定", Color("8a6b50")]]:
        var nav_button := Button.new()
        nav_button.text = str(entry[0])
        nav_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        nav_button.custom_minimum_size = Vector2(0, 64)
        nav_button.add_theme_font_size_override("font_size", 17)
        _style_primary_button(nav_button, entry[1], Color("4b9fe0"), Color("fff0ac"))
        nav_button.disabled = entry[0] != "⌂\n主城"
        navigation.add_child(nav_button)


func _panel_style(fill: Color, border: Color, radius: int = 16, border_width: int = 2) -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    style.bg_color = fill
    style.border_color = border
    style.set_border_width_all(border_width)
    style.set_corner_radius_all(radius)
    style.set_content_margin_all(14)
    style.shadow_color = Color(0.04, 0.12, 0.25, 0.42)
    style.shadow_size = 6
    style.shadow_offset = Vector2(0, 4)
    return style


func _style_primary_button(button: Button, fill: Color, hover: Color, text_color: Color) -> void:
    button.add_theme_stylebox_override("normal", _panel_style(fill, Color("ffe18a"), 18, 3))
    button.add_theme_stylebox_override("hover", _panel_style(hover, Color("fff5bc"), 18, 3))
    button.add_theme_stylebox_override("pressed", _panel_style(fill.darkened(0.16), Color("ffe18a"), 18, 3))
    button.add_theme_stylebox_override("disabled", _panel_style(fill.darkened(0.38), Color("8090a7"), 18, 2))
    button.add_theme_color_override("font_color", text_color)
    button.add_theme_color_override("font_hover_color", Color.WHITE)
    button.add_theme_color_override("font_pressed_color", text_color)
    button.add_theme_color_override("font_disabled_color", Color("bec8d5"))


func _build_campaign_overlay() -> void:
    campaign_overlay = Control.new()
    campaign_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    campaign_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
    campaign_overlay.visible = false
    add_child(campaign_overlay)
    var sky := ColorRect.new()
    sky.color = Color("347fbd")
    sky.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    campaign_overlay.add_child(sky)
    var mist := Label.new()
    mist.text = "✦    ☁       ✦    ☁"
    mist.position = Vector2(34, 120)
    mist.add_theme_font_size_override("font_size", 46)
    mist.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.32))
    mist.mouse_filter = Control.MOUSE_FILTER_IGNORE
    campaign_overlay.add_child(mist)
    var center := CenterContainer.new()
    center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    campaign_overlay.add_child(center)
    var panel := PanelContainer.new()
    panel.custom_minimum_size = Vector2(610, 1080)
    panel.add_theme_stylebox_override("panel", _panel_style(Color("173d7d"), Color("f7d979"), 28, 3))
    center.add_child(panel)
    var margin := MarginContainer.new()
    margin.add_theme_constant_override("margin_left", 14)
    margin.add_theme_constant_override("margin_top", 14)
    margin.add_theme_constant_override("margin_right", 14)
    margin.add_theme_constant_override("margin_bottom", 14)
    panel.add_child(margin)
    var layout := VBoxContainer.new()
    layout.add_theme_constant_override("separation", 12)
    margin.add_child(layout)
    var title := Label.new()
    title.text = "王國戰役地圖"
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.add_theme_font_size_override("font_size", 34)
    title.add_theme_color_override("font_color", Color("fff0ac"))
    layout.add_child(title)
    var subtitle := Label.new()
    subtitle.text = "穿越十章領地，奪回織城戰線"
    subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    subtitle.add_theme_font_size_override("font_size", 16)
    subtitle.add_theme_color_override("font_color", Color("cceeff"))
    layout.add_child(subtitle)
    var scroll := ScrollContainer.new()
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    layout.add_child(scroll)
    campaign_list = VBoxContainer.new()
    campaign_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    campaign_list.add_theme_constant_override("separation", 12)
    scroll.add_child(campaign_list)
    var back := Button.new()
    back.text = "← 返回主城"
    back.custom_minimum_size = Vector2(0, 54)
    back.add_theme_font_size_override("font_size", 18)
    _style_primary_button(back, Color("356da8"), Color("4d91ca"), Color("ebf7ff"))
    back.pressed.connect(_show_hub)
    layout.add_child(back)


func _build_stage_detail_overlay() -> void:
    stage_detail_overlay = Control.new()
    stage_detail_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    stage_detail_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
    stage_detail_overlay.visible = false
    add_child(stage_detail_overlay)
    var backdrop := ColorRect.new()
    backdrop.color = Color("215a92")
    backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    stage_detail_overlay.add_child(backdrop)
    var center := CenterContainer.new()
    center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    stage_detail_overlay.add_child(center)
    var panel := PanelContainer.new()
    panel.custom_minimum_size = Vector2(610, 1080)
    panel.add_theme_stylebox_override("panel", _panel_style(Color("193d78"), Color("ffe08a"), 28, 3))
    center.add_child(panel)
    var margin := MarginContainer.new()
    margin.add_theme_constant_override("margin_left", 24)
    margin.add_theme_constant_override("margin_top", 22)
    margin.add_theme_constant_override("margin_right", 24)
    margin.add_theme_constant_override("margin_bottom", 22)
    panel.add_child(margin)
    var layout := VBoxContainer.new()
    layout.add_theme_constant_override("separation", 12)
    margin.add_child(layout)
    var heading := Label.new()
    heading.text = "關卡詳情"
    heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    heading.add_theme_font_size_override("font_size", 32)
    heading.add_theme_color_override("font_color", Color("fff0ac"))
    layout.add_child(heading)
    var scroll := ScrollContainer.new()
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    layout.add_child(scroll)
    stage_detail_content = VBoxContainer.new()
    stage_detail_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    stage_detail_content.add_theme_constant_override("separation", 12)
    scroll.add_child(stage_detail_content)
    stage_detail_start_button = Button.new()
    stage_detail_start_button.text = "⚔  前往備戰"
    stage_detail_start_button.custom_minimum_size = Vector2(0, 68)
    stage_detail_start_button.add_theme_font_size_override("font_size", 23)
    _style_primary_button(stage_detail_start_button, Color("319c57"), Color("52bd73"), Color("fff5bc"))
    stage_detail_start_button.pressed.connect(_start_stage_from_detail)
    layout.add_child(stage_detail_start_button)
    var back := Button.new()
    back.text = "← 返回戰役地圖"
    back.custom_minimum_size = Vector2(0, 48)
    back.add_theme_font_size_override("font_size", 17)
    _style_primary_button(back, Color("356da8"), Color("4d91ca"), Color("ebf7ff"))
    back.pressed.connect(_show_campaign)
    layout.add_child(back)


func _show_stage_detail(stage_id: int) -> void:
    stage_detail = Campaign.get_stage(stage_id, campaign_stages)
    if stage_detail.is_empty():
        return
    campaign_overlay.visible = false
    hub_overlay.visible = false
    stage_detail_overlay.visible = true
    _refresh_stage_detail()


func _refresh_stage_detail() -> void:
    for child in stage_detail_content.get_children():
        stage_detail_content.remove_child(child)
        child.queue_free()
    if stage_detail.is_empty():
        return
    var stage_id := int(stage_detail["id"])
    var progress: Dictionary = profile.get("campaign_progress", {}).get(str(stage_id), {})
    var unlocked: bool = stage_id in profile.get("unlocked_stages", [1])
    var map_data := Maps.get_map(str(stage_detail["mapId"]))
    var targets: Dictionary = stage_detail.get("starTargets", {})

    var title_card := PanelContainer.new()
    title_card.add_theme_stylebox_override("panel", _panel_style(_chapter_color(int(stage_detail["chapter"])), Color("fff0a0"), 24, 3))
    stage_detail_content.add_child(title_card)
    var title_box := VBoxContainer.new()
    title_box.add_theme_constant_override("separation", 5)
    title_card.add_child(title_box)
    var stage_title := Label.new()
    stage_title.text = "STAGE %02d  ·  %s" % [stage_id, str(stage_detail["name"])]
    stage_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    stage_title.add_theme_font_size_override("font_size", 28)
    stage_title.add_theme_color_override("font_color", Color.WHITE)
    title_box.add_child(stage_title)
    var chapter_title := Label.new()
    chapter_title.text = "第 %d 章｜%s%s" % [int(stage_detail["chapter"]), str(stage_detail.get("chapterTitle", "")), "｜%s" % _star_text(int(progress.get("stars", 0))) if bool(progress.get("cleared", false)) else ""]
    chapter_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    chapter_title.add_theme_font_size_override("font_size", 17)
    chapter_title.add_theme_color_override("font_color", Color("e9f8ff"))
    title_box.add_child(chapter_title)

    _add_detail_card("☁  戰場地圖", "%s｜主天氣：%s" % [str(stage_detail["mapId"]), _map_weather_text(map_data)], Color("2d86bd"))
    _add_detail_card("♜  敵方城堡", "AI 城堡 Lv.%d｜HP %.0f｜DEF %.0f｜%s AI" % [
        int(stage_detail["aiCastleLevel"]), Progression.castle_hp(int(stage_detail["aiCastleLevel"])), Progression.castle_def(int(stage_detail["aiCastleLevel"])), _difficulty_text(str(stage_detail["aiDifficulty"])),
    ], Color("4e69b7"))
    _add_detail_card("✦  登場職業", "  ·  ".join(stage_detail.get("classes", [])), Color("7653a9"))
    _add_detail_card("◆  稀有度分布", _rarity_text(stage_detail.get("rarityWeights", {})), Color("aa5f55"))
    var item_ids: Array = stage_detail.get("aiItems", [])
    _add_detail_card("▣  敵方道具", "無攜帶道具" if item_ids.is_empty() else "  ·  ".join(item_ids), Color("a0763f"))
    _add_detail_card("★  星等挑戰", "★★★ 完成 %d 輪內｜★★ 完成 %d 輪內｜★ 成功通關" % [
        int(targets.get("threeStarMaxRounds", 0)), int(targets.get("twoStarMaxRounds", 0)),
    ], Color("3d8f77"))
    _add_detail_card("◈  首通獎勵", "戰功 +%d｜經驗 +50%s" % [
        int(stage_detail.get("meritReward", 0)), "｜解鎖 %s" % str(stage_detail.get("unlocksClass", "")) if stage_detail.has("unlocksClass") else "",
    ], Color("b76d42"))
    if bool(stage_detail.get("tutorial", false)):
        _add_detail_card("?  教學提示", "本關會引導自由選擇、跟色連鎖與首次連線。", Color("278da5"))
    if bool(stage_detail.get("boss", false)):
        _add_detail_card("!  終焉庇護", "末日天候切換時，終焉領主回復戰力上限 5%。", Color("a63e4d"))
    stage_detail_start_button.disabled = not unlocked
    stage_detail_start_button.text = "⚔  前往備戰" if unlocked else "🔒  尚未解鎖"


func _add_detail_card(title: String, body: String, color: Color) -> void:
    var card := PanelContainer.new()
    card.add_theme_stylebox_override("panel", _panel_style(color, Color("ffe3a3"), 18, 2))
    stage_detail_content.add_child(card)
    var box := VBoxContainer.new()
    box.add_theme_constant_override("separation", 3)
    card.add_child(box)
    var title_label := Label.new()
    title_label.text = title
    title_label.add_theme_font_size_override("font_size", 19)
    title_label.add_theme_color_override("font_color", Color("fff5cf"))
    box.add_child(title_label)
    var body_label := Label.new()
    body_label.text = body
    body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    body_label.add_theme_font_size_override("font_size", 16)
    body_label.add_theme_color_override("font_color", Color.WHITE)
    box.add_child(body_label)


func _start_stage_from_detail() -> void:
    if not stage_detail.is_empty():
        _show_battle_prep(int(stage_detail["id"]))


func _build_battle_prep_overlay() -> void:
    battle_prep_overlay = Control.new()
    battle_prep_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    battle_prep_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
    battle_prep_overlay.visible = false
    add_child(battle_prep_overlay)
    var sky := ColorRect.new()
    sky.color = Color("276b9d")
    sky.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    battle_prep_overlay.add_child(sky)
    var banners := Label.new()
    banners.text = "⚑        ✦        ⚑"
    banners.position = Vector2(38, 112)
    banners.add_theme_font_size_override("font_size", 44)
    banners.add_theme_color_override("font_color", Color(1.0, 0.9, 0.44, 0.28))
    banners.mouse_filter = Control.MOUSE_FILTER_IGNORE
    battle_prep_overlay.add_child(banners)
    var center := CenterContainer.new()
    center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    battle_prep_overlay.add_child(center)
    var panel := PanelContainer.new()
    panel.custom_minimum_size = Vector2(610, 1080)
    panel.add_theme_stylebox_override("panel", _panel_style(Color("193d78"), Color("ffe08a"), 28, 3))
    center.add_child(panel)
    var margin := MarginContainer.new()
    margin.add_theme_constant_override("margin_left", 24)
    margin.add_theme_constant_override("margin_top", 22)
    margin.add_theme_constant_override("margin_right", 24)
    margin.add_theme_constant_override("margin_bottom", 22)
    panel.add_child(margin)
    var layout := VBoxContainer.new()
    layout.add_theme_constant_override("separation", 12)
    margin.add_child(layout)
    var heading := Label.new()
    heading.text = "遠征備戰"
    heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    heading.add_theme_font_size_override("font_size", 33)
    heading.add_theme_color_override("font_color", Color("fff0ac"))
    layout.add_child(heading)
    var subheading := Label.new()
    subheading.text = "整備城堡與戰術道具，準備出征"
    subheading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    subheading.add_theme_font_size_override("font_size", 16)
    subheading.add_theme_color_override("font_color", Color("cceeff"))
    layout.add_child(subheading)
    var scroll := ScrollContainer.new()
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    layout.add_child(scroll)
    battle_prep_content = VBoxContainer.new()
    battle_prep_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    battle_prep_content.add_theme_constant_override("separation", 12)
    scroll.add_child(battle_prep_content)
    battle_prep_start_button = Button.new()
    battle_prep_start_button.text = "⚔  出征！"
    battle_prep_start_button.custom_minimum_size = Vector2(0, 68)
    battle_prep_start_button.add_theme_font_size_override("font_size", 24)
    _style_primary_button(battle_prep_start_button, Color("319c57"), Color("52bd73"), Color("fff5bc"))
    battle_prep_start_button.pressed.connect(_start_stage_from_prep)
    layout.add_child(battle_prep_start_button)
    var back := Button.new()
    back.text = "← 返回關卡詳情"
    back.custom_minimum_size = Vector2(0, 48)
    back.add_theme_font_size_override("font_size", 17)
    _style_primary_button(back, Color("356da8"), Color("4d91ca"), Color("ebf7ff"))
    back.pressed.connect(_return_to_stage_detail)
    layout.add_child(back)


func _show_battle_prep(stage_id: int) -> void:
    stage_detail = Campaign.get_stage(stage_id, campaign_stages)
    if stage_detail.is_empty():
        return
    result_overlay.visible = false
    hub_overlay.visible = false
    campaign_overlay.visible = false
    stage_detail_overlay.visible = false
    battle_prep_overlay.visible = true
    _refresh_battle_prep()


func _refresh_battle_prep() -> void:
    for child in battle_prep_content.get_children():
        battle_prep_content.remove_child(child)
        child.queue_free()
    if stage_detail.is_empty():
        return
    var stage_id := int(stage_detail["id"])
    var targets: Dictionary = stage_detail.get("starTargets", {})
    var player_castle_level := int(profile.get("castle_level", 1))
    var enemy_castle_level := int(stage_detail.get("aiCastleLevel", 1))
    var map_data := Maps.get_map(str(stage_detail.get("mapId", Maps.DEFAULT_MAP_ID)))
    var unlocked: bool = stage_id in profile.get("unlocked_stages", [1])
    _add_prep_card("⚔  STAGE %02d｜%s" % [stage_id, str(stage_detail["name"])], "第 %d 章 %s｜%s｜%s AI" % [
        int(stage_detail["chapter"]), str(stage_detail.get("chapterTitle", "")), str(stage_detail["mapId"]), _difficulty_text(str(stage_detail["aiDifficulty"])),
    ], _chapter_color(int(stage_detail["chapter"])))
    _add_prep_card("♜  城堡對陣", "我方 晨曦城堡 Lv.%d｜HP %.0f + 10 先手加成｜DEF %.0f\n敵方 城塞 Lv.%d｜HP %.0f｜DEF %.0f" % [
        player_castle_level, Progression.castle_hp(player_castle_level), Progression.castle_def(player_castle_level),
        enemy_castle_level, Progression.castle_hp(enemy_castle_level), Progression.castle_def(enemy_castle_level),
    ], Color("4077b7"))
    _add_prep_card("✦  出戰職業", _training_summary(stage_detail.get("classes", [])), Color("7653a9"))
    _add_prep_card("☁  地形與天候", "%s｜主天氣：%s\n職業地形加成將在棋盤出現時生效。" % [
        str(stage_detail["mapId"]), _map_weather_text(map_data),
    ], Color("2d86bd"))
    _add_prep_card("▣  戰術行囊", "本場已配發全部 20 種戰術道具各 1 份。開戰後可由左側道具欄使用；敵軍攜帶：%s" % [
        "無" if stage_detail.get("aiItems", []).is_empty() else "、".join(stage_detail.get("aiItems", [])),
    ], Color("a0763f"))
    _add_prep_card("★  勝利目標", "★★★ %d 輪內｜★★ %d 輪內｜★ 成功擊破敵方城堡\n首通：戰功 +%d｜經驗 +50" % [
        int(targets.get("threeStarMaxRounds", 0)), int(targets.get("twoStarMaxRounds", 0)), int(stage_detail.get("meritReward", 0)),
    ], Color("3d8f77"))
    battle_prep_start_button.disabled = not unlocked
    battle_prep_start_button.text = "⚔  出征！" if unlocked else "🔒  尚未解鎖"


func _add_prep_card(title: String, body: String, color: Color) -> void:
    var card := PanelContainer.new()
    card.add_theme_stylebox_override("panel", _panel_style(color, Color("ffe3a3"), 18, 2))
    battle_prep_content.add_child(card)
    var box := VBoxContainer.new()
    box.add_theme_constant_override("separation", 3)
    card.add_child(box)
    var title_label := Label.new()
    title_label.text = title
    title_label.add_theme_font_size_override("font_size", 20)
    title_label.add_theme_color_override("font_color", Color("fff5cf"))
    box.add_child(title_label)
    var body_label := Label.new()
    body_label.text = body
    body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    body_label.add_theme_font_size_override("font_size", 16)
    body_label.add_theme_color_override("font_color", Color.WHITE)
    box.add_child(body_label)


func _training_summary(class_ids: Array) -> String:
    var training: Dictionary = profile.get("class_training", {})
    var rows: Array[String] = []
    for class_id in class_ids:
        rows.append("%s Lv.%d" % [str(class_id), int(training.get(str(class_id), 1))])
    return "  ·  ".join(rows) + "\n職業訓練提高該職業在棋盤上的出現權重。"


func _start_stage_from_prep() -> void:
    if not stage_detail.is_empty():
        _start_stage(int(stage_detail["id"]))


func _return_to_stage_detail() -> void:
    if not stage_detail.is_empty():
        _show_stage_detail(int(stage_detail["id"]))


func _chapter_color(chapter: int) -> Color:
    var colors := [Color("398d63"), Color("3e8ec5"), Color("8168bc"), Color("cb7047"), Color("b48a43"), Color("5280bb"), Color("d0923f"), Color("31968a"), Color("5a6ea8"), Color("a34b54")]
    return colors[clampi(chapter - 1, 0, colors.size() - 1)]


func _map_weather_text(map_data: Dictionary) -> String:
    var kind = map_data.get("mainWeather", null)
    if str(kind) == "apocalypse":
        return "末日天候循環"
    return Weather.display_name(kind)


func _difficulty_text(difficulty: String) -> String:
    return {"easy": "簡單", "normal": "一般", "hard": "困難"}.get(difficulty, difficulty)


func _rarity_text(weights: Dictionary) -> String:
    return "灰 %d%%  ·  綠 %d%%  ·  藍 %d%%  ·  紅 %d%%  ·  金 %d%%" % [
        int(weights.get("灰", 0)), int(weights.get("綠", 0)), int(weights.get("藍", 0)), int(weights.get("紅", 0)), int(weights.get("金", 0)),
    ]


func _refresh_hub() -> void:
    var castle_level := int(profile.get("castle_level", 1))
    var selected_class := "劍士"
    if hub_training_selector != null:
        selected_class = str(hub_training_selector.get_item_metadata(hub_training_selector.selected))
    var training_level := int(profile.get("class_training", {}).get(selected_class, 1))
    hub_resource_label.text = "%s  Lv.%d\n✦ 經驗 %d    ◈ 戰功 %d" % [
        str(profile.get("display_name", "城主")), int(profile.get("level", 1)), int(profile.get("exp", 0)), int(profile.get("merit_points", 0)),
    ]
    hub_profile_label.text = "城堡 Lv.%d  ·  HP %.0f  ·  DEF %.0f" % [
        castle_level, Progression.castle_hp(castle_level), Progression.castle_def(castle_level),
    ]
    hub_training_status_label.text = "✦ 職業訓練所｜%s Lv.%d｜下次費用 %d" % [
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
            var chapter_card := PanelContainer.new()
            chapter_card.add_theme_stylebox_override("panel", _panel_style(_chapter_color(chapter), Color("fff0a0"), 18, 2))
            campaign_list.add_child(chapter_card)
            var chapter_label := Label.new()
            chapter_label.text = "✦  第 %d 章｜%s" % [chapter, str(stage.get("chapterTitle", ""))]
            chapter_label.add_theme_font_size_override("font_size", 21)
            chapter_label.add_theme_color_override("font_color", Color("fff9d7"))
            chapter_card.add_child(chapter_label)
        var button := Button.new()
        var stage_result: Dictionary = progress.get(str(stage_id), {})
        var cleared := bool(stage_result.get("cleared", false))
        var locked := int(stage_id) not in unlocked
        var targets: Dictionary = stage.get("starTargets", {})
        button.text = "STAGE %02d  ·  %s%s\n%s｜AI Lv.%d｜★3 %d 輪／★2 %d 輪" % [
            int(stage_id), str(stage["name"]), "  %s" % _star_text(int(stage_result.get("stars", 0))) if cleared else ("  🔒" if locked else ""),
            str(stage["mapId"]), int(stage["aiCastleLevel"]), int(targets.get("threeStarMaxRounds", 0)), int(targets.get("twoStarMaxRounds", 0)),
        ]
        button.custom_minimum_size = Vector2(0, 76)
        button.alignment = HORIZONTAL_ALIGNMENT_LEFT
        button.add_theme_font_size_override("font_size", 17)
        _style_primary_button(button, _chapter_color(chapter).darkened(0.14), _chapter_color(chapter), Color("fff9df"))
        button.tooltip_text = "%s｜首通戰功 %d｜二星 ≤ %d 輪｜三星 ≤ %d 輪｜%d 個 AI 道具" % [
            str(stage["mapId"]), int(stage.get("meritReward", 0)), int(targets.get("twoStarMaxRounds", 0)), int(targets.get("threeStarMaxRounds", 0)), stage.get("aiItems", []).size(),
        ]
        button.disabled = locked
        button.pressed.connect(_show_stage_detail.bind(int(stage_id)))
        campaign_list.add_child(button)


func _show_hub() -> void:
    result_overlay.visible = false
    campaign_overlay.visible = false
    stage_detail_overlay.visible = false
    battle_prep_overlay.visible = false
    hub_overlay.visible = true
    difficulty_selector.disabled = false
    map_selector.disabled = false
    _refresh_hub()


func _show_campaign() -> void:
    result_overlay.visible = false
    hub_overlay.visible = false
    stage_detail_overlay.visible = false
    battle_prep_overlay.visible = false
    campaign_overlay.visible = true
    _refresh_campaign()


func _start_free_battle() -> void:
    current_stage = {}
    hub_overlay.visible = false
    stage_detail_overlay.visible = false
    battle_prep_overlay.visible = false
    difficulty_selector.disabled = false
    map_selector.disabled = false
    _new_preview_match()


func _start_stage(stage_id: int) -> void:
    current_stage = Campaign.get_stage(stage_id, campaign_stages)
    if current_stage.is_empty():
        return
    campaign_overlay.visible = false
    stage_detail_overlay.visible = false
    battle_prep_overlay.visible = false
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
        _show_battle_prep(next_stage_id)


func _star_text(stars: int) -> String:
    var filled := "★".repeat(clampi(stars, 0, 3))
    var empty := "☆".repeat(3 - clampi(stars, 0, 3))
    return filled + empty
