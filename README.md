# TOEIC 単語ドリル

SwiftUI で作る **英単語（フレーズ）テスト** iOS アプリ。単語カード風の UI で、英単語・英語フレーズ・日本語を表示し、正解/不正解で学習進捗を管理します。

## 主な機能

- **フレーズカード表示**: 英単語・英語フレーズ・日本語をカード形式で表示
- **テストモード**: ランダムで「英単語テスト」または「日本語テスト」を出題（マスキング表示）
- **正解/不正解管理**: 連続正解回数に応じた出題優先度（苦手な単語を優先）
- **音声再生**: TTS（デフォルト）または mp3 による発音確認
- **日別統計**: 午前5時区切りの日単位で出題数・正答率を記録
- **統計グラフ**: 過去7日間の出題数・正解率を棒グラフで表示
- **CSV インポート/エクスポート**: フレーズデータ・日別統計のバックアップ・復元
- **新規フレーズ登録**: 手動追加または CSV 一括取り込み

## 技術スタック

| 項目 | 内容 |
|------|------|
| 言語 | Swift |
| UI | SwiftUI |
| 永続化 | SwiftData |
| ターゲット | iOS 17 以降 |
| 音声 | AVFoundation（TTS / mp3 切替可能） |

## 必要環境

- Xcode 15 以降
- iOS 17 以降

## セットアップ

1. リポジトリをクローン
   ```bash
   git clone https://github.com/YOUR_USERNAME/TOEIC_drill.git
   cd TOEIC_drill
   ```

2. Xcode で `TOEIC_drill.xcodeproj` を開く

3. シミュレータまたは実機を選択してビルド・実行

初回起動時、フレーズが 0 件の場合はバンドル内の `csvs/TOEIC_phrases_initial.csv` が自動インポートされます。

## 使い方

- **右スワイプ**: 次のフレーズへ
- **左スワイプ**: 前のフレーズへ
- **正解/不正解ボタン**: 学習進捗を記録（正解で連続正解回数 +1、不正解で 0 にリセット）
- **正解表示**: マスキングを解除
- **長押し**: 英単語・英語フレーズ・日本語をクリップボードにコピー
- **タップで編集**: フレーズの編集シートを表示

## データ形式

### フレーズ CSV（8列）

| 列名 | 説明 |
|------|------|
| source_file | 音声ファイルのベース名 |
| level | レベル（例: level_600, level_730） |
| index | 連番 |
| word | 英単語 |
| ja_translation | 日本語フレーズ |
| phrase | 英語フレーズ（`[xxx]` がテスト対象） |
| correct_count | 連続正解回数 |
| memo | メモ |

### 日別統計 CSV（3列）

| 列名 | 説明 |
|------|------|
| day_start | 日の開始（ISO8601、午前5時区切り） |
| question_count | 出題数 |
| correct_count | 正解数 |

## プロジェクト構成

```
TOEIC_drill/
├── TOEIC_drillApp.swift    # エントリポイント
├── AppRootView.swift       # 初回 CSV インポート
├── ContentView.swift       # メイン UI
├── PhraseEditSheetView.swift  # フレーズ編集
├── Phrase.swift            # フレーズモデル
├── DailyStats.swift        # 日別統計モデル
├── DailyStatsGraphView.swift # 統計グラフ
├── CSVImporter.swift       # CSV インポート/エクスポート
├── AudioPlayback.swift     # 音声再生
├── csvs/                   # 初期データ
└── mp3s/                   # 音声ファイル（オプション）
```

## 設計ドキュメント

詳細な仕様・設計は `docs/design/` を参照してください。

- [01-OVERVIEW.md](docs/design/01-OVERVIEW.md) - プロジェクト概要
- [02-ARCHITECTURE.md](docs/design/02-ARCHITECTURE.md) - アーキテクチャ・画面構成
- [03-DATA.md](docs/design/03-DATA.md) - データモデル・CSV 形式
- [04-FEATURES.md](docs/design/04-FEATURES.md) - 機能一覧と実装の要点

## ライセンス

MIT License
