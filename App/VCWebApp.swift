import SwiftUI
import WebKit

@main
struct VCWebApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            Group {
                if model.showGame {
                    GameScreen(model: model)
                        .preferredColorScheme(.dark)
                } else {
                    LandingView()
                        .preferredColorScheme(.dark)
                }
            }
            .environmentObject(model)
        }
    }
}

/// 游戏页：全屏 WebView + 右上角两个小按钮（备份存档 / 退出）。
private struct GameScreen: View {
    @ObservedObject var model: AppModel
    @StateObject private var holder = WebViewHolder()
    @State private var note: String?
    @State private var showNote = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            GameWebView(
                remoteURL: model.gameURL,
                localRoot: model.localWebRoot,
                gameRoot: model.gameFilesRoot,
                holder: holder
            )
            .ignoresSafeArea()

            HStack(spacing: 10) {
                Button {
                    model.backupSaves(using: holder.webView) { text in
                        note = text
                        showNote = true
                    }
                } label: {
                    Image(systemName: "square.and.arrow.down.on.square")
                        .font(.system(size: 20, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white.opacity(0.75))
                        .padding(10)
                        .background(.black.opacity(0.35), in: Circle())
                }
                .accessibilityLabel("备份存档")

                Button {
                    model.quitGame()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 28))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white.opacity(0.7))
                }
                .accessibilityLabel("退出")
            }
            .padding(14)
        }
        .statusBarHidden(true)
        .alert("存档备份", isPresented: $showNote) {
            Button("好", role: .cancel) { showNote = false }
        } message: {
            Text(note ?? "")
        }
    }
}
