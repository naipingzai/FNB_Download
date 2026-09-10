#!/usr/bin/env python3
"""用 PyInstaller 打包 Python 引擎为独立可执行文件。"""
import os
import subprocess
import sys
import shutil

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, "assets", "python")
BUILD_DIR = os.path.join(ROOT, "linux", "python_bundle")
ENTRY = os.path.join(ASSETS, "fnb_subprocess.py")

HIDDEN = [
    "fnb_bridge", "fnb_native", "compat_setup",
    "tkd", "tkd.config", "tkd.config.parameter", "tkd.tools", "tkd.custom",
    "tkd.manager", "tkd.interface", "tkd.interface.template",
    "tkd.interface.detail", "tkd.interface.account", "tkd.interface.mix",
    "tkd.interface.comment", "tkd.interface.hot", "tkd.interface.search",
    "tkd.extract", "tkd.downloader", "tkd.link", "tkd.storage", "tkd.record",
    "tkd.module", "tkd.models", "tkd.encrypt",
    "xhs", "xhs.application", "xhs.expansion", "xhs.module",
    "httpx", "httpx._client", "curl_cffi", "curl_cffi.requests",
]

def main():
    if os.path.exists(BUILD_DIR):
        shutil.rmtree(BUILD_DIR)
    os.makedirs(BUILD_DIR, exist_ok=True)

    cmd = [
        sys.executable, "-m", "PyInstaller",
        "--noconfirm", "--onefile", "--name=fnb_engine",
        f"--distpath={os.path.join(BUILD_DIR, 'dist')}",
        f"--workpath={os.path.join(BUILD_DIR, 'work')}",
        f"--specpath={BUILD_DIR}",
        f"--add-data={ASSETS}/tkd:tkd",
        f"--add-data={ASSETS}/xhs:xhs",
        f"--add-data={ASSETS}/fnb_bridge.py:.",
        f"--add-data={ASSETS}/fnb_native.py:.",
        f"--add-data={ASSETS}/compat_setup.py:.",
        # 确保标准库子模块完整打包
        "--collect-submodules=http",
        "--collect-submodules=email",
        "--collect-submodules=xml",
        "--collect-submodules=json",
        "--collect-submodules=encodings",
        # C 扩展模块
        "--collect-all=sqlite3",
        "--hidden-import=_sqlite3",
        "--hidden-import=aiosqlite",
    ]
    for h in HIDDEN:
        cmd.append(f"--hidden-import={h}")
    cmd.append(ENTRY)

    print(f"打包中...")
    r = subprocess.run(cmd, cwd=ROOT)
    if r.returncode != 0:
        print("打包失败")
        return 1

    src = os.path.join(BUILD_DIR, "dist", "fnb_engine")
    dst = os.path.join(BUILD_DIR, "bin", "fnb_engine")
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    shutil.copy2(src, dst)
    os.chmod(dst, 0o755)
    print(f"打包成功: {dst} ({os.path.getsize(dst)/1024/1024:.1f}MB)")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
