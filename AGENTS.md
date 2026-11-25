# MonitorGlow 協作規則

- 繁體中文，技術名詞保留原文。Swift + SwiftPM，只用 Command Line Tools，不需要 Xcode。
- 協定依據：`docs/PROTOCOL.md`（靜態分析＋實機驗證）。openLightsSync 是 CC BY-NC-SA 4.0，只參考協定事實，**不抄程式碼**。
- **指令白名單**：只能送 `LampCommand` 列出的指令。韌體升級、bootloader、寫 flash／UUID 一律不加。未知指令不試送。
- 對燈條送指令前，先請使用者結束官方 SyncLight，避免兩支程式搶同一個 HID 裝置。
- 沒有實機驗證過的協定行為，註解標「待驗證」。
- 送燈的顏色一律經過 `RGB.powerLimited`（USB 供電保護），不要繞過。
- 看面板畫面：`MONITORGLOW_SNAPSHOT=<資料夾>` 執行 debug 版，會輸出各模式 PNG。
- 圖示：原稿 `Resources/icon-source.png`（gpt-image 生成，2026-11-25 使用者選 C；候選在 `docs/icon-candidates/`），`scripts/make-icon.sh` 裁成 Apple 圖示網格並產生 `Resources/AppIcon.icns`。
