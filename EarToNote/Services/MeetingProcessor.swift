import AVFoundation
import Foundation
import MeetingCore
import Observation
import SwiftData
import UIKit

enum ProcessingError: LocalizedError {
    case missingAudio

    var errorDescription: String? {
        switch self {
        case .missingAudio:
            "Bu toplantının ses dosyası bulunamadı."
        }
    }
}

enum ProcessingStage: Equatable {
    case preparing
    case separatingSpeakers
    case transcribing
    case identifyingSpeakers

    var title: String {
        switch self {
        case .preparing: "Hazırlanıyor"
        case .separatingSpeakers: "Konuşmacılar ayrıştırılıyor"
        case .transcribing: "Yazıya dökülüyor"
        case .identifyingSpeakers: "Konuşmacılar tanınıyor"
        }
    }
}

struct ProcessingProgress: Equatable {
    var stage: ProcessingStage
    var transcription: Double = 0
    var diarization: Double = 0

    var fraction: Double {
        switch stage {
        case .preparing: 0.02
        case .separatingSpeakers: 0.05 + 0.3 * min(diarization, 1)
        case .transcribing: 0.35 + 0.6 * min(transcription, 1)
        case .identifyingSpeakers: 0.97
        }
    }
}

/// Turns a finished recording into a speaker-attributed transcript: diarization finds who spoke when,
/// every speaker turn is transcribed, and every voice is matched against the people saved on the device.
@MainActor
@Observable
final class MeetingProcessor {
    private static let unknownSpeakerKey = "?"

    private(set) var progress: [UUID: ProcessingProgress] = [:]

    @ObservationIgnored private var tasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var didRecover = false
    @ObservationIgnored private let transcriptionService = TranscriptionService()
    @ObservationIgnored private let background = BackgroundProcessingCoordinator()
    @ObservationIgnored private let aligner = TranscriptAligner()

    func isProcessing(_ meetingID: UUID) -> Bool {
        tasks[meetingID] != nil
    }

    /// Starts (or restarts) processing. A previous transcript of the meeting is replaced once the new one
    /// is ready; until then, and if processing is cancelled, it is kept.
    func process(_ meeting: Meeting, in context: ModelContext) {
        let meetingID = meeting.id
        guard tasks[meetingID] == nil else { return }

        meeting.status = .processing
        meeting.errorMessage = nil
        try? context.save()

        progress[meetingID] = ProcessingProgress(stage: .preparing)
        background.begin(jobID: meetingID, title: meeting.title, subtitle: ProcessingStage.preparing.title) { [weak self] in
            self?.cancel(meetingID)
        }
        tasks[meetingID] = Task { [weak self] in
            await self?.run(meetingID: meetingID, context: context)
        }
        updateIdleTimer()
    }

    func cancel(_ meetingID: UUID) {
        tasks[meetingID]?.cancel()
    }

    /// Meetings left in "recording" or "processing" by a previous launch (the app was terminated) are
    /// marked as failed so the user can retry them.
    func recoverInterruptedMeetings(in context: ModelContext) {
        guard !didRecover else { return }
        didRecover = true
        let meetings = (try? context.fetch(FetchDescriptor<Meeting>())) ?? []
        for meeting in meetings where tasks[meeting.id] == nil {
            switch meeting.status {
            case .recording:
                meeting.status = .failed
                meeting.errorMessage = "Kayıt beklenmedik şekilde sonlandı. Kaydedilebilen kısmı işlemeyi deneyebilirsiniz."
            case .processing where !meeting.segments.isEmpty:
                // Re-processing was interrupted; the previous transcript is still intact.
                meeting.status = .ready
            case .processing:
                meeting.status = .failed
                meeting.errorMessage = "İşlem yarıda kaldı. Tekrar deneyebilirsiniz."
            case .ready, .failed:
                break
            }
        }
        try? context.save()
    }

    private func run(meetingID: UUID, context: ModelContext) async {
        var succeeded = false
        do {
            guard let meeting = fetchMeeting(meetingID, in: context) else { throw CancellationError() }
            let audioURL = meeting.audioURL
            let localeIdentifier = meeting.localeIdentifier
            guard FileManager.default.fileExists(atPath: audioURL.path) else { throw ProcessingError.missingAudio }
            if meeting.duration <= 0 {
                meeting.duration = Self.fileDuration(of: audioURL)
            }
            let duration = meeting.duration
            let speakerCount = meeting.expectedSpeakerCount
            let transcriptionService = self.transcriptionService

            setStage(.separatingSpeakers, for: meetingID)
            // The language model is downloaded on first use; that can happen while speakers are separated.
            async let languageModel: Void = transcriptionService.installModel(localeIdentifier: localeIdentifier)
            let diarization = try await DiarizationService.shared.diarize(
                fileURL: audioURL,
                speakerCount: speakerCount
            ) { [weak self] value in
                Task { @MainActor in
                    self?.report(diarization: value, for: meetingID)
                }
            }
            try await languageModel
            try Task.checkCancellation()

            setStage(.transcribing, for: meetingID)
            let transcription = try await transcriptionService.transcribe(
                fileURL: audioURL,
                localeIdentifier: localeIdentifier,
                duration: duration,
                turns: diarization.turns
            ) { [weak self] value in
                Task { @MainActor in
                    self?.report(transcription: value, for: meetingID)
                }
            }
            try Task.checkCancellation()

            guard let current = fetchMeeting(meetingID, in: context) else { throw CancellationError() }
            setStage(.identifyingSpeakers, for: meetingID)
            buildTranscript(for: current, transcription: transcription, diarization: diarization, in: context)
            current.status = .ready
            current.errorMessage = nil
            try context.save()
            succeeded = true
        } catch {
            if let meeting = fetchMeeting(meetingID, in: context) {
                if error is CancellationError, !meeting.segments.isEmpty {
                    meeting.status = .ready
                    meeting.errorMessage = nil
                } else {
                    meeting.status = .failed
                    meeting.errorMessage = error is CancellationError ? "İşlem iptal edildi." : error.localizedDescription
                }
                try? context.save()
            }
        }
        finish(meetingID, success: succeeded)
    }

    private func buildTranscript(
        for meeting: Meeting,
        transcription: TranscriptionOutput,
        diarization: DiarizationOutput,
        in context: ModelContext
    ) {
        // Voices from the previous transcript of this meeting, so that re-processing keeps the people
        // they were assigned to, including names that were only given in this meeting.
        let previousVoices = meeting.participants.compactMap { participant -> KnownSpeaker? in
            guard let profile = participant.speaker, let embedding = participant.embedding, !embedding.isEmpty else { return nil }
            return KnownSpeaker(id: profile.id, embedding: embedding)
        }
        let previousProfileIDs = Set(previousVoices.map(\.id))
        SpeakerDirectory.clearTranscript(of: meeting, in: context, keeping: previousProfileIDs)
        defer { SpeakerDirectory.deleteUnusedProfiles(withIDs: previousProfileIDs, in: context) }

        let alignedSegments = if let speakerKeys = transcription.speakerKeys {
            aligner.align(words: transcription.words, speakerKeys: speakerKeys)
        } else {
            aligner.align(words: transcription.words, turns: diarization.turns)
        }
        let speechDurations = SpeakerStats.speechDurations(of: diarization.turns)

        // Only voices that actually said something become participants; diarization also reports
        // short clusters of noise or coughing that should not turn into new people.
        var usedKeys: [String] = []
        var firstAppearance: [String: Double] = [:]
        for segment in alignedSegments {
            let key = segment.speakerKey ?? Self.unknownSpeakerKey
            if firstAppearance[key] == nil {
                firstAppearance[key] = segment.start
                usedKeys.append(key)
            }
        }

        let candidates = usedKeys.compactMap { key -> SpeakerCandidate? in
            guard let embedding = diarization.embeddings[key], !embedding.isEmpty else { return nil }
            return SpeakerCandidate(key: key, embedding: embedding, speechDuration: speechDurations[key] ?? 0)
        }
        let profiles = SpeakerDirectory.allProfiles(in: context)
        let known = profiles.compactMap { profile -> KnownSpeaker? in
            guard profile.hasVoiceprint, let vector = profile.voiceprint.vector else { return nil }
            return KnownSpeaker(id: profile.id, embedding: vector)
        } + previousVoices
        let matches = SpeakerMatcher(threshold: Float(AppSettings.matchThreshold)).match(candidates: candidates, known: known)
        let profilesByID = Dictionary(profiles.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var nextNumber = SpeakerNaming.nextNumber(existing: profiles.map(\.number))

        var participants: [String: MeetingParticipant] = [:]
        for key in usedKeys {
            let participant = MeetingParticipant(
                diarizationKey: key,
                speechDuration: speechDurations[key] ?? 0,
                firstAppearance: firstAppearance[key] ?? 0,
                embedding: diarization.embeddings[key]
            )
            context.insert(participant)
            participant.meeting = meeting

            let profile: SpeakerProfile
            if let match = matches[key], let profileID = match.profileID, let existing = profilesByID[profileID] {
                profile = existing
                SpeakerDirectory.attach(participant, to: profile)
                participant.matchSimilarity = Double(match.similarity)
            } else {
                profile = SpeakerDirectory.makeProfile(number: nextNumber, in: context)
                nextNumber += 1
                SpeakerDirectory.attach(participant, to: profile)
            }
            participants[key] = participant
        }

        for (index, aligned) in alignedSegments.enumerated() {
            let segment = TranscriptSegment(index: index, start: aligned.start, end: aligned.end, text: aligned.text)
            context.insert(segment)
            segment.meeting = meeting
            segment.participant = participants[aligned.speakerKey ?? Self.unknownSpeakerKey]
        }
    }

    private func setStage(_ stage: ProcessingStage, for meetingID: UUID) {
        guard var current = progress[meetingID] else { return }
        current.stage = stage
        progress[meetingID] = current
        background.update(jobID: meetingID, fraction: current.fraction, subtitle: stage.title)
    }

    private func report(transcription value: Double, for meetingID: UUID) {
        guard var current = progress[meetingID] else { return }
        current.transcription = max(current.transcription, value)
        progress[meetingID] = current
        background.update(jobID: meetingID, fraction: current.fraction, subtitle: current.stage.title)
    }

    private func report(diarization value: Double, for meetingID: UUID) {
        guard var current = progress[meetingID] else { return }
        current.diarization = max(current.diarization, value)
        progress[meetingID] = current
        background.update(jobID: meetingID, fraction: current.fraction, subtitle: current.stage.title)
    }

    private func finish(_ meetingID: UUID, success: Bool) {
        tasks[meetingID] = nil
        progress[meetingID] = nil
        background.end(jobID: meetingID, success: success)
        updateIdleTimer()
    }

    /// Keeps the screen awake while processing so the work is not suspended by auto-lock.
    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = !tasks.isEmpty
    }

    private func fetchMeeting(_ meetingID: UUID, in context: ModelContext) -> Meeting? {
        var descriptor = FetchDescriptor<Meeting>(predicate: #Predicate { $0.id == meetingID })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private nonisolated static func fileDuration(of url: URL) -> TimeInterval {
        guard let file = try? AVAudioFile(forReading: url) else { return 0 }
        let sampleRate = file.processingFormat.sampleRate
        return sampleRate > 0 ? Double(file.length) / sampleRate : 0
    }
}
