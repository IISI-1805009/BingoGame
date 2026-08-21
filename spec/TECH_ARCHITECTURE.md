# 織城戰線 Woven Rampart — Godot 技術架構

> 本文件是 [GAME_DESIGN.md](GAME_DESIGN.md) 的技術實作對應文件，回答「用什麼技術、怎麼串起來」。玩法規則仍以 GAME_DESIGN.md 為準，實作順序見 [DEVELOPMENT_PLAN.md](DEVELOPMENT_PLAN.md)。

## 0. 決策摘要

| 項目 | 決定 | 一句話理由 |
|---|---|---|
| 遊戲引擎 | **Godot 4.x 最新穩定版（standard build）** | 以成熟的 GDScript 行動裝置匯出路徑為主；升級小版本前先跑自動測試與雙平台 smoke test |
| 語言 | **GDScript** | Godot 的 C# 行動裝置匯出仍有額外限制；本案優先降低 iOS／Android 建置風險 |
| Renderer | **Compatibility** 起步 | 本作以 2D UI 為主，先選行動裝置與 iOS Simulator 相容性較廣的路徑；需要特效時再以實機數據評估調整 |
| 畫面技術 | Godot `Control`／`Container`／Theme；戰鬥演出使用 `AnimationPlayer`／Tween | 本作是 2D UI 導向的回合制遊戲，不需要 3D 或重型物理系統 |
| 對局權威 | **伺服器主導**（server-authoritative） | PvP client 只送出意圖；合法性、亂數、計時、傷害與勝負均由 server 決定 |
| 核心規則 | `res://game_core/` 的純 GDScript domain layer，client 與 Godot headless match server 共用 | 避免 PvE／PvP 各寫一套規則；核心不得依賴場景、畫面、音效或輸入節點 |
| 單機存檔 | MVP 使用 `user://` 版本化存檔；正式帳號上線後再同步至 meta backend | 先完成可離線玩的單機垂直切片，不讓帳號服務阻擋核心玩法驗證 |
| Meta 後端 | **正式連網階段前決定供應商**；介面先抽象為 HTTPS API | Godot 沒有必須綁定的第一方服務；先固定資料契約，避免現在過早綁定廠商 |
| 對局後端 | Godot 4 headless dedicated server，單一程序可承載多場 `MatchSession` | 與 client 共用 GDScript 規則；Godot 4 可直接以 headless／dedicated-server export 執行 |
| 通訊 | 對局內 `wss://` WebSocket + JSON；meta 資料走 HTTPS JSON API | 回合制重視可靠與易除錯，不需要 UDP 等級的延遲；正式環境一律 TLS |

不採用 Godot C# 作為預設，是因為本作首發目標包含 iOS／Android，而 Godot 官方目前仍將 C# 行動裝置匯出標為 experimental。若未來要改用 C#，必須先用實機完成 iOS、Android、原生插件與商店封裝的技術驗證，不可只憑桌面版成功就切換。

## 1. 系統分層

```text
┌────────────────────────────────────────────────────────────┐
│ Godot Client（iOS / Android；開發期另有 Desktop debug）       │
│ - Scene/UI、動畫、觸控輸入、音效                              │
│ - PvE：呼叫 game_core，在本機執行規則與 AI                     │
│ - PvP：只送 Action，依伺服器提供的 MatchView 更新畫面            │
│ - LocalSaveRepository / MetaApiClient / MatchSocketClient     │
└────────────────────────────────────────────────────────────┘
                  │ wss://                    │ https://
                  ▼                           ▼
┌────────────────────────────────┐  ┌───────────────────────────┐
│ Godot Headless Match Server     │  │ Meta Backend（供應商待選） │
│ - MatchSession（每場一個）       │  │ - 登入與 token 驗證          │
│ - game_core（規則唯一實作）      │  │ - 玩家進度與雙軌貨幣          │
│ - 合法性驗證／權威亂數／15 秒計時 │  │ - 解鎖、排行榜、營運資料       │
│ - 依玩家產生遮罩後 MatchView     │  │ - 對局結果冪等寫入             │
│ - 斷線保留、重連、超時代打       │  └───────────────────────────┘
└────────────────────────────────┘
                  │
                  ▼
┌────────────────────────────────┐
│ res://game_core/（純 GDScript） │
│ - 狀態／Action／Result           │
│ - 跟色、連線、傷害、天氣、道具    │
│ - Seeded RNG 與序列化            │
│ - 不讀取 Node、SceneTree、時間或網路│
└────────────────────────────────┘
```

## 2. Godot 專案邊界

建議目錄如下；實際建立專案時沿用，不把規則塞進畫面 script：

```text
res://
  game_core/          # 純規則、資料物件、seeded RNG；client/server 共用
  game_client/        # 場景、presenter、輸入、動畫、音效
  game_server/        # MatchSession、連線、計時、MatchView 遮罩
  ai/                 # PvE 決策；只能透過公開 Action API 操作 core
  data/               # 職業、道具、關卡、平衡參數 Resource/JSON
  infrastructure/     # local save、HTTP、WebSocket、logging
  tests/              # 單元、契約、回放與整合測試
```

核心規則必須符合以下限制：

- 輸入是 `MatchState + Action + RNG`，輸出是新狀態與 `DomainEvent[]`；不直接播放動畫。
- 不呼叫 `Time`、全域隨機、`SceneTree` 或任何 UI Node；所有亂數由 server 建立的 seed／state 注入。
- 所有 Action 都可驗證、序列化並留下 replay log；相同初始狀態、seed 與 Action 序列必須得到相同結果。
- [sim/bingo_sim.py](sim/bingo_sim.py) 保留作平衡實驗工具，不成為 production runtime；以固定案例測試對照 Python 與 GDScript 的關鍵公式。

## 3. 單機模式技術路徑

- PvE 直接在 client 內建立 `MatchSessionLocal`，呼叫同一份 `game_core`。
- AI 只能讀取規則允許它看到的 `MatchView`，並回傳一般 Action，不能直接改 `MatchState`。
- 第一階段使用 `user://save.json`（或二進位等價格式），必須包含 `schemaVersion`、原子寫入與壞檔備份；不要直接序列化 Scene/Node。
- 單機進度先離線可用。加入帳號後由 `ProfileRepository` 決定讀本機或遠端，UI 與規則層不感知存檔來源。

## 4. 對戰模式技術路徑

1. **驗證與配對**：client 以 meta backend 核發的短效 token 建立連線；配對服務產生 `matchId`，Match Server 建立 `MatchSession`。
2. **開局**：選地圖、共同職業、個人專屬、道具與擲骰全部由 server 驗證／計算並廣播結果。
3. **行動**：client 傳 `actionId + expectedStateVersion + action payload`。server 驗證身分、回合、格子、道具與狀態版本後才套用。
4. **同步**：每次成功行動使 `stateVersion` 遞增。server 依收件玩家產生 `MatchView`，只遮掉對手尚未認領格的職業、稀有度與建設等級；已認領角色資訊公開，不能把完整 `MatchState` 送到 client 再靠 UI 隱藏。
5. **計時**：15 秒 deadline 使用 server 的 monotonic clock；client 倒數只供顯示，不能決定是否超時。
6. **結算**：server 產生帶唯一 `resultId` 的結果，透過 meta API 冪等寫入獎勵，成功後才標記已發放，避免重送造成重複領取。

## 5. 斷線重連與訊息可靠性

重連不需要新增玩法規則，但仍是明確的工程功能：

- socket 與玩家身分分離，以 `matchId + authenticatedPlayerId` 找回對局；`playerId` 不接受 client 自報。
- 對局在斷線後繼續計時並執行超時代打；server 保留到對局結束加上一段清理寬限期。
- 重連成功後回傳該玩家專屬的完整 `MatchView` 與目前 `stateVersion`，client 以此重建畫面。
- `actionId` 用於去重；`expectedStateVersion` 用於拒絕過期操作。重送同一 Action 不得重複扣資源或觸發傷害。
- client 只把動畫當成 state transition 的呈現；重連或漏事件時可跳過舊動畫，直接呈現最新狀態。

## 6. 資料與安全界線

詳細結構見 [DATA_MODEL.md](DATA_MODEL.md)。額外原則如下：

- `MatchState` 是 server／本機 PvE 的完整狀態；`MatchView` 才是 PvP 下發資料，兩者不可混用。
- auth token 只放在連線驗證或 HTTPS header，不寫 log、不進 replay。
- PvP 亂數 seed／內部 RNG state 不在對局進行中下發，避免預測未來盤面；對局結束後可依除錯政策保存 server-side replay。
- client 顯示的錯誤訊息來自穩定 `errorCode` 對照表，不直接顯示 server exception。

## 7. 部署與擴容

- 開發期：以桌面 client + 本機 `godot --headless` server 做端到端測試。
- MVP：一個 Linux dedicated-server export 承載多場 `MatchSession`，前方以支援 WebSocket/TLS 的反向代理終止 `wss://`。
- 對局狀態先放 server 記憶體；程序異常時該局不可恢復是 MVP 已知限制。公開測試前至少加入 action replay／週期 snapshot，或明確接受異常局作廢並補償。
- 擴容時以 `matchId` 做 sticky routing；需要跨程序恢復後再導入 Redis／共享 snapshot storage，不提前複雜化。
- dedicated-server export 應排除材質、貼圖與音訊等 server 不需要的資源。

## 8. 測試與發佈門檻

- 單元測試：跟色、跳過、所有連線方向、逐線 DEF、同色／多線倍率、建設、天氣、20 道具、勝負。
- 決定性測試：固定 seed + Action log 的最終 state hash 在 client 與 headless server 一致。
- 資訊遮罩測試：任何 `MatchView` 都不得含對手**未認領格**的 `classId`、`rarity`、`constructionLevel` 或未公開道具資訊；已認領角色的公開欄位必須與雙方畫面一致。
- 網路整合：重送、亂序、過期版本、斷線重連、雙端同時送操作、timeout race。
- 行動裝置 smoke test：每個里程碑至少在一台實體 Android 與一台實體 iOS 測試觸控、安全區、背景切換、網路切換與恢復。

## 9. 正式連網前的決策閘門

- Meta backend 供應商與資料所在地區、費用、備份／刪除帳號能力。
- 登入方案：guest、Sign in with Apple、Google Play Games／Google Sign-In 的組合。
- Match Server 雲端與區域；台灣／亞洲玩家的延遲目標。
- 監控、crash reporting、隱私同意與營運分析方案。
- 程序異常時採「恢復對局」或「作廢並補償」；這會決定 snapshot／replay 的必要深度。

## 10. 官方技術依據

- [Godot：匯出 dedicated server／headless 專案](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_dedicated_servers.html)
- [Godot：WebSocket 網路支援](https://docs.godotengine.org/en/stable/tutorials/networking/websocket.html)
- [Godot：Android 匯出](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_android.html)
- [Godot：iOS 匯出](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_ios.html)
