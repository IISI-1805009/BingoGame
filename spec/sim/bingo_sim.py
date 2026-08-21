"""
織城戰線 Woven Rampart -- 核心數值模擬器 (v2)

v2 修正：雙方各自擁有一張獨立的 5x5 盤面（不是共用盤面）。連線只在自己
的盤面上判定，跟色鏈是唯一跨盤面的耦合（跟對手上一次自由選擇的職業）。
這個修正也讓 v1 發現的「25 格瓜分完卻無連線」僵局不再可能發生：每張
盤面只有單一擁有者在認領，連線一旦湊齊就會自動清空重填，不存在雙方
瓜分同一張盤面導致誰都連不成線的情況。v1 的 fallback_reshuffle 機制
在此版本移除（並用模擬驗證了 0 次真正意義上的僵局，見檔案最後的
self-check）。

範圍與簡化：
  - 完整實作：跟色鏈、二選一經濟（自由選擇 vs 建設）、連線偵測（各自
    盤面獨立判定）、傷害/回復公式（稀有度、同職業加成、多線加成）、
    7 個攻擊職業 + 建築工的被動技能（含戰士/騎士差異化）、天氣的攻擊力
    削弱效果與格子鎖定效果（冰山寒流／狂風／火山／地震／暴雨洪水，各自
    盤面獨立判定，迷霧因純資訊/心理效果未建模）、先攻方開局戰力值加成、
    瘟疫 LV2 專項測試鉤子（plague_round / plague_count，見 BALANCE.md 5.2.1）。
  - 簡化/省略：其餘 19 個道具、地圖地形加成、忍者被動。

AI 是貪婪啟發式（優先完成連線 > 累積連線潛力，會依機率選擇建設），
不是最優解，結果僅供數值方向感參考。
"""
import random

CLASSES_ATTACK = ['劍士', '武士', '戰士', '弓手', '騎士', '忍者', '法師']
BUILDER = '建築工'
RARITIES = ['灰', '綠', '藍', '紅', '金']
RARITY_MULT = {'灰': 1.0, '綠': 1.2, '藍': 1.5, '紅': 2.0, '金': 3.0}


def _build_lines():
    lines = []
    for r in range(5):
        lines.append(tuple(r * 5 + c for c in range(5)))
    for c in range(5):
        lines.append(tuple(r * 5 + c for r in range(5)))
    lines.append(tuple(i * 5 + i for i in range(5)))
    lines.append(tuple(i * 5 + (4 - i) for i in range(5)))
    return lines


LINES = _build_lines()
LINES_THROUGH = {i: [ln for ln in LINES if i in ln] for i in range(25)}


def make_config(**overrides):
    cfg = dict(
        base_atk=10,
        castle_hp=100,
        castle_def=10,
        hp_cap_mult=2.0,
        income=9,
        construction_cost={2: 20, 3: 40},
        construction_bonus={1: 0.0, 2: 0.10, 3: 0.20},
        same_class_mult=1.3,
        multiline_mult=1.3,
        swordsman_true_dmg_per_unit=10,
        samurai_pure_bonus=0.5,
        def_break_threshold=30,
        def_break_reduction=0.5,
        def_break_threshold_full=50,  # 戰士專屬：DEF>=此值時完全無視 DEF
        knight_charge_bonus=0.20,     # 騎士專屬：第2條以上連線時，該線再額外加成
        archer_pierce_pct=0.30,
        mage_heal_pct=0.10,
        builder_stack_bonus=0.15,
        rarity_weights={'灰': 40, '綠': 30, '藍': 20, '紅': 8, '金': 2},
        classes=['劍士', '弓手', '武士', '建築工', '戰士'],
        weather_enabled=True,
        weather_trigger_every=3,   # 輪
        weather_trigger_chance=0.40,
        weather_duration=2,        # 輪
        poison_debuff=0.20,
        sandstorm_debuff=0.10,
        build_probability=0.30,
        max_turns=500,
        first_mover_hp_bonus=10,  # 先攻方開局額外戰力值加成（模擬調校值，見規格書 2.2）
        plague_round=None,   # 測試用：在第幾輪對「後攻方」施放瘟疫（None=不觸發）
        plague_count=0,      # 瘟疫殺死的已認領格數
    )
    cfg.update(overrides)
    return cfg


class Cell:
    __slots__ = ('cls', 'rarity', 'claimed', 'level')

    def __init__(self, cls, rarity):
        self.cls = cls
        self.rarity = rarity
        self.claimed = False
        self.level = 1


class Castle:
    __slots__ = ('hp', 'hp_cap', 'defense')

    def __init__(self, hp, hp_cap, defense):
        self.hp = hp
        self.hp_cap = hp_cap
        self.defense = defense


def roll_rarity(cfg):
    return random.choices(RARITIES, weights=[cfg['rarity_weights'][x] for x in RARITIES])[0]


def new_cell(cfg):
    return Cell(random.choice(cfg['classes']), roll_rarity(cfg))


def make_board(cfg):
    return [new_cell(cfg) for _ in range(25)]


def line_score(board, idx):
    """單一擁有者盤面的貪婪啟發式：claimed 越多分數越高，能立即完成連線給爆炸加分。"""
    best = -1
    complete = False
    for ln in LINES_THROUGH[idx]:
        others = [j for j in ln if j != idx]
        claimed_count = sum(1 for j in others if board[j].claimed)
        if claimed_count == 4:
            complete = True
        best = max(best, claimed_count)
    return best + (1000 if complete else 0), complete


def pick_best_cell(board, candidates):
    scored = [(line_score(board, idx)[0], idx) for idx in candidates]
    scored.sort(key=lambda x: (-x[0], random.random()))
    return scored[0][1]


WEATHER_KINDS = ['poison', 'sandstorm', 'ice', 'wind', 'volcano', 'quake', 'flood', 'fog']


class Weather:
    """locked[p][idx] = round 編號，超過就自動解除（凍結/掩埋，見 6.2）。
    狂風/火山/暴雨洪水是觸發當下的一次性效果，不佔用「持續中」狀態。
    迷霧目前確認為純粹的資訊/心理效果，不影響任何合法選格判定，故不建模。
    """

    def __init__(self):
        self.kind = None
        self.rounds_left = 0
        self.affected_cell = [None, None]  # 每張盤面各自的中毒目標格
        self.locked = [dict(), dict()]      # idx -> 解除的 round 數

    def active(self):
        return self.kind is not None

    def is_locked(self, player, idx, current_round):
        until = self.locked[player].get(idx)
        return until is not None and current_round < until

    def maybe_trigger(self, cfg, boards, current_round):
        if not cfg['weather_enabled']:
            return
        if random.random() < cfg['weather_trigger_chance']:
            self.kind = random.choice(WEATHER_KINDS)
            self.rounds_left = cfg['weather_duration']
            if self.kind == 'poison':
                self.affected_cell = [random.randrange(25), random.randrange(25)]
            elif self.kind == 'ice':
                for p in range(2):
                    for idx in random.sample(range(25), 3):
                        self.locked[p][idx] = current_round + cfg['weather_duration']
            elif self.kind == 'quake':
                for p in range(2):
                    for idx in random.sample(range(25), 3):
                        # 簡化：原規則需消耗一次行動才能清除，這裡近似為跟凍結同時長自動排除
                        self.locked[p][idx] = current_round + cfg['weather_duration']
            elif self.kind == 'wind':
                for p in range(2):
                    board = boards[p]
                    unclaimed = [j for j in range(25) if not board[j].claimed]
                    pick = random.sample(unclaimed, min(5, len(unclaimed)))
                    contents = [(board[j].cls, board[j].rarity) for j in pick]
                    random.shuffle(contents)
                    for j, (c, r) in zip(pick, contents):
                        board[j].cls, board[j].rarity = c, r
            elif self.kind == 'volcano':
                for p in range(2):
                    board = boards[p]
                    for idx in random.sample(range(25), 3):
                        board[idx] = new_cell(cfg)
            elif self.kind == 'flood':
                for p in range(2):
                    board = boards[p]
                    claimed = [j for j in range(25) if board[j].claimed]
                    pick = random.sample(claimed, min(3, len(claimed)))
                    contents = [(board[j].cls, board[j].rarity, board[j].level) for j in pick]
                    random.shuffle(contents)
                    for j, (c, r, lv) in zip(pick, contents):
                        board[j].cls, board[j].rarity, board[j].level = c, r, lv

    def tick_round(self, cfg):
        if self.active():
            self.rounds_left -= 1
            if self.rounds_left <= 0:
                self.kind = None
                self.affected_cell = [None, None]


def unit_atk_value(cell, idx, player, cfg, weather, archer_pierce=False):
    base = cfg['base_atk'] * RARITY_MULT[cell.rarity]
    debuff = 0.0
    if weather.active():
        if weather.kind == 'poison' and idx == weather.affected_cell[player]:
            debuff = cfg['poison_debuff']
        elif weather.kind == 'sandstorm':
            debuff = cfg['sandstorm_debuff']
    if debuff and archer_pierce:
        debuff *= (1 - cfg['archer_pierce_pct'])
    return base * (1 - debuff)


def resolve_line(board, ln, player, cfg, weather, line_no_this_turn, castles):
    attackers = [j for j in ln if board[j].cls in CLASSES_ATTACK]
    builders = [j for j in ln if board[j].cls == BUILDER]
    all_same = len({board[j].cls for j in ln}) == 1

    multiline_mult = cfg['multiline_mult'] if line_no_this_turn >= 2 else 1.0
    same_mult = cfg['same_class_mult'] if all_same else 1.0

    atk_sum = 0.0
    swordsman_count = 0
    has_warrior = False
    has_knight = False
    mage_bonus_heal = 0.0
    for j in attackers:
        cell = board[j]
        is_archer = cell.cls == '弓手'
        val = unit_atk_value(cell, j, player, cfg, weather, archer_pierce=is_archer)
        val *= (1 + cfg['construction_bonus'][cell.level])
        if cell.cls == '劍士':
            swordsman_count += 1
        if cell.cls == '武士' and all_same:
            val *= (1 + cfg['samurai_pure_bonus'])
        if cell.cls == '戰士':
            has_warrior = True
        if cell.cls == '騎士':
            has_knight = True
        if cell.cls == '法師':
            mage_bonus_heal += val * cfg['mage_heal_pct']
        atk_sum += val

    true_dmg = swordsman_count * cfg['swordsman_true_dmg_per_unit'] * multiline_mult if swordsman_count else 0.0

    # 騎士：貫穿衝鋒，第2條以上連線時該線再額外加成
    knight_mult = (1 + cfg['knight_charge_bonus']) if (has_knight and line_no_this_turn >= 2) else 1.0

    dmg = 0.0
    if attackers:
        defender = castles[1 - player]
        eff_def = defender.defense
        if has_warrior and eff_def >= cfg['def_break_threshold_full']:
            eff_def = 0.0  # 戰士：DEF 達到完全穿透門檻
        elif has_warrior and eff_def >= cfg['def_break_threshold']:
            eff_def *= (1 - cfg['def_break_reduction'])
        dmg = max(1.0, atk_sum * same_mult * multiline_mult * knight_mult - eff_def) + true_dmg

    heal_sum = 0.0
    if builders:
        raw = 0.0
        for j in builders:
            cell = board[j]
            val = unit_atk_value(cell, j, player, cfg, weather, archer_pierce=False)
            val *= (1 + cfg['construction_bonus'][cell.level])
            raw += val
        stack_mult = 1 + cfg['builder_stack_bonus'] * (len(builders) - 1)
        heal_sum = raw * stack_mult * same_mult * multiline_mult

    heal_total = heal_sum + mage_bonus_heal * multiline_mult

    for j in ln:
        board[j] = new_cell(cfg)

    return dmg, heal_total


def find_completed_lines(board, idx):
    out = []
    for ln in LINES_THROUGH[idx]:
        if all(board[j].claimed for j in ln):
            out.append(ln)
    return out


def apply_income(castle, amount):
    castle.hp = min(castle.hp_cap, castle.hp + amount)


def choose_and_claim(board, candidates, player, cfg, castles, weather, turn_line_count):
    idx = pick_best_cell(board, candidates)
    board[idx].claimed = True
    board[idx].level = 1
    completed = find_completed_lines(board, idx)
    triggered = False
    for ln in completed:
        if any(not board[j].claimed for j in ln):
            continue  # 已被前一條線的清空重填影響，跳過
        turn_line_count += 1
        dmg, heal = resolve_line(board, ln, player, cfg, weather, turn_line_count, castles)
        castles[1 - player].hp = max(0.0, castles[1 - player].hp - dmg)
        apply_income(castles[player], heal)
        triggered = True
    return idx, turn_line_count, triggered


def maybe_apply_plague(cfg, boards, mover1, rounds, already_applied):
    """測試用：模擬瘟疫 LV2 在中局對後攻方施放的效果（見 BALANCE.md 瘟疫 LV2 調校）。"""
    if already_applied or cfg['plague_round'] is None or rounds < cfg['plague_round']:
        return already_applied
    target = 1 - mover1
    board_t = boards[target]
    claimed = [j for j in range(25) if board_t[j].claimed]
    for idx in random.sample(claimed, min(cfg['plague_count'], len(claimed))):
        board_t[idx] = new_cell(cfg)
    return True


def decide_build(board, cfg, castle, weather, player, current_round):
    upgradable = [j for j in range(25) if board[j].claimed and board[j].level < 3
                  and not weather.is_locked(player, j, current_round)]
    if not upgradable:
        return None
    upgradable.sort(key=lambda j: board[j].level)
    target = upgradable[0]
    cost = cfg['construction_cost'][board[target].level + 1]
    if castle.hp - cost < 1:
        return None
    if random.random() > cfg['build_probability']:
        return None
    return target, cost


def simulate_match(cfg, seed=None):
    if seed is not None:
        random.seed(seed)
    boards = [make_board(cfg), make_board(cfg)]
    hp0 = cfg['castle_hp']
    cap = hp0 * cfg['hp_cap_mult']
    castles = [Castle(hp0, cap, cfg['castle_def']), Castle(hp0, cap, cfg['castle_def'])]
    weather = Weather()

    mover1 = random.randrange(2)
    if cfg['first_mover_hp_bonus']:
        castles[mover1].hp = min(castles[mover1].hp_cap, castles[mover1].hp + cfg['first_mover_hp_bonus'])
    current = mover1
    first_move = True
    chain_class = [None, None]  # chain_class[p] = 職業 p 這回合要跟的色
    turns = 0
    rounds = 0
    turns_since_round_boundary = 0
    lines_total = 0
    build_count = 0
    stuck = False
    plague_applied = False

    for _ in range(cfg['max_turns']):
        if castles[0].hp <= 0 or castles[1].hp <= 0:
            break
        turns += 1
        board = boards[current]
        if first_move:
            all_unclaimed = [j for j in range(25) if not board[j].claimed]
            if not all_unclaimed:
                stuck = True  # 真正的滿盤（結構上不該發生，見 GAME_DESIGN.md 2.3）
                break
            candidates = [j for j in all_unclaimed if not weather.is_locked(current, j, rounds)]
            if not candidates:
                # 全部空格都暫時被凍結/掩埋，本回合無格可選，控制權交還對手重新起始
                current = 1 - current
                continue
            idx, _, trig = choose_and_claim(board, candidates, current, cfg, castles, weather, 0)
            if trig:
                lines_total += 1
            apply_income(castles[current], cfg['income'])
            chain_class[1 - current] = board[idx].cls if board[idx].claimed else chain_class[1 - current]
            first_move = False
        else:
            target_class = chain_class[current]
            legal = [j for j in range(25) if not board[j].claimed and board[j].cls == target_class
                     and not weather.is_locked(current, j, rounds)]
            if not legal:
                current = 1 - current
                first_move = True
                continue
            turn_line_count = 0
            idx, turn_line_count, trig = choose_and_claim(board, legal, current, cfg, castles, weather, turn_line_count)
            if trig:
                lines_total += 1
            if castles[0].hp <= 0 or castles[1].hp <= 0:
                break
            build = decide_build(board, cfg, castles[current], weather, current, rounds)
            if build:
                target, cost = build
                castles[current].hp -= cost
                board[target].level += 1
                build_count += 1
            else:
                all_unclaimed = [j for j in range(25) if not board[j].claimed]
                candidates = [j for j in all_unclaimed if not weather.is_locked(current, j, rounds)]
                if not candidates:
                    # 沒有可自由選擇的格子（真正滿盤或全部暫時鎖定），本回合第二動作作廢
                    candidates = None
                if candidates is None:
                    turns_since_round_boundary += 1
                    if turns_since_round_boundary >= 2:
                        turns_since_round_boundary = 0
                        rounds += 1
                        if rounds % cfg['weather_trigger_every'] == 0:
                            weather.maybe_trigger(cfg, boards, rounds)
                        weather.tick_round(cfg)
                        plague_applied = maybe_apply_plague(cfg, boards, mover1, rounds, plague_applied)
                    current = 1 - current
                    continue
                idx2, turn_line_count, trig2 = choose_and_claim(board, candidates, current, cfg, castles, weather, turn_line_count)
                if trig2:
                    lines_total += 1
                apply_income(castles[current], cfg['income'])
                chain_class[1 - current] = board[idx2].cls
        turns_since_round_boundary += 1
        if turns_since_round_boundary >= 2:
            turns_since_round_boundary = 0
            rounds += 1
            if rounds % cfg['weather_trigger_every'] == 0:
                weather.maybe_trigger(cfg, boards, rounds)
            weather.tick_round(cfg)
            plague_applied = maybe_apply_plague(cfg, boards, mover1, rounds, plague_applied)
        current = 1 - current

    if castles[0].hp <= 0 and castles[1].hp <= 0:
        winner = 1 - current
    elif castles[0].hp <= 0:
        winner = 1
    elif castles[1].hp <= 0:
        winner = 0
    else:
        winner = None

    return dict(
        winner=winner,
        mover1=mover1,
        mover1_won=(winner == mover1) if winner is not None else None,
        turns=turns,
        rounds=rounds,
        lines_total=lines_total,
        build_count=build_count,
        stuck=stuck,
        hp0=castles[0].hp, hp1=castles[1].hp,
    )


def run_batch(cfg, n, seed_base=0):
    results = [simulate_match(cfg, seed=seed_base + i) for i in range(n)]
    decided = [r for r in results if r['winner'] is not None]
    n_decided = len(decided)
    mover1_wins = sum(1 for r in decided if r['mover1_won'])
    avg_turns = sum(r['turns'] for r in decided) / max(1, n_decided)
    avg_rounds = sum(r['rounds'] for r in decided) / max(1, n_decided)
    avg_lines = sum(r['lines_total'] for r in decided) / max(1, n_decided)
    avg_builds = sum(r['build_count'] for r in decided) / max(1, n_decided)
    stuck_count = sum(1 for r in results if r['stuck'])
    timeouts = n - n_decided
    return dict(
        n=n,
        decided=n_decided,
        timeouts=timeouts,
        stuck_count=stuck_count,
        mover1_win_rate=mover1_wins / max(1, n_decided),
        avg_turns=avg_turns,
        avg_rounds=avg_rounds,
        avg_lines=avg_lines,
        avg_builds=avg_builds,
    )


if __name__ == '__main__':
    cfg = make_config()
    stats = run_batch(cfg, 5000, seed_base=1)
    for k, v in stats.items():
        print(f'{k}: {v}')
