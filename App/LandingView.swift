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
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("VCWeb")
                            .font(.system(size: 34, weight: .black, design: .rounded))
                        Text("罪恶都市 · 网页版套壳")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    section(
                        "这是什么",
                        "一个把网页版 reVC 装进 iOS 的外壳。App 只提供启动页、全屏 WebView 和地址设置，游戏画面、声音、存档全部来自网页那边，App 自己不带任何游戏素材。"
                    )

                    section(
                        "怎么开始",
                        "点「开始游戏」就是全屏加载页面。加载不出来，去「连接地址」切到官方源再试；地址只收 http(s)://，填错不会保存。"
                    )

                    section(
                        "存档在哪",
                        "存档在网页自己的 OPFS 存储里，在 WebKit 容器内，App 读不到也不会去动。想备份就在游戏里用页面自己的导出。"
                    )

                    section(
                        "你需要什么",
                        "一份正版《GTA：罪恶都市》授权，以及能访问对应网页版的网络环境。App 里没有任何破解、绕过或分发游戏素材的功能。"
                    )

                    section(
                        "免责",
                        "非官方项目，与 Rockstar Games、Take-Two 没有任何关系。请勿用于分发或出售游戏素材，也不要当成正版替代品。"
                    )

                    Text(version)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
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

    private func section(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "版本 \(short) (\(build)) · 未签名构建"
    }
}
