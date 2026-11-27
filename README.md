# 我的筆記

自用、無廣告的筆記 app，一套 Flutter 程式碼同時支援 Android 手機和 Windows 電腦，透過自己的 Google Drive 同步。

## 里程碑

1. **基本筆記**：文字筆記（粗體、底線、刪除線、螢光、清單）、待辦清單、資料夾（可巢狀）、顏色、置頂、封存、垃圾桶（保留 30 天）、搜尋、深色模式 ← 目前
2. 匯入 Keep My Notes 的 `.kmnb` 備份
3. 手寫筆記
4. 指紋 / Windows Hello 解鎖、提醒通知
5. Google Drive 同步
6. 打包 Android APK 和 Windows 安裝檔

## 下載測試版

每次推上 GitHub，Actions 會自動建置：到 repo 的 **Actions** 分頁，點最新一次的 build，在頁面最下方的 Artifacts 下載

- `android-apk`：解壓後把 `app-release.apk` 傳到手機安裝
- `windows-app`：解壓後執行 `my_notes.exe`

## 開發

```
flutter pub get
flutter test
flutter run -d windows   # 或接上手機 flutter run
```

資料存在本機 SQLite（`lib/data/database.dart`）。每筆資料都有 `updated_at`，永久刪除會留下 tombstone，之後同步靠這兩樣合併兩台裝置的變更。

備份檔（`*.kmnb`）是私人資料，已列在 `.gitignore`，不要提交。
