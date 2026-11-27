# 交給 AI Agent 的安裝指令

把下面整段貼給能在目標電腦上執行終端機指令的 agent（例如 Hermes Agent、Codex、Claude Code），
它就能從零裝好 Hex、繁中轉換與適合這台電腦的語音模型。

```text
在這台 Windows 電腦上用一般的 PowerShell 執行下列步驟。
不要在 Claude 桌面程式的終端機裡跑：那是封裝（MSIX）程式，寫進 AppData 的檔案會被導到它的私人儲存區，
腳本偵測到會直接拒絕。若你在 WSL 裡，請透過 powershell.exe 在 Windows 端執行，不要在 Linux 端安裝。

1. git clone https://github.com/Tai-ShengYeh/hex-zh-hant
   cd hex-zh-hant
   （已經 clone 過就改成：cd hex-zh-hant ; git pull --ff-only）
2. powershell -ExecutionPolicy Bypass -File .\install-windows.ps1
3. powershell -ExecutionPolicy Bypass -File .\install-model.ps1 -WhatIf
   把輸出的硬體偵測結果與選擇回報給我。
4. powershell -ExecutionPolicy Bypass -File .\install-model.ps1
5. & "$env:APPDATA\hex\bin\hex.com" vocabulary add Hex
   & "$env:APPDATA\hex\bin\hex.com" vocabulary add Claude
6. 回報這幾個指令的輸出：
   & "$env:APPDATA\hex\bin\hex.com" status
   & "$env:APPDATA\hex\bin\hex.com" model status
   & "$env:APPDATA\hex\bin\hex.com" commands check

規則：
- 任何一步以非零結束碼結束就停下來，回報完整的錯誤訊息，不要自己改腳本或換別的做法。
- 若出現 "vendor installer changed since it was reviewed"，不要自己加 -AllowUnreviewedInstaller；
  先回報，等人看過 Anomaly 新版的安裝腳本再決定。
- 若出現 "does not match its pinned SHA-256"，不要略過核對；回報即可。
- 不要修改 Hex 的 settings.json；設定一律由腳本透過 hex settings apply 寫入。
```

## 需要人在電腦前做的事

- Hex 第一次啟動時，Windows 可能會詢問麥克風權限，要有人按允許。
- 按住 `Ctrl+Alt+Space` 講一句話測試。之後可以用
  `hex history --raw --limit 1` 確認：`raw_text` 是模型原始輸出，`final_text` 應為繁體。

## 預期結果

`install-model.ps1` 的自動選擇：

| 電腦 | 選擇 |
|---|---|
| 系統記憶體至少 12 GB，且有 Hex 能用、本身記憶體至少 3 GB 的顯示卡 | Qwen3-ASR 1.7B |
| 其他 | Qwen3-ASR 0.6B |

| 電腦 | 規格 | 預期選擇 | 狀態 |
|---|---|---|---|
| HP VICTUS 16 | RTX 3050 Ti 4 GB，16 GB 記憶體 | 1.7B | 已安裝、實測 |
| HP OmniBook 5 | Radeon 760M 內建顯示，12 GB（可用 11.1 GB） | 0.6B | 已安裝、實測 |
| 辦公室桌機 | RTX 5060 8 GB，16 GB 記憶體 | 1.7B | 尚未安裝 |

RTX 50 系列還沒實測過。若 `-WhatIf` 顯示這張卡「Hex cannot use it」，通常是顯示卡驅動程式太舊，
Hex 認不到 Vulkan 裝置；更新 NVIDIA 驅動程式後再跑一次 `-WhatIf`。
