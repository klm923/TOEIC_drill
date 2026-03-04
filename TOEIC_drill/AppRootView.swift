//
//  AppRootView.swift
//  TOEIC_drill
//
//  メイン画面（ContentView）を表示する。初回起動でフレーズが0件のときはバンドルの初期CSVを取り込む。
//
//  運用: Debug でインポートしたデータを Release でも使うには、アプリを削除せずに
//  Release ビルドで上書きインストールすればよい（同一 Bundle ID のため同じ SwiftData が参照される）。
//

import SwiftUI
import SwiftData

/// ContentView を表示する。初回起動時（フレーズ0件）はバンドル内 TOEIC_phrases_initial.csv を取り込む。
struct AppRootView: View {
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ContentView()
            .task {
                await importInitialIfNeeded()
            }
    }

    /// フレーズが0件のときのみ、バンドル内の初期CSV（csvs/TOEIC_phrases_initial.csv）を取り込む
    @MainActor
    private func importInitialIfNeeded() async {
        let descriptor = FetchDescriptor<Phrase>()
        let count = (try? modelContext.fetchCount(descriptor)) ?? 0
        guard count == 0 else { return }

        do {
            let imported = try CSVImporter.importInitialFromBundle(modelContext: modelContext)
            if imported > 0 {
                print("初回: フレーズ \(imported) 件を初期データからインポートしました")
            }
        } catch {
            print("初期CSVインポートエラー: \(error)")
        }
    }
}
