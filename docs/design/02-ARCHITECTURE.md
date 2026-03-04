# 02. アーキテクチャ・画面構成

## 起動〜画面の流れ

```
TOEIC_drillApp (SwiftData ModelContainer)
  └─ AppRootView
        .task → importInitialIfNeeded()（フレーズ0件なら csvs/TOEIC_phrases_initial.csv をインポート）
        └─ ContentView
```

- **AppRootView**: ContentView を表示し、初回のみバンドル内初期 CSV をインポートする。
- **ContentView**: メイン画面（検索・カード・ステータスバー・DEBUG 時のインポート/エクスポート）。

## 主要ファイルと責務

| ファイル | 責務 |
|----------|------|
| `TOEIC_drillApp.swift` | エントリポイント。SwiftData の Schema([Phrase.self, DailyStats.self]) で ModelContainer を生成し、AppRootView に渡す。 |
| `AppRootView.swift` | ContentView の表示。フレーズが0件のときのみ `CSVImporter.importInitialFromBundle` を実行。 |
| `ContentView.swift` | メインUI。検索、フレーズカード（連番・レベル・英単語・英語フレーズ・日本語・正解表示・正解/不正解・メモ）、ステータスバー、スワイプ、長押しコピー・タップで編集シート。DEBUG 時はインポート/エクスポートボタン。 |
| `PhraseEditSheetView.swift` | フレーズ編集シート（英単語・日本語フレーズ・英語フレーズ・メモ）。「保存」で SwiftData に反映。 |
| `Phrase.swift` | SwiftData モデル Phrase（sourceFile, level, index, word, jaTranslation, phrase, correctCount, memo）。 |
| `DailyStats.swift` | SwiftData モデル DailyStats（dayStart, questionCount, correctCount）。DayBoundary で午前5時区切りの日を計算。 |
| `CSVImporter.swift` | CSV インポート（importInitialFromBundle, replaceWithCSV, importFrom）、パース（8列必須）、エクスポート用 buildExportCSV / CSVExportDocument、改行エスケープ・アンエスケープ。 |
| `AudioPlayback.swift` | 音声再生。PlaybackMode（.tts / .mp3）で切り替え。TTS は AVSpeechSynthesizer、mp3 はバンドル内 mp3s/[level]/ を参照。@MainActor, ObservableObject。 |

## ContentView の状態と分割

- **@Query** で phrases（correctCount 昇順）、allDailyStats を取得。
- **filteredPhrases**: 検索テキストでフィルタ。検索欄が空なら phrases と同値。
- **currentPhrase**: 表示中のフレーズ。**phraseHistory**: 左スワイプ用の履歴。**recentlyShownIds**: 直近10件の ID（抽出時に除外）。
- メインの View は `body` → `navigationContent` → `contentWithLayout` / `contentWithDialogs` に分割し、型チェックの負荷を分散している。
- メモ欄は「表示のみ」。タップで PhraseEditSheet を開く。編集はシート内で実施。

## 編集・インポート/エクスポートの入口

- **編集**: メモ欄の「タップで編集」またはメモ表示エリアのタップ → `showPhraseEditSheet = true` → PhraseEditSheetView(phrase: currentPhrase)。
- **長押し**: 英単語・英語フレーズ・日本語の各フィールドは長押しでクリップボードにコピー（英語フレーズは [] 除去）。触覚フィードバックあり。
- **CSV インポート**: DEBUG 時のみ表示される「インポート」ボタン → 確認ダイアログ → ファイル選択 → `CSVImporter.replaceWithCSV`。
- **CSV エクスポート**: DEBUG 時のみ「エクスポート」ボタン → fileExporter で保存先指定 → buildExportCSV（index 昇順）を CSVExportDocument で出力。
