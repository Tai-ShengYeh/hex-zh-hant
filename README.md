# hex-zh-hant

讓 **Hex**（Anomaly 的本機語音聽寫工具）在 Windows 上安裝好，並且把**聽寫輸出的中文改成繁體（台灣用語）**。

> Hex 內建只有介面語言的繁體中文，**聽寫文字本身沒有簡轉繁**。
> 官方說明：沒有任何模型能穩定選對字形（[#1835](https://github.com/anomalyco/hex/issues/1835)），
> 而官方認可的解法是 `hex.config.ts` 的自訂轉換（[#829](https://github.com/anomalyco/hex/issues/829)）。
> 這個 repo 就是把那條路鋪成一鍵腳本。

---

## 給 Agent 的指令（先讀 `AGENTS.md`）

從已檢視過的本機 clone 執行，不要直接抓 `main` 分支的腳本來跑（分支內容隨時可能改變）：

```powershell
powershell -ExecutionPolicy Bypass -File .\install-windows.ps1
```

腳本自己會驗證下面三個條件，任何一項不成立就以非零結束碼結束。

驗證成功的三個條件：

1. `hex commands check` 輸出含 `3 transformations`
2. `hex settings get ui_language` 輸出 `zh-Hant`
3. `hex settings get dictation_processing.default_mode` 內含 `s2twp`

## 給人的安裝方式

```powershell
# clone 後執行（轉換器檔案會以內建的 SHA-256 核對）
git clone https://github.com/mathruffian-dot/hex-zh-hant
cd hex-zh-hant
powershell -ExecutionPolicy Bypass -File .\install-windows.ps1
```

參數：

| 參數 | 說明 |
|---|---|
| `-Hotkey control+option+space` | 聽寫快捷鍵（預設 `Ctrl+Alt+Space`） |
| `-SkipHotkey` | 不動你現有的快捷鍵 |
| `-ConfigureOnly` | 不安裝、不啟動 Hex，也不動介面語言與快捷鍵；只放轉換器並加入 `s2twp` |
| `-AllowUnreviewedInstaller` | 官方安裝腳本的 SHA-256 與檢視過的版本不同時仍然執行（請先自己讀過新版） |

## 腳本做了什麼

| 步驟 | 內容 |
|---|---|
| 1 | 若 `%APPDATA%\hex\bin\hex.com` 不存在，下載官方 `install-windows.ps1`，核對它的 SHA-256 與檢視過的版本一致，強制使用 stable 頻道後執行（官方腳本只驗證檔案大小與 SHA-256） |
| 2 | 檢查 `hex.exe`／`hex.com` 的 Authenticode 簽章必須有效且簽署者為 Anomaly Innovations, Inc，否則不啟動 |
| 3 | `hex commands init` 建立 `~/.config/hex`，放入 OpenCC `s2tw`／`s2twp` 轉換器（4 個檔案逐一核對 SHA-256；原本就有的 `hex.config.ts` 會先備份） |
| 4 | 用 Hex 自己的 `hex settings apply` 一次寫入：「每次聽寫」加上 `s2twp`、`ui_language = zh-Hant`、避開注音衝突的快捷鍵。由 Hex 驗證、全有或全無，不手改 `settings.json`，也不必關閉 Hex |
| 5 | 驗證結果；任何一項不符就回傳非零結束碼 |

重複執行是安全的：已經是目標值的設定不會再寫入。

## 為什麼預設熱鍵是 Ctrl+Alt+Space

Hex 預設 `Ctrl+Space`，但那是 Windows 注音／新注音的**中英切換**，兩者會互撞。
`Ctrl+Alt+Space` 不衝突；想換成 `caps-lock` 或 `f5` 也可以：`-Hotkey caps-lock`。

## 轉換效果

| 模型輸出（簡體） | Hex 貼出（s2twp） |
|---|---|
| 这个软件里的内存和硬盘都很慢 | 這個**軟體**裡的**記憶體**和**硬碟**都很慢 |
| 数据库的网络连接断开了 | **資料庫**的**網路連線**斷開了 |
| 头发被台风吹乱了，一只狗跑过来 | **頭髮**被**颱風**吹亂了，**一隻**狗跑過來 |
| U盘里有资料 | **隨身碟**裡有資料 |

## 驗證方式

```powershell
hex commands check                        # 3 transformations
hex settings get ui_language              # zh-Hant

# 講一句話之後：
hex history --raw --limit 1               # raw_text 是簡體，final_text 應為繁體
```

⚠️ **不要用 Hex 的「試試」欄位驗證**：那個預覽只套用內建步驟，腳本轉換只在真的聽寫時執行。

## 選用：Breeze ASR 25 語音模型

[Breeze ASR 25](https://huggingface.co/MediaTek-Research/Breeze-ASR-25)（聯發科創新基地，Apache-2.0）是以 Whisper large-v2
微調的台灣華語模型，**直接輸出繁體**，中英夾雜的句子辨識較好。Hex 的模型清單裡沒有它，要用 `hex model import` 匯入：

```powershell
# 先跑過 install-windows.ps1，再從一般的 PowerShell 視窗執行
powershell -ExecutionPolicy Bypass -File .\install-breeze.ps1
```

腳本會從 [handy-computer/Breeze-ASR-25-gguf](https://huggingface.co/handy-computer/Breeze-ASR-25-gguf) 的固定版本下載
Q8_0 檔（1.67 GB，可續傳），核對大小與 SHA-256 後匯入並切換過去，最後刪掉下載檔。Hex 裡已經有這個模型時不會重新下載。

| 參數 | 說明 |
|---|---|
| `-Path <檔案>` | 用已經下載好的 GGUF，不再下載（一樣要通過 SHA-256 核對） |
| `-NoSelect` | 只匯入，不切換目前使用的模型 |
| `-KeepDownload` | 保留下載檔 |

要留意：

- 過程中需要約 3.5 GB 的可用空間（下載檔加上 Hex 自己的副本），完成後佔 1.7 GB。
- **Breeze 不會加標點符號**，Hex 也沒有自動標點的設定；需要標點時改用 Qwen3-ASR（`hex model use qwen3_asr06_b`）。
- `s2twp` 步驟可以留著：遇到繁體文字不會改動，換回輸出簡體的模型時仍然有效。
- 切換回去：`hex model use <模型 id>`（`hex model list` 可查）；移除：`hex model remove custom-1650c163cd1623d1`。

## 已知限制

- 轉換是**聽完之後**處理：即時字幕（Labs › Live text）的預覽仍是簡體，貼出的最終文字才是繁體。
- 「每次聽寫」是全域預設；你自建的**每個 App 模式要各自再加一次** `s2twp`。
- 依賴 OpenCC 的字典（Apache-2.0），字詞判斷以台灣用語為主；專有名詞建議加進 Hex 的 Vocabulary。
- 只有 Windows 安裝腳本。macOS／Linux 可手動照「手動步驟」做，路徑同為 `~/.config/hex`。

## 手動步驟（不想跑腳本）

```powershell
# 1. 安裝 Hex（官方；裝完可用 Get-AuthenticodeSignature 檢查 %APPDATA%\hex\bin\hex.com 的簽章）
powershell -ExecutionPolicy Bypass -Command "iwr https://anoma.ly/hex/install-windows.ps1 -OutFile i.ps1; ./i.ps1"

# 2. 建立轉換器工作區
hex commands init

# 3. 把 transformer/ 底下的 4 個 .ts 複製到 %USERPROFILE%\.config\hex
#    hex.config.ts, hex-s2tw.ts, hex-data-st.ts, hex-data-tw.ts
hex commands check

# 4. 在 Hex 視窗的 Output 窗格把「簡轉繁（台灣用語）」加進「每次聽寫」，
#    或把 hex settings get dictation_processing.default_mode 的 JSON 加上 "s2twp" 後
#    存成 {"dictation_processing.default_mode": {...}}，再執行 hex settings apply <檔案>
```

## 移除

```powershell
# 只移除繁中轉換
Remove-Item "$env:USERPROFILE\.config\hex\hex-s2tw.ts","$env:USERPROFILE\.config\hex\hex-data-st.ts","$env:USERPROFILE\.config\hex\hex-data-tw.ts"
# hex.config.ts 還在 import 上面刪掉的檔案，一併刪除後讓 Hex 重建預設的範本
Remove-Item "$env:USERPROFILE\.config\hex\hex.config.ts"
hex commands init
# 再到 Hex 的 Output 窗格把「簡轉繁（台灣用語）」從步驟移除

# 連 Hex 一起移除（用官方安裝腳本的反安裝）
iwr https://anoma.ly/hex/install-windows.ps1 -OutFile uninstall-hex.ps1
powershell -ExecutionPolicy Bypass -File .\uninstall-hex.ps1 -Uninstall
```

## 授權

本 repo 的腳本與說明為 Apache-2.0。轉換器與字典資料來自 OpenCC（Apache-2.0）與
[truelife2/opencode-hex3-transformer-s2tw](https://github.com/truelife2/opencode-hex3-transformer-s2tw)，
詳見 `NOTICE.md`。Hex 本身為 Anomaly 的 MIT 授權專案。
