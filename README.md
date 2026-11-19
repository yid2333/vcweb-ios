# 罪恶都市 iOS 套壳（VCWeb）

把网页版 reVC（GTA Vice City 的 WebAssembly 移植）套成 iOS App 的外壳工程。
App 只负责启动界面、全屏 WebView、导入游戏文件和本地资料管理，**不附带任何游戏素材**。

> 状态：工程还没真正编译过。GitHub Actions 因为账号问题没跑起来，所以下面所有构建结论都是静态检查的结果，不是「已验证编过」。第一次 CI 跑完之前别把 ipa 当成品。

## 现在的事实（2026-11-20 线上核对）

默认地址：

```
https://dos.zone/vcsky/release/v16/index.html
    ?wasm=https%3A%2F%2Fbr.cdn.dos.zone%2Fvcsky%2Fv16.wasm.br
    &lang=en
```

- 页面实测 200、88 KB，在 `/vcsky/release/v16/` 下。
- 页面只引三个脚本：`GamepadEmulator.js`、`jsdos-cloud-sdk.js`、`game.js`；`game.js` 再动态加载 `index.js`（Emscripten 胶水，322 KB，`OPFS` 文件系统的实现就在里面）。
- wasm 是外链 `br.cdn.dos.zone/vcsky/v16.wasm.br`，由 `?wasm=` 参数带进去，已经整体 URL 编码好，App 里原样传，不要自己拆参数。
- **来源限制**：`index.html` 末尾有一段 host 检查，但读的是 `window.parent.location.host`，只有被 iframe 套着才生效。顶层直接打开时就是 `dos.zone`，检查通过。注意：换成别的域名（比如本地包）会触发跳回 `dos.zone/ru/grand-theft-auto-vice-city/`。
- **UA 限制**：没有拦截，只用 `/Mobi|Android|iPhone|iPad|iPod/i` 判断是不是移动端来开触屏控件。WKWebView 默认 UA 带 `iPhone`，能过。
- **存档**：`game.js` 把 OPFS 挂到 Emscripten 的 `/vc-assets`，存档和 `revc.ini` 都在里面。云存档要 js-dos 的 premium key（`v8.js-dos.com/key`），没有 key 只是不能云同步，本地照玩。
- `/vc-assets` 是 Emscripten 的虚拟挂载点，不是网址，所以 `https://dos.zone/vc-assets/...` 必然 404 —— 别再往这个方向查。

## 两条路

**在线（默认，能用）**
App 直接加载上面那个 dos.zone 地址。需要联网，游戏数据从 `br.cdn.dos.zone` 拉。

**离线（还没通，先别指望）**
把网页版放进 `App/Web/`，App 会走自定义 scheme `vcweb://local/`，由 `WKURLSchemeHandler` 从包内读文件，不用 `file://`（`file://` 下 wasm 和 fetch 会被 CORS 挡掉）。

但现在这条路被两件事挡着，都还没解：

1. v16 的 host 检查会把非 `dos.zone` 的域跳走，本地包加载后会被踹回线上。
2. OPFS 要求安全上下文，自定义 scheme 不算；不降级的话离线包一进去 FS 挂载就失败。

真要离线，得在 App 里起一个 `127.0.0.1` 的本地 HTTP 服务（localhost 算安全上下文），而不是继续用自定义 scheme。这是个不小的改动，等在线版先跑通再说。

## 目录

```
revc-ios/
├── App/
│   ├── VCWebApp.swift          入口：启动器 ↔ 游戏
│   ├── AppModel.swift          地址、导入的文件、本地网页包
│   ├── LandingView.swift       启动器界面、导入、设置、关于
│   ├── GameWebView.swift       WKWebView 全屏 + 导航/弹窗处理
│   ├── VCWebSchemeHandler.swift  vcweb:// 本地文件服务
│   ├── GameBridge.swift        给网页用的 JS 桥（读 Documents/GameFiles）
│   ├── SaveBackup.swift        存档备份（从 OPFS 导到 Documents）
│   └── Web/                    本地网页版放这里（可选，目前空）
├── Info.plist
├── project.yml                 XcodeGen 工程描述
├── scripts/build-ipa.sh        编出未签名 ipa
├── scripts/mirror-assets.sh    抓上游前端（旧 v6 布局，未验证）
└── .github/workflows/build.yml 云端编译
```

## 编译

需要 macOS + Xcode + [XcodeGen](https://github.com/yonaskolb/XcodeGen)：

```bash
brew install xcodegen
bash scripts/build-ipa.sh
```

产物是 `VCWeb-unsigned.ipa`。未签名，不能直接装，丢进 LiveContainer 或用自签工具重签后安装。

没有 Mac 就把仓库推到 GitHub，Actions 里的 `build-ipa` 会编，跑完在 Artifacts 里下 ipa。

已知的编译风险点（没法在本机验证，列出来备查）：

- `project.yml` 用 `INFOPLIST_FILE` 指仓库里的 Info.plist，并关了 `GENERATE_INFOPLIST_FILE`；别改回 XcodeGen 的 `info:`，那会覆盖手写的 plist。
- 全局 `CODE_SIGNING_ALLOWED=NO`；LiveContainer 会自己重签。
- 没有 Asset Catalog 和 AppIcon，只有警告，不挡编译。

## 使用时

1. 打开 App，点「开始游戏」→ 全屏加载网页版。
2. 「连接地址」可以换地址，只收 `http(s)://`；填错会提示，不会存。
3. 「导入游戏文件」选文件夹，会拷进 `Documents/GameFiles`；也可以在「文件」App 里直接往 App 文件夹拖（`UIFileSharingEnabled` 已开）。
4. 网页里想读这些文件：
   - 直接当网址用：`<img src="vcweb://game/tex/x.png">`、`fetch("vcweb://game/data/a.dat")`
   - 或用 JS 桥：

```js
await VCWebNative.listFiles();      // ["models/gta3.dir", ...]
await VCWebNative.exists("x.dff");  // true / false
await VCWebNative.readBase64("x.dff");
await VCWebNative.readText("revc.ini");
```

## 存档和数据

- 网页存档在 WebKit 的 OPFS 里，挂在页面的 Emscripten `/vc-assets` 下，原生读不到，只能让页面自己读。
- 游戏里右上角有个「备份存档」按钮：点一下会在页面里跑 JS，只取
  `vc-assets/local/userfiles/**` 和 `vc-assets/local/revc.ini`，落到：

```
Documents/SaveBackups/2026-11-20-013000/
├── manifest.json
└── local/
    ├── revc.ini
    └── userfiles/...
```

  `UIFileSharingEnabled` 已开，可以直接在「文件」App 里把整个 `SaveBackups` 拷走。
- 只能玩着的时候备份（存档在页面自己的存储里，页面没跑就没法读）。
- 导回去（恢复）还没做，见待办。
- 导入的游戏文件在 `Documents/GameFiles`，同样能通过「文件」App 备份。

## 上游

网页版本体是 [Lolendor/reVCDOS](https://github.com/Lolendor/reVCDOS)（DOS.Zone 团队的 HTML5 移植）。仓库里 `dist/` 是前端，`server.py` / `index.php` / Docker 只负责发文件、缓存和存档；游戏素材不在仓库里，运行时从 CDN 拉。

旧 v6 前端（仓库里的版本）把资源铺在 `/vcsky/`、`/vcbr/`，线上 v16 换成了 `?wasm=` 外链 + OPFS 挂载，脚本清单也变了。`scripts/mirror-assets.sh` 只按旧布局抓，没验证过，用之前先对一下。

## 免责

非官方项目，跟 Rockstar Games、Take-Two 没有任何关系。游戏素材版权归原厂，必须自己持有正版。仅供个人学习，不要分发或售卖。

## 待办

- [x] 默认地址换成线上 v16（原 armdev.cn 镜像 403）
- [x] 本地文件改走 `vcweb://` + WKURLSchemeHandler，不用 file://
- [ ] **第一次真正编译**：GitHub Actions 还没跑过，Swift 只做了静态检查
- [ ] 在线版真机验证：WKWebView 里能不能过 OPFS、触屏控件能不能用、能不能出声
- [ ] 离线：本地包要改掉 v16 的 host 跳转，并且得有安全上下文（打算上 127.0.0.1 本地服务）
- [x] 存档备份：游戏里点按钮，把 OPFS 的存档导到 `Documents/SaveBackups/`
- [ ] 存档恢复：把备份写回 OPFS（页面启动前注入，时序还没验证）
- [ ] 手柄支持（GamepadEmulator.js 已有，WKWebView 里要走 Gamepad API，未验证）
