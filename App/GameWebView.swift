import SwiftUI
import UIKit
import WebKit

/// 全屏跑网页版 reVC 的 WKWebView。
///
/// 两种来源：
///   - 在线：直接加载 `remoteURL`（默认是 DOS.Zone 的 v16 页面）
///   - 离线：App 包里有 Web/index.html 时，走 vcweb:// 本地 scheme
///
/// 不用 file://：file:// 下 wasm / fetch 会被挡成跨源，页面还进不了安全上下文。
/// 把 WKWebView 实例递给外壳（备份存档之类的操作要拿它去页面里跑 JS）。
final class WebViewHolder: ObservableObject {
    weak var webView: WKWebView?
}

struct GameWebView: UIViewRepresentable {
    let remoteURL: URL
    /// App 包里 Web/ 目录；有的话优先离线。
    let localRoot: URL?
    let holder: WebViewHolder

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        // 按移动端视口渲染，避免页面按桌面宽度排版后留下大片黑边
        config.defaultWebpagePreferences.preferredContentMode = .mobile

        // 本地文件走自定义 scheme
        config.setURLSchemeHandler(
            VCWebSchemeHandler(localRoot: localRoot),
            forURLScheme: VCWebScheme.scheme
        )

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.scrollView.bounces = false
        // 页面里的设置、存档这些面板需要滑动，之前被禁掉了
        webView.scrollView.isScrollEnabled = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.scrollView.showsHorizontalScrollIndicator = false
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsLinkPreview = false
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }

        holder.webView = webView

        if localRoot != nil {
            webView.load(URLRequest(url: VCWebScheme.localURL()))
        } else {
            webView.load(URLRequest(url: remoteURL))
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {

        // MARK: 导航

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            // 页面里 "在别的站点看" 之类的按钮：交回系统
            if navigationAction.targetFrame == nil {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }

            let scheme = url.scheme?.lowercased() ?? ""
            let allowed = ["https", "http", VCWebScheme.scheme, "about", "blob", "data", "ws", "wss"]
            if !allowed.contains(scheme) {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            showLoadError(error, in: webView)
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            showLoadError(error, in: webView)
        }

        // MARK: JS 弹窗

        func webView(
            _ webView: WKWebView,
            runJavaScriptAlertPanelWithMessage message: String,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping () -> Void
        ) {
            guard let host = topViewController() else {
                completionHandler()
                return
            }
            let box = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            box.addAction(UIAlertAction(title: "好", style: .default) { _ in completionHandler() })
            host.present(box, animated: true)
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptConfirmPanelWithMessage message: String,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping (Bool) -> Void
        ) {
            guard let host = topViewController() else {
                completionHandler(false)
                return
            }
            let box = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            box.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(false) })
            box.addAction(UIAlertAction(title: "好", style: .default) { _ in completionHandler(true) })
            host.present(box, animated: true)
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptTextInputPanelWithPrompt prompt: String,
            defaultText: String?,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping (String?) -> Void
        ) {
            guard let host = topViewController() else {
                completionHandler(nil)
                return
            }
            let box = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
            box.addTextField { $0.text = defaultText }
            box.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(nil) })
            box.addAction(UIAlertAction(title: "好", style: .default) { _ in
                completionHandler(box.textFields?.first?.text)
            })
            host.present(box, animated: true)
        }

        private func showLoadError(_ error: Error, in webView: WKWebView) {
            let ns = error as NSError
            // -999 = 主动取消，别报警
            if ns.code == NSURLErrorCancelled { return }
            let html = """
            <html><head><meta name="viewport" content="width=device-width,initial-scale=1">
            <style>body{background:#100a36;color:#c9b8ff;font-family:-apple-system;padding:28px;line-height:1.6}
            h2{color:#ff8fa3}</style></head><body>
            <h2>页面加载失败</h2>
            <p>\(ns.localizedDescription)</p>
            <p style="opacity:.6">地址：\(webView.url?.absoluteString ?? "-")</p>
            </body></html>
            """
            webView.loadHTMLString(html, baseURL: nil)
        }

        private func topViewController() -> UIViewController? {
            let scenes = UIApplication.shared.connectedScenes
            let windowScene = scenes.first {
                $0.activationState == .foregroundActive
            } as? UIWindowScene
            var top = windowScene?.windows.first { $0.isKeyWindow }?.rootViewController
            while let presented = top?.presentedViewController { top = presented }
            return top
        }
    }
}
