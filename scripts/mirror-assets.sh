#!/usr/bin/env bash
# 把网页版前端和它依赖的 CDN 资源镜像到本地，做成离线包。
#
# 用法：bash scripts/mirror-assets.sh
# 需要：curl、sha256sum（macOS 上用 shasum -a 256，脚本会自动判断）
#
# ⚠️ 这个脚本按的是仓库里旧 v6 前端的布局（dist/ + cdn.dos.zone/vcsky/sha256sums.txt）。
#    线上 v16 已经换成 /vcsky/release/v16/ + ?wasm= 外链 + OPFS，脚本没验证过，
#    直接跑大概率对不上。离线那一步还没通，见 README「两条路」。
#
# 注意：cdn.dos.zone 上放的是游戏素材，版权归原厂。镜像只给自己离线用，
# 不要打包分发。
set -euo pipefail

cd "$(dirname "$0")/.."

UPSTREAM="${UPSTREAM:-https://github.com/Lolendor/reVCDOS.git}"
DIST_DIR="Web"
CDN_BASE="${CDN_BASE:-https://cdn.dos.zone/vcsky}"

have() { command -v "$1" >/dev/null 2>&1; }
if have sha256sum; then SHA="sha256sum"; elif have shasum; then SHA="shasum -a 256"; else
  echo "没有 sha256sum / shasum，装一个再来" >&2; exit 1
fi

echo "==> 拉前端（dist/）"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
git clone --depth 1 "$UPSTREAM" "$TMP/repo"
mkdir -p "$DIST_DIR"
cp -R "$TMP/repo/dist/." "$DIST_DIR/"
cp "$TMP/repo/LICENSE" "$DIST_DIR/LICENSE" 2>/dev/null || true

echo "==> 取资源清单"
curl -fsSL "$CDN_BASE/sha256sums.txt" -o "$TMP/sums.txt"

echo "==> 下载资源到 $DIST_DIR/assets/"
mkdir -p "$DIST_DIR/assets"
while read -r hash name; do
  [ -z "${name:-}" ] && continue
  out="$DIST_DIR/assets/$name"
  mkdir -p "$(dirname "$out")"
  if [ -f "$out" ] && echo "$hash  $out" | $SHA -c --quiet - 2>/dev/null; then
    continue
  fi
  echo "  $name"
  curl -fsSL "$CDN_BASE/$name" -o "$out"
  echo "$hash  $out" | $SHA -c --quiet -
done < "$TMP/sums.txt"

echo "==> 完成。要不要离线跑，看 Web/index.html 怎么找资源，必要时改 dist/modules 里的 CDN 地址指向 assets/。"
du -sh "$DIST_DIR"
