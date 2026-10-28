// Headless smoke test for say2me logic (no GUI, no mic).
// Reads a wav file, rewrites it through WavWriter, runs the recognizer,
// prints the result. Build & run via tests/smoke.sh.
import Foundation
import AVFoundation

@main
struct Smoke {
    static func main() {
        let args = CommandLine.arguments
        guard args.count >= 3 else {
            print("usage: smoke <in.wav> <lang>")
            Foundation.exit(2)
        }
        // repo root from compile-time source path (CLI binary, no bundle)
        let src = URL(fileURLWithPath: #filePath)   // .../sense-dict/tests/smoke.swift
        let repo = src.deletingLastPathComponent().deletingLastPathComponent()
        let fm = FileManager.default
        let vendorDir = repo.appendingPathComponent("vendor")
        var cli: String?
        if let ents = try? fm.contentsOfDirectory(atPath: vendorDir.path) {
            for e in ents.sorted().reversed() where e.contains("osx-arm64") {
                let p = vendorDir.appendingPathComponent(e).appendingPathComponent("bin/sherpa-onnx-offline").path
                if fm.isExecutableFile(atPath: p) { cli = p; break }
            }
        }
        let modelDir = repo.appendingPathComponent("models/sense-voice").path
        guard let cliPath = cli, fm.fileExists(atPath: modelDir + "/model.int8.onnx") else {
            print("FAIL: cannot resolve cli or model under \(repo.path)")
            Foundation.exit(2)
        }
        let inWav = args[1]
        let lang = args[2]

        // 1. decode input wav to 16k mono Float32 (mimics recorder output)
        guard let file = try? AVAudioFile(forReading: URL(fileURLWithPath: inWav)) else {
            print("FAIL: cannot open \(inWav)"); Foundation.exit(1)
        }
        let srcFmt = file.processingFormat
        let tgtFmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000,
                                   channels: 1, interleaved: false)!
        guard let conv = AVAudioConverter(from: srcFmt, to: tgtFmt) else {
            print("FAIL: converter"); Foundation.exit(1)
        }
        var samples: [Float] = []
        let capBuf = AVAudioPCMBuffer(pcmFormat: srcFmt, frameCapacity: 65536)!
        while true {
            do { try file.read(into: capBuf) }
            catch { print("FAIL: read \(error)"); Foundation.exit(1) }
            if capBuf.frameLength == 0 { break }
            let ratio = 16000.0 / srcFmt.sampleRate
            let out = AVAudioPCMBuffer(pcmFormat: tgtFmt,
                                       frameCapacity: AVAudioFrameCount(Double(capBuf.frameLength) * ratio) + 64)!
            var err: NSError?
            conv.convert(to: out, error: &err) { _, status in
                status.pointee = .haveData
                return capBuf
            }
            if let e = err { print("FAIL: convert \(e)"); Foundation.exit(1) }
            samples.append(contentsOf: UnsafeBufferPointer(start: out.floatChannelData![0],
                                                            count: Int(out.frameLength)))
            if capBuf.frameLength < capBuf.frameCapacity { break }
        }
        print("decoded samples: \(samples.count)")

        // 2. write through WavWriter
        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("smoke-\(UUID().uuidString).wav")
        do { try WavWriter.write(samples: samples, to: outURL) }
        catch { print("FAIL: WavWriter \(error)"); Foundation.exit(1) }

        // 3. recognize
        do {
            let text = try Recognizer.run(wavPath: outURL.path,
                                          config: .init(cliPath: cliPath, modelDir: modelDir,
                                                        language: lang, useITN: true))
            try? FileManager.default.removeItem(at: outURL)
            print("RECOGNIZED: \(text)")
            Foundation.exit(text.isEmpty ? 1 : 0)
        } catch {
            print("FAIL: \(error.localizedDescription)")
            Foundation.exit(1)
        }
    }
}
