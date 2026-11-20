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

/// 游戏页：全屏 WebView + 左上角一个退出按钮（避开游戏自己的右上角菜单）。
private struct GameScreen: View {
    @ObservedObject var model: AppModel
    @StateObject private var holder = WebViewHolder()

    var body: some View {
        ZStack(alignment: .topLeading) {
            GameWebView(
                remoteURL: model.gameURL,
                localRoot: model.localWebRoot,
                holder: holder
            )
            .ignoresSafeArea()

            Button {
                model.quitGame()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 26))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white.opacity(0.45))
            }
            .accessibilityLabel("退出")
            .padding(12)
        }
        .statusBarHidden(true)
    }
}
