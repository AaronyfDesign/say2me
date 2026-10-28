import Foundation

/// Calls the sherpa-onnx-offline CLI with the SenseVoice-Small model.
enum Recognizer {
    struct Config {
        var cliPath: String
        var modelDir: String
        var language: String   // auto | zh | en | ja | ko | yue
        var useITN: Bool
    }

    enum RecognizerError: LocalizedError {
        case cliMissing
        case modelMissing
        case exitStatus(Int32, String)
        case noOutput

        var errorDescription: String? {
            switch self {
            case .cliMissing: return "找不到 sherpa-onnx-offline 可执行文件"
            case .modelMissing: return "找不到 SenseVoice 模型（modelDir 设置为空且自动解析失败）"
            case .exitStatus(let s, let msg): return "识别进程退出码 \(s)：\(msg)"
            case .noOutput: return "识别进程无输出"
            }
        }
    }

    /// Returns the recognized text (tags like <|zh|> stripped).
    static func run(wavPath: String, config: Config) throws -> String {
        guard FileManager.default.isExecutableFile(atPath: config.cliPath) else {
            throw RecognizerError.cliMissing
        }
        guard FileManager.default.fileExists(atPath: config.modelDir + "/model.int8.onnx") else {
            throw RecognizerError.modelMissing
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: config.cliPath)
        p.arguments = [
            "--tokens=\(config.modelDir)/tokens.txt",
            "--sense-voice-model=\(config.modelDir)/model.int8.onnx",
            "--sense-voice-language=\(config.language)",
            "--sense-voice-use-itn=\(config.useITN ? "1" : "0")",
            wavPath,
        ]
        let stdout = Pipe()
        let stderr = Pipe()
        p.standardOutput = stdout
        p.standardError = stderr
        try p.run()
        p.waitUntilExit()

        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        guard p.terminationStatus == 0 else {
            throw RecognizerError.exitStatus(p.terminationStatus,
                                             String(String(decoding: errData, as: UTF8.self).suffix(300)))
        }
        let outText = String(decoding: outData, as: UTF8.self)
        guard let line = outText.split(separator: "\n").reversed()
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }),
              let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = obj["text"] as? String else {
            throw RecognizerError.noOutput
        }
        return stripTags(text)
    }

    /// Strip SenseVoice inline tags like <|zh|> <|NEUTRAL|> <|Speech|>.
    static func stripTags(_ s: String) -> String {
        guard let re = try? NSRegularExpression(pattern: #"<\|[^|]*\|>"#) else { return s }
        let range = NSRange(s.startIndex..., in: s)
        let trimmed = re.stringByReplacingMatches(in: s, range: range, withTemplate: "")
        return trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
