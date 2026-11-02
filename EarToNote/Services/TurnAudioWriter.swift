import AVFoundation
import Foundation
import MeetingCore

enum TurnAudioError: LocalizedError {
    case conversionUnavailable

    var errorDescription: String? {
        "Ses kaydı yazıya dökme için hazırlanamadı."
    }
}

/// Writes the audio described by a `TurnLayout`: every region is read from the recording, leveled with
/// `TurnLeveler` and followed by silence. Regions are read one at a time, so long recordings are never
/// held in memory as a whole.
enum TurnAudioWriter {
    private static let frameLength = 0.02
    private static let fadeLength = 0.01

    static func write(
        _ layout: TurnLayout,
        from sourceURL: URL,
        to destinationURL: URL,
        leveler: TurnLeveler = TurnLeveler(),
        progress: (Double) -> Void = { _ in }
    ) throws {
        let source = try AVAudioFile(forReading: sourceURL)
        guard let workFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: layout.sampleRate,
            channels: 1,
            interleaved: false
        ), let converter = AVAudioConverter(from: source.processingFormat, to: workFormat)
        else { throw TurnAudioError.conversionUnavailable }

        let fileSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: layout.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let destination = try AVAudioFile(
            forWriting: destinationURL,
            settings: fileSettings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        let silence = [Float](repeating: 0, count: layout.gapSamples)

        for (index, region) in layout.regions.enumerated() {
            try Task.checkCancellation()
            var samples = try read(region, sampleRate: layout.sampleRate, from: source, converter: converter)
            level(&samples, sampleRate: layout.sampleRate, leveler: leveler)
            try append(samples, to: destination, format: workFormat)
            try append(silence, to: destination, format: workFormat)
            progress(Double(index + 1) / Double(layout.regions.count))
        }
    }

    /// The region's samples at the layout's sample rate; always exactly `region.sampleCount` of them.
    private static func read(
        _ region: TurnLayout.Region,
        sampleRate: Double,
        from source: AVAudioFile,
        converter: AVAudioConverter
    ) throws -> [Float] {
        let sourceRate = source.processingFormat.sampleRate
        let startFrame = AVAudioFramePosition((Double(region.sourceStart) / sampleRate * sourceRate).rounded())
        let endFrame = min(
            source.length,
            AVAudioFramePosition((Double(region.sourceEnd) / sampleRate * sourceRate).rounded())
        )
        var samples: [Float] = []
        samples.reserveCapacity(region.sampleCount)
        guard endFrame > startFrame else { return [Float](repeating: 0, count: region.sampleCount) }

        source.framePosition = startFrame
        converter.reset()
        let chunk: AVAudioFrameCount = 8192
        guard let input = AVAudioPCMBuffer(pcmFormat: source.processingFormat, frameCapacity: chunk),
              let output = AVAudioPCMBuffer(
                pcmFormat: converter.outputFormat,
                frameCapacity: AVAudioFrameCount(Double(chunk) * sampleRate / sourceRate) + 1024
              )
        else { throw TurnAudioError.conversionUnavailable }

        var remaining = AVAudioFrameCount(endFrame - startFrame)
        var readError: Error?
        while true {
            output.frameLength = 0
            var conversionError: NSError?
            let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
                guard remaining > 0, readError == nil else {
                    inputStatus.pointee = .endOfStream
                    return nil
                }
                do {
                    try source.read(into: input, frameCount: min(chunk, remaining))
                } catch {
                    readError = error
                }
                guard readError == nil, input.frameLength > 0 else {
                    remaining = 0
                    inputStatus.pointee = .endOfStream
                    return nil
                }
                remaining -= min(remaining, input.frameLength)
                inputStatus.pointee = .haveData
                return input
            }
            if let error = readError ?? conversionError { throw error }
            if let channel = output.floatChannelData?[0], output.frameLength > 0 {
                samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
            }
            if status == .endOfStream || status == .error { break }
        }

        if samples.count > region.sampleCount {
            samples.removeLast(samples.count - region.sampleCount)
        } else if samples.count < region.sampleCount {
            samples.append(contentsOf: repeatElement(0, count: region.sampleCount - samples.count))
        }
        return samples
    }

    /// Applies the region's gain with short fades at both ends; peaks are rounded off instead of clipped.
    private static func level(_ samples: inout [Float], sampleRate: Double, leveler: TurnLeveler) {
        guard !samples.isEmpty else { return }
        let frame = max(1, Int(frameLength * sampleRate))
        var frameRMS: [Float] = []
        frameRMS.reserveCapacity(samples.count / frame + 1)
        var start = 0
        while start + frame <= samples.count {
            var sum: Float = 0
            for index in start..<(start + frame) {
                sum += samples[index] * samples[index]
            }
            frameRMS.append((sum / Float(frame)).squareRoot())
            start += frame
        }
        let gain = leveler.gain(frameRMS: frameRMS)

        let fade = min(Int(fadeLength * sampleRate), samples.count / 2)
        let last = samples.count - 1
        for index in samples.indices {
            var value = samples[index] * gain
            if index < fade {
                value *= Float(index) / Float(fade)
            } else if last - index < fade {
                value *= Float(last - index) / Float(fade)
            }
            let magnitude = abs(value)
            if magnitude > 0.9 {
                value = (0.9 + 0.1 * tanh((magnitude - 0.9) / 0.1)) * (value < 0 ? -1 : 1)
            }
            samples[index] = value
        }
    }

    private static func append(_ samples: [Float], to file: AVAudioFile, format: AVAudioFormat) throws {
        guard !samples.isEmpty else { return }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0]
        else { throw TurnAudioError.conversionUnavailable }
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        try file.write(from: buffer)
    }
}
