extends SceneTree

const Rules = preload("res://game_core/bingo_rules.gd")
const Session = preload("res://game_core/pve_session.gd")
const Ai = preload("res://ai/bingo_ai.gd")
const Maps = preload("res://game_core/map_catalog.gd")
const Weather = preload("res://game_core/weather_system.gd")
const Items = preload("res://game_core/item_system.gd")
const Campaign = preload("res://game_core/campaign_catalog.gd")
const Profiles = preload("res://game_core/profile_store.gd")
const Progression = preload("res://game_core/progression.gd")

var failures: Array[String] = []


func _init() -> void:
    _test_deterministic_board_generation()
    _test_opening_follow_and_second_action_flow()
    _test_follow_skip_restarts_chain()
    _test_board_lines_and_refill()
    _test_formula_golden_cases()
    _test_class_passives()
    _test_map_catalog_and_modifiers()
    _test_all_weather_effects()
    _test_weather_schedule_and_expiry()
    _test_weather_items()
    _test_disruption_items()
    _test_recovery_items()
    _test_profile_save_migration_and_recovery()
    _test_campaign_progression_economy()
    _test_campaign_session_configuration()
    _test_all_campaign_stages_boot()
    _test_final_boss_weather_heal()
    _test_multiline_across_two_actions()
    _test_construction_rules()
    _test_simultaneous_attack_batch()
    _test_ai_difficulty_parameters()
    _test_session_auto_skips_player_follow()
    _test_pve_session_replay()
    if failures.is_empty():
        print("Woven Rampart core smoke tests: PASS (23 suites)")
        quit(0)
        return
    for failure in failures:
        push_error(failure)
    print("Woven Rampart core smoke tests: FAIL (%d failures)" % failures.size())
    quit(1)


func _check(condition: bool, message: String) -> void:
    if not condition:
        failures.append(message)


func _test_deterministic_board_generation() -> void:
    var first := Rules.create_match(12345)
    var second := Rules.create_match(12345)
    var first_board: Array = first["players"][0]["board"]
    var second_board: Array = second["players"][0]["board"]
    _check(first_board.size() == 25, "board must contain 25 cells")
    _check(Rules.board_signature(first_board) == Rules.board_signature(second_board), "same seed must produce same board")
    _check(first["schema_version"] == 1, "state schema version must be present")
    _check(first["players"][0]["castle_hp"] == 110.0, "first mover must receive +10 starting power")
    _check(first["players"][0]["castle_hp_cap"] == 200.0, "first mover bonus must not increase the healing cap")
    var custom := Rules.DEFAULT_CONFIG.duplicate(true)
    custom["first_mover_hp_bonus"] = 5.0
    custom["rarity_weights"] = {"灰": 0, "綠": 0, "藍": 0, "紅": 0, "金": 100}
    var configured := Rules.create_match(12345, Rules.DEFAULT_CLASSES, 1, custom)
    _check(configured["players"][1]["castle_hp"] == 105.0, "first mover bonus must come from versioned balance data")
    _check(configured["players"][0]["board"][0]["rarity"] == "金", "rarity generation must use balance weights")


func _test_opening_follow_and_second_action_flow() -> void:
    var state := Rules.create_match(11)
    var opening_class: String = state["players"][0]["board"][0]["class_id"]
    var opening := Rules.select_cell(state, 0, 0, "free")
    _check(bool(opening["ok"]), "opening free selection must be legal")
    _check(int(state["current_player"]) == 1, "the opening choice must end the first mover's turn")
    _check(state["action_stage"] == "follow", "the second player must follow after the opening choice")
    _check(state["chain_target"][1] == opening_class, "opening choice must set the opponent follow target")

    var follow_index := _find_unclaimed_with_class(state["players"][1]["board"], opening_class, true)
    _check(follow_index >= 0, "fixed board should contain a legal follow cell")
    if follow_index < 0:
        return
    var follow := Rules.select_cell(state, 1, follow_index, "follow")
    _check(bool(follow["ok"]), "matching follow selection must be legal")
    _check(int(state["current_player"]) == 1, "successful follow must keep control for the second action")
    _check(state["action_stage"] == "second_action", "successful follow must open free/build choice")

    var free_index := _first_unclaimed(state["players"][1]["board"])
    var second := Rules.select_cell(state, 1, free_index, "free")
    _check(bool(second["ok"]), "free choice must be legal as the second action")
    _check(int(state["current_player"]) == 0 and state["action_stage"] == "follow", "second action must pass control back")
    _check(int(state["turns_completed"]) == 2 and int(state["round"]) == 2, "one round must contain two completed player turns")


func _test_follow_skip_restarts_chain() -> void:
    var state := Rules.create_match(31)
    state["current_player"] = 1
    state["action_stage"] = "follow"
    state["chain_target"][1] = "不存在職業"
    var skipped := Rules.skip_follow(state, 1)
    _check(bool(skipped["ok"]), "follow with no legal cell must be skippable")
    _check(int(state["current_player"]) == 0 and state["action_stage"] == "free", "skip must give the opponent a fresh free choice")
    var fresh := Rules.select_cell(state, 0, _first_unclaimed(state["players"][0]["board"]), "free")
    _check(bool(fresh["ok"]), "fresh free choice after a skip must be legal")
    _check(int(state["current_player"]) == 1 and state["action_stage"] == "follow", "fresh free choice must start a new follow chain")


func _test_board_lines_and_refill() -> void:
    var state := Rules.create_match(7)
    var board: Array = state["players"][0]["board"]
    for index in [0, 1, 2, 3, 4]:
        board[index]["claimed"] = true
    var completed := Rules.find_completed_lines(board, 4)
    _check(completed.size() == 1, "completed row must be detected")
    var output := Rules.resolve_completed_lines(state, 0, completed)
    _check(float(output["attack_power"]) > 0.0, "attack line must produce power")
    for index in [0, 1, 2, 3, 4]:
        _check(not bool(board[index]["claimed"]), "completed cells must be cleared and refilled")
        _check(int(board[index]["construction_level"]) == 1, "refilled cells must reset construction")


func _test_formula_golden_cases() -> void:
    var attack_board := _uniform_board("劍士", "灰")
    var pure_attack := Rules.line_output(attack_board, Rules.LINES[0], 1)
    _check(is_equal_approx(float(pure_attack["attack_power"]), 65.0), "five gray attackers must match Python reference output 50 x 1.3 = 65")
    _check(is_equal_approx(float(pure_attack["heal"]), 0.0), "attack-only line must not heal")

    var builder_board := _uniform_board("建築工", "灰")
    var pure_heal := Rules.line_output(builder_board, Rules.LINES[0], 1)
    _check(is_equal_approx(float(pure_heal["heal"]), 104.0), "five builders must match Python reference output 50 x 1.6 x 1.3 = 104")
    _check(is_equal_approx(float(pure_heal["attack_power"]), 0.0), "builder-only line must not attack")

    var upgraded_board := _uniform_board("劍士", "灰")
    upgraded_board[0]["construction_level"] = 2
    upgraded_board[1]["rarity"] = "金"
    var upgraded := Rules.line_output(upgraded_board, Rules.LINES[0], 1)
    _check(is_equal_approx(float(upgraded["attack_power"]), 92.3), "rarity and construction multipliers must be applied before pure-line bonus")


func _test_multiline_across_two_actions() -> void:
    var state := Rules.create_match(41)
    var board: Array = state["players"][0]["board"]
    for index in Rules.LINES[0]:
        board[index] = _cell("劍士", "灰", true)
    var first := Rules.resolve_completed_lines(state, 0, [Rules.LINES[0]])
    _check(is_equal_approx(float(first["attack_power"]), 65.0), "first line in a turn must use the base pure-line multiplier")
    for index in Rules.LINES[1]:
        board[index] = _cell("劍士", "灰", true)
    var second := Rules.resolve_completed_lines(state, 0, [Rules.LINES[1]])
    _check(is_equal_approx(float(second["attack_power"]), 84.5), "second action's line in the same turn must receive the multiline multiplier")
    _check(bool(second["events"][0]["is_multiline"]), "line event must expose multiline presentation data")


func _test_class_passives() -> void:
    var sword := Rules.line_output(_uniform_board("劍士", "灰"), Rules.LINES[0], 1)
    _check(is_equal_approx(float(sword["true_damage"]), 50.0), "swordsmen must add base-attack true damage per unit")
    _check(is_equal_approx(Rules.resolve_line_damage(sword, 10.0), 105.0), "swordsman true damage must bypass castle DEF")

    var samurai := Rules.line_output(_uniform_board("武士", "灰"), Rules.LINES[0], 1)
    _check(is_equal_approx(float(samurai["attack_power"]), 97.5), "pure samurai line must stack +50% with the pure-line multiplier")

    var warrior := Rules.line_output(_uniform_board("戰士", "灰"), Rules.LINES[0], 1)
    _check(is_equal_approx(Rules.resolve_line_damage(warrior, 30.0), 50.0), "warrior must halve DEF mitigation at DEF 30")
    _check(is_equal_approx(Rules.resolve_line_damage(warrior, 50.0), 65.0), "warrior must fully pierce DEF 50")

    var archer_context := {"global_weather_debuff": 0.1}
    var archer := Rules.line_output(_uniform_board("弓手", "灰"), Rules.LINES[0], 1, Rules.DEFAULT_CONFIG, archer_context)
    _check(is_equal_approx(float(archer["attack_power"]), 60.45), "archer must ignore 30% of sandstorm-style attack reduction")

    var knight := Rules.line_output(_uniform_board("騎士", "灰"), Rules.LINES[0], 2)
    _check(is_equal_approx(float(knight["attack_power"]), 101.4), "knight must add its charge bonus on multiline attacks")

    var mage := Rules.line_output(_uniform_board("法師", "灰"), Rules.LINES[0], 1)
    _check(is_equal_approx(float(mage["heal"]), 5.0), "mage must grant 10% of its own contribution as healing")

    var trained_context := {"class_training": {"建築工": 2}}
    var builder := Rules.line_output(_uniform_board("建築工", "灰"), Rules.LINES[0], 1, Rules.DEFAULT_CONFIG, trained_context)
    _check(is_equal_approx(float(builder["heal"]), 114.4), "builder training must increase base recovery by 10% per level")

    var ninja_state := Rules.create_match(121, Rules.ALL_CLASSES)
    ninja_state["players"][0]["board"][0]["class_id"] = "忍者"
    var guaranteed := Rules.DEFAULT_CONFIG.duplicate(true)
    guaranteed["ninja_evade_chance"] = 1.0
    _check(Rules.ninja_evades_kill(ninja_state, 0, 0, "plague", guaranteed), "ninja evade must protect against plague when its deterministic roll succeeds")
    _check(not Rules.ninja_evades_kill(ninja_state, 0, 0, "volcano", guaranteed), "ninja evade must not protect against unrelated kill sources")


func _test_map_catalog_and_modifiers() -> void:
    var maps := Maps.load_maps()
    _check(maps.size() == 11, "map catalog must contain all 11 specified maps")
    var desert := Maps.get_map("沙丘荒漠", maps)
    _check(is_equal_approx(Maps.class_modifier(desert, "建築工"), 0.15), "desert must buff builders by 15%")
    _check(is_equal_approx(Maps.class_modifier(desert, "劍士"), -0.15), "desert must penalize swordsmen by 15%")
    _check(is_equal_approx(Maps.class_modifier(desert, "劍士", "劍士"), 0.15), "personal exclusive bonus must replace a terrain penalty instead of stacking")
    var terrain_context := {"class_modifiers": {"劍士": 0.15}}
    var terrain_line := Rules.line_output(_uniform_board("劍士", "灰"), Rules.LINES[0], 1, Rules.DEFAULT_CONFIG, terrain_context)
    _check(is_equal_approx(float(terrain_line["attack_power"]), 74.75), "terrain modifiers must feed the authoritative line formula")


func _test_all_weather_effects() -> void:
    var config := Rules.DEFAULT_CONFIG.duplicate(true)

    var poison := _weather_state(201)
    var poison_events := Weather.trigger_weather(poison, "poison", 2, config)
    _check(poison_events.size() == 1 and poison_events[0]["affected_cells"][0].size() == 1, "poison must pick one cell independently on each board")
    _check(poison["weather_debuffs"][0].size() == 1 and poison["weather_debuffs"][1].size() == 1, "poison must install per-board attack debuffs")

    var ice := _weather_state(202)
    var ice_event: Dictionary = Weather.trigger_weather(ice, "ice", 2, config)[0]
    _check(ice_event["affected_cells"][0].size() == 3 and _count_status(ice, 0, "frozen") == 3, "ice must freeze three cells on each board")

    var wind := _weather_state(203)
    var wind_before := _board_contents_multiset(wind["players"][0]["board"])
    var wind_event: Dictionary = Weather.trigger_weather(wind, "wind", 2, config)[0]
    _check(wind_event["affected_cells"][0].size() == 5, "wind must choose five unclaimed cells when available")
    _check(wind_before == _board_contents_multiset(wind["players"][0]["board"]), "wind must shuffle existing contents without rerolling them")

    var volcano := _weather_state(204)
    for player_index in range(2):
        for cell in volcano["players"][player_index]["board"]:
            cell["claimed"] = true
    var volcano_event: Dictionary = Weather.trigger_weather(volcano, "volcano", 2, config)[0]
    _check(int(volcano_event["details"]["killed_claimed"][0]) == 3, "volcano must kill claimed soldiers in its three selected cells")
    for index in volcano_event["affected_cells"][0]:
        _check(not bool(volcano["players"][0]["board"][index]["claimed"]), "volcano victims must be replaced by fresh unclaimed soldiers")

    var quake := _weather_state(205)
    var quake_event: Dictionary = Weather.trigger_weather(quake, "quake", 2, config)[0]
    _check(_count_status(quake, 0, "buried") == 3, "quake must leave three buried cells on each board")
    var buried_index := int(quake_event["affected_cells"][0][0])
    quake["current_player"] = 0
    var clear := Rules.clear_buried_cell(quake, 0, buried_index)
    _check(bool(clear["ok"]) and quake["players"][0]["board"][buried_index]["status"] == "normal", "clearing rubble must consume an action and restore the cell")

    var sandstorm := _weather_state(206)
    Weather.trigger_weather(sandstorm, "sandstorm", 2, config)
    _check(is_equal_approx(float(sandstorm["global_weather_debuff"]), 0.1), "sandstorm must apply the global 10% attack reduction")

    var flood := _weather_state(207)
    for player_index in range(2):
        for index in range(5):
            flood["players"][player_index]["board"][index]["claimed"] = true
            flood["players"][player_index]["board"][index]["construction_level"] = 2 + (index % 2)
    var flood_event: Dictionary = Weather.trigger_weather(flood, "flood", 2, config)[0]
    _check(flood_event["affected_cells"][0].size() == 3, "flood must select up to three claimed cells")
    _check(_count_claimed(flood, 0) == 5, "flood must move claimed cells without killing or unclaiming them")

    var fog := _weather_state(208)
    var fog_event: Dictionary = Weather.trigger_weather(fog, "fog", 2, config)[0]
    _check(_count_status(fog, 0, "fogged") == 5, "fog must hide five unclaimed cells from their owner")
    var fog_index := int(fog_event["affected_cells"][0][0])
    fog["current_player"] = 0
    fog["action_stage"] = "follow"
    fog["chain_target"][0] = fog["players"][0]["board"][fog_index]["class_id"]
    _check(Rules.can_follow(fog, 0), "fogged cells must remain legal follow choices")
    var reveal := Rules.select_cell(fog, 0, fog_index, "follow", config, false)
    _check(bool(reveal["ok"]) and reveal["events"][0]["type"] == "fog_revealed", "selecting a fogged cell must reveal it")


func _test_weather_schedule_and_expiry() -> void:
    var config := Rules.DEFAULT_CONFIG.duplicate(true)
    config["weather_trigger_chance"] = 1.0
    config["main_weather_chance"] = 1.0
    var state := _weather_state(301, "毒霧沼澤")
    var map_data := Maps.get_map("毒霧沼澤")
    _check(Weather.advance_completed_round(state, 1, config, map_data).is_empty(), "normal maps must not roll weather before the third completed round")
    var triggered := Weather.advance_completed_round(state, 3, config, map_data)
    _check(triggered.size() == 1 and triggered[0]["kind"] == "poison", "third round must use the map's main weather when the 70% roll is forced")
    Weather.advance_completed_round(state, 4, config, map_data)
    _check(int(state["weather"]["rounds_left"]) == 1, "weather must retain one round after its first tick")
    var ended := Weather.advance_completed_round(state, 5, config, map_data)
    _check(ended.size() == 1 and ended[0]["type"] == "weather_ended", "weather must end after two completed rounds")

    var apocalypse := _weather_state(302, "末日")
    var apocalypse_map := Maps.get_map("末日")
    var first := Weather.advance_completed_round(apocalypse, 1, config, apocalypse_map)
    var first_kind: String = first[-1]["kind"]
    var second := Weather.advance_completed_round(apocalypse, 2, config, apocalypse_map)
    _check(second[-1]["kind"] != first_kind, "apocalypse must cycle without repeating until all eight weather kinds are used")
    _check(int(apocalypse["weather"]["rounds_left"]) == 1, "apocalypse weather must last one round")


func _test_weather_items() -> void:
    var config := Rules.DEFAULT_CONFIG.duplicate(true)
    var catalog := Items.load_items()
    _check(catalog.size() == 20, "item catalog must contain all 20 specified items")

    var blanket := _item_state(401)
    Weather.trigger_weather(blanket, "ice", 2, config)
    var blanket_result := Items.use_item(blanket, 0, "驅寒毛毯", {}, config, catalog)
    _check(bool(blanket_result["ok"]) and _count_status(blanket, 0, "frozen") == 0, "cold blanket must immediately unfreeze every own cell")
    var blanket_again := Items.use_item(blanket, 0, "驅寒毛毯", {}, config, catalog)
    _check(not bool(blanket_again["ok"]) and blanket_again["error"] == "ITEM_EXHAUSTED", "an item with no remaining count must not be usable twice")

    var wind_guard := _item_state(402)
    Items.use_item(wind_guard, 0, "防風結界", {}, config, catalog)
    var guarded_wind: Dictionary = Weather.trigger_weather(wind_guard, "wind", 2, config)[0]
    _check(guarded_wind["affected_cells"][0].is_empty() and not bool(wind_guard["weather_protections"][0]["wind"]), "wind barrier must prevent and then consume one wind shuffle")

    var fire_guard := _item_state(403)
    for cell in fire_guard["players"][0]["board"]:
        cell["claimed"] = true
    Items.use_item(fire_guard, 0, "滅火壺", {}, config, catalog)
    var guarded_fire: Dictionary = Weather.trigger_weather(fire_guard, "volcano", 2, config)[0]
    for index in guarded_fire["affected_cells"][0]:
        _check(bool(fire_guard["players"][0]["board"][index]["claimed"]) and fire_guard["players"][0]["board"][index]["status"] == "frozen", "fire extinguisher must convert volcano death into freezing")

    var summons := {
        "瘟疫瘴氣符": "poison", "極寒霜訣符": "ice", "疾風召喚符": "wind", "熔岩噴發符": "volcano",
        "大地震顫符": "quake", "沙暴召喚符": "sandstorm", "洪流沖刷符": "flood", "迷霧潛行符": "fog",
    }
    var summon_seed := 410
    for item_id in summons:
        var summon_state := _item_state(summon_seed)
        summon_seed += 1
        var summon_result := Items.use_item(summon_state, 0, item_id, {}, config, catalog)
        _check(bool(summon_result["ok"]) and summon_state["weather"]["kind"] == summons[item_id], "%s must summon its matching weather" % item_id)

    var sunny := _item_state(420, "末日")
    Items.use_item(sunny, 0, "晴天結界", {}, config, catalog)
    var suppressed := Weather.advance_completed_round(sunny, 1, config, Maps.get_map("末日"))
    _check(int(sunny["sunny_rounds_left"]) == 1 and suppressed[-1]["type"] == "weather_suppressed", "sunny barrier must suppress scheduled weather for two rounds")


func _test_disruption_items() -> void:
    var catalog := Items.load_items()
    var no_evade := Rules.DEFAULT_CONFIG.duplicate(true)
    no_evade["ninja_evade_chance"] = 0.0
    for plague_case in [["瘟疫LV1", 5], ["瘟疫LV2", 7]]:
        var plague := _item_state(501 + int(plague_case[1]))
        for index in range(10):
            plague["players"][1]["board"][index]["claimed"] = true
            plague["players"][1]["board"][index]["construction_level"] = 3
            plague["players"][1]["board"][index]["class_id"] = "劍士"
        var plague_result := Items.use_item(plague, 0, str(plague_case[0]), {}, no_evade, catalog)
        _check(bool(plague_result["ok"]) and _count_claimed(plague, 1) == 10 - int(plague_case[1]), "%s must kill the configured number of claimed cells" % plague_case[0])
        var plague_event: Dictionary = plague_result["events"][1]
        for index in plague_event["killed"]:
            _check(int(plague["players"][1]["board"][index]["construction_level"]) == 3, "plague deaths must preserve construction")

    var seal := _item_state(520)
    var sealed := Items.use_item(seal, 0, "職業封印", {"class_id": "劍士"}, Rules.DEFAULT_CONFIG, catalog)
    seal["current_player"] = 1
    seal["action_stage"] = "follow"
    seal["chain_target"][1] = "劍士"
    seal["players"][1]["board"][0]["class_id"] = "劍士"
    _check(bool(sealed["ok"]) and not Rules.can_follow(seal, 1), "class seal must make even matching cells unavailable")
    seal["action_stage"] = "free"
    var ai_after_seal := Ai.take_turn(seal, 1, Rules.DEFAULT_CONFIG, false, "normal")
    if bool(ai_after_seal.get("ok", false)):
        var chosen_index := int(ai_after_seal["action"]["cell_index"])
        _check(seal["players"][1]["board"][chosen_index]["class_id"] != "劍士", "AI must exclude sealed classes from free-choice candidates")
    seal["round"] = 3
    Items.advance_completed_round(seal)
    _check(not Items.is_class_sealed(seal, 1, "劍士"), "class seal must expire after two rounds")

    var mine := _item_state(530)
    Items.use_item(mine, 0, "地雷", {}, no_evade, catalog)
    var mine_index := _find_mine(mine, 1)
    mine["players"][1]["board"][mine_index]["class_id"] = "劍士"
    mine["current_player"] = 1
    mine["action_stage"] = "free"
    var exploded := Rules.select_cell(mine, 1, mine_index, "free", no_evade, false)
    _check(bool(exploded["ok"]) and _has_event(exploded["events"], "mine_triggered") and not bool(mine["players"][1]["board"][mine_index]["claimed"]), "mine must kill and replace a non-ninja who selects it")

    var ninja_mine := _item_state(531)
    Items.use_item(ninja_mine, 0, "地雷", {}, Rules.DEFAULT_CONFIG, catalog)
    var ninja_mine_index := _find_mine(ninja_mine, 1)
    ninja_mine["players"][1]["board"][ninja_mine_index]["class_id"] = "忍者"
    ninja_mine["current_player"] = 1
    ninja_mine["action_stage"] = "free"
    var guaranteed := Rules.DEFAULT_CONFIG.duplicate(true)
    guaranteed["ninja_evade_chance"] = 1.0
    var evaded := Rules.select_cell(ninja_mine, 1, ninja_mine_index, "free", guaranteed, false)
    _check(_has_event(evaded["events"], "mine_evaded") and bool(ninja_mine["players"][1]["board"][ninja_mine_index]["claimed"]), "ninja must keep the selected cell when mine evasion succeeds")


func _test_recovery_items() -> void:
    var catalog := Items.load_items()
    var config := Rules.DEFAULT_CONFIG.duplicate(true)

    var token_one := _item_state(601)
    for cell in token_one["players"][0]["board"]:
        cell["construction_level"] = 2
    var token_one_result := Items.use_item(token_one, 0, "兵符LV1", {}, config, catalog)
    _check(token_one_result["events"][1]["cells"].size() == 10, "army token LV1 must reroll ten unclaimed cells")
    for index in token_one_result["events"][1]["cells"]:
        _check(int(token_one["players"][0]["board"][index]["construction_level"]) == 2, "army token LV1 must preserve construction")

    var token_two := _item_state(602)
    for cell in token_two["players"][0]["board"]:
        cell["claimed"] = true
        cell["construction_level"] = 3
        cell["status"] = "frozen"
    Items.use_item(token_two, 0, "兵符LV2", {}, config, catalog)
    _check(_count_claimed(token_two, 0) == 0 and _count_status(token_two, 0, "normal") == 25, "army token LV2 must reset claims and statuses across the full board")
    _check(int(token_two["players"][0]["board"][0]["construction_level"]) == 1, "army token LV2 must reset construction")

    var repair := _item_state(603)
    repair["players"][0]["board"][0]["status"] = "frozen"
    repair["players"][0]["board"][1]["status"] = "buried"
    Items.use_item(repair, 0, "緊急維修", {}, config, catalog)
    _check(repair["players"][0]["board"][0]["status"] == "normal" and repair["players"][0]["board"][1]["status"] == "normal", "emergency repair must clear all own negative statuses")

    var swap := _item_state(604)
    swap["players"][0]["board"][0]["claimed"] = true
    swap["players"][0]["board"][0]["class_id"] = "法師"
    swap["players"][0]["board"][0]["construction_level"] = 3
    var swapped := Items.use_item(swap, 0, "換防令", {"cell_index": 0}, config, catalog)
    _check(bool(swapped["ok"]) and swap["players"][0]["board"][0]["class_id"] == "法師" and int(swap["players"][0]["board"][0]["construction_level"]) == 3, "defense swap must reroll rarity while preserving class and construction")


func _test_profile_save_migration_and_recovery() -> void:
    var path := "/private/tmp/woven_rampart_profile_test.json"
    var profile := Profiles.default_profile()
    profile["merit_points"] = 345
    profile["castle_level"] = 3
    _check(Profiles.save_profile(profile, path), "versioned profile must save atomically")
    var loaded := Profiles.load_profile(path)
    _check(int(loaded["schema_version"]) == 2 and int(loaded["merit_points"]) == 345 and int(loaded["castle_level"]) == 3, "saved profile must round-trip without losing progression")
    var legacy := Profiles.migrate_and_validate({"meritPoints": 88, "castleLevel": 2, "classTraining": {"劍士": 4}})
    _check(int(legacy["schema_version"]) == 2 and int(legacy["merit_points"]) == 88 and int(legacy["castle_level"]) == 2 and int(legacy["class_training"]["劍士"]) == 4, "legacy camelCase profile must migrate to schema version 2")
    var version_one := Profiles.migrate_and_validate({
        "schema_version": 1,
        "unlocked_representative_stages": [1, 5],
        "campaign_progress": {"1": {"cleared": true}},
    })
    _check(version_one["unlocked_stages"] == [1, 2, 5] and not version_one.has("unlocked_representative_stages"), "schema v1 representative unlocks and cleared progress must migrate without loss")
    var corrupt_path := "/private/tmp/woven_rampart_profile_corrupt.json"
    var corrupt_file := FileAccess.open(corrupt_path, FileAccess.WRITE)
    corrupt_file.store_string("{not valid json")
    corrupt_file.close()
    var recovered := Profiles.load_profile(corrupt_path)
    _check(bool(recovered["recovered_from_corrupt"]) and int(recovered["castle_level"]) == 1, "corrupt profile must recover to safe defaults")


func _test_campaign_progression_economy() -> void:
    var stages := Campaign.load_stages()
    var stage_ids := Campaign.stage_ids(stages)
    _check(stages.size() == 46 and stage_ids.front() == 1 and stage_ids.back() == 46, "campaign catalog must expose every Stage from 1 through 46")
    var profile := Profiles.default_profile()
    profile["merit_points"] = 500
    var castle_upgrade := Progression.upgrade_castle(profile)
    _check(bool(castle_upgrade["ok"]) and int(profile["castle_level"]) == 2 and int(profile["merit_points"]) == 400, "castle Lv.1 to Lv.2 must cost 100 merit")
    var training_upgrade := Progression.upgrade_training(profile, "劍士")
    _check(bool(training_upgrade["ok"]) and int(profile["class_training"]["劍士"]) == 2 and int(profile["merit_points"]) == 340, "training Lv.1 to Lv.2 must cost 60 merit")

    profile["merit_points"] = 0
    var first := Progression.award_stage_clear(profile, stages[1], 12)
    _check(bool(first["first_clear"]) and int(first["merit_earned"]) == 30 and int(first["exp_earned"]) == 50, "first clear must award full merit and 50 experience")
    _check(2 in profile["unlocked_stages"] and 5 not in profile["unlocked_stages"], "clearing Stage 1 must unlock only Stage 2")
    var repeat := Progression.award_stage_clear(profile, stages[1], 10)
    _check(not bool(repeat["first_clear"]) and int(repeat["merit_earned"]) == 15 and int(repeat["exp_earned"]) == 0, "repeat clear must award half merit and no experience")
    _check(int(profile["campaign_progress"]["1"]["best_clear_turns"]) == 10 and int(profile["campaign_progress"]["1"]["stars"]) == 3, "progress must keep best turns and preserve the best earned star grade")
    _check(Progression.clear_rounds(21) == 11 and Progression.stars_for_clear(stages[10], 20) == 3 and Progression.stars_for_clear(stages[10], 24) == 2 and Progression.stars_for_clear(stages[10], 28) == 1, "star formula must use full rounds and the stage's data-driven three/two-star targets")
    Progression.award_stage_clear(profile, stages[5], 14)
    _check(int(profile["level"]) == 2 and "戰士" in profile["unlocked_classes"], "100 cumulative experience must reach player Lv.2 and chapter clear must unlock its class")
    _check(6 in profile["unlocked_stages"], "clearing the first chapter finale must unlock Stage 6")
    _check(is_equal_approx(Progression.castle_hp(40), 1075.0) and is_equal_approx(Progression.castle_def(40), 127.0), "castle Lv.40 formulas must match the final boss scale")


func _test_campaign_session_configuration() -> void:
    var stages := Campaign.load_stages()
    var profile := Profiles.default_profile()
    profile["castle_level"] = 3
    profile["class_training"]["劍士"] = 4
    var stage10 := Session.new(701, "easy", "平靜草原", profile, stages[10])
    _check(int(stage10.state["stage_id"]) == 10 and stage10.state["map_id"] == "極地雪原", "stage config must override free-battle map and stage id")
    _check(is_equal_approx(float(stage10.state["players"][0]["castle_hp"]), 160.0) and is_equal_approx(float(stage10.state["players"][0]["castle_def"]), 16.0), "player castle progression must apply to campaign battle")
    _check(is_equal_approx(float(stage10.state["players"][1]["castle_hp"]), 200.0) and is_equal_approx(float(stage10.state["players"][1]["castle_def"]), 22.0), "Stage 10 AI castle Lv.5 must use campaign formulas")
    _check(stage10.state["class_pool"].size() == 5 and int(stage10.config["rarity_weights"]["灰"]) == 50, "stage class pool and rarity distribution must override global balance")
    _check(int(Rules.class_weights_from_training(profile["class_training"], stage10.state["class_pool"])["劍士"]) == 145, "training Lv.4 must add 45% relative board-generation weight")

    var stage45 := Session.new(702, "easy", "平靜草原", profile, stages[45])
    _check(int(stage45.state["item_counts"][1]["瘟疫LV2"]) == 1 and int(stage45.state["item_counts"][1]["兵符LV1"]) == 0, "elite AI must receive only its configured three items")
    var opening := stage45.submit_player_action(0, "free")
    _check(bool(opening["ok"]), "elite campaign session must play through its first AI response")
    var ai_used_item := false
    for entry in stage45.action_log:
        if int(entry.get("player_index", -1)) == 1 and entry.get("action_kind", "") == "use_item":
            ai_used_item = true
    _check(ai_used_item, "elite AI must actively use a configured item on its turn")
    var replayed := Session.replay(stage45.export_replay())
    _check(bool(replayed["ok"]) and bool(replayed["matches_expected"]), "campaign configuration, AI items, and player progression must replay deterministically")


func _test_all_campaign_stages_boot() -> void:
    var stages := Campaign.load_stages()
    var chapter_maps := ["毒霧沼澤", "極地雪原", "疾風平原", "熔岩地帶", "震裂荒地", "高空浮島", "沙丘荒漠", "湖畔雨林", "迷霧森林", "末日"]
    for stage_id in range(1, 47):
        var stage: Dictionary = stages.get(stage_id, {})
        _check(not stage.is_empty(), "every campaign stage must expand from chapter data")
        if stage.is_empty():
            continue
        var chapter := int(stage["chapter"])
        _check(stage["mapId"] == chapter_maps[chapter - 1], "every stage must use its chapter map")
        var rarity_total := 0
        for weight in stage["rarityWeights"].values():
            rarity_total += int(weight)
        _check(rarity_total == 100, "every stage rarity distribution must total 100")
        _check(stage["classes"].size() == (4 if stage_id <= 5 else 5) and "建築工" in stage["classes"], "campaign class pools must follow the four-class tutorial exception and otherwise contain five classes including builder")
        var expected_item_count := 0
        if stage_id >= 26 and stage_id <= 35:
            expected_item_count = 1
        elif stage_id >= 36 and stage_id <= 40:
            expected_item_count = 2
        elif stage_id >= 41:
            expected_item_count = 3
        _check(stage["aiItems"].size() == expected_item_count, "AI item count must follow the chapter difficulty curve")
        var targets: Dictionary = stage.get("starTargets", {})
        _check(int(targets.get("threeStarMaxRounds", 0)) > 0 and int(targets.get("twoStarMaxRounds", 0)) >= int(targets.get("threeStarMaxRounds", 0)), "every campaign stage must define ordered time-based star targets")
        _check(int(stage.get("nextStage", 0)) == (stage_id + 1 if stage_id < 46 else 0), "campaign stages must form one continuous unlock chain")
        var session := Session.new(9000 + stage_id, "easy", "平靜草原", Profiles.default_profile(), stage)
        _check(int(session.state["stage_id"]) == stage_id and session.state["map_id"] == stage["mapId"], "every expanded stage must initialize a playable campaign session")
        for item_id in stage["aiItems"]:
            _check(int(session.state["item_counts"][1].get(item_id, 0)) == 1, "every configured AI item must exist in the battle inventory")
    _check(bool(stages[1].get("tutorial", false)) and int(stages[1]["rarityWeights"]["灰"]) == 100, "Stage 1 must retain its deterministic tutorial overrides")
    _check(stages[5].get("unlocksClass", "") == "戰士" and stages[10].get("unlocksClass", "") == "騎士" and stages[15].get("unlocksClass", "") == "忍者" and stages[20].get("unlocksClass", "") == "法師", "chapter finales must unlock the four advanced classes in specification order")


func _test_final_boss_weather_heal() -> void:
    var stages := Campaign.load_stages()
    var boss := Session.new(801, "hard", "末日", Profiles.default_profile(), stages[46])
    boss.state["players"][1]["castle_hp"] = 1000.0
    boss.state["round"] = 2
    var events := []
    boss._append_round_weather_events(1, events)
    _check(_has_event(events, "weather_triggered") and _has_event(events, "boss_weather_heal"), "Stage 46 must heal the boss whenever apocalypse weather changes")
    _check(is_equal_approx(float(boss.state["players"][1]["castle_hp"]), 1107.5), "final boss shelter must heal 5% of its 2150 HP cap")


func _test_construction_rules() -> void:
    var state := Rules.create_match(17)
    var cell: Dictionary = state["players"][0]["board"][0]
    cell["claimed"] = true
    state["current_player"] = 0
    state["action_stage"] = "second_action"
    var before := float(state["players"][0]["castle_hp"])
    var result := Rules.build_cell(state, 0, 0)
    _check(bool(result["ok"]), "claimed cell can be built during second action")
    _check(int(cell["construction_level"]) == 2, "construction must advance to level 2")
    _check(float(state["players"][0]["castle_hp"]) == before - 20.0, "level 2 build must cost 20 power")

    var unsafe := Rules.create_match(18)
    unsafe["current_player"] = 0
    unsafe["action_stage"] = "second_action"
    unsafe["players"][0]["board"][0]["claimed"] = true
    unsafe["players"][0]["castle_hp"] = 20.0
    var denied := Rules.build_cell(unsafe, 0, 0)
    _check(not bool(denied["ok"]) and denied["error"] == "INSUFFICIENT_POWER", "construction must preserve the 1-point safety floor")
    unsafe["action_stage"] = "follow"
    var wrong_stage := Rules.build_cell(unsafe, 0, 0)
    _check(not bool(wrong_stage["ok"]) and wrong_stage["error"] == "BUILD_NOT_AVAILABLE", "direct build calls must still enforce the turn stage")


func _test_simultaneous_attack_batch() -> void:
    var clash := Rules.resolve_attack_batch(120.0, 80.0, 10.0, 10.0)
    _check(float(clash["survivor_power_0"]) == 40.0, "stronger side must keep residual power")
    _check(float(clash["survivor_power_1"]) == 0.0, "weaker side must be annihilated")
    _check(float(clash["damage_to_1"]) == 30.0, "DEF must apply after the clash")
    var equal := Rules.resolve_attack_batch(100.0, 100.0)
    _check(float(equal["survivor_power_0"]) == 0.0 and float(equal["survivor_power_1"]) == 0.0, "equal power must annihilate both armies")
    _check(float(equal["damage_to_0"]) == 0.0 and float(equal["damage_to_1"]) == 0.0, "equal power must not damage either castle")
    var session := Session.new(19)
    var resolved: Array = session._resolve_pending_attacks([
        {"type": "attack_ready", "player_index": 0, "attack_power": 120.0},
        {"type": "attack_ready", "player_index": 1, "attack_power": 80.0},
    ])
    _check(resolved.size() == 1 and resolved[0]["type"] == "attack_batch_resolved", "PvE session must resolve both attack outputs as one batch")
    _check(float(session.state["players"][1]["castle_hp"]) == 70.0, "batch residual power must damage the weaker side's castle")
    var equal_session := Session.new(20)
    var equal_resolved: Array = equal_session._resolve_pending_attacks([
        {"type": "attack_ready", "player_index": 0, "attack_power": 100.0, "true_damage": 50.0},
        {"type": "attack_ready", "player_index": 1, "attack_power": 100.0, "true_damage": 50.0},
    ])
    _check(float(equal_session.state["players"][0]["castle_hp"]) == 110.0 and float(equal_session.state["players"][1]["castle_hp"]) == 100.0, "true damage must not hit a castle when equal armies annihilate each other")
    _check(bool(equal_resolved[0]["equal_power"]), "equal passive-enabled attacks must still resolve as mutual annihilation")


func _test_ai_difficulty_parameters() -> void:
    var easy_state := _make_ai_choice_state()
    var easy := Ai.take_turn(easy_state, 1, Rules.DEFAULT_CONFIG, false, "easy")
    _check(int(easy.get("action", {}).get("cell_index", -1)) == 0, "easy AI must use the first legal deterministic choice")
    var hard_state := _make_ai_choice_state()
    var hard := Ai.take_turn(hard_state, 1, Rules.DEFAULT_CONFIG, false, "hard")
    _check(int(hard.get("action", {}).get("cell_index", -1)) == 1, "hard AI must prefer the choice with stronger total line potential")


func _test_pve_session_replay() -> void:
    var session := Session.new(91, "hard", "末日")
    var item_use := session.submit_player_item("沙暴召喚符")
    _check(bool(item_use["ok"]), "PvE session must accept an available item")
    var opening := session.submit_player_action(0, "free")
    _check(bool(opening["ok"]), "PvE session must accept the player's opening action")
    _check(session.action_log.size() >= 3, "PvE session must record exact player and AI actions")
    for entry in session.action_log:
        _check(entry.has("cell_index") and entry.has("action_kind"), "every replay entry must contain an exact serializable action")
    var replay_data := session.export_replay()
    var replayed := Session.replay(replay_data)
    _check(bool(replayed["ok"]), "exported replay must execute successfully")
    _check(bool(replayed["matches_expected"]), "same seed, difficulty, and actions must reproduce the exact state")
    _check(replayed["state"]["map_id"] == "末日" and replayed["state"]["weather"]["kind"] != null, "replay must preserve map selection and scheduled weather")
    _check(int(replayed["state"]["item_counts"][0]["沙暴召喚符"]) == 0, "replay must reproduce item consumption")


func _test_session_auto_skips_player_follow() -> void:
    var session := Session.new(101)
    session.state["current_player"] = 0
    session.state["action_stage"] = "follow"
    session.state["chain_target"][0] = "不存在職業"
    var advanced := session._advance_automatic_actions()
    _check(bool(advanced["ok"]), "session must automatically resolve a human follow with no legal cell")
    _check(session.action_log.size() > 0 and session.action_log[0]["action_kind"] == "skip_follow", "automatic human skip must be written to the action log")
    _check(int(session.state["current_player"]) == 0, "automatic skip and AI response must return control to the human")


func _make_ai_choice_state() -> Dictionary:
    var state := Rules.create_match(77)
    state["current_player"] = 1
    state["action_stage"] = "follow"
    state["chain_target"][1] = "劍士"
    var board: Array = state["players"][1]["board"]
    for index in range(board.size()):
        board[index] = _cell("弓手", "灰", false)
    board[0] = _cell("劍士", "灰", false)
    board[1] = _cell("劍士", "灰", false)
    for index in [6, 11, 16, 21]:
        board[index] = _cell("弓手", "灰", true)
    return state


func _uniform_board(class_id: String, rarity: String) -> Array:
    var board := []
    for _index in range(25):
        board.append(_cell(class_id, rarity, true))
    return board


func _weather_state(seed_value: int, map_id: String = "平靜草原") -> Dictionary:
    var state := Rules.create_match(seed_value, Rules.ALL_CLASSES)
    Weather.initialize_state(state, map_id)
    return state


func _item_state(seed_value: int, map_id: String = "平靜草原") -> Dictionary:
    var state := _weather_state(seed_value, map_id)
    Items.initialize_state(state)
    return state


func _find_mine(state: Dictionary, player_index: int) -> int:
    for index in range(state["players"][player_index]["board"].size()):
        if bool(state["players"][player_index]["board"][index].get("mine", false)):
            return index
    return -1


func _has_event(events: Array, event_type: String) -> bool:
    for event in events:
        if event.get("type", "") == event_type:
            return true
    return false


func _count_status(state: Dictionary, player_index: int, status: String) -> int:
    var count := 0
    for cell in state["players"][player_index]["board"]:
        if cell.get("status", "normal") == status:
            count += 1
    return count


func _count_claimed(state: Dictionary, player_index: int) -> int:
    var count := 0
    for cell in state["players"][player_index]["board"]:
        if bool(cell["claimed"]):
            count += 1
    return count


func _board_contents_multiset(board: Array) -> Array:
    var contents := []
    for cell in board:
        contents.append("%s:%s:%d" % [cell["class_id"], cell["rarity"], int(cell["construction_level"])])
    contents.sort()
    return contents


func _cell(class_id: String, rarity: String, claimed: bool) -> Dictionary:
    return {
        "class_id": class_id,
        "rarity": rarity,
        "claimed": claimed,
        "construction_level": 1,
        "status": "normal",
    }


func _first_unclaimed(board: Array) -> int:
    for index in range(board.size()):
        if not bool(board[index]["claimed"]):
            return index
    return -1


func _find_unclaimed_with_class(board: Array, class_id, want_match: bool) -> int:
    for index in range(board.size()):
        var cell: Dictionary = board[index]
        var matches: bool = cell["class_id"] == class_id
        if not bool(cell["claimed"]) and matches == want_match:
            return index
    return -1
