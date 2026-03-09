//
//  ContentView.swift
//  TOEIC_drill
//
//  Created by klm923 on 2026/02/19.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UIKit

// MARK: - プレビュー用テストモード（コード上で .englishWord / .japanese を切り替え可能）
private enum PreviewTestModeKey: EnvironmentKey {
    static let defaultValue: TestMode? = nil
}
private extension EnvironmentValues {
    var previewTestMode: TestMode? {
        get { self[PreviewTestModeKey.self] }
        set { self[PreviewTestModeKey.self] = newValue }
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.previewTestMode) private var previewTestMode
    /// 1. correctCount 昇順、2. 同値はランダム、3. 過去N問は除外（Nは設定で10〜50）
    @Query(sort: \Phrase.correctCount, order: .forward) private var phrases: [Phrase]
    @Query(sort: \DailyStats.dayStart, order: .reverse) private var allDailyStats: [DailyStats]

    @State private var searchText: String = ""
    @State private var showImportWarning = false
    @State private var showImportResult = false
    @State private var importResultMessage = ""
    /// インポート用（フレーズ・統計で1つの fileImporter を共有し、iOS で片方だけ有効になる問題を避ける）
    @State private var showImportSheet = false
    @State private var pendingImportKind: PendingImportKind = .none
    /// エクスポート用（フレーズ・統計で1つの fileExporter を共有し、iOS で片方だけ有効になる問題を避ける）
    @State private var showExportSheet = false
    @State private var exportSheetDocument: CSVExportDocument?
    @State private var exportSheetDefaultFilename = "TOEIC_phrases_export.csv"
    /// データベース修正シート（日本語・英語フレーズの編集）
    @State private var showPhraseEditSheet = false
    /// 新規フレーズ登録シート
    @State private var showNewPhraseSheet = false
    @State private var newPhraseResultMessage: String?
    @State private var showNewPhraseResultAlert = false
    /// 統計CSVインポート
    @State private var showStatsImportWarning = false
    @State private var showStatsImportResult = false
    @State private var statsImportResultMessage = ""
    /// 日別統計グラフシート
    @State private var showDailyStatsGraph = false
    /// 設定シート
    @State private var showSettingsSheet = false

    /// 現在表示中のフレーズ
    @State private var currentPhrase: Phrase?
    /// 左スワイプ（前へ）用の履歴
    @State private var phraseHistory: [Phrase] = []
    /// 過去N問のフレーズID（抽出時に除外する）。件数は設定で 10〜50
    @State private var recentlyShownIds: [PersistentIdentifier] = []
    @AppStorage("recentlyShownIdsMax") private var recentlyShownIdsMax: Int = 10
    @State private var isAnswerRevealed: Bool = false
    /// キーボード表示中は true（フレーズ Group を非表示にして検索フィールドを確保）
    @State private var isKeyboardVisible = false

    /// 現在のテストモード（フレーズ表示ごとにランダムで切り替え）
    @State private var currentTestMode: TestMode = .englishWord
    @StateObject private var audioPlayback = AudioPlayback()

    /// 今日の統計（午前5時区切り）。なければ nil
    private var todayStats: DailyStats? {
        let start = DayBoundary.currentDayStart()
        return allDailyStats.first { Calendar.current.isDate($0.dayStart, equalTo: start, toGranularity: .minute) }
    }

    /// 検索でフィルタ済みのフレーズ一覧
    private var filteredPhrases: [Phrase] {
        if searchText.isEmpty {
            return phrases
        }
        let lower = searchText.lowercased()
        return phrases.filter {
            $0.word.lowercased().contains(lower) ||
            $0.jaTranslation.contains(searchText) ||
            $0.phrase.lowercased().contains(lower) ||
            $0.memo.contains(lower) ||
            $0.level.contains(lower)
        }
    }

    /// 抽出規則: 1. correctCount昇順 2. 同値はランダム 3. 過去10問は除外して再抽出
    private func selectNextPhrase() -> Phrase? {
        let filtered = filteredPhrases
        guard !filtered.isEmpty else { return nil }

        // correctCount でグループ化し、昇順に
        let grouped = Dictionary(grouping: filtered, by: { $0.correctCount })
        let sortedCounts = grouped.keys.sorted()

        for count in sortedCounts {
            guard let phrasesInGroup = grouped[count] else { continue }
            // 過去N問を除外（Nは設定で10〜50）
            let candidates = phrasesInGroup.filter { phrase in
                !recentlyShownIds.contains(phrase.persistentModelID)
            }
            if let picked = candidates.randomElement() {
                return picked
            }
        }
        // 全件が過去N問に含まれる場合は、その中からランダム（フォールバック）
        return filtered.randomElement()
    }

    var body: some View {
        NavigationStack {
            navigationContent
        }
    }

    /// ナビゲーション内のメインコンテンツ（型チェック負荷を分散するため分離）
    private var navigationContent: some View {
        contentWithDialogs
    }

    /// レイアウト＋onChange/onAppear まで
    private var contentWithLayout: some View {
        mainStackContent
            .onChange(of: currentPhrase?.persistentModelID) { _, _ in
                isAnswerRevealed = false
                currentTestMode = Bool.random() ? .englishWord : .japanese
            }
            .onChange(of: recentlyShownIdsMax) { _, newMax in
                let max = max(10, min(50, newMax))
                if recentlyShownIds.count > max {
                    recentlyShownIds = Array(recentlyShownIds.suffix(max))
                }
            }
            .onChange(of: searchText) { _, _ in
                phraseHistory = []
                recentlyShownIds = []
                if let next = selectNextPhrase() {
                    currentPhrase = next
                    addToRecentlyShown(next)
                    currentTestMode = Bool.random() ? .englishWord : .japanese
                } else {
                    currentPhrase = nil
                }
                isAnswerRevealed = false
            }
            .onAppear {
                if currentPhrase == nil, !filteredPhrases.isEmpty {
                    if let next = selectNextPhrase() {
                        currentPhrase = next
                        addToRecentlyShown(next)
                        currentTestMode = Bool.random() ? .englishWord : .japanese
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                isKeyboardVisible = true
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                isKeyboardVisible = false
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemIndigo).opacity(0.1))
//            .ignoresSafeArea(.keyboard)
            .navigationTitle("TOEIC 金のフレーズ")
            .toolbarTitleDisplayMode(.inlineLarge)
    }

    /// ダイアログ・ファイルピッカー・シートを付与（型チェック負荷軽減のため Modifier に分割）
    @ViewBuilder
    private var contentWithDialogs: some View {
        contentWithLayout
            .modifier(PhraseImportExportModifier(
                showImportWarning: $showImportWarning,
                showImportResult: $showImportResult,
                importResultMessage: importResultMessage,
                onConfirmImport: { pendingImportKind = .phrase; showImportSheet = true }
            ))
            .modifier(StatsImportExportModifier(
                showStatsImportWarning: $showStatsImportWarning,
                showStatsImportResult: $showStatsImportResult,
                statsImportResultMessage: statsImportResultMessage,
                onConfirmImport: { pendingImportKind = .stats; showImportSheet = true }
            ))
            .fileImporter(
                isPresented: $showImportSheet,
                allowedContentTypes: [.commaSeparatedText, .plainText],
                allowsMultipleSelection: false
            ) { result in
                Task { @MainActor in
                    switch pendingImportKind {
                    case .phrase: handleFileImport(result: result)
                    case .stats: handleStatsFileImport(result: result)
                    case .none: break
                    }
                    showImportSheet = false
                    pendingImportKind = .none
                }
            }
            .fileExporter(
                isPresented: $showExportSheet,
                document: exportSheetDocument ?? CSVExportDocument(csvString: ""),
                contentType: .commaSeparatedText,
                defaultFilename: exportSheetDefaultFilename
            ) { _ in
                showExportSheet = false
                exportSheetDocument = nil
            }
            .sheet(isPresented: $showPhraseEditSheet) {
                phraseEditSheetContent
            }
            .sheet(isPresented: $showNewPhraseSheet, onDismiss: {
                if newPhraseResultMessage != nil {
                    showNewPhraseResultAlert = true
                }
            }) {
                PhraseEditSheetView(
                    phrase: nil,
                    isPresented: $showNewPhraseSheet,
                    saveResultMessage: $newPhraseResultMessage
                )
            }
            .sheet(isPresented: $showDailyStatsGraph) {
                DailyStatsGraphView(stats: allDailyStats)
            }
            .sheet(isPresented: $showSettingsSheet) {
                SettingsView(isPresented: $showSettingsSheet)
            }
            .alert("登録しました", isPresented: $showNewPhraseResultAlert) {
                Button("OK", role: .cancel) {
                    newPhraseResultMessage = nil
                }
            } message: {
                Text(newPhraseResultMessage ?? "")
            }
    }

    @ViewBuilder
    private var phraseEditSheetContent: some View {
        if let phrase = currentPhrase {
            PhraseEditSheetView(
                phrase: phrase,
                isPresented: $showPhraseEditSheet,
                saveResultMessage: .constant(nil)
            )
        }
    }

    private var mainStackContent: some View {
        VStack(spacing: 10) {
            flashcardContent
            searchField
            statusBar
        }
    }

    /// フレーズDBをCSVでエクスポート（共有の fileExporter で表示）
    private func startExport() {
        exportSheetDocument = CSVExportDocument(csvString: buildExportCSV(phrases: phrases))
        exportSheetDefaultFilename = "TOEIC_phrases_export.csv"
        showExportSheet = true
    }

    /// 日別統計をCSVでエクスポート（ステータスバーの「統計エクスポート」から。共有の fileExporter で表示）
    private func startStatsExport() {
        exportSheetDocument = CSVExportDocument(csvString: buildStatsExportCSV(stats: allDailyStats))
        exportSheetDefaultFilename = "TOEIC_daily_stats_export.csv"
        showExportSheet = true
    }

    /// 統計CSVのファイル選択結果を処理し、マージインポートを実行
    private func handleStatsFileImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else {
                statsImportResultMessage = "ファイルへのアクセスができませんでした。"
                showStatsImportResult = true
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            do {
                let count = try importStatsFromCSV(url: url, modelContext: modelContext)
                statsImportResultMessage = "\(count) 件の日別統計をマージしました。"
            } catch {
                statsImportResultMessage = "インポートエラー: \(error.localizedDescription)"
            }
            showStatsImportResult = true
        case .failure(let error):
            statsImportResultMessage = "ファイル選択エラー: \(error.localizedDescription)"
            showStatsImportResult = true
        }
    }

    /// ファイル選択結果を処理し、総入れ替えインポートを実行
    private func handleFileImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            // セキュリティスコープ付きURLの場合はアクセス開始
            guard url.startAccessingSecurityScopedResource() else {
                importResultMessage = "ファイルへのアクセスができませんでした。"
                showImportResult = true
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            do {
                let count = try CSVImporter.replaceWithCSV(url: url, modelContext: modelContext)
                importResultMessage = "\(count) 件をインポートしました。"
            } catch {
                importResultMessage = "インポートエラー: \(error.localizedDescription)"
            }
            showImportResult = true
        case .failure(let error):
            importResultMessage = "ファイル選択エラー: \(error.localizedDescription)"
            showImportResult = true
        }
    }

    // MARK: - ステータスバー（日単位・出題数・正答率％、午前5時で日リセット）
    private var statusBar: some View {
        HStack(spacing: 16) {
            Text("出題数: \(todayStats?.questionCount ?? 0)")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
            Text("正答率: \(todayStats?.accuracyPercent ?? 0)%")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
            Spacer()
            HStack(spacing: 4) {
                Button(action: { showDailyStatsGraph = true }) {
                    Image(systemName: "chart.bar")
                        .font(.system(size: 16))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("グラフ")
                Button(action: startStatsExport) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("統計エクスポート")
                Button(action: { showStatsImportWarning = true }) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 16))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("統計インポート")
                Button(action: { showSettingsSheet = true }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 16))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("設定")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - 検索フィールド
    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
            TextField("単語・フレーズ・レベルで抽出", text: $searchText)
                .font(.system(size: 18))
                .textFieldStyle(.plain)
        }
        .padding(10)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - 単語カード風メインコンテンツ
    private var flashcardContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 連番・英単語レベル（左寄せ）と登録単語数（右寄せ）
            HStack {
                HStack(spacing: 8) {
                    Text("No.\(currentPhrase?.index ?? 0, format: .number.grouping(.never))") // ３桁区切りの「,」は表示しない
                        .font(.system(size: 16))
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    Text(currentPhrase?.level ?? "")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("登録数: \(filteredPhrases.count, format: .number.grouping(.never))") // ３桁区切りの「,」は表示しない
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                Button(action: { showNewPhraseSheet = true }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22))
                }
                .buttonStyle(.borderless)
//                #if DEBUG
                HStack(spacing: 4) {
                    Button(action: startExport) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 16))
                    }
                    .buttonStyle(.borderless)
                    Button(action: { showImportWarning = true }) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 16))
                    }
                    .buttonStyle(.borderless)
                }
//                #endif
            }

            Divider()

            if !isKeyboardVisible {
                Group {
                    if let phrase = currentPhrase {
                        // 英単語 → 英語フレーズ → 日本語の順、日本語は再生ボタンなし（取り込まない）
                        phraseRow(label: "英単語", text: displayWord(phrase.word), showPlayButton: true, onTapBackground: nil) {
                            audioPlayback.play(phrase: phrase, kind: .word)
                        }
                        .onLongPressGesture {
                            UIPasteboard.general.string = phrase.word
                            let generator = UIImpactFeedbackGenerator(style: .medium)
                            generator.impactOccurred()
                        }
                        phraseRow(label: "英語フレーズ", text: displayPhrase(phrase.phrase), showPlayButton: true, onTapBackground: nil) {
                            audioPlayback.play(phrase: phrase, kind: .phrase)
                        }
                        .onLongPressGesture {
                            UIPasteboard.general.string = phraseTextForClipboard(phrase.phrase)
                            let generator = UIImpactFeedbackGenerator(style: .medium)
                            generator.impactOccurred()
                        }
                        phraseRow(label: "日本語", text: displayJapanese(phrase.jaTranslation), showPlayButton: false, onTapBackground: nil, onPlay: nil)
                        .onLongPressGesture {
                            UIPasteboard.general.string = phrase.jaTranslation
                            let generator = UIImpactFeedbackGenerator(style: .medium)
                            generator.impactOccurred()
                        }
                    } else {
                        Text("フレーズがありません")
                            .font(.system(size: 17))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                }
            }

            Divider()

            HStack(spacing: 12) {
                Button(action: {
                    var t = Transaction()
                    t.animation = nil
                    withTransaction(t) { isAnswerRevealed.toggle() }
                }) {
                    Image(systemName: isAnswerRevealed ? "eye.slash" : "eye")
                        .font(.system(size: 24))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderedProminent)

                Spacer()

                Button(action: { markIncorrect() }) {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 24))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.bordered)
                .tint(.red)

                Button(action: { markCorrect() }) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 24))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.bordered)
                .tint(.green)

                Text("連続正解: \(currentPhrase?.correctCount ?? 0)")
                    .font(.system(size: 17))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)

            Divider()

            // メモ: 表示のみ。タップで PhraseEditSheet を開きメモ・フレーズを編集（キーボード被りを避ける）
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("メモ")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("タップで編集")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                ScrollView {
                    Group {
                        if isAnswerRevealed {
                            Text(currentPhrase?.memo ?? "")
                                .font(.system(size: 12))
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                                .lineLimit(nil)
                        } else {
                            Text("？？？")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: .infinity)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
                .onTapGesture {
                    showPhraseEditSheet = true
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 50)
                .onEnded { value in
                    // 右スワイプで次へ、左スワイプで前へ
                    if value.translation.width > 0 {
                        goToPrevious()
                    } else {
                        goToNext()
                    }
                }
        )
    }

    // MARK: - フレーズ移動
    /// 過去N問に追加（最大件数は設定で 10〜50）
    private func addToRecentlyShown(_ phrase: Phrase) {
        let max = max(10, min(50, recentlyShownIdsMax))
        recentlyShownIds.append(phrase.persistentModelID)
        if recentlyShownIds.count > max {
            recentlyShownIds.removeFirst()
        }
    }

    private func goToNext() {
        guard let current = currentPhrase else { return }
        guard let next = selectNextPhrase() else { return }
        phraseHistory.append(current)
        addToRecentlyShown(next)
        currentPhrase = next
    }

    private func goToPrevious() {
        if let prev = phraseHistory.popLast() {
            currentPhrase = prev
        }
    }

    // MARK: - 正解・不正解
    /// 正解ボタンタップ時: 触覚フィードバック（振動1回）
    private func markCorrect() {
        guard let phrase = currentPhrase else { return }
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.impactOccurred()
        phrase.correctCount = phrase.correctCount + 1
        recordDailyAnswer(correct: true)
        try? modelContext.save()
    }

    /// 不正解ボタンタップ時: 触覚フィードバック（振動2回）、連続正解回数は 0 にリセット
    private func markIncorrect() {
        guard let phrase = currentPhrase else { return }
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            generator.impactOccurred()
        }
        phrase.correctCount = 0
        recordDailyAnswer(correct: false)
        try? modelContext.save()
    }

    /// 日単位の出題数・正解数を更新（午前5時区切りで当日分に加算）
    private func recordDailyAnswer(correct: Bool) {
        let dayStart = DayBoundary.currentDayStart()
        let stats: DailyStats
        if let existing = allDailyStats.first(where: { Calendar.current.isDate($0.dayStart, equalTo: dayStart, toGranularity: .minute) }) {
            stats = existing
        } else {
            stats = DailyStats(dayStart: dayStart)
            modelContext.insert(stats)
        }
        stats.questionCount += 1
        if correct { stats.correctCount += 1 }
    }

    // MARK: - テストモード別の表示（英単語モード / 日本語モードをランダムに実行）
    /// プレビュー時は Environment の previewTestMode を優先、通常時は currentTestMode
    private var effectiveTestMode: TestMode {
        previewTestMode ?? currentTestMode
    }

    /// 英単語: 英単語モード時はマスキング、日本語モード時はそのまま
    private func displayWord(_ word: String) -> String {
        switch effectiveTestMode {
        case .englishWord: return isAnswerRevealed ? word : replaceUnderscore(word) //"________"
        case .japanese: return word
        }
    }

    /// 日本語フレーズ: 日本語モード時は "？？？" に置換、英単語モード時はそのまま
    private func displayJapanese(_ jaTranslation: String) -> String {
        switch effectiveTestMode {
        case .englishWord: return jaTranslation
        case .japanese: return isAnswerRevealed ? jaTranslation : "？？？"
        }
    }

    /// 英語フレーズ: 英単語モード時は[]内をマスキング、日本語モード時は[]除去して表示
    private func displayPhrase(_ phrase: String) -> String {
        switch effectiveTestMode {
        case .englishWord:
            let pattern = "([^\\]]*)\\[([^\\]]*)\\]([^\\]]*)"
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return phrase }
            let nsRange = NSRange(phrase.startIndex..., in: phrase)
            let words = regex.matches(in: phrase, range: nsRange)
            if words.count != 1 { return phrase }
            let words1 = phrase[Range(words[0].range(at: 1), in: phrase)!]
            let words2 = phrase[Range(words[0].range(at: 2), in: phrase)!]
            let words3 = phrase[Range(words[0].range(at: 3), in: phrase)!]
            return isAnswerRevealed ? String(words1 + String(words2) + String(words3)) : String(words1 + replaceUnderscore(String(words2)) + String(words3))
//            let template = isAnswerRevealed ? "$1" : "________"
//            return regex.stringByReplacingMatches(in: phrase, range: nsRange, withTemplate: template)
        case .japanese:
            let pattern = "\\[([^\\]]*)\\]"
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return phrase }
            let nsRange = NSRange(phrase.startIndex..., in: phrase)
            return regex.stringByReplacingMatches(in: phrase, range: nsRange, withTemplate: "$1")
        }
    }
    
    /// 英単語を「_」に変換（各単語の文字数＋1本のアンダースコア）
    private func replaceUnderscore(_ words: String) -> String {
        words
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .map { String(repeating: "_", count: min($0.count + 1, 8)) }
            .joined(separator: " ")
    }

    // MARK: - フレーズ行（ラベル + テキスト + 音声再生ボタン（英単語・英語フレーズのみ）+ 行下スペース）
    private func phraseRow(label: String, text: String, showPlayButton: Bool = true, onTapBackground: (() -> Void)? = nil, onPlay: (() -> Void)? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(size: 17))
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .contentShape(Rectangle())
                .onTapGesture { onTapBackground?() }
            if showPlayButton, let onPlay = onPlay {
                Button(action: onPlay) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 22))
                }
//                .buttonStyle(.bordered)
            }
            Spacer().frame(height: 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    /// 英語フレーズの [] を除去してクリップボード用の文字列にする（例: "The [word] here" → "The word here"）
    private func phraseTextForClipboard(_ phrase: String) -> String {
        let pattern = "\\[([^\\]]*)\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return phrase }
        let nsRange = NSRange(phrase.startIndex..., in: phrase)
        return regex.stringByReplacingMatches(in: phrase, range: nsRange, withTemplate: "$1")
    }

}

// MARK: - フレーズ CSV インポート用 Modifier（fileImporter は ContentView で1つに統一）
private struct PhraseImportExportModifier: ViewModifier {
    @Binding var showImportWarning: Bool
    @Binding var showImportResult: Bool
    let importResultMessage: String
    let onConfirmImport: () -> Void

    func body(content: Content) -> some View {
        content
            .alert("CSVインポート", isPresented: $showImportWarning) {
                Button("キャンセル", role: .cancel) { }
                Button("インポート", role: .destructive) {
                    onConfirmImport()
                }
            } message: {
                Text("既存の登録単語及び登録したメモはすべて初期化されます。")
            }
            .alert("CSVインポート", isPresented: $showImportResult) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(importResultMessage)
            }
    }
}

// MARK: - 統計 CSV インポート用 Modifier（fileImporter は ContentView で1つに統一）
private struct StatsImportExportModifier: ViewModifier {
    @Binding var showStatsImportWarning: Bool
    @Binding var showStatsImportResult: Bool
    let statsImportResultMessage: String
    let onConfirmImport: () -> Void

    func body(content: Content) -> some View {
        content
            .alert("統計CSVインポート", isPresented: $showStatsImportWarning) {
                Button("キャンセル", role: .cancel) { }
                Button("インポート", role: .destructive) {
                    onConfirmImport()
                }
            } message: {
                Text("選択したCSVの日別データで、同一日の統計がマージ（上書き）されます。")
            }
            .alert("統計インポート", isPresented: $showStatsImportResult) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(statsImportResultMessage)
            }
    }
}

/// 共有 fileImporter でどのインポートを実行するか
private enum PendingImportKind {
    case none
    case phrase
    case stats
}

/// テストモード: 英単語テスト or 日本語テスト
private enum TestMode {
    case englishWord  // 英単語・英語フレーズの[]内をマスキング
    case japanese      // 日本語フレーズを "？？？" でマスキング
}

#Preview {
    // プレビュー用: モードを切り替える場合は .englishWord または .japanese に変更
    let previewTestMode: TestMode = .englishWord

    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Phrase.self, DailyStats.self, configurations: config)
    let context = ModelContext(container)
    let samplePhrase = Phrase(
        sourceFile: "preview",
        level: "level_600",
        index: 1,
        word: "sample simple",
        jaTranslation: "サンプル",
        phrase: "This is a [sample simple] phrase.",
        correctCount: 0,
        memo: "プレビュー用メモ"
    )
    context.insert(samplePhrase)
    try? context.save()

    return ContentView()
        .modelContainer(container)
        .environment(\.previewTestMode, previewTestMode)
}

