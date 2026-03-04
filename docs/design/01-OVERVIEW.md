# 01. プロジェクト概要

## 目的

SwiftUI で**英単語（フレーズ）のテスト**を行う **iOS アプリ**。単語カード風のUIで、英単語・英語フレーズ・日本語を表示し、正解/不正解で学習進捗を管理する。

## 技術スタック

| 項目 | 内容 |
|------|------|
| 言語 | Swift |
| UI | SwiftUI |
| 永続化 | SwiftData（Schema: Phrase, DailyStats） |
| ターゲット | iOS 17 以降 |
| 音声 | AVFoundation（TTS デフォルト / mp3 切替可能） |

## 制約・方針

- コード内に**日本語コメント**を入れ、初心者にも分かりやすくする。
- 画面・ロジックは `ContentView` を中心に構成。型チェック負荷対策のため、長い View は `navigationContent` / `contentWithLayout` / `contentWithDialogs` などに分割している。

## 関連ドキュメント

- 要件・タスク一覧: プロジェクトルート `docs/markdown.md`
- データ構造・CSV形式: [03-DATA.md](03-DATA.md)
- 機能の実装要点: [04-FEATURES.md](04-FEATURES.md)
