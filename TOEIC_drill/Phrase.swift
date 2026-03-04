//
//  Phrase.swift
//  TOEIC_drill
//
//  フレーズデータベース（SwiftData モデル）
//

import Foundation
import SwiftData

/// フレーズデータを格納する SwiftData モデル
@Model
final class Phrase {
    /// 音声ファイルのベース名（.mp3 は含めない）
    var sourceFile: String

    /// 英単語のレベル（例: level_600）
    var level: String

    /// 連番
    var index: Int

    /// 英単語
    var word: String

    /// 日本語フレーズ
    var jaTranslation: String

    /// 英語フレーズ（[]で囲まれた部分がテスト対象）
    var phrase: String

    /// 連続正解回数（正解で+1、不正解で-1、最小0）
    var correctCount: Int

    /// ユーザーメモ
    var memo: String

    init(
        sourceFile: String,
        level: String,
        index: Int,
        word: String,
        jaTranslation: String,
        phrase: String,
        correctCount: Int = 0,
        memo: String = ""
    ) {
        self.sourceFile = sourceFile
        self.level = level
        self.index = index
        self.word = word
        self.jaTranslation = jaTranslation
        self.phrase = phrase
        self.correctCount = correctCount
        self.memo = memo
    }
}
