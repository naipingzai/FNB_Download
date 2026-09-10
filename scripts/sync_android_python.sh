#!/usr/bin/env bash
# 同步 Python 代码到 Android Chaquopy 目录
# 真源: assets/python（tkd/ xhs/ compat/ fnb_native.py + fnb_bridge）
# 目标: android/app/src/main/python
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="assets/python"
DST="android/app/src/main/python"
BRIDGE="native/bridge/fnb_bridge.py"

mkdir -p "$DST"

# 清理旧的包目录
rm -rf "$DST/tkd" "$DST/xhs" "$DST/compat"

# 1) 核心文件
for f in fnb_native.py fnb_bridge.py compat_setup.py; do
    if [ -f "$SRC/$f" ]; then
        cp -v "$SRC/$f" "$DST/$f"
    fi
done

# 2) 原生核心包
for pkg in tkd xhs; do
    if [ -d "$SRC/$pkg" ]; then
        cp -r "$SRC/$pkg" "$DST/$pkg"
        find "$DST/$pkg" -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
        echo "✅ $pkg/ 已同步 ($(find "$DST/$pkg" -name '*.py' | wc -l) 个文件)"
    fi
done

# 3) 兼容 shim（curl_cffi/pydantic/javascript 替身）
if [ -d "$SRC/compat" ]; then
    cp -r "$SRC/compat" "$DST/compat"
    echo "✅ compat/ 已同步"
fi

# 4) 统一调度层
if [ -f "$BRIDGE" ]; then
    cp -v "$BRIDGE" "$DST/fnb_bridge.py"
else
    echo "警告: 未找到 $BRIDGE" >&2
fi

echo "✅ Python 代码已同步到 $DST"
