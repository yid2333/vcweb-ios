import Foundation

/// 存档备份。
///
/// 网页版的存档在页面自己挂的 OPFS 里（Emscripten 的 `/vc-assets`），
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

    /// 跑在页面里的脚本：自己找 OPFS 里放存档的地方，读成 base64。
    ///
    /// 不写死路径：页面挂 OPFS 的方式可能变（`/vc-assets` 在 FS 里，
    /// 落到 OPFS 根下的名字未必一样），所以整棵目录树找一遍，
    /// 只收 `userfiles` 底下的存档和 `revc.ini` / `gta_vc.set` 这类配置，
    /// 游戏数据（几百 MB）一个字节都不碰。
    ///
    /// 找不到时把看过哪些目录一起返回，方便排查。
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

    function isInteresting(path) {
      var lower = path.toLowerCase();
      if (lower.indexOf("userfiles") >= 0) { return true; }
      if (lower.indexOf("save") >= 0 && lower.indexOf("/") >= 0) { return true; }
      var tail = lower.split("/").pop();
      return tail === "revc.ini" || tail === "gta_vc.set" || tail === "gta_vc.set.b";
    }

    var files = [];
    var seen = [];
    var bytesBudget = 64 * 1024 * 1024;

    async function walk(dir, prefix, depth) {
      if (depth > 5) { return; }
      if (seen.length < 300) { seen.push(prefix === "" ? "/" : prefix); }

      var entries = [];
      if (dir.entries) {
        for await (var pair of dir.entries()) { entries.push([pair[0], pair[1]]); }
      } else {
        for await (var name of dir.keys()) { entries.push([name, null]); }
      }

      for (var i = 0; i < entries.length; i++) {
        var name = entries[i][0];
        var handle = entries[i][1];
        var path = prefix === "" ? name : prefix + "/" + name;

        if (handle && handle.kind === "file") {
          if (!isInteresting(path)) { continue; }
          try {
            var blob = await handle.getFile();
            if (blob.size > bytesBudget) { continue; }
            var bytes = new Uint8Array(await blob.arrayBuffer());
            bytesBudget -= blob.size;
            files.push({ path: path, b64: toBase64(bytes) });
          } catch (e) { /* 单个文件读失败不影响别的 */ }
          continue;
        }

        var sub = handle;
        if (!sub) {
          try { sub = await dir.getDirectoryHandle(name); } catch (e) { sub = null; }
        }
        if (sub) { await walk(sub, path, depth + 1); }
      }
    }

    var root = await navigator.storage.getDirectory();
    await walk(root, "", 0);

    var diag = seen.slice(0, 40).join("\\n");

    if (files.length === 0) {
      return {
        ok: false,
        reason: "OPFS 里没找到存档文件",
        diag: "看过的目录：\\n" + diag
      };
    }

    return { ok: true, files: files, diag: "" };
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

            // 页面给的路径只用来拼文件名，绝不让 .. 跑出备份目录。
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
