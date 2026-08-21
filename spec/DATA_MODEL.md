# 織城戰線 Woven Rampart — 資料模型與訊息格式

> 本文件定義 [TECH_ARCHITECTURE.md](TECH_ARCHITECTURE.md) 提到的資料結構與 Client↔Server 訊息格式。所有數值欄位對應的規則見 [GAME_DESIGN.md](GAME_DESIGN.md)，本文件只管「資料長什麼樣子」。以 TypeScript-like 的型別記法書寫，實作時對照為 GDScript typed class／Dictionary，跨網路時使用版本化 JSON。

## 1. 玩家帳號資料（PlayerProfile）

MVP 單機版存於 Godot `user://` 的版本化存檔；正式連網後由 meta backend 保存權威帳號資料，本機只保留 cache。貨幣與解鎖的遠端寫入不得由 client 直接決定。

```
PlayerProfile {
  schemaVersion: int
  playerId: string                 // 單機為本機 ID；連網後由驗證服務提供
  displayName: string
  level: int                       // 玩家等級，見 GAME_DESIGN.md 4.1、經濟數值見 4.4
  exp: int

  // 單機資源（GAME_DESIGN.md 10.1）
  meritPoints: int                 // 戰功點數
  castleLevel: int                 // 單機城堡等級
  classTraining: Map<ClassId, int> // 8 個職業各自的職業訓練所等級（4.1）

  // 對戰資源（GAME_DESIGN.md 9.2，與單機資源互不流通）
  honorPoints: int                 // 榮譽點數
  unlockedClassesPvp: ClassId[]    // 已解鎖的 PvP 職業庫，預設 [劍士,弓手,武士,建築工]
  unlockedItemsPvp: ItemId[]       // 已解鎖的 PvP 道具池，預設 [驅寒毛毯,瘟疫LV1,兵符LV1,晴天結界]

  // 單機戰役進度（GAME_DESIGN.md 10.2）
  campaignProgress: Map<StageId, StageResult>
}

StageResult {
  cleared: bool
  stars: 1 | 2 | 3  // 見 GAME_DESIGN.md 10.2.1；保留歷史最高值
  bestClearTurns: int // 最少 turnsCompleted；顯示輪數為 ceil(bestClearTurns / 2)
}

ClassId = '劍士' | '武士' | '戰士' | '弓手' | '騎士' | '忍者' | '法師' | '建築工'
ItemId = 瘟疫LV1 | 瘟疫LV2 | ... （20 個道具，逐一對應 GAME_DESIGN.md 第八節的道具名稱）
```

## 2. 對局狀態（MatchState）

`MatchState` 是 PvP server／本機 PvE 使用的完整權威狀態，**不得直接下發給 PvP client**。PvP 必須依收件玩家轉成第 3 節的 `MatchView`，只遮罩對手尚未認領的格子；已認領角色、稀有度與建設等級是公開資訊。對局結束後只把結算摘要冪等寫入 meta backend。

```
MatchState {
  schemaVersion: int
  stateVersion: int                // 每個成功 Action 後 +1，用於拒絕過期操作
  matchId: string
  mode: 'pvp' | 'pve'
  mapId: MapId                     // 見 GAME_DESIGN.md 第七節，決定主天氣與地形加成表

  players: [PlayerInMatch, PlayerInMatch]   // index 0/1，對應 GAME_DESIGN.md 模擬器裡的 player 0/1
  currentTurnPlayer: 0 | 1
  firstMover: 0 | 1                // 擲骰勝出方，開局 +10 戰力值（見 2.2）
  turnPhase: 'follow_color' | 'free_or_build' | 'waiting_for_input'
  turnTimer: { deadline: timestamp, action: 'follow_color' | 'free_choice' | 'build_or_free' }

  chainClassTarget: [ClassId | null, ClassId | null]  // 各自要跟的職業，index 對應 players

  weather: {
    kind: WeatherKind | null
    roundsLeft: int
    lockedCells: [Map<cellIndex, unlockRound>, Map<cellIndex, unlockRound>]  // 冰山寒流/地震
  }

  round: int                       // 見 2.2「輪」的定義
  linesCompletedThisTurn: int      // 用於多線加成判定，見 2.4

  itemPool: [ItemId[], ItemId[]]   // 雙方賽前選的 3 個道具（PvP）
  itemsUsed: [Map<ItemId, bool>, Map<ItemId, bool>]

  winner: 0 | 1 | null
  resultId: string | null          // 結算唯一 ID，避免獎勵重複發放

  // 僅 server／本機 PvE 保存，不出現在進行中的 PvP MatchView
  rngState: string
  processedActionIds: string[]
}

PlayerInMatch {
  playerId: string
  board: Cell[25]                  // 見 2.1，各自獨立盤面
  castleHp: number
  castleHpCap: number
  castleDef: number
  personalExclusiveClass: ClassId | null   // 見 9.1，+15% 加成對象
}

Cell {
  classId: ClassId
  rarity: '灰' | '綠' | '藍' | '紅' | '金'
  claimed: bool
  constructionLevel: 1 | 2 | 3
  status: 'normal' | 'frozen' | 'buried' | 'fogged'   // 見第六節天氣格子效果
}
```

## 3. 玩家可見狀態（MatchView）

server 必須為每個玩家分別建立 view；「畫面不顯示」不是安全界線，未公開資料不可出現在封包中。

```text
MatchView {
  schemaVersion: int
  stateVersion: int
  matchId: string
  mode: 'pvp' | 'pve'
  mapId: MapId
  self: PlayerView                 // 自己的完整盤面
  opponent: OpponentView           // 只遮罩對手未認領格的盤面
  currentTurnPlayerId: string
  firstMoverPlayerId: string
  turnPhase: 'follow_color' | 'free_or_build' | 'waiting_for_input'
  turnDeadline: timestamp
  chainClassTarget: ClassId | null // 僅該玩家現在需要跟的目標
  weather: PublicWeatherView
  round: int
  ownItemPool: ItemId[]
  ownItemsUsed: Map<ItemId, bool>
  winnerId: string | null
}

PlayerView {
  playerId: string
  board: Cell[25]
  castleHp: number
  castleHpCap: number
  castleDef: number
  personalExclusiveClass: ClassId | null
}

OpponentView {
  playerId: string
  board: ObservedCellView[25]
  castleHp: number
  castleHpCap: number
  castleDef: number
  personalExclusiveClass: ClassId | null
}

ObservedCellView {
  claimed: bool
  publicStatus: 'normal' | 'frozen' | 'buried' | 'fogged'
  classId: ClassId | null          // 未認領時為 null；已認領時公開
  rarity: '灰' | '綠' | '藍' | '紅' | '金' | null
  constructionLevel: 1 | 2 | 3 | null // 未認領時為 null；已認領時公開
}
```

若日後規則決定某項資訊也需隱藏（例如對手尚未使用的道具），以移除欄位處理，不使用「client 收到但 UI 不畫」的做法。對手未認領格的 `classId`、`rarity`、`constructionLevel` 必須在序列化前移除或設為 null，不能把完整 Cell 下發後再靠 UI 隱藏。

## 4. WebSocket 訊息格式（對局內）

第一個訊息完成驗證後，server 將 socket 綁定到玩家身分；後續 Action 不再接受 client 自報 `playerId`。所有會改變狀態的 Action 都帶唯一 `actionId` 與 client 最後看見的 `expectedStateVersion`。

**Client → Server**

```
JoinMatch      { protocolVersion, matchId, authToken }
Resume         { protocolVersion, matchId, authToken }
SelectCell     { actionId, expectedStateVersion, cellIndex }
ChooseBuild    { actionId, expectedStateVersion, cellIndex }
UseItem        { actionId, expectedStateVersion, itemId, target? }
Surrender      { actionId, expectedStateVersion }
```

**Server → Client**

```
MatchViewSync    { view: MatchView }                     // 開局、Resume 或版本落後時使用
ActionResolved   { actionId, stateVersion, publicEvents: DomainEvent[], view: MatchView }
AttackBatchResolved { batchId, sides: [{ playerId, power, survivorPower, damage, heal, outcome }], resolutionOrder }
LineResult       { lineIndices: int[], damage: number, heal: number, isPure: bool, isMultiline: bool }
WeatherTriggered { kind: WeatherKind, affectedCells: [int[], int[]] }
ItemUsed         { playerId, itemId, effect: any }
TurnTimeout      { playerId, autoAction: SelectCell | ChooseBuild }
MatchEnded       { resultId, winnerId, honorPointsEarned?, meritPointsEarned? }
ActionRejected   { actionId?, stateVersion, errorCode, message, latestView?: MatchView }
```

正式環境的 `authToken` 只能透過 TLS 傳送且不得寫入 log／replay。`DomainEvent` 只包含該玩家可見的演出資料；不得藉事件繞過 `MatchView` 遮罩。

## 5. 尚待補的部分

- **星等門檻的真人調校**：`StageResult.stars` 的公式與資料欄位已定案（GAME_DESIGN.md 10.2.1）；Stage 1 與 Stage 46 的具體輪數門檻尚須以真人 playtest 重校。
- **道具目標選擇的完整清單**：目前只有「職業封印」明確需要指定目標（選職業），需要逐一過一遍 20 個道具確認哪些需要額外參數（例如「地雷」是隨機放置不需要，但要不要讓玩家選「用在哪一場」以外的額外參數？目前設計是不需要）。
- **錯誤碼清單**（`ActionRejected.errorCode`）：例如 `NOT_YOUR_TURN`、`STALE_STATE`、`CELL_UNAVAILABLE`、`ITEM_EXHAUSTED`、`ACTION_ALREADY_PROCESSED`，需要在實作時列出完整清單，供 client 顯示對應提示。
- **公開事件欄位**（`DomainEvent`）：實作動畫前列出穩定事件 schema，並逐項確認不會洩漏對手隱藏資訊。
