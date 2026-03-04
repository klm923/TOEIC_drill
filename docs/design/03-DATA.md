# 03. データモデル・永続化・CSV・音声

## SwiftData モデル

### Phrase（フレーズ1件）

| プロパティ | 型 | 説明 |
|------------|-----|------|
| sourceFile | String | 音声ファイルのベース名（.mp3 なし） |
| level | String | 例: level_600, level_730 |
| index | Int | 連番 |
| word | String | 英単語 |
| jaTranslation | String | 日本語フレーズ |
| phrase | String | 英語フレーズ。[] で囲んだ部分がテスト対象 |
| correctCount | Int | 連続正解回数。正解で+1、不正解で0にリセット。負にはしない。 |
| memo | String | ユーザーメモ（改行可） |

### DailyStats（日別統計）

| プロパティ | 型 | 説明 |
|------------|-----|------|
| dayStart | Date | その日の開始（午前5時） |
| questionCount | Int | 出題数（正解+不正解のタップ数） |
| correctCount | Int | 正解タップ数 |

- **日の区切り**: `DayBoundary.currentDayStart()` で午前5時区切り。4:59 までが「前日」、5:00 からが「当日」。

---

## CSV 形式（エクスポート・インポート共通）

- **8列必須**: `source_file, level, index, word, ja_translation, phrase, correct_count, memo`
- **1行目**: ヘッダー。2行目以降がデータ。
- **改行の扱い**: エクスポート時にフィールド内の改行は `\n` にエスケープ、`\` は `\\`。インポート時に `\n` → 改行、`\r` → \r、`\\` → `\` で復元。
- **CSV のエスケープ**: カンマ・改行・ダブルクォートを含むフィールドは `"..."` で囲み、内部の `"` は `""`。
- **エクスポート**: index 昇順でソートしてから出力。

### 追加用CSVファイル（PhraseEditSheet の CSV ボタン）

`PhraseEditSheet` の「CSV」ボタンで取り込む CSV は、既存フレーズに**追加**する形式。8列はエクスポート形式と同じ。

| 項目名 | 内容 | 備考 |
|--------|------|------|
| source_file | 任意の英数及び記号（10文字以内） | 必須。超過分は切り詰め。.mp3 は除去 |
| level | 任意の英数及び記号（10文字以内） | 必須。超過分は切り詰め |
| index | 任意 | 無視。2001 以降の空き番号を自動採番 |
| word | 英単語 | 必須。空の行はスキップ |
| ja_translation | 日本語フレーズ | 必須。空の行はスキップ |
| phrase | 英語フレーズ | 必須。空の行はスキップ |
| correct_count | 任意 | 無視。常に 0 を設定 |
| memo | メモ | 任意 |

- **1行目**: ヘッダー。2行目以降がデータ。
- **改行・エスケープ**: エクスポート形式と同じ（`\n` エスケープ、`"..."` 囲み等）。

### 日別統計 CSV（エクスポート・インポート）

- **3列**: `day_start`, `question_count`, `correct_count`
- **1行目**: ヘッダー。2行目以降がデータ。
- **day_start**: ISO8601 形式（例: 2026-02-25T05:00:00.000+09:00）。午前5時区切りの「日」の開始日時。
- **インポート時**: 同一日（dayStart がカレンダー上同一分）の既存 DailyStats は上書き、存在しなければ新規作成。マージ方式。

初期データ: バンドル内 `csvs/TOEIC_phrases_initial.csv`（同じ8列形式）。フレーズ0件のときのみ `CSVImporter.importInitialFromBundle` で取り込む。

---

## 音声ファイル（mp3 再生時）

- **配置**: アプリバンドル内 `mp3s/[level]/`。例: `mp3s/level_730/TOEIC_kin_kaitei_10_001_parts2.mp3`
- **命名**: `[sourceFile]_[index%100 の3桁ゼロ埋め]_parts0 または parts2.mp3`
  - parts0: 英単語
  - parts2: 英語フレーズ（日本語 parts1 は使わない）
- ビルド時に Run Script で `TOEIC_drill/mp3s` をバンドルにコピーしている（要 project.pbxproj の Copy mp3s フェーズ）。

---

## 音声再生方式（AudioPlayback）

- **デフォルト**: TTS（`playbackMode == .tts`）。`useTTSByDefault == true`。
- **切り替え**: `playbackMode = .mp3` にするとバンドル内 mp3 を再生。定数 `useTTSByDefault` を false にすると起動時から mp3。
- TTS: 英単語は `phrase.word`、英語フレーズは `phrase.phrase` の `[xxx]` を中身に置換した文字列を読み上げ。音声は en-US（取得できる場合のみ設定、失敗時はデフォルト音声）。
