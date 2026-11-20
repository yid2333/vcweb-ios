import Foundation
import WebKit

/// 自定义 scheme：本地网页包走它，不用 file://。
///
/// 为什么不用 file://：WKWebView 加载 file:// 页面时，wasm / ES module /
/// fetch 都会被 CORS 当成跨源挡掉，页内还会被当作不安全上下文。
/// 自定义 scheme + WKURLSchemeHandler 有正常来源，能跑 wasm 和 fetch。
///
/// 路由：
///   vcweb://local/<路径>  → App 包里的 Web/ 目录
enum VCWebScheme {
    static let scheme = "vcweb"
    static let localHost = "local"

    static func localURL(_ path: String = "index.html") -> URL {
        URL(string: "\(scheme)://\(localHost)/\(path)")!
    }
}

final class VCWebSchemeHandler: NSObject, WKURLSchemeHandler {
    private let localRoot: URL?
    init(localRoot: URL?) {
        self.localRoot = localRoot?.standardizedFileURL
        super.init()
    }

    // MARK: - WKURLSchemeHandler

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else {
            reply(task, status: 400, body: "坏请求")
            return
        }
        guard let host = url.host?.lowercased() else {
            reply(task, status: 400, body: "缺 host：\(url.absoluteString)")
            return
        }

        guard host == VCWebScheme.localHost, let root = localRoot else {
            reply(task, status: 404, body: "没有可用的本地目录：\(host)")
            return
        }

        guard let fileURL = resolve(url: url, under: root) else {
            reply(task, status: 403, body: "越界路径：\(url.path)")
            return
        }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            reply(task, status: 404, body: "找不到文件：\(url.path)")
            return
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        } catch {
            reply(task, status: 500, body: "读不出来：\(error.localizedDescription)")
            return
        }

        guard let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": Self.mimeType(for: fileURL),
                // 自定义 scheme 下 fetch / wasm 照样按跨源规则检查，放开。
                "Access-Control-Allow-Origin": "*",
                "Cache-Control": "no-cache"
            ]
        ) else {
            reply(task, status: 500, body: "响应构造失败")
            return
        }

        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    /// 整个请求是同步读完直接回的，stop 不会插进来，所以什么都不用做。
    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}

    // MARK: - 内部

    /// 把 vcweb://host/a/b.js 映射到 root/a/b.js，并挡住 ../ 越界。
    private func resolve(url: URL, under root: URL) -> URL? {
        var path = url.path
        if let decoded = path.removingPercentEncoding {
            path = decoded
        }
        while path.hasPrefix("/") { path.removeFirst() }
        if path.isEmpty { path = "index.html" }

        let candidate = root.appendingPathComponent(path).standardizedFileURL
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard candidate.path == root.path || candidate.path.hasPrefix(rootPath) else {
            return nil
        }
        return candidate
    }

    private func reply(_ task: WKURLSchemeTask, status: Int, body: String) {
        guard let url = task.request.url,
              let payload = body.data(using: .utf8),
              let response = HTTPURLResponse(
                url: url,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Content-Type": "text/plain; charset=utf-8",
                    "Access-Control-Allow-Origin": "*"
                ]
              ) else { return }
        task.didReceive(response)
        task.didReceive(payload)
        task.didFinish()
    }

    static func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "html", "htm": return "text/html; charset=utf-8"
        case "js", "mjs": return "text/javascript; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "json": return "application/json; charset=utf-8"
        case "wasm": return "application/wasm"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "svg": return "image/svg+xml"
        case "ico": return "image/x-icon"
        case "mp3": return "audio/mpeg"
        case "ogg", "oga": return "audio/ogg"
        case "wav": return "audio/wav"
        case "mp4", "m4v": return "video/mp4"
        case "webm": return "video/webm"
        case "woff": return "font/woff"
        case "woff2": return "font/woff2"
        case "ttf": return "font/ttf"
        case "txt", "ini", "cfg", "md", "xml", "csv", "glsl", "frag", "vert":
            return "text/plain; charset=utf-8"
        default:
            return "application/octet-stream"
        }
    }
}
