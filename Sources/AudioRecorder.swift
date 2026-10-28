import Foundation
import AVFoundation

/// Captures microphone audio and converts it to 16 kHz mono Float32 in memory.
final class AudioRecorder {
    private let engine = AVAudioEngine()
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: 16000,
        channels: 1, interleaved: false)!
    private var converter: AVAudioConverter?
    private var samples: [Float] = []
    private let lock = NSLock()
    private(set) var running = false

    enum RecorderError: Error { case noConverter, micDenied(Error) }

    func start() throws {
        let input = engine.inputNode
        let inFormat = input.outputFormat(forBus: 0)
        guard let conv = AVAudioConverter(from: inFormat, to: targetFormat) else {
            throw RecorderError.noConverter
        }
        converter = conv
        lock.lock(); samples = []; lock.unlock()

        input.installTap(onBus: 0, bufferSize: 4096, format: inFormat) { [weak self] buf, _ in
            guard let self = self, let conv = self.converter else { return }
            let ratio = 16000.0 / inFormat.sampleRate
            let cap = AVAudioFrameCount(Double(buf.frameLength) * ratio) + 64
            guard let out = AVAudioPCMBuffer(pcmFormat: self.targetFormat, frameCapacity: cap) else { return }
            var err: NSError?
            conv.convert(to: out, error: &err) { _, status in
                status.pointee = .haveData
                return buf
            }
            guard err == nil, out.frameLength > 0 else { return }
            let n = Int(out.frameLength)
            let ch = out.floatChannelData![0]
            self.lock.lock()
            self.samples.append(contentsOf: UnsafeBufferPointer(start: ch, count: n))
            self.lock.unlock()
        }
        engine.prepare()
        try engine.start()
        running = true
    }

    func stop() -> [Float] {
        if running {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            running = false
        }
        lock.lock(); defer { lock.unlock() }
        let s = samples
        samples = []
        return s
    }
}

/// Writes Float32 samples as a 16-bit PCM 16 kHz mono WAV file.
enum WavWriter {
    static func write(samples: [Float], to url: URL) throws {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                    sampleRate: 16000, channels: 1,
                                    interleaved: false)!
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings,
                                    commonFormat: .pcmFormatFloat32,
                                    interleaved: false)
        guard let buf = AVAudioPCMBuffer(pcmFormat: format,
                                         frameCapacity: AVAudioFrameCount(samples.count)) else {
            throw NSError(domain: "WavWriter", code: 1)
        }
        buf.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { ptr in
            guard let base = ptr.baseAddress else { return }
            buf.floatChannelData![0].update(from: base, count: samples.count)
        }
        try file.write(from: buf)
    }
}
