//
//  CSVImporter.swift
//  TOEIC_drill
//
//  CSV からフレーズデータをインポートするユーティリティ／エクスポート用 FileDocument
//

import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// CSV ファイルからフレーズデータを SwiftData にインポートする（エクスポート形式の8列CSVのみ対応）
enum CSVImporter {

    /// 初回起動用: バンドル内の csvs/TOEIC_phrases_initial.csv をインポート（データが0件のときのみ利用想定）
    /// ファイルが存在しない場合は 0 を返す。例外は投げない。
    @MainActor
    static func importInitialFromBundle(modelContext: ModelContext) throws -> Int {
        guard let url = Bundle.main.url(forResource: "TOEIC_phrases_initial", withExtension: "csv", subdirectory: "csvs")
            ?? Bundle.main.url(forResource: "TOEIC_phrases_initial", withExtension: "csv") else {
            return 0
        }
        return try importFrom(url: url, modelContext: modelContext)
    }

    /// 既存の全フレーズを削除してから指定 URL の CSV で総入れ替え
    /// エクスポート形式（8列: source_file, level, index, word, ja_translation, phrase, correct_count, memo）のみ取り込む
    @MainActor
    static func replaceWithCSV(url: URL, modelContext: ModelContext) throws -> Int {
        let descriptor = FetchDescriptor<Phrase>()
        let existing = try modelContext.fetch(descriptor)
        for phrase in existing {
            modelContext.delete(phrase)
        }
        try modelContext.save()
        return try importFrom(url: url, modelContext: modelContext)
    }

    /// CSV から新規フレーズを追加インポート（index は 2001 以降の空き番号を自動採番、correctCount は 0）
    /// 要件: sourceFile/level は10文字以内に切り詰め、word/jaTranslation/phrase が空の行はスキップ
    @MainActor
    static func importAppendFrom(url: URL, modelContext: ModelContext) throws -> Int {
        let content = try String(contentsOf: url, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)
        guard !lines.isEmpty else { return 0 }

        var nextIndex = nextAvailableAppendIndex(modelContext: modelContext)
        var count = 0
        for line in lines.dropFirst() {
            guard !line.isEmpty else { continue }
            guard let parsed = parseCSVLineForAppend(line) else { continue }
            let phrase = Phrase(
                sourceFile: parsed.sourceFile,
                level: parsed.level,
                index: nextIndex,
                word: parsed.word,
                jaTranslation: parsed.jaTranslation,
                phrase: parsed.phrase,
                correctCount: 0,
                memo: parsed.memo
            )
            modelContext.insert(phrase)
            nextIndex += 1
            count += 1
        }
        if count > 0 {
            try modelContext.save()
        }
        return count
    }

    /// 追加インポート用: index >= 2001 の最大値 + 1（なければ 2001）
    @MainActor
    private static func nextAvailableAppendIndex(modelContext: ModelContext) -> Int {
        var descriptor = FetchDescriptor<Phrase>(
            predicate: #Predicate<Phrase> { $0.index >= 2001 },
            sortBy: [SortDescriptor(\.index, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        guard let list = try? modelContext.fetch(descriptor),
              let first = list.first else {
            return 2001
        }
        return first.index + 1
    }

    /// 追加インポート用: 1行をパース。sourceFile/level は10文字に切り詰め。word/jaTranslation/phrase が空なら nil
    private static func parseCSVLineForAppend(_ line: String) -> (sourceFile: String, level: String, word: String, jaTranslation: String, phrase: String, memo: String)? {
        let columns = parseCSVColumns(line)
        guard columns.count >= 8 else { return nil }
        let word = unescapeCSVField(columns[3]).trimmingCharacters(in: .whitespacesAndNewlines)
        let jaTranslation = unescapeCSVField(columns[4]).trimmingCharacters(in: .whitespacesAndNewlines)
        let phraseText = unescapeCSVField(columns[5]).trimmingCharacters(in: .whitespacesAndNewlines)
        if word.isEmpty || jaTranslation.isEmpty || phraseText.isEmpty { return nil }

        var sourceFile = unescapeCSVField(columns[0])
        if sourceFile.hasSuffix(".mp3") { sourceFile = String(sourceFile.dropLast(4)) }
        sourceFile = String(sourceFile.prefix(10))
        var level = unescapeCSVField(columns[1])
        level = String(level.prefix(10))
        let memo = unescapeCSVField(columns[7])

        return (sourceFile: sourceFile, level: level, word: word, jaTranslation: jaTranslation, phrase: phraseText, memo: memo)
    }

    /// 指定 URL の CSV をインポート
    @MainActor
    static func importFrom(url: URL, modelContext: ModelContext) throws -> Int {
        let content = try String(contentsOf: url, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)
        guard !lines.isEmpty else { return 0 }

        var count = 0
        // 1行目はヘッダー
        for line in lines.dropFirst() {
            guard !line.isEmpty else { continue }
            guard let phrase = parseCSVLine(line) else { continue }
            modelContext.insert(phrase)
            count += 1
        }
        try modelContext.save()
        return count
    }

    /// CSV 1行をパースして Phrase を生成
    /// エクスポート形式（8列）のみ: source_file, level, index, word, ja_translation, phrase, correct_count, memo
    /// エクスポート時にエスケープした改行（\n）等はデコードして復元する
    private static func parseCSVLine(_ line: String) -> Phrase? {
        let columns = parseCSVColumns(line)
        guard columns.count >= 8 else { return nil }
        guard let index = Int(columns[2]) else { return nil }

        // source_file から .mp3 を除去してベース名として保存
        var sourceFile = unescapeCSVField(columns[0])
        if sourceFile.hasSuffix(".mp3") {
            sourceFile = String(sourceFile.dropLast(4))
        }

        let correctCount = Int(columns[6]) ?? 0
        let memo = unescapeCSVField(columns[7])

        return Phrase(
            sourceFile: sourceFile,
            level: unescapeCSVField(columns[1]),
            index: index,
            word: unescapeCSVField(columns[3]),
            jaTranslation: unescapeCSVField(columns[4]),
            phrase: unescapeCSVField(columns[5]),
            correctCount: correctCount,
            memo: memo
        )
    }

    /// ダブルクォートで囲まれたカンマを考慮して CSV カラムを分割
    private static func parseCSVColumns(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false

        for char in line {
            switch char {
            case "\"":
                inQuotes.toggle()
            case ",":
                if inQuotes {
                    current.append(char)
                } else {
                    result.append(current)
                    current = ""
                }
            default:
                current.append(char)
            }
        }
        result.append(current)
        return result
    }
}

enum CSVImportError: Error {
    case fileNotFound
}

// MARK: - フレーズデータベースのエクスポート（メンテナンス用）

/// エクスポート用 CSV を保持する FileDocument（出力場所指定で fileExporter に渡す）
struct CSVExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText, .plainText] }
    static var writableContentTypes: [UTType] { [.commaSeparatedText, .plainText] }

    var csvString: String

    init(csvString: String = "") {
        self.csvString = csvString
    }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents {
            csvString = String(decoding: data, as: UTF8.self)
        } else {
            csvString = ""
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = Data(csvString.utf8)
        return FileWrapper(regularFileWithContents: data)
    }
}

/// フレーズ一覧からエクスポート用 CSV 文字列を生成（ヘッダー付き・再インポート用）
func buildExportCSV(phrases: [Phrase]) -> String {
    let header = "source_file,level,index,word,ja_translation,phrase,correct_count,memo"
    let sorted = phrases.sorted { $0.index < $1.index }
    let rows = sorted.map { phrase in
        [
            escapeCSVField(phrase.sourceFile),
            escapeCSVField(phrase.level),
            String(phrase.index),
            escapeCSVField(phrase.word),
            escapeCSVField(phrase.jaTranslation),
            escapeCSVField(phrase.phrase),
            String(phrase.correctCount),
            escapeCSVField(phrase.memo),
        ].joined(separator: ",")
    }
    return ([header] + rows).joined(separator: "\n")
}

/// CSV の1フィールドをエスケープ（改行を \n に、バックスラッシュを \\ に。カンマ・ダブルクォート含む場合は "" で囲む）
private func escapeCSVField(_ value: String) -> String {
    let backslashEscaped = value.replacingOccurrences(of: "\\", with: "\\\\")
    let newlineEscaped = backslashEscaped
        .replacingOccurrences(of: "\r", with: "\\r")
        .replacingOccurrences(of: "\n", with: "\\n")
    if newlineEscaped.contains(",") || newlineEscaped.contains("\"") {
        return "\"" + newlineEscaped.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
    return newlineEscaped
}

/// エクスポート時にエスケープした改行・バックスラッシュを復元（\\n → 改行, \\r → \r, \\ → \）
private func unescapeCSVField(_ value: String) -> String {
    value
        .replacingOccurrences(of: "\\n", with: "\n")
        .replacingOccurrences(of: "\\r", with: "\r")
        .replacingOccurrences(of: "\\\\", with: "\\")
}

// MARK: - 日々の統計データ（DailyStats）の CSV エクスポート・インポート

private let statsCSVHeader = "day_start,question_count,correct_count"

/// 日付フォーマッター（ISO8601）。dayStart のシリアライズ用
private var statsDateFormatter: ISO8601DateFormatter {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}

/// DailyStats 一覧からエクスポート用 CSV 文字列を生成（day_start 昇順）
func buildStatsExportCSV(stats: [DailyStats]) -> String {
    let sorted = stats.sorted { $0.dayStart < $1.dayStart }
    let formatter = statsDateFormatter
    let rows = sorted.map { s in
        [
            formatter.string(from: s.dayStart),
            String(s.questionCount),
            String(s.correctCount),
        ].joined(separator: ",")
    }
    return ([statsCSVHeader] + rows).joined(separator: "\n")
}

/// 統計 CSV を読み込み、既存の DailyStats とマージ（同一 dayStart は上書き）して返した件数を返す
@MainActor
func importStatsFromCSV(url: URL, modelContext: ModelContext) throws -> Int {
    let content = try String(contentsOf: url, encoding: .utf8)
    let lines = content.components(separatedBy: .newlines)
    guard !lines.isEmpty else { return 0 }

    let formatter = statsDateFormatter
    let descriptor = FetchDescriptor<DailyStats>()
    let existing = try modelContext.fetch(descriptor)
    let calendar = Calendar.current
    var processedInThisImport: [DailyStats] = []
    var count = 0

    for line in lines.dropFirst() {
        guard !line.isEmpty else { continue }
        let cols = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        guard cols.count >= 3,
              let dayStart = formatter.date(from: cols[0].trimmingCharacters(in: .whitespaces)),
              let questionCount = Int(cols[1].trimmingCharacters(in: .whitespaces)),
              let correctCount = Int(cols[2].trimmingCharacters(in: .whitespaces)) else { continue }

        let stats: DailyStats
        if let match = existing.first(where: { calendar.isDate($0.dayStart, equalTo: dayStart, toGranularity: .minute) }) {
            stats = match
        } else if let match = processedInThisImport.first(where: { calendar.isDate($0.dayStart, equalTo: dayStart, toGranularity: .minute) }) {
            stats = match
        } else {
            stats = DailyStats(dayStart: dayStart)
            modelContext.insert(stats)
            processedInThisImport.append(stats)
        }
        stats.questionCount = questionCount
        stats.correctCount = correctCount
        count += 1
    }
    try modelContext.save()
    return count
}
