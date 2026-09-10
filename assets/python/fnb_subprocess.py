#!/usr/bin/env python3
"""fnb_subprocess — DownloadEngine Linux subprocess 模式入口。

由 DownloadEngine 作为长驻子进程启动，通过 stdin 接收 JSON 请求、
stdout 返回 JSON 响应，实现与 Dart 的通信。

协议：
  每条请求/响应占一行 JSON（\n 分隔）
  请求: {"function": "...", "args": {...}}
  响应: {"success": true/false, ...}
"""
import json
import os
import sys


def _install_stderr_stdout():
    """将 sys.stdout 永久重定向到 stderr，保护 JSON 行协议。
    
    核心原理：
    - sys.stdout → stderr（所有 print/rich Console 的输出都走 stderr）
    - os.write(1, ...) → 真正的 fd 1（JSON 行协议专用，不经过 sys.stdout）
    
    上游 tkd/xhs 的 rich Console、ColorfulConsole、各种 print()
    都通过 sys.stdout 输出，重定向后全部走 stderr，不干扰 JSON 协议。
    """
    _real_stderr = sys.stderr

    class _StdoutToStderr:
        """永久伪 stdout：所有 write/flush 转发到 stderr。"""
        def write(self, s):
            return _real_stderr.write(s)
        def flush(self):
            return _real_stderr.flush()
        @property
        def encoding(self):
            return "utf-8"
        def fileno(self):
            return 2  # stderr fd
        def isatty(self):
            return False
        def readable(self):
            return False
        def writable(self):
            return True

    sys.stdout = _StdoutToStderr()


def _json_write(line):
    """通过 fd 1 直接写 JSON 行，绕过 sys.stdout。"""
    data = (line + "\n").encode("utf-8")
    os.write(1, data)


# 在模块加载时立即安装 stderr 重定向（保护所有 import 阶段的输出）
_install_stderr_stdout()

# 添加脚本目录到 sys.path
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, SCRIPT_DIR)
# native/bridge 也要加入（fnb_bridge.py 在开发态位于 native/bridge/）
BRIDGE_DIR = os.path.join(os.path.dirname(SCRIPT_DIR), "native", "bridge")
if os.path.isdir(BRIDGE_DIR):
    sys.path.insert(0, BRIDGE_DIR)

import fnb_bridge


def main():
    # 从命令行参数获取 app_data_dir（init 前注入）
    app_data_dir = sys.argv[1] if len(sys.argv) > 1 else ""

    # 初始化引擎（sys.stdout 已永久重定向到 stderr）
    result = fnb_bridge.init(app_data_dir)

    # 输出 init 结果（作为启动握手）—— 通过 fd 1 直接写
    _json_write(result)

    # 主循环：从 stdin 读取请求，处理后输出响应
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            req = json.loads(line)
            function = req.get("function", "")
            args = req.get("args", {})
            args_json = json.dumps(args, ensure_ascii=False)
            resp = fnb_bridge.call(function, args_json)
        except Exception as e:
            resp = json.dumps({"success": False, "message": str(e)})
        _json_write(resp)


if __name__ == "__main__":
    main()
