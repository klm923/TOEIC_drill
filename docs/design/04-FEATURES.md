# 04. 機能一覧と実装の要点

## フレーズの表示・抽出

- **表示データ**: SwiftData の Phrase。`@Query(sort: \Phrase.correctCount, order: .forward)` で取得し、`filteredPhrases` で検索テキストによるフィルタを適用。
- **「登録単語数」表示**: `filteredPhrases.count`。検索時は抽出された件数を表示。
- **次のフレーズの選び方（selectNextPhrase）**:
  1. correctCount の昇順でグループ化。
  2. 同値内はランダム。
  3. 直近10問（recentlyShownIds）に含まれる ID は除外。
  4. 候補が残らなければ、全件からランダムで1件（フォールバック）。
- **検索フィルタと recentlyShownIds**:
  - フィルタ適用時（searchText が空→非空）: `recentlyShownIdsBackup` に現在の recentlyShownIds を退避し、recentlyShownIds をリセット。
  - フィルタ解除時（searchText が非空→空）: 退避していた recentlyShownIds を復元。復元後、recentlyShownIdsMax を超える分は末尾でトリム。
  - 検索語の変更のみ（A→B）: 退避は更新せず、recentlyShownIds のみリセット。

## テストモード・マスキング

- **テストモード**: フレーズ表示ごとにランダムで「英単語テスト」または「日本語テスト」を選択（currentTestMode）。
- **英単語テスト**: 英単語を `________`、英語フレーズの `[xxx]` を `________`（[] は除去して表示）。日本語はそのまま。
- **日本語テスト**: 日本語フレーズを `？？？`。英単語・英語フレーズはそのまま（[] は除去して表示）。
- **正解表示**: 正解表示ボタンで isAnswerRevealed をトグルし、マスキングを解除。メモも非表示時は `？？？`。

## 正解・不正解・触覚

- **正解**: correctCount += 1。触覚フィードバック 1回（UIImpactFeedbackGenerator .light）。
- **不正解**: correctCount = 0 にリセット。触覚フィードバック 2回（.medium、0.12秒間隔）。
- いずれも `recordDailyAnswer(correct:)` で DailyStats を更新（午前5時区切りの日で questionCount / correctCount を加算）。

## スワイプ・履歴

- **右スワイプ**: 次のフレーズへ。現在を phraseHistory に積み、selectNextPhrase で次を表示。
- **左スワイプ**: phraseHistory から1件 pop して前のフレーズを表示。

## メモ・編集

- **メモ表示**: カード内は表示のみ。正解表示時は currentPhrase?.memo、非表示時は `？？？`。メモ欄は .frame(maxHeight: .infinity) で可変高さ、はみ出しは ScrollView でスクロール。
- **編集**: メモエリアまたは「タップで編集」で PhraseEditSheet を表示。シート内で英単語・日本語フレーズ・英語フレーズ・メモを編集し「保存」で modelContext.save()。

## 長押しでクリップボードコピー

- 英単語行: 長押しで `phrase.word` をコピー。
- 英語フレーズ行: 長押しで `phraseTextForClipboard(phrase.phrase)` をコピー（[] を除去した文字列）。
- 日本語行: 長押しで `phrase.jaTranslation` をコピー。
- いずれも UIPasteboard.general.string に代入し、UIImpactFeedbackGenerator(.medium) で触覚フィードバック。

## ステータスバー

- 表示: 「出題数: N」「正答率: M%」。todayStats（DayBoundary.currentDayStart() と一致する DailyStats）から取得。なければ 0 / 0%。
- 更新: 正解/不正解ボタンで recordDailyAnswer が呼ばれ、その日の questionCount と correctCount を更新。

## CSV インポート・エクスポート（フレーズデータ）

- **インポート**: ~~DEBUG 時のみ~~「新規フレーズ登録」横に配置の「フレーズエクスポート」ボタンから。確認ダイアログ後、fileImporter で CSV を選択し `CSVImporter.replaceWithCSV`（全削除のうえ importFrom）。8列形式のみ対応。セキュリティスコープ付き URL は startAccessingSecurityScopedResource を利用。
- **エクスポート**: ~~DEBUG 時のみ~~「フレーズエクスポート」ボタン横に配置の「フレーズインポート」ボタンから。buildExportCSV（index 昇順）で CSV 文字列を生成し、CSVExportDocument を fileExporter で保存。defaultFilename: TOEIC_phrases_export.csv。

## CSV インポート・エクスポート（日々の統計データ）

- **エクスポート**: ステータスバーに配置の「統計エクスポート」ボタン（↑アイコン）から。`buildStatsExportCSV(stats:)` で全 DailyStats を day_start 昇順の CSV にし、`CSVExportDocument` を fileExporter で保存。defaultFilename: TOEIC_daily_stats_export.csv。形式は3列: day_start（ISO8601）, question_count, correct_count。
- **インポート**: ステータスバーに配置の「統計インポート」ボタン（↓アイコン）から。確認ダイアログ後、fileImporter で CSV を選択し `importStatsFromCSV` でマージ（同一日は上書き）。セキュリティスコープ付き URL は startAccessingSecurityScopedResource を利用。


## 音声再生

- ContentView で `@StateObject private var audioPlayback = AudioPlayback()`。英単語・英語フレーズ行の再生ボタンで `audioPlayback.play(phrase:kind:)`（.word / .phrase）。
- AudioPlayback は playbackMode に応じて TTS または mp3 を再生。TTS 時は英語フレーズの [] を除去した文を読み上げ。

## レイアウト・その他

- カード内は `.frame(maxHeight: .infinity, alignment: .top)` で上寄せ。メモ欄の高さ可変によりレイアウトがずれないようにしている。
- isAnswerRevealed のトグルは `withTransaction(Transaction(animation: nil))` でアニメーションなしにし、表示切り替え時のレイアウトの揺れを抑えている。
- 正解表示ボタン・不正解・正解ボタンのアイコンは .frame(width: 24, height: 24) でサイズを固定。

## 新規フレーズ登録機能

- **トリガー**: 「登録単語数」の右に「＋」ボタンを配置。タップにより、`PhraseEditSheet` を表示して、新規単語を登録。
- **登録項目**:

  | 項目名 | 内容 | 備考 |
  |------------|------|-------|
  | sourceFile | 固定値: YYYYMMDD | 自動（登録日（西暦８桁）） |
  | level | 固定値: "level_999" | 自動 |
  | index | 連番: 2001 以降の空き番号  | 自動 |
  | word | `PhraseEditSheet` で「英単語」に入力した値 | 必須 |
  | jaTranslation | `PhraseEditSheet` で「日本語フレーズ」に入力した値 | 必須 |
  | phrase | `PhraseEditSheet` で「英語フレーズ」に入力した値 | 必須 |
  | correctCount | 固定値: 0 | 自動 |
  | memo | `PhraseEditSheet` で「メモ」に入力した値 | 任意 |

- **確認メッセージの表示**: 「保存」ボタンタップ後に、登録結果についてメッセージを表示。
- **CSVファイル取り込み機能**: `PhraseEditSheet` の「保存」ボタンの左に「CSV」ボタンを配置し、CSVファイルから新規フレーズを登録。
- **CSVファイルのレイアウト**: 

  | 項目名 | 内容 | 備考 |
  |------------|------|-------|
  | sourceFile | 任意の英数及び記号（10文字以内） | 必須 |
  | level | 任意の英数及び記号（10文字以内） | 必須 |
  | index | どのような値が入っていても 2001 以降の空き番号を自動採番 | 自動
  | word | 任意の「英単語」 | 必須 |
  | jaTranslation | 任意の「日本語フレーズ」 | 必須 |
  | phrase | 任意の「英語フレーズ」 | 必須 |
  | correctCount | どのような値が入っていても固定値「0」を設定 | 自動 |
  | memo | 任意の「メモ」 | 任意 |

## `DailyStats` のグラフ化

- **トリガー**: `statusBar` の「統計エクスポート」ボタンの左側に「グラフ」ボタンを配置。タップにより、`DailyStatsGraph`（新規作成）を表示する。
- **DailyStatsGraph**: 日毎の「出題数」等をグラフ化して表示する。
- **グラフの形式**: 縦の棒グラフ。下から「正解タップ数 `correctCount` 」を水色, 「不正解タップ数 `questionCount - correctCount` 」をピンク色, その上に「出題数」, 「正解率(%)」を数字で表示する。
- **グラフの縦軸**: グラフ表示期間内の「最大出題数」を「100単位」で切り上げた数字をグラフの最大値とする。
- **グラフの横軸**: 一番右を本日として、「過去7日間」を遡って表示。左右にスワイプすることで、表示期間をスライドさせることができる。

## 設定画面

- **トリガー**: `statusBar` の一番右（「統計インポート」ボタン（↓アイコン））の右の「設定（歯車）」ボタンのタップで表示
- **設定項目**:
  1. 過去履歴の保持件数（`recentlyShownIds`）: 10 ~ 50 の範囲で設定
  2. アプリ情報: アプリ名, バージョン情報
