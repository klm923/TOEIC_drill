//
//  AudioPlayback.swift
//  TOEIC_drill
//
//  英単語・英語フレーズの音声再生（mp3 または iOS TTS を切り替え可能）
//

import AVFoundation
import Combine
import SwiftUI

/// 再生方式の切り替え（ここを変更するだけで mp3 / TTS を切り替え可能）
private let useTTSByDefault = true

/// 英単語（parts0）または英語フレーズ（parts2）の再生
@MainActor
final class AudioPlayback: ObservableObject {
    /// 再生方式: .tts = iOS の Text-to-Speech / .mp3 = バンドル内 mp3 ファイル
    enum PlaybackMode {
        case tts
        case mp3
    }

    /// 現在の再生方式（useTTSByDefault で初期値が決まる。コード上で .mp3 に戻すと mp3 再生になる）
    var playbackMode: PlaybackMode = useTTSByDefault ? .tts : .mp3

    @Published private(set) var isPlaying = false
    private var player: AVAudioPlayer?
    private var synthesizer: AVSpeechSynthesizer?
    private var ttsDelegate: TTSDelegate?
    private var didConfigureSession = false

    /// 英単語または英語フレーズを再生（playbackMode に応じて TTS または mp3）
    func play(phrase: Phrase, kind: AudioKind) {
        configureAudioSessionIfNeeded()
        stop()

        switch playbackMode {
        case .tts:
            playWithTTS(phrase: phrase, kind: kind)
        case .mp3:
            playWithMP3(phrase: phrase, kind: kind)
        }
    }

    // MARK: - TTS 再生（英単語・英語フレーズを iOS の読み上げで再生）
    private func playWithTTS(phrase: Phrase, kind: AudioKind) {
        let text: String
        switch kind {
        case .word:
            text = phrase.word
        case .phrase:
            text = phraseTextForTTS(phrase.phrase)
        }
        guard !text.isEmpty else { return }

        let utterance = AVSpeechUtterance(string: text)
        // 英語再生のため en-US を指定。取得に失敗する環境ではデフォルト音声にフォールバック
        if let enVoice = AVSpeechSynthesisVoice(language: "en-US") {
            utterance.voice = enVoice
        }
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate

        let delegate = TTSDelegate(onFinish: { [weak self] in
            Task { @MainActor in
                self?.isPlaying = false
            }
        })
        ttsDelegate = delegate
        let syn = AVSpeechSynthesizer()
        syn.delegate = delegate
        synthesizer = syn
        syn.speak(utterance)
        isPlaying = true
    }

    /// 英語フレーズの [] を除去して TTS 用の読み上げ文にする（例: "The [word] here" → "The word here"）
    private func phraseTextForTTS(_ phrase: String) -> String {
        let pattern = "\\[([^\\]]*)\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return phrase }
        let nsRange = NSRange(phrase.startIndex..., in: phrase)
        return regex.stringByReplacingMatches(in: phrase, range: nsRange, withTemplate: "$1")
    }

    // MARK: - MP3 再生（従来のバンドル内 mp3 ファイル再生・コード上で playbackMode = .mp3 にすれば利用可能）
    private func playWithMP3(phrase: Phrase, kind: AudioKind) {
        guard let url = urlFor(phrase: phrase, kind: kind) else {
            let suffix = String(format: "%03d", phrase.index % 100)
            let part = kind == .word ? "parts0" : "parts2"
            print("音声ファイルが見つかりません: \(phrase.sourceFile)_\(suffix)_\(part).mp3 (level: \(phrase.level))")
            return
        }
        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.prepareToPlay()
            player?.play()
            isPlaying = true
        } catch {
            print("音声再生エラー: \(error)")
        }
    }

    /// 再生用にオーディオセッションを設定（初回のみ）
    private func configureAudioSessionIfNeeded() {
        guard !didConfigureSession else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            didConfigureSession = true
        } catch {
            print("AVAudioSession 設定エラー: \(error)")
        }
    }

    func stop() {
        synthesizer?.stopSpeaking(at: .immediate)
        synthesizer = nil
        ttsDelegate = nil
        player?.stop()
        player = nil
        isPlaying = false
    }

    /// 英単語: parts0 / 英語フレーズ: parts2（日本語 parts1 は取り込まない）
    enum AudioKind {
        case word   // parts0
        case phrase // parts2
    }

    /// mp3s/[level]/[sourceFile]_[index%100 3桁]_parts0 or parts2.mp3（MP3 再生時のみ使用）
    private func urlFor(phrase: Phrase, kind: AudioKind) -> URL? {
        let part: String
        switch kind {
        case .word: part = "parts0"
        case .phrase: part = "parts2"
        }
        let suffix = String(format: "%03d", phrase.index % 100)
        let fileName = "\(phrase.sourceFile)_\(suffix)_\(part).mp3"

        if let url = Bundle.main.url(forResource: phrase.sourceFile + "_" + suffix + "_" + part, withExtension: "mp3", subdirectory: "mp3s/\(phrase.level)") {
            return url
        }
        for base in [Bundle.main.bundleURL, Bundle.main.resourceURL].compactMap({ $0 }) {
            let url = base
                .appending(path: "mp3s")
                .appending(path: phrase.level)
                .appending(path: fileName)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }
}

/// AVSpeechSynthesizer の完了通知を MainActor で受け取るためのデリゲート
private final class TTSDelegate: NSObject, AVSpeechSynthesizerDelegate {
    let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        onFinish()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        onFinish()
    }
}
