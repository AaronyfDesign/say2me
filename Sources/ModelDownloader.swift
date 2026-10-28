import Foundation
import Combine

/// 语音模型下载器：首次使用时从 GitHub Release 下载 SenseVoice 模型
/// 到 ~/Library/Application Support/say2me/model/，解压校验后置为就绪。
final class ModelDownloader: NSObject, ObservableObject {

    static let shared = ModelDownloader()

    enum State: Equatable {
        case notDownloaded
        case downloading(progress: Double, downloadedMB: Int, totalMB: Int)
        case extracting
        case ready
        case failed(String)
    }

    @Published private(set) var state: State = .notDownloaded

    static let modelURL = URL(string:
        "https://github.com/AaronyfDesign/say2me/releases/download/model-sensevoice-v1/say2me-sensevoice-model.zip")!

    static var supportDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("say2me", isDirectory: true)
    }

    static var modelDir: URL {
        supportDir.appendingPathComponent("model", isDirectory: true)
    }

    static var isModelPresent: Bool {
        FileManager.default.fileExists(atPath: modelDir.appendingPathComponent("model.int8.onnx").path)
            && FileManager.default.fileExists(atPath: modelDir.appendingPathComponent("tokens.txt").path)
    }

    private var session: URLSession!
    private var task: URLSessionDownloadTask?
    private var zipURL: URL { Self.supportDir.appendingPathComponent("model.zip") }

    private override init() {
        super.init()
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForResource = 60 * 60
        cfg.timeoutIntervalForRequest = 60
        session = URLSession(configuration: cfg, delegate: self, delegateQueue: .main)
        state = Self.isModelPresent ? .ready : .notDownloaded
        // 清理上次中断留下的残缺 zip
        try? FileManager.default.removeItem(at: zipURL)
    }

    func startDownload() {
        switch state {
        case .downloading, .extracting:
            return
        default:
            break
        }
        do {
            try FileManager.default.createDirectory(at: Self.supportDir, withIntermediateDirectories: true)
        } catch {
            state = .failed("无法创建目录：\(error.localizedDescription)")
            return
        }
        // 重试前清理旧 zip
        try? FileManager.default.removeItem(at: zipURL)
        state = .downloading(progress: 0, downloadedMB: 0, totalMB: 0)
        let t = session.downloadTask(with: Self.modelURL)
        t.resume()
        task = t
    }

    // MARK: - 解压与校验（后台线程）

    private func extract(from tmp: URL) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            DispatchQueue.main.async { self.state = .extracting }
            let fm = FileManager.default
            do {
                try fm.createDirectory(at: Self.modelDir, withIntermediateDirectories: true)
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                proc.arguments = ["-x", "-k", tmp.path, Self.modelDir.path]
                try proc.run()
                proc.waitUntilExit()
                guard proc.terminationStatus == 0,
                      Self.isModelPresent else {
                    throw NSError(domain: "say2me.model", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: "解压后未找到 model.int8.onnx / tokens.txt"])
                }
                try? fm.removeItem(at: tmp)
                DispatchQueue.main.async { self.state = .ready }
            } catch {
                DispatchQueue.main.async {
                    self.state = .failed("解压失败：\(error.localizedDescription)")
                }
            }
        }
    }
}

extension ModelDownloader: URLSessionDownloadDelegate {

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : 180_000_000
        state = .downloading(progress: Double(totalBytesWritten) / Double(total),
                             downloadedMB: Int(totalBytesWritten / 1_048_576),
                             totalMB: Int(total / 1_048_576))
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // location 是临时文件，先搬到稳定路径再解压
        let fm = FileManager.default
        try? fm.removeItem(at: zipURL)
        do {
            try fm.moveItem(at: location, to: zipURL)
        } catch {
            state = .failed("保存下载文件失败：\(error.localizedDescription)")
            return
        }
        extract(from: zipURL)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error = error else { return }
        if case .extracting = state { return } // 解压阶段的取消误报忽略
        state = .failed("下载失败：\(error.localizedDescription)")
    }
}
