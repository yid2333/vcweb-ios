import Foundation

/// 存档备份。
///
/// 网页版的存档在 WebKit 的 OPFS 里（页面自己挂在 Emscripten 的 `/vc-assets`），
/// 原生这边读不到，只能让页面里的 JS 去读，再经由 WebView 传回。
/// 备份出来的目录长这样，能直接从「文件」App 拷走：
///
///   Documents/SaveBackups/2026-11-20-013000/
///     manifest.json
///     local/revc.ini
///     local/userfiles/GTAVCsf1.b
enum SaveBackup {
    /// 备份文件放这儿。
    static func root(in documents: URL) -> URL {
        documents.appendingPathComponent("SaveBackups", isDirectory: true)
    }

    /// 跑在页面里的脚本：把 OPFS 里的存档读成 base64。
    ///
    /// 只取 `vc-assets/local/userfiles` 和 `vc-assets/local/revc.ini`，
    /// 不碰游戏数据（那一堆是几百 MB，备份没意义）。
    static let exportScript = """
    if (!navigator.storage || !navigator.storage.getDirectory) {
      throw new Error("这个 WebView 不支持 OPFS，存不了档");
    }

    function toBase64(bytes) {
      var out = "";
      var chunk = 0x8000;
      for (var i = 0; i < bytes.length; i += chunk) {
        out += String.fromCharCode.apply(null, bytes.subarray(i, i + chunk));
      }
      return btoa(out);
    }

    async function namesOf(dir) {
      var names = [];
      if (dir.keys) {
        for await (var name of dir.keys()) { names.push(name); }
        return names;
      }
      for await (var entry of dir.entries()) { names.push(entry[0]); }
      return names;
    }

    async function walk(dir, prefix, out, depth) {
      if (depth > 6) { return; }
      var names = await namesOf(dir);
      for (var name of names) {
        try {
          var file = await dir.getFileHandle(name);
          var blob = await file.getFile();
          var bytes = new Uint8Array(await blob.arrayBuffer());
          out.push({ path: prefix + name, b64: toBase64(bytes) });
        } catch (e) {
          try {
            var sub = await dir.getDirectoryHandle(name);
            await walk(sub, prefix + name + "/", out, depth + 1);
          } catch (e2) { /* 既不是文件也不是目录，跳过 */ }
        }
      }
    }

    var files = [];
    var root = await navigator.storage.getDirectory();
    var assets;
    try {
      assets = await root.getDirectoryHandle("vc-assets");
    } catch (e) {
      return { ok: false, reason: "OPFS 里还没有 vc-assets，先进一次游戏再来备份" };
    }

    var local = null;
    try { local = await assets.getDirectoryHandle("local"); } catch (e) { local = null; }
    if (local) {
      var userfiles = null;
      try { userfiles = await local.getDirectoryHandle("userfiles"); } catch (e) { userfiles = null; }
      if (userfiles) { await walk(userfiles, "local/userfiles/", files, 0); }
      try {
        var ini = await local.getFileHandle("revc.ini");
        var iniBlob = await ini.getFile();
        var iniBytes = new Uint8Array(await iniBlob.arrayBuffer());
        files.push({ path: "local/revc.ini", b64: toBase64(iniBytes) });
      } catch (e) { /* 没有 ini 也正常 */ }
    }

    return { ok: true, files: files };
    """

    struct Result {
        let url: URL
        let fileCount: Int
        let byteCount: Int
    }

    /// 把从页面拿回来的 { path, b64 } 列表落到磁盘。
    static func write(
        payload: [[String: Any]],
        documents: URL,
        now: Date = Date()
    ) throws -> Result {
        let stamp = Self.formatter.string(from: now)
        let dir = root(in: documents).appendingPathComponent(stamp, isDirectory: true)

        var total = 0
        var manifest: [[String: Any]] = []

        for item in payload {
            guard let rawPath = item["path"] as? String,
                  let b64 = item["b64"] as? String,
                  let data = Data(base64Encoded: b64) else { continue }
            let safe = sanitize(rawPath)
            guard !safe.isEmpty else { continue }

            // 用户名字是备份时的实际路径，只用它拼文件名，绝不让 / 跑出目录。
            let dest = dir.appendingPathComponent(safe)
            let parent = dest.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            try data.write(to: dest, options: .atomic)

            total += data.count
            manifest.append(["path": safe, "bytes": data.count])
        }

        let meta: [String: Any] = [
            "createdAt": ISO8601DateFormatter().string(from: now),
            "fileCount": manifest.count,
            "byteCount": total,
            "files": manifest
        ]
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let metaData = try JSONSerialization.data(
            withJSONObject: meta,
            options: [.prettyPrinted, .sortedKeys]
        )
        try metaData.write(to: dir.appendingPathComponent("manifest.json"), options: .atomic)

        return Result(url: dir, fileCount: manifest.count, byteCount: total)
    }

    /// 所有备份，新的在前。
    static func snapshots(in documents: URL) -> [URL] {
        let base = root(in: documents)
        let items = (try? FileManager.default.contentsOfDirectory(
            at: base,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return items
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    static func delete(_ url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

    // MARK: - 内部

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return f
    }()

    /// 只保留相对路径，去掉开头的 / 和任何 .. 段。
    private static func sanitize(_ path: String) -> String {
        let parts = path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
            .filter { $0 != "." && $0 != ".." }
        return parts.joined(separator: "/")
    }
}
