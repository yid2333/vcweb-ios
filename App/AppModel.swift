import Foundation
import SwiftUI

/// 全局状态：游戏地址、本地网页包、导入的游戏文件目录。
final class AppModel: ObservableObject {
    @Published var showGame = false
    @Published var gameURL: URL = AppModel.defaultGameURL
    @Published var localWebRoot: URL?
    @Published var gameFileCount = 0

    /// 默认地址：国内镜像（实测不挂梯子也能进）。
    /// 官方源见 `officialGameURL`，在设置里可以切过去，但国内网络得自备梯子。
    static let defaultGameURL = URL(string: "https://gtavc.armdev.cn/")!

    /// DOS.Zone 官方托管的网页版 v16（境外网络可用）。
    static let officialGameURL = URL(string:
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

    /// 切到 DOS.Zone 官方源（国内需要梯子）。
    func useOfficialGameURL() {
        gameURL = Self.officialGameURL
        defaults.set(Self.officialGameURL.absoluteString, forKey: "gameURL")
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

    func quitGame() {
        showGame = false
    }
}
