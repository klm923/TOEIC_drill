//
//  SettingsView.swift
//  TOEIC_drill
//
//  Created by klm923 on 2026/03/10.
//

import SwiftUI

/// 設定画面: 過去履歴保持件数（10〜50）、アプリ情報
struct SettingsView: View {
    @Binding var isPresented: Bool
    @AppStorage("recentlyShownIdsMax") private var recentlyShownIdsMax: Int = 10

    private let minCount = 10
    private let maxCount = 50

    private var appName: String {
        Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "TOEIC_drill"
    }
    private var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(
                        value: $recentlyShownIdsMax,
                        in: minCount...maxCount,
                        step: 1
                    ) {
                        HStack {
                            Text("過去履歴の保持件数")
                            Spacer()
                            Text("\(recentlyShownIdsMax) 件")
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text("出題時に除外する過去のフレーズ数（10〜50）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("抽出設定")
                }

                Section {
                    LabeledContent("アプリ名", value: appName)
                    LabeledContent("バージョン", value: appVersion)
                } header: {
                    Text("アプリ情報")
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") {
                        isPresented = false
                    }
                }
            }
        }
    }
}

#Preview {
    SettingsView(isPresented: .constant(true))
}
