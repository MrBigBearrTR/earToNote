import AVFoundation
import CoreMedia
import Foundation
import MeetingCore
import Speech

enum TranscriptionError: LocalizedError {
    case unsupportedLocale(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedLocale(let identifier):
            "Bu cihaz \(identifier) dilini cihaz üzerinde yazıya dökemiyor. Ayarlar'dan başka bir dil seçebilirsiniz."
        }
    }
}

enum SpeechModelStatus: Equatable {
    case installed
    case notInstalled
    case unsupported
}

/// The on-device speech module used for a language. `SpeechTranscriber` is built for long-form audio and
/// is preferred; `DictationTranscriber` covers languages it does not support, such as Turkish.
private enum Transcriber: Sendable {
    case speech(SpeechTranscriber)
    case dictation(DictationTranscriber)

    enum Engine {
        case speech
        case dictation
    }

    static func resolve(localeIdentifier: String) async -> (engine: Engine, locale: Locale)? {
        let requested = Locale(identifier: localeIdentifier)
        if let locale = await SpeechTranscriber.supportedLocale(equivalentTo: requested) {
            return (.speech, locale)
        }
        if let locale = await DictationTranscriber.supportedLocale(equivalentTo: requested) {
            return (.dictation, locale)
        }
        return nil
    }

    static func installedLocales(for engine: Engine) async -> [Locale] {
        switch engine {
        case .speech: await SpeechTranscriber.installedLocales
        case .dictation: await DictationTranscriber.installedLocales
        }
    }

    init(engine: Engine, locale: Locale) {
        switch engine {
        case .speech:
            self = .speech(SpeechTranscriber(
                locale: locale,
                transcriptionOptions: [],
                reportingOptions: [],
                attributeOptions: [.audioTimeRange]
            ))
        case .dictation:
            // Unlike SpeechTranscriber, dictation only punctuates on request; paragraphs are split at
            // sentence ends, so punctuation is required.
            self = .dictation(DictationTranscriber(
                locale: locale,
                contentHints: [.farField],
                transcriptionOptions: [.punctuation],
                reportingOptions: [],
                attributeOptions: [.audioTimeRange]
            ))
        }
    }

    var module: any SpeechModule {
        switch self {
        case .speech(let transcriber): transcriber
        case .dictation(let transcriber): transcriber
        }
    }
}

/// Transcribes recordings fully on device with Apple's SpeechAnalyzer (iOS 26).
/// The language model is a system asset: it is downloaded once and shared with other apps, so it
/// does not increase the app's size.
struct TranscriptionService {
    func modelStatus(localeIdentifier: String) async -> SpeechModelStatus {
        guard let resolved = await Transcriber.resolve(localeIdentifier: localeIdentifier) else {
            return .unsupported
        }
        let installed = await Transcriber.installedLocales(for: resolved.engine)
        let target = resolved.locale.identifier(.bcp47)
        return installed.contains { $0.identifier(.bcp47) == target } ? .installed : .notInstalled
    }

    /// Downloads the language model if needed. `progress` receives values in 0...1.
    func installModel(localeIdentifier: String, progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws {
        let transcriber = try await makeTranscriber(localeIdentifier: localeIdentifier)
        try await ensureAssets(for: transcriber, progress: progress)
    }

    /// Returns the recognized words with their position in the recording. `progress` receives values in 0...1.
    func transcribe(
        fileURL: URL,
        localeIdentifier: String,
        duration: TimeInterval,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> [TimedWord] {
        let transcriber = try await makeTranscriber(localeIdentifier: localeIdentifier)
        try await ensureAssets(for: transcriber)

        let analyzer = SpeechAnalyzer(modules: [transcriber.module])
        async let collected = collectWords(from: transcriber, duration: duration, progress: progress)

        let audioFile = try AVAudioFile(forReading: fileURL)
        if let lastSample = try await analyzer.analyzeSequence(from: audioFile) {
            try await analyzer.finalizeAndFinish(through: lastSample)
        } else {
            // The file contained no audio samples.
            await analyzer.cancelAndFinishNow()
        }

        let words = try await collected
        progress(1)
        return words
    }

    private func makeTranscriber(localeIdentifier: String) async throws -> Transcriber {
        guard let resolved = await Transcriber.resolve(localeIdentifier: localeIdentifier) else {
            throw TranscriptionError.unsupportedLocale(localeIdentifier)
        }
        return Transcriber(engine: resolved.engine, locale: resolved.locale)
    }

    private func ensureAssets(for transcriber: Transcriber, progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws {
        guard let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber.module]) else {
            progress(1)
            return
        }
        let observation = request.progress.observe(\.fractionCompleted, options: [.initial, .new]) { observed, _ in
            progress(observed.fractionCompleted)
        }
        defer { observation.invalidate() }
        try await request.downloadAndInstall()
        progress(1)
    }

    private func collectWords(
        from transcriber: Transcriber,
        duration: TimeInterval,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> [TimedWord] {
        switch transcriber {
        case .speech(let module):
            try await collectWords(from: module.results, text: \.text, duration: duration, progress: progress)
        case .dictation(let module):
            try await collectWords(from: module.results, text: \.text, duration: duration, progress: progress)
        }
    }

    private func collectWords<Results: AsyncSequence>(
        from results: Results,
        text: (Results.Element) -> AttributedString,
        duration: TimeInterval,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> [TimedWord] where Results.Element: SpeechModuleResult {
        var words: [TimedWord] = []
        for try await result in results where result.isFinal {
            words.append(contentsOf: Self.words(from: text(result), range: result.range))
            if duration > 0 {
                let reached = result.range.end.seconds
                if reached.isFinite {
                    progress(min(0.99, reached / duration))
                }
            }
        }
        return words
    }

    /// Splits a result into timed pieces using the per-run `audioTimeRange` attribute. Runs without
    /// timing (e.g. whitespace) are attached to the preceding piece.
    private static func words(from text: AttributedString, range: CMTimeRange) -> [TimedWord] {
        var words: [TimedWord] = []
        for run in text.runs {
            let piece = String(text[run.range].characters)
            if let timeRange = run.audioTimeRange, timeRange.start.seconds.isFinite, timeRange.end.seconds.isFinite {
                words.append(TimedWord(text: piece, start: timeRange.start.seconds, end: timeRange.end.seconds))
            } else if !words.isEmpty {
                words[words.count - 1].text += piece
            } else if !piece.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let start = range.start.seconds
                words.append(TimedWord(text: piece, start: start.isFinite ? start : 0, end: start.isFinite ? start : 0))
            }
        }

        if words.isEmpty {
            let plain = String(text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
            let start = range.start.seconds
            let end = range.end.seconds
            if !plain.isEmpty, start.isFinite, end.isFinite {
                words.append(TimedWord(text: plain, start: start, end: end))
            }
        }
        return words
    }
}
