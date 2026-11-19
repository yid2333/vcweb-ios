import Foundation
import WebKit

/// 给网页版用的 JS 桥。
///
/// 网页那边可以直接 <img src="vcweb://game/x.png"> / fetch("vcweb://game/...")
/// 读导进 App 的游戏文件；需要目录列表或拿 base64 时用下面这些：
///
///   await VCWebNative.listFiles()      → ["data/a.img", "models/x.dff", ...]
///   await VCWebNative.exists(path)     → true / false
///   await VCWebNative.readBase64(path) → "AAECAw..."（二进制）
///   await VCWebNative.readText(path)   → "..."（文本，UTF-8）
///
/// 路径相对 Documents/GameFiles。
final class GameBridge: NSObject, WKScriptMessageHandler {
    static let handlerName = "vcBridge"

    private let gameRoot: URL

    init(gameRoot: URL) {
        self.gameRoot = gameRoot.standardizedFileURL
        super.init()
    }

    static var javascriptAPI: String {
        """
        (function () {
          if (window.VCWebNative) { return; }
          var pending = new Map();
          var seq = 0;

          window.__vcResolve = function (id, ok, payload) {
            var p = pending.get(id);
            if (!p) { return; }
            pending.delete(id);
            if (ok) { p.resolve(payload); } else { p.reject(new Error(String(payload))); }
          };

          function call(method, args) {
            return new Promise(function (resolve, reject) {
              var id = ++seq;
              pending.set(id, { resolve: resolve, reject: reject });
              try {
                window.webkit.messageHandlers.\(handlerName).postMessage({
                  id: id, method: method, args: args || []
                });
              } catch (e) {
                pending.delete(id);
                reject(e);
              }
            });
          }

          window.VCWebNative = {
            gameFilesBase: "\(VCWebScheme.scheme)://\(VCWebScheme.gameHost)/",
            listFiles: function () { return call("listFiles", []); },
            exists: function (path) { return call("exists", [path]); },
            readBase64: function (path) { return call("readBase64", [path]); },
            readText: function (path) { return call("readText", [path]); }
          };
        })();
        """
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? [String: Any],
              let id = body["id"] as? Int,
              let method = body["method"] as? String else { return }
        let args = body["args"] as? [Any] ?? []

        do {
            let result = try handle(method: method, args: args)
            reply(to: message.webView, id: id, ok: true, payload: result)
        } catch {
            reply(to: message.webView, id: id, ok: false, payload: error.localizedDescription)
        }
    }

    // MARK: - 方法

    private func handle(method: String, args: [Any]) throws -> Any {
        switch method {
        case "listFiles":
            return try listFiles()
        case "exists":
            let url = try fileURL(args.first as? String)
            return FileManager.default.fileExists(atPath: url.path)
        case "readBase64":
            let data = try readData(args.first as? String)
            return data.base64EncodedString()
        case "readText":
            let data = try readData(args.first as? String)
            return String(data: data, encoding: .utf8) ?? ""
        default:
            throw BridgeError.unknownMethod(method)
        }
    }

    private func listFiles() throws -> [String] {
        let root = gameRoot
        guard let walker = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var out: [String] = []
        for case let url as URL in walker {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            if values?.isDirectory == true { continue }
            let full = url.standardizedFileURL.path
            guard full.hasPrefix(root.path + "/") else { continue }
            out.append(String(full.dropFirst(root.path.count + 1)))
            if out.count >= 20000 { break }
        }
        return out.sorted()
    }

    private func readData(_ path: String?) throws -> Data {
        let url = try fileURL(path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw BridgeError.notFound(path ?? "")
        }
        return try Data(contentsOf: url, options: .mappedIfSafe)
    }

    /// 把网页传进来的相对路径夹在 GameFiles 墙内，挡住 ../。
    private func fileURL(_ path: String?) throws -> URL {
        guard let raw = path, !raw.isEmpty else { throw BridgeError.badPath }
        var clean = raw
        while clean.hasPrefix("/") { clean.removeFirst() }
        let url = gameRoot.appendingPathComponent(clean).standardizedFileURL
        let root = gameRoot.path.hasSuffix("/") ? gameRoot.path : gameRoot.path + "/"
        guard url.path.hasPrefix(root) else { throw BridgeError.outOfBounds(raw) }
        return url
    }

    private func reply(to webView: WKWebView?, id: Int, ok: Bool, payload: Any) {
        guard let webView else { return }
        let json: String
        if let data = try? JSONSerialization.data(withJSONObject: [payload], options: [.fragmentsAllowed]),
           let text = String(data: data, encoding: .utf8),
           text.count >= 2 {
            json = String(text.dropFirst().dropLast())
        } else if let text = payload as? String {
            json = Self.jsString(text)
        } else {
            json = "null"
        }
        let script = "window.__vcResolve(\(id), \(ok ? "true" : "false"), \(json));"
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    private static func jsString(_ value: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [value], options: []))
            ?? Data("[\"\"]".utf8)
        let text = String(data: data, encoding: .utf8) ?? "[\"\"]"
        return String(text.dropFirst().dropLast())
    }

    enum BridgeError: LocalizedError {
        case unknownMethod(String)
        case notFound(String)
        case badPath
        case outOfBounds(String)

        var errorDescription: String? {
            switch self {
            case .unknownMethod(let name): return "未知方法：\(name)"
            case .notFound(let path): return "找不到文件：\(path)"
            case .badPath: return "路径为空"
            case .outOfBounds(let path): return "路径越界：\(path)"
            }
        }
    }
}
