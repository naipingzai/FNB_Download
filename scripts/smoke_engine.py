#!/usr/bin/env python3
"""引擎冒烟测试：校验 fnb_bridge 初始化与 tkd/xhs 引擎可装配（不发起网络下载）。

用法（开发态）:
    .venv-linux/bin/python scripts/smoke_engine.py

退出码 0 表示初始化与引擎装配成功。
"""
import os
import sys
import tempfile
import traceback

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "native", "bridge"))
sys.path.insert(0, os.path.join(ROOT, "assets", "python"))


def main() -> int:
    import fnb_bridge

    data_dir = tempfile.mkdtemp(prefix="fnb_smoke_")
    init = fnb_bridge.init(data_dir)
    print("init ->", init)
    if '"success":true' not in init.replace(" ", "").replace("'", '"'):
        return 1

    for platform in ("douyin", "xhs"):
        try:
            eng = fnb_bridge._get_engine(platform)
            if eng is None:
                print(f"[FAIL] {platform}: engine is None")
                return 2
            print(f"[OK] {platform} engine: {type(eng).__name__}")
        except Exception:
            print(f"[FAIL] {platform} engine assembly error:")
            traceback.print_exc()
            return 3

    print("SMOKE_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
