//
//  PhraseEditSheetView.swift
//  TOEIC_drill
//
//  データベース修正機能: 日本語フレーズ・英語フレーズを長押しで開く修正画面
//  新規フレーズ登録時は phrase == nil で表示し、保存時に新規 Phrase を insert する。
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// フレーズの編集または新規登録を行うシート。phrase が nil のときは新規登録モード。
struct PhraseEditSheetView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// 編集時は既存フレーズ、新規登録時は nil
    let phrase: Phrase?
    @Binding var isPresented: Bool
    /// 新規登録の保存成功時にメッセージを設定する（編集時は nil のまま）
    @Binding var saveResultMessage: String?

    @State private var editWord: String = ""
    @State private var editJaTranslation: String = ""
    @State private var editPhrase: String = ""
    @State private var editMemo: String = ""
    @State private var showValidationAlert = false
    @State private var showCSVFileImporter = false
    @State private var csvImportResultMessage: String?

    private var isNewPhrase: Bool { phrase == nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("英単語") {
                    TextField("英単語", text: $editWord)
                }
                Section("英語フレーズ") {
                    TextField("英語フレーズ（[]で囲んだ部分がテスト対象）", text: $editPhrase, axis: .vertical)
                        .lineLimit(3...6)
                }
                Section("日本語フレーズ") {
                    TextField("日本語フレーズ", text: $editJaTranslation, axis: .vertical)
                        .lineLimit(3...6)
                }
                Section("メモ") {
                    TextField("メモ（複数行可）", text: $editMemo, axis: .vertical)
                        .lineLimit(4...12)
                }
            }
            .navigationTitle(isNewPhrase ? "新規フレーズを登録" : "フレーズを修正")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        isPresented = false
                        dismiss()
                    }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button("CSV") {
                        showCSVFileImporter = true
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        saveAndDismiss()
                    }
                }
            }
            .fileImporter(
                isPresented: $showCSVFileImporter,
                allowedContentTypes: [.commaSeparatedText, .plainText],
                allowsMultipleSelection: false
            ) { result in
                handleCSVImport(result: result)
            }
            .onAppear {
                if let p = phrase {
                    editWord = p.word
                    editJaTranslation = p.jaTranslation
                    editPhrase = p.phrase
                    editMemo = p.memo
                }
            }
            .alert("入力してください", isPresented: $showValidationAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("英単語・日本語フレーズ・英語フレーズ・メモをすべて入力してください。")
            }
            .alert("CSV取り込み", isPresented: Binding(
                get: { csvImportResultMessage != nil },
                set: { if !$0 { csvImportResultMessage = nil } }
            )) {
                Button("OK", role: .cancel) { csvImportResultMessage = nil }
            } message: {
                if let msg = csvImportResultMessage {
                    Text(msg)
                }
            }
        }
    }

    /// ファイルピッカーで選んだ CSV を追加インポートし、結果メッセージを表示する
    private func handleCSVImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                csvImportResultMessage = "ファイルが選択されていません。"
                return
            }
            guard url.startAccessingSecurityScopedResource() else {
                csvImportResultMessage = "ファイルにアクセスできません。"
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            do {
                let count = try CSVImporter.importAppendFrom(url: url, modelContext: modelContext)
                csvImportResultMessage = count > 0 ? "\(count)件を登録しました。" : "登録できるデータがありませんでした。"
            } catch {
                csvImportResultMessage = "取り込みに失敗しました: \(error.localizedDescription)"
            }
        case .failure(let error):
            csvImportResultMessage = "ファイルを開けませんでした: \(error.localizedDescription)"
        }
    }

    /// 編集内容を保存してシートを閉じる。新規の場合は Phrase を insert し、保存結果メッセージを設定する。
    private func saveAndDismiss() {
        let word = editWord.trimmingCharacters(in: .whitespacesAndNewlines)
        let jaTranslation = editJaTranslation.trimmingCharacters(in: .whitespacesAndNewlines)
        let phraseText = editPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
        let memo = editMemo.trimmingCharacters(in: .whitespacesAndNewlines)

        if isNewPhrase {
            if word.isEmpty || jaTranslation.isEmpty || phraseText.isEmpty {
                showValidationAlert = true
                return
            }
            let nextIndex = nextAvailableIndexForNewPhrase()
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd"
            let sourceFile = formatter.string(from: Date())
            let newPhrase = Phrase(
                sourceFile: sourceFile,
                level: "level_999",
                index: nextIndex,
                word: word,
                jaTranslation: jaTranslation,
                phrase: phraseText,
                correctCount: 0,
                memo: memo
            )
            modelContext.insert(newPhrase)
            try? modelContext.save()
            saveResultMessage = "「\(word)」を登録しました。"
        } else if let p = phrase {
            p.word = word
            p.jaTranslation = jaTranslation
            p.phrase = phraseText
            p.memo = memo
            try? modelContext.save()
        }
        isPresented = false
        dismiss()
    }

    /// 新規フレーズ用の index: 2001 以降の空き番号（既存の index >= 2001 の最大値 + 1、なければ 2001）
    private func nextAvailableIndexForNewPhrase() -> Int {
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
}
