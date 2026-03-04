//
//  DailyStats.swift
//  TOEIC_drill
//
//  日単位の出題数・正答率（午前5時で日が切り替わる）
//

import Foundation
import SwiftData

/// 日単位の出題統計（午前5時区切りで1日）
@Model
final class DailyStats {
    /// その日の開始日時（午前5時）
    var dayStart: Date

    /// 出題数（正解＋不正解のタップ数）
    var questionCount: Int

    /// 正解ボタンをタップした数
    var correctCount: Int

    init(dayStart: Date, questionCount: Int = 0, correctCount: Int = 0) {
        self.dayStart = dayStart
        self.questionCount = questionCount
        self.correctCount = correctCount
    }

    /// 正答率（％）。出題数0のときは0
    var accuracyPercent: Int {
        guard questionCount > 0 else { return 0 }
        return Int(round(Double(correctCount) / Double(questionCount) * 100))
    }
}

// MARK: - 午前5時区切りの「日」判定
enum DayBoundary {
    /// 現在の「日」の開始日時（午前5時）を返す。4:59までは前日5時、5:00からは当日5時。
    static func currentDayStart(calendar: Calendar = .current) -> Date {
        let now = Date()
        var comps = calendar.dateComponents([.year, .month, .day], from: now)
        comps.hour = 5
        comps.minute = 0
        comps.second = 0
        guard let today5am = calendar.date(from: comps) else { return now }
        if now < today5am {
            return calendar.date(byAdding: .day, value: -1, to: today5am) ?? today5am
        }
        return today5am
    }
}
