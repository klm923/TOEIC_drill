//
//  DailyStatsGraphView.swift
//  TOEIC_drill
//
//  日別統計の縦棒グラフ（Swift Charts、過去7日間、スワイプで期間スライド）
//

import SwiftUI
import SwiftData
import Charts

/// グラフ用の1日分の積み上げ要素（正解 or 不正解）
private struct DayBarSegment: Identifiable {
    let id: String
    let dayStart: Date
    /// X軸用の日付ラベル（M/d）。時間ではなく項目として表示する
    let dayLabel: String
    let kind: String  // "正解" or "不正解"（chartForegroundStyleScale 用）
    let count: Int
}

/// 日毎の出題数・正解数などを縦棒グラフで表示。一番右を本日として過去7日間。左右スワイプで表示期間をスライド。
struct DailyStatsGraphView: View {
    let stats: [DailyStats]
    @Environment(\.dismiss) private var dismiss

    private let calendar = Calendar.current
    /// 表示ウィンドウの右端を「今日」から何日前にするか。0 = 今日が右端
    @State private var slideOffset: Int = 0

    /// 表示する7日間の右端の dayStart（午前5時）
    private var rightmostDayStart: Date {
        let today = DayBoundary.currentDayStart(calendar: calendar)
        return calendar.date(byAdding: .day, value: -slideOffset, to: today) ?? today
    }

    /// 左から右へ 7 日分の dayStart
    private var displayedDayStarts: [Date] {
        (0..<7).compactMap { i in
            calendar.date(byAdding: .day, value: -6 + i, to: rightmostDayStart)
        }
    }

    /// 表示中の7日間の最大出題数
    private var maxQuestionInWindow: Int {
        displayedDayStarts.map { statsFor(dayStart: $0).questionCount }.max() ?? 0
    }

    /// 表示中の7日間の最大出題数（100単位で切り上げ）。縦軸用
    private var yAxisMax: Int {
        let maxQ = maxQuestionInWindow
        if maxQ == 0 { return 100 }
        return ((maxQ + 99) / 100) * 100
    }

    /// Swift Charts 用の積み上げデータ（各日の正解・不正解2件ずつ）。X軸は日付文字列（項目）として扱う
    private var chartSegments: [DayBarSegment] {
        displayedDayStarts.flatMap { dayStart in
            let (qCount, cCount) = statsFor(dayStart: dayStart)
            let incorrect = qCount - cCount
            let label = dateFormatter.string(from: dayStart)
            return [
                DayBarSegment(id: "\(dayStart.timeIntervalSince1970)-correct", dayStart: dayStart, dayLabel: label, kind: "正解", count: cCount),
                DayBarSegment(id: "\(dayStart.timeIntervalSince1970)-incorrect", dayStart: dayStart, dayLabel: label, kind: "不正解", count: incorrect)
            ]
        }
    }

    private func statsFor(dayStart: Date) -> (questionCount: Int, correctCount: Int) {
        guard let s = stats.first(where: { calendar.isDate($0.dayStart, equalTo: dayStart, toGranularity: .minute) }) else {
            return (0, 0)
        }
        return (s.questionCount, s.correctCount)
    }

    private func accuracyPercent(questionCount: Int, correctCount: Int) -> Int {
        guard questionCount > 0 else { return 0 }
        return Int(round(Double(correctCount) / Double(questionCount) * 100))
    }

    private static let barColorCorrect = Color(red: 0.4, green: 0.7, blue: 1.0)   // 水色
    private static let barColorIncorrect = Color(red: 1.0, green: 0.5, blue: 0.6)   // ピンク

    private var dateFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "M/d"
        f.locale = Locale(identifier: "ja_JP")
        return f
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if maxQuestionInWindow > 0 {
                    chartWithLabels
                } else {
                    Text("表示するデータがありません")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(30)
            .navigationTitle("日別統計グラフ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .gesture(
                DragGesture(minimumDistance: 30)
                    .onEnded { value in
                        let threshold: CGFloat = 50
                        if value.translation.width > threshold {
                            // 右スワイプで日付を遡る
                            slideOffset = min(slideOffset + 1, 365)
                        } else if value.translation.width < -threshold {
                            // 左スワイプで今日に近づく
                            slideOffset = max(0, slideOffset - 1)
                        }
                    }
            )
        }
    }

    /// 棒の上に出題数・正解率%、Chart、横軸日付
    private var chartWithLabels: some View {
        ZStack() {
            VStack(alignment: .center, spacing: 8) {
                Spacer()
                Chart(chartSegments) { segment in
                    BarMark(
                        x: .value("日", segment.dayLabel),
                        y: .value("数", segment.count),
                        width: .ratio(0.8)
                    )
                    .foregroundStyle(by: .value("種類", segment.kind))
                }
                .chartYScale(domain: 0...yAxisMax)
                .chartForegroundStyleScale([
                    "正解": Self.barColorCorrect,
                    "不正解": Self.barColorIncorrect
                ])
                .chartXAxis {
                    AxisMarks(values: displayedDayStarts.map { dateFormatter.string(from: $0) }) { value in
                        AxisValueLabel()
                        AxisGridLine()
                    }
                }
            }
            
            VStack(alignment: .center) {
                Spacer()
                HStack(spacing: 0) {
                    ForEach(displayedDayStarts, id: \.timeIntervalSince1970) { dayStart in
                        let (qCount, cCount) = statsFor(dayStart: dayStart)
                        let percent = accuracyPercent(questionCount: qCount, correctCount: cCount)
                        VStack(spacing: 2) {
                            Text("\(percent)%")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                            Text("\(qCount)")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    Spacer(minLength: 25)
                }
                .padding(.bottom, 40)
            }
        }
//        .frame(maxWidth: .infinity)
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: DailyStats.self, configurations: config)
    let context = ModelContext(container)
    let cal = Calendar.current
    var comps = cal.dateComponents([.year, .month, .day], from: Date())
    comps.hour = 5
    comps.minute = 0
    comps.second = 0
    guard let today5am = cal.date(from: comps) else {
        return DailyStatsGraphView(stats: [])
    }
    // 過去7日分のダミーデータ（出題数・正解数は適当な値）
    let dummyQuestionCounts = [12, 28, 45, 33, 52, 19, 38]
    let dummyCorrectCounts = [10, 22, 38, 28, 44, 15, 32]
    for (i, (q, c)) in zip(dummyQuestionCounts, dummyCorrectCounts).enumerated() {
        let dayStart = cal.date(byAdding: .day, value: -6 + i, to: today5am)!
        let s = DailyStats(dayStart: dayStart, questionCount: q, correctCount: c)
        context.insert(s)
    }
    try? context.save()
    let descriptor = FetchDescriptor<DailyStats>(sortBy: [SortDescriptor(\.dayStart, order: .reverse)])
    let stats = (try? context.fetch(descriptor)) ?? []
    return DailyStatsGraphView(stats: stats)
}
