import SwiftUI

/// 启动器界面：进游戏、改地址、关于。
struct LandingView: View {
    @EnvironmentObject private var model: AppModel

    @State private var showSettings = false
    @State private var showAbout = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.05, green: 0.12, blue: 0.28),
                         Color(red: 0.35, green: 0.05, blue: 0.30)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                Spacer()

                Text("罪恶都市")
                    .font(.system(size: 52, weight: .black, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(colors: [.white, Color(red: 1, green: 0.75, blue: 0.4)],
                                       startPoint: .top, endPoint: .bottom)
                    )

                Text("Vice City · 网页版套壳")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.65))

                Text(model.isOffline ? "本地包模式" : "在线模式")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.12), in: Capsule())
                    .foregroundStyle(.white.opacity(0.75))

                Spacer()

                VStack(spacing: 12) {
                    primaryButton("开始游戏") { model.startGame() }

                    HStack(spacing: 12) {
                        secondaryButton("连接地址") { showSettings = true }
                        secondaryButton("关于") { showAbout = true }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 24)

            }
        }
        .statusBarHidden(true)
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(model)
        }
        .sheet(isPresented: $showAbout) {
            AboutView()
        }
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(colors: [Color(red: 1, green: 0.55, blue: 0.2),
                                            Color(red: 0.95, green: 0.3, blue: 0.25)],
                                   startPoint: .leading, endPoint: .trailing),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .foregroundStyle(.white)
        }
    }

    private func secondaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(.white.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .foregroundStyle(.white)
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://", text: $text)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .font(.callout.monospaced())
                } header: {
                    Text("游戏页面地址")
                } footer: {
                    Text("默认是国内镜像，不用梯子。境外网络可以填 DOS.Zone 官方 v16 地址，地址里带 ?wasm= 的参数要完整保留。")
                }

                Section {
                    Button("恢复默认地址") {
                        model.resetGameURL()
                        text = model.gameURL.absoluteString
                    }
                    Button("切到 DOS.Zone 官方源") {
                        model.useOfficialGameURL()
                        text = model.gameURL.absoluteString
                    }
                } footer: {
                    Text(model.isOffline
                         ? "App 包里已经带了本地网页包，会优先走离线，这个地址只在没本地包时用。"
                         : "目前走在线加载。")
                }
            }
            .navigationTitle("连接设置")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if model.saveGameURL(text) {
                            dismiss()
                        } else {
                            error = "地址格式不对，要以 http:// 或 https:// 开头。"
                        }
                    }
                }
            }
            .alert("存不了", isPresented: Binding(
                get: { error != nil },
                set: { if !$0 { error = nil } }
            )) {
                Button("好", role: .cancel) { error = nil }
            } message: {
                Text(error ?? "")
            }
            .onAppear { text = model.gameURL.absoluteString }
        }
    }
}

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("这是什么")
                        .font(.headline)
                    Text("一个跑网页版 reVC 的 iOS 外壳。游戏本体来自社区的开源移植，本 App 只负责显示和操作，不附带任何游戏素材。")
                        .font(.callout)

                    Text("你需要什么")
                        .font(.headline)
                        .padding(.top, 6)
                    Text("自己的一份《GTA：罪恶都市》正版游戏文件，以及网页版的运行环境。")
                        .font(.callout)

                    Text("免责")
                        .font(.headline)
                        .padding(.top, 6)
                    Text("非官方项目，与 Rockstar Games、Take-Two 无关。请勿用于分发或出售游戏素材。")
                        .font(.callout)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("关于")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("好") { dismiss() }
                }
            }
        }
    }
}
