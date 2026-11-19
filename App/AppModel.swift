import Foundation
import SwiftUI
import WebKit

/// 全局状态：游戏地址、本地网页包、导入的游戏文件目录。
final class AppModel: ObservableObject {
    @Published var showGame = false
    @Published var gameURL: URL = AppModel.defaultGameURL
    @Published var localWebRoot: URL?
    @Published var gameFileCount = 0
    @Published var lastBackupText: String?

    /// 默认地址：DOS.Zone 官方托管的网页版 v16。
    /// wasm 参数是外链（br.cdn.dos.zone），已经整体 URL 编码好，原样交给 WKWebView。
    static let defaultGameURL = URL(string:
        "https://dos.zone/vcsky/release/v16/index.html" +
        "?wasm=https%3A%2F%2Fbr.cdn.dos.zone%2Fvcsky%2Fv16.wasm.br" +
        "&lang=en"
    )!

    private let defaults = UserDefaults.standard

    var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    var gameFilesRoot: URL {
        documents.appendingPathComponent("GameFiles", isDirectory: true)
    }

    init() {
        createFolders()
        loadSavedURL()
        scanLocalWebBundle()
        refreshGameFileCount()
        lastBackupText = defaults.string(forKey: "lastBackup")
    }

    private func createFolders() {
        try? FileManager.default.createDirectory(
            at: gameFilesRoot,
            withIntermediateDirectories: true
        )
    }

    private func loadSavedURL() {
        if let raw = defaults.string(forKey: "gameURL"),
           let url = URL(string: raw) {
            gameURL = url
        }
    }

    /// 保存用户填的地址；只收 http/https，填错就不动原值。
    @discardableResult
    func saveGameURL(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else { return false }
        gameURL = url
        defaults.set(url.absoluteString, forKey: "gameURL")
        return true
    }

    /// 恢复默认地址。
    func resetGameURL() {
        gameURL = Self.defaultGameURL
        defaults.removeObject(forKey: "gameURL")
    }

    /// 是否走本地离线包。
    var isOffline: Bool { localWebRoot != nil }

    /// App 包里如果塞了本地网页版（Web/index.html），优先用本地的。
    private func scanLocalWebBundle() {
        if let index = Bundle.main.url(
            forResource: "index",
            withExtension: "html",
            subdirectory: "Web"
        ) {
            localWebRoot = index.deletingLastPathComponent()
            return
        }
        if let index = Bundle.main.url(forResource: "index", withExtension: "html") {
            localWebRoot = index.deletingLastPathComponent()
        }
    }

    /// 把选中的文件夹里的东西拷进 Documents/GameFiles。
    func importFolder(from picked: URL) throws {
        let scoped = picked.startAccessingSecurityScopedResource()
        defer { if scoped { picked.stopAccessingSecurityScopedResource() } }

        let items = try FileManager.default.contentsOfDirectory(
            at: picked,
            includingPropertiesForKeys: [.isDirectoryKey]
        )
        for item in items {
            let dest = gameFilesRoot.appendingPathComponent(item.lastPathComponent)
            if FileManager.default.fileExists(atPath: dest.path) {
                try? FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: item, to: dest)
        }
        refreshGameFileCount()
    }

    func refreshGameFileCount() {
        let count = (try? FileManager.default.contentsOfDirectory(
            atPath: gameFilesRoot.path
        ).count) ?? 0
        gameFileCount = count
    }

    func startGame() {
        showGame = true
    }

    /// 从正在跑游戏的 WebView 里把存档导到 Documents/SaveBackups。
    /// 只能玩着的时候做：存档在页面自己的 OPFS 里，只能让页面自己去读。
    func backupSaves(using webView: WKWebView?, completion: @escaping (String) -> Void) {
        guard let webView else {
            completion("还没进游戏，没有可备份的存档")
            return
        }
        webView.callAsyncJavaScript(
            SaveBackup.exportScript,
            arguments: [:],
            in: nil,
            in: .page
        ) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                completion("备份失败：\(error.localizedDescription)")
            case .success(let value):
                guard let dict = value as? [String: Any] else {
                    completion("备份失败：页面没返回数据")
                    return
                }
                guard dict["ok"] as? Bool == true else {
                    completion("备份失败：\(dict["reason"] as? String ?? "未知原因")")
                    return
                }
                let files = dict["files"] as? [[String: Any]] ?? []
                do {
                    let saved = try SaveBackup.write(payload: files, documents: self.documents)
                    let kb = max(1, saved.byteCount / 1024)
                    let text = "已备份 \(saved.fileCount) 个文件（\(kb) KB）"
                    self.lastBackupText = text
                    self.defaults.set(text, forKey: "lastBackup")
                    completion("\(text)\n目录：SaveBackups/\(saved.url.lastPathComponent)")
                } catch {
                    completion("写文件失败：\(error.localizedDescription)")
                }
            }
        }
    }

    func quitGame() {
        showGame = false
    }
}
